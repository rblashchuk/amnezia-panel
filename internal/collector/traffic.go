package collector

import (
	"log"
	"time"

	"vpn-panel/internal/db"
	"vpn-panel/internal/wg"
)

type TrafficCollector struct {
	DB        *db.DB
	WG        *wg.Collector

	lastState map[string]peerState
}

type peerState struct {
	Rx uint64
	Tx uint64
}

func New(db *db.DB, wgCollector *wg.Collector) *TrafficCollector {
	return &TrafficCollector{
		DB:        db,
		WG:        wgCollector,
		lastState: make(map[string]peerState),
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
	raw, err := c.WG.Dump()
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
		prev := c.lastState[p.PublicKey]

		rx := p.RxBytes
		tx := p.TxBytes

		var rxDelta, txDelta uint64

		if rx >= prev.Rx {
			rxDelta = rx - prev.Rx
		} else {
			rxDelta = rx
		}

		if tx >= prev.Tx {
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