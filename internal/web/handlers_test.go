package web

import (
	"net/url"
	"testing"
	"time"

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

func TestParseTrafficWindowFromTo(t *testing.T) {
	from := "2026-06-17T10:00:00Z"
	to := "2026-06-17T14:30:00Z"

	parsedFrom, parsedTo, duration, err := parseTrafficWindow(url.Values{
		"from": []string{from},
		"to":   []string{to},
	}, time.Date(2026, 6, 17, 15, 0, 0, 0, time.UTC))

	assert.NoError(t, err)
	assert.Equal(t, time.Date(2026, 6, 17, 10, 0, 0, 0, time.UTC), parsedFrom)
	assert.Equal(t, time.Date(2026, 6, 17, 14, 30, 0, 0, time.UTC), parsedTo)
	assert.Equal(t, 4*time.Hour+30*time.Minute, duration)
}

func TestParseTrafficWindowRejectsInvalidOrder(t *testing.T) {
	_, _, _, err := parseTrafficWindow(url.Values{
		"from": []string{"2026-06-17T14:30:00Z"},
		"to":   []string{"2026-06-17T10:00:00Z"},
	}, time.Date(2026, 6, 17, 15, 0, 0, 0, time.UTC))

	assert.Error(t, err)
}
