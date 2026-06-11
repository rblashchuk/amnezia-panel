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

	fs := http.FS(web.StaticFS)
	mux.Handle("/static/",
		http.StripPrefix("/static/",
			http.FileServer(fs),
		),
	)

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("OK"))
	})

	log.Println("listening on 127.0.0.1:9000")

	log.Fatal(http.ListenAndServe("127.0.0.1:9000", mux))
}