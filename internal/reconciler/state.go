package reconciler

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type loadedState struct {
	State     State
	Exists    bool
	Migration *StateMigration
}

func StatePath(home string) string {
	return filepath.Join(home, "state", "reconciliation.json")
}

func DefaultPlasticineHome() (string, error) {
	if home := os.Getenv("PLASTICINE_HOME"); home != "" {
		return home, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".plasticine"), nil
}

func ReadState(home string) (State, error) {
	loaded, err := loadState(home)
	if err != nil {
		return State{}, err
	}
	if !loaded.Exists {
		return State{}, os.ErrNotExist
	}
	return loaded.State, nil
}

func loadState(home string) (loadedState, error) {
	data, err := os.ReadFile(StatePath(home))
	if os.IsNotExist(err) {
		return loadedState{State: emptyState(), Exists: false}, nil
	}
	if err != nil {
		return loadedState{}, err
	}

	var raw struct {
		SchemaVersion int `json:"schema_version"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return loadedState{}, fmt.Errorf("decode reconciliation state: %w", err)
	}
	if raw.SchemaVersion > CurrentStateSchema {
		return loadedState{}, fmt.Errorf("reconciliation state schema %d is newer than supported schema %d", raw.SchemaVersion, CurrentStateSchema)
	}

	var state State
	if err := json.Unmarshal(data, &state); err != nil {
		return loadedState{}, fmt.Errorf("decode reconciliation state: %w", err)
	}
	ensureStateMaps(&state)
	if raw.SchemaVersion == 0 {
		state.SchemaVersion = CurrentStateSchema
		return loadedState{
			State:  state,
			Exists: true,
			Migration: &StateMigration{
				FromSchema: 0,
				ToSchema:   CurrentStateSchema,
				Message:    "legacy state will be migrated to the current reconciliation schema",
			},
		}, nil
	}
	state.SchemaVersion = raw.SchemaVersion
	if state.SchemaVersion < CurrentStateSchema {
		from := state.SchemaVersion
		state.SchemaVersion = CurrentStateSchema
		return loadedState{
			State:  state,
			Exists: true,
			Migration: &StateMigration{
				FromSchema: from,
				ToSchema:   CurrentStateSchema,
				Message:    "state schema migration is required before mutation",
			},
		}, nil
	}
	return loadedState{State: state, Exists: true}, nil
}

func emptyState() State {
	state := State{SchemaVersion: CurrentStateSchema}
	ensureStateMaps(&state)
	return state
}

func ensureStateMaps(state *State) {
	if state.Ownership == nil {
		state.Ownership = map[string]Ownership{}
	}
	if state.SecretReferences == nil {
		state.SecretReferences = map[ComponentID]SecretReference{}
	}
}

func writeState(home string, state State) error {
	state.SchemaVersion = CurrentStateSchema
	ensureStateMaps(&state)
	path := StatePath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return err
	}
	tempPath := path + ".tmp"
	if err := os.WriteFile(tempPath, append(data, '\n'), 0o600); err != nil {
		return err
	}
	return os.Rename(tempPath, path)
}
