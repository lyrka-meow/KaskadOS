package gpu

import (
	"fmt"

	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/internal/server/models"
)

func HandleRequest(conn *models.Conn, req models.Request, manager *Manager) {
	switch req.Method {
	case "gpu.getState":
		models.Respond(conn, req.ID, manager.State())
	default:
		models.RespondError(conn, req.ID, fmt.Sprintf("unknown method: %s", req.Method))
	}
}
