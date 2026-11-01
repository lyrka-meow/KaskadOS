package config

import _ "embed"

//go:embed embedded/hyprland.lua
var HyprlandLuaConfig string

//go:embed embedded/hypr-colors.lua
var KaskadColorsLuaConfig string

//go:embed embedded/hypr-layout.lua
var KaskadLayoutLuaConfig string

//go:embed embedded/hypr-binds.lua
var KaskadBindsLuaConfig string

//go:embed embedded/hypr-outputs.lua
var KaskadOutputsLuaConfig string

//go:embed embedded/hypr-cursor.lua
var KaskadCursorLuaConfig string

//go:embed embedded/hypr-windowrules.lua
var KaskadWindowRulesLuaConfig string

//go:embed embedded/hypr-binds-user.lua
var KaskadBindsUserLuaConfig string
