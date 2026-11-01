//go:build linux

package enginebridge

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseRoutingPolicy(t *testing.T) {
	policy, err := parseRoutingPolicy([]byte(`{
		"route": {
			"final": "direct",
			"rules": [
				{"action":"sniff"},
				{"action":"route","outbound":"proxy","process_path":["/usr/bin/discord"]}
			]
		}
	}`))
	if err != nil {
		t.Fatal(err)
	}
	if policy.DefaultOutbound != "direct" || policy.ProcessPaths["/usr/bin/discord"] != "proxy" {
		t.Fatalf("unexpected policy: %#v", policy)
	}
}

func TestDiscoverSocketCgroupsUsesExecutableAndUnifiedHierarchy(t *testing.T) {
	root := t.TempDir()
	process := filepath.Join(root, "123")
	if err := os.Mkdir(process, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("/usr/bin/bridge", filepath.Join(process, "exe")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(process, "cgroup"), []byte("0::/user.slice/user-1000.slice/app.slice/bridge.scope\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	policy := routingPolicy{DefaultOutbound: "proxy", ProcessPaths: map[string]string{"/usr/bin/bridge": "direct"}}
	cgroups := discoverSocketCgroups(root, policy)
	if len(cgroups) != 1 || cgroups[0].Level != 4 || cgroups[0].Path != "user.slice/user-1000.slice/app.slice/bridge.scope" || cgroups[0].Outbound != "direct" {
		t.Fatalf("unexpected cgroups: %#v", cgroups)
	}
}

func TestDiscoverSocketCgroupsRejectsSharedSessionScope(t *testing.T) {
	root := t.TempDir()
	process := filepath.Join(root, "123")
	if err := os.Mkdir(process, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("/usr/bin/discord", filepath.Join(process, "exe")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(process, "cgroup"), []byte("0::/user.slice/user-1000.slice/session-7.scope\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	policy := routingPolicy{DefaultOutbound: "direct", ProcessPaths: map[string]string{"/usr/bin/discord": "proxy"}}
	if cgroups := discoverSocketCgroups(root, policy); len(cgroups) != 0 {
		t.Fatalf("shared desktop session must not become an application route: %#v", cgroups)
	}
}

func TestBuildNFTRulesetMarksExceptionsBeforeDirectDefault(t *testing.T) {
	ruleset := buildNFTRuleset("direct", []socketCgroup{{Level: 5, Path: "user.slice/user-1000.slice/user@1000.service/app.slice/app-discord.scope", Outbound: "proxy"}})
	if strings.Contains(ruleset, "destroy table") {
		t.Fatalf("table cleanup must not be part of the create transaction:\n%s", ruleset)
	}
	proxyRule := `socket cgroupv2 level 5 "user.slice/user-1000.slice/user@1000.service/app.slice/app-discord.scope" meta mark set 0x2023 ct mark set meta mark return`
	defaultRule := `meta mark set 0x2024 ct mark set meta mark`
	if !strings.Contains(ruleset, proxyRule) || !strings.Contains(ruleset, defaultRule) {
		t.Fatalf("missing packet marks:\n%s", ruleset)
	}
	if strings.Index(ruleset, proxyRule) > strings.Index(ruleset, defaultRule) {
		t.Fatalf("proxy exception must precede the direct default:\n%s", ruleset)
	}
	if !strings.Contains(ruleset, "type route hook output priority -147") {
		t.Fatalf("missing post-sing-box UDP route chain:\n%s", ruleset)
	}
	if strings.Count(ruleset, proxyRule) != 2 {
		t.Fatalf("proxy exception must be applied before and after sing-box UDP processing:\n%s", ruleset)
	}
	if !strings.Contains(ruleset, `meta l4proto != { icmp, udp, ipv6-icmp } return`) {
		t.Fatalf("post chain must be limited to UDP and ICMP:\n%s", ruleset)
	}
}

func TestBuildNFTRulesetLeavesProxyDefaultUnmarked(t *testing.T) {
	ruleset := buildNFTRuleset("proxy", []socketCgroup{{Level: 5, Path: "user.slice/user-1000.slice/user@1000.service/app.slice/bridge.scope", Outbound: "direct"}})
	if !strings.Contains(ruleset, `meta mark set 0x2024 ct mark set meta mark return`) {
		t.Fatalf("missing direct exception:\n%s", ruleset)
	}
	if strings.Contains(ruleset, "\n    meta mark set 0x2024 ct mark set meta mark\n") {
		t.Fatalf("proxy default must be left for sing-box to capture:\n%s", ruleset)
	}
	if strings.Contains(ruleset, "\n    meta mark set 0x2024 ct mark set meta mark\n") {
		t.Fatalf("proxy default must not gain an unconditional direct mark:\n%s", ruleset)
	}
}
