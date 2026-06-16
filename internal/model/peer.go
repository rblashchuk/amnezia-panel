package model

import "time"

type Peer struct {
	PublicKey     string    `json:"public_key"`
	Name          string    `json:"name,omitempty"`
	CreationDate  string    `json:"creation_date,omitempty"`
	AllowedIPs    string    `json:"allowed_ips,omitempty"`
	RxBytes       uint64    `json:"rx_bytes"`
	TxBytes       uint64    `json:"tx_bytes"`
	LastHandshake time.Time `json:"last_handshake"`
}

type ClientMetadata struct {
	ClientID     string `json:"client_id"`
	Name         string `json:"name,omitempty"`
	CreationDate string `json:"creation_date,omitempty"`
	AllowedIPs   string `json:"allowed_ips,omitempty"`
}

type Source struct {
	ID        string `json:"id"`
	Protocol  string `json:"protocol"`
	Label     string `json:"label"`
	Container string `json:"container,omitempty"`
	Command   string `json:"command"`
	Mode      string `json:"mode"`
}

type PeerTotal struct {
	Rx uint64
	Tx uint64
}

type TrafficSample struct {
	SourceID    string
	Protocol    string
	Container   string
	PublicKey   string
	RxTotal     uint64
	TxTotal     uint64
	RxDelta     uint64
	TxDelta     uint64
	CollectedAt time.Time
}
