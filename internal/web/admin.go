package web

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/rblashchuk/amnezia-panel/internal/admin"
	"github.com/rblashchuk/amnezia-panel/internal/wg"
)

type AdminHandler struct {
	Service *admin.Service
}

type renameClientRequest struct {
	Protocol  string `json:"protocol"`
	Container string `json:"container"`
	ClientID  string `json:"client_id"`
	Name      string `json:"name"`
}

func (h AdminHandler) RenameClient(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if h.Service == nil {
		http.Error(w, "admin service is not configured", http.StatusServiceUnavailable)
		return
	}

	var request renameClientRequest
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		http.Error(w, "invalid JSON request", http.StatusBadRequest)
		return
	}

	result, err := h.Service.RenameClient(r.Context(), admin.RenameClientRequest{
		Protocol:  request.Protocol,
		Container: request.Container,
		ClientID:  request.ClientID,
		Name:      request.Name,
	})
	if err != nil {
		writeAdminError(w, err)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

func writeAdminError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, admin.ErrOperationInProgress):
		http.Error(w, err.Error(), http.StatusConflict)
	case errors.Is(err, admin.ErrUnsupportedProtocol), errors.Is(err, wg.ErrClientNotFound):
		http.Error(w, err.Error(), http.StatusBadRequest)
	case errors.Is(err, admin.ErrVerificationFailed):
		http.Error(w, err.Error(), http.StatusInternalServerError)
	default:
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}
