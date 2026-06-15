package collector

import (
	"context"
	"log"
	"time"

	"vpn-panel/internal/db"
	"vpn-panel/internal/wg"
)

type TrafficCollector struct {
	DB      *db.DB
	Sources []wg.Source

	lastState map[string]peerState
}

type peerState struct {
	Rx uint64
	Tx uint64
}

func New(db *db.DB, sources []wg.Source) *TrafficCollector {
	lastState := make(map[string]peerState)
	totals, err := db.LatestPeerTotals()
	if err != nil {
		log.Println("load latest peer totals error:", err)
	}
	for key, total := range totals {
		lastState[key] = peerState{Rx: total.Rx, Tx: total.Tx}
	}

	return &TrafficCollector{
		DB:        db,
		Sources:   sources,
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
	for _, source := range c.Sources {
		c.collectSource(source)
	}
}

func (c *TrafficCollector) collectSource(source wg.Source) {
	info := source.Info()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	raw, err := source.Dump(ctx)
	if err != nil {
		log.Printf("%s dump error: %v", info.ID, err)
		return
	}

	peers, err := wg.ParseDump(string(raw))
	if err != nil {
		log.Printf("%s parse error: %v", info.ID, err)
		return
	}

	for _, p := range peers {
		stateKey := info.ID + "|" + p.PublicKey
		prev, seen := c.lastState[stateKey]

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

		c.lastState[stateKey] = peerState{
			Rx: rx,
			Tx: tx,
		}

		_, err := c.DB.Exec(`
INSERT INTO peer_samples (
	source_id, protocol, container, public_key,
	rx_total, tx_total,
	rx_delta, tx_delta, collected_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
`, info.ID, info.Protocol, info.Container, p.PublicKey, rx, tx, rxDelta, txDelta, time.Now())

		if err != nil {
			log.Printf("%s insert error: %v", info.ID, err)
		}
	}
}
