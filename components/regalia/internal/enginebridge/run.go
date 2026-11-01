package enginebridge

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"sync"
	"syscall"
	"time"

	"github.com/lyrka-meow/KaskadOS/components/regalia/internal/engineconfig"
)

const maxEngineLogSize = 1024 * 1024

type boundedLog struct {
	file *os.File
	mu   sync.Mutex
}

func (log *boundedLog) Write(content []byte) (int, error) {
	log.mu.Lock()
	defer log.mu.Unlock()
	info, err := log.file.Stat()
	if err != nil {
		return 0, err
	}
	if info.Size()+int64(len(content)) > maxEngineLogSize {
		if err := log.file.Truncate(0); err != nil {
			return 0, err
		}
	}
	return log.file.Write(content)
}

func (log *boundedLog) WriteString(content string) (int, error) {
	return log.Write([]byte(content))
}

func (log *boundedLog) Close() error {
	return log.file.Close()
}

func Run(configPath, binaryPath, logPath string) error {
	configuration, err := readPrivateConfiguration(configPath)
	if err != nil {
		return err
	}
	if err := engineconfig.Validate(configuration); err != nil {
		return fmt.Errorf("unsafe engine configuration: %w", err)
	}
	if err := validateSystemBinary(binaryPath); err != nil {
		return err
	}
	if err := check(binaryPath, configuration); err != nil {
		return err
	}
	logFile, err := openPrivateLog(logPath)
	if err != nil {
		return err
	}
	defer logFile.Close()
	routing, err := newRoutingController(configuration, logFile)
	if err != nil {
		return fmt.Errorf("prepare packet routing: %w", err)
	}
	// Install packet policy before sing-box creates the TUN. Otherwise packets
	// emitted during engine startup can be captured before the bypass exists.
	if err := routing.refresh(); err != nil {
		return fmt.Errorf("install packet routing: %w", err)
	}
	engineStarted := false
	defer func() {
		if !engineStarted {
			routing.remove()
		}
	}()

	command := exec.Command(binaryPath, "run", "--disable-color", "-c", "stdin")
	command.Stdin = bytes.NewReader(configuration)
	command.Stdout = logFile
	command.Stderr = logFile
	if err := command.Start(); err != nil {
		return fmt.Errorf("start sing-box: %w", err)
	}
	engineStarted = true
	routingContext, stopRouting := context.WithCancel(context.Background())
	routingDone := make(chan struct{})
	go func() {
		defer close(routingDone)
		routing.Run(routingContext)
	}()
	defer func() {
		stopRouting()
		<-routingDone
	}()

	// systemd stops only this bridge process first (KillMode=mixed). Forward the
	// shutdown signal to sing-box ourselves and wait for it to remove its TUN,
	// policy-routing and nftables state. Signalling the whole cgroup at once can
	// terminate the bridge before sing-box has completed that cleanup, leaving
	// traffic redirected to a port that no longer exists.
	shutdown := make(chan os.Signal, 1)
	signal.Notify(shutdown, os.Interrupt, syscall.SIGTERM)
	defer signal.Stop(shutdown)

	done := make(chan error, 1)
	go func() {
		done <- command.Wait()
	}()

	select {
	case err := <-done:
		if err != nil {
			return fmt.Errorf("sing-box exited: %w", err)
		}
		return nil
	case <-shutdown:
		if err := command.Process.Signal(os.Interrupt); err != nil && !errors.Is(err, os.ErrProcessDone) {
			_ = command.Process.Kill()
			<-done
			return fmt.Errorf("stop sing-box: %w", err)
		}
	}

	timer := time.NewTimer(8 * time.Second)
	defer timer.Stop()
	select {
	case <-done:
		// A signal-driven exit is expected here. sing-box has had a chance to run
		// its own cleanup before the systemd unit is considered stopped.
		return nil
	case <-timer.C:
		if err := command.Process.Kill(); err != nil && !errors.Is(err, os.ErrProcessDone) {
			return fmt.Errorf("kill unresponsive sing-box: %w", err)
		}
		<-done
		return errors.New("sing-box did not stop cleanly before the shutdown timeout")
	}
}

func openPrivateLog(path string) (*boundedLog, error) {
	fileDescriptor, err := syscall.Open(
		path,
		syscall.O_WRONLY|syscall.O_APPEND|syscall.O_CREAT|syscall.O_CLOEXEC|syscall.O_NOFOLLOW,
		0o600,
	)
	if err != nil {
		return nil, fmt.Errorf("open engine log: %w", err)
	}
	file := os.NewFile(uintptr(fileDescriptor), path)
	info, err := file.Stat()
	if err != nil {
		_ = file.Close()
		return nil, fmt.Errorf("inspect engine log: %w", err)
	}
	stat, owned := info.Sys().(*syscall.Stat_t)
	if !info.Mode().IsRegular() || !owned || int(stat.Uid) != os.Getuid() || info.Mode().Perm()&0o077 != 0 {
		_ = file.Close()
		return nil, errors.New("engine log must be a private regular file owned by the service user")
	}
	return &boundedLog{file: file}, nil
}

func readPrivateConfiguration(path string) ([]byte, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open engine configuration: %w", err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return nil, fmt.Errorf("inspect engine configuration: %w", err)
	}
	if !info.Mode().IsRegular() {
		return nil, errors.New("engine configuration is not a regular file")
	}
	if info.Mode().Perm()&0o077 != 0 {
		return nil, fmt.Errorf("engine configuration mode is %o, group and other access must be disabled", info.Mode().Perm())
	}
	if stat, ok := info.Sys().(*syscall.Stat_t); !ok || int(stat.Uid) != os.Getuid() {
		return nil, errors.New("engine configuration is not owned by the service user")
	}
	reader := io.LimitReader(file, engineconfig.MaxSize+1)
	configuration, err := io.ReadAll(reader)
	if err != nil {
		return nil, fmt.Errorf("read engine configuration: %w", err)
	}
	if len(configuration) > engineconfig.MaxSize {
		return nil, fmt.Errorf("engine configuration exceeds %d bytes", engineconfig.MaxSize)
	}
	return configuration, nil
}

func validateSystemBinary(path string) error {
	if !filepath.IsAbs(path) {
		return errors.New("sing-box path must be absolute")
	}
	info, err := os.Lstat(path)
	if err != nil {
		return fmt.Errorf("inspect sing-box: %w", err)
	}
	if !info.Mode().IsRegular() || info.Mode().Perm()&0o111 == 0 {
		return errors.New("sing-box is not a regular executable")
	}
	if info.Mode().Perm()&0o022 != 0 {
		return errors.New("sing-box must not be writable by group or other users")
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok || stat.Uid != 0 {
		return errors.New("sing-box must be owned by root")
	}
	return nil
}

func check(binaryPath string, configuration []byte) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, binaryPath, "check", "--disable-color", "-c", "stdin")
	command.Stdin = bytes.NewReader(configuration)
	output, err := command.CombinedOutput()
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return errors.New("sing-box configuration check timed out")
	}
	if err != nil {
		detail := string(bytes.TrimSpace(output))
		if detail == "" {
			detail = err.Error()
		}
		return fmt.Errorf("sing-box rejected the configuration: %s", detail)
	}
	return nil
}
