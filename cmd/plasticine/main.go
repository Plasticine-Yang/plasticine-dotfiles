package main

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"runtime"
	"strings"

	plasticine "github.com/Plasticine-Yang/plasticine-dotfiles"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/candidate"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/release"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/version"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	if len(args) == 0 {
		usage()
		return 2
	}
	switch args[0] {
	case "version":
		fmt.Println(version.Current().String())
		return 0
	case "plan":
		return runReconcilerCommand(args[0], args[1:])
	case "apply":
		return runReconcilerCommand(args[0], args[1:])
	case "doctor":
		return runReconcilerCommand(args[0], args[1:])
	case "__candidate-self-install":
		if version.Current().Version == "dev" {
			fmt.Fprintln(os.Stderr, "development builds cannot use candidate self-install")
			return 1
		}
		return runCandidateSelfInstall(args[1:])
	default:
		usage()
		return 2
	}
}

func runCandidateSelfInstall(args []string) int {
	plasticineHome, err := reconciler.DefaultPlasticineHome()
	if err != nil {
		fmt.Fprintf(os.Stderr, "resolve home: %v\n", err)
		return 1
	}
	executable, err := os.Executable()
	if err != nil {
		fmt.Fprintf(os.Stderr, "resolve candidate executable: %v\n", err)
		return 1
	}
	installPath := filepath.Join(plasticineHome, "bin", "plasticine")
	result, err := candidate.SelfInstall(context.Background(), candidate.Request{
		Home:                plasticineHome,
		CurrentExecutable:   installPath,
		CandidateExecutable: executable,
		InstallPath:         installPath,
		StateCompatibility: func() candidate.StateCompatibilityResult {
			return candidate.ReadOnlyStateCompatibility(plasticineHome)
		},
		FirstApply: func(context.Context) error {
			previousLockEnv, hadLockEnv := os.LookupEnv("PLASTICINE_LOCK_HELD")
			if err := os.Setenv("PLASTICINE_LOCK_HELD", "1"); err != nil {
				return err
			}
			defer func() {
				if hadLockEnv {
					_ = os.Setenv("PLASTICINE_LOCK_HELD", previousLockEnv)
				} else {
					_ = os.Unsetenv("PLASTICINE_LOCK_HELD")
				}
			}()
			if code := runReconcilerCommand("apply", args); code != 0 {
				return fmt.Errorf("first apply exited with %d", code)
			}
			return nil
		},
	})
	fmt.Printf("candidate_self_install: %s\n", result.Outcome)
	if err != nil {
		fmt.Fprintf(os.Stderr, "candidate self-install failed: %v\n", err)
		return 1
	}
	if result.Outcome != candidate.OutcomeInstalled {
		return 1
	}
	return 0
}

