package network

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/godbus/dbus/v5"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/errdefs"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/log"
)

const (
	nmAgentManagerPath  = "/org/freedesktop/NetworkManager/AgentManager"
	nmAgentManagerIface = "org.freedesktop.NetworkManager.AgentManager"
	nmSecretAgentIface  = "org.freedesktop.NetworkManager.SecretAgent"
	agentObjectPath     = "/org/freedesktop/NetworkManager/SecretAgent"
	agentIdentifier     = "org.kaskados.NetworkSecretAgent"
)

const (
	nmSecretAgentFlagAllowInteraction = 0x1
	nmSecretAgentFlagRequestNew       = 0x2
	nmSecretAgentFlagOnlySystem       = 0x80000000
)

type SecretAgent struct {
	conn    *dbus.Conn
	objPath dbus.ObjectPath
	id      string
	prompts PromptBroker
	manager *Manager
	backend *NetworkManagerBackend
}

type (
	nmVariantMap map[string]dbus.Variant
	nmSettingMap map[string]nmVariantMap
)

const introspectXML = `
<node>
	<interface name="org.freedesktop.NetworkManager.SecretAgent">
		<method name="GetSecrets">
			<arg type="a{sa{sv}}" name="connection" direction="in"/>
			<arg type="o" name="connection_path" direction="in"/>
			<arg type="s" name="setting_name" direction="in"/>
			<arg type="as" name="hints" direction="in"/>
			<arg type="u" name="flags" direction="in"/>
			<arg type="a{sa{sv}}" name="secrets" direction="out"/>
		</method>
		<method name="DeleteSecrets">
			<arg type="a{sa{sv}}" name="connection" direction="in"/>
			<arg type="o" name="connection_path" direction="in"/>
		</method>
		<method name="DeleteSecrets2">
			<arg type="o" name="connection_path" direction="in"/>
			<arg type="s" name="setting" direction="in"/>
		</method>
		<method name="CancelGetSecrets">
			<arg type="o" name="connection_path" direction="in"/>
			<arg type="s" name="setting_name" direction="in"/>
		</method>
	</interface>
	<interface name="org.freedesktop.DBus.Introspectable">
		<method name="Introspect">
			<arg name="data" type="s" direction="out"/>
		</method>
	</interface>
</node>`

func NewSecretAgent(prompts PromptBroker, manager *Manager, backend *NetworkManagerBackend) (*SecretAgent, error) {
	c, err := dbus.ConnectSystemBus()
	if err != nil {
		return nil, fmt.Errorf("failed to connect to system bus: %w", err)
	}

	sa := &SecretAgent{conn: c, objPath: dbus.ObjectPath(agentObjectPath), id: agentIdentifier, prompts: prompts, manager: manager, backend: backend}
	if err := c.Export(sa, sa.objPath, nmSecretAgentIface); err != nil {
		c.Close()
		return nil, fmt.Errorf("failed to export secret agent: %w", err)
	}
	if err := c.Export(sa, sa.objPath, "org.freedesktop.DBus.Introspectable"); err != nil {
		c.Close()
		return nil, fmt.Errorf("failed to export introspection: %w", err)
	}

	mgr := c.Object("org.freedesktop.NetworkManager", dbus.ObjectPath(nmAgentManagerPath))
	if call := mgr.Call(nmAgentManagerIface+".Register", 0, sa.id); call.Err != nil {
		c.Close()
		return nil, fmt.Errorf("failed to register agent with NetworkManager: %w", call.Err)
	}
	log.Infof("[SecretAgent] Registered KaskadOS Wi-Fi agent (id=%s, path=%s)", sa.id, sa.objPath)
	return sa, nil
}

func (a *SecretAgent) Close() {
	if a.conn == nil {
		return
	}
	mgr := a.conn.Object("org.freedesktop.NetworkManager", dbus.ObjectPath(nmAgentManagerPath))
	mgr.Call(nmAgentManagerIface+".Unregister", 0, a.id)
	a.conn.Close()
}

