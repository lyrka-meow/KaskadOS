package main

import "testing"

func TestKaskadOSDoesNotExposeUnsafeKaskadRestart(t *testing.T) {
	commands := getCommonCommands()
	foundRun := false
	for _, command := range commands {
		switch command.Name() {
		case "restart", "restart-detached":
			t.Fatalf("unsafe lifecycle command %q must not be exposed", command.Name())
		case "run":
			foundRun = true
		}
	}
	if !foundRun {
		t.Fatal("internal Kaskad run command is required by the KaskadOS session")
	}
}
