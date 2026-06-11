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

	mux.HandleFunc("/api/peers", handler.Peers)

	mux.HandleFunc("/peers", handler.PeersPage)

	mux.Handle("/static/",
		http.StripPrefix("/static/",
			http.FileServer(http.Dir("./web/static")),
		),
	)

	log.Println("listening on 127.0.0.1:9000")

	log.Fatal(
		http.ListenAndServe("127.0.0.1:9000", mux),
	)
}