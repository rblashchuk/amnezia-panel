package wg

import (
	"fmt"
	"os/exec"
)

type Collector struct {
	Container string
}

func (c *Collector) Dump() ([]byte, error) {

	cmd := exec.Command(
		"docker",
		"exec",
		c.Container,
		"wg",
		"show",
		"all",
		"dump",
	)

	out, err := cmd.CombinedOutput()
	if err != nil {
		return nil, fmt.Errorf("wg error: %s: %w", string(out), err)
	}
	return out, nil
}
