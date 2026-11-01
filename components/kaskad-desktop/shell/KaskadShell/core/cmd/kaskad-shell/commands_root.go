package main

import (
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "kaskad-shell",
	Short: "kaskad-shell CLI",
	Long:  "kaskad-shell is the KaskadShell management CLI and backend server.",
}

func init() {
	rootCmd.PersistentFlags().StringVarP(shellApp.CustomConfigVar(), "config", "c", "", "Path to a UI config dir (containing shell.qml) to use instead of the embedded UI (env: KASKAD_SHELL_DIR)")
}
