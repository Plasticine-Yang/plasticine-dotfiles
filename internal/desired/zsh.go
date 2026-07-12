package desired

import _ "embed"

//go:embed assets/p10k.zsh
var powerlevel10kConfig string

func Powerlevel10kConfig() string {
	return powerlevel10kConfig
}
