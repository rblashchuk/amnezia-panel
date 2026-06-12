package web

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"vpn-panel/internal/db"
	"vpn-panel/internal/model"
	"vpn-panel/internal/wg"
)

type Handler struct {
	WG wg.Source
	DB *db.DB
}

func (h *Handler) Peers(w http.ResponseWriter, r *http.Request) {

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	dump, err := h.WG.Dump(ctx)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	peers, err := wg.ParseDump(string(dump))
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(peers)
}

type TrafficResponse struct {
	PublicKey     string         `json:"public_key"`
	RangeSeconds  int64          `json:"range_seconds"`
	BucketSeconds int64          `json:"bucket_seconds"`
	RxBytes       uint64         `json:"rx_bytes"`
	TxBytes       uint64         `json:"tx_bytes"`
	Points        []TrafficPoint `json:"points"`
}

type TrafficPoint struct {
	CollectedAt time.Time `json:"collected_at"`
	RxBytes     uint64    `json:"rx_bytes"`
	TxBytes     uint64    `json:"tx_bytes"`
}

func (h *Handler) Traffic(w http.ResponseWriter, r *http.Request) {
	publicKey := r.URL.Query().Get("public_key")
	if publicKey == "" {
		http.Error(w, "public_key is required", http.StatusBadRequest)
		return
	}

	rangeDuration := parseDurationParam(r.URL.Query().Get("range"), 24*time.Hour)
	bucketDuration := parseDurationParam(r.URL.Query().Get("bucket"), defaultBucket(rangeDuration))

	if rangeDuration <= 0 || bucketDuration <= 0 {
		http.Error(w, "range and bucket must be positive durations", http.StatusBadRequest)
		return
	}

	since := time.Now().Add(-rangeDuration)
	samples, err := h.DB.TrafficSamples(publicKey, since)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	response := buildTrafficResponse(publicKey, rangeDuration, bucketDuration, samples)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func (h *Handler) PeersPage(w http.ResponseWriter, r *http.Request) {
	http.Redirect(w, r, "/", http.StatusTemporaryRedirect)
}

func parseDurationParam(value string, fallback time.Duration) time.Duration {
	if value == "" {
		return fallback
	}

	if seconds, err := strconv.ParseInt(value, 10, 64); err == nil {
		return time.Duration(seconds) * time.Second
	}

	duration, err := time.ParseDuration(value)
	if err != nil {
		return fallback
	}
	return duration
}

func defaultBucket(rangeDuration time.Duration) time.Duration {
	switch {
	case rangeDuration <= 6*time.Hour:
		return 5 * time.Minute
	case rangeDuration <= 24*time.Hour:
		return 15 * time.Minute
	case rangeDuration <= 7*24*time.Hour:
		return time.Hour
	default:
		return 24 * time.Hour
	}
}

func buildTrafficResponse(publicKey string, rangeDuration, bucketDuration time.Duration, samples []model.TrafficSample) TrafficResponse {
	pointsByBucket := make(map[int64]*TrafficPoint)
	var rxTotal, txTotal uint64

	for _, sample := range samples {
		bucketUnix := sample.CollectedAt.Truncate(bucketDuration).Unix()
		point, ok := pointsByBucket[bucketUnix]
		if !ok {
			point = &TrafficPoint{CollectedAt: time.Unix(bucketUnix, 0)}
			pointsByBucket[bucketUnix] = point
		}

		point.RxBytes += sample.RxDelta
		point.TxBytes += sample.TxDelta
		rxTotal += sample.RxDelta
		txTotal += sample.TxDelta
	}

	points := make([]TrafficPoint, 0, len(pointsByBucket))
	for _, point := range pointsByBucket {
		points = append(points, *point)
	}

	sortTrafficPoints(points)

	return TrafficResponse{
		PublicKey:     publicKey,
		RangeSeconds:  int64(rangeDuration.Seconds()),
		BucketSeconds: int64(bucketDuration.Seconds()),
		RxBytes:       rxTotal,
		TxBytes:       txTotal,
		Points:        points,
	}
}

func sortTrafficPoints(points []TrafficPoint) {
	for i := 1; i < len(points); i++ {
		point := points[i]
		j := i - 1
		for j >= 0 && points[j].CollectedAt.After(point.CollectedAt) {
			points[j+1] = points[j]
			j--
		}
		points[j+1] = point
	}
}
