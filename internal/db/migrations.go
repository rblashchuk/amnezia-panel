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
`)
	return err
}
