package wg_test

import (
	"encoding/json"
	"errors"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/rblashchuk/amnezia-panel/internal/wg"
)

func TestParseClientsTableCurrentFormat(t *testing.T) {
	input := []byte(`[
  {
    "clientId": "peer-public-key",
    "userData": {
      "clientName": "Alice iPhone",
      "creationDate": "Wed Jun 17 12:34:56 2026",
      "allowedIps": "10.8.1.3/32"
    }
  }
]`)

	clients, err := wg.ParseClientsTable(input)

	assert.NoError(t, err)
	assert.Len(t, clients, 1)
	assert.Equal(t, "Alice iPhone", clients["peer-public-key"].Name)
	assert.Equal(t, "Wed Jun 17 12:34:56 2026", clients["peer-public-key"].CreationDate)
	assert.Equal(t, "10.8.1.3/32", clients["peer-public-key"].AllowedIPs)
}

func TestParseClientsTableLegacyFormat(t *testing.T) {
	input := []byte(`{
  "peer-public-key": {
    "clientName": "Bob Laptop"
  }
}`)

	clients, err := wg.ParseClientsTable(input)

	assert.NoError(t, err)
	assert.Len(t, clients, 1)
	assert.Equal(t, "Bob Laptop", clients["peer-public-key"].Name)
}

func TestParseClientsTableEmpty(t *testing.T) {
	clients, err := wg.ParseClientsTable(nil)

	assert.NoError(t, err)
	assert.Empty(t, clients)
}

func TestRenameClientInClientsTablePreservesUnknownFields(t *testing.T) {
	input := []byte(`[
  {
    "clientId": "peer-public-key",
    "unexpectedTopLevel": {"kept": true},
    "userData": {
      "clientName": "Alice iPhone",
      "creationDate": "Wed Jun 17 12:34:56 2026",
      "allowedIps": "10.8.1.3/32",
      "latestHandshake": "5m",
      "customField": {"nested": 42}
    }
  }
]`)

	output, err := wg.RenameClientInClientsTable(input, "peer-public-key", "Alice MacBook")

	require.NoError(t, err)

	var entries []map[string]any
	require.NoError(t, json.Unmarshal(output, &entries))
	require.Len(t, entries, 1)

	userData, ok := entries[0]["userData"].(map[string]any)
	require.True(t, ok)

	assert.Equal(t, "peer-public-key", entries[0]["clientId"])
	assert.Equal(t, "Alice MacBook", userData["clientName"])
	assert.Equal(t, "Wed Jun 17 12:34:56 2026", userData["creationDate"])
	assert.Equal(t, "10.8.1.3/32", userData["allowedIps"])
	assert.Equal(t, "5m", userData["latestHandshake"])
	assert.Equal(t, map[string]any{"nested": float64(42)}, userData["customField"])
	assert.Equal(t, map[string]any{"kept": true}, entries[0]["unexpectedTopLevel"])
}

func TestRenameClientInClientsTableNormalizesLegacyFormat(t *testing.T) {
	input := []byte(`{
  "peer-public-key": {
    "clientName": "Bob Laptop",
    "creationDate": "Wed Jun 17 12:34:56 2026",
    "unknown": "kept"
  }
}`)

	output, err := wg.RenameClientInClientsTable(input, "peer-public-key", "Bob Phone")

	require.NoError(t, err)

	var entries []map[string]any
	require.NoError(t, json.Unmarshal(output, &entries))
	require.Len(t, entries, 1)

	userData, ok := entries[0]["userData"].(map[string]any)
	require.True(t, ok)

	assert.Equal(t, "peer-public-key", entries[0]["clientId"])
	assert.Equal(t, "Bob Phone", userData["clientName"])
	assert.Equal(t, "Wed Jun 17 12:34:56 2026", userData["creationDate"])
	assert.Equal(t, "kept", userData["unknown"])
}

func TestRenameClientInClientsTableReturnsNotFound(t *testing.T) {
	input := []byte(`[
  {
    "clientId": "peer-public-key",
    "userData": {
      "clientName": "Alice iPhone"
    }
  }
]`)

	_, err := wg.RenameClientInClientsTable(input, "missing-peer", "New Name")

	assert.True(t, errors.Is(err, wg.ErrClientNotFound))
}
