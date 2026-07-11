package reconciler

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"sort"
	"strings"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
)

var ErrOwnerActionRequired = errors.New("owner action required")

type SystemAdapter interface {
	MissingCapabilities(context.Context, Request, []ComponentID) ([]Capability, error)
	ApplySystemDependencies(context.Context, Request, []Capability) ([]string, error)
}

type LocalSystemAdapter struct{}

func (LocalSystemAdapter) MissingCapabilities(ctx context.Context, req Request, active []ComponentID) ([]Capability, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	required := requiredCapabilities(active, req)
	var missing []Capability
	for _, capability := range required {
		if !localCapabilityPresent(req, capability) {
			missing = append(missing, capability)
		}
	}
	return missing, nil
}

func (LocalSystemAdapter) ApplySystemDependencies(ctx context.Context, req Request, missing []Capability) ([]string, error) {
	if len(missing) == 0 {
		return nil, nil
	}
	switch req.Host.Family {
	case platform.FamilyDebian, platform.FamilyUbuntu:
		packages := aptPackagesFor(missing)
		if len(packages) == 0 {
			return nil, nil
		}
		if err := exec.CommandContext(ctx, "sudo", "apt-get", "update").Run(); err != nil {
			return nil, err
		}
		args := append([]string{"apt-get", "install", "-y", "--no-install-recommends"}, packages...)
		if err := exec.CommandContext(ctx, "sudo", args...).Run(); err != nil {
			return nil, err
		}
		return []string{"apt-get update", "apt-get install --no-install-recommends " + strings.Join(packages, " ")}, nil
	case platform.FamilyMacOS:
		if containsCapability(missing, CapabilityAppleDevelopmentTools) {
			if err := exec.CommandContext(ctx, "xcode-select", "--install").Run(); err != nil {
				return nil, err
			}
			return []string{"xcode-select --install"}, fmt.Errorf("%w: complete Apple Command Line Tools installer and rerun apply", ErrOwnerActionRequired)
		}
		return nil, fmt.Errorf("missing macOS capabilities require Owner action: %v", missing)
	default:
		return nil, fmt.Errorf("unsupported system dependency changes on %s", req.Host.Family)
	}
}

func localCapabilityPresent(req Request, capability Capability) bool {
	switch capability {
	case CapabilityGit:
		return commandExists("git")
	case CapabilityZsh:
		return commandExists("zsh")
	case CapabilityOpenSSH:
		return commandExists("ssh") && commandExists("ssh-keygen")
	case CapabilityCA:
		for _, path := range []string{"/etc/ssl/certs/ca-certificates.crt", "/etc/ssl/cert.pem", "/etc/pki/tls/certs/ca-bundle.crt"} {
			if _, err := os.Stat(path); err == nil {
				return true
			}
		}
		return runtime.GOOS == "darwin"
	case CapabilityAppleDevelopmentTools:
		if req.Host.Family != platform.FamilyMacOS {
			return true
		}
		return exec.Command("xcode-select", "-p").Run() == nil
	case CapabilitySystemdUserSession:
		if req.Host.OS != platform.OSLinux {
			return true
		}
		if os.Getenv("XDG_RUNTIME_DIR") == "" {
			return false
		}
		return exec.Command("systemctl", "--user", "show-environment").Run() == nil
	default:
		return false
	}
}

func commandExists(name string) bool {
	_, err := exec.LookPath(name)
	return err == nil
}

func requiredCapabilities(active []ComponentID, req Request) []Capability {
	required := map[Capability]bool{}
	for _, component := range active {
		switch component {
		case ComponentShell:
			required[CapabilityGit] = true
			required[CapabilityZsh] = true
			required[CapabilityCA] = true
		case ComponentGitConfig:
			required[CapabilityGit] = true
		case ComponentGitHubSSH:
			required[CapabilityGit] = true
			required[CapabilityOpenSSH] = true
			required[CapabilityCA] = true
			if req.Target.OS == platform.OSLinux {
				required[CapabilitySystemdUserSession] = true
			}
			if req.Target.OS == platform.OSDarwin {
				required[CapabilityAppleDevelopmentTools] = true
			}
		case ComponentNeovim, ComponentLazygit:
			required[CapabilityGit] = true
			required[CapabilityCA] = true
		case ComponentFNM, ComponentUV:
			required[CapabilityCA] = true
		}
	}
	values := make([]Capability, 0, len(required))
	for capability := range required {
		values = append(values, capability)
	}
	sort.Slice(values, func(i int, j int) bool { return values[i] < values[j] })
	return values
}

func aptPackagesFor(capabilities []Capability) []string {
	packages := map[string]bool{}
	for _, capability := range capabilities {
		switch capability {
		case CapabilityGit:
			packages["git"] = true
		case CapabilityZsh:
			packages["zsh"] = true
		case CapabilityOpenSSH:
			packages["openssh-client"] = true
		case CapabilityCA:
			packages["ca-certificates"] = true
		}
	}
	values := make([]string, 0, len(packages))
	for pkg := range packages {
		values = append(values, pkg)
	}
	sort.Strings(values)
	return values
}

func containsCapability(values []Capability, want Capability) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}
