package admin

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

type SSHConfig struct {
	AuthMethod string
	Host       string
	User       string
	Port       string
	KeyPath    string
}

type SSHDockerFiles struct {
	Config SSHConfig
}

func (f SSHDockerFiles) ReadFile(ctx context.Context, container, path string) ([]byte, error) {
	if err := validateDockerFileTarget(container, path); err != nil {
		return nil, err
	}

	command := sudoDockerCommand(fmt.Sprintf(
		"exec %s sh -c %s",
		shellQuote(container),
		shellQuote("cat "+shellQuote(path)),
	))
	return f.run(ctx, nil, command)
}

func (f SSHDockerFiles) WriteFileAtomic(ctx context.Context, container, path string, data []byte) error {
	if err := validateDockerFileTarget(container, path); err != nil {
		return err
	}

	tmpPath := fmt.Sprintf("%s.amnezia-panel-%d.tmp", path, time.Now().UnixNano())
	script := fmt.Sprintf(
		"set -e; tmp=%s; cat > \"$tmp\"; chmod 600 \"$tmp\"; mv \"$tmp\" %s",
		shellQuote(tmpPath),
		shellQuote(path),
	)
	command := sudoDockerCommand(fmt.Sprintf(
		"exec -i %s sh -c %s",
		shellQuote(container),
		shellQuote(script),
	))
	_, err := f.run(ctx, data, command)
	return err
}

func (f SSHDockerFiles) run(ctx context.Context, stdin []byte, remoteCommand string) ([]byte, error) {
	args, err := f.sshArgs(remoteCommand)
	if err != nil {
		return nil, err
	}

	cmd := exec.CommandContext(ctx, "ssh", args...)
	if stdin != nil {
		cmd.Stdin = bytes.NewReader(stdin)
	}

	out, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("ssh command failed: %s: %w", strings.TrimSpace(string(out)), err)
	}
	return out, nil
}

func (f SSHDockerFiles) sshArgs(remoteCommand string) ([]string, error) {
	config := f.Config
	if config.AuthMethod == "password-only" {
		return nil, errors.New("password-only SSH auth is not available for non-interactive admin operations")
	}
	if config.Host == "" {
		return nil, errors.New("ssh host is required")
	}

	target := config.Host
	args := []string{
		"-o", "BatchMode=yes",
		"-o", "ServerAliveInterval=30",
		"-o", "ServerAliveCountMax=3",
	}

	if config.AuthMethod != "ssh-config" {
		if config.User == "" {
			return nil, errors.New("ssh user is required")
		}
		target = config.User + "@" + config.Host
		if config.Port != "" {
			args = append(args, "-p", config.Port)
		}
	}
	if config.AuthMethod == "identity-file" {
		if config.KeyPath == "" {
			return nil, errors.New("ssh key path is required")
		}
		args = append(args, "-i", config.KeyPath)
	}

	args = append(args, target, remoteCommand)
	return args, nil
}

func validateDockerFileTarget(container, path string) error {
	if strings.TrimSpace(container) == "" {
		return errors.New("container is required")
	}
	if strings.TrimSpace(path) == "" {
		return errors.New("path is required")
	}
	return nil
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\"'\"'") + "'"
}

func sudoDockerCommand(args string) string {
	return fmt.Sprintf(`if [ "$(id -u)" -eq 0 ]; then docker %s; else sudo -n docker %s; fi`, args, args)
}
