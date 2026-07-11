package release

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
)

const ChecksumManifestName = "checksums.txt"

type ManagedTool string

const (
	ManagedToolNeovim  ManagedTool = "neovim"
	ManagedToolLazygit ManagedTool = "lazygit"
	ManagedToolFNM     ManagedTool = "fnm"
	ManagedToolUV      ManagedTool = "uv"
)

type ArtifactType string

const (
	ArtifactTypeRawExecutable ArtifactType = "raw_executable"
	ArtifactTypeTarGz         ArtifactType = "tar_gz"
	ArtifactTypeZip           ArtifactType = "zip"
)

type ToolLock struct {
	Tools map[ManagedTool]ToolVersion `json:"tools"`
}

type ToolVersion struct {
	Version string                                   `json:"version"`
	Targets map[platform.ArtifactTarget]ToolArtifact `json:"targets"`
}

type ToolArtifact struct {
	URL          string       `json:"url"`
	ArtifactType ArtifactType `json:"artifact_type"`
	SHA256       string       `json:"sha256"`
}

func LoadToolLock(path string) (ToolLock, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return ToolLock{}, err
	}
	return LoadToolLockBytes(data)
}

func LoadToolLockBytes(data []byte) (ToolLock, error) {
	var lock ToolLock
	if err := json.Unmarshal(data, &lock); err != nil {
		return ToolLock{}, err
	}
	return lock, nil
}

func ValidateToolLock(lock ToolLock) error {
	var problems []string
	for _, tool := range managedTools() {
		version, ok := lock.Tools[tool]
		if !ok {
			problems = append(problems, fmt.Sprintf("missing managed tool %s", tool))
			continue
		}
		if strings.TrimSpace(version.Version) == "" {
			problems = append(problems, fmt.Sprintf("%s missing version", tool))
		}
		for _, target := range platform.SupportedArtifactTargets() {
			artifact, ok := version.Targets[target]
			if !ok {
				problems = append(problems, fmt.Sprintf("%s missing target %s", tool, target))
				continue
			}
			if err := validateImmutableURL(artifact.URL); err != nil {
				problems = append(problems, fmt.Sprintf("%s %s URL %q is not immutable: %v", tool, target, artifact.URL, err))
			}
			if !validArtifactType(artifact.ArtifactType) {
				problems = append(problems, fmt.Sprintf("%s %s has invalid artifact type %q", tool, target, artifact.ArtifactType))
			}
			if !isSHA256(artifact.SHA256) {
				problems = append(problems, fmt.Sprintf("%s %s has invalid SHA-256 %q", tool, target, artifact.SHA256))
			}
		}
	}
	if len(problems) > 0 {
		return errors.New(strings.Join(problems, "; "))
	}
	return nil
}

func managedTools() []ManagedTool {
	return []ManagedTool{
		ManagedToolNeovim,
		ManagedToolLazygit,
		ManagedToolFNM,
		ManagedToolUV,
	}
}

func validateImmutableURL(raw string) error {
	parsed, err := url.Parse(raw)
	if err != nil {
		return err
	}
	if parsed.Scheme != "https" {
		return fmt.Errorf("scheme must be https")
	}
	if parsed.Host == "" {
		return fmt.Errorf("host is required")
	}
	lowerPath := strings.ToLower(parsed.EscapedPath())
	for _, mutable := range []string{"/latest", "/main", "/master", "/nightly"} {
		if strings.Contains(lowerPath, mutable) {
			return fmt.Errorf("contains mutable selector %s", mutable)
		}
	}
	return nil
}

func validArtifactType(kind ArtifactType) bool {
	switch kind {
	case ArtifactTypeRawExecutable, ArtifactTypeTarGz, ArtifactTypeZip:
		return true
	default:
		return false
	}
}

