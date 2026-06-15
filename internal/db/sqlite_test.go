package db_test

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/rblashchuk/amnezia-panel/internal/db"
)

func TestTrafficSamplesAndLatestPeerTotals(t *testing.T) {
	database, err := db.New(filepath.Join(t.TempDir(), "vpn.db"))
	require.NoError(t, err)
	require.NoError(t, database.Migrate())

	oldTime := time.Now().Add(-2 * time.Hour).UTC()
	newTime := time.Now().UTC()

	_, err = database.Exec(`
INSERT INTO peer_samples (
	source_id, protocol, container, public_key, rx_total, tx_total,
	rx_delta, tx_delta, collected_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?, ?, ?, ?)
`, "wireguard", "wireguard", "amnezia-wireguard", "peer-a", 100, 200, 0, 0, oldTime,
		"wireguard", "wireguard", "amnezia-wireguard", "peer-a", 150, 260, 50, 60, newTime)
	require.NoError(t, err)

	totals, err := database.LatestPeerTotals()
	require.NoError(t, err)
	require.Equal(t, uint64(150), totals["wireguard|peer-a"].Rx)
	require.Equal(t, uint64(260), totals["wireguard|peer-a"].Tx)

	samples, err := database.TrafficSamples("wireguard", "peer-a", oldTime.Add(time.Minute))
	require.NoError(t, err)
	require.Len(t, samples, 1)
	require.Equal(t, "wireguard", samples[0].SourceID)
	require.Equal(t, uint64(50), samples[0].RxDelta)
	require.Equal(t, uint64(60), samples[0].TxDelta)
}
