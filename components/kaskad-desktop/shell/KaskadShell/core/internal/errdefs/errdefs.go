package errdefs

import (
	kaskaderrdefs "github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/third_party/kaskadgo/errdefs"
)

type ErrorType = kaskaderrdefs.ErrorType

type CustomError = kaskaderrdefs.CustomError

const (
	ErrTypeNotLinux ErrorType = kaskaderrdefs.AppErrorBase + iota
	ErrTypeInvalidArchitecture
	ErrTypeUnsupportedDistribution
	ErrTypeUnsupportedVersion
	ErrTypeUpdateCancelled
	ErrTypeNoUpdateNeeded
	ErrTypeInvalidTemperature
	ErrTypeInvalidGamma
	ErrTypeInvalidLocation
	ErrTypeInvalidManualTimes
	ErrTypeNoWaylandDisplay
	ErrTypeNoGammaControl
	ErrTypeNotInitialized
	ErrTypeSecretPromptCancelled
	ErrTypeSecretPromptTimeout
	ErrTypeSecretAgentFailed
	ErrTypeGeneric
)

func NewCustomError(errType ErrorType, message string) error {
	return kaskaderrdefs.NewCustomError(errType, message)
}

const (
	ErrBadCredentials   = "bad-credentials"
	ErrNoSuchSSID       = "no-such-ssid"
	ErrAssocTimeout     = "assoc-timeout"
	ErrDhcpTimeout      = "dhcp-timeout"
	ErrUserCanceled     = "user-canceled"
	ErrWifiDisabled     = "wifi-disabled"
	ErrAlreadyConnected = "already-connected"
	ErrConnectionFailed = "connection-failed"

	ErrHotspotIPConfigFailed   = "hotspot-ip-config-failed"
	ErrHotspotSupplicantFailed = "hotspot-supplicant-failed"
	ErrHotspotFailed           = "hotspot-failed"
)

var (
	ErrUpdateCancelled       = NewCustomError(ErrTypeUpdateCancelled, "update cancelled by user")
	ErrNoUpdateNeeded        = NewCustomError(ErrTypeNoUpdateNeeded, "no update needed")
	ErrInvalidTemperature    = NewCustomError(ErrTypeInvalidTemperature, "temperature must be between 1000 and 10000")
	ErrInvalidGamma          = NewCustomError(ErrTypeInvalidGamma, "gamma must be between 0 and 10")
	ErrInvalidLocation       = NewCustomError(ErrTypeInvalidLocation, "invalid latitude/longitude")
	ErrInvalidManualTimes    = NewCustomError(ErrTypeInvalidManualTimes, "both sunrise and sunset must be set or neither")
	ErrNoWaylandDisplay      = NewCustomError(ErrTypeNoWaylandDisplay, "no wayland display available")
	ErrNoGammaControl        = NewCustomError(ErrTypeNoGammaControl, "compositor does not support gamma control")
	ErrNotInitialized        = NewCustomError(ErrTypeNotInitialized, "manager not initialized")
	ErrSecretPromptCancelled = NewCustomError(ErrTypeSecretPromptCancelled, "secret prompt cancelled by user")
	ErrSecretPromptTimeout   = NewCustomError(ErrTypeSecretPromptTimeout, "secret prompt timed out")
	ErrSecretAgentFailed     = NewCustomError(ErrTypeSecretAgentFailed, "secret agent operation failed")
)
