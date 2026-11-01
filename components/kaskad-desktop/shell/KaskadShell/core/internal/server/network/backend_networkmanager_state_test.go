package network

import (
	"errors"
	"testing"

	"github.com/Wifx/gonetworkmanager/v2"
	"github.com/godbus/dbus/v5"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/errdefs"
	mock_gonetworkmanager "github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNetworkManagerBackend_UpdatePrimaryConnection(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	mockNM.EXPECT().GetPropertyPrimaryConnection().Return(nil, nil)
	mockNM.EXPECT().GetPropertyConnectivity().Return(gonetworkmanager.NmConnectivityNone, nil)

	err = backend.updatePrimaryConnection()
	assert.NoError(t, err)
	assert.Equal(t, StatusDisconnected, backend.state.NetworkStatus)
	assert.Equal(t, "none", backend.state.Connectivity)
}

func TestNetworkManagerBackend_PrimaryWiFiWinsOverAttachedCable(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	primary := mock_gonetworkmanager.NewMockActiveConnection(t)
	device := mock_gonetworkmanager.NewMockDevice(t)
	backend, err := NewNetworkManagerBackend(mockNM)
	require.NoError(t, err)
	backend.state.EthernetConnected = true
	backend.state.NetworkStatus = StatusEthernet
	mockNM.EXPECT().GetPropertyConnectivity().Return(gonetworkmanager.NmConnectivityLimited, nil)
	mockNM.EXPECT().GetPropertyPrimaryConnection().Return(primary, nil)
	primary.EXPECT().GetPath().Return(dbus.ObjectPath("/active/wifi"))
	primary.EXPECT().GetPropertyType().Return("802-11-wireless", nil)
	primary.EXPECT().GetPropertyID().Return("Phone uplink", nil)
	primary.EXPECT().GetPropertyDevices().Return([]gonetworkmanager.Device{device}, nil)
	device.EXPECT().GetPropertyInterface().Return("wlan0", nil)
	require.NoError(t, backend.updatePrimaryConnection())
	assert.Equal(t, StatusWiFi, backend.state.NetworkStatus)
	assert.Equal(t, "802-11-wireless", backend.state.PrimaryConnectionType)
	assert.Equal(t, "Phone uplink", backend.state.PrimaryConnectionName)
	assert.Equal(t, "wlan0", backend.state.PrimaryDevice)
	assert.Equal(t, "limited", backend.state.Connectivity)
}

func TestNetworkManagerBackend_FailedPrimaryReadClearsStaleRoute(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	backend, err := NewNetworkManagerBackend(mockNM)
	require.NoError(t, err)
	backend.state.NetworkStatus = StatusEthernet
	backend.state.PrimaryConnectionName = "Old route"
	backend.state.PrimaryDevice = "eth0"
	backend.state.PrimaryConnectionType = "802-3-ethernet"
	backend.state.Connectivity = "full"
	mockNM.EXPECT().GetPropertyConnectivity().Return(gonetworkmanager.NmConnectivityUnknown, errors.New("unavailable"))
	mockNM.EXPECT().GetPropertyPrimaryConnection().Return(nil, errors.New("unavailable"))
	require.Error(t, backend.updatePrimaryConnection())
	assert.Equal(t, StatusDisconnected, backend.state.NetworkStatus)
	assert.Empty(t, backend.state.PrimaryConnectionName)
	assert.Empty(t, backend.state.PrimaryConnectionType)
	assert.Empty(t, backend.state.PrimaryDevice)
	assert.Equal(t, "unknown", backend.state.Connectivity)
}

func TestConnectivityNames(t *testing.T) {
	for value, expected := range map[gonetworkmanager.NmConnectivity]string{
		gonetworkmanager.NmConnectivityUnknown: "unknown",
		gonetworkmanager.NmConnectivityNone:    "none",
		gonetworkmanager.NmConnectivityPortal:  "portal",
		gonetworkmanager.NmConnectivityLimited: "limited",
		gonetworkmanager.NmConnectivityFull:    "full",
		gonetworkmanager.NmConnectivity(99):    "unknown",
	} {
		assert.Equal(t, expected, connectivityName(value))
	}
}

func TestNetworkManagerBackend_UpdateEthernetState_NoDevice(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	backend.ethernetDevice = nil
	err = backend.updateEthernetState()
	assert.NoError(t, err)
}

func TestNetworkManagerBackend_UpdateWiFiState_NoDevice(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	backend.wifiDevice = nil
	err = backend.updateWiFiState()
	assert.NoError(t, err)
}

func TestNetworkManagerBackend_ClassifyNMStateReason(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	testCases := []struct {
		reason   uint32
		expected string
	}{
		{NmDeviceStateReasonWrongPassword, errdefs.ErrBadCredentials},
		{NmDeviceStateReasonNoSecrets, errdefs.ErrUserCanceled},
		{NmDeviceStateReasonSupplicantTimeout, errdefs.ErrBadCredentials},
		{NmDeviceStateReasonDhcpClientFailed, errdefs.ErrDhcpTimeout},
		{NmDeviceStateReasonNoSsid, errdefs.ErrNoSuchSSID},
		{999, errdefs.ErrConnectionFailed},
	}

	for _, tc := range testCases {
		result := backend.classifyNMStateReason(tc.reason)
		assert.Equal(t, tc.expected, result)
	}
}

func TestNetworkManagerBackend_GetDeviceIP_NoConfig(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	mockDevice := mock_gonetworkmanager.NewMockDevice(t)

	backend, err := NewNetworkManagerBackend(mockNM)
	assert.NoError(t, err)

	mockDevice.EXPECT().GetPropertyIP4Config().Return(nil, nil)

	ip := backend.getDeviceIP(mockDevice)
	assert.Empty(t, ip)
}
