package network

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/Wifx/gonetworkmanager/v2"
)

const (
	priorityHigh    = int32(100)
	priorityLow     = int32(10)
	priorityDefault = int32(0)

	metricPreferred    = int64(100)
	metricNonPreferred = int64(300)
	// Restore NetworkManager's per-device defaults in automatic mode.
	metricDefault = int64(-1)
)

func validConnectionPreference(pref ConnectionPreference) bool {
	return pref == PreferenceWiFi || pref == PreferenceEthernet || pref == PreferenceAuto
}

// connectionPreferenceBackend keeps unsupported backends from acknowledging a
// routing change they cannot perform. commit persists only a successful change.
type connectionPreferenceBackend interface {
	applyConnectionPreference(ConnectionPreference, func() error) error
}

func (m *Manager) SetConnectionPreference(pref ConnectionPreference) error {
	if !validConnectionPreference(pref) {
		return fmt.Errorf("invalid preference: %s", pref)
	}
	backend, ok := m.backend.(connectionPreferenceBackend)
	if !ok {
		return fmt.Errorf("connection preference is not supported by this network backend")
	}
	m.preferenceMutex.Lock()
	defer m.preferenceMutex.Unlock()

	if err := backend.applyConnectionPreference(pref, func() error {
		return saveConnectionPreference(pref)
	}); err != nil {
		return err
	}
	m.stateMutex.Lock()
	m.state.Preference = pref
	m.state.PreferenceInitialized = true
	m.stateMutex.Unlock()
	m.notifySubscribers()
	return nil
}

type connectionPriority struct {
	priority int32
	ipv4     int64
	ipv6     int64
}

type connectionPriorityChange struct {
	uuid    string
	before  connectionPriority
	after   connectionPriority
	devices []string
}

func priorityForPreference(pref ConnectionPreference, connType string) connectionPriority {
	if pref == PreferenceAuto {
		return connectionPriority{priorityDefault, metricDefault, metricDefault}
	}
	if (pref == PreferenceEthernet && connType == "802-3-ethernet") ||
		(pref == PreferenceWiFi && connType == "802-11-wireless") {
		return connectionPriority{priorityHigh, metricPreferred, metricPreferred}
	}
	return connectionPriority{priorityLow, metricNonPreferred, metricNonPreferred}
}

func priorityChangeForSettings(settings gonetworkmanager.ConnectionSettings, pref ConnectionPreference) (*connectionPriorityChange, error) {
	connection := settings["connection"]
	connType, _ := connection["type"].(string)
	if connType != "802-3-ethernet" && connType != "802-11-wireless" {
		return nil, nil
	}
	// Sharing connections are downstream networks, never uplink candidates.
	if settings["802-11-wireless"]["mode"] == "ap" ||
		settings["ipv4"]["method"] == "shared" || settings["ipv6"]["method"] == "shared" {
		return nil, nil
	}
	uuid, _ := connection["uuid"].(string)
	if uuid == "" {
		return nil, fmt.Errorf("network profile has no UUID")
	}
	priority, err := numericPrioritySetting(connection["autoconnect-priority"], 0, 32)
	if err != nil {
		return nil, fmt.Errorf("profile %s autoconnect priority: %w", uuid, err)
	}
	ipv4, err := numericPrioritySetting(settings["ipv4"]["route-metric"], -1, 64)
	if err != nil {
		return nil, fmt.Errorf("profile %s IPv4 metric: %w", uuid, err)
	}
	ipv6, err := numericPrioritySetting(settings["ipv6"]["route-metric"], -1, 64)
	if err != nil {
		return nil, fmt.Errorf("profile %s IPv6 metric: %w", uuid, err)
	}
	return &connectionPriorityChange{
		uuid: uuid, before: connectionPriority{int32(priority), ipv4, ipv6},
		after: priorityForPreference(pref, connType),
	}, nil
}

func numericPrioritySetting(value any, fallback int64, bits int) (int64, error) {
	if value == nil {
		return fallback, nil
	}
	return strconv.ParseInt(fmt.Sprint(value), 10, bits)
}

