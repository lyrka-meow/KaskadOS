package network

import (
	"fmt"
	"os"

	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/log"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/models"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/third_party/kaskadgo/ipc/params"
)

func HandleRequest(conn *models.Conn, req models.Request, manager *Manager) {
	switch req.Method {
	case "network.getState":
		handleGetState(conn, req, manager)
	case "network.wifi.scan":
		handleScanWiFi(conn, req, manager)
	case "network.wifi.networks":
		handleGetWiFiNetworks(conn, req, manager)
	case "network.wifi.connect":
		handleConnectWiFi(conn, req, manager)
	case "network.wifi.disconnect":
		handleDisconnectWiFi(conn, req, manager)
	case "network.wifi.forget":
		handleForgetWiFi(conn, req, manager)
	case "network.wifi.toggle":
		handleToggleWiFi(conn, req, manager)
	case "network.wifi.enable":
		handleEnableWiFi(conn, req, manager)
	case "network.wifi.disable":
		handleDisableWiFi(conn, req, manager)
	case "network.ethernet.connect.config":
		handleConnectEthernetSpecificConfig(conn, req, manager)
	case "network.ethernet.connect":
		handleConnectEthernet(conn, req, manager)
	case "network.ethernet.disconnect":
		handleDisconnectEthernet(conn, req, manager)
	case "network.ethernet.sharing.set":
		handleSetEthernetSharing(conn, req, manager)
	case "network.preference.set":
		handleSetPreference(conn, req, manager)
	case "network.info":
		handleGetNetworkInfo(conn, req, manager)
	case "network.qrcode":
		handleGetNetworkQRCode(conn, req, manager)
	case "network.qrcode-content":
		handleGetNetworkQRCodeContent(conn, req, manager)
	case "network.delete-qrcode":
		handleDeleteQRCode(conn, req, manager)
	case "network.ethernet.info":
		handleGetWiredNetworkInfo(conn, req, manager)
	case "network.ethernet.profile.get":
		handleGetWiredProfile(conn, req, manager)
	case "network.ethernet.profile.apply":
		handleApplyWiredProfile(conn, req, manager)
	case "network.ethernet.profile.confirm":
		handleConfirmWiredProfile(conn, req, manager)
	case "network.ethernet.profile.rollback":
		handleRollbackWiredProfile(conn, req, manager)
	case "network.subscribe":
		handleSubscribe(conn, req, manager)
	case "network.credentials.submit":
		handleCredentialsSubmit(conn, req, manager)
	case "network.credentials.cancel":
		handleCredentialsCancel(conn, req, manager)
	case "network.wifi.setAutoconnect":
		handleSetWiFiAutoconnect(conn, req, manager)
	case "network.hotspot.configure":
		handleConfigureHotspot(conn, req, manager)
	case "network.hotspot.start":
		handleStartHotspot(conn, req, manager)
	case "network.hotspot.stop":
		handleStopHotspot(conn, req, manager)
	case "network.hotspot.getSecrets":
		handleGetHotspotSecrets(conn, req, manager)
	case "network.hotspot.clients":
		handleListHotspotClients(conn, req, manager)
	case "network.hotspot.client.disconnect":
		handleDisconnectHotspotClient(conn, req, manager)
	case "network.hotspot.client.block":
		handleSetHotspotClientBlocked(conn, req, manager, true)
	case "network.hotspot.client.unblock":
		handleSetHotspotClientBlocked(conn, req, manager, false)
	case "network.hotspot.client.setName":
		handleSetHotspotClientName(conn, req, manager)
	case "network.hotspot.analytics.get":
		handleGetHotspotAnalytics(conn, req, manager)
	case "network.hotspot.analytics.setEnabled":
		handleSetHotspotAnalyticsEnabled(conn, req, manager)
	case "network.hotspot.analytics.deleteSession":
		handleDeleteHotspotAnalyticsSession(conn, req, manager)
	case "network.hotspot.analytics.clearCurrent":
		handleClearCurrentHotspotAnalytics(conn, req, manager)
	case "network.hotspot.analytics.clearDevice":
		handleClearHotspotAnalyticsDevice(conn, req, manager)
	case "network.hotspot.analytics.clearAll":
		handleClearAllHotspotAnalytics(conn, req, manager)
	default:
		models.RespondError(conn, req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleSetEthernetSharing(conn *models.Conn, req models.Request, manager *Manager) {
	enabled, ok := models.Get[bool](req, "enabled")
	if !ok {
		models.RespondError(conn, req.ID, "missing or invalid enabled parameter")
		return
	}
	device := params.StringOpt(req.Params, "device", "")
	useVPN, _ := models.Get[bool](req, "useVPN")
	if err := manager.SetEthernetSharing(enabled, device, useVPN); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "Ethernet sharing state updated"})
}

func handleCredentialsSubmit(conn *models.Conn, req models.Request, manager *Manager) {
	token, err := params.String(req.Params, "token")
	if err != nil {
		log.Warnf("handleCredentialsSubmit: missing or invalid token parameter")
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	secrets, err := params.StringMap(req.Params, "secrets")
	if err != nil {
		log.Warnf("handleCredentialsSubmit: missing or invalid secrets parameter")
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	save := params.BoolOpt(req.Params, "save", true)

	if err := manager.SubmitCredentials(token, secrets, save); err != nil {
		log.Warnf("handleCredentialsSubmit: failed to submit credentials: %v", err)
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	log.Infof("handleCredentialsSubmit: credentials submitted successfully")
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "credentials submitted"})
}

func handleCredentialsCancel(conn *models.Conn, req models.Request, manager *Manager) {
	token, err := params.String(req.Params, "token")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	if err := manager.CancelCredentials(token); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "credentials cancelled"})
}

