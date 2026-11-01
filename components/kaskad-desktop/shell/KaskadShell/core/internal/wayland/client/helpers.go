package client

import wlclient "github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/pkg/go-wayland/wayland/client"

func Roundtrip(display *wlclient.Display, ctx *wlclient.Context) error {
	callback, err := display.Sync()
	if err != nil {
		return err
	}

	done := make(chan struct{})
	callback.SetDoneHandler(func(e wlclient.CallbackDoneEvent) {
		close(done)
	})

	for {
		select {
		case <-done:
			return nil
		default:
			if err := ctx.Dispatch(); err != nil {
				return err
			}
		}
	}
}
