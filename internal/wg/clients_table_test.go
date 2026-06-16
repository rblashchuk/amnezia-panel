package wg_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

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
