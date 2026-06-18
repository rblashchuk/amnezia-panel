package admin

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/rblashchuk/amnezia-panel/internal/wg"
)

type RemoteFiles interface {
	ReadFile(ctx context.Context, container, path string) ([]byte, error)
	WriteFileAtomic(ctx context.Context, container, path string, data []byte) error
}

type Service struct {
	Files RemoteFiles
	Lock  *OperationLock
}

type RenameClientRequest struct {
	Protocol  string
	Container string
	ClientID  string
	Name      string
}

type RenameClientResult struct {
	Protocol  string `json:"protocol"`
	Container string `json:"container"`
	ClientID  string `json:"client_id"`
	Name      string `json:"name"`
	Path      string `json:"path"`
}

func (s *Service) RenameClient(ctx context.Context, req RenameClientRequest) (RenameClientResult, error) {
	if s.Files == nil {
		return RenameClientResult{}, errors.New("admin remote files are not configured")
	}

	lock := s.Lock
	if lock == nil {
		lock = &OperationLock{}
	}
	if !lock.TryLock() {
		return RenameClientResult{}, ErrOperationInProgress
	}
	defer lock.Unlock()

	protocol := strings.TrimSpace(req.Protocol)
	container := strings.TrimSpace(req.Container)
	clientID := strings.TrimSpace(req.ClientID)
	name := strings.TrimSpace(req.Name)
	if container == "" {
		return RenameClientResult{}, errors.New("container is required")
	}
	if clientID == "" {
		return RenameClientResult{}, errors.New("client_id is required")
	}
	if name == "" {
		return RenameClientResult{}, errors.New("name is required")
	}

	path := wg.ClientsTablePath(protocol)
	if path == "" {
		return RenameClientResult{}, fmt.Errorf("%w: %s", ErrUnsupportedProtocol, protocol)
	}

	current, err := s.Files.ReadFile(ctx, container, path)
	if err != nil {
		return RenameClientResult{}, err
	}

	next, err := wg.RenameClientInClientsTable(current, clientID, name)
	if err != nil {
		return RenameClientResult{}, err
	}

	if err := s.Files.WriteFileAtomic(ctx, container, path, next); err != nil {
		return RenameClientResult{}, err
	}

	verified, err := s.Files.ReadFile(ctx, container, path)
	if err != nil {
		return RenameClientResult{}, err
	}
	clients, err := wg.ParseClientsTable(verified)
	if err != nil {
		return RenameClientResult{}, err
	}
	if clients[clientID].Name != name {
		return RenameClientResult{}, ErrVerificationFailed
	}

	return RenameClientResult{
		Protocol:  protocol,
		Container: container,
		ClientID:  clientID,
		Name:      name,
		Path:      path,
	}, nil
}
