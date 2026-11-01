package main

import (
	"fmt"
	"os"
	"os/exec"
	"syscall"

	"github.com/spf13/cobra"
)

var greeterCmd = &cobra.Command{
	Use:                "greeter",
	Short:              "Deprecated: moved to the standalone kaskad-shell-greeter binary",
	Long:               "The greeter has moved to the standalone kaskad-shell-greeter package.\nThis command forwards to 'kaskad-shell-greeter' when it is installed.",
	DisableFlagParsing: true,
	SilenceUsage:       true,
	RunE: func(_ *cobra.Command, args []string) error {
		binary, err := exec.LookPath("kaskad-shell-greeter")
		if err != nil {
			return fmt.Errorf("'kaskad-shell greeter' has moved to the standalone kaskad-shell-greeter package.\n  %s", greeterPackageInstallHint())
		}
		if isLegacyWrapperScript(binary) {
			return fmt.Errorf("'kaskad-shell greeter' has moved to the standalone kaskad-shell-greeter package; %s is the old wrapper script.\n  %s", binary, greeterPackageInstallHint())
		}
		fmt.Fprintln(os.Stderr, "warning: 'kaskad-shell greeter' is deprecated; use 'kaskad-shell-greeter' directly")
		return syscall.Exec(binary, append([]string{"kaskad-shell-greeter"}, args...), os.Environ())
	},
}

func isLegacyWrapperScript(path string) bool {
	file, err := os.Open(path)
	if err != nil {
		return false
	}
	defer file.Close()
	header := make([]byte, 2)
	if _, err := file.Read(header); err != nil {
		return false
	}
	return string(header) == "#!"
}

func greeterPackageInstallHint() string {
	return "Kaskad DE uses the system login manager. Install or update it through the operating system package manager."
}
