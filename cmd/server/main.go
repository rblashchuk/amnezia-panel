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

	sources := buildWGSources()

	c := collector.New(database, sources)
	go c.Run()

	handler := &web.Handler{
		WGSources: sources,
		DB:        database,
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/api/peers", handler.Peers)
	mux.HandleFunc("/api/sources", handler.Sources)
	mux.HandleFunc("/api/debug", handler.Debug)
	mux.HandleFunc("/api/traffic", handler.Traffic)
	mux.HandleFunc("/peers", handler.PeersPage)

	mux.Handle("/", web.AppHandler())

	listenAddr := env("VPN_PANEL_LISTEN", "127.0.0.1:9000")
	log.Println("listening on", listenAddr)
	log.Fatal(http.ListenAndServe(listenAddr, mux))
}

func buildWGSources() []wg.Source {
	sources, err := wg.SourcesFromEnv(
		os.Getenv("VPN_ENDPOINTS"),
		env("VPN_SOURCE", "docker"),
		os.Getenv("VPN_CONTAINER"),
		os.Getenv("WG_COMMAND"),
	)
	if err != nil {
		log.Fatal(err)
	}
	if len(sources) == 0 {
		log.Fatal("no VPN sources configured")
	}
	return sources
}

func env(name, fallback string) string {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	return value
}
