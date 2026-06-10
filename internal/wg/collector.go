package wg

import (
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

	return cmd.Output()
}