package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/release"
)

func TestPublicationGateDryRunAcceptsCompleteStableRelease(t *testing.T) {
	t.Parallel()

	assetDir, installScript := completeGatePublicationAssets(t)
	code := run([]string{"publication", "v1.2.3", "v1.2.3", assetDir, installScript})
	if code != 0 {
		t.Fatalf("publication gate exit code = %d, want 0", code)
	}
}

func TestPublicationGateDryRunRejectsMissingInstallScript(t *testing.T) {
	t.Parallel()

	assetDir, installScript := completeGatePublicationAssets(t)
	if err := os.Remove(installScript); err != nil {
		t.Fatalf("remove install script: %v", err)
	}
	code := run([]string{"publication", "v1.2.3", "v1.2.3", assetDir, installScript})
	if code != 1 {
		t.Fatalf("publication gate exit code = %d, want 1", code)
	}
}

func TestPublicationGateDryRunRejectsFailedGateAndDuplicateRelease(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		name string
		args []string
	}{
		{
			name: "failed gate",
			args: []string{"publication", "--required-gates-passed=false", "v1.2.3", "v1.2.3", "missing-assets", "missing-install.sh"},
		},
		{
			name: "duplicate release",
			args: []string{"publication", "--existing-release=true", "v1.2.3", "v1.2.3", "missing-assets", "missing-install.sh"},
		},
	} {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			code := run(tc.args)
			if code != 1 {
				t.Fatalf("publication gate exit code = %d, want 1", code)
			}
		})
	}
}

func TestMetadataGateAcceptsBuildValuesForEveryBinary(t *testing.T) {
	t.Parallel()

	assetDir := t.TempDir()
	for _, target := range platform.SupportedArtifactTargets() {
		path := filepath.Join(assetDir, release.BinaryName(target))
		if err := os.WriteFile(path, []byte("plasticine v1.2.3 commit=abc123 commit_time=2026-07-12T00:00:00Z"), 0o755); err != nil {
			t.Fatalf("write executable %s: %v", path, err)
		}
	}

	code := run([]string{"metadata", assetDir, "v1.2.3", "abc123", "2026-07-12T00:00:00Z"})
	if code != 0 {
		t.Fatalf("metadata gate exit code = %d, want 0", code)
	}
}

func completeGatePublicationAssets(t *testing.T) (string, string) {
	t.Helper()

	dir := t.TempDir()
	for _, target := range platform.SupportedArtifactTargets() {
		path := filepath.Join(dir, release.BinaryName(target))
		if err := os.WriteFile(path, []byte("binary-"+target.String()), 0o755); err != nil {
			t.Fatalf("write executable %s: %v", path, err)
		}
	}
	if err := release.WriteChecksumManifest(dir, platform.SupportedArtifactTargets()); err != nil {
		t.Fatalf("write checksums: %v", err)
	}
	installScript := filepath.Join(dir, "install.sh")
	if err := os.WriteFile(installScript, []byte("#!/bin/sh\n"), 0o644); err != nil {
		t.Fatalf("write install script: %v", err)
	}
	return dir, installScript
}
