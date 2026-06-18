package web

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/rblashchuk/amnezia-panel/internal/admin"
	"github.com/rblashchuk/amnezia-panel/internal/wg"
)

func TestAdminHandlerRenameClient(t *testing.T) {
	path := wg.ClientsTablePath("wireguard")
	files := &adminMemoryFiles{files: map[string][]byte{
		path: []byte(`[
  {
    "clientId": "peer-public-key",
    "userData": {
      "clientName": "Alice iPhone"
    }
  }
]`),
	}}
	handler := AdminHandler{Service: &admin.Service{Files: files}}
	body := bytes.NewBufferString(`{
  "protocol": "wireguard",
  "container": "amnezia-wireguard",
  "client_id": "peer-public-key",
  "name": "Alice MacBook"
}`)

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/api/admin/clients/rename", body)

	handler.RenameClient(response, request)

	require.Equal(t, http.StatusOK, response.Code)

	var result admin.RenameClientResult
	require.NoError(t, json.NewDecoder(response.Body).Decode(&result))
	assert.Equal(t, "Alice MacBook", result.Name)
	assert.Equal(t, "amnezia-wireguard", result.Container)
}

func TestAdminHandlerRenameClientRequiresService(t *testing.T) {
	handler := AdminHandler{}

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/api/admin/clients/rename", bytes.NewBufferString(`{}`))

	handler.RenameClient(response, request)

	assert.Equal(t, http.StatusServiceUnavailable, response.Code)
}

func TestAdminHandlerRenameClientMapsNotFoundToBadRequest(t *testing.T) {
	handler := AdminHandler{Service: &admin.Service{Files: &adminMemoryFiles{files: map[string][]byte{
		wg.ClientsTablePath("wireguard"): []byte(`[]`),
	}}}}
	body := bytes.NewBufferString(`{
  "protocol": "wireguard",
  "container": "amnezia-wireguard",
  "client_id": "missing-peer",
  "name": "Alice MacBook"
}`)

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodPost, "/api/admin/clients/rename", body)

	handler.RenameClient(response, request)

	assert.Equal(t, http.StatusBadRequest, response.Code)
}

type adminMemoryFiles struct {
	files map[string][]byte
}

func (m *adminMemoryFiles) ReadFile(_ context.Context, _ string, path string) ([]byte, error) {
	return append([]byte(nil), m.files[path]...), nil
}

func (m *adminMemoryFiles) WriteFileAtomic(_ context.Context, _ string, path string, data []byte) error {
	m.files[path] = append([]byte(nil), data...)
	return nil
}
