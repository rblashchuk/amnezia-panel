package wg

import (
	"encoding/json"
	"errors"

	"github.com/rblashchuk/amnezia-panel/internal/model"
)

var ErrClientNotFound = errors.New("client not found in clientsTable")

type clientsTableEntry struct {
	ClientID string          `json:"clientId"`
	UserData clientsUserData `json:"userData"`
}

type clientsUserData struct {
	ClientName   string `json:"clientName"`
	CreationDate string `json:"creationDate"`
	AllowedIPs   string `json:"allowedIps"`
}

type ClientsTableDocument struct {
	entries []clientsTableEntryDocument
}

type clientsTableEntryDocument struct {
	fields   map[string]json.RawMessage
	ClientID string
	UserData clientsUserDataDocument
}

type clientsUserDataDocument struct {
	fields map[string]json.RawMessage
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

func ParseClientsTableDocument(data []byte) (ClientsTableDocument, error) {
	if len(data) == 0 {
		return ClientsTableDocument{}, nil
	}

	var current []json.RawMessage
	if err := json.Unmarshal(data, &current); err == nil {
		entries := make([]clientsTableEntryDocument, 0, len(current))
		for _, rawEntry := range current {
			entry, err := parseClientsTableEntry(rawEntry)
			if err != nil {
				return ClientsTableDocument{}, err
			}
			if entry.ClientID != "" {
				entries = append(entries, entry)
			}
		}
		return ClientsTableDocument{entries: entries}, nil
	}

	var legacy map[string]json.RawMessage
	if err := json.Unmarshal(data, &legacy); err != nil {
		return ClientsTableDocument{}, err
	}

	entries := make([]clientsTableEntryDocument, 0, len(legacy))
	for clientID, rawUserData := range legacy {
		userData, err := parseClientsUserData(rawUserData)
		if err != nil {
			return ClientsTableDocument{}, err
		}
		entries = append(entries, clientsTableEntryDocument{
			fields:   map[string]json.RawMessage{},
			ClientID: clientID,
			UserData: userData,
		})
	}

	return ClientsTableDocument{entries: entries}, nil
}

func RenameClientInClientsTable(data []byte, clientID, name string) ([]byte, error) {
	document, err := ParseClientsTableDocument(data)
	if err != nil {
		return nil, err
	}

	if !document.RenameClient(clientID, name) {
		return nil, ErrClientNotFound
	}

	return document.MarshalJSON()
}

func (d *ClientsTableDocument) RenameClient(clientID, name string) bool {
	for i := range d.entries {
		if d.entries[i].ClientID != clientID {
			continue
		}
		d.entries[i].UserData.setString("clientName", name)
		return true
	}
	return false
}

func (d ClientsTableDocument) MarshalJSON() ([]byte, error) {
	entries := make([]json.RawMessage, 0, len(d.entries))
	for _, entry := range d.entries {
		rawEntry, err := entry.marshalJSON()
		if err != nil {
			return nil, err
		}
		entries = append(entries, rawEntry)
	}
	return json.MarshalIndent(entries, "", "  ")
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

func parseClientsTableEntry(data []byte) (clientsTableEntryDocument, error) {
	fields := map[string]json.RawMessage{}
	if err := json.Unmarshal(data, &fields); err != nil {
		return clientsTableEntryDocument{}, err
	}

	var clientID string
	if rawClientID, ok := fields["clientId"]; ok {
		if err := json.Unmarshal(rawClientID, &clientID); err != nil {
			return clientsTableEntryDocument{}, err
		}
	}

	userData := clientsUserDataDocument{fields: map[string]json.RawMessage{}}
	if rawUserData, ok := fields["userData"]; ok {
		parsed, err := parseClientsUserData(rawUserData)
		if err != nil {
			return clientsTableEntryDocument{}, err
		}
		userData = parsed
	}

	return clientsTableEntryDocument{
		fields:   fields,
		ClientID: clientID,
		UserData: userData,
	}, nil
}

func parseClientsUserData(data []byte) (clientsUserDataDocument, error) {
	fields := map[string]json.RawMessage{}
	if len(data) == 0 {
		return clientsUserDataDocument{fields: fields}, nil
	}
	if err := json.Unmarshal(data, &fields); err != nil {
		return clientsUserDataDocument{}, err
	}
	return clientsUserDataDocument{fields: fields}, nil
}

func (e clientsTableEntryDocument) marshalJSON() ([]byte, error) {
	fields := cloneRawFields(e.fields)
	fields["clientId"] = mustMarshalRaw(e.ClientID)

	rawUserData, err := e.UserData.marshalJSON()
	if err != nil {
		return nil, err
	}
	fields["userData"] = rawUserData

	return json.Marshal(fields)
}

func (u clientsUserDataDocument) marshalJSON() ([]byte, error) {
	return json.Marshal(cloneRawFields(u.fields))
}

func (u *clientsUserDataDocument) setString(key, value string) {
	if u.fields == nil {
		u.fields = map[string]json.RawMessage{}
	}
	u.fields[key] = mustMarshalRaw(value)
}

func cloneRawFields(fields map[string]json.RawMessage) map[string]json.RawMessage {
	cloned := make(map[string]json.RawMessage, len(fields))
	for key, value := range fields {
		cloned[key] = append(json.RawMessage(nil), value...)
	}
	return cloned
}

func mustMarshalRaw(value any) json.RawMessage {
	data, err := json.Marshal(value)
	if err != nil {
		panic(err)
	}
	return data
}
