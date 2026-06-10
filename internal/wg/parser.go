package wg

import (
	"strconv"
	"strings"

	"vpn-panel/internal/model"
)

func ParseDump(data string) ([]model.Peer, error) {

	var peers []model.Peer

	lines := strings.Split(strings.TrimSpace(data), "\n")

	for _, line := range lines {
		if line == "" {
			continue
		}

		fields := strings.Split(line, "\t")

		// нам нужно минимум чтобы были rx/tx
		if len(fields) < 8 {
			continue
		}

		// последние 3 поля обычно:
		// latestHandshake, rx, tx
		rxIndex := len(fields) - 3
		txIndex := len(fields) - 2

		rx, err1 := strconv.ParseUint(fields[rxIndex], 10, 64)
		tx, err2 := strconv.ParseUint(fields[txIndex], 10, 64)

		// если не числа — пропускаем peer
		if err1 != nil || err2 != nil {
			continue
		}

		peers = append(peers, model.Peer{
			PublicKey: fields[1],
			RxBytes:   rx,
			TxBytes:   tx,
		})
	}

	return peers, nil
}