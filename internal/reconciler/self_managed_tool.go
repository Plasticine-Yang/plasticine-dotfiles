package reconciler

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const traexSessionManagerInstallerURL = "https://raw.githubusercontent.com/Plasticine-Yang/traex-session-manager/main/install.sh"

type selfManagedTool struct {
	Component     ComponentID
	InstallerURL  string
	PrimaryPath   func(Request) string
	HealthArgs    []string
	Prerequisites []Capability
	Timeout       time.Duration
}

func selfManagedTools() []selfManagedTool {
	return []selfManagedTool{
		{
			Component:    ComponentTraexSessionManager,
			InstallerURL: traexSessionManagerInstallerURL,
			PrimaryPath: func(req Request) string {
				return filepath.Join(workstationRoot(req), ".local", "bin", "tsm")
			},
			HealthArgs:    []string{"--version"},
			Prerequisites: []Capability{CapabilityCurl, CapabilityTar, CapabilitySHA256Verifier},
			Timeout:       2 * time.Minute,
		},
	}
}

func selfManagedToolFor(component ComponentID) (selfManagedTool, bool) {
	for _, tool := range selfManagedTools() {
		if tool.Component == component {
			return tool, true
		}
	}
	return selfManagedTool{}, false
}

func (tool selfManagedTool) validate() error {
	installerURL, err := url.Parse(tool.InstallerURL)
	if err != nil || installerURL.Scheme != "https" || installerURL.Host == "" {
		return fmt.Errorf("%s Self-managed Tool installer must be a Release-declared HTTPS URL", tool.Component)
	}
	if tool.PrimaryPath == nil || len(tool.HealthArgs) == 0 || tool.Timeout <= 0 {
		return fmt.Errorf("%s Self-managed Tool descriptor is incomplete", tool.Component)
	}
	return nil
}

func (tool selfManagedTool) healthy(ctx context.Context, req Request) bool {
	path := tool.PrimaryPath(req)
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0o111 == 0 {
		return false
	}
	command := exec.CommandContext(ctx, path, tool.HealthArgs...)
	command.Env = installerEnvironment(req)
	return command.Run() == nil
}

func selfManagedDoctorChecks(ctx context.Context, req Request, loaded loadedState) []Check {
	excluded := WorkstationScope{}.Excluded
	if loaded.Exists {
		excluded = loaded.State.Scope.Excluded
	}
	if req.ReplaceScope {
		excluded = req.Exclude
	}
	excludedSet := componentSet(excluded)
	filtered := componentSet(req.Components)
	var checks []Check
	for _, tool := range selfManagedTools() {
		if excludedSet[tool.Component] || len(filtered) > 0 && !filtered[tool.Component] {
			continue
		}
		healthy := tool.healthy(ctx, req)
		message := tool.PrimaryPath(req)
		if healthy {
			message += " reports a version"
		} else {
			message += " cannot report a version"
		}
		checks = append(checks, Check{
			Name:    "self-managed:" + string(tool.Component),
			Healthy: healthy,
			Message: message,
		})
	}
	return checks
}

func (s *planSnapshot) planSelfManagedTools(ctx context.Context, req Request) error {
	for _, component := range sortedComponentsFromSet(s.Active) {
		tool, ok := selfManagedToolFor(component)
		if !ok {
			continue
		}
		if err := tool.validate(); err != nil {
			s.block(BlockerOperationalFailure, err.Error())
			continue
		}
		if tool.healthy(ctx, req) {
			continue
		}
		s.Result.Changes = append(s.Result.Changes, Change{
			Component:    component,
			Kind:         ChangeRunExternalInstaller,
			ResourceKind: ResourceSelfManagedTool,
			Path:         tool.InstallerURL,
			Summary:      "run opaque external script installer; downstream files and selected version are controlled by upstream",
		})
	}
	return nil
}

