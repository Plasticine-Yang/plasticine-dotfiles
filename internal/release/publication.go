package release

import (
	"fmt"
	"os"
	"regexp"
	"strings"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
)

const defaultReleaseDownloadBase = "https://github.com/Plasticine-Yang/plasticine-dotfiles/releases"

type ReleaseChannel string

const (
	ReleaseChannelStable     ReleaseChannel = "stable"
	ReleaseChannelPrerelease ReleaseChannel = "prerelease"
)

type PublicationRequest struct {
	Tag                 string
	Version             string
	AssetDir            string
	InstallScriptPath   string
	DownloadBase        string
	RequiredGatesPassed bool
	ExistingRelease     bool
	DirtyBuild          bool
}

type PublicationPlan struct {
	Tag                    string
	Version                string
	Channel                ReleaseChannel
	UpdatesLatestStable    bool
	LatestStableInstallURL string
	VersionInstallURL      string
	Artifacts              []string
	ChecksumManifest       string
	InstallScriptPath      string
}

var semverCorePattern = regexp.MustCompile(`^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`)

func PlanPublication(req PublicationRequest) (PublicationPlan, error) {
	if !req.RequiredGatesPassed {
		return PublicationPlan{}, fmt.Errorf("required release gates have not passed")
	}
	if req.ExistingRelease {
		return PublicationPlan{}, fmt.Errorf("release already exists: %s", strings.TrimSpace(req.Tag))
	}
	if req.DirtyBuild {
		return PublicationPlan{}, fmt.Errorf("dirty builds cannot be published")
	}

	tag := strings.TrimSpace(req.Tag)
	version := strings.TrimSpace(req.Version)
	if !validSemVerTag(tag) {
		return PublicationPlan{}, fmt.Errorf("publication requires a SemVer tag vX.Y.Z with optional prerelease: %s", tag)
	}
	if version == "dev" {
		return PublicationPlan{}, fmt.Errorf("development builds cannot be published")
	}
	if version != tag {
		return PublicationPlan{}, fmt.Errorf("tag/version mismatch: tag=%s version=%s", tag, version)
	}

	report, err := ValidateReleaseArtifacts(req.AssetDir, platform.SupportedArtifactTargets())
	if err != nil {
		return PublicationPlan{}, err
	}
	if err := validateInstallScriptAsset(req.InstallScriptPath); err != nil {
		return PublicationPlan{}, err
	}

	channel := ReleaseChannelStable
	updatesLatestStable := true
	if strings.Contains(tag, "-") {
		channel = ReleaseChannelPrerelease
		updatesLatestStable = false
	}
	downloadBase := strings.TrimRight(req.DownloadBase, "/")
	if downloadBase == "" {
		downloadBase = defaultReleaseDownloadBase
	}

	return PublicationPlan{
		Tag:                    tag,
		Version:                version,
		Channel:                channel,
		UpdatesLatestStable:    updatesLatestStable,
		LatestStableInstallURL: downloadBase + "/latest/download/install.sh",
		VersionInstallURL:      downloadBase + "/download/" + tag + "/install.sh",
		Artifacts:              report.Artifacts,
		ChecksumManifest:       report.Manifest,
		InstallScriptPath:      req.InstallScriptPath,
	}, nil
}

func validSemVerTag(tag string) bool {
	core, prerelease, hasPrerelease := strings.Cut(tag, "-")
	if !semverCorePattern.MatchString(core) {
		return false
	}
	if !hasPrerelease {
		return true
	}
	if prerelease == "" {
		return false
	}
	for _, identifier := range strings.Split(prerelease, ".") {
		if identifier == "" || !validPrereleaseIdentifier(identifier) {
			return false
		}
		if numericIdentifier(identifier) && len(identifier) > 1 && identifier[0] == '0' {
			return false
		}
	}
	return true
}

func validPrereleaseIdentifier(identifier string) bool {
	for _, r := range identifier {
		if (r >= '0' && r <= '9') || (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || r == '-' {
			continue
		}
		return false
	}
	return true
}

func numericIdentifier(identifier string) bool {
	for _, r := range identifier {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

func validateInstallScriptAsset(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("missing install.sh: %w", err)
	}
	if info.IsDir() {
		return fmt.Errorf("install.sh is a directory")
	}
	return nil
}
