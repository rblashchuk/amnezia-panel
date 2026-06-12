package model

import "time"

type Peer struct {
	PublicKey     string    `json:"public_key"`
	RxBytes       uint64    `json:"rx_bytes"`
	TxBytes       uint64    `json:"tx_bytes"`
	LastHandshake time.Time `json:"last_handshake"`
}

type PeerTotal struct {
	Rx uint64
	Tx uint64
}

type TrafficSample struct {
	PublicKey   string
	RxTotal     uint64
	TxTotal     uint64
	RxDelta     uint64
	TxDelta     uint64
	CollectedAt time.Time
}
