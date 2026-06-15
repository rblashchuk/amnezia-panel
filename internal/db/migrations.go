package db

func (db *DB) Migrate() error {
	_, err := db.Exec(`
CREATE TABLE IF NOT EXISTS peer_samples (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    public_key TEXT NOT NULL,
    source_id TEXT NOT NULL DEFAULT 'wireguard',
    protocol TEXT NOT NULL DEFAULT 'wireguard',
    container TEXT NOT NULL DEFAULT '',

    rx_total INTEGER NOT NULL,
    tx_total INTEGER NOT NULL,

    rx_delta INTEGER NOT NULL,
    tx_delta INTEGER NOT NULL,

    collected_at DATETIME NOT NULL
);
`)
	if err != nil {
		return err
	}

	if err := db.ensureColumn("peer_samples", "source_id", "TEXT NOT NULL DEFAULT 'wireguard'"); err != nil {
		return err
	}
	if err := db.ensureColumn("peer_samples", "protocol", "TEXT NOT NULL DEFAULT 'wireguard'"); err != nil {
		return err
	}
	if err := db.ensureColumn("peer_samples", "container", "TEXT NOT NULL DEFAULT ''"); err != nil {
		return err
	}

	_, err = db.Exec(`
CREATE INDEX IF NOT EXISTS idx_peer_samples_source_public_key_collected_at
ON peer_samples (source_id, public_key, collected_at);
`)
	return err
}

func (db *DB) ensureColumn(table, column, definition string) error {
	rows, err := db.Query(`PRAGMA table_info(` + table + `)`)
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var cid int
		var name, columnType string
		var notNull int
		var defaultValue any
		var pk int
		if err := rows.Scan(&cid, &name, &columnType, &notNull, &defaultValue, &pk); err != nil {
			return err
		}
		if name == column {
			return rows.Err()
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}

	_, err = db.Exec(`ALTER TABLE ` + table + ` ADD COLUMN ` + column + ` ` + definition)
	return err
}
