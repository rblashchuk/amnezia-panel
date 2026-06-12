package wg

import (
	"context"
	"fmt"
	"os/exec"
)

type Source interface {
	Dump(ctx context.Context) ([]byte, error)
}

type DockerSource struct {
	Container string
}

func (s *DockerSource) Dump(ctx context.Context) ([]byte, error) {
	cmd := exec.CommandContext(
		ctx,
		"docker",
		"exec",
		s.Container,
		"wg",
		"show",
		"all",
		"dump",
	)

	out, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("wg error: %s: %w", string(out), err)
	}
	return out, nil
}

type LocalSource struct {
	Command string
}

func (s *LocalSource) Dump(ctx context.Context) ([]byte, error) {
	command := s.Command
	if command == "" {
		command = "wg"
	}

	cmd := exec.CommandContext(
		ctx,
		command,
		"show",
		"all",
		"dump",
	)

	out, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("wg error: %s: %w", string(out), err)
	}
	return out, nil
}
