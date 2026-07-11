package reconciler

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type reconciliationLockMode string

const (
	sharedLock    reconciliationLockMode = "shared"
	exclusiveLock reconciliationLockMode = "exclusive"
)

func acquireReconciliationLock(home string, mode reconciliationLockMode, skip bool) (func(), *Blocker, error) {
	if skip || os.Getenv("PLASTICINE_LOCK_HELD") == "1" {
		return func() {}, nil, nil
	}
	lockDir := filepath.Join(home, "locks")
	if err := os.MkdirAll(lockDir, 0o700); err != nil {
		return nil, nil, err
	}
	exclusivePath := filepath.Join(lockDir, "plasticine.lock")
	sharedDir := filepath.Join(lockDir, "plasticine.shared")

	switch mode {
	case sharedLock:
		if holder, ok := readLockHolder(exclusivePath); ok {
			return nil, &Blocker{Code: BlockerLockHeld, Message: "exclusive reconciliation lock is held by " + holder}, nil
		}
		if err := os.MkdirAll(sharedDir, 0o700); err != nil {
			return nil, nil, err
		}
		sharedPath := filepath.Join(sharedDir, fmt.Sprintf("%d.lock", os.Getpid()))
		if err := os.WriteFile(sharedPath, []byte(lockHolder()), 0o600); err != nil {
			return nil, nil, err
		}
		if holder, ok := readLockHolder(exclusivePath); ok {
			_ = os.Remove(sharedPath)
			return nil, &Blocker{Code: BlockerLockHeld, Message: "exclusive reconciliation lock is held by " + holder}, nil
		}
		return func() { _ = os.Remove(sharedPath) }, nil, nil
	case exclusiveLock:
		if holder, ok := readLockHolder(exclusivePath); ok {
			return nil, &Blocker{Code: BlockerLockHeld, Message: "exclusive reconciliation lock is held by " + holder}, nil
		}
		if holders := sharedLockHolders(sharedDir); len(holders) > 0 {
			return nil, &Blocker{Code: BlockerLockHeld, Message: "shared reconciliation lock is held by " + strings.Join(holders, ", ")}, nil
		}
		file, err := os.OpenFile(exclusivePath, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
		if os.IsExist(err) {
			holder, _ := readLockHolder(exclusivePath)
			return nil, &Blocker{Code: BlockerLockHeld, Message: "exclusive reconciliation lock is held by " + holder}, nil
		}
		if err != nil {
			return nil, nil, err
		}
		if _, err := file.WriteString(lockHolder()); err != nil {
			_ = file.Close()
			_ = os.Remove(exclusivePath)
			return nil, nil, err
		}
		if holders := sharedLockHolders(sharedDir); len(holders) > 0 {
			_ = file.Close()
			_ = os.Remove(exclusivePath)
			return nil, &Blocker{Code: BlockerLockHeld, Message: "shared reconciliation lock is held by " + strings.Join(holders, ", ")}, nil
		}
		return func() {
			_ = file.Close()
			_ = os.Remove(exclusivePath)
		}, nil, nil
	default:
		return nil, nil, fmt.Errorf("unknown reconciliation lock mode %q", mode)
	}
}

func readLockHolder(path string) (string, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", false
	}
	holder := strings.TrimSpace(string(data))
	if holder == "" {
		holder = path
	}
	return holder, true
}

func sharedLockHolders(sharedDir string) []string {
	entries, err := os.ReadDir(sharedDir)
	if err != nil {
		return nil
	}
	var holders []string
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		holder, ok := readLockHolder(filepath.Join(sharedDir, entry.Name()))
		if ok {
			holders = append(holders, holder)
		}
	}
	return holders
}

func lockHolder() string {
	return fmt.Sprintf("pid=%d command=%s\n", os.Getpid(), strings.Join(os.Args, " "))
}
