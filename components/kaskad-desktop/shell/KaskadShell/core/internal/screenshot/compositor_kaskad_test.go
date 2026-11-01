package screenshot

import (
	"testing"

	"github.com/godbus/dbus/v5"
)

func TestKaskadWindowGeometry(t *testing.T) {
	window := map[string]dbus.Variant{
		"output": dbus.MakeVariant("DP-1"),
		"geometry": dbus.MakeVariant(map[string]dbus.Variant{
			"x":      dbus.MakeVariant(float64(-120)),
			"y":      dbus.MakeVariant(float64(48)),
			"width":  dbus.MakeVariant(float64(1280)),
			"height": dbus.MakeVariant(float64(720)),
		}),
	}

	geometry, err := kaskadWindowGeometry(window)
	if err != nil {
		t.Fatalf("decode Kaskad window geometry: %v", err)
	}
	if geometry.X != -120 || geometry.Y != 48 || geometry.Width != 1280 || geometry.Height != 720 || geometry.Output != "DP-1" {
		t.Fatalf("unexpected geometry: %+v", geometry)
	}
}

func TestKaskadWindowGeometryRejectsMissingWindow(t *testing.T) {
	if _, err := kaskadWindowGeometry(nil); err == nil {
		t.Fatal("missing active window must return an error")
	}
}