func (b *NetworkManagerBackend) connectionPriorityPlan(pref ConnectionPreference) ([]connectionPriorityChange, error) {
	settings, err := b.networkManagerSettings()
	if err != nil {
		return nil, err
	}
	connections, err := settings.ListConnections()
	if err != nil {
		return nil, fmt.Errorf("list network profiles: %w", err)
	}
	var plan []connectionPriorityChange
	byUUID := make(map[string]int)
	for _, connection := range connections {
		values, err := connection.GetSettings()
		if err != nil {
			return nil, fmt.Errorf("read network profile: %w", err)
		}
		change, err := priorityChangeForSettings(values, pref)
		if err != nil {
			return nil, err
		}
		if change != nil {
			byUUID[change.uuid] = len(plan)
			plan = append(plan, *change)
		}
	}
	active, err := b.nmConn.(gonetworkmanager.NetworkManager).GetPropertyActiveConnections()
	if err != nil {
		return nil, fmt.Errorf("list active network connections: %w", err)
	}
	for _, connection := range active {
		uuid, err := connection.GetPropertyUUID()
		if err != nil {
			return nil, fmt.Errorf("read active network connection UUID: %w", err)
		}
		index, found := byUUID[uuid]
		if !found {
			continue
		}
		devices, err := connection.GetPropertyDevices()
		if err != nil {
			return nil, fmt.Errorf("read devices of profile %s: %w", uuid, err)
		}
		for _, device := range devices {
			state, err := device.GetPropertyState()
			if err != nil {
				return nil, fmt.Errorf("read active device state: %w", err)
			}
			if state != gonetworkmanager.NmDeviceStateActivated {
				continue
			}
			name, err := device.GetPropertyInterface()
			if err != nil || name == "" {
				return nil, fmt.Errorf("read active interface for profile %s", uuid)
			}
			plan[index].devices = append(plan[index].devices, name)
		}
	}
	return plan, nil
}

func nmcliPreferenceCommand(args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	output, err := exec.CommandContext(ctx, "nmcli", append([]string{"--wait", "10"}, args...)...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(string(output)))
	}
	return nil
}

func modifyConnectionPriority(run func(...string) error, uuid string, value connectionPriority) error {
	return run("connection", "modify", "uuid", uuid,
		"connection.autoconnect-priority", strconv.FormatInt(int64(value.priority), 10),
		"ipv4.route-metric", strconv.FormatInt(value.ipv4, 10),
		"ipv6.route-metric", strconv.FormatInt(value.ipv6, 10))
}

// NetworkManager updates one profile at a time. On any failure, restore the
// original values and report rollback errors as well; never acknowledge a
// partially applied preference as success.
func applyConnectionPriorityPlan(plan []connectionPriorityChange, run func(...string) error, commit func() error) (err error) {
	var changed []connectionPriorityChange
	defer func() {
		if err == nil {
			return
		}
		for i := len(changed) - 1; i >= 0; i-- {
			change := changed[i]
			if rollbackErr := modifyConnectionPriority(run, change.uuid, change.before); rollbackErr != nil {
				err = errors.Join(err, fmt.Errorf("restore profile %s: %w", change.uuid, rollbackErr))
			}
		}
		for _, change := range changed {
			for _, device := range change.devices {
				if rollbackErr := run("device", "reapply", device); rollbackErr != nil {
					err = errors.Join(err, fmt.Errorf("restore active interface %s: %w", device, rollbackErr))
				}
			}
		}
	}()
	for _, change := range plan {
		// Include the failing operation in recovery: a timed-out command may
		// already have reached NetworkManager.
		changed = append(changed, change)
		if err = modifyConnectionPriority(run, change.uuid, change.after); err != nil {
			return fmt.Errorf("update profile %s: %w", change.uuid, err)
		}
	}
	for _, change := range plan {
		for _, device := range change.devices {
			if err = run("device", "reapply", device); err != nil {
				return fmt.Errorf("apply network priority on %s: %w", device, err)
			}
		}
	}
	if err = commit(); err != nil {
		return fmt.Errorf("save network preference: %w", err)
	}
	return nil
}

func (b *NetworkManagerBackend) applyConnectionPreference(pref ConnectionPreference, commit func() error) error {
	plan, err := b.connectionPriorityPlan(pref)
	if err != nil {
		return err
	}
	if err := applyConnectionPriorityPlan(plan, nmcliPreferenceCommand, commit); err != nil {
		return err
	}
	// Refresh cached primary state; a failed read must not turn an applied
	// preference into a failed operation, and will be retried by NM signals.
	_ = b.updatePrimaryConnection()
	if b.onStateChange != nil {
		b.onStateChange()
	}
	return nil
}

func (m *Manager) GetConnectionPreference() ConnectionPreference {
	m.stateMutex.RLock()
	defer m.stateMutex.RUnlock()
	return m.state.Preference
}

func (m *Manager) WasRecentlyFailed(ssid string) bool {
	nm, ok := m.backend.(*NetworkManagerBackend)
	if !ok {
		return false
	}
	nm.failedMutex.RLock()
	defer nm.failedMutex.RUnlock()
	if nm.lastFailedSSID != ssid {
		return false
	}
	return time.Now().Unix()-nm.lastFailedTime < 10
}