func (a *SecretAgent) GetSecrets(conn map[string]nmVariantMap, path dbus.ObjectPath, settingName string, hints []string, flags uint32) (nmSettingMap, *dbus.Error) {
	connType, displayName := readConnTypeAndName(conn)
	ssid := readSSID(conn)
	log.Infof("[SecretAgent] GetSecrets: path=%s, type=%s, setting=%s, hints=%v, flags=%d", path, connType, settingName, hints, flags)

	// Regalia is the only KaskadOS VPN frontend. This agent owns only Wi-Fi
	// and 802.1X secrets and never revives NetworkManager's former VPN UI.
	if settingName == "vpn" || connType == "vpn" || connType == "wireguard" {
		return nil, noSecretsError()
	}
	if connType != "802-11-wireless" || (settingName != "802-11-wireless-security" && settingName != "802-1x") {
		return nil, noSecretsError()
	}
	if flags&nmSecretAgentFlagOnlySystem != 0 {
		return nil, noSecretsError()
	}

	connUUID := readConnectionString(conn, "uuid")
	if a.backend != nil {
		a.backend.stateMutex.RLock()
		isConnecting := a.backend.state.IsConnecting
		connectingSSID := a.backend.state.ConnectingSSID
		a.backend.stateMutex.RUnlock()
		if isConnecting && connectingSSID != ssid {
			log.Infof("[SecretAgent] Ignoring request for SSID %q while connecting to %q", ssid, connectingSSID)
			return nil, noSecretsError()
		}
	}

	fields, handled := wifiFieldsNeeded(settingName, hints, conn)
	if !handled {
		return nil, noSecretsError()
	}
	requestNew := flags&nmSecretAgentFlagRequestNew != 0
	if requestNew {
		if a.backend != nil {
			a.backend.clearCachedWiFiSecret(connUUID)
		}
	} else {
		if secretOut := a.trySecretService(connUUID, settingName, fields); secretOut != nil {
			return secretOut, nil
		}
		if a.backend != nil {
			if cached := a.backend.lookupCachedWiFiSecret(connUUID, settingName); cached != nil {
				return buildWiFiSecretsResponse(settingName, cached), nil
			}
		}
	}

	if flags&nmSecretAgentFlagAllowInteraction == 0 {
		return nil, noSecretsError()
	}
	if a.prompts == nil {
		return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.Failed", nil)
	}
	reason := reasonFromFlags(flags)
	if a.manager != nil && a.manager.WasRecentlyFailed(ssid) {
		reason = "wrong-password"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	token, err := a.prompts.Ask(ctx, PromptRequest{
		Name: displayName, SSID: ssid, ConnType: connType, SettingName: settingName,
		Fields: fields, FieldsInfo: buildFieldsInfo(fields), Hints: hints, Reason: reason,
		ConnectionId: readConnectionString(conn, "id"), ConnectionUuid: connUUID, ConnectionPath: string(path),
	})
	if err != nil {
		return nil, dbus.MakeFailedError(err)
	}
	reply, err := a.prompts.Wait(ctx, token)
	if err != nil {
		a.handleCancelledPrompt(connUUID, connType)
		if reply.Cancel || errors.Is(err, errdefs.ErrSecretPromptCancelled) {
			return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.UserCanceled", nil)
		}
		return nil, dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.Failed", nil)
	}

	out := buildWiFiSecretsResponse(settingName, reply.Secrets)
	if settingName == "802-1x" {
		if identity := reply.Secrets["identity"]; identity != "" {
			a.save8021xIdentity(path, identity)
		}
	}
	if a.backend != nil {
		a.backend.cacheWiFiSecret(connUUID, ssid, settingName, reply.Secrets)
	}
	return out, nil
}

func (a *SecretAgent) handleCancelledPrompt(connUUID, connType string) {
	if a.backend == nil {
		return
	}
	a.backend.stateMutex.Lock()
	wasConnecting := a.backend.state.IsConnecting
	connectingSSID := a.backend.state.ConnectingSSID
	preExisting := a.backend.state.ConnectingPreExisting
	if wasConnecting {
		a.backend.state.IsConnecting = false
		a.backend.state.ConnectingSSID = ""
	}
	a.backend.stateMutex.Unlock()
	a.backend.clearCachedWiFiSecret(connUUID)

	if wasConnecting && connectingSSID != "" && connType == "802-11-wireless" && !preExisting {
		if err := a.backend.ForgetWiFiNetwork(connectingSSID); err != nil {
			log.Warnf("[SecretAgent] Failed to remove cancelled Wi-Fi profile %q: %v", connectingSSID, err)
		}
	}
	if wasConnecting && a.backend.onStateChange != nil {
		a.backend.onStateChange()
	}
}

func (a *SecretAgent) DeleteSecrets(conn map[string]nmVariantMap, path dbus.ObjectPath) *dbus.Error {
	log.Infof("[SecretAgent] DeleteSecrets: path=%s, SSID=%s", path, readSSID(conn))
	return nil
}

func (a *SecretAgent) DeleteSecrets2(path dbus.ObjectPath, setting string) *dbus.Error {
	log.Infof("[SecretAgent] DeleteSecrets2: path=%s, setting=%s", path, setting)
	return nil
}

func (a *SecretAgent) CancelGetSecrets(path dbus.ObjectPath, settingName string) *dbus.Error {
	if a.prompts != nil {
		if err := a.prompts.Cancel(string(path), settingName); err != nil {
			log.Warnf("[SecretAgent] Failed to cancel prompt: %v", err)
		}
	}
	return nil
}

func (a *SecretAgent) Introspect() (string, *dbus.Error) { return introspectXML, nil }

func (a *SecretAgent) save8021xIdentity(path dbus.ObjectPath, identity string) {
	if a.conn == nil {
		return
	}
	connObj := a.conn.Object("org.freedesktop.NetworkManager", path)
	var existing map[string]map[string]dbus.Variant
	if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.GetSettings", 0).Store(&existing); err != nil {
		log.Warnf("[SecretAgent] Failed to get settings for identity save: %v", err)
		return
	}
	settings := make(map[string]map[string]dbus.Variant)
	if connection, ok := existing["connection"]; ok {
		settings["connection"] = connection
	}
	dot1x := existing["802-1x"]
	if dot1x == nil {
		dot1x = make(map[string]dbus.Variant)
	}
	dot1x["identity"] = dbus.MakeVariant(identity)
	settings["802-1x"] = dot1x
	var result map[string]dbus.Variant
	if err := connObj.Call("org.freedesktop.NetworkManager.Settings.Connection.Update2", 0, settings, uint32(0x1), map[string]dbus.Variant{}).Store(&result); err != nil {
		log.Warnf("[SecretAgent] Failed to save 802.1X identity: %v", err)
	}
}