func handleGetState(conn *models.Conn, req models.Request, manager *Manager) {
	models.Respond(conn, req.ID, manager.GetState())
}

func handleScanWiFi(conn *models.Conn, req models.Request, manager *Manager) {
	device := params.StringOpt(req.Params, "device", "")
	var err error
	if device != "" {
		err = manager.ScanWiFiDevice(device)
	} else {
		err = manager.ScanWiFi()
	}
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "scanning"})
}

func handleGetWiFiNetworks(conn *models.Conn, req models.Request, manager *Manager) {
	models.Respond(conn, req.ID, manager.GetWiFiNetworks())
}

func handleConnectWiFi(conn *models.Conn, req models.Request, manager *Manager) {
	ssid, err := params.String(req.Params, "ssid")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	var connReq ConnectionRequest
	connReq.SSID = ssid
	connReq.Password = params.StringOpt(req.Params, "password", "")
	connReq.Username = params.StringOpt(req.Params, "username", "")
	connReq.Device = params.StringOpt(req.Params, "device", "")

	if interactive, ok := models.Get[bool](req, "interactive"); ok {
		connReq.Interactive = interactive
	} else {
		state := manager.GetState()
		alreadyConnected := state.WiFiConnected && state.WiFiSSID == ssid

		if alreadyConnected && connReq.Device == "" {
			connReq.Interactive = false
		} else {
			networkInfo, err := manager.GetNetworkInfo(ssid)
			isSaved := err == nil && networkInfo.Saved

			if isSaved {
				connReq.Interactive = false
			} else if err == nil && networkInfo.Secured && connReq.Password == "" && connReq.Username == "" {
				connReq.Interactive = true
			}
		}
	}

	connReq.AnonymousIdentity = params.StringOpt(req.Params, "anonymousIdentity", "")
	connReq.DomainSuffixMatch = params.StringOpt(req.Params, "domainSuffixMatch", "")
	connReq.EAPMethod = params.StringOpt(req.Params, "eapMethod", "")
	connReq.Phase2Auth = params.StringOpt(req.Params, "phase2Auth", "")
	connReq.CACertPath = params.StringOpt(req.Params, "caCertPath", "")
	connReq.ClientCertPath = params.StringOpt(req.Params, "clientCertPath", "")
	connReq.PrivateKeyPath = params.StringOpt(req.Params, "privateKeyPath", "")

	if useSystemCACerts, ok := models.Get[bool](req, "useSystemCACerts"); ok {
		connReq.UseSystemCACerts = &useSystemCACerts
	}

	if err := manager.ConnectWiFi(connReq); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "connecting"})
}

