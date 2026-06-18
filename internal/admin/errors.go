package admin

import "errors"

var (
	ErrOperationInProgress = errors.New("admin operation already in progress")
	ErrUnsupportedProtocol = errors.New("unsupported protocol")
	ErrVerificationFailed  = errors.New("post-write verification failed")
)