func noSecretsError() *dbus.Error {
	return dbus.NewError("org.freedesktop.NetworkManager.SecretAgent.Error.NoSecrets", nil)
}

func readSSID(conn map[string]nmVariantMap) string {
	if wireless, ok := conn["802-11-wireless"]; ok {
		if value, ok := wireless["ssid"]; ok {
			switch ssid := value.Value().(type) {
			case []byte:
				return string(ssid)
			case string:
				return ssid
			}
		}
	}
	return ""
}

func readConnectionString(conn map[string]nmVariantMap, key string) string {
	if connection, ok := conn["connection"]; ok {
		if value, ok := connection[key]; ok {
			if text, ok := value.Value().(string); ok {
				return text
			}
		}
	}
	return ""
}

func readConnTypeAndName(conn map[string]nmVariantMap) (string, string) {
	connType := readConnectionString(conn, "type")
	name := readConnectionString(conn, "id")
	if name == "" && connType == "802-11-wireless" {
		name = readSSID(conn)
	}
	return connType, name
}

func wifiFieldsNeeded(setting string, hints []string, conn map[string]nmVariantMap) ([]string, bool) {
	switch setting {
	case "802-11-wireless-security":
		return []string{"psk"}, true
	case "802-1x":
		if len(hints) > 0 {
			return hints, true
		}
		return infer8021xFields(conn), true
	default:
		return nil, false
	}
}

func infer8021xFields(conn map[string]nmVariantMap) []string {
	dot1x, ok := conn["802-1x"]
	if !ok {
		return []string{"identity", "password"}
	}
	fields := make([]string, 0, 2)
	if value, ok := dot1x["identity"]; !ok {
		fields = append(fields, "identity")
	} else if identity, ok := value.Value().(string); !ok || identity == "" {
		fields = append(fields, "identity")
	}
	if value, ok := dot1x["eap"]; ok {
		if methods, ok := value.Value().([]string); ok && len(methods) > 0 && methods[0] == "tls" {
			return append(fields, "private-key-password")
		}
	}
	return append(fields, "password")
}

func buildFieldsInfo(fields []string) []FieldInfo {
	result := make([]FieldInfo, 0, len(fields))
	for _, field := range fields {
		info := FieldInfo{Name: field, Label: field, IsSecret: true}
		switch field {
		case "identity":
			info.Label, info.IsSecret = "Username", false
		case "psk", "password":
			info.Label = "Password"
		case "private-key-password":
			info.Label = "Private Key Password"
		case "phase2-private-key-password":
			info.Label = "Phase 2 Private Key Password"
		case "pin":
			info.Label = "PIN"
		}
		result = append(result, info)
	}
	return result
}

func reasonFromFlags(flags uint32) string {
	if flags&nmSecretAgentFlagRequestNew != 0 {
		return "wrong-password"
	}
	if flags&0x4 != 0 {
		return "user-requested"
	}
	return "required"
}

func buildWiFiSecretsResponse(settingName string, secrets map[string]string) nmSettingMap {
	section := nmVariantMap{}
	for key, value := range secrets {
		if settingName == "802-1x" {
			switch key {
			case "password", "private-key-password", "phase2-private-key-password", "pin":
				section[key] = dbus.MakeVariant(value)
			}
			continue
		}
		section[key] = dbus.MakeVariant(value)
	}
	return nmSettingMap{settingName: section}
}
