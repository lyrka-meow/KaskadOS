package network

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/Wifx/gonetworkmanager/v2"
	mock_gonetworkmanager "github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/mocks/github.com/Wifx/gonetworkmanager/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestManager_SetConnectionPreference(t *testing.T) {
	t.Run("invalid preference", func(t *testing.T) {
		manager := &Manager{
			state: &NetworkState{
				Preference: PreferenceAuto,
			},
		}

		err := manager.SetConnectionPreference(ConnectionPreference("invalid"))
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "invalid preference")
	})
}

func TestManager_GetConnectionPreference(t *testing.T) {
	tests := []struct {
		name       string
		preference ConnectionPreference
	}{
		{"auto", PreferenceAuto},
		{"wifi", PreferenceWiFi},
		{"ethernet", PreferenceEthernet},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			manager := &Manager{
				state: &NetworkState{
					Preference: tt.preference,
				},
			}

			result := manager.GetConnectionPreference()
			assert.Equal(t, tt.preference, result)
		})
	}
}

type preferenceBackendStub struct {
	Backend
	apply func(ConnectionPreference, func() error) error
}

func (b preferenceBackendStub) applyConnectionPreference(pref ConnectionPreference, commit func() error) error {
	return b.apply(pref, commit)
}

func TestPreferencePublishesOnlyAfterSuccessfulApplyAndSave(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	m := &Manager{state: &NetworkState{Preference: PreferenceAuto}, dirty: make(chan struct{}, 1)}
	m.backend = preferenceBackendStub{apply: func(pref ConnectionPreference, commit func() error) error {
		assert.Equal(t, PreferenceEthernet, pref)
		assert.Equal(t, PreferenceAuto, m.GetConnectionPreference())
		assert.False(t, m.state.PreferenceInitialized)
		return commit()
	}}
	require.NoError(t, m.SetConnectionPreference(PreferenceEthernet))
	assert.Equal(t, PreferenceEthernet, m.GetConnectionPreference())
	assert.True(t, m.state.PreferenceInitialized)
	pref, initialized, err := loadConnectionPreference()
	require.NoError(t, err)
	assert.Equal(t, PreferenceEthernet, pref)
	assert.True(t, initialized)
	assert.Len(t, m.dirty, 1)
}

func TestFailedPreferenceRetainsConfirmedState(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	require.NoError(t, saveConnectionPreference(PreferenceWiFi))
	m := &Manager{state: &NetworkState{Preference: PreferenceWiFi, PreferenceInitialized: true}, dirty: make(chan struct{}, 1)}
	m.backend = preferenceBackendStub{apply: func(ConnectionPreference, func() error) error {
		return errors.New("NetworkManager denied changes")
	}}
	require.ErrorContains(t, m.SetConnectionPreference(PreferenceEthernet), "denied")
	assert.Equal(t, PreferenceWiFi, m.GetConnectionPreference())
	pref, initialized, err := loadConnectionPreference()
	require.NoError(t, err)
	assert.Equal(t, PreferenceWiFi, pref)
	assert.True(t, initialized)
	assert.Empty(t, m.dirty)
}

func TestUnsupportedPreferenceDoesNotClaimSuccess(t *testing.T) {
	m := &Manager{state: &NetworkState{Preference: PreferenceAuto}}
	require.ErrorContains(t, m.SetConnectionPreference(PreferenceEthernet), "not supported")
	assert.Equal(t, PreferenceAuto, m.GetConnectionPreference())
	assert.False(t, m.state.PreferenceInitialized)
}

func TestPriorityPlanExcludesDownstreamConnections(t *testing.T) {
	for _, settings := range []gonetworkmanager.ConnectionSettings{
		{"connection": {"type": "802-11-wireless"}, "802-11-wireless": {"mode": "ap"}},
		{"connection": {"type": "802-3-ethernet"}, "ipv4": {"method": "shared"}},
		{"connection": {"type": "802-3-ethernet"}, "ipv6": {"method": "shared"}},
		{"connection": {"type": "vpn"}},
	} {
		change, err := priorityChangeForSettings(settings, PreferenceEthernet)
		require.NoError(t, err)
		assert.Nil(t, change)
	}
}

func TestPriorityPlanUsesUUIDAndPreservesOriginalValues(t *testing.T) {
	settings := gonetworkmanager.ConnectionSettings{
		"connection": {"id": "Duplicate name", "uuid": "eth-profile-uuid", "type": "802-3-ethernet", "autoconnect-priority": int32(5)},
		"ipv4":       {"route-metric": int64(42)}, "ipv6": {"route-metric": int64(93)},
	}
	change, err := priorityChangeForSettings(settings, PreferenceEthernet)
	require.NoError(t, err)
	assert.Equal(t, "eth-profile-uuid", change.uuid)
	assert.Equal(t, connectionPriority{5, 42, 93}, change.before)
	assert.Equal(t, connectionPriority{100, 100, 100}, change.after)
	assert.Equal(t, connectionPriority{0, -1, -1}, priorityForPreference(PreferenceAuto, "802-3-ethernet"))
	assert.Equal(t, connectionPriority{10, 300, 300}, priorityForPreference(PreferenceWiFi, "802-3-ethernet"))
}

