package gpu

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestNormalizeBDF(t *testing.T) {
	require.Equal(t, "0000:01:00.0", normalizeBDF("00000000:01:00.0"))
	require.Equal(t, "0000:00:02.0", normalizeBDF("0000:00:02.0"))
	require.Empty(t, normalizeBDF("not-a-device"))
}

func TestParseNvidiaSMI(t *testing.T) {
	state := parseNvidiaSMI("00000000:01:00.0, NVIDIA GeForce RTX 4050 Laptop GPU, 37, 512, 6141, 44\n")
	device := state["0000:01:00.0"]
	require.Equal(t, "NVIDIA GeForce RTX 4050 Laptop GPU", device.name)
	require.Equal(t, 37.0, device.utilization)
	require.Equal(t, uint64(512), device.memoryUsedMiB)
	require.Equal(t, 44.0, device.temperature)
}

func TestParseFDInfoAndUtilization(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "fdinfo")
	require.NoError(t, os.WriteFile(path, []byte("drm-driver:\ti915\ndrm-client-id:\t7\ndrm-pdev:\t0000:00:02.0\ndrm-engine-render:\t250000000 ns\ndrm-engine-copy:\t100000000 ns\n"), 0o600))
	parsed, ok := parseFDInfo(path)
	require.True(t, ok)
	require.Equal(t, "0000:00:02.0", parsed.device)
	require.Equal(t, uint64(250000000), parsed.engines["render"])

	devices := []Device{{ID: "0000:00:02.0"}}
	previous := map[string]uint64{"0000:00:02.0|7|render": 100000000, "0000:00:02.0|7|copy": 50000000}
	current := map[string]uint64{"0000:00:02.0|7|render": 250000000, "0000:00:02.0|7|copy": 100000000}
	applyDRMUtilization(devices, current, previous, time.Second)
	require.True(t, devices[0].UsageAvailable)
	require.InDelta(t, 15, devices[0].Utilization, 0.001)
	require.InDelta(t, 5, devices[0].Engines["copy"], 0.001)
}

func TestClassifyDevice(t *testing.T) {
	require.Equal(t, "integrated", classifyDevice("0000:00:02.0", "0x8086", "i915", 0))
	require.Equal(t, "discrete", classifyDevice("0000:01:00.0", "0x10de", "nvidia", 0))
	require.Equal(t, "discrete", classifyDevice("0000:03:00.0", "0x1002", "amdgpu", 8*1024*1024*1024))
}
