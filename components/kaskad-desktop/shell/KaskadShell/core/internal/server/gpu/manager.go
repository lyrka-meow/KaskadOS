package gpu

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

var cardNamePattern = regexp.MustCompile(`^card[0-9]+$`)

type Device struct {
	ID             string             `json:"id"`
	Card           string             `json:"card"`
	Driver         string             `json:"driver"`
	VendorID       string             `json:"vendorId"`
	DeviceID       string             `json:"deviceId"`
	Kind           string             `json:"kind"`
	Name           string             `json:"name,omitempty"`
	Utilization    float64            `json:"utilization"`
	UsageAvailable bool               `json:"usageAvailable"`
	Engines        map[string]float64 `json:"engines,omitempty"`
	VRAMUsedBytes  uint64             `json:"vramUsedBytes,omitempty"`
	VRAMTotalBytes uint64             `json:"vramTotalBytes,omitempty"`
	Temperature    float64            `json:"temperature,omitempty"`
	RuntimeStatus  string             `json:"runtimeStatus,omitempty"`
}

type State struct {
	Devices   []Device `json:"devices"`
	SampledAt int64    `json:"sampledAt"`
}

type Manager struct {
	mu             sync.Mutex
	sysRoot        string
	procRoot       string
	now            func() time.Time
	runNvidiaSMI   func(context.Context) ([]byte, error)
	previous       map[string]uint64
	previousSample time.Time
}

func NewManager() *Manager {
	return &Manager{
		sysRoot:  "/sys",
		procRoot: "/proc",
		now:      time.Now,
		previous: make(map[string]uint64),
		runNvidiaSMI: func(ctx context.Context) ([]byte, error) {
			return exec.CommandContext(ctx, "nvidia-smi",
				"--query-gpu=pci.bus_id,name,utilization.gpu,memory.used,memory.total,temperature.gpu",
				"--format=csv,noheader,nounits").Output()
		},
	}
}

func (m *Manager) State() State {
	m.mu.Lock()
	defer m.mu.Unlock()

	now := m.now()
	devices := m.discoverDevices()
	counters := m.readDRMCounters()
	elapsed := now.Sub(m.previousSample)
	if !m.previousSample.IsZero() && elapsed > 0 {
		applyDRMUtilization(devices, counters, m.previous, elapsed)
	}
	m.previous = counters
	m.previousSample = now
	m.applyNvidia(devices)

	sort.Slice(devices, func(i, j int) bool { return devices[i].ID < devices[j].ID })
	return State{Devices: devices, SampledAt: now.UnixMilli()}
}

func (m *Manager) discoverDevices() []Device {
	entries, err := os.ReadDir(filepath.Join(m.sysRoot, "class", "drm"))
	if err != nil {
		return nil
	}
	devices := make([]Device, 0, len(entries))
	seen := make(map[string]bool)
	for _, entry := range entries {
		if !cardNamePattern.MatchString(entry.Name()) {
			continue
		}
		deviceDir := filepath.Join(m.sysRoot, "class", "drm", entry.Name(), "device")
		target, err := filepath.EvalSymlinks(deviceDir)
		if err != nil {
			continue
		}
		id := normalizeBDF(filepath.Base(target))
		if id == "" || seen[id] {
			continue
		}
		seen[id] = true
		vendor := readTrimmed(filepath.Join(deviceDir, "vendor"))
		deviceID := readTrimmed(filepath.Join(deviceDir, "device"))
		driver := ""
		if driverPath, err := filepath.EvalSymlinks(filepath.Join(deviceDir, "driver")); err == nil {
			driver = filepath.Base(driverPath)
		}
		total := readUint(filepath.Join(deviceDir, "mem_info_vram_total"))
		used := readUint(filepath.Join(deviceDir, "mem_info_vram_used"))
		devices = append(devices, Device{
			ID: id, Card: entry.Name(), Driver: driver,
			VendorID: strings.TrimPrefix(vendor, "0x"), DeviceID: strings.TrimPrefix(deviceID, "0x"),
			Kind:          classifyDevice(id, vendor, driver, total),
			VRAMUsedBytes: used, VRAMTotalBytes: total,
			Temperature:   readTemperature(deviceDir),
			RuntimeStatus: readTrimmed(filepath.Join(deviceDir, "power", "runtime_status")),
		})
	}
	return devices
}

func (m *Manager) readDRMCounters() map[string]uint64 {
	result := make(map[string]uint64)
	processes, err := os.ReadDir(m.procRoot)
	if err != nil {
		return result
	}
	// A DRM client can have duplicated file descriptors. drm-client-id identifies
	// the shared client, so only one copy may participate in the total.
	seenClients := make(map[string]bool)
	for _, process := range processes {
		if !process.IsDir() {
			continue
		}
		if _, err := strconv.Atoi(process.Name()); err != nil {
			continue
		}
		fdinfos, err := os.ReadDir(filepath.Join(m.procRoot, process.Name(), "fdinfo"))
		if err != nil {
			continue
		}
		for _, fdinfo := range fdinfos {
			parsed, ok := parseFDInfo(filepath.Join(m.procRoot, process.Name(), "fdinfo", fdinfo.Name()))
			if !ok {
				continue
			}
			clientKey := parsed.device + "|" + parsed.clientID
			if seenClients[clientKey] {
				continue
			}
			seenClients[clientKey] = true
			for engine, value := range parsed.engines {
				result[clientKey+"|"+engine] = value
			}
		}
	}
	return result
}

type fdInfo struct {
	device   string
	clientID string
	engines  map[string]uint64
}

