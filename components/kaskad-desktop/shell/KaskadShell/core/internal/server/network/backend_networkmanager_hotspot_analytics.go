package network

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"golang.org/x/net/publicsuffix"
)

const (
	hotspotAnalyticsRetentionDays = 30
	hotspotAnalyticsMaxSessions   = 60
	hotspotAnalyticsMaxDomains    = 200
	hotspotAnalyticsLogPath       = "/run/kaskados-hotspot-queries.log"
	hotspotAnalyticsMaxRawLog     = 4 * 1024 * 1024
)

var hotspotDNSQueryPattern = regexp.MustCompile(`(?i)query\[[^]]+\]\s+([^\s]+)\s+from\s+([0-9a-f:.]+)`)

type HotspotDomainAnalytics struct {
	Domain                 string `json:"domain"`
	Queries                uint64 `json:"queries"`
	FirstSeen              int64  `json:"firstSeen"`
	LastSeen               int64  `json:"lastSeen"`
	EstimatedActiveSeconds uint64 `json:"estimatedActiveSeconds"`
}

type HotspotSessionAnalytics struct {
	ID                     string                   `json:"id"`
	MAC                    string                   `json:"mac"`
	IP                     string                   `json:"ip,omitempty"`
	AutoName               string                   `json:"autoName,omitempty"`
	Vendor                 string                   `json:"vendor,omitempty"`
	RandomizedMAC          bool                     `json:"randomizedMAC"`
	StartedAt              int64                    `json:"startedAt"`
	EndedAt                int64                    `json:"endedAt,omitempty"`
	RxBytes                uint64                   `json:"rxBytes"`
	TxBytes                uint64                   `json:"txBytes"`
	Queries                uint64                   `json:"queries"`
	EstimatedActiveSeconds uint64                   `json:"estimatedActiveSeconds"`
	LastActivityAt         int64                    `json:"lastActivityAt,omitempty"`
	LastConnectedSeconds   uint64                   `json:"lastConnectedSeconds,omitempty"`
	LastRawRxBytes         uint64                   `json:"lastRawRxBytes,omitempty"`
	LastRawTxBytes         uint64                   `json:"lastRawTxBytes,omitempty"`
	RxBaseline             uint64                   `json:"rxBaseline,omitempty"`
	TxBaseline             uint64                   `json:"txBaseline,omitempty"`
	Domains                []HotspotDomainAnalytics `json:"domains"`
}

type HotspotDeviceAnalytics struct {
	MAC                    string                    `json:"mac"`
	Name                   string                    `json:"name,omitempty"`
	AutoName               string                    `json:"autoName,omitempty"`
	Vendor                 string                    `json:"vendor,omitempty"`
	RandomizedMAC          bool                      `json:"randomizedMAC"`
	SessionsCount          int                       `json:"sessionsCount"`
	Queries                uint64                    `json:"queries"`
	RxBytes                uint64                    `json:"rxBytes"`
	TxBytes                uint64                    `json:"txBytes"`
	EstimatedActiveSeconds uint64                    `json:"estimatedActiveSeconds"`
	LastSeen               int64                     `json:"lastSeen"`
	Sessions               []HotspotSessionAnalytics `json:"sessions"`
}

type HotspotAnalyticsResponse struct {
	Enabled       bool                     `json:"enabled"`
	RetentionDays int                      `json:"retentionDays"`
	MaxSessions   int                      `json:"maxSessionsPerDevice"`
	MaxDomains    int                      `json:"maxDomainsPerSession"`
	StorageBytes  int64                    `json:"storageBytes"`
	Devices       []HotspotDeviceAnalytics `json:"devices"`
}

type hotspotAnalyticsStore struct {
	Version       int                       `json:"version"`
	Enabled       bool                      `json:"enabled"`
	RetentionDays int                       `json:"retentionDays"`
	LogOffset     int64                     `json:"logOffset"`
	Sessions      []HotspotSessionAnalytics `json:"sessions"`
}

func hotspotAnalyticsPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "KaskadShell", "hotspot-analytics.json"), nil
}

