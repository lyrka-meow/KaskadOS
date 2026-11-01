//go:build linux

package enginebridge

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	regaliaBypassTable = "regalia_bypass"
	directMark         = "0x2024"
	proxyMark          = "0x2023"
)

type routingPolicy struct {
	DefaultOutbound string
	ProcessPaths    map[string]string
}

type socketCgroup struct {
	Level    int
	Path     string
	Outbound string
}

type routingController struct {
	policy   routingPolicy
	procRoot string
	log      *boundedLog
	mu       sync.Mutex
	last     string
}

func parseRoutingPolicy(configuration []byte) (routingPolicy, error) {
	var document struct {
		Route struct {
			Final string `json:"final"`
			Rules []struct {
				Action       string   `json:"action"`
				Outbound     string   `json:"outbound"`
				ProcessPaths []string `json:"process_path"`
			} `json:"rules"`
		} `json:"route"`
	}
	if err := json.Unmarshal(configuration, &document); err != nil {
		return routingPolicy{}, fmt.Errorf("decode routing policy: %w", err)
	}
	policy := routingPolicy{
		DefaultOutbound: document.Route.Final,
		ProcessPaths:    make(map[string]string),
	}
	if policy.DefaultOutbound != "direct" && policy.DefaultOutbound != "proxy" {
		return routingPolicy{}, errors.New("routing policy has an invalid default outbound")
	}
	for _, rule := range document.Route.Rules {
		if rule.Action != "route" || (rule.Outbound != "direct" && rule.Outbound != "proxy") {
			continue
		}
		for _, processPath := range rule.ProcessPaths {
			policy.ProcessPaths[filepath.Clean(processPath)] = rule.Outbound
		}
	}
	return policy, nil
}

func newRoutingController(configuration []byte, log *boundedLog) (*routingController, error) {
	policy, err := parseRoutingPolicy(configuration)
	if err != nil {
		return nil, err
	}
	return &routingController{policy: policy, procRoot: "/proc", log: log}, nil
}

func (controller *routingController) Run(ctx context.Context) {
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			controller.remove()
			return
		case <-ticker.C:
			_ = controller.refresh()
		}
	}
}

func (controller *routingController) refresh() error {
	cgroups := discoverSocketCgroups(controller.procRoot, controller.policy)
	ruleset := buildNFTRuleset(controller.policy.DefaultOutbound, cgroups)
	controller.mu.Lock()
	defer controller.mu.Unlock()
	if ruleset == controller.last {
		return nil
	}
	if controller.last == "" {
		// Remove stale state left by an interrupted older engine. There is no
		// live Regalia ruleset to preserve during the initial installation.
		controller.destroyTable()
	} else {
		// nft applies a complete stdin document as one transaction. Replacing an
		// already-active table this way avoids a window in which sing-box can
		// capture packets while process cgroups are being refreshed.
		ruleset = "delete table inet " + regaliaBypassTable + "\n" + ruleset
	}
	command := exec.Command("/usr/bin/nft", "-f", "-")
	command.Stdin = strings.NewReader(ruleset)
	output, err := command.CombinedOutput()
	if err != nil {
		controller.writeLog("regalia packet routing: nftables update failed: %v: %s\n", err, strings.TrimSpace(string(output)))
		return fmt.Errorf("update nftables packet routing: %w", err)
	}
	controller.last = buildNFTRuleset(controller.policy.DefaultOutbound, cgroups)
	controller.writeLog("regalia packet routing: active (%s by default, %d application cgroups)\n", controller.policy.DefaultOutbound, len(cgroups))
	return nil
}

func (controller *routingController) remove() {
	controller.destroyTable()
}

func (controller *routingController) destroyTable() {
	command := exec.Command("/usr/bin/nft", "destroy", "table", "inet", regaliaBypassTable)
	// A missing table is the normal state before the first successful refresh
	// and after an earlier failed transaction, so cleanup is intentionally
	// idempotent and silent.
	_, _ = command.CombinedOutput()
}

func (controller *routingController) writeLog(format string, values ...any) {
	if controller.log != nil {
		_, _ = controller.log.WriteString(fmt.Sprintf(format, values...))
	}
}

