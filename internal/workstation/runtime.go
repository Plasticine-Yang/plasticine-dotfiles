package workstation

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"runtime"
	"strings"

	plasticine "github.com/Plasticine-Yang/plasticine-dotfiles"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/release"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/version"
)

type Options struct {
	Home            string
	WorkstationRoot string
	System          reconciler.SystemAdapter
	DiagnosticURLs  []string
}

type Runtime struct {
	Reconciler reconciler.Reconciler
	Target     platform.ArtifactTarget
	Host       platform.Host
	Version    version.Info

	baseRequest reconciler.Request
}

func New(options Options) (Runtime, error) {
	home := options.Home
	if home == "" {
		var err error
		home, err = reconciler.DefaultPlasticineHome()
		if err != nil {
			return Runtime{}, fmt.Errorf("resolve home: %w", err)
		}
	}
	workstationRoot := options.WorkstationRoot
	if workstationRoot == "" {
		var err error
		workstationRoot, err = os.UserHomeDir()
		if err != nil {
			return Runtime{}, fmt.Errorf("resolve workstation root: %w", err)
		}
	}
	toolLock, err := release.LoadToolLockBytes(plasticine.DefaultToolLockJSON)
	if err != nil {
		return Runtime{}, fmt.Errorf("load embedded tool lock: %w", err)
	}
	target := CurrentTarget()
	host := CurrentHost(target)
	loginShell, loginShellKnown := CurrentLoginShell()
	system := options.System
	if system == nil {
		system = reconciler.LocalSystemAdapter{}
	}
	diagnosticURLs := options.DiagnosticURLs
	if diagnosticURLs == nil {
		diagnosticURLs = []string{"https://github.com"}
	}
	return Runtime{
		Reconciler: reconciler.New(reconciler.Options{
			DesiredStateID: DesiredStateID(),
			ToolLockSHA256: ToolLockSHA256(),
			ToolLock:       toolLock,
			DiagnosticURLs: diagnosticURLs,
			System:         system,
		}),
		Target:  target,
		Host:    host,
		Version: version.Current(),
		baseRequest: reconciler.Request{
			Home:            home,
			WorkstationRoot: workstationRoot,
			Target:          target,
			Host:            host,
			LoginShell:      loginShell,
			LoginShellKnown: loginShellKnown,
			ZshPath:         DesiredZshPath(target),
		},
	}, nil
}

func (runtime Runtime) Request() reconciler.Request {
	request := runtime.baseRequest
	request.Exclude = append([]reconciler.ComponentID(nil), request.Exclude...)
	request.Components = append([]reconciler.ComponentID(nil), request.Components...)
	if request.Capabilities != nil {
		request.Capabilities = make(map[reconciler.Capability]bool, len(runtime.baseRequest.Capabilities))
		for capability, available := range runtime.baseRequest.Capabilities {
			request.Capabilities[capability] = available
		}
	}
	request.NetworkChecks = append([]reconciler.Check(nil), request.NetworkChecks...)
	return request
}

func CurrentTarget() platform.ArtifactTarget {
	target, err := platform.ParseArtifactTarget(runtime.GOOS + "/" + runtime.GOARCH)
	if err == nil {
		return target
	}
	return platform.ArtifactTarget{OS: platform.OS(runtime.GOOS), Arch: platform.Arch(runtime.GOARCH)}
}

func CurrentHost(target platform.ArtifactTarget) platform.Host {
	family := platform.Family(os.Getenv("PLASTICINE_HOST_FAMILY"))
	hostVersion := os.Getenv("PLASTICINE_HOST_VERSION")
	if family == "" {
		if target.OS == platform.OSDarwin {
			family = platform.FamilyMacOS
			if hostVersion == "" {
				hostVersion = "13.0"
			}
		} else {
			family, hostVersion = linuxHostFamilyVersion(hostVersion)
		}
	}
	return platform.Host{
		OS:      target.OS,
		Arch:    target.Arch,
		Family:  family,
		Version: hostVersion,
	}
}

func CurrentLoginShell() (string, bool) {
	currentUser, err := user.Current()
	if err != nil {
		return "", false
	}
	if runtime.GOOS == "darwin" {
		output, err := exec.Command("dscl", ".", "-read", "/Users/"+currentUser.Username, "UserShell").Output()
		if err == nil {
			fields := strings.Fields(string(output))
			if len(fields) > 0 {
				return fields[len(fields)-1], true
			}
		}
	}
	data, err := os.ReadFile("/etc/passwd")
	if err != nil {
		return "", false
	}
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Split(line, ":")
		if len(fields) < 7 {
			continue
		}
		if fields[0] == currentUser.Username || fields[2] == currentUser.Uid {
			return fields[6], true
		}
	}
	return "", false
}

func DesiredZshPath(target platform.ArtifactTarget) string {
	switch target.OS {
	case platform.OSDarwin:
		return "/bin/zsh"
	case platform.OSLinux:
		return "/usr/bin/zsh"
	default:
		return ""
	}
}

func DesiredStateID() string {
	components := reconciler.ComponentCatalog()
	ids := make([]string, 0, len(components))
	for _, component := range components {
		ids = append(ids, string(component.ID))
	}
	sum := sha256.Sum256([]byte("components:" + strings.Join(ids, ",") + "\n"))
	return hex.EncodeToString(sum[:])
}

func ToolLockSHA256() string {
	sum := sha256.Sum256(plasticine.DefaultToolLockJSON)
	return hex.EncodeToString(sum[:])
}

func linuxHostFamilyVersion(versionOverride string) (platform.Family, string) {
	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return platform.FamilyOtherLinux, versionOverride
	}
	values := map[string]string{}
	for _, line := range strings.Split(string(data), "\n") {
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		values[key] = strings.Trim(value, `"`)
	}
	family := platform.FamilyOtherLinux
	switch strings.ToLower(values["ID"]) {
	case "debian":
		family = platform.FamilyDebian
	case "ubuntu":
		family = platform.FamilyUbuntu
	}
	hostVersion := versionOverride
	if hostVersion == "" {
		hostVersion = values["VERSION_ID"]
	}
	return family, hostVersion
}