func (s *planSnapshot) selfManagedInstallerPlanned(component ComponentID) bool {
	for _, change := range s.Result.Changes {
		if change.Component == component && change.Kind == ChangeRunExternalInstaller {
			return true
		}
	}
	return false
}

func (r Reconciler) applySelfManagedTool(ctx context.Context, req Request, change Change) error {
	tool, ok := selfManagedToolFor(change.Component)
	if !ok {
		return fmt.Errorf("unknown Self-managed Tool component %s", change.Component)
	}
	if err := tool.validate(); err != nil {
		return err
	}
	installCtx, cancel := context.WithTimeout(ctx, tool.Timeout)
	defer cancel()

	tempDir, err := os.MkdirTemp("", "plasticine-external-installer-*")
	if err != nil {
		return fmt.Errorf("prepare private installer directory: %w", err)
	}
	defer os.RemoveAll(tempDir)
	if err := os.Chmod(tempDir, 0o700); err != nil {
		return fmt.Errorf("secure private installer directory: %w", err)
	}
	scriptPath := filepath.Join(tempDir, "install.sh")
	if err := downloadExternalInstaller(installCtx, r.httpClient, tool.InstallerURL, scriptPath); err != nil {
		return fmt.Errorf("%s installer download failed: %w", tool.Component, err)
	}
	command := ExternalInstallerCommand{
		Component:   tool.Component,
		ScriptPath:  scriptPath,
		Environment: environmentMap(installerEnvironment(req)),
		Stdout:      req.InstallerStdout,
		Stderr:      req.InstallerStderr,
	}
	if command.Stdout == nil {
		command.Stdout = os.Stdout
	}
	if command.Stderr == nil {
		command.Stderr = os.Stderr
	}
	runner := r.installerRunner
	if runner == nil {
		runner = runExternalInstaller
	}
	if err := runner(installCtx, command); err != nil {
		if errors.Is(err, context.DeadlineExceeded) || errors.Is(installCtx.Err(), context.DeadlineExceeded) {
			return fmt.Errorf("%s installer timed out: %w", tool.Component, context.DeadlineExceeded)
		}
		if installCtx.Err() != nil {
			return fmt.Errorf("%s installer interrupted or timed out: %w", tool.Component, installCtx.Err())
		}
		return fmt.Errorf("%s installer failed: %w", tool.Component, err)
	}
	if !tool.healthy(installCtx, req) {
		return fmt.Errorf("%s installer completed but primary executable failed its health command", tool.Component)
	}
	return nil
}

func downloadExternalInstaller(ctx context.Context, client *http.Client, sourceURL string, destination string) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, sourceURL, nil)
	if err != nil {
		return err
	}
	response, err := client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode > 299 {
		return fmt.Errorf("%s returned %s", redactCredentialURL(sourceURL), response.Status)
	}
	target, err := os.OpenFile(destination, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(target, response.Body)
	closeErr := target.Close()
	if copyErr != nil {
		return copyErr
	}
	return closeErr
}

func runExternalInstaller(ctx context.Context, installer ExternalInstallerCommand) error {
	command := exec.CommandContext(ctx, "/bin/sh", installer.ScriptPath)
	command.Env = environmentSlice(installer.Environment)
	command.Stdout = installer.Stdout
	command.Stderr = installer.Stderr
	return command.Run()
}

func installerEnvironment(req Request) []string {
	environment := environmentMap(os.Environ())
	environment["HOME"] = workstationRoot(req)
	return environmentSlice(environment)
}

func environmentMap(values []string) map[string]string {
	environment := make(map[string]string, len(values))
	for _, value := range values {
		key, item, ok := strings.Cut(value, "=")
		if ok {
			environment[key] = item
		}
	}
	return environment
}

func environmentSlice(environment map[string]string) []string {
	values := make([]string, 0, len(environment))
	for key, value := range environment {
		values = append(values, key+"="+value)
	}
	return values
}
