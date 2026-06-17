package main

import (
	"log"
	"net/http"
	"os"

	"github.com/rblashchuk/amnezia-panel/internal/collector"
	"github.com/rblashchuk/amnezia-panel/internal/db"
	"github.com/rblashchuk/amnezia-panel/internal/web"
	"github.com/rblashchuk/amnezia-panel/internal/wg"
)

func main() {
	if remoteURL := os.Getenv("VPN_REMOTE_URL"); remoteURL != "" {
		serveRemoteProxy(remoteURL, os.Getenv("VPN_REMOTE_TOKEN"))
		return
	}

	serveCollector()
}

func serveCollector() {
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
	apiToken := os.Getenv("VPN_PANEL_TOKEN")

	mux.HandleFunc("/api/peers", web.RequireBearerToken(apiToken, handler.Peers))
	mux.HandleFunc("/api/sources", web.RequireBearerToken(apiToken, handler.Sources))
	mux.HandleFunc("/api/debug", web.RequireBearerToken(apiToken, handler.Debug))
	mux.HandleFunc("/api/traffic", web.RequireBearerToken(apiToken, handler.Traffic))

	listenAddr := env("VPN_PANEL_LISTEN", "127.0.0.1:9000")
	log.Println("collector mode listening on", listenAddr)
	log.Fatal(http.ListenAndServe(listenAddr, mux))
}

func serveRemoteProxy(remoteURL, token string) {
	proxy, err := web.NewCollectorProxy(remoteURL, token)
	if err != nil {
		log.Fatal(err)
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/api/peers", proxy.Peers)
	mux.HandleFunc("/api/sources", proxy.Sources)
	mux.HandleFunc("/api/debug", proxy.Debug)
	mux.HandleFunc("/api/traffic", proxy.Traffic)
	mux.HandleFunc("/peers", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/", http.StatusTemporaryRedirect)
	})

	mux.Handle("/", web.AppHandler())

	listenAddr := env("VPN_PANEL_LISTEN", "127.0.0.1:9000")
	log.Println("local proxy mode listening on", listenAddr, "remote", remoteURL)
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