func runReconcilerCommand(command string, args []string) int {
	flags := flag.NewFlagSet(command, flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	home := flags.String("home", "", "Plasticine home")
	yes := flags.Bool("yes", false, "authorize non-interactive apply")
	allowSystem := flags.Bool("allow-system", false, "authorize planned system changes")
	adopt := flags.Bool("adopt", false, "adopt all conflicts in the current filtered plan")
	githubKey := flags.String("github-key", "", "explicit GitHub SSH private key path")
	var excludes componentListFlag
	var components componentListFlag
	flags.Var(&excludes, "exclude", "replace Workstation Scope with an excluded component (repeatable)")
	flags.Var(&components, "component", "narrow this run to an active component (repeatable)")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	plasticineHome := *home
	if plasticineHome == "" {
		var err error
		plasticineHome, err = reconciler.DefaultPlasticineHome()
		if err != nil {
			fmt.Fprintf(os.Stderr, "resolve home: %v\n", err)
			return 1
		}
	}
	workstationRoot := os.Getenv("PLASTICINE_WORKSTATION_ROOT")
	if workstationRoot == "" {
		var err error
		workstationRoot, err = os.UserHomeDir()
		if err != nil {
			fmt.Fprintf(os.Stderr, "resolve workstation root: %v\n", err)
			return 1
		}
	}
	target := currentTarget()
	host := currentHost(target)
	toolLock, err := release.LoadToolLockBytes(plasticine.DefaultToolLockJSON)
	if err != nil {
		fmt.Fprintf(os.Stderr, "load embedded tool lock: %v\n", err)
		return 1
	}
	loginShell, loginShellKnown := currentLoginShell()
	zshPath := desiredZshPath(target)
	r := reconciler.New(reconciler.Options{
		DesiredStateID: desiredStateID(),
		ToolLockSHA256: toolLockSHA256(),
		ToolLock:       toolLock,
		DiagnosticURLs: []string{"https://github.com"},
		System:         reconciler.LocalSystemAdapter{},
	})
	req := reconciler.Request{
		Home:             plasticineHome,
		WorkstationRoot:  workstationRoot,
		Target:           target,
		Host:             host,
		Yes:              *yes,
		AllowSystem:      *allowSystem,
		ReplaceScope:     excludes.set,
		Exclude:          excludes.values,
		Components:       components.values,
		Adopt:            *adopt,
		IncludeGitHubSSH: *githubKey != "",
		GitHubKeyPath:    *githubKey,
		LoginShell:       loginShell,
		LoginShellKnown:  loginShellKnown,
		ZshPath:          zshPath,
	}
	if command == "apply" && !*yes {
		req.Authorize = promptApplyAuthorization
	}
	var (
		result reconciler.Result
		runErr error
	)
	switch command {
	case "plan":
		result, runErr = r.Plan(context.Background(), req)
	case "apply":
		result, runErr = r.Apply(context.Background(), req)
	case "doctor":
		result, runErr = r.Doctor(context.Background(), req)
	default:
		return 2
	}
	if runErr != nil {
		fmt.Fprintf(os.Stderr, "%s failed: %v\n", command, runErr)
		return 1
	}
	printResult(command, result)
	switch result.Outcome {
	case reconciler.OutcomeChangesPlanned, reconciler.OutcomeApplied, reconciler.OutcomeNoChange, reconciler.OutcomeHealthy:
		return 0
	case reconciler.OutcomeDenied, reconciler.OutcomeBlocked, reconciler.OutcomePartial, reconciler.OutcomeUnhealthy:
		return 1
	default:
		return 1
	}
}

func currentTarget() platform.ArtifactTarget {
	target, err := platform.ParseArtifactTarget(runtime.GOOS + "/" + runtime.GOARCH)
	if err == nil {
		return target
	}
	return platform.ArtifactTarget{OS: platform.OS(runtime.GOOS), Arch: platform.Arch(runtime.GOARCH)}
}

func currentHost(target platform.ArtifactTarget) platform.Host {
	family := platform.Family(os.Getenv("PLASTICINE_HOST_FAMILY"))
	version := os.Getenv("PLASTICINE_HOST_VERSION")
	if family == "" {
		if target.OS == platform.OSDarwin {
			family = platform.FamilyMacOS
			if version == "" {
				version = "13.0"
			}
		} else {
			family, version = linuxHostFamilyVersion(version)
		}
	}
	return platform.Host{
		OS:      target.OS,
		Arch:    target.Arch,
		Family:  family,
		Version: version,
	}
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
	version := versionOverride
	if version == "" {
		version = values["VERSION_ID"]
	}
	return family, version
}

func currentLoginShell() (string, bool) {
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

func desiredZshPath(target platform.ArtifactTarget) string {
	switch target.OS {
	case platform.OSDarwin:
		return "/bin/zsh"
	case platform.OSLinux:
		return "/usr/bin/zsh"
	default:
		return ""
	}
}

func desiredStateID() string {
	sum := sha256.Sum256([]byte("components:shell,git-config,github-ssh,neovim,lazygit,fnm,uv\n"))
	return hex.EncodeToString(sum[:])
}

func toolLockSHA256() string {
	sum := sha256.Sum256(plasticine.DefaultToolLockJSON)
	return hex.EncodeToString(sum[:])
}

func printResult(command string, result reconciler.Result) {
	printResultTo(os.Stdout, command, result)
}

func printResultTo(writer io.Writer, command string, result reconciler.Result) {
	fmt.Fprintf(writer, "%s: %s\n", command, result.Outcome)
	fmt.Fprintf(writer, "target: %s\n", result.Target)
	fmt.Fprintf(writer, "support: %s\n", result.Support.Level)
	if result.DesiredStateID != "" {
		fmt.Fprintf(writer, "desired_state: %s\n", result.DesiredStateID)
	}
	for _, component := range result.Scope.Active {
		fmt.Fprintf(writer, "active_component: %s\n", component)
	}
	for _, component := range result.Scope.Excluded {
		fmt.Fprintf(writer, "excluded_component: %s\n", component)
	}
	for _, component := range result.Components {
		message := strings.TrimSpace(component.Message)
		if message == "" {
			fmt.Fprintf(writer, "component: %s %s\n", component.Component, component.Status)
			continue
		}
		fmt.Fprintf(writer, "component: %s %s %s\n", component.Component, component.Status, message)
	}
	if result.StateMigration != nil {
		fmt.Fprintf(writer, "state_migration: %d->%d %s\n", result.StateMigration.FromSchema, result.StateMigration.ToSchema, result.StateMigration.Message)
	}
	for _, change := range result.Changes {
		scope := "user"
		if change.SystemChange {
			scope = "system"
		}
		if change.Path != "" {
			fmt.Fprintf(writer, "change: %s %s %s %s %s\n", change.Component, change.Kind, scope, change.Path, strings.TrimSpace(change.Summary))
			continue
		}
		fmt.Fprintf(writer, "change: %s %s %s %s\n", change.Component, change.Kind, scope, strings.TrimSpace(change.Summary))
	}
	for _, conflict := range result.Conflicts {
		fmt.Fprintf(writer, "conflict: %s adoptable=%t %s\n", conflict.Component, conflict.Adoptable, conflict.Path)
	}
	for _, retirement := range result.Retirements {
		fmt.Fprintf(writer, "retirement: %s %s\n", retirement.Component, retirement.Path)
	}
	for _, blocker := range result.Blockers {
		fmt.Fprintf(writer, "blocker: %s %s\n", blocker.Code, blocker.Message)
	}
	for _, effect := range result.DurableEffects {
		fmt.Fprintf(writer, "durable_effect: %s\n", effect)
	}
	for _, check := range result.Checks {
		status := "ok"
		if !check.Healthy {
			status = "failed"
		}
		fmt.Fprintf(writer, "check: %s %s %s\n", check.Name, status, strings.TrimSpace(check.Message))
	}
}

func promptApplyAuthorization(result reconciler.Result) bool {
	printResultTo(os.Stdout, "apply-plan", result)
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		fmt.Fprintln(os.Stderr, "apply requires --yes when no controlling terminal is available")
		return false
	}
	defer tty.Close()

	if _, err := fmt.Fprint(tty, "Apply this plan? Type yes to continue: "); err != nil {
		return false
	}
	scanner := bufio.NewScanner(tty)
	if !scanner.Scan() {
		return false
	}
	return strings.EqualFold(strings.TrimSpace(scanner.Text()), "yes")
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: plasticine <plan|apply|doctor|version>")
}

type componentListFlag struct {
	values []reconciler.ComponentID
	set    bool
}

func (flag *componentListFlag) String() string {
	parts := make([]string, 0, len(flag.values))
	for _, value := range flag.values {
		parts = append(parts, string(value))
	}
	return strings.Join(parts, ",")
}

func (flag *componentListFlag) Set(value string) error {
	flag.set = true
	for _, part := range strings.Split(value, ",") {
		component := strings.TrimSpace(part)
		if component == "" {
			continue
		}
		flag.values = append(flag.values, reconciler.ComponentID(component))
	}
	return nil
}
