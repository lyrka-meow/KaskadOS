package config

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/lyrka-meow/KaskadOS/components/regalia/internal/state"
)

func TestBuildUsesSelectedServerAndProcessPaths(t *testing.T) {
	snapshot := readySnapshot()
	result, err := Build(snapshot)
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := json.Unmarshal(result.JSON, &document); err != nil {
		t.Fatal(err)
	}
	outbounds := document["outbounds"].([]any)
	proxy := outbounds[0].(map[string]any)
	if proxy["tag"] != "proxy" || proxy["password"] != "secret" {
		t.Fatalf("unexpected proxy outbound: %#v", proxy)
	}
	route := document["route"].(map[string]any)
	rules := route["rules"].([]any)
	directRule := rules[2].(map[string]any)
	if directRule["action"] != "route" || directRule["outbound"] != "direct" {
		t.Fatalf("direct application route was not preserved for the engine classifier: %#v", directRule)
	}
	paths := directRule["process_path"].([]any)
	if len(paths) != 1 || paths[0] != "/usr/bin/chromium" {
		t.Fatalf("unexpected process paths: %#v", paths)
	}
}

func TestDirectByDefaultKeepsProxyExceptionsInConfiguration(t *testing.T) {
	snapshot := readySnapshot()
	snapshot.RouteProfiles[0].DefaultOutbound = "direct"
	snapshot.RouteProfiles[0].Apps[0].Outbound = "proxy"
	result, err := Build(snapshot)
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := json.Unmarshal(result.JSON, &document); err != nil {
		t.Fatal(err)
	}
	rules := document["route"].(map[string]any)["rules"].([]any)
	proxyRule := rules[2].(map[string]any)
	if proxyRule["action"] != "route" || proxyRule["outbound"] != "proxy" {
		t.Fatalf("proxy exception must remain available to the engine classifier: %#v", proxyRule)
	}
	if len(rules) != 3 {
		t.Fatalf("kernel bypass must be installed by regalia-engine, not emitted as a sing-box rule: %#v", rules)
	}
}

func TestGeneratedConfigurationPassesSingBoxCheck(t *testing.T) {
	binary := os.Getenv("REGALIA_SING_BOX")
	if binary == "" {
		t.Skip("REGALIA_SING_BOX is not set")
	}
	result, err := Build(readySnapshot())
	if err != nil {
		t.Fatal(err)
	}
	configPath := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(configPath, result.JSON, 0o600); err != nil {
		t.Fatal(err)
	}
	command := exec.Command(binary, "check", "--disable-color", "-c", configPath)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("sing-box check failed: %v\n%s", err, output)
	}
}

func TestGeneratedNetcheckConfigurationPassesSingBoxCheck(t *testing.T) {
	binary := os.Getenv("REGALIA_SING_BOX")
	if binary == "" {
		t.Skip("REGALIA_SING_BOX is not set")
	}
	result, err := BuildWithOptions(readySnapshot(), NetcheckOptions{
		Port: 43123, DirectUser: "direct", DirectPassword: "direct-secret",
		ProxyUser: "proxy", ProxyPassword: "proxy-secret",
	})
	if err != nil {
		t.Fatal(err)
	}
	configPath := filepath.Join(t.TempDir(), "config.json")
	if err := os.WriteFile(configPath, result.JSON, 0o600); err != nil {
		t.Fatal(err)
	}
	command := exec.Command(binary, "check", "--disable-color", "-c", configPath)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("sing-box netcheck config failed: %v\n%s", err, output)
	}
}

func TestNetcheckDirectRouteUsesWorkingResolver(t *testing.T) {
	result, err := BuildWithOptions(readySnapshot(), NetcheckOptions{
		Port: 43123, DirectUser: "direct", DirectPassword: "direct-secret",
		ProxyUser: "proxy", ProxyPassword: "proxy-secret",
	})
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := json.Unmarshal(result.JSON, &document); err != nil {
		t.Fatal(err)
	}
	route := document["route"].(map[string]any)
	rules := route["rules"].([]any)
	resolveRule := rules[0].(map[string]any)
	if resolveRule["inbound"] != "regalia-netcheck" ||
		resolveRule["auth_user"] != "direct" ||
		resolveRule["action"] != "resolve" ||
		resolveRule["server"] != "dns-remote" ||
		resolveRule["strategy"] != "prefer_ipv4" {
		t.Fatalf("unexpected direct netcheck resolver rule: %#v", resolveRule)
	}
	directRule := rules[1].(map[string]any)
	if directRule["action"] != "route" || directRule["outbound"] != "direct" {
		t.Fatalf("unexpected direct netcheck route: %#v", directRule)
	}
}

func readySnapshot() state.State {
	outbound := json.RawMessage(`{
		"type":"trojan",
		"server":"vpn.example",
		"server_port":443,
		"password":"secret",
		"tls":{"enabled":true,"server_name":"vpn.example"}
	}`)
	return state.State{
		SchemaVersion:  state.SchemaVersion,
		ActiveServerID: "server-1",
		ActiveRouteID:  "route-1",
		Profiles: []state.SubscriptionProfile{{
			ID: "profile-1",
			Servers: []state.Server{{
				ID:       "server-1",
				Name:     "Warsaw",
				Protocol: "trojan",
				Outbound: outbound,
			}},
		}},
		RouteProfiles: []state.RouteProfile{{
			ID:              "route-1",
			DefaultOutbound: "proxy",
			Apps: []state.AppRule{{
				ProcessPath: "/usr/bin/chromium",
				Outbound:    "direct",
			}},
		}},
	}
}

func TestBuildRequiresSelection(t *testing.T) {
	if _, err := Build(state.State{}); err == nil {
		t.Fatal("expected missing-server error")
	}
}
