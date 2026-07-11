package release_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/release"
)

func TestReleaseArtifactsRequireFourRawExecutablesAndMatchingChecksums(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	for _, target := range platform.SupportedArtifactTargets() {
		writeExecutable(t, filepath.Join(dir, release.BinaryName(target)), "binary-"+target.String())
	}
	if err := release.WriteChecksumManifest(dir, platform.SupportedArtifactTargets()); err != nil {
		t.Fatalf("write checksums: %v", err)
	}

	report, err := release.ValidateReleaseArtifacts(dir, platform.SupportedArtifactTargets())
	if err != nil {
		t.Fatalf("validate artifacts: %v", err)
	}
	if len(report.Artifacts) != 4 {
		t.Fatalf("artifact count = %d, want 4", len(report.Artifacts))
	}
	if report.Manifest != filepath.Join(dir, release.ChecksumManifestName) {
		t.Fatalf("manifest = %q", report.Manifest)
	}
}

func TestReleaseArtifactValidationFailsBeforePublishOnChecksumMismatch(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	for _, target := range platform.SupportedArtifactTargets() {
		writeExecutable(t, filepath.Join(dir, release.BinaryName(target)), "binary-"+target.String())
	}
	if err := release.WriteChecksumManifest(dir, platform.SupportedArtifactTargets()); err != nil {
		t.Fatalf("write checksums: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, release.BinaryName(platform.TargetLinuxAMD64)), []byte("tampered"), 0o755); err != nil {
		t.Fatalf("tamper artifact: %v", err)
	}

	_, err := release.ValidateReleaseArtifacts(dir, platform.SupportedArtifactTargets())
	if err == nil {
		t.Fatal("checksum mismatch validated successfully")
	}
	if !strings.Contains(err.Error(), "checksum mismatch") {
		t.Fatalf("error = %q, want checksum mismatch", err.Error())
	}
}

func TestReleaseArtifactValidationRejectsArchiveWrapping(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	for _, target := range platform.SupportedArtifactTargets() {
		writeExecutable(t, filepath.Join(dir, release.BinaryName(target)), "binary-"+target.String())
	}
	if err := release.WriteChecksumManifest(dir, platform.SupportedArtifactTargets()); err != nil {
		t.Fatalf("write checksums: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, release.BinaryName(platform.TargetLinuxARM64)+".tar.gz"), []byte("wrapped"), 0o644); err != nil {
		t.Fatalf("write archive: %v", err)
	}

	_, err := release.ValidateReleaseArtifacts(dir, platform.SupportedArtifactTargets())
	if err == nil {
		t.Fatal("archive wrapping validated successfully")
	}
	if !strings.Contains(err.Error(), "archive wrapping") {
		t.Fatalf("error = %q, want archive wrapping", err.Error())
	}
}

func TestReproducibilityComparesChecksumManifests(t *testing.T) {
	t.Parallel()

	left := t.TempDir()
	right := t.TempDir()
	for _, dir := range []string{left, right} {
		for _, target := range platform.SupportedArtifactTargets() {
			writeExecutable(t, filepath.Join(dir, release.BinaryName(target)), "same-"+target.String())
		}
		if err := release.WriteChecksumManifest(dir, platform.SupportedArtifactTargets()); err != nil {
			t.Fatalf("write checksums for %s: %v", dir, err)
		}
	}

	if err := release.CompareChecksumManifests(left, right); err != nil {
		t.Fatalf("compare identical manifests: %v", err)
	}
	if err := os.WriteFile(filepath.Join(right, release.BinaryName(platform.TargetDarwinAMD64)), []byte("different"), 0o755); err != nil {
		t.Fatalf("tamper right artifact: %v", err)
	}
	if err := release.WriteChecksumManifest(right, platform.SupportedArtifactTargets()); err != nil {
		t.Fatalf("rewrite right checksums: %v", err)
	}

	err := release.CompareChecksumManifests(left, right)
	if err == nil {
		t.Fatal("different manifests compared successfully")
	}
	if !strings.Contains(err.Error(), "reproducibility failure") {
		t.Fatalf("error = %q, want reproducibility failure", err.Error())
	}
}

func TestReleaseMetadataValidationRequiresEveryBinaryToContainBuildValues(t *testing.T) {
	t.Parallel()

	dir := t.TempDir()
	metadata := release.BuildMetadata{
		Version:    "v1.2.3",
		Commit:     "abc123",
		CommitTime: "2026-07-12T00:00:00Z",
	}
	for _, target := range platform.SupportedArtifactTargets() {
		writeExecutable(t, filepath.Join(dir, release.BinaryName(target)), "plasticine v1.2.3 commit=abc123 commit_time=2026-07-12T00:00:00Z")
	}

	if err := release.ValidateReleaseMetadata(dir, platform.SupportedArtifactTargets(), metadata); err != nil {
		t.Fatalf("validate metadata: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, release.BinaryName(platform.TargetLinuxAMD64)), []byte("plasticine v1.2.3 commit_time=2026-07-12T00:00:00Z"), 0o755); err != nil {
		t.Fatalf("tamper metadata: %v", err)
	}

	err := release.ValidateReleaseMetadata(dir, platform.SupportedArtifactTargets(), metadata)
	if err == nil {
		t.Fatal("metadata validation accepted a binary missing commit metadata")
	}
	if !strings.Contains(err.Error(), "missing embedded commit metadata") {
		t.Fatalf("error = %q, want missing commit metadata", err.Error())
	}
}

func writeExecutable(t *testing.T, path string, body string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
		t.Fatalf("write executable %s: %v", path, err)
	}
}
