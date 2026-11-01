package screenshot

import (
	"fmt"
	"io"
	"os"

	"github.com/godbus/dbus/v5"
)

const (
	kaskadScreenshotService   = "org.kde.KWin.ScreenShot2"
	kaskadScreenshotPath      = dbus.ObjectPath("/org/kde/KWin/ScreenShot2")
	kaskadScreenshotInterface = "org.kde.KWin.ScreenShot2"
	qImageFormatRGB32         = uint32(4)
	qImageFormatARGB32        = uint32(5)
	qImageFormatARGB32Premul  = uint32(6)
)

func (s *Screenshoter) captureKaskadActiveWindow() (*CaptureResult, error) {
	options := s.kaskadCaptureOptions()
	options["include-decoration"] = dbus.MakeVariant(true)
	options["include-shadow"] = dbus.MakeVariant(false)
	return captureKaskadRaw("CaptureActiveWindow", options)
}

func (s *Screenshoter) captureKaskadScreen(output *WaylandOutput) (*CaptureResult, error) {
	result, err := captureKaskadRaw("CaptureScreen", output.name, s.kaskadCaptureOptions())
	if err != nil {
		return nil, err
	}
	result.Region = Region{
		X: output.x, Y: output.y,
		Width: output.width, Height: output.height,
		Output: output.name,
	}
	return result, nil
}

func (s *Screenshoter) captureKaskadArea(region Region) (*CaptureResult, error) {
	result, err := captureKaskadRaw(
		"CaptureArea",
		region.X,
		region.Y,
		region.Width,
		region.Height,
		s.kaskadCaptureOptions(),
	)
	if err != nil {
		return nil, err
	}
	result.Region = region
	return result, nil
}

func (s *Screenshoter) kaskadCaptureOptions() map[string]dbus.Variant {
	return map[string]dbus.Variant{
		"include-cursor":    dbus.MakeVariant(s.config.Cursor == CursorOn),
		"native-resolution": dbus.MakeVariant(true),
	}
}

func captureKaskadRaw(method string, arguments ...any) (*CaptureResult, error) {
	reader, writer, err := os.Pipe()
	if err != nil {
		return nil, fmt.Errorf("create screenshot pipe: %w", err)
	}
	defer reader.Close()

	conn, err := dbus.SessionBus()
	if err != nil {
		writer.Close()
		return nil, fmt.Errorf("connect to session bus: %w", err)
	}
	arguments = append(arguments, dbus.UnixFD(writer.Fd()))

	var attributes map[string]dbus.Variant
	call := conn.Object(kaskadScreenshotService, kaskadScreenshotPath).
		Call(kaskadScreenshotInterface+"."+method, 0, arguments...)
	writer.Close()
	if call.Err != nil {
		return nil, fmt.Errorf("Kaskad screenshot %s: %w", method, call.Err)
	}
	if err := call.Store(&attributes); err != nil {
		return nil, fmt.Errorf("decode Kaskad screenshot metadata: %w", err)
	}

	width := int(variantNumber(attributes["width"]))
	height := int(variantNumber(attributes["height"]))
	stride := int(variantNumber(attributes["stride"]))
	imageFormat := uint32(variantNumber(attributes["format"]))
	if width <= 0 || height <= 0 || stride < width*4 {
		return nil, fmt.Errorf("invalid Kaskad screenshot dimensions %dx%d, stride %d", width, height, stride)
	}

	pixelFormat := FormatARGB8888
	switch imageFormat {
	case qImageFormatRGB32:
		pixelFormat = FormatXRGB8888
	case qImageFormatARGB32, qImageFormatARGB32Premul:
		pixelFormat = FormatARGB8888
	default:
		return nil, fmt.Errorf("unsupported Kaskad screenshot image format %d", imageFormat)
	}

	buffer, err := CreateShmBuffer(width, height, stride)
	if err != nil {
		return nil, fmt.Errorf("create screenshot buffer: %w", err)
	}
	if _, err := io.ReadFull(reader, buffer.Data()); err != nil {
		buffer.Close()
		return nil, fmt.Errorf("read Kaskad screenshot pixels: %w", err)
	}
	buffer.Format = pixelFormat

	scale := variantNumber(attributes["scale"])
	if scale <= 0 {
		scale = 1
	}
	return &CaptureResult{
		Buffer: buffer,
		Format: uint32(pixelFormat),
		Scale:  scale,
	}, nil
}
