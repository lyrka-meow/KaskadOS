package server

import (
	"fmt"
	"strings"

	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/apppicker"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/bluez"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/brightness"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/clipboard"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/cups"
	serverDbus "github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/dbus"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/evdev"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/files"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/freedesktop"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/gpu"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/location"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/loginctl"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/mime"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/models"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/network"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/software"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/sysupdate"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/thememode"
	serverThemes "github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/themes"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/timedate"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/wallpaper"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/wayland"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/windowsapps"
)

func RouteRequest(conn *models.Conn, req models.Request) {
	if strings.HasPrefix(req.Method, "gpu.") {
		if gpuManager == nil {
			models.RespondError(conn, req.ID, "GPU metrics manager not initialized")
			return
		}
		gpu.HandleRequest(conn, req, gpuManager)
		return
	}

	if strings.HasPrefix(req.Method, "network.") {
		if networkManager == nil {
			models.RespondError(conn, req.ID, "network manager not initialized")
			return
		}
		network.HandleRequest(conn, req, networkManager)
		return
	}

	if strings.HasPrefix(req.Method, "themes.") {
		serverThemes.HandleRequest(conn, req)
		return
	}

	if strings.HasPrefix(req.Method, "theme.auto.") {
		if themeModeManager == nil {
			models.RespondError(conn, req.ID, "theme mode manager not initialized")
			return
		}
		thememode.HandleRequest(conn, req, themeModeManager)
		return
	}

	if strings.HasPrefix(req.Method, "wallpaper.") {
		if wallpaperManager == nil {
			models.RespondError(conn, req.ID, "wallpaper manager not initialized")
			return
		}
		wallpaper.HandleRequest(conn, req, wallpaperManager)
		return
	}

	if strings.HasPrefix(req.Method, "loginctl.") {
		if loginctlManager == nil {
			models.RespondError(conn, req.ID, "loginctl manager not initialized")
			return
		}
		loginctl.HandleRequest(conn, req, loginctlManager)
		return
	}

	if strings.HasPrefix(req.Method, "freedesktop.") {
		if freedesktopManager == nil {
			models.RespondError(conn, req.ID, "freedesktop manager not initialized")
			return
		}
		freedesktop.HandleRequest(conn, req, freedesktopManager)
		return
	}

	if strings.HasPrefix(req.Method, "wayland.") {
		if waylandManager == nil {
			models.RespondError(conn, req.ID, "wayland manager not initialized")
			return
		}
		wayland.HandleRequest(conn, req, waylandManager)
		return
	}

	if strings.HasPrefix(req.Method, "bluetooth.") {
		if bluezManager == nil {
			models.RespondError(conn, req.ID, "bluetooth manager not initialized")
			return
		}
		bluez.HandleRequest(conn, req, bluezManager)
		return
	}

	if strings.HasPrefix(req.Method, "mime.") {
		mime.HandleRequest(conn, req)
		return
	}

	if strings.HasPrefix(req.Method, "browser.") || strings.HasPrefix(req.Method, "apppicker.") {
		if appPickerManager == nil {
			models.RespondError(conn, req.ID, "apppicker manager not initialized")
			return
		}
		apppicker.HandleRequest(conn, req, appPickerManager)
		return
	}

	if strings.HasPrefix(req.Method, "cups.") {
		if cupsManager == nil {
			models.RespondError(conn, req.ID, "CUPS manager not initialized")
			return
		}
		cups.HandleRequest(conn, req, cupsManager)
		return
	}

	if strings.HasPrefix(req.Method, "brightness.") {
		if brightnessManager == nil {
			models.RespondError(conn, req.ID, "brightness manager not initialized")
			return
		}
		brightness.HandleRequest(conn, req, brightnessManager)
		return
	}

	if strings.HasPrefix(req.Method, "evdev.") {
		if evdevManager == nil {
			models.RespondError(conn, req.ID, "evdev manager not initialized")
			return
		}
		evdev.HandleRequest(conn, req, evdevManager)
		return
	}

	if strings.HasPrefix(req.Method, "dbus.") {
		if dbusManager == nil {
			models.RespondError(conn, req.ID, "dbus manager not initialized")
			return
		}
		serverDbus.HandleRequest(conn, req, dbusManager, dbusClientID)
		return
	}

	if strings.HasPrefix(req.Method, "clipboard.") {
		switch req.Method {
		case "clipboard.getConfig":
			cfg := clipboard.LoadConfig()
			models.Respond(conn, req.ID, cfg)
			return
		case "clipboard.setConfig":
			handleClipboardSetConfig(conn, req)
			return
		}
		if clipboardManager == nil {
			models.RespondError(conn, req.ID, "clipboard manager not initialized")
			return
		}
		clipboard.HandleRequest(conn, req, clipboardManager)
		return
	}

	if strings.HasPrefix(req.Method, "location.") {
		if locationManager == nil {
			models.RespondError(conn, req.ID, "location manager not initialized")
			return
		}
		location.HandleRequest(conn, req, locationManager)
		return
	}

	if strings.HasPrefix(req.Method, "sysupdate.") {
		if sysUpdateManager == nil {
			models.RespondError(conn, req.ID, "sysupdate manager not initialized")
			return
		}
		sysupdate.HandleRequest(conn, req, sysUpdateManager)
		return
	}

	if strings.HasPrefix(req.Method, "software.") {
		if softwareManager == nil {
			models.RespondError(conn, req.ID, "software manager not initialized")
			return
		}
		software.HandleRequest(conn, req, softwareManager)
		return
	}

	if strings.HasPrefix(req.Method, "windows.") {
		if windowsAppsManager == nil {
			models.RespondError(conn, req.ID, "windows applications manager not initialized")
			return
		}
		windowsapps.HandleRequest(conn, req, windowsAppsManager)
		return
	}

	if strings.HasPrefix(req.Method, "files.") {
		if filesManager == nil {
			models.RespondError(conn, req.ID, "file manager backend not initialized")
			return
		}
		files.HandleRequest(conn, req, filesManager)
		return
	}

	if strings.HasPrefix(req.Method, "timedate.") {
		if timeDateManager == nil {
			models.RespondError(conn, req.ID, "time synchronization manager not initialized")
			return
		}
		timedate.HandleRequest(conn, req, timeDateManager)
		return
	}

	switch req.Method {
	case "ping":
		models.Respond(conn, req.ID, "pong")
	case "getServerInfo":
		info := getServerInfo()
		models.Respond(conn, req.ID, info)
	case "subscribe":
		handleSubscribe(conn, req)
	case "matugen.queue":
		handleMatugenQueue(conn, req)
	case "matugen.status":
		handleMatugenStatus(conn, req)
	default:
		models.RespondError(conn, req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}

func handleClipboardSetConfig(conn *models.Conn, req models.Request) {
	cfg := clipboard.LoadConfig()

	if v, ok := models.Get[float64](req, "maxHistory"); ok {
		cfg.MaxHistory = int(v)
	}
	if v, ok := models.Get[float64](req, "maxEntrySize"); ok {
		cfg.MaxEntrySize = int64(v)
	}
	if v, ok := models.Get[float64](req, "autoClearDays"); ok {
		cfg.AutoClearDays = int(v)
	}
	if v, ok := models.Get[bool](req, "clearAtStartup"); ok {
		cfg.ClearAtStartup = v
	}
	if v, ok := models.Get[bool](req, "disabled"); ok {
		cfg.Disabled = v
	}
	if v, ok := models.Get[float64](req, "maxPinned"); ok {
		cfg.MaxPinned = int(v)
	}

	if err := clipboard.SaveConfig(cfg); err != nil {
		models.RespondError(conn, req.ID, err.Error())
		return
	}

	models.Respond(conn, req.ID, models.SuccessResult{Success: true, Message: "config updated"})
}
