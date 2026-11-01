package main

import (
	"context"
	"fmt"
	"os"

	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/config"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/log"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/shellembed"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/third_party/kaskadgo/shellapp"
)

var shellApp = shellapp.New(shellapp.Config{
	ID:        "kaskad-shell",
	EnvPrefix: "KASKAD",
	QSAppID:   "org.kaskados.Shell",
	Version:   Version,
	Embedded:  embeddedShell{},
	Boot:      bootBackend,
	PreLaunch: preLaunch,
	ExtraEnv:  kaskadShellExtraEnv,
	OnUIExit:  logStartupFailure,
})

type embeddedShell struct{}

func (embeddedShell) Available() bool { return shellembed.Available() }

func (embeddedShell) Extract(baseDir string) (string, error) { return shellembed.Extract(baseDir) }

func (embeddedShell) Prune(baseDir, keep string) { shellembed.Prune(baseDir, keep) }

type kaskadShellBackend struct {
	srv  *server.Server
	done chan error
}

func (b *kaskadShellBackend) SocketPath() string { return b.srv.SocketPath() }

func (b *kaskadShellBackend) Close() { b.srv.Close() }

func (b *kaskadShellBackend) Done() <-chan error { return b.done }

func bootBackend(ctx context.Context) (shellapp.Backend, error) {
	config.CleanupStrayHyprlandConfFile(log.Infof)
	server.CLIVersion = Version

	srv := server.New()
	if err := srv.Listen(); err != nil {
		return nil, err
	}

	backend := &kaskadShellBackend{srv: srv, done: make(chan error, 1)}
	go func() {
		defer func() {
			if r := recover(); r != nil {
				backend.done <- fmt.Errorf("server panic: %v", r)
			}
		}()
		backend.done <- srv.Serve(false)
	}()

	return backend, nil
}

func preLaunch() {
	go printASCII()
	ensureFontCache()
}

func kaskadShellExtraEnv(string) []string {
	var env []string
	if selfPath, err := os.Executable(); err == nil {
		env = append(env, "KASKAD_EXECUTABLE="+selfPath)
	}
	if os.Getenv("QSG_USE_SIMPLE_ANIMATION_DRIVER") == "" {
		env = append(env, "QSG_USE_SIMPLE_ANIMATION_DRIVER=1")
	}
	return env
}