func discoverSocketCgroups(procRoot string, policy routingPolicy) []socketCgroup {
	entries, err := os.ReadDir(procRoot)
	if err != nil {
		return nil
	}
	seen := make(map[string]socketCgroup)
	conflicts := make(map[string]bool)
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		if _, err := strconv.Atoi(entry.Name()); err != nil {
			continue
		}
		processDirectory := filepath.Join(procRoot, entry.Name())
		executable, err := os.Readlink(filepath.Join(processDirectory, "exe"))
		if err != nil {
			continue
		}
		executable = strings.TrimSuffix(executable, " (deleted)")
		outbound, matched := policy.ProcessPaths[filepath.Clean(executable)]
		if !matched || outbound == policy.DefaultOutbound {
			continue
		}
		content, err := os.ReadFile(filepath.Join(processDirectory, "cgroup"))
		if err != nil {
			continue
		}
		path := unifiedCgroupPath(string(content))
		if !isDedicatedApplicationCgroup(path) {
			// session-*.scope is shared by unrelated programs launched from the
			// desktop session. Marking it for one matching executable would also
			// route every other program in that session (for example Minecraft's
			// LAN bridge together with Discord). Only application-owned scopes are
			// safe units for socket-cgroup routing.
			continue
		}
		parts := strings.FieldsFunc(path, func(character rune) bool { return character == '/' })
		if len(parts) == 0 {
			continue
		}
		candidate := socketCgroup{
			Level:    len(parts),
			Path:     strings.TrimPrefix(path, "/"),
			Outbound: outbound,
		}
		key := fmt.Sprintf("%d\x00%s", candidate.Level, candidate.Path)
		if conflicts[key] {
			continue
		}
		if existing, exists := seen[key]; exists && existing.Outbound != candidate.Outbound {
			// One cgroup cannot safely receive two contradictory marks. Leaving it
			// on the profile default is safer than leaking either application's
			// traffic onto the wrong route.
			delete(seen, key)
			conflicts[key] = true
			continue
		}
		seen[key] = candidate
	}
	result := make([]socketCgroup, 0, len(seen))
	for _, cgroup := range seen {
		result = append(result, cgroup)
	}
	sort.Slice(result, func(left, right int) bool {
		if result[left].Level != result[right].Level {
			return result[left].Level < result[right].Level
		}
		if result[left].Path != result[right].Path {
			return result[left].Path < result[right].Path
		}
		return result[left].Outbound < result[right].Outbound
	})
	return result
}

func isDedicatedApplicationCgroup(path string) bool {
	clean := filepath.Clean("/" + strings.TrimPrefix(path, "/"))
	if !strings.Contains(clean, "/app.slice/") {
		return false
	}
	name := filepath.Base(clean)
	return strings.HasSuffix(name, ".scope") || strings.HasSuffix(name, ".service")
}

func unifiedCgroupPath(content string) string {
	for _, line := range strings.Split(content, "\n") {
		if strings.HasPrefix(line, "0::/") {
			return strings.TrimPrefix(line, "0::")
		}
	}
	return ""
}

func buildNFTRuleset(defaultOutbound string, cgroups []socketCgroup) string {
	var buffer bytes.Buffer
	buffer.WriteString("table inet " + regaliaBypassTable + " {\n")
	buffer.WriteString("  chain output_pre {\n")
	buffer.WriteString("    type route hook output priority -160; policy accept;\n")
	writeCgroupMarkRules(&buffer, cgroups)
	if defaultOutbound == "direct" {
		// Mark both the packet and its conntrack entry. sing-box's NFQUEUE
		// pre-matcher may replace the packet mark, while the connection mark
		// remains available to its own exclusion rules.
		buffer.WriteString("    meta mark set " + directMark + " ct mark set meta mark\n")
	}
	buffer.WriteString("  }\n")
	buffer.WriteString("  chain output_udp_post {\n")
	// sing-box's output_udp_icmp chain runs at mangle + 2 (-148) and marks
	// otherwise-unmatched UDP for the TUN. Run immediately afterwards and
	// restore the policy mark; because this is a route chain, the kernel then
	// performs routing again using Regalia's fwmark rules.
	buffer.WriteString("    type route hook output priority -147; policy accept;\n")
	buffer.WriteString("    meta l4proto != { icmp, udp, ipv6-icmp } return\n")
	writeCgroupMarkRules(&buffer, cgroups)
	if defaultOutbound == "direct" {
		buffer.WriteString("    meta mark set " + directMark + " ct mark set meta mark\n")
	}
	buffer.WriteString("  }\n")
	buffer.WriteString("}\n")
	return buffer.String()
}

func writeCgroupMarkRules(buffer *bytes.Buffer, cgroups []socketCgroup) {
	for _, cgroup := range cgroups {
		mark := directMark
		if cgroup.Outbound == "proxy" {
			mark = proxyMark
		}
		buffer.WriteString(fmt.Sprintf("    socket cgroupv2 level %d %s meta mark set %s ct mark set meta mark return\n", cgroup.Level, strconv.Quote(cgroup.Path), mark))
	}
}
