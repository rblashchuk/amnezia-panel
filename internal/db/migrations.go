package db

func (db *DB) Migrate() error {
	_, err := db.Exec(`
CREATE TABLE IF NOT EXISTS peer_samples (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    public_key TEXT NOT NULL,

    rx_total INTEGER NOT NULL,
    tx_total INTEGER NOT NULL,

    rx_delta INTEGER NOT NULL,
    tx_delta INTEGER NOT NULL,

    collected_at DATETIME NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_peer_samples_public_key_collected_at
ON peer_samples (public_key, collected_at);
`)
	return err
}
