package main

import (
	"log"
	"net/http"
	"os"

	"vpn-panel/internal/collector"
	"vpn-panel/internal/db"
	"vpn-panel/internal/web"
	"vpn-panel/internal/wg"
)

func main() {
	database, err := db.New("/data/vpn.db")
	if err != nil {
		log.Fatal(err)
	}

	if err := database.Migrate(); err != nil {
		log.Fatal(err)
	}

	container := os.Getenv("VPN_CONTAINER")
	if container == "" {
		container = "amnezia-wireguard"
	}

	wgCollector := &wg.Collector{
		Container: container,
	}

	c := collector.New(database, wgCollector)
	go c.Run()

	handler := &web.Handler{
		WG: wgCollector,
		DB: database,
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/api/peers", handler.Peers)
	mux.HandleFunc("/peers", handler.PeersPage)

	mux.Handle("/static/",
		http.StripPrefix("/static/",
			http.FileServer(http.FS(web.StaticFS)),
		),
	)

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("OK"))
	})

	log.Println("listening on 127.0.0.1:9000")
	log.Fatal(http.ListenAndServe("127.0.0.1:9000", mux))
}