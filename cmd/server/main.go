package main

import (
	"log"
	"net/http"

	"vpn-panel/internal/web"
	"vpn-panel/internal/wg"
)

func main() {

	wgCollector := &wg.Collector{
		Container: "amnezia-wireguard",
	}

	handler := &web.Handler{
		WG: wgCollector,
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/", handler.Index)
	mux.HandleFunc("/api/peers", handler.Peers)

	log.Println(
		"listening on 127.0.0.1:9000",
	)

	err := http.ListenAndServe(
		"127.0.0.1:9000",
		mux,
	)

	log.Fatal(err)
}