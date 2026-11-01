//go:build distro_binary

package main

import (
	"os"

	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/clipboard"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/log"
)

var Version = "dev"

func init() {
	authCmd.AddCommand(authSyncCmd, authResolveLockCmd, authListServicesCmd, authValidateCmd)
	setupCmd.AddCommand(setupBindsCmd, setupLayoutCmd, setupColorsCmd, setupAlttabCmd, setupOutputsCmd, setupCursorCmd, setupWindowrulesCmd)
	rootCmd.AddCommand(getCommonCommands()...)
	rootCmd.AddCommand(authCmd)

	rootCmd.SetHelpTemplate(getHelpTemplate())
}

func main() {
	clipboard.MaybeServeAndExit()

	if os.Geteuid() == 0 && !isReadOnlyCommand(os.Args) {
		log.Fatal("This program should not be run as root. Exiting.")
	}

	if err := rootCmd.Execute(); err != nil {
		log.Fatal(err)
	}
}
