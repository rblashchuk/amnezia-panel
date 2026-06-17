package web

import (
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type CollectorProxy struct {
	BaseURL *url.URL
	Token   string
	Client  *http.Client
}

func NewCollectorProxy(rawURL, token string) (*CollectorProxy, error) {
	baseURL, err := url.Parse(rawURL)
	if err != nil {
		return nil, err
	}
	if baseURL.Scheme == "" || baseURL.Host == "" {
		return nil, url.InvalidHostError(rawURL)
	}

	return &CollectorProxy{
		BaseURL: baseURL,
		Token:   token,
		Client: &http.Client{
			Timeout: 30 * time.Second,
		},
	}, nil
}

func (p *CollectorProxy) Sources(w http.ResponseWriter, r *http.Request) {
	p.forward(w, r, "/api/sources")
}

func (p *CollectorProxy) Peers(w http.ResponseWriter, r *http.Request) {
	p.forward(w, r, "/api/peers")
}

func (p *CollectorProxy) Traffic(w http.ResponseWriter, r *http.Request) {
	p.forward(w, r, "/api/traffic")
}

func (p *CollectorProxy) Debug(w http.ResponseWriter, r *http.Request) {
	p.forward(w, r, "/api/debug")
}

func (p *CollectorProxy) forward(w http.ResponseWriter, r *http.Request, path string) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	target := *p.BaseURL
	target.Path = strings.TrimRight(p.BaseURL.Path, "/") + path
	target.RawQuery = r.URL.RawQuery

	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, target.String(), nil)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if p.Token != "" {
		req.Header.Set("Authorization", "Bearer "+p.Token)
	}

	resp, err := p.Client.Do(req)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	copyForwardHeaders(w.Header(), resp.Header)
	w.WriteHeader(resp.StatusCode)
	_, _ = io.Copy(w, resp.Body)
}

func copyForwardHeaders(dst, src http.Header) {
	for key, values := range src {
		if isHopByHopHeader(key) {
			continue
		}
		for _, value := range values {
			dst.Add(key, value)
		}
	}
}

func isHopByHopHeader(key string) bool {
	switch strings.ToLower(key) {
	case "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
		"te", "trailer", "transfer-encoding", "upgrade":
		return true
	default:
		return false
	}
}