func loadHotspotAnalyticsStore() (*hotspotAnalyticsStore, error) {
	store := &hotspotAnalyticsStore{Version: 1, RetentionDays: hotspotAnalyticsRetentionDays}
	path, err := hotspotAnalyticsPath()
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return store, nil
	}
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(data, store); err != nil {
		return nil, err
	}
	if store.RetentionDays <= 0 {
		store.RetentionDays = hotspotAnalyticsRetentionDays
	}
	return store, nil
}

func saveHotspotAnalyticsStore(store *hotspotAnalyticsStore) error {
	path, err := hotspotAnalyticsPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(store, "", "  ")
	if err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".hotspot-analytics-*")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0600); err != nil {
		_ = temporary.Close()
		return err
	}
	if _, err := temporary.Write(data); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	return os.Rename(temporaryPath, path)
}

func (b *NetworkManagerBackend) ensureHotspotAnalyticsLocked() (*hotspotAnalyticsStore, error) {
	if b.analyticsStore != nil {
		return b.analyticsStore, nil
	}
	store, err := loadHotspotAnalyticsStore()
	if err != nil {
		return nil, err
	}
	b.analyticsStore = store
	return store, nil
}

func (b *NetworkManagerBackend) saveHotspotAnalyticsLocked(force bool) error {
	if !b.analyticsDirty {
		return nil
	}
	if !force && !b.analyticsLastSave.IsZero() && time.Since(b.analyticsLastSave) < 30*time.Second {
		return nil
	}
	if err := saveHotspotAnalyticsStore(b.analyticsStore); err != nil {
		return err
	}
	b.analyticsDirty = false
	b.analyticsLastSave = time.Now()
	return nil
}

func (b *NetworkManagerBackend) flushHotspotAnalytics() {
	b.analyticsMutex.Lock()
	defer b.analyticsMutex.Unlock()
	if b.analyticsStore != nil {
		_ = b.saveHotspotAnalyticsLocked(true)
	}
}

func (b *NetworkManagerBackend) startHotspotAnalyticsCollector() {
	b.analyticsWG.Add(1)
	go func() {
		defer b.analyticsWG.Done()
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		_, _, _ = b.ListHotspotClients()
		for {
			select {
			case <-ticker.C:
				b.refreshHotspotHealth()
				_, _, _ = b.ListHotspotClients()
			case <-b.stopChan:
				return
			}
		}
	}()
}

func currentHotspotLogSize() int64 {
	info, err := os.Stat(hotspotAnalyticsLogPath)
	if err != nil {
		return 0
	}
	return info.Size()
}

func hotspotLeaseIPToMAC() map[string]string {
	result := map[string]string{}
	for _, path := range []string{"/run/kaskados-hotspot/dnsmasq.leases", "/var/lib/misc/dnsmasq.leases"} {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(data), "\n") {
			fields := strings.Fields(line)
			if len(fields) < 3 || net.ParseIP(fields[2]) == nil {
				continue
			}
			if mac, err := normalizeHotspotMAC(fields[1]); err == nil {
				result[fields[2]] = mac
			}
		}
	}
	return result
}

func hotspotAnalyticsDomain(value string) string {
	value = strings.ToLower(strings.TrimSuffix(strings.TrimSpace(value), "."))
	if value == "" || net.ParseIP(value) != nil || strings.HasSuffix(value, ".arpa") || strings.HasSuffix(value, ".local") {
		return ""
	}
	if domain, err := publicsuffix.EffectiveTLDPlusOne(value); err == nil {
		return domain
	}
	return value
}

func (b *NetworkManagerBackend) readHotspotDNSQueriesLocked(store *hotspotAnalyticsStore, ipToMAC map[string]string, now int64) (bool, error) {
	file, err := os.Open(hotspotAnalyticsLogPath)
	if os.IsPermission(err) {
		if grantErr := runHotspotInterfaceControl("grant-analytics-log"); grantErr == nil {
			file, err = os.Open(hotspotAnalyticsLogPath)
		}
	}
	if os.IsNotExist(err) || os.IsPermission(err) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return false, err
	}
	if info.Size() < store.LogOffset {
		store.LogOffset = 0
	}
	if _, err := file.Seek(store.LogOffset, io.SeekStart); err != nil {
		return false, err
	}
	reader := bufio.NewReader(io.LimitReader(file, 8*1024*1024))
	changed := false
	for {
		line, readErr := reader.ReadString('\n')
		store.LogOffset += int64(len(line))
		matches := hotspotDNSQueryPattern.FindStringSubmatch(line)
		if len(matches) == 3 {
			domain := hotspotAnalyticsDomain(matches[1])
			mac := ipToMAC[matches[2]]
			if domain != "" && mac != "" {
				if session := activeHotspotAnalyticsSession(store, mac); session != nil {
					recordHotspotDomain(session, domain, now)
					changed = true
				}
			}
		}
		if readErr != nil {
			if readErr != io.EOF {
				return changed, readErr
			}
			break
		}
	}
	return changed, nil
}

