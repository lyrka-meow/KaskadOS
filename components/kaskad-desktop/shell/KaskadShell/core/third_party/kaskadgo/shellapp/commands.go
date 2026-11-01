package shellapp

import (
	"os"

	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/third_party/kaskadgo/log"
	"github.com/spf13/cobra"
)

// Commands returns the supported shell lifecycle commands.
//
// KaskadOS intentionally has no in-session restart command. Restarting this
// process also tears down the graphical session, so desktop updates take
// effect on the next login instead.
func (a *App) Commands() []*cobra.Command {
	return []*cobra.Command{
		a.runCommand(),
		a.killCommand(),
	}
}

func (a *App) runCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:     "run",
		Short:   "Launch " + binaryName() + " (backend + UI)",
		Long:    "Start the " + binaryName() + " backend and launch the UI.",
		PreRunE: a.ResolveConfig,
		RunE: func(cmd *cobra.Command, _ []string) error {
			daemon, _ := cmd.Flags().GetBool("daemon")
			session, _ := cmd.Flags().GetBool("session")
			a.startHidden, _ = cmd.Flags().GetBool("hidden")
			isDaemonChild, _ := cmd.Flags().GetBool("daemon-child")

			if !isDaemonChild && a.cfg.ShowMethod != "" && len(a.PIDs()) > 0 {
				if err := a.CallUI(a.cfg.ShowMethod, nil); err == nil {
					log.Infof("%s already running; showing window", binaryName())
					return nil
				}
			}

			if err := a.applyLogFlags(cmd); err != nil {
				return err
			}
			if daemon {
				return a.RunDaemon(session)
			}
			return a.RunInteractive(session)
		},
	}

	cmd.Flags().BoolP("daemon", "d", false, "Run in daemon (background) mode")
	cmd.Flags().Bool("daemon-child", false, "Internal flag for daemon child process")
	cmd.Flags().Bool("session", false, "Session managed (e.g. systemd unit)")
	cmd.Flags().Bool("hidden", false, "Start with the window hidden (tray only)")
	cmd.Flags().String("log-level", "", "Log level: debug, info, warn, error, fatal (overrides "+a.cfg.EnvPrefix+"_LOG_LEVEL)")
	cmd.Flags().String("log-file", "", "Append logs to this file in addition to stderr (overrides "+a.cfg.EnvPrefix+"_LOG_FILE)")
	_ = cmd.Flags().MarkHidden("daemon-child")
	return cmd
}

func (a *App) applyLogFlags(cmd *cobra.Command) error {
	if v, _ := cmd.Flags().GetString("log-level"); v != "" {
		if err := os.Setenv(a.cfg.EnvPrefix+"_LOG_LEVEL", v); err != nil {
			return err
		}
	}
	if v, _ := cmd.Flags().GetString("log-file"); v != "" {
		if err := os.Setenv(a.cfg.EnvPrefix+"_LOG_FILE", v); err != nil {
			return err
		}
	}
	log.ApplyEnvOverrides()
	return nil
}

func (a *App) killCommand() *cobra.Command {
	return &cobra.Command{
		Use:   "kill",
		Short: "Kill running " + binaryName() + " processes",
		Run: func(_ *cobra.Command, _ []string) {
			a.Kill()
		},
	}
}