func handleDisconnectWiFi(conn *models.Conn, req models.Request, manager *Manager) {
	device := params.StringOpt(req.Params, "device", "")
	var err error
	if device != "" {
		err = manager.DisconnectWiFiDevice(device)
	} else {
		err = manager.DisconnectWiFi()
	}
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "disconnected"})
}

func handleForgetWiFi(conn *models.Conn, req models.Request, manager *Manager) {
	ssid, err := params.String(req.Params, "ssid")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	if err := manager.ForgetWiFiNetwork(ssid); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "forgotten"})
}

func handleToggleWiFi(conn *models.Conn, req models.Request, manager *Manager) {
	if err := manager.ToggleWiFi(); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	state := manager.GetState()
	models.Respond(conn, req.ID, map[string]bool{"enabled": state.WiFiEnabled})
}

func handleEnableWiFi(conn *models.Conn, req models.Request, manager *Manager) {
	if err := manager.EnableWiFi(); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, map[string]bool{"enabled": true})
}

func handleDisableWiFi(conn *models.Conn, req models.Request, manager *Manager) {
	if err := manager.DisableWiFi(); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, map[string]bool{"enabled": false})
}

func handleConnectEthernetSpecificConfig(conn *models.Conn, req models.Request, manager *Manager) {
	uuid, err := params.String(req.Params, "uuid")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	if err := manager.activateConnection(uuid); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "connecting"})
}

func handleConnectEthernet(conn *models.Conn, req models.Request, manager *Manager) {
	if err := manager.ConnectEthernet(); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "connecting"})
}

func handleDisconnectEthernet(conn *models.Conn, req models.Request, manager *Manager) {
	device := params.StringOpt(req.Params, "device", "")
	var err error
	if device != "" {
		err = manager.DisconnectEthernetDevice(device)
	} else {
		err = manager.DisconnectEthernet()
	}
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "disconnected"})
}

func handleSetPreference(conn *models.Conn, req models.Request, manager *Manager) {
	preference, err := params.String(req.Params, "preference")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	if err := manager.SetConnectionPreference(ConnectionPreference(preference)); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, map[string]string{"preference": preference})
}

func handleGetNetworkInfo(conn *models.Conn, req models.Request, manager *Manager) {
	ssid, err := params.String(req.Params, "ssid")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	network, err := manager.GetNetworkInfoDetailed(ssid)
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, network)
}

func handleGetNetworkQRCode(conn *models.Conn, req models.Request, manager *Manager) {
	ssid, err := params.String(req.Params, "ssid")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	content, err := manager.GetNetworkQRCode(ssid)
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, content)
}

func handleGetNetworkQRCodeContent(conn *models.Conn, req models.Request, manager *Manager) {
	ssid, err := params.String(req.Params, "ssid")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	content, err := manager.GetWiFiQRContent(ssid)
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, content)
}

func handleDeleteQRCode(conn *models.Conn, req models.Request, _ *Manager) {
	path, err := params.String(req.Params, "path")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	if !isValidQRCodePath(path) {
		models.RespondError(conn, req.ID, "invalid QR code path")
		return
	}

	if err := os.Remove(path); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "QR code file deleted"})
}

func handleGetWiredNetworkInfo(conn *models.Conn, req models.Request, manager *Manager) {
	uuid, err := params.String(req.Params, "uuid")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	network, err := manager.GetWiredNetworkInfoDetailed(uuid)
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, network)
}

