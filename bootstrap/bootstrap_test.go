package bootstrap_test

import (
	"crypto/sha256"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/release"
)

func TestBootstrapSelectsStableAndExactReleaseAssets(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name       string
		version    string
		wantPrefix string
	}{
		{
			name:       "stable",
			wantPrefix: "/releases/latest/download/",
		},
		{
			name:       "exact",
			version:    "v1.2.3",
			wantPrefix: "/releases/download/v1.2.3/",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			fixture := newFixture(t)
			result := runBootstrap(t, fixture, platform.TargetDarwinARM64, tt.version, "--yes", "--component", "shell")
			if result.err != nil {
				t.Fatalf("bootstrap failed: %v\n%s", result.err, result.output)
			}
			if !fixture.requested(tt.wantPrefix + release.BinaryName(platform.TargetDarwinARM64)) {
				t.Fatalf("requests = %v, want binary under %s", fixture.paths(), tt.wantPrefix)
			}
			if !fixture.requested(tt.wantPrefix + release.ChecksumManifestName) {
				t.Fatalf("requests = %v, want checksum manifest under %s", fixture.paths(), tt.wantPrefix)
			}
			if got := strings.TrimSpace(readFile(t, result.capture)); got != "__candidate-self-install\n--yes\n--component\nshell" {
				t.Fatalf("candidate args = %q", got)
			}
		})
	}
}

func TestBootstrapMapsEveryArtifactTarget(t *testing.T) {
	t.Parallel()

	for _, target := range platform.SupportedArtifactTargets() {
		target := target
		t.Run(target.String(), func(t *testing.T) {
			t.Parallel()
			fixture := newFixture(t)
			result := runBootstrap(t, fixture, target, "", "version")
			if result.err != nil {
				t.Fatalf("bootstrap failed: %v\n%s", result.err, result.output)
			}
			want := "/releases/latest/download/" + release.BinaryName(target)
			if !fixture.requested(want) {
				t.Fatalf("requests = %v, want %s", fixture.paths(), want)
			}
		})
	}
}

func TestBootstrapFailsBeforeCandidateHandoffOnChecksumMismatch(t *testing.T) {
	t.Parallel()

	fixture := newFixture(t)
	fixture.badChecksum = true
	result := runBootstrap(t, fixture, platform.TargetLinuxAMD64, "", "apply", "--yes")
	if result.err == nil {
		t.Fatalf("bootstrap succeeded despite checksum mismatch:\n%s", result.output)
	}
	if pathExists(result.capture) {
		t.Fatalf("candidate ran despite checksum mismatch: %s", readFile(t, result.capture))
	}
	if !strings.Contains(result.output, "checksum mismatch") {
		t.Fatalf("output = %q, want checksum mismatch", result.output)
	}
}

func TestBootstrapFailsBeforeCandidateHandoffOnInterruptedDownload(t *testing.T) {
	t.Parallel()

	fixture := newFixture(t)
	fixture.interruptBinary = true
	result := runBootstrap(t, fixture, platform.TargetLinuxARM64, "v2.0.0", "doctor")
	if result.err == nil {
		t.Fatalf("bootstrap succeeded despite interrupted download:\n%s", result.output)
	}
	if pathExists(result.capture) {
		t.Fatalf("candidate ran despite interrupted download: %s", readFile(t, result.capture))
	}
}

type fixture struct {
	server          *httptest.Server
	candidate       []byte
	badChecksum     bool
	interruptBinary bool
	requests        []string
}

func newFixture(t *testing.T) *fixture {
	t.Helper()

	f := &fixture{
		candidate: []byte("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$PLASTICINE_CAPTURE\"\n"),
	}
	f.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.requests = append(f.requests, r.URL.Path)
		switch {
		case strings.HasSuffix(r.URL.Path, release.ChecksumManifestName):
			sum := sha256.Sum256(f.candidate)
			if f.badChecksum {
				sum = sha256.Sum256([]byte("not the candidate"))
			}
			for _, target := range platform.SupportedArtifactTargets() {
				fmt.Fprintf(w, "%x  %s\n", sum, release.BinaryName(target))
			}
		case strings.Contains(pathBase(r.URL.Path), "plasticine_"):
			if f.interruptBinary {
				w.Header().Set("Content-Length", "9999")
				_, _ = w.Write([]byte("partial"))
				return
			}
			_, _ = w.Write(f.candidate)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(f.server.Close)
	return f
}

func (f *fixture) requested(path string) bool {
	for _, got := range f.requests {
		if got == path {
			return true
		}
	}
	return false
}

func (f *fixture) paths() []string {
	return append([]string(nil), f.requests...)
}

type bootstrapResult struct {
	err     error
	output  string
	capture string
}

func runBootstrap(t *testing.T, fixture *fixture, target platform.ArtifactTarget, version string, args ...string) bootstrapResult {
	t.Helper()

	home := t.TempDir()
	capture := filepath.Join(home, "candidate-args.txt")
	cmd := exec.Command("sh", append([]string{filepath.Join("..", "install.sh")}, args...)...)
	cmd.Env = append(os.Environ(),
		"PLASTICINE_DOWNLOAD_BASE="+fixture.server.URL+"/releases",
		"PLASTICINE_HOME="+home,
		"PLASTICINE_OS="+string(target.OS),
		"PLASTICINE_ARCH="+string(target.Arch),
		"PLASTICINE_VERSION="+version,
		"PLASTICINE_CAPTURE="+capture,
	)
	output, err := cmd.CombinedOutput()
	return bootstrapResult{err: err, output: string(output), capture: capture}
}

func pathBase(path string) string {
	parts := strings.Split(strings.TrimRight(path, "/"), "/")
	return parts[len(parts)-1]
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return string(data)
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
