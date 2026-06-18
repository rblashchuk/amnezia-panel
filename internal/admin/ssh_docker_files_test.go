package admin_test

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/rblashchuk/amnezia-panel/internal/admin"
)

func TestSSHDockerFilesRejectsPasswordOnlyAuth(t *testing.T) {
	files := admin.SSHDockerFiles{Config: admin.SSHConfig{
		AuthMethod: "password-only",
		Host:       "vpn.example.com",
		User:       "root",
		Port:       "22",
	}}

	_, err := files.ReadFile(t.Context(), "amnezia-wireguard", "/opt/amnezia/wireguard/clientsTable")

	require.Error(t, err)
	assert.Contains(t, err.Error(), "password-only SSH auth")
}

func TestSSHDockerFilesRequiresHost(t *testing.T) {
	files := admin.SSHDockerFiles{Config: admin.SSHConfig{
		AuthMethod: "default",
		User:       "root",
		Port:       "22",
	}}

	_, err := files.ReadFile(t.Context(), "amnezia-wireguard", "/opt/amnezia/wireguard/clientsTable")

	require.Error(t, err)
	assert.Contains(t, err.Error(), "ssh host is required")
}
