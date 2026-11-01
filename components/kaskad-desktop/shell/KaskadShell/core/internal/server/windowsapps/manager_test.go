package windowsapps

import (
	"os"
	"path/filepath"
	"testing"
)

func TestStateReportsOptionalRunner(t *testing.T) {
	binDir := t.TempDir()
	t.Setenv("PATH", binDir)

	manager := &Manager{state: State{Phase: "idle"}}
	if manager.State().RunnerAvailable {
		t.Fatal("runner must be unavailable when umu-run is absent")
	}

	runner := filepath.Join(binDir, "umu-run")
	if err := os.WriteFile(runner, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatalf("create fake runner: %v", err)
	}
	if !manager.State().RunnerAvailable {
		t.Fatal("runner must be available when umu-run is executable")
	}
}
