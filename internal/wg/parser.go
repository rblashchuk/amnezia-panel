package wg

import (
	"strconv"
	"strings"
	"time"

	"github.com/rblashchuk/amnezia-panel/internal/model"
)

func ParseDump(data string) ([]model.Peer, error) {
	var peers []model.Peer

	lines := strings.Split(strings.TrimSpace(data), "\n")

	for _, line := range lines {
		if line == "" {
			continue
		}

		fields := strings.Split(line, "\t")

		// минимум: interface + pubkey + ... + handshake + rx + tx
		if len(fields) < 7 {
			continue
		}

		// структура wg dump (с конца):
		// ... latestHandshake rx tx status
		//
		// нас интересуют последние 3 числа перед статусом

		if len(fields) < 5 {
			continue
		}

		// безопасные индексы с конца
		hsIndex := len(fields) - 4
		rxIndex := len(fields) - 3
		txIndex := len(fields) - 2

		if hsIndex < 0 || rxIndex < 0 || txIndex < 0 {
			continue
		}

		// RX
		rx, err1 := strconv.ParseUint(fields[rxIndex], 10, 64)
		if err1 != nil {
			rx = 0
		}

		// TX
		tx, err2 := strconv.ParseUint(fields[txIndex], 10, 64)
		if err2 != nil {
			tx = 0
		}

		// handshake (unix time)
		var lastHandshake time.Time
		hsInt, err := strconv.ParseInt(fields[hsIndex], 10, 64)
		if err == nil && hsInt > 0 {
			lastHandshake = time.Unix(hsInt, 0)
		}

		// public key всегда второй колонкой в dump
		publicKey := ""
		if len(fields) > 1 {
			publicKey = fields[1]
		}

		peers = append(peers, model.Peer{
			PublicKey:     publicKey,
			RxBytes:       rx,
			TxBytes:       tx,
			LastHandshake: lastHandshake,
		})
	}

	return peers, nil
}
