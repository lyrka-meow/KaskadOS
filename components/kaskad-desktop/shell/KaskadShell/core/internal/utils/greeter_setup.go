package utils

import (
	"bufio"
	"fmt"
	"os/exec"
	"strings"
)

// RunKaskadGreeterInstall delegates greeter setup to the standalone kaskad-shell-greeter
// binary, which owns greetd configuration since the greeter moved out of Kaskad.
func RunKaskadGreeterInstall(sudoPassword string, logFunc func(string)) error {
	binary, err := exec.LookPath("kaskad-shell-greeter")
	if err != nil {
		return fmt.Errorf("kaskad-shell-greeter binary not found; install the kaskad-shell-greeter package and run 'kaskad-shell-greeter install'")
	}

	var cmd *exec.Cmd
	if sudoPassword == "" {
		cmd = exec.Command(binary, "install", "--yes")
	} else {
		cmd = exec.Command("sudo", "-S", "-p", "", binary, "install", "--yes")
		cmd.Stdin = strings.NewReader(sudoPassword + "\n")
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	cmd.Stderr = cmd.Stdout

	if err := cmd.Start(); err != nil {
		return err
	}
	scanner := bufio.NewScanner(stdout)
	for scanner.Scan() {
		logFunc(scanner.Text())
	}
	return cmd.Wait()
}
