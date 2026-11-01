package main

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/screenshot"
)

func TestResolveScreenshotFilename(t *testing.T) {
	now := time.Date(2026, time.October, 15, 14, 32, 8, 0, time.Local)
	if got := resolveScreenshotFilename("KASKAD_{date}_{time}", screenshot.FormatPNG, now); got != "KASKAD_2026-10-15_14-32-08.png" {
		t.Fatalf("unexpected expanded filename: %q", got)
	}
	if got := resolveScreenshotFilename("../unsafe", screenshot.FormatJPEG, now); got != "unsafe.jpg" {
		t.Fatalf("filename must stay inside the configured folder: %q", got)
	}
}

func TestAvailableScreenshotPathDoesNotOverwrite(t *testing.T) {
	directory := t.TempDir()
	first := filepath.Join(directory, "capture.png")
	if err := os.WriteFile(first, []byte("existing"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := availableScreenshotPath(directory, "capture.png"); got != filepath.Join(directory, "capture_2.png") {
		t.Fatalf("unexpected collision path: %q", got)
	}
}
