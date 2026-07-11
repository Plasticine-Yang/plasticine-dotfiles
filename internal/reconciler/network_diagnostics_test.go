package reconciler

import (
	"context"
	"errors"
	"testing"
)

func TestGitHubSSHDiagnosticClassifiesFailures(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		name    string
		ctx     context.Context
		output  string
		err     error
		healthy bool
		message string
	}{
		{
			name:    "success",
			ctx:     context.Background(),
			output:  "Hi user! You've successfully authenticated, but GitHub does not provide shell access.",
			healthy: true,
			message: "GitHub accepted the configured key",
		},
		{
			name:    "host key",
			ctx:     context.Background(),
			output:  "Host key verification failed.",
			err:     errors.New("exit status 255"),
			message: "host-key: GitHub host key verification failed",
		},
		{
			name:    "authentication",
			ctx:     context.Background(),
			output:  "git@github.com: Permission denied (publickey).",
			err:     errors.New("exit status 255"),
			message: "authentication: GitHub rejected the configured key",
		},
		{
			name:    "timeout",
			ctx:     canceledContext(t),
			err:     context.DeadlineExceeded,
			message: "interrupted: GitHub SSH diagnostic canceled",
		},
		{
			name:    "deadline",
			ctx:     deadlineContext(t),
			err:     context.DeadlineExceeded,
			message: "timeout: GitHub SSH diagnostic timed out",
		},
		{
			name:    "network unreachable",
			ctx:     context.Background(),
			err:     errors.New("ssh: connect to host github.com port 22: No route to host"),
			message: "network-unreachable: GitHub SSH endpoint is unreachable",
		},
	} {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			check := githubSSHDiagnosticCheck(tc.ctx, []byte(tc.output), tc.err)
			if check.Name != "github-ssh" {
				t.Fatalf("check name = %q", check.Name)
			}
			if check.Healthy != tc.healthy {
				t.Fatalf("healthy = %t, want %t", check.Healthy, tc.healthy)
			}
			if check.Message != tc.message {
				t.Fatalf("message = %q, want %q", check.Message, tc.message)
			}
		})
	}
}

func canceledContext(t *testing.T) context.Context {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	return ctx
}

func deadlineContext(t *testing.T) context.Context {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 0)
	defer cancel()
	<-ctx.Done()
	return ctx
}
