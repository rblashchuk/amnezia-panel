package dockerapi

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
)

const socketPath = "/var/run/docker.sock"

type Client struct {
	http *http.Client
}

type Container struct {
	Names  []string `json:"Names"`
	Image  string   `json:"Image"`
	Status string   `json:"Status"`
}

func New() *Client {
	transport := &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", socketPath)
		},
	}
	return &Client{http: &http.Client{Transport: transport}}
}

func (c *Client) Exec(ctx context.Context, container string, command []string) ([]byte, error) {
	createBody := map[string]any{
		"AttachStdout": true,
		"AttachStderr": true,
		"Tty":          true,
		"Cmd":          command,
	}

	var createResponse struct {
		ID string `json:"Id"`
	}
	if err := c.postJSON(ctx, "/containers/"+url.PathEscape(container)+"/exec", createBody, &createResponse); err != nil {
		return nil, err
	}
	if createResponse.ID == "" {
		return nil, fmt.Errorf("docker exec create returned empty id")
	}

	startBody := map[string]any{
		"Detach": false,
		"Tty":    true,
	}
	out, err := c.postRaw(ctx, "/exec/"+createResponse.ID+"/start", startBody)
	if err != nil {
		return nil, err
	}

	var inspectResponse struct {
		ExitCode int `json:"ExitCode"`
	}
	if err := c.getJSON(ctx, "/exec/"+createResponse.ID+"/json", &inspectResponse); err != nil {
		return nil, err
	}
	if inspectResponse.ExitCode != 0 {
		return nil, fmt.Errorf("docker exec failed with exit code %d: %s", inspectResponse.ExitCode, strings.TrimSpace(string(out)))
	}

	return out, nil
}

func (c *Client) Containers(ctx context.Context) ([]Container, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://docker/containers/json?all=1", nil)
	if err != nil {
		return nil, err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("docker containers failed: %s", strings.TrimSpace(string(data)))
	}

	var containers []Container
	if err := json.Unmarshal(data, &containers); err != nil {
		return nil, err
	}
	return containers, nil
}

func (c *Client) postJSON(ctx context.Context, endpoint string, body any, target any) error {
	data, err := json.Marshal(body)
	if err != nil {
		return err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "http://docker"+endpoint, bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	responseData, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("docker api failed: %s", strings.TrimSpace(string(responseData)))
	}

	return json.Unmarshal(responseData, target)
}

func (c *Client) getJSON(ctx context.Context, endpoint string, target any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "http://docker"+endpoint, nil)
	if err != nil {
		return err
	}

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	responseData, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("docker api failed: %s", strings.TrimSpace(string(responseData)))
	}

	return json.Unmarshal(responseData, target)
}

func (c *Client) postRaw(ctx context.Context, endpoint string, body any) ([]byte, error) {
	data, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "http://docker"+endpoint, bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	responseData, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("docker api failed: %s", strings.TrimSpace(string(responseData)))
	}

	return responseData, nil
}