func parseFDInfo(path string) (fdInfo, bool) {
	file, err := os.Open(path)
	if err != nil {
		return fdInfo{}, false
	}
	defer file.Close()
	parsed := fdInfo{engines: make(map[string]uint64)}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		key, value, ok := strings.Cut(scanner.Text(), ":")
		if !ok {
			continue
		}
		value = strings.TrimSpace(value)
		switch key {
		case "drm-pdev":
			parsed.device = normalizeBDF(value)
		case "drm-client-id":
			parsed.clientID = value
		default:
			if !strings.HasPrefix(key, "drm-engine-") {
				continue
			}
			fields := strings.Fields(value)
			if len(fields) == 0 {
				continue
			}
			if counter, err := strconv.ParseUint(fields[0], 10, 64); err == nil {
				parsed.engines[strings.TrimPrefix(key, "drm-engine-")] = counter
			}
		}
	}
	return parsed, parsed.device != "" && parsed.clientID != "" && len(parsed.engines) > 0
}

func applyDRMUtilization(devices []Device, current, previous map[string]uint64, elapsed time.Duration) {
	perDevice := make(map[string]map[string]uint64)
	for key, currentValue := range current {
		previousValue, ok := previous[key]
		if !ok || currentValue < previousValue {
			continue
		}
		parts := strings.Split(key, "|")
		if len(parts) != 3 {
			continue
		}
		if perDevice[parts[0]] == nil {
			perDevice[parts[0]] = make(map[string]uint64)
		}
		perDevice[parts[0]][parts[2]] += currentValue - previousValue
	}
	for index := range devices {
		engines := perDevice[devices[index].ID]
		if len(engines) == 0 {
			continue
		}
		devices[index].Engines = make(map[string]float64, len(engines))
		for name, activeNS := range engines {
			value := clampPercent(float64(activeNS) / float64(elapsed.Nanoseconds()) * 100)
			devices[index].Engines[name] = value
			// Engines can run in parallel. Their sum may exceed 100%, therefore the
			// busiest engine is the meaningful overall load for a compact widget.
			if value > devices[index].Utilization {
				devices[index].Utilization = value
			}
		}
		devices[index].UsageAvailable = true
	}
}

func (m *Manager) applyNvidia(devices []Device) {
	hasNvidia := false
	for index := range devices {
		device := devices[index]
		if device.Driver == "nvidia" || device.VendorID == "10de" {
			if device.RuntimeStatus == "suspended" {
				devices[index].UsageAvailable = true
				continue
			}
			hasNvidia = true
		}
	}
	if !hasNvidia {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 1200*time.Millisecond)
	defer cancel()
	output, err := m.runNvidiaSMI(ctx)
	if err != nil {
		return
	}
	data := parseNvidiaSMI(string(output))
	for index := range devices {
		item, ok := data[devices[index].ID]
		if !ok {
			continue
		}
		devices[index].Name = item.name
		devices[index].Utilization = item.utilization
		devices[index].UsageAvailable = true
		devices[index].VRAMUsedBytes = item.memoryUsedMiB * 1024 * 1024
		devices[index].VRAMTotalBytes = item.memoryTotalMiB * 1024 * 1024
		devices[index].Temperature = item.temperature
	}
}

type nvidiaData struct {
	name                          string
	utilization, temperature      float64
	memoryUsedMiB, memoryTotalMiB uint64
}

func parseNvidiaSMI(output string) map[string]nvidiaData {
	result := make(map[string]nvidiaData)
	for _, line := range strings.Split(strings.TrimSpace(output), "\n") {
		fields := strings.Split(line, ",")
		if len(fields) < 6 {
			continue
		}
		id := normalizeBDF(strings.TrimSpace(fields[0]))
		if id == "" {
			continue
		}
		result[id] = nvidiaData{
			name:          strings.TrimSpace(fields[1]),
			utilization:   clampPercent(parseFloat(fields[2])),
			memoryUsedMiB: parseUint(fields[3]), memoryTotalMiB: parseUint(fields[4]),
			temperature: parseFloat(fields[5]),
		}
	}
	return result
}

func normalizeBDF(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	parts := strings.Split(value, ":")
	if len(parts) != 3 || len(parts[2]) != 4 || parts[2][2] != '.' {
		return ""
	}
	domain := parts[0]
	if len(domain) > 4 {
		domain = domain[len(domain)-4:]
	}
	return fmt.Sprintf("%04s:%02s:%s", domain, parts[1], parts[2])
}

func classifyDevice(id, vendor, driver string, vram uint64) string {
	vendor = strings.TrimPrefix(strings.ToLower(vendor), "0x")
	if driver == "nvidia" || vendor == "10de" {
		return "discrete"
	}
	if strings.HasPrefix(id, "0000:00:02.") && vendor == "8086" {
		return "integrated"
	}
	if vram >= 1024*1024*1024 {
		return "discrete"
	}
	if vendor == "8086" || (vendor == "1002" && vram == 0) {
		return "integrated"
	}
	return "unknown"
}

func readTrimmed(path string) string {
	value, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(value))
}

func readUint(path string) uint64 { return parseUint(readTrimmed(path)) }

func parseUint(value string) uint64 {
	fields := strings.Fields(strings.TrimSpace(value))
	if len(fields) == 0 {
		return 0
	}
	result, _ := strconv.ParseUint(fields[0], 10, 64)
	return result
}

func parseFloat(value string) float64 {
	result, _ := strconv.ParseFloat(strings.TrimSpace(value), 64)
	return result
}

func readTemperature(deviceDir string) float64 {
	paths, _ := filepath.Glob(filepath.Join(deviceDir, "hwmon", "hwmon*", "temp1_input"))
	for _, path := range paths {
		if value := parseFloat(readTrimmed(path)); value != 0 {
			return value / 1000
		}
	}
	return 0
}

func clampPercent(value float64) float64 {
	if value < 0 {
		return 0
	}
	if value > 100 {
		return 100
	}
	return value
}