func handleGetWiredProfile(conn *models.Conn, req models.Request, manager *Manager) {
	uuid, err := params.String(req.Params, "uuid")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	profile, err := manager.GetWiredProfile(uuid)
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, profile)
}

func handleApplyWiredProfile(conn *models.Conn, req models.Request, manager *Manager) {
	metric := params.IntOpt(req.Params, "metric", 100)
	rollbackSeconds := params.IntOpt(req.Params, "rollbackSeconds", 60)
	if rollbackSeconds < 30 || rollbackSeconds > 300 {
		models.RespondError(conn, req.ID, "время отката должно быть от 30 до 300 секунд")
		return
	}
	result, err := manager.ApplyWiredProfile(WiredProfileUpdate{
		UUID:             params.StringOpt(req.Params, "uuid", ""),
		MACMode:          params.StringOpt(req.Params, "macMode", "hardware"),
		CustomMAC:        params.StringOpt(req.Params, "customMac", ""),
		DefaultRouteMode: params.StringOpt(req.Params, "defaultRouteMode", "auto"),
		Gateway:          params.StringOpt(req.Params, "gateway", ""),
		Metric:           int64(metric),
		RollbackSeconds:  uint32(rollbackSeconds),
	})
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, result)
}

func handleConfirmWiredProfile(conn *models.Conn, req models.Request, manager *Manager) {
	token, err := params.String(req.Params, "checkpointToken")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	if err := manager.ConfirmWiredProfile(token); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "настройки подтверждены"})
}

func handleRollbackWiredProfile(conn *models.Conn, req models.Request, manager *Manager) {
	token, err := params.String(req.Params, "checkpointToken")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	if err := manager.RollbackWiredProfile(token); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "предыдущие настройки восстановлены"})
}

func handleSubscribe(conn *models.Conn, req models.Request, manager *Manager) {
	clientID := fmt.Sprintf("client-%p", conn)
	stateChan := manager.Subscribe(clientID)
	defer manager.Unsubscribe(clientID)

	initialState := manager.GetState()
	event := NetworkEvent{
		Type: EventStateChanged,
		Data: initialState,
	}
	if err := conn.WriteResponse(models.Response[NetworkEvent]{
		ID:     req.ID,
		Result: &event,
	}); err != nil {
		return
	}

	for state := range stateChan {
		event := NetworkEvent{
			Type: EventStateChanged,
			Data: state,
		}
		if err := conn.WriteResponse(models.Response[NetworkEvent]{
			Result: &event,
		}); err != nil {
			return
		}
	}
}

func handleSetWiFiAutoconnect(conn *models.Conn, req models.Request, manager *Manager) {
	ssid, err := params.String(req.Params, "ssid")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	autoconnect, err := params.Bool(req.Params, "autoconnect")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	if err := manager.SetWiFiAutoconnect(ssid, autoconnect); err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to set autoconnect: %v", err))
		return
	}

	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "autoconnect updated"})
}

func handleConfigureHotspot(conn *models.Conn, req models.Request, manager *Manager) {
	ssid, err := params.String(req.Params, "ssid")
	if err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	hotspotReq := HotspotRequest{
		SSID:          ssid,
		Password:      params.StringOpt(req.Params, "password", ""),
		Device:        params.StringOpt(req.Params, "device", ""),
		Band:          params.StringOpt(req.Params, "band", ""),
		Compatibility: params.BoolOpt(req.Params, "compatibility", false),
	}

	if err := manager.ConfigureHotspot(hotspotReq); err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to configure hotspot: %v", err))
		return
	}

	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "hotspot configured"})
}

func handleStartHotspot(conn *models.Conn, req models.Request, manager *Manager) {
	if err := manager.StartHotspot(); err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to start hotspot: %v", err))
		return
	}

	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "hotspot started"})
}

func handleStopHotspot(conn *models.Conn, req models.Request, manager *Manager) {
	if err := manager.StopHotspot(); err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to stop hotspot: %v", err))
		return
	}

	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "hotspot stopped"})
}

