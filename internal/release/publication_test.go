package release_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/release"
)

func TestPublicationPlanClassifiesStableAndPrerelease(t *testing.T) {
	t.Parallel()

	stableDir, stableInstall := completePublicationAssets(t)
	stable, err := release.PlanPublication(release.PublicationRequest{
		Tag:                 "v1.2.3",
		Version:             "v1.2.3",
		AssetDir:            stableDir,
		InstallScriptPath:   stableInstall,
		RequiredGatesPassed: true,
	})
	if err != nil {
		t.Fatalf("plan stable publication: %v", err)
	}
	if stable.Channel != release.ReleaseChannelStable {
		t.Fatalf("stable channel = %q, want %q", stable.Channel, release.ReleaseChannelStable)
	}
	if !stable.UpdatesLatestStable {
		t.Fatal("stable publication did not update the latest-stable channel")
	}
	if stable.LatestStableInstallURL != "https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh" {
		t.Fatalf("latest stable URL = %q", stable.LatestStableInstallURL)
	}

	prereleaseDir, prereleaseInstall := completePublicationAssets(t)
	prerelease, err := release.PlanPublication(release.PublicationRequest{
		Tag:                 "v1.2.4-rc.1",
		Version:             "v1.2.4-rc.1",
		AssetDir:            prereleaseDir,
		InstallScriptPath:   prereleaseInstall,
		RequiredGatesPassed: true,
	})
	if err != nil {
		t.Fatalf("plan prerelease publication: %v", err)
	}
	if prerelease.Channel != release.ReleaseChannelPrerelease {
		t.Fatalf("prerelease channel = %q, want %q", prerelease.Channel, release.ReleaseChannelPrerelease)
	}
	if prerelease.UpdatesLatestStable {
		t.Fatal("prerelease publication updated the latest-stable channel")
	}
	if prerelease.VersionInstallURL != "https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/download/v1.2.4-rc.1/install.sh" {
		t.Fatalf("version install URL = %q", prerelease.VersionInstallURL)
	}
}

func TestPublicationPlanRejectsMissingAssetsBeforeRelease(t *testing.T) {
	t.Parallel()

	assetDir, installScript := completePublicationAssets(t)
	if err := os.Remove(filepath.Join(assetDir, release.BinaryName(platform.TargetLinuxARM64))); err != nil {
		t.Fatalf("remove asset: %v", err)
	}

	_, err := release.PlanPublication(release.PublicationRequest{
		Tag:                 "v1.2.3",
		Version:             "v1.2.3",
		AssetDir:            assetDir,
		InstallScriptPath:   installScript,
		RequiredGatesPassed: true,
	})
	if err == nil {
		t.Fatal("publication with missing asset planned successfully")
	}
	if !strings.Contains(err.Error(), "missing raw executable") {
		t.Fatalf("error = %q, want missing raw executable", err.Error())
	}
}

func TestPublicationPlanRejectsFailedGateDuplicateAndDirtyBuild(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		name string
		req  release.PublicationRequest
		want string
	}{
		{
			name: "failed gate",
			req: release.PublicationRequest{
				Tag:                 "v1.2.3",
				Version:             "v1.2.3",
				RequiredGatesPassed: false,
			},
			want: "required release gates have not passed",
		},
		{
			name: "duplicate release",
			req: release.PublicationRequest{
				Tag:                 "v1.2.3",
				Version:             "v1.2.3",
				RequiredGatesPassed: true,
				ExistingRelease:     true,
			},
			want: "release already exists",
		},
		{
			name: "dirty build",
			req: release.PublicationRequest{
				Tag:                 "v1.2.3",
				Version:             "v1.2.3",
				RequiredGatesPassed: true,
				DirtyBuild:          true,
			},
			want: "dirty builds cannot be published",
		},
	} {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			_, err := release.PlanPublication(tc.req)
			if err == nil {
				t.Fatal("publication planned successfully")
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error = %q, want %q", err.Error(), tc.want)
			}
		})
	}
}

func TestPublicationPlanRejectsTagVersionMismatchAndDevelopmentVersion(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		name string
		req  release.PublicationRequest
		want string
	}{
		{
			name: "tag version mismatch",
			req: release.PublicationRequest{
				Tag:                 "v1.2.3",
				Version:             "v1.2.4",
				RequiredGatesPassed: true,
			},
			want: "tag/version mismatch",
		},
		{
			name: "development version",
			req: release.PublicationRequest{
				Tag:                 "v1.2.3",
				Version:             "dev",
				RequiredGatesPassed: true,
			},
			want: "development builds cannot be published",
		},
		{
			name: "invalid semver tag",
			req: release.PublicationRequest{
				Tag:                 "latest",
				Version:             "latest",
				RequiredGatesPassed: true,
			},
			want: "SemVer tag",
		},
		{
			name: "empty prerelease identifier",
			req: release.PublicationRequest{
				Tag:                 "v1.2.3-rc..1",
				Version:             "v1.2.3-rc..1",
				RequiredGatesPassed: true,
			},
			want: "SemVer tag",
		},
		{
			name: "numeric prerelease leading zero",
			req: release.PublicationRequest{
				Tag:                 "v1.2.3-01",
				Version:             "v1.2.3-01",
				RequiredGatesPassed: true,
			},
			want: "SemVer tag",
		},
	} {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			_, err := release.PlanPublication(tc.req)
			if err == nil {
				t.Fatal("publication planned successfully")
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error = %q, want %q", err.Error(), tc.want)
			}
		})
	}
}

func completePublicationAssets(t *testing.T) (string, string) {
	t.Helper()

	dir := t.TempDir()
	for _, target := range platform.SupportedArtifactTargets() {
		writeExecutable(t, filepath.Join(dir, release.BinaryName(target)), "binary-"+target.String())
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