func activeHotspotAnalyticsSession(store *hotspotAnalyticsStore, mac string) *HotspotSessionAnalytics {
	for i := len(store.Sessions) - 1; i >= 0; i-- {
		if store.Sessions[i].MAC == mac && store.Sessions[i].EndedAt == 0 {
			return &store.Sessions[i]
		}
	}
	return nil
}

func recordHotspotDomain(session *HotspotSessionAnalytics, domain string, now int64) {
	session.Queries++
	if session.LastActivityAt == 0 || now-session.LastActivityAt > 5*60*1000 {
		session.EstimatedActiveSeconds += 60
	} else if delta := uint64((now - session.LastActivityAt) / 1000); delta > 0 {
		if delta > 60 {
			delta = 60
		}
		session.EstimatedActiveSeconds += delta
	}
	session.LastActivityAt = now
	for i := range session.Domains {
		entry := &session.Domains[i]
		if entry.Domain != domain {
			continue
		}
		entry.Queries++
		if entry.LastSeen == 0 || now-entry.LastSeen > 5*60*1000 {
			entry.EstimatedActiveSeconds += 60
		} else if delta := uint64((now - entry.LastSeen) / 1000); delta > 0 {
			if delta > 60 {
				delta = 60
			}
			entry.EstimatedActiveSeconds += delta
		}
		entry.LastSeen = now
		return
	}
	session.Domains = append(session.Domains, HotspotDomainAnalytics{
		Domain: domain, Queries: 1, FirstSeen: now, LastSeen: now, EstimatedActiveSeconds: 60,
	})
}

func (b *NetworkManagerBackend) observeHotspotAnalytics(clients []HotspotClient) {
	b.analyticsMutex.Lock()
	store, err := b.ensureHotspotAnalyticsLocked()
	if err != nil {
		b.analyticsMutex.Unlock()
		return
	}
	if !store.Enabled {
		b.analyticsMutex.Unlock()
		if currentHotspotLogSize() >= hotspotAnalyticsMaxRawLog {
			_ = runHotspotInterfaceControl("reset-analytics-log")
		}
		return
	}
	now := time.Now().UnixMilli()
	changed := false
	seen := make(map[string]bool, len(clients))
	ipToMAC := hotspotLeaseIPToMAC()
	for _, client := range clients {
		seen[client.MAC] = true
		if client.IP != "" {
			ipToMAC[client.IP] = client.MAC
		}
		session := activeHotspotAnalyticsSession(store, client.MAC)
		start := now - int64(client.ConnectedSeconds)*1000
		if session != nil && client.ConnectedSeconds+10 < session.LastConnectedSeconds {
			session.EndedAt = now
			session = nil
			changed = true
		}
		if session == nil {
			session = &HotspotSessionAnalytics{
				ID: fmt.Sprintf("%d-%s", now, strings.ReplaceAll(client.MAC, ":", "")), MAC: client.MAC,
				IP: client.IP, AutoName: client.AutoName, Vendor: client.Vendor, RandomizedMAC: client.RandomizedMAC,
				StartedAt: start,
			}
			store.Sessions = append(store.Sessions, *session)
			session = &store.Sessions[len(store.Sessions)-1]
			changed = true
		}
		session.IP = client.IP
		session.AutoName = client.AutoName
		session.Vendor = client.Vendor
		session.RandomizedMAC = client.RandomizedMAC
		session.LastRawRxBytes = client.RxBytes
		session.LastRawTxBytes = client.TxBytes
		if client.RxBytes >= session.RxBaseline {
			session.RxBytes = client.RxBytes - session.RxBaseline
		}
		if client.TxBytes >= session.TxBaseline {
			session.TxBytes = client.TxBytes - session.TxBaseline
		}
		session.LastConnectedSeconds = client.ConnectedSeconds
		changed = true
	}
	for i := range store.Sessions {
		if store.Sessions[i].EndedAt == 0 && !seen[store.Sessions[i].MAC] {
			store.Sessions[i].EndedAt = now
			changed = true
		}
	}
	queriesChanged, _ := b.readHotspotDNSQueriesLocked(store, ipToMAC, now)
	b.pruneHotspotAnalyticsLocked(store, now)
	if changed || queriesChanged {
		b.analyticsDirty = true
	}
	_ = b.saveHotspotAnalyticsLocked(false)
	shouldResetLog := store.LogOffset >= hotspotAnalyticsMaxRawLog && currentHotspotLogSize() >= hotspotAnalyticsMaxRawLog
	b.analyticsMutex.Unlock()
	if shouldResetLog && runHotspotInterfaceControl("reset-analytics-log") == nil {
		b.analyticsMutex.Lock()
		if b.analyticsStore != nil {
			b.analyticsStore.LogOffset = 0
			b.analyticsDirty = true
		}
		b.analyticsMutex.Unlock()
	}
}

