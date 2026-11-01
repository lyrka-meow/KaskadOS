package network

import (
	"testing"

	"github.com/godbus/dbus/v5"
	"github.com/stretchr/testify/assert"
)

func wifiTestConnection() map[string]nmVariantMap {
	return map[string]nmVariantMap{
		"connection": {
			"id":   dbus.MakeVariant("TestWiFi"),
			"uuid": dbus.MakeVariant("wifi-uuid"),
			"type": dbus.MakeVariant("802-11-wireless"),
		},
		"802-11-wireless": {"ssid": dbus.MakeVariant([]byte("TestSSID"))},
	}
}

func TestSecretAgentOnlySystemFlag(t *testing.T) {
	agent := &SecretAgent{}
	_, err := agent.GetSecrets(wifiTestConnection(), "/test/path", "802-11-wireless-security", nil, nmSecretAgentFlagOnlySystem)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "NoSecrets")
}

func TestSecretAgentNoInteractionFlag(t *testing.T) {
	agent := &SecretAgent{}
	_, err := agent.GetSecrets(wifiTestConnection(), "/test/path", "802-11-wireless-security", nil, 0)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "NoSecrets")
}

func TestSecretAgentRejectsNetworkManagerVPN(t *testing.T) {
	agent := &SecretAgent{}
	conn := map[string]nmVariantMap{
		"connection": {
			"id":   dbus.MakeVariant("Legacy VPN"),
			"type": dbus.MakeVariant("vpn"),
		},
	}
	_, err := agent.GetSecrets(conn, "/test/vpn", "vpn", []string{"password"}, nmSecretAgentFlagAllowInteraction)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "NoSecrets")
}

func TestWiFiFieldsNeeded(t *testing.T) {
	fields, handled := wifiFieldsNeeded("802-11-wireless-security", nil, wifiTestConnection())
	assert.True(t, handled)
	assert.Equal(t, []string{"psk"}, fields)

	fields, handled = wifiFieldsNeeded("vpn", []string{"password"}, wifiTestConnection())
	assert.False(t, handled)
	assert.Nil(t, fields)
}

func TestInfer8021xFields(t *testing.T) {
	conn := wifiTestConnection()
	conn["802-1x"] = nmVariantMap{"eap": dbus.MakeVariant([]string{"peap"})}
	assert.Equal(t, []string{"identity", "password"}, infer8021xFields(conn))

	conn["802-1x"] = nmVariantMap{
		"identity": dbus.MakeVariant("alice"),
		"eap":      dbus.MakeVariant([]string{"tls"}),
	}
	assert.Equal(t, []string{"private-key-password"}, infer8021xFields(conn))
}

func TestBuildWiFiSecretsResponse(t *testing.T) {
	t.Run("wpa-psk", func(t *testing.T) {
		out := buildWiFiSecretsResponse("802-11-wireless-security", map[string]string{"psk": "hunter2"})
		assert.Equal(t, "hunter2", out["802-11-wireless-security"]["psk"].Value())
	})

	t.Run("802-1x excludes identity", func(t *testing.T) {
		out := buildWiFiSecretsResponse("802-1x", map[string]string{"identity": "john", "password": "hunter2"})
		assert.Equal(t, "hunter2", out["802-1x"]["password"].Value())
		_, hasIdentity := out["802-1x"]["identity"]
		assert.False(t, hasIdentity)
	})
}

func TestWiFiSecretCache(t *testing.T) {
	b := &NetworkManagerBackend{}
	b.cacheWiFiSecret("uuid-1", "HomeNet", "802-11-wireless-security", map[string]string{"psk": "hunter2"})
	assert.Equal(t, map[string]string{"psk": "hunter2"}, b.lookupCachedWiFiSecret("uuid-1", "802-11-wireless-security"))
	assert.Nil(t, b.lookupCachedWiFiSecret("uuid-2", "802-11-wireless-security"))
	b.clearCachedWiFiSecretBySSID("HomeNet")
	assert.Nil(t, b.lookupCachedWiFiSecret("uuid-1", "802-11-wireless-security"))
}

func TestNmVariantMap(t *testing.T) {
	settingMap := nmSettingMap{"test-setting": {"test-key": dbus.MakeVariant("test-value")}}
	assert.Equal(t, "test-value", settingMap["test-setting"]["test-key"].Value())
}
