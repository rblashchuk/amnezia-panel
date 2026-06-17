package web

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/rblashchuk/amnezia-panel/internal/model"
)

func TestSortPeersByNameThenPublicKey(t *testing.T) {
	peers := []model.Peer{
		{PublicKey: "z-key", Name: "Zoe"},
		{PublicKey: "b-key"},
		{PublicKey: "a-key", Name: "alice"},
		{PublicKey: "c-key", Name: "Alice"},
	}

	sortPeers(peers)

	assert.Equal(t, []string{"a-key", "c-key", "b-key", "z-key"}, []string{
		peers[0].PublicKey,
		peers[1].PublicKey,
		peers[2].PublicKey,
		peers[3].PublicKey,
	})
}
