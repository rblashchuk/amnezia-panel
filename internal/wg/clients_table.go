package wg

import (
	"encoding/json"

	"github.com/rblashchuk/amnezia-panel/internal/model"
)

type clientsTableEntry struct {
	ClientID string          `json:"clientId"`
	UserData clientsUserData `json:"userData"`
}

type clientsUserData struct {
	ClientName   string `json:"clientName"`
	CreationDate string `json:"creationDate"`
	AllowedIPs   string `json:"allowedIps"`
}

func ParseClientsTable(data []byte) (map[string]model.ClientMetadata, error) {
	result := make(map[string]model.ClientMetadata)
	if len(data) == 0 {
		return result, nil
	}

	var current []clientsTableEntry
	if err := json.Unmarshal(data, &current); err == nil {
		for _, entry := range current {
			addClientMetadata(result, entry.ClientID, entry.UserData)
		}
		return result, nil
	}

	var legacy map[string]clientsUserData
	if err := json.Unmarshal(data, &legacy); err != nil {
		return nil, err
	}

	for clientID, userData := range legacy {
		addClientMetadata(result, clientID, userData)
	}

	return result, nil
}

func addClientMetadata(result map[string]model.ClientMetadata, clientID string, userData clientsUserData) {
	if clientID == "" {
		return
	}

	result[clientID] = model.ClientMetadata{
		ClientID:     clientID,
		Name:         userData.ClientName,
		CreationDate: userData.CreationDate,
		AllowedIPs:   userData.AllowedIPs,
	}
}
