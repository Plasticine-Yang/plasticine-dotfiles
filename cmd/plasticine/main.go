package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	plasticine "github.com/Plasticine-Yang/plasticine-dotfiles"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/candidate"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
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
		StateCompatible:     candidate.ReadOnlyStateCompatible(plasticineHome),
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
	r := reconciler.New(reconciler.Options{
		DesiredStateID: desiredStateID(),
		ToolLockSHA256: toolLockSHA256(),
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
	}
	var (
		result reconciler.Result
		err    error
	)
	switch command {
	case "plan":
		result, err = r.Plan(context.Background(), req)
	case "apply":
		result, err = r.Apply(context.Background(), req)
	case "doctor":
		result, err = r.Doctor(context.Background(), req)
	default:
		return 2
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "%s failed: %v\n", command, err)
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
			family = platform.FamilyOtherLinux
		}
	}
	return platform.Host{
		OS:      target.OS,
		Arch:    target.Arch,
		Family:  family,
		Version: version,
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
	fmt.Printf("%s: %s\n", command, result.Outcome)
	fmt.Printf("target: %s\n", result.Target)
	fmt.Printf("support: %s\n", result.Support.Level)
	if result.DesiredStateID != "" {
		fmt.Printf("desired_state: %s\n", result.DesiredStateID)
	}
	for _, component := range result.Scope.Active {
		fmt.Printf("active_component: %s\n", component)
	}
	for _, component := range result.Scope.Excluded {
		fmt.Printf("excluded_component: %s\n", component)
	}
	if result.StateMigration != nil {
		fmt.Printf("state_migration: %d->%d %s\n", result.StateMigration.FromSchema, result.StateMigration.ToSchema, result.StateMigration.Message)
	}
	for _, change := range result.Changes {
		fmt.Printf("change: %s %s %s\n", change.Component, change.Kind, strings.TrimSpace(change.Summary))
	}
	for _, conflict := range result.Conflicts {
		fmt.Printf("conflict: %s adoptable=%t %s\n", conflict.Component, conflict.Adoptable, conflict.Path)
	}
	for _, retirement := range result.Retirements {
		fmt.Printf("retirement: %s %s\n", retirement.Component, retirement.Path)
	}
	for _, blocker := range result.Blockers {
		fmt.Printf("blocker: %s %s\n", blocker.Code, blocker.Message)
	}
	for _, effect := range result.DurableEffects {
		fmt.Printf("durable_effect: %s\n", effect)
	}
	for _, check := range result.Checks {
		status := "ok"
		if !check.Healthy {
			status = "failed"
		}
		fmt.Printf("check: %s %s %s\n", check.Name, status, strings.TrimSpace(check.Message))
	}
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
