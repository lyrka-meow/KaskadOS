package location

import (
	"sync"

	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/geolocation"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/third_party/kaskadgo/syncmap"
)

type State struct {
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

type Manager struct {
	state      *State
	stateMutex sync.RWMutex

	client geolocation.Client

	stopChan chan struct{}
	sigWG    sync.WaitGroup

	subscribers  syncmap.Map[string, chan State]
	dirty        chan struct{}
	notifierWg   sync.WaitGroup
	lastNotified *State
}