func TestPreferencePlanOnlyReappliesActiveUplinkDevices(t *testing.T) {
	mockNM := mock_gonetworkmanager.NewMockNetworkManager(t)
	settings := mock_gonetworkmanager.NewMockSettings(t)
	profile := mock_gonetworkmanager.NewMockConnection(t)
	ap := mock_gonetworkmanager.NewMockActiveConnection(t)
	uplink := mock_gonetworkmanager.NewMockActiveConnection(t)
	device := mock_gonetworkmanager.NewMockDevice(t)
	backend, err := NewNetworkManagerBackend(mockNM)
	require.NoError(t, err)
	backend.settings = settings
	settings.EXPECT().ListConnections().Return([]gonetworkmanager.Connection{profile}, nil)
	profile.EXPECT().GetSettings().Return(gonetworkmanager.ConnectionSettings{
		"connection": {"uuid": "eth-uuid", "type": "802-3-ethernet"},
	}, nil)
	mockNM.EXPECT().GetPropertyActiveConnections().Return([]gonetworkmanager.ActiveConnection{ap, uplink}, nil)
	ap.EXPECT().GetPropertyUUID().Return("ap-uuid", nil)
	uplink.EXPECT().GetPropertyUUID().Return("eth-uuid", nil)
	uplink.EXPECT().GetPropertyDevices().Return([]gonetworkmanager.Device{device}, nil)
	device.EXPECT().GetPropertyState().Return(gonetworkmanager.NmDeviceStateActivated, nil)
	device.EXPECT().GetPropertyInterface().Return("eth0", nil)
	plan, err := backend.connectionPriorityPlan(PreferenceEthernet)
	require.NoError(t, err)
	require.Len(t, plan, 1)
	assert.Equal(t, []string{"eth0"}, plan[0].devices)
}

func TestPriorityApplyRollsBackOnModifyReapplyAndPersistenceFailures(t *testing.T) {
	plan := []connectionPriorityChange{
		{uuid: "eth-uuid", before: connectionPriority{3, 42, 99}, after: connectionPriority{100, 100, 100}, devices: []string{"eth0"}},
		{uuid: "wifi-uuid", before: connectionPriority{9, 55, 56}, after: connectionPriority{10, 300, 300}, devices: []string{"wlan0"}},
	}
	for _, test := range []struct {
		name       string
		failAt     int
		failCommit bool
	}{
		{"modify", 2, false}, {"reapply", 3, false}, {"persist", 0, true},
	} {
		t.Run(test.name, func(t *testing.T) {
			var commands [][]string
			committed := false
			run := func(args ...string) error {
				commands = append(commands, append([]string(nil), args...))
				if len(commands) == test.failAt {
					return errors.New("denied")
				}
				return nil
			}
			err := applyConnectionPriorityPlan(plan, run, func() error {
				if test.failCommit {
					return errors.New("disk full")
				}
				committed = true
				return nil
			})
			require.Error(t, err)
			assert.False(t, committed)
			assert.Equal(t, []string{"connection", "modify", "uuid", "eth-uuid"}, commands[0][:4])
			assert.Contains(t, commands, []string{"connection", "modify", "uuid", "eth-uuid", "connection.autoconnect-priority", "3", "ipv4.route-metric", "42", "ipv6.route-metric", "99"})
			assert.Contains(t, commands, []string{"connection", "modify", "uuid", "wifi-uuid", "connection.autoconnect-priority", "9", "ipv4.route-metric", "55", "ipv6.route-metric", "56"})
			assert.Equal(t, []string{"device", "reapply", "wlan0"}, commands[len(commands)-1])
		})
	}
}

func TestPriorityApplyReportsFailedRecovery(t *testing.T) {
	plan := []connectionPriorityChange{{uuid: "eth-uuid", devices: []string{"eth0"}}}
	err := applyConnectionPriorityPlan(plan, func(...string) error { return errors.New("blocked") }, func() error {
		t.Fatal("commit should not run")
		return nil
	})
	require.ErrorContains(t, err, "update profile eth-uuid")
	require.ErrorContains(t, err, "restore profile eth-uuid")
	require.ErrorContains(t, err, "restore active interface eth0")
}

func TestPreferenceStoreBootstrapAndValidation(t *testing.T) {
	configDir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", configDir)
	pref, initialized, err := loadConnectionPreference()
	require.NoError(t, err)
	assert.Equal(t, PreferenceAuto, pref)
	assert.False(t, initialized)
	for _, value := range []ConnectionPreference{PreferenceEthernet, PreferenceWiFi, PreferenceAuto} {
		require.NoError(t, saveConnectionPreference(value))
		pref, initialized, err = loadConnectionPreference()
		require.NoError(t, err)
		assert.Equal(t, value, pref)
		assert.True(t, initialized)
	}
	require.Error(t, saveConnectionPreference("invalid"))
	path, err := connectionPreferencePath()
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(path, []byte(`{"preference":"invalid"}`), 0600))
	_, initialized, err = loadConnectionPreference()
	require.Error(t, err)
	assert.False(t, initialized)
	leftovers, err := filepath.Glob(filepath.Join(filepath.Dir(path), ".network-preference-*"))
	require.NoError(t, err)
	assert.Empty(t, leftovers)
}
