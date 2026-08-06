package main

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/x/term"

	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/candidate"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/platform"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/reconciler"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/release"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/tui"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/version"
	"github.com/Plasticine-Yang/plasticine-dotfiles/internal/workstation"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	if len(args) == 0 {
		return runTUI()
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
	case "upgrade":
		return runUpgrade(args[1:])
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

func runTUI() int {
	if !usableInteractiveTerminal(os.Stdin, os.Stdout, os.Getenv("TERM")) {
		fmt.Fprintln(os.Stderr, "interactive TUI requires a terminal; use an explicit subcommand")
		usage()
		return 2
	}
	runtime, err := workstation.New(workstation.Options{
		WorkstationRoot: os.Getenv("PLASTICINE_WORKSTATION_ROOT"),
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	reason, err := tui.Run(context.Background(), runtime, tui.IO{
		In:  os.Stdin,
		Out: os.Stdout,
		Err: os.Stderr,
		Env: map[string]string{
			"NO_COLOR": os.Getenv("NO_COLOR"),
		},
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "TUI failed: %v\n", err)
		return 1
	}
	return reason.Code()
}

func usableInteractiveTerminal(input *os.File, output *os.File, terminalType string) bool {
	if strings.EqualFold(strings.TrimSpace(terminalType), "dumb") {
		return false
	}
	return term.IsTerminal(input.Fd()) && term.IsTerminal(output.Fd())
}

func runUpgrade(applyArgs []string) int {
	plasticineHome, err := reconciler.DefaultPlasticineHome()
	if err != nil {
		fmt.Fprintf(os.Stderr, "resolve home: %v\n", err)
		return 1
	}
	target := workstation.CurrentTarget()
	if !supportedArtifactTarget(target) {
		fmt.Fprintf(os.Stderr, "unsupported artifact target: %s\n", target)
		return 1
	}
	binaryName := release.BinaryName(target)
	baseURL := upgradeAssetBaseURL()
	workDir := filepath.Join(plasticineHome, "bootstrap")
	candidatePath := filepath.Join(workDir, binaryName)
	manifestPath := filepath.Join(workDir, release.ChecksumManifestName)
	if err := os.MkdirAll(workDir, 0o700); err != nil {
		fmt.Fprintf(os.Stderr, "prepare bootstrap directory: %v\n", err)
		return 1
	}
	if err := downloadReleaseAsset(baseURL+"/"+binaryName, candidatePath); err != nil {
		fmt.Fprintf(os.Stderr, "download candidate: %v\n", err)
		return 1
	}
	if err := downloadReleaseAsset(baseURL+"/"+release.ChecksumManifestName, manifestPath); err != nil {
		fmt.Fprintf(os.Stderr, "download checksum manifest: %v\n", err)
		return 1
	}
	expected, err := checksumFromManifest(manifestPath, binaryName)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read checksum manifest: %v\n", err)
		return 1
	}
	actual, err := sha256File(candidatePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "checksum candidate: %v\n", err)
		return 1
	}
	if actual != expected {
		fmt.Fprintf(os.Stderr, "checksum mismatch for %s\n", binaryName)
		return 1
	}
	if err := os.Chmod(candidatePath, 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "mark candidate executable: %v\n", err)
		return 1
	}
	cmd := exec.Command(candidatePath, append([]string{"__candidate-self-install"}, applyArgs...)...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		if exit, ok := err.(*exec.ExitError); ok {
			return exit.ExitCode()
		}
		fmt.Fprintf(os.Stderr, "run candidate self-install: %v\n", err)
		return 1
	}
	return 0
}

func upgradeAssetBaseURL() string {
	downloadBase := strings.TrimRight(os.Getenv("PLASTICINE_DOWNLOAD_BASE"), "/")
	if downloadBase == "" {
		downloadBase = "https://github.com/Plasticine-Yang/plasticine-dotfiles/releases"
	}
	if selectedVersion := os.Getenv("PLASTICINE_VERSION"); selectedVersion != "" {
		return downloadBase + "/download/" + selectedVersion
	}
	return downloadBase + "/latest/download"
}

func downloadReleaseAsset(url string, destination string) error {
	partial := destination + ".partial"
	_ = os.Remove(partial)
	response, err := http.Get(url)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode > 299 {
		return fmt.Errorf("%s returned %s", url, response.Status)
	}
	target, err := os.OpenFile(partial, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(target, response.Body)
	closeErr := target.Close()
	if copyErr != nil {
		_ = os.Remove(partial)
		return copyErr
	}
	if closeErr != nil {
		_ = os.Remove(partial)
		return closeErr
	}
	return os.Rename(partial, destination)
}

func checksumFromManifest(path string, binaryName string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 2 && fields[1] == binaryName {
			return fields[0], nil
		}
	}
	return "", fmt.Errorf("checksum manifest missing %s", binaryName)
}

