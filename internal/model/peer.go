package model

import "time"

type Peer struct {
	PublicKey     string    `json:"public_key"`
	RxBytes       uint64    `json:"rx_bytes"`
	TxBytes       uint64    `json:"tx_bytes"`
	LastHandshake time.Time `json:"last_handshake"`
}