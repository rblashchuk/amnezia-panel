package wg

import (
	"context"
	"fmt"
	"os/exec"

	"github.com/rblashchuk/amnezia-panel/internal/model"
)

type Source interface {
	Info() model.Source
	Dump(ctx context.Context) ([]byte, error)
	Clients(ctx context.Context) (map[string]model.ClientMetadata, error)
}

type DockerSource struct {
	ID        string
	Protocol  string
	Label     string
	Container string
	Command   string
}

func (s *DockerSource) Info() model.Source {
	return model.Source{
		ID:        s.ID,
		Protocol:  s.Protocol,
		Label:     s.Label,
		Container: s.Container,
		Command:   s.command(),
		Mode:      "docker",
	}
}

func (s *DockerSource) Dump(ctx context.Context) ([]byte, error) {
	command := s.command()

	cmd := exec.CommandContext(
		ctx,
		"docker",
		"exec",
		s.Container,
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

func (s *DockerSource) Clients(ctx context.Context) (map[string]model.ClientMetadata, error) {
	path := clientsTablePath(s.Protocol)
	if path == "" {
		return map[string]model.ClientMetadata{}, nil
	}

	cmd := exec.CommandContext(
		ctx,
		"docker",
		"exec",
		s.Container,
		"sh",
		"-c",
		fmt.Sprintf("cat %s 2>/dev/null || true", path),
	)

	out, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("clientsTable error: %s: %w", string(out), err)
	}

	return ParseClientsTable(out)
}

func (s *DockerSource) command() string {
	if s.Command != "" {
		return s.Command
	}
	if s.Protocol == "awg" {
		return "awg"
	}
	return "wg"
}

type LocalSource struct {
	ID       string
	Protocol string
	Label    string
	Command  string
}

func (s *LocalSource) Info() model.Source {
	return model.Source{
		ID:       s.ID,
		Protocol: s.Protocol,
		Label:    s.Label,
		Command:  s.command(),
		Mode:     "local",
	}
}

func (s *LocalSource) Dump(ctx context.Context) ([]byte, error) {
	command := s.command()

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

func (s *LocalSource) Clients(ctx context.Context) (map[string]model.ClientMetadata, error) {
	return map[string]model.ClientMetadata{}, nil
}

func (s *LocalSource) command() string {
	if s.Command != "" {
		return s.Command
	}
	if s.Protocol == "awg" {
		return "awg"
	}
	return "wg"
}

func clientsTablePath(protocol string) string {
	switch protocol {
	case "wireguard":
		return "/opt/amnezia/wireguard/clientsTable"
	case "awg":
		return "/opt/amnezia/awg/clientsTable"
	case "openvpn":
		return "/opt/amnezia/openvpn/clientsTable"
	case "xray":
		return "/opt/amnezia/xray/clientsTable"
	default:
		return ""
	}
}
