package workstation_test

import (
	"strings"
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/workstation"
)

func TestRuntimeBuildsIndependentBaseRequests(t *testing.T) {
	t.Setenv("PLASTICINE_HOST_FAMILY", "macos")
	t.Setenv("PLASTICINE_HOST_VERSION", "13.0")

	runtime, err := workstation.New(workstation.Options{
		Home:            t.TempDir(),
		WorkstationRoot: t.TempDir(),
		DiagnosticURLs:  []string{},
	})
	if err != nil {
		t.Fatalf("new runtime: %v", err)
	}
	first := runtime.Request()
	first.Exclude = append(first.Exclude, reconciler.ComponentGitConfig)
	second := runtime.Request()
	if len(second.Exclude) != 0 {
		t.Fatalf("base request was mutated: %#v", second.Exclude)
	}
	if runtime.Target.String() == "/" {
		t.Fatalf("runtime target was not detected: %#v", runtime.Target)
	}
}

func TestDesiredStateIDMatchesStableComponentCatalog(t *testing.T) {
	t.Parallel()

	if got := workstation.DesiredStateID(); len(got) != 64 {
		t.Fatalf("desired state ID length = %d, want 64: %q", len(got), got)
	}
	if got := workstation.DesiredStateID(); got != "b366c8117f80ad8cdfa58c8ea29db345a80d4bc2ef00a25a8491e2e8ccfa8b91" {
		t.Fatalf("desired state ID changed with runtime extraction: %s", got)
	}
	if got := workstation.ToolLockSHA256(); len(got) != 64 || strings.Trim(got, "0123456789abcdef") != "" {
		t.Fatalf("tool lock digest is not lowercase SHA-256: %q", got)
	}
}
