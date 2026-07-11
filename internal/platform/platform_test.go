package platform_test

import (
	"testing"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
)

func TestArtifactTargetsAreFiniteAndNamed(t *testing.T) {
	t.Parallel()

	targets := platform.SupportedArtifactTargets()
	if len(targets) != 4 {
		t.Fatalf("target count = %d, want 4", len(targets))
	}
	want := map[platform.ArtifactTarget]bool{
		platform.TargetDarwinAMD64: false,
		platform.TargetDarwinARM64: false,
		platform.TargetLinuxAMD64:  false,
		platform.TargetLinuxARM64:  false,
	}
	for _, target := range targets {
		seen, ok := want[target]
		if !ok {
			t.Fatalf("unexpected target %s", target)
		}
		if seen {
			t.Fatalf("duplicate target %s", target)
		}
		want[target] = true
	}
}

func TestSupportFloorsAreDeterministic(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		host platform.Host
		want platform.SupportLevel
	}{
		{
			name: "macOS 13 is full",
			host: platform.Host{OS: platform.OSDarwin, Arch: platform.ArchARM64, Family: platform.FamilyMacOS, Version: "13.0"},
			want: platform.SupportFull,
		},
		{
			name: "macOS 12 can run binary but not full system changes",
			host: platform.Host{OS: platform.OSDarwin, Arch: platform.ArchARM64, Family: platform.FamilyMacOS, Version: "12.6"},
			want: platform.SupportUserScopedOnly,
		},
		{
			name: "Debian 12 is full",
			host: platform.Host{OS: platform.OSLinux, Arch: platform.ArchAMD64, Family: platform.FamilyDebian, Version: "12"},
			want: platform.SupportFull,
		},
		{
			name: "Ubuntu 22.04 is full",
			host: platform.Host{OS: platform.OSLinux, Arch: platform.ArchARM64, Family: platform.FamilyUbuntu, Version: "22.04"},
			want: platform.SupportFull,
		},
		{
			name: "other Linux is user scoped only",
			host: platform.Host{OS: platform.OSLinux, Arch: platform.ArchAMD64, Family: platform.FamilyOtherLinux, Version: "39"},
			want: platform.SupportUserScopedOnly,
		},
		{
			name: "unsupported architecture is rejected",
			host: platform.Host{OS: platform.OSLinux, Arch: "386", Family: platform.FamilyDebian, Version: "12"},
			want: platform.SupportUnsupported,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got := platform.ClassifySupport(tt.host)
			if got.Level != tt.want {
				t.Fatalf("support = %s, want %s (%s)", got.Level, tt.want, got.Reason)
			}
		})
	}
}
