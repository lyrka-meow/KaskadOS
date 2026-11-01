package xdg_shell

import "github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/pkg/go-wayland/wayland/client"

type Popup struct {
	client.BaseProxy
}

func NewPopup(ctx *client.Context) *Popup {
	p := &Popup{}
	ctx.Register(p)
	return p
}
