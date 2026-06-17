package web

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCollectorProxyForwardsKnownAPI(t *testing.T) {
	transport := roundTripFunc(func(r *http.Request) (*http.Response, error) {
		assert.Equal(t, "/api/sources", r.URL.Path)
		assert.Equal(t, "source_id=wireguard", r.URL.RawQuery)
		assert.Equal(t, "Bearer secret", r.Header.Get("Authorization"))

		return &http.Response{
			StatusCode: http.StatusOK,
			Header: http.Header{
				"Content-Type": []string{"application/json"},
			},
			Body: io.NopCloser(strings.NewReader(`[{"id":"wireguard"}]`)),
		}, nil
	})

	proxy, err := NewCollectorProxy("http://collector.local", "secret")
	require.NoError(t, err)
	proxy.Client = &http.Client{Transport: transport}

	req := httptest.NewRequest(http.MethodGet, "/api/sources?source_id=wireguard", nil)
	rec := httptest.NewRecorder()

	proxy.Sources(rec, req)

	assert.Equal(t, http.StatusOK, rec.Code)
	assert.JSONEq(t, `[{"id":"wireguard"}]`, rec.Body.String())
}

func TestCollectorProxyRejectsNonGET(t *testing.T) {
	proxy, err := NewCollectorProxy("http://collector.local", "")
	require.NoError(t, err)

	req := httptest.NewRequest(http.MethodPost, "/api/sources", nil)
	rec := httptest.NewRecorder()

	proxy.Sources(rec, req)

	assert.Equal(t, http.StatusMethodNotAllowed, rec.Code)
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) {
	return f(r)
}
