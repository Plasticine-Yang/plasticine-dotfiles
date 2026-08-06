package reconciler_test

import (
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
)

func TestComponentCatalogIsStableAndDefensive(t *testing.T) {
	t.Parallel()

	catalog := reconciler.ComponentCatalog()
	if len(catalog) != 8 {
		t.Fatalf("catalog length = %d, want 8", len(catalog))
	}
	if catalog[0].ID != reconciler.ComponentShell || catalog[2].ID != reconciler.ComponentGitHubSSH {
		t.Fatalf("unexpected catalog order: %#v", catalog)
	}
	if len(catalog[2].Dependencies) != 1 || catalog[2].Dependencies[0] != reconciler.ComponentShell {
		t.Fatalf("github-ssh dependencies = %#v", catalog[2].Dependencies)
	}

	catalog[0].ID = "mutated"
	catalog[2].Dependencies[0] = "mutated"
	fresh := reconciler.ComponentCatalog()
	if fresh[0].ID != reconciler.ComponentShell || fresh[2].Dependencies[0] != reconciler.ComponentShell {
		t.Fatalf("catalog returned mutable internal storage: %#v", fresh)
	}
}