func (b *NetworkManagerBackend) pruneHotspotAnalyticsLocked(store *hotspotAnalyticsStore, now int64) {
	cutoff := now - int64(store.RetentionDays)*24*60*60*1000
	kept := make([]HotspotSessionAnalytics, 0, len(store.Sessions))
	counts := map[string]int{}
	for i := len(store.Sessions) - 1; i >= 0; i-- {
		session := store.Sessions[i]
		seenAt := session.EndedAt
		if seenAt == 0 {
			seenAt = now
		}
		if seenAt < cutoff || counts[session.MAC] >= hotspotAnalyticsMaxSessions {
			continue
		}
		counts[session.MAC]++
		if len(session.Domains) > hotspotAnalyticsMaxDomains {
			sort.Slice(session.Domains, func(a, b int) bool { return session.Domains[a].LastSeen > session.Domains[b].LastSeen })
			session.Domains = session.Domains[:hotspotAnalyticsMaxDomains]
		}
		kept = append(kept, session)
	}
	for i, j := 0, len(kept)-1; i < j; i, j = i+1, j-1 {
		kept[i], kept[j] = kept[j], kept[i]
	}
	store.Sessions = kept
}

func (b *NetworkManagerBackend) GetHotspotAnalytics() (HotspotAnalyticsResponse, error) {
	b.analyticsMutex.Lock()
	defer b.analyticsMutex.Unlock()
	store, err := b.ensureHotspotAnalyticsLocked()
	if err != nil {
		return HotspotAnalyticsResponse{}, err
	}
	names, _ := loadHotspotNames()
	devicesByMAC := map[string]*HotspotDeviceAnalytics{}
	for _, session := range store.Sessions {
		device := devicesByMAC[session.MAC]
		if device == nil {
			device = &HotspotDeviceAnalytics{MAC: session.MAC, Name: names[session.MAC]}
			devicesByMAC[session.MAC] = device
		}
		device.AutoName = session.AutoName
		device.Vendor = session.Vendor
		device.RandomizedMAC = session.RandomizedMAC
		device.SessionsCount++
		device.Queries += session.Queries
		device.RxBytes += session.RxBytes
		device.TxBytes += session.TxBytes
		device.EstimatedActiveSeconds += session.EstimatedActiveSeconds
		seenAt := session.EndedAt
		if seenAt == 0 {
			seenAt = time.Now().UnixMilli()
		}
		if seenAt > device.LastSeen {
			device.LastSeen = seenAt
		}
		copySession := session
		copySession.Domains = append([]HotspotDomainAnalytics(nil), session.Domains...)
		sort.Slice(copySession.Domains, func(i, j int) bool {
			if copySession.Domains[i].EstimatedActiveSeconds == copySession.Domains[j].EstimatedActiveSeconds {
				return copySession.Domains[i].Queries > copySession.Domains[j].Queries
			}
			return copySession.Domains[i].EstimatedActiveSeconds > copySession.Domains[j].EstimatedActiveSeconds
		})
		device.Sessions = append(device.Sessions, copySession)
	}
	response := HotspotAnalyticsResponse{
		Enabled: store.Enabled, RetentionDays: store.RetentionDays,
		MaxSessions: hotspotAnalyticsMaxSessions, MaxDomains: hotspotAnalyticsMaxDomains,
	}
	if path, pathErr := hotspotAnalyticsPath(); pathErr == nil {
		if info, statErr := os.Stat(path); statErr == nil {
			response.StorageBytes = info.Size()
		}
	}
	for _, device := range devicesByMAC {
		sort.Slice(device.Sessions, func(i, j int) bool { return device.Sessions[i].StartedAt > device.Sessions[j].StartedAt })
		response.Devices = append(response.Devices, *device)
	}
	sort.Slice(response.Devices, func(i, j int) bool { return response.Devices[i].LastSeen > response.Devices[j].LastSeen })
	return response, nil
}

