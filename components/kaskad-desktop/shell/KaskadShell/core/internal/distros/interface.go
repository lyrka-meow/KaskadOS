package distros

// DistroFamily describes the operating system for local runtime integration.
type DistroFamily string

const (
	FamilyArch   DistroFamily = "arch"
	FamilyFedora DistroFamily = "fedora"
	FamilySUSE   DistroFamily = "suse"
	FamilyUbuntu DistroFamily = "ubuntu"
	FamilyDebian DistroFamily = "debian"
	FamilyNix    DistroFamily = "nix"
	FamilyGentoo DistroFamily = "gentoo"
	FamilyVoid   DistroFamily = "void"
)

type DistroConfig struct {
	ID       string
	ColorHex string
	Family   DistroFamily
}

// Registry contains detection metadata only. Package installation belongs to
// the operating system's package manager, not to the shell.
var Registry = map[string]DistroConfig{
	"kaskados":            {ID: "kaskados", ColorHex: "#A2DAB2", Family: FamilyArch},
	"arch":                {ID: "arch", ColorHex: "#1793D1", Family: FamilyArch},
	"cachyos":             {ID: "cachyos", ColorHex: "#00BCA8", Family: FamilyArch},
	"endeavouros":         {ID: "endeavouros", ColorHex: "#7F3FBF", Family: FamilyArch},
	"manjaro":             {ID: "manjaro", ColorHex: "#35BF5C", Family: FamilyArch},
	"fedora":              {ID: "fedora", ColorHex: "#51A2DA", Family: FamilyFedora},
	"opensuse-tumbleweed": {ID: "opensuse-tumbleweed", ColorHex: "#73BA25", Family: FamilySUSE},
	"opensuse-leap":       {ID: "opensuse-leap", ColorHex: "#73BA25", Family: FamilySUSE},
	"ubuntu":              {ID: "ubuntu", ColorHex: "#E95420", Family: FamilyUbuntu},
	"debian":              {ID: "debian", ColorHex: "#A80030", Family: FamilyDebian},
	"nixos":               {ID: "nixos", ColorHex: "#5277C3", Family: FamilyNix},
	"gentoo":              {ID: "gentoo", ColorHex: "#54487A", Family: FamilyGentoo},
	"void":                {ID: "void", ColorHex: "#478061", Family: FamilyVoid},
}

func IsDistroSupported(id string) bool {
	_, exists := Registry[id]
	return exists
}
