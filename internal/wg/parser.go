package wg

import (
	"strconv"
	"strings"

	"vpn-panel/internal/model"
)

func ParseDump(data string) ([]model.Peer, error) {

	var peers []model.Peer

	lines := strings.Split(data, "\n")

	for _, line := range lines {

		fields := strings.Split(line, "\t")

		if len(fields) != 8 {
			continue
		}

		rx, _ := strconv.ParseUint(fields[5], 10, 64)
		tx, _ := strconv.ParseUint(fields[6], 10, 64)

		peers = append(peers, model.Peer{
			PublicKey: fields[0],
			RxBytes:   rx,
			TxBytes:   tx,
		})
	}

	return peers, nil
}