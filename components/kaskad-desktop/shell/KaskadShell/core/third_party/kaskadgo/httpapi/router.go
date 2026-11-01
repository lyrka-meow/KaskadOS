package httpapi

import (
	"net/http"

	"github.com/danielgtaylor/huma/v2"
	"github.com/danielgtaylor/huma/v2/adapters/humachi"
	"github.com/go-chi/chi/v5"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/third_party/kaskadgo/errdefs/humaerr"
	"github.com/lyrka-meow/KaskadOS/components/kaskad-desktop/shell/KaskadShell/core/third_party/kaskadgo/httpapi/middleware"
)

type RouterConfig struct {
	Title   string
	Version string
	Options []Option
}

func NewRouter(cfg RouterConfig, register func(api huma.API, r chi.Router)) chi.Router {
	router := chi.NewRouter()

	router.Get("/health", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("OK"))
	})

	router.Group(func(rt chi.Router) {
		rt.Use(middleware.Logger)

		huma.NewError = humaerr.HumaErrorFunc

		humaCfg := NewHumaConfig(cfg.Title, cfg.Version, cfg.Options...)
		humaCfg.DocsPath = ""
		api := humachi.New(rt, humaCfg)

		mw := middleware.NewMiddleware(api)
		api.UseMiddleware(mw.Recoverer)

		rt.Get("/docs", DocsHandler(cfg.Title))

		register(api, rt)
	})

	return router
}