func (b *NetworkManagerBackend) SetHotspotAnalyticsEnabled(enabled bool) error {
	b.analyticsMutex.Lock()
	defer b.analyticsMutex.Unlock()
	store, err := b.ensureHotspotAnalyticsLocked()
	if err != nil {
		return err
	}
	if store.Enabled == enabled {
		return nil
	}
	store.Enabled = enabled
	store.LogOffset = currentHotspotLogSize()
	if !enabled {
		now := time.Now().UnixMilli()
		for i := range store.Sessions {
			if store.Sessions[i].EndedAt == 0 {
				store.Sessions[i].EndedAt = now
			}
		}
		_ = runHotspotInterfaceControl("reset-analytics-log")
	}
	b.analyticsDirty = true
	return b.saveHotspotAnalyticsLocked(true)
}

func (b *NetworkManagerBackend) DeleteHotspotAnalyticsSession(value, sessionID string) error {
	mac, err := normalizeHotspotMAC(value)
	if err != nil {
		return err
	}
	b.analyticsMutex.Lock()
	defer b.analyticsMutex.Unlock()
	store, err := b.ensureHotspotAnalyticsLocked()
	if err != nil {
		return err
	}
	filtered := store.Sessions[:0]
	for _, session := range store.Sessions {
		if session.MAC != mac || session.ID != sessionID {
			filtered = append(filtered, session)
		}
	}
	store.Sessions = filtered
	b.analyticsDirty = true
	return b.saveHotspotAnalyticsLocked(true)
}

func (b *NetworkManagerBackend) ClearCurrentHotspotAnalytics(value string) error {
	mac, err := normalizeHotspotMAC(value)
	if err != nil {
		return err
	}
	b.analyticsMutex.Lock()
	defer b.analyticsMutex.Unlock()
	store, err := b.ensureHotspotAnalyticsLocked()
	if err != nil {
		return err
	}
	if session := activeHotspotAnalyticsSession(store, mac); session != nil {
		now := time.Now().UnixMilli()
		session.StartedAt = now
		session.RxBytes = 0
		session.TxBytes = 0
		session.RxBaseline = session.LastRawRxBytes
		session.TxBaseline = session.LastRawTxBytes
		session.Queries = 0
		session.EstimatedActiveSeconds = 0
		session.LastActivityAt = 0
		session.Domains = nil
	}
	b.analyticsDirty = true
	return b.saveHotspotAnalyticsLocked(true)
}

func (b *NetworkManagerBackend) ClearHotspotAnalyticsDevice(value string) error {
	mac, err := normalizeHotspotMAC(value)
	if err != nil {
		return err
	}
	b.analyticsMutex.Lock()
	defer b.analyticsMutex.Unlock()
	store, err := b.ensureHotspotAnalyticsLocked()
	if err != nil {
		return err
	}
	filtered := store.Sessions[:0]
	for _, session := range store.Sessions {
		if session.MAC != mac {
			filtered = append(filtered, session)
		}
	}
	store.Sessions = filtered
	b.analyticsDirty = true
	return b.saveHotspotAnalyticsLocked(true)
}

func (b *NetworkManagerBackend) ClearAllHotspotAnalytics() error {
	b.analyticsMutex.Lock()
	defer b.analyticsMutex.Unlock()
	store, err := b.ensureHotspotAnalyticsLocked()
	if err != nil {
		return err
	}
	store.Sessions = nil
	store.LogOffset = currentHotspotLogSize()
	b.analyticsDirty = true
	return b.saveHotspotAnalyticsLocked(true)
}
