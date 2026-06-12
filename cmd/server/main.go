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
	dbPath := env("VPN_PANEL_DB", "/app/data/vpn.db")
	database, err := db.New(dbPath)
	if err != nil {
		log.Fatal(err)
	}

	if err := database.Migrate(); err != nil {
		log.Fatal(err)
	}

	wgSource := buildWGSource()

	c := collector.New(database, wgSource)
	go c.Run()

	handler := &web.Handler{
		WG: wgSource,
		DB: database,
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/api/peers", handler.Peers)
	mux.HandleFunc("/api/traffic", handler.Traffic)
	mux.HandleFunc("/peers", handler.PeersPage)

	mux.Handle("/static/",
		http.StripPrefix("/static/",
			http.FileServer(http.FS(web.StaticFS)),
		),
	)

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("OK"))
	})

	listenAddr := env("VPN_PANEL_LISTEN", "127.0.0.1:9000")
	log.Println("listening on", listenAddr)
	log.Fatal(http.ListenAndServe(listenAddr, mux))
}

func buildWGSource() wg.Source {
	mode := env("VPN_SOURCE", "docker")
	switch mode {
	case "local":
		return &wg.LocalSource{
			Command: env("WG_COMMAND", "wg"),
		}
	case "docker":
		return &wg.DockerSource{
			Container: env("VPN_CONTAINER", "amnezia-wireguard"),
		}
	default:
		log.Fatalf("unsupported VPN_SOURCE %q", mode)
		return nil
	}
}

func env(name, fallback string) string {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	return value
}
