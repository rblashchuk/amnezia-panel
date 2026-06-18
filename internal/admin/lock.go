package admin

import "sync"

type OperationLock struct {
	mu     sync.Mutex
	locked bool
}

func (l *OperationLock) TryLock() bool {
	l.mu.Lock()
	defer l.mu.Unlock()

	if l.locked {
		return false
	}
	l.locked = true
	return true
}

func (l *OperationLock) Unlock() {
	l.mu.Lock()
	defer l.mu.Unlock()

	l.locked = false
}
