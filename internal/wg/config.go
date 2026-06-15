package wg

import (
	"fmt"
	"strings"
)

func SourcesFromEnv(endpoints, legacyMode, legacyContainer, legacyCommand string) ([]Source, error) {
	if endpoints != "" {
		return parseEndpoints(endpoints)
	}

	switch legacyMode {
	case "", "docker":
		return []Source{
			&DockerSource{
				ID:        "wireguard",
				Protocol:  "wireguard",
				Label:     "WireGuard",
				Container: fallback(legacyContainer, "amnezia-wireguard"),
				Command:   "wg",
			},
		}, nil
	case "local":
		return []Source{
			&LocalSource{
				ID:       "wireguard",
				Protocol: "wireguard",
				Label:    "WireGuard",
				Command:  fallback(legacyCommand, "wg"),
			},
		}, nil
	default:
		return nil, fmt.Errorf("unsupported VPN_SOURCE %q", legacyMode)
	}
}

func parseEndpoints(value string) ([]Source, error) {
	parts := strings.Split(value, ",")
	sources := make([]Source, 0, len(parts))

	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}

		fields := strings.Split(part, ":")
		if len(fields) != 3 {
			return nil, fmt.Errorf("invalid VPN_ENDPOINTS entry %q, expected protocol:container:command", part)
		}

		protocol := strings.TrimSpace(fields[0])
		container := strings.TrimSpace(fields[1])
		command := strings.TrimSpace(fields[2])

		if protocol == "" || container == "" || command == "" {
			return nil, fmt.Errorf("invalid VPN_ENDPOINTS entry %q, empty field", part)
		}

		sources = append(sources, &DockerSource{
			ID:        protocol,
			Protocol:  protocol,
			Label:     labelFor(protocol),
			Container: container,
			Command:   command,
		})
	}

	if len(sources) == 0 {
		return nil, fmt.Errorf("VPN_ENDPOINTS did not contain any sources")
	}

	return sources, nil
}

func labelFor(protocol string) string {
	switch protocol {
	case "awg":
		return "AmneziaWG"
	case "wireguard":
		return "WireGuard"
	default:
		return strings.ToUpper(protocol)
	}
}

func fallback(value, defaultValue string) string {
	if value == "" {
		return defaultValue
	}
	return value
}
