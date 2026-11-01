package network

import (
	"testing"

	"github.com/Wifx/gonetworkmanager/v2"
)

func TestBuildEthernetSharingSettings(t *testing.T) {
	settings := buildEthernetSharingSettings("enp1s0", "ordinary-uuid", true, true, nil, nil)
	connection := settings["connection"]
	if got := connection["type"]; got != "802-3-ethernet" {
		t.Fatalf("connection type = %v", got)
	}
	if got := connection["stable-id"]; got != kaskadEthernetSharingStableID {
		t.Fatalf("stable id = %v", got)
	}
	if got := connection["interface-name"]; got != "enp1s0" {
		t.Fatalf("interface = %v", got)
	}
	if got := connection["autoconnect-priority"]; got != int32(100) {
		t.Fatalf("autoconnect priority = %v", got)
	}
	if got := connection["id"]; got != kaskadEthernetSharingConnectionID+" (VPN)" {
		t.Fatalf("VPN connection id = %v", got)
	}
	if got := settings["ipv4"]["method"]; got != "shared" {
		t.Fatalf("IPv4 method = %v", got)
	}
	if got := settings["ipv4"]["never-default"]; got != true {
		t.Fatalf("IPv4 never-default = %v", got)
	}
	if got := settings["ipv6"]["method"]; got != "ignore" {
		t.Fatalf("IPv6 method = %v", got)
	}
	if got := ethernetSharingRestoreUUID(settings); got != "ordinary-uuid" {
		t.Fatalf("restore UUID = %q", got)
	}
	if !ethernetSharingVPNFromSettings(settings) {
		t.Fatal("VPN routing mode was not persisted")
	}
}

func TestBuildEthernetSharingSettingsPreservesIdentityAndRestoreProfile(t *testing.T) {
	existing := buildEthernetSharingSettings("enp1s0", "ordinary-uuid", false, false, nil, nil)
	existing["connection"]["uuid"] = "sharing-uuid"
	// GetSettings may contain legacy address arrays whose nested D-Bus type is
	// not safely round-trippable through gonetworkmanager. Rebuilding must keep
	// only Kaskad's canonical fields instead of copying those arrays back.
	existing["ipv6"]["addresses"] = []any{[]any{[]byte{0}, uint32(64), []byte{0}}}
	hardwareProfile := gonetworkmanager.ConnectionSettings{
		"802-3-ethernet": {
			"auto-negotiate":     false,
			"speed":              uint32(100),
			"duplex":             "full",
			"cloned-mac-address": "stable",
			"mtu":                uint32(1500),
			"mac-address":        []byte{0, 1, 2, 3, 4, 5},
		},
	}
	updated := buildEthernetSharingSettings("enp2s0", "", true, false, existing, hardwareProfile)
	if ethernetSharingVPNFromSettings(updated) {
		t.Fatal("direct routing mode changed to VPN")
	}
	if got := updated["connection"]["uuid"]; got != "sharing-uuid" {
		t.Fatalf("sharing UUID = %v", got)
	}
	if got := ethernetSharingRestoreUUID(updated); got != "ordinary-uuid" {
		t.Fatalf("restore UUID = %q", got)
	}
	if _, exists := updated["ipv6"]["addresses"]; exists {
		t.Fatal("legacy IPv6 address array leaked into canonical sharing profile")
	}
	if got := updated["802-3-ethernet"]["auto-negotiate"]; got != false {
		t.Fatalf("auto-negotiate = %v", got)
	}
	if got := updated["802-3-ethernet"]["speed"]; got != uint32(100) {
		t.Fatalf("speed = %v", got)
	}
	if got := updated["802-3-ethernet"]["duplex"]; got != "full" {
		t.Fatalf("duplex = %v", got)
	}
	if got := updated["802-3-ethernet"]["cloned-mac-address"]; got != "stable" {
		t.Fatalf("cloned MAC mode = %v", got)
	}
	if _, exists := updated["802-3-ethernet"]["mac-address"]; exists {
		t.Fatal("non-scalar MAC array leaked into canonical sharing profile")
	}
}

func TestCanonicalEthernetHardwareSettingsRejectsIncompleteFixedMode(t *testing.T) {
	profile := gonetworkmanager.ConnectionSettings{
		"802-3-ethernet": {
			"auto-negotiate":     false,
			"speed":              uint32(0),
			"cloned-mac-address": "stable",
		},
	}
	wired := canonicalEthernetHardwareSettings(profile)
	if _, exists := wired["auto-negotiate"]; exists {
		t.Fatal("incomplete fixed link mode was preserved")
	}
	if _, exists := wired["speed"]; exists {
		t.Fatal("zero fixed speed was preserved")
	}
	if got := wired["cloned-mac-address"]; got != "stable" {
		t.Fatalf("independent stable MAC setting = %v", got)
	}
}

func TestEthernetSharingConnectionDetectionRequiresOwnedSharedProfile(t *testing.T) {
	valid := buildEthernetSharingSettings("enp1s0", "", true, false, nil, nil)
	if !isKaskadEthernetSharingConnection(valid) {
		t.Fatal("owned shared profile was not detected")
	}

	ordinaryShared := gonetworkmanager.ConnectionSettings{
		"connection": {"type": "802-3-ethernet", "stable-id": "some-user-profile"},
		"ipv4":       {"method": "shared"},
	}
	if isKaskadEthernetSharingConnection(ordinaryShared) {
		t.Fatal("user-owned shared profile was detected as Kaskad-owned")
	}

	ownedAutomatic := buildEthernetSharingSettings("enp1s0", "", true, false, nil, nil)
	ownedAutomatic["ipv4"]["method"] = "auto"
	if isKaskadEthernetSharingConnection(ownedAutomatic) {
		t.Fatal("non-shared profile was detected as active sharing configuration")
	}
}