func handleGetHotspotSecrets(conn *models.Conn, req models.Request, manager *Manager) {
	password, err := manager.GetHotspotSecrets()
	if err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to get hotspot secrets: %v", err))
		return
	}

	models.Respond(conn, req.ID, map[string]string{"password": password})
}

func handleListHotspotClients(conn *models.Conn, req models.Request, manager *Manager) {
	clients, blocked, err := manager.ListHotspotClients()
	if err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to list hotspot clients: %v", err))
		return
	}
	models.Respond(conn, req.ID, map[string]any{"clients": clients, "blocked": blocked})
}

func hotspotClientMAC(req models.Request) (string, error) {
	return params.String(req.Params, "mac")
}

func handleDisconnectHotspotClient(conn *models.Conn, req models.Request, manager *Manager) {
	mac, err := hotspotClientMAC(req)
	if err == nil {
		err = manager.DisconnectHotspotClient(mac)
	}
	if err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to disconnect hotspot client: %v", err))
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "hotspot client disconnected"})
}

func handleSetHotspotClientBlocked(conn *models.Conn, req models.Request, manager *Manager, blocked bool) {
	mac, err := hotspotClientMAC(req)
	if err == nil {
		err = manager.SetHotspotClientBlocked(mac, blocked)
	}
	if err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to change hotspot client block: %v", err))
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "hotspot client block updated"})
}

func handleSetHotspotClientName(conn *models.Conn, req models.Request, manager *Manager) {
	mac, err := hotspotClientMAC(req)
	if err == nil {
		name := params.StringOpt(req.Params, "name", "")
		err = manager.SetHotspotClientName(mac, name)
	}
	if err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to save hotspot client name: %v", err))
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "hotspot client name saved"})
}

func handleGetHotspotAnalytics(conn *models.Conn, req models.Request, manager *Manager) {
	analytics, err := manager.GetHotspotAnalytics()
	if err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to read hotspot analytics: %v", err))
		return
	}
	models.Respond(conn, req.ID, analytics)
}

func handleSetHotspotAnalyticsEnabled(conn *models.Conn, req models.Request, manager *Manager) {
	enabled := params.BoolOpt(req.Params, "enabled", false)
	if err := manager.SetHotspotAnalyticsEnabled(enabled); err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to change hotspot analytics: %v", err))
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "hotspot analytics updated"})
}

func handleDeleteHotspotAnalyticsSession(conn *models.Conn, req models.Request, manager *Manager) {
	mac, err := hotspotClientMAC(req)
	if err == nil {
		var sessionID string
		sessionID, err = params.String(req.Params, "sessionId")
		if err == nil {
			err = manager.DeleteHotspotAnalyticsSession(mac, sessionID)
		}
	}
	if err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to delete hotspot session: %v", err))
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "hotspot session deleted"})
}

func handleClearCurrentHotspotAnalytics(conn *models.Conn, req models.Request, manager *Manager) {
	mac, err := hotspotClientMAC(req)
	if err == nil {
		err = manager.ClearCurrentHotspotAnalytics(mac)
	}
	if err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to clear current hotspot session: %v", err))
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "current hotspot session cleared"})
}

func handleClearHotspotAnalyticsDevice(conn *models.Conn, req models.Request, manager *Manager) {
	mac, err := hotspotClientMAC(req)
	if err == nil {
		err = manager.ClearHotspotAnalyticsDevice(mac)
	}
	if err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to clear hotspot device analytics: %v", err))
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "hotspot device analytics cleared"})
}

func handleClearAllHotspotAnalytics(conn *models.Conn, req models.Request, manager *Manager) {
	if err := manager.ClearAllHotspotAnalytics(); err != nil {
		models.RespondError(conn, req.ID, fmt.Sprintf("failed to clear hotspot analytics: %v", err))
		return
	}
	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "hotspot analytics cleared"})
}
