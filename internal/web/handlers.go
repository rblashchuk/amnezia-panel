package web

import (
	"encoding/json"
	"log"
	"net/http"

	"vpn-panel/internal/wg"
)

type Handler struct {
	WG *wg.Collector
}

func (h *Handler) Peers(w http.ResponseWriter, r *http.Request) {

	dump, err := h.WG.Dump()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	peers, err := wg.ParseDump(string(dump))
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(peers)
}

func (h *Handler) PeersPage(w http.ResponseWriter, r *http.Request) {
	log.Println("PEERS PAGE HIT")

	http.ServeFile(w, r, "./web/index.html")
}
