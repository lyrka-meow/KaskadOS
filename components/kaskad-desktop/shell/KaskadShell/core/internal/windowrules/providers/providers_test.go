package providers

import "github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/windowrules"

func newTestWindowRule(id, name, appID string) windowrules.WindowRule {
	return windowrules.WindowRule{
		ID:      id,
		Name:    name,
		Enabled: true,
		MatchCriteria: windowrules.MatchCriteria{
			AppID: appID,
		},
	}
}

func boolPtr(b bool) *bool {
	return &b
}

func floatPtr(f float64) *float64 {
	return &f
}
