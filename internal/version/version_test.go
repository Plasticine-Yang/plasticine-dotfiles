package version_test

import (
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/version"
)

func TestInfoStringReportsReleaseMetadata(t *testing.T) {
	t.Parallel()

	info := version.Info{
		Version:    "v1.2.3",
		Commit:     "abc123",
		CommitTime: "2026-07-12T00:00:00Z",
	}
	want := "plasticine v1.2.3 commit=abc123 commit_time=2026-07-12T00:00:00Z"
	if got := info.String(); got != want {
		t.Fatalf("Info.String() = %q, want %q", got, want)
	}
}
