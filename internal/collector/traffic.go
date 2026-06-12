package collector

import (
	"context"
	"log"
	"time"

	"vpn-panel/internal/db"
	"vpn-panel/internal/wg"
)

type TrafficCollector struct {
	DB *db.DB
	WG wg.Source

	lastState map[string]peerState
}

type peerState struct {
	Rx uint64
	Tx uint64
}

func New(db *db.DB, wgCollector wg.Source) *TrafficCollector {
	lastState := make(map[string]peerState)
	totals, err := db.LatestPeerTotals()
	if err != nil {
		log.Println("load latest peer totals error:", err)
	}
	for publicKey, total := range totals {
		lastState[publicKey] = peerState{Rx: total.Rx, Tx: total.Tx}
	}

	return &TrafficCollector{
		DB:        db,
		WG:        wgCollector,
		lastState: lastState,
	}
}

func (c *TrafficCollector) Run() {
	ticker := time.NewTicker(time.Minute)

	for {
		c.collect()
		<-ticker.C
	}
}

func (c *TrafficCollector) collect() {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	raw, err := c.WG.Dump(ctx)
	if err != nil {
		log.Println("dump error:", err)
		return
	}

	peers, err := wg.ParseDump(string(raw))
	if err != nil {
		log.Println("parse error:", err)
		return
	}

	for _, p := range peers {
		prev, seen := c.lastState[p.PublicKey]

		rx := p.RxBytes
		tx := p.TxBytes

		var rxDelta, txDelta uint64

		if !seen {
			rxDelta = 0
		} else if rx >= prev.Rx {
			rxDelta = rx - prev.Rx
		} else {
			rxDelta = rx
		}

		if !seen {
			txDelta = 0
		} else if tx >= prev.Tx {
			txDelta = tx - prev.Tx
		} else {
			txDelta = tx
		}

		c.lastState[p.PublicKey] = peerState{
			Rx: rx,
			Tx: tx,
		}

		_, err := c.DB.Exec(`
INSERT INTO peer_samples (
	public_key, rx_total, tx_total,
	rx_delta, tx_delta, collected_at
) VALUES (?, ?, ?, ?, ?, ?)
`, p.PublicKey, rx, tx, rxDelta, txDelta, time.Now())

		if err != nil {
			log.Println("insert error:", err)
		}
	}
}
