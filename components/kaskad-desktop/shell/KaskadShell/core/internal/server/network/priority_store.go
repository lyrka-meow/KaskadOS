package network

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

func connectionPreferencePath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "KaskadShell", "network-preference.json"), nil
}

func loadConnectionPreference() (ConnectionPreference, bool, error) {
	path, err := connectionPreferencePath()
	if err != nil {
		return PreferenceAuto, false, err
	}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return PreferenceAuto, false, nil
	}
	if err != nil {
		return PreferenceAuto, false, err
	}
	var stored PriorityUpdate
	if err := json.Unmarshal(data, &stored); err != nil {
		return PreferenceAuto, false, err
	}
	if !validConnectionPreference(stored.Preference) {
		return PreferenceAuto, false, fmt.Errorf("invalid saved network preference")
	}
	return stored.Preference, true, nil
}

func saveConnectionPreference(pref ConnectionPreference) error {
	if !validConnectionPreference(pref) {
		return fmt.Errorf("invalid preference: %s", pref)
	}
	path, err := connectionPreferencePath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".network-preference-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	defer file.Close()
	if err := json.NewEncoder(file).Encode(PriorityUpdate{Preference: pref}); err != nil {
		return err
	}
	if err := file.Sync(); err != nil {
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(file.Name(), path)
}
