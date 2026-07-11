package platform

import (
	"fmt"
	"strconv"
	"strings"
)

type OS string

const (
	OSDarwin OS = "darwin"
	OSLinux  OS = "linux"
)

type Arch string

const (
	ArchAMD64 Arch = "amd64"
	ArchARM64 Arch = "arm64"
)

type Family string

const (
	FamilyMacOS      Family = "macos"
	FamilyDebian     Family = "debian"
	FamilyUbuntu     Family = "ubuntu"
	FamilyOtherLinux Family = "other-linux"
)

type ArtifactTarget struct {
	OS   OS   `json:"os"`
	Arch Arch `json:"arch"`
}

var (
	TargetDarwinAMD64 = ArtifactTarget{OS: OSDarwin, Arch: ArchAMD64}
	TargetDarwinARM64 = ArtifactTarget{OS: OSDarwin, Arch: ArchARM64}
	TargetLinuxAMD64  = ArtifactTarget{OS: OSLinux, Arch: ArchAMD64}
	TargetLinuxARM64  = ArtifactTarget{OS: OSLinux, Arch: ArchARM64}
)

func (target ArtifactTarget) String() string {
	return string(target.OS) + "/" + string(target.Arch)
}

func (target ArtifactTarget) MarshalText() ([]byte, error) {
	return []byte(target.String()), nil
}

func (target *ArtifactTarget) UnmarshalText(text []byte) error {
	parsed, err := ParseArtifactTarget(string(text))
	if err != nil {
		return err
	}
	*target = parsed
	return nil
}

func ParseArtifactTarget(value string) (ArtifactTarget, error) {
	switch value {
	case TargetDarwinAMD64.String():
		return TargetDarwinAMD64, nil
	case TargetDarwinARM64.String():
		return TargetDarwinARM64, nil
	case TargetLinuxAMD64.String():
		return TargetLinuxAMD64, nil
	case TargetLinuxARM64.String():
		return TargetLinuxARM64, nil
	default:
		return ArtifactTarget{}, fmt.Errorf("unsupported artifact target %q", value)
	}
}

func SupportedArtifactTargets() []ArtifactTarget {
	return []ArtifactTarget{
		TargetDarwinAMD64,
		TargetDarwinARM64,
		TargetLinuxAMD64,
		TargetLinuxARM64,
	}
}

type Host struct {
	OS      OS
	Arch    Arch
	Family  Family
	Version string
}

type SupportLevel string

const (
	SupportFull           SupportLevel = "full"
	SupportUserScopedOnly SupportLevel = "user-scoped-only"
	SupportUnsupported    SupportLevel = "unsupported"
)

type SupportClassification struct {
	Level  SupportLevel
	Reason string
}

func ClassifySupport(host Host) SupportClassification {
	if !isSupportedArch(host.Arch) {
		return SupportClassification{Level: SupportUnsupported, Reason: "unsupported architecture"}
	}
	if host.OS == OSDarwin {
		if host.Family != FamilyMacOS {
			return SupportClassification{Level: SupportUnsupported, Reason: "darwin host must be macOS"}
		}
		if versionAtLeast(host.Version, "13.0") {
			return SupportClassification{Level: SupportFull, Reason: "macOS support floor met"}
		}
		return SupportClassification{Level: SupportUserScopedOnly, Reason: "macOS support floor not met"}
	}
	if host.OS != OSLinux {
		return SupportClassification{Level: SupportUnsupported, Reason: "unsupported operating system"}
	}
	switch host.Family {
	case FamilyDebian:
		if versionAtLeast(host.Version, "12") {
			return SupportClassification{Level: SupportFull, Reason: "Debian support floor met"}
		}
		return SupportClassification{Level: SupportUserScopedOnly, Reason: "Debian support floor not met"}
	case FamilyUbuntu:
		if versionAtLeast(host.Version, "22.04") {
			return SupportClassification{Level: SupportFull, Reason: "Ubuntu support floor met"}
		}
		return SupportClassification{Level: SupportUserScopedOnly, Reason: "Ubuntu support floor not met"}
	case FamilyOtherLinux:
		return SupportClassification{Level: SupportUserScopedOnly, Reason: "other Linux is user-scoped only"}
	default:
		return SupportClassification{Level: SupportUserScopedOnly, Reason: "unknown Linux family is user-scoped only"}
	}
}

func isSupportedArch(arch Arch) bool {
	return arch == ArchAMD64 || arch == ArchARM64
}

func versionAtLeast(got string, floor string) bool {
	gotParts := parseVersion(got)
	floorParts := parseVersion(floor)
	maxLen := len(gotParts)
	if len(floorParts) > maxLen {
		maxLen = len(floorParts)
	}
	for len(gotParts) < maxLen {
		gotParts = append(gotParts, 0)
	}
	for len(floorParts) < maxLen {
		floorParts = append(floorParts, 0)
	}
	for index := 0; index < maxLen; index++ {
		if gotParts[index] > floorParts[index] {
			return true
		}
		if gotParts[index] < floorParts[index] {
			return false
		}
	}
	return true
}

func parseVersion(value string) []int {
	parts := strings.Split(value, ".")
	parsed := make([]int, 0, len(parts))
	for _, part := range parts {
		number, err := strconv.Atoi(part)
		if err != nil {
			parsed = append(parsed, 0)
			continue
		}
		parsed = append(parsed, number)
	}
	return parsed
}