func isSHA256(value string) bool {
	if len(value) != sha256.Size*2 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func BinaryName(target platform.ArtifactTarget) string {
	return "plasticine_" + string(target.OS) + "_" + string(target.Arch)
}

type ArtifactReport struct {
	Artifacts []string
	Manifest  string
}

type BuildMetadata struct {
	Version    string
	Commit     string
	CommitTime string
}

func ValidateReleaseArtifacts(dir string, targets []platform.ArtifactTarget) (ArtifactReport, error) {
	if err := rejectArchiveWrapping(dir); err != nil {
		return ArtifactReport{}, err
	}
	manifestPath := filepath.Join(dir, ChecksumManifestName)
	manifest, err := readChecksumManifest(manifestPath)
	if err != nil {
		return ArtifactReport{}, err
	}
	report := ArtifactReport{Manifest: manifestPath}
	for _, target := range targets {
		name := BinaryName(target)
		path := filepath.Join(dir, name)
		info, err := os.Stat(path)
		if err != nil {
			return ArtifactReport{}, fmt.Errorf("missing raw executable %s: %w", name, err)
		}
		if info.IsDir() {
			return ArtifactReport{}, fmt.Errorf("raw executable %s is a directory", name)
		}
		if info.Mode()&0o111 == 0 {
			return ArtifactReport{}, fmt.Errorf("raw executable %s is not executable", name)
		}
		got, err := fileSHA256(path)
		if err != nil {
			return ArtifactReport{}, err
		}
		want, ok := manifest[name]
		if !ok {
			return ArtifactReport{}, fmt.Errorf("checksum manifest missing %s", name)
		}
		if got != want {
			return ArtifactReport{}, fmt.Errorf("checksum mismatch for %s", name)
		}
		report.Artifacts = append(report.Artifacts, path)
	}
	return report, nil
}

func WriteChecksumManifest(dir string, targets []platform.ArtifactTarget) error {
	lines := make([]string, 0, len(targets))
	for _, target := range targets {
		name := BinaryName(target)
		sum, err := fileSHA256(filepath.Join(dir, name))
		if err != nil {
			return err
		}
		lines = append(lines, fmt.Sprintf("%s  %s", sum, name))
	}
	sort.Strings(lines)
	return os.WriteFile(filepath.Join(dir, ChecksumManifestName), []byte(strings.Join(lines, "\n")+"\n"), 0o644)
}

func ValidateReleaseMetadata(dir string, targets []platform.ArtifactTarget, expected BuildMetadata) error {
	values := []struct {
		name  string
		value string
	}{
		{name: "version", value: expected.Version},
		{name: "commit", value: expected.Commit},
		{name: "commit_time", value: expected.CommitTime},
	}
	for _, item := range values {
		if strings.TrimSpace(item.value) == "" {
			return fmt.Errorf("missing expected %s metadata", item.name)
		}
	}
	for _, target := range targets {
		name := BinaryName(target)
		data, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return err
		}
		for _, item := range values {
			if !bytes.Contains(data, []byte(item.value)) {
				return fmt.Errorf("%s missing embedded %s metadata %q", name, item.name, item.value)
			}
		}
	}
	return nil
}

func CompareChecksumManifests(leftDir string, rightDir string) error {
	left, err := os.ReadFile(filepath.Join(leftDir, ChecksumManifestName))
	if err != nil {
		return err
	}
	right, err := os.ReadFile(filepath.Join(rightDir, ChecksumManifestName))
	if err != nil {
		return err
	}
	if string(left) != string(right) {
		return fmt.Errorf("reproducibility failure: checksum manifests differ")
	}
	return nil
}

func rejectArchiveWrapping(dir string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		name := entry.Name()
		if strings.HasPrefix(name, "plasticine_") && isArchiveName(name) {
			return fmt.Errorf("archive wrapping is not allowed: %s", name)
		}
	}
	return nil
}

func isArchiveName(name string) bool {
	for _, suffix := range []string{".tar", ".tar.gz", ".tgz", ".zip", ".gz"} {
		if strings.HasSuffix(name, suffix) {
			return true
		}
	}
	return false
}

func readChecksumManifest(path string) (map[string]string, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	checksums := make(map[string]string)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) != 2 {
			return nil, fmt.Errorf("invalid checksum manifest line %q", scanner.Text())
		}
		if !isSHA256(fields[0]) {
			return nil, fmt.Errorf("invalid checksum %q for %s", fields[0], fields[1])
		}
		checksums[fields[1]] = fields[0]
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return checksums, nil
}

func fileSHA256(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()

	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}
