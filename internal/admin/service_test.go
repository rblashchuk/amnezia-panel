package admin_test

import (
	"context"
	"errors"
	"sync"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/rblashchuk/amnezia-panel/internal/admin"
	"github.com/rblashchuk/amnezia-panel/internal/wg"
)

func TestServiceRenameClient(t *testing.T) {
	files := newMemoryFiles(map[string][]byte{
		wg.ClientsTablePath("wireguard"): []byte(`[
  {
    "clientId": "peer-public-key",
    "userData": {
      "clientName": "Alice iPhone",
      "latestHandshake": "5m"
    }
  }
]`),
	})
	service := admin.Service{Files: files}

	result, err := service.RenameClient(context.Background(), admin.RenameClientRequest{
		Protocol:  "wireguard",
		Container: "amnezia-wireguard",
		ClientID:  "peer-public-key",
		Name:      "Alice MacBook",
	})

	require.NoError(t, err)
	assert.Equal(t, "wireguard", result.Protocol)
	assert.Equal(t, "amnezia-wireguard", result.Container)
	assert.Equal(t, "peer-public-key", result.ClientID)
	assert.Equal(t, "Alice MacBook", result.Name)
	assert.Equal(t, wg.ClientsTablePath("wireguard"), result.Path)

	clients, err := wg.ParseClientsTable(files.files[wg.ClientsTablePath("wireguard")])
	require.NoError(t, err)
	assert.Equal(t, "Alice MacBook", clients["peer-public-key"].Name)
}

func TestServiceRenameClientRejectsUnsupportedProtocol(t *testing.T) {
	service := admin.Service{Files: newMemoryFiles(nil)}

	_, err := service.RenameClient(context.Background(), admin.RenameClientRequest{
		Protocol:  "x-wireguard",
		Container: "amnezia-wireguard",
		ClientID:  "peer-public-key",
		Name:      "Alice MacBook",
	})

	assert.True(t, errors.Is(err, admin.ErrUnsupportedProtocol))
}

func TestServiceRenameClientReturnsVerificationFailed(t *testing.T) {
	path := wg.ClientsTablePath("wireguard")
	files := newMemoryFiles(map[string][]byte{
		path: []byte(`[
  {
    "clientId": "peer-public-key",
    "userData": {
      "clientName": "Alice iPhone"
    }
  }
]`),
	})
	files.ignoreWrites = true

	service := admin.Service{Files: files}

	_, err := service.RenameClient(context.Background(), admin.RenameClientRequest{
		Protocol:  "wireguard",
		Container: "amnezia-wireguard",
		ClientID:  "peer-public-key",
		Name:      "Alice MacBook",
	})

	assert.True(t, errors.Is(err, admin.ErrVerificationFailed))
}

func TestServiceRenameClientUsesOperationLock(t *testing.T) {
	lock := &admin.OperationLock{}
	require.True(t, lock.TryLock())
	defer lock.Unlock()

	service := admin.Service{
		Files: newMemoryFiles(nil),
		Lock:  lock,
	}

	_, err := service.RenameClient(context.Background(), admin.RenameClientRequest{
		Protocol:  "wireguard",
		Container: "amnezia-wireguard",
		ClientID:  "peer-public-key",
		Name:      "Alice MacBook",
	})

	assert.True(t, errors.Is(err, admin.ErrOperationInProgress))
}

type memoryFiles struct {
	mu           sync.Mutex
	files        map[string][]byte
	ignoreWrites bool
}

func newMemoryFiles(files map[string][]byte) *memoryFiles {
	if files == nil {
		files = map[string][]byte{}
	}
	return &memoryFiles{files: files}
}

func (m *memoryFiles) ReadFile(_ context.Context, _ string, path string) ([]byte, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	data := m.files[path]
	return append([]byte(nil), data...), nil
}

func (m *memoryFiles) WriteFileAtomic(_ context.Context, _ string, path string, data []byte) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.ignoreWrites {
		return nil
	}
	m.files[path] = append([]byte(nil), data...)
	return nil
}
