package db

import (
	"database/sql"
	"time"

	"vpn-panel/internal/model"

	_ "modernc.org/sqlite"
)

type DB struct {
	*sql.DB
}

func New(path string) (*DB, error) {
	conn, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}

	conn.SetMaxOpenConns(1)

	return &DB{conn}, nil
}

func (db *DB) LatestPeerTotals() (map[string]model.PeerTotal, error) {
	rows, err := db.Query(`
SELECT ps.source_id, ps.public_key, ps.rx_total, ps.tx_total
FROM peer_samples ps
JOIN (
	SELECT source_id, public_key, MAX(collected_at) AS collected_at
	FROM peer_samples
	GROUP BY source_id, public_key
) latest
ON latest.source_id = ps.source_id
AND latest.public_key = ps.public_key
AND latest.collected_at = ps.collected_at
`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	totals := make(map[string]model.PeerTotal)
	for rows.Next() {
		var sourceID, publicKey string
		var rxTotal, txTotal uint64
		if err := rows.Scan(&sourceID, &publicKey, &rxTotal, &txTotal); err != nil {
			return nil, err
		}
		totals[sourceID+"|"+publicKey] = model.PeerTotal{
			Rx: rxTotal,
			Tx: txTotal,
		}
	}

	return totals, rows.Err()
}

func (db *DB) TrafficSamples(sourceID, publicKey string, since time.Time) ([]model.TrafficSample, error) {
	rows, err := db.Query(`
SELECT source_id, protocol, container, public_key, rx_total, tx_total, rx_delta, tx_delta, collected_at
FROM peer_samples
WHERE source_id = ?
AND public_key = ?
AND collected_at >= ?
ORDER BY collected_at ASC
`, sourceID, publicKey, since)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var samples []model.TrafficSample
	for rows.Next() {
		var sample model.TrafficSample
		if err := rows.Scan(
			&sample.SourceID,
			&sample.Protocol,
			&sample.Container,
			&sample.PublicKey,
			&sample.RxTotal,
			&sample.TxTotal,
			&sample.RxDelta,
			&sample.TxDelta,
			&sample.CollectedAt,
		); err != nil {
			return nil, err
		}
		samples = append(samples, sample)
	}

	return samples, rows.Err()
}