func sha256File(path string) (string, error) {
	source, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer source.Close()
	sum := sha256.New()
	if _, err := io.Copy(sum, source); err != nil {
		return "", err
	}
	return hex.EncodeToString(sum.Sum(nil)), nil
}

func supportedArtifactTarget(target platform.ArtifactTarget) bool {
	for _, supported := range platform.SupportedArtifactTargets() {
		if target == supported {
			return true
		}
	}
	return false
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
	skipLoginShell := flags.Bool("skip-login-shell", false, "skip login shell changes while keeping shell configuration active")
	adopt := flags.Bool("adopt", false, "adopt all conflicts in the current filtered plan")
	githubKey := flags.String("github-key", "", "explicit GitHub SSH private key path")
	colorValue := flags.String("color", "auto", "colorize output: auto, always, or never")
	var excludes componentListFlag
	var components componentListFlag
	flags.Var(&excludes, "exclude", "replace Workstation Scope with an excluded component (repeatable)")
	flags.Var(&components, "component", "narrow this run to an active component (repeatable)")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	color, err := parseColorMode(*colorValue)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	runtime, err := workstation.New(workstation.Options{
		Home:            *home,
		WorkstationRoot: os.Getenv("PLASTICINE_WORKSTATION_ROOT"),
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	req := runtime.Request()
	req.Yes = *yes
	req.AllowSystem = *allowSystem
	req.SkipLoginShell = *skipLoginShell
	req.ReplaceScope = excludes.set
	req.Exclude = excludes.values
	req.Components = components.values
	req.Adopt = *adopt
	req.IncludeGitHubSSH = *githubKey != ""
	req.GitHubKeyPath = *githubKey
	if *githubKey == "" && !*yes && (command == "plan" || command == "apply") {
		req.GitHubKeySelector = promptGitHubKeySelection
	}
	if command == "apply" && !*yes {
		req.Authorize = func(ctx context.Context, result reconciler.Result) reconciler.AuthorizationDecision {
			return promptApplyAuthorization(ctx, result, *allowSystem, *adopt)
		}
	}
	var (
		result reconciler.Result
		runErr error
	)
	switch command {
	case "plan":
		result, runErr = runtime.Reconciler.Plan(context.Background(), req)
	case "apply":
		result, runErr = runtime.Reconciler.Apply(context.Background(), req)
	case "doctor":
		result, runErr = runtime.Reconciler.Doctor(context.Background(), req)
	default:
		return 2
	}
	if runErr != nil {
		fmt.Fprintf(os.Stderr, "%s failed: %v\n", command, runErr)
		return 1
	}
	caps := defaultOutputCapabilities()
	caps.Color = color
	renderResult(os.Stdout, command, result, caps)
	switch result.Outcome {
	case reconciler.OutcomeChangesPlanned, reconciler.OutcomeApplied, reconciler.OutcomeNoChange, reconciler.OutcomeHealthy:
		return 0
	case reconciler.OutcomeDenied, reconciler.OutcomeBlocked, reconciler.OutcomePartial, reconciler.OutcomeUnhealthy:
		return 1
	default:
		return 1
	}
}

func promptApplyAuthorization(ctx context.Context, result reconciler.Result, allowSystem bool, allowAdoption bool) reconciler.AuthorizationDecision {
	printResultTo(os.Stdout, "apply-plan", result)
	if err := ctx.Err(); err != nil {
		return reconciler.AuthorizationDecision{}
	}
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		fmt.Fprintln(os.Stderr, "apply requires --yes when no controlling terminal is available")
		return reconciler.AuthorizationDecision{}
	}
	defer tty.Close()

	if _, err := fmt.Fprint(tty, "Apply this plan? Type yes to continue: "); err != nil {
		return reconciler.AuthorizationDecision{}
	}
	scanner := bufio.NewScanner(tty)
	if !scanner.Scan() {
		return reconciler.AuthorizationDecision{}
	}
	approved := strings.EqualFold(strings.TrimSpace(scanner.Text()), "yes")
	return reconciler.AuthorizationDecision{
		Approved:           approved,
		AllowSystemChanges: approved && allowSystem,
		AllowAdoption:      approved && allowAdoption,
		AllowRetirements:   approved,
	}
}

func promptGitHubKeySelection(ctx context.Context) (string, bool) {
	if err := ctx.Err(); err != nil {
		return "", false
	}
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		fmt.Fprintln(os.Stderr, "github-ssh requires --github-key when no controlling terminal is available")
		return "", false
	}
	defer tty.Close()

	if _, err := fmt.Fprintln(tty, "GitHub SSH requires an explicit private key path."); err != nil {
		return "", false
	}
	if _, err := fmt.Fprint(tty, "Path to GitHub SSH private key: "); err != nil {
		return "", false
	}
	scanner := bufio.NewScanner(tty)
	if !scanner.Scan() {
		return "", false
	}
	path := strings.TrimSpace(scanner.Text())
	if path == "" {
		return "", false
	}
	return path, true
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: plasticine <plan|apply|doctor|upgrade|version>")
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
