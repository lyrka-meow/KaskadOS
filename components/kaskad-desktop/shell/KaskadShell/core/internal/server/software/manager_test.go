package software

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestProgressFromLine(t *testing.T) {
	tests := []struct {
		line string
		want int
		ok   bool
	}{
		{"(1/2) installing kitty [################] 73%", 73, true},
		{"Installing… ████████████████████ 100%", 100, true},
		{"download 7% verify 42%", 42, true},
		{"Сборка AUR-пакета: kitty", 0, false},
	}
	for _, test := range tests {
		got, ok := progressFromLine(test.line)
		if got != test.want || ok != test.ok {
			t.Fatalf("progressFromLine(%q) = (%d, %v), want (%d, %v)", test.line, got, ok, test.want, test.ok)
		}
	}
}

func TestStageFromLine(t *testing.T) {
	for line, want := range map[string]string{
		"Получение исходников AUR: kitty": "Загрузка исходников",
		"downloading kitty":      "Загрузка пакета",
		"(1/1) installing kitty": "Установка пакета",
		"Проверка ключей":        "Проверка пакета",
		"Сборка AUR-пакета":      "Сборка пакета",
	} {
		if got := stageFromLine(line); got != want {
			t.Fatalf("stageFromLine(%q) = %q, want %q", line, got, want)
		}
	}
}

func TestOperationProgressIsMonotonicAndOperationWide(t *testing.T) {
	progress, known := operationProgress(5, "Загрузка пакета", 50, true)
	if !known || progress != 39 {
		t.Fatalf("download progress = (%d, %v), want (39, true)", progress, known)
	}

	progress, known = operationProgress(progress, "Проверка пакета", 20, true)
	if !known || progress != 72 {
		t.Fatalf("check progress = (%d, %v), want (72, true)", progress, known)
	}

	// A package manager can restart its own percentage for the next file. The
	// user-facing operation must never move backwards.
	progress, known = operationProgress(progress, "Загрузка пакета", 2, true)
	if !known || progress != 72 {
		t.Fatalf("regressed progress = (%d, %v), want (72, true)", progress, known)
	}

	progress, known = operationProgress(progress, "Установка пакета", 50, true)
	if !known || progress != 90 {
		t.Fatalf("install progress = (%d, %v), want (90, true)", progress, known)
	}
}

func TestDesktopEntryApplicationDirsFollowXDG(t *testing.T) {
	dataHome := t.TempDir()
	dataOne := t.TempDir()
	dataTwo := t.TempDir()
	t.Setenv("XDG_DATA_HOME", dataHome)
	t.Setenv("XDG_DATA_DIRS", dataOne+":"+dataTwo)

	want := []string{
		filepath.Join(dataHome, "applications"),
		filepath.Join(dataOne, "applications"),
		filepath.Join(dataTwo, "applications"),
	}
	if got := desktopEntryApplicationDirs(); !reflect.DeepEqual(got, want) {
		t.Fatalf("desktop entry directories = %v, want %v", got, want)
	}
}

func TestNotifyDesktopEntryMonitorsLeavesNoMarker(t *testing.T) {
	dataHome := t.TempDir()
	dataDir := t.TempDir()
	t.Setenv("XDG_DATA_HOME", dataHome)
	t.Setenv("XDG_DATA_DIRS", dataDir)

	notifyDesktopEntryMonitors()
	for _, dir := range desktopEntryApplicationDirs() {
		entries, err := os.ReadDir(dir)
		if err != nil {
			t.Fatalf("read refresh directory %q: %v", dir, err)
		}
		if len(entries) != 0 {
			t.Fatalf("refresh directory %q contains leftover files: %v", dir, entries)
		}
	}
}

func TestCleanTerminalLine(t *testing.T) {
	line := "\x1b[1;32m chromium 37%\x1b[0m\r"
	if got := cleanTerminalLine(line); got != "chromium 37%" {
		t.Fatalf("cleanTerminalLine() = %q", got)
	}
}

func TestRunLoggedTerminalExposesCarriageReturnProgress(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	var lines []string
	err := runLoggedTerminal(ctx, func(line string) {
		line = cleanTerminalLine(line)
		if line != "" {
			lines = append(lines, line)
		}
	}, "sh", "-c", `printf '\033[32mdownloading chromium 10%%\033[0m\rdownloading chromium 74%%\rdownloading chromium 100%%\n'`)
	if err != nil {
		t.Fatal(err)
	}
	joined := strings.Join(lines, "\n")
	for _, want := range []string{"10%", "74%", "100%"} {
		if !strings.Contains(joined, want) {
			t.Fatalf("terminal progress %s missing from %q", want, joined)
		}
	}
}

func TestOperationsAreQueuedAndRunInOrder(t *testing.T) {
	manager := &Manager{state: OperationState{Phase: PhaseIdle}}
	firstStarted := make(chan struct{})
	releaseFirst := make(chan struct{})
	done := make(chan struct{})
	var order []string

	if err := manager.start("install", Item{ID: "one", PackageName: "one", Source: SourcePacman}, func(context.Context, func(string)) error {
		close(firstStarted)
		<-releaseFirst
		order = append(order, "one")
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	<-firstStarted
	if err := manager.start("install", Item{ID: "two", PackageName: "two", Source: SourceFlatpak}, func(context.Context, func(string)) error {
		order = append(order, "two")
		close(done)
		return nil
	}); err != nil {
		t.Fatal(err)
	}

	state := manager.State()
	if len(state.Queue) != 1 || state.Queue[0].Item.PackageName != "two" || state.Total != 2 {
		t.Fatalf("unexpected queued state: %#v", state)
	}
	close(releaseFirst)
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("queued operation did not start")
	}

	deadline := time.Now().Add(2 * time.Second)
	for manager.State().Phase != PhaseComplete && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	state = manager.State()
	if !reflect.DeepEqual(order, []string{"one", "two"}) {
		t.Fatalf("operation order = %v", order)
	}
	if state.Completed != 2 || state.Total != 2 || state.Failed != 0 || len(state.Queue) != 0 {
		t.Fatalf("unexpected final state: %#v", state)
	}
}
