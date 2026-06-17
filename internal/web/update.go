package web

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"time"

	"github.com/rblashchuk/amnezia-panel/internal/dockerapi"
)

type UpdateCheckResponse struct {
	CheckedAt       time.Time        `json:"checked_at"`
	Available       bool             `json:"available"`
	CanCheck        bool             `json:"can_check"`
	Message         string           `json:"message"`
	Command         string           `json:"command"`
	LocalPanel      UpdateImageState `json:"local_panel"`
	Collector       UpdateImageState `json:"collector"`
	RequiresCommand bool             `json:"requires_command"`
}

type UpdateImageState struct {
	Container string `json:"container"`
	Image     string `json:"image"`
	CurrentID string `json:"current_id"`
	LatestID  string `json:"latest_id"`
	Available bool   `json:"available"`
	Error     string `json:"error,omitempty"`
}

func UpdateCheck(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	response := checkUpdates(r.Context())
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func checkUpdates(ctx context.Context) UpdateCheckResponse {
	response := UpdateCheckResponse{
		CheckedAt: time.Now(),
		CanCheck:  true,
		Command:   "ap update",
		LocalPanel: UpdateImageState{
			Container: envOrDefault("LOCAL_CONTAINER_NAME", "amnezia-panel"),
			Image:     envOrDefault("PANEL_IMAGE", envOrDefault("REPO_IMAGE", "ghcr.io/rblashchuk/amnezia-panel:latest")),
		},
		Collector: UpdateImageState{
			Container: envOrDefault("REMOTE_CONTAINER_NAME", "amnezia-panel-collector"),
			Image:     envOrDefault("COLLECTOR_IMAGE", "ghcr.io/rblashchuk/amnezia-panel-collector:latest"),
		},
	}

	checkCtx, cancel := context.WithTimeout(ctx, 25*time.Second)
	defer cancel()

	client := dockerapi.New()
	container, err := client.ContainerInspect(checkCtx, response.LocalPanel.Container)
	if err != nil {
		response.CanCheck = false
		response.RequiresCommand = true
		response.Message = "Docker socket is not available to the local panel. Run `ap update` in the terminal to check and apply updates."
		response.LocalPanel.Error = err.Error()
		return response
	}
	response.LocalPanel.CurrentID = container.Image

	if err := client.ImagePull(checkCtx, response.LocalPanel.Image, os.Getenv("LOCAL_DOCKER_PLATFORM")); err != nil {
		response.CanCheck = false
		response.RequiresCommand = true
		response.Message = "Could not pull the latest panel image. Run `ap update` in the terminal for the full update flow."
		response.LocalPanel.Error = err.Error()
		return response
	}

	image, err := client.ImageInspect(checkCtx, response.LocalPanel.Image)
	if err != nil {
		response.CanCheck = false
		response.RequiresCommand = true
		response.Message = "Could not inspect the latest panel image. Run `ap update` in the terminal for the full update flow."
		response.LocalPanel.Error = err.Error()
		return response
	}
	response.LocalPanel.LatestID = image.ID
	response.LocalPanel.Available = response.LocalPanel.CurrentID != "" && response.LocalPanel.CurrentID != response.LocalPanel.LatestID

	response.Available = response.LocalPanel.Available
	if response.Available {
		response.RequiresCommand = true
		response.Collector.Available = true
		response.Message = "An update is available. Run the command below to update both the local panel and the VPS collector."
	} else {
		response.Message = "The local panel image is up to date."
	}

	return response
}

func envOrDefault(name, fallback string) string {
	value := os.Getenv(name)
	if value == "" {
		return fallback
	}
	return value
}
