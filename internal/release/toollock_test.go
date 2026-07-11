package release_test

import (
	"path/filepath"
	"strings"
	"testing"

	plasticine "github.com/Plasticine-Yang/plasticine-dotfiles"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/release"
)

func TestRepositoryToolLockIsCompleteForEveryArtifactTarget(t *testing.T) {
	t.Parallel()

	lock, err := release.LoadToolLock(filepath.Join("..", "..", "tool-lock.json"))
	if err != nil {
		t.Fatalf("load tool lock: %v", err)
	}
	if err := release.ValidateToolLock(lock); err != nil {
		t.Fatalf("validate repository tool lock: %v", err)
	}
}

func TestEmbeddedToolLockIsReleaseValid(t *testing.T) {
	t.Parallel()

	lock, err := release.LoadToolLockBytes(plasticine.DefaultToolLockJSON)
	if err != nil {
		t.Fatalf("load embedded tool lock: %v", err)
	}
	if err := release.ValidateToolLock(lock); err != nil {
		t.Fatalf("validate embedded tool lock: %v", err)
	}
}

func TestToolLockValidationRejectsMutableOrIncompleteArtifacts(t *testing.T) {
	t.Parallel()

	lock := release.ToolLock{
		Tools: map[release.ManagedTool]release.ToolVersion{
			release.ManagedToolLazygit: {
				Version: "v1.0.0",
				Targets: map[platform.ArtifactTarget]release.ToolArtifact{
					platform.TargetDarwinARM64: {
						URL:          "https://example.com/latest/lazygit.tar.gz",
						ArtifactType: release.ArtifactTypeTarGz,
						SHA256:       strings.Repeat("0", 64),
					},
				},
			},
		},
	}

	err := release.ValidateToolLock(lock)
	if err == nil {
		t.Fatal("validate mutable tool lock succeeded")
	}
	for _, want := range []string{
		"neovim",
		"darwin/amd64",
		"linux/arm64",
		"mutable",
	} {
		if !strings.Contains(err.Error(), want) {
			t.Fatalf("error %q does not mention %q", err.Error(), want)
		}
	}
}
