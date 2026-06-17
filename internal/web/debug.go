package web

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/rblashchuk/amnezia-panel/internal/dockerapi"
)

type DebugInfo struct {
	GeneratedAt time.Time         `json:"generated_at"`
	Runtime     RuntimeInfo       `json:"runtime"`
	System      SystemInfo        `json:"system"`
	Memory      map[string]uint64 `json:"memory_kb"`
	Disk        DiskInfo          `json:"disk"`
	Network     []NetworkInfo     `json:"network"`
	Containers  []ContainerInfo   `json:"containers"`
}

type RuntimeInfo struct {
	GoVersion  string `json:"go_version"`
	GOOS       string `json:"goos"`
	GOARCH     string `json:"goarch"`
	NumCPU     int    `json:"num_cpu"`
	Goroutines int    `json:"goroutines"`
}

type SystemInfo struct {
	Hostname string `json:"hostname"`
	Kernel   string `json:"kernel"`
	LoadAvg  string `json:"load_avg"`
	Uptime   string `json:"uptime"`
}

type DiskInfo struct {
	Path      string  `json:"path"`
	Total     uint64  `json:"total"`
	Free      uint64  `json:"free"`
	Available uint64  `json:"available"`
	UsedPct   float64 `json:"used_pct"`
}

type NetworkInfo struct {
	Interface string `json:"interface"`
	RxBytes   uint64 `json:"rx_bytes"`
	TxBytes   uint64 `json:"tx_bytes"`
}

type ContainerInfo struct {
	Name   string `json:"name"`
	Status string `json:"status"`
	Image  string `json:"image"`
}

func (h *Handler) Debug(w http.ResponseWriter, r *http.Request) {
	info := DebugInfo{
		GeneratedAt: time.Now(),
		Runtime: RuntimeInfo{
			GoVersion:  runtime.Version(),
			GOOS:       runtime.GOOS,
			GOARCH:     runtime.GOARCH,
			NumCPU:     runtime.NumCPU(),
			Goroutines: runtime.NumGoroutine(),
		},
		System: SystemInfo{
			Hostname: hostname(),
			Kernel:   commandOutput("uname", "-srmo"),
			LoadAvg:  readTrimmed("/proc/loadavg"),
			Uptime:   readTrimmed("/proc/uptime"),
		},
		Memory:     readMeminfo(),
		Disk:       diskInfo("/app/data"),
		Network:    readNetworkInfo(),
		Containers: dockerContainers(),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(info)
}

func hostname() string {
	value, err := os.Hostname()
	if err != nil {
		return ""
	}
	return value
}

func readTrimmed(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}

func commandOutput(name string, args ...string) string {
	out, err := exec.Command(name, args...).CombinedOutput()
	if err != nil {
		return strings.TrimSpace(string(out))
	}
	return strings.TrimSpace(string(out))
}

func readMeminfo() map[string]uint64 {
	data, err := os.ReadFile("/proc/meminfo")
	if err != nil {
		return map[string]uint64{}
	}

	result := make(map[string]uint64)
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		value, err := strconv.ParseUint(fields[1], 10, 64)
		if err != nil {
			continue
		}
		result[strings.TrimSuffix(fields[0], ":")] = value
	}
	return result
}

func diskInfo(path string) DiskInfo {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return DiskInfo{Path: path}
	}

	total := stat.Blocks * uint64(stat.Bsize)
	free := stat.Bfree * uint64(stat.Bsize)
	available := stat.Bavail * uint64(stat.Bsize)
	used := total - free

	var usedPct float64
	if total > 0 {
		usedPct = float64(used) / float64(total) * 100
	}

	return DiskInfo{
		Path:      path,
		Total:     total,
		Free:      free,
		Available: available,
		UsedPct:   usedPct,
	}
}

func readNetworkInfo() []NetworkInfo {
	data, err := os.ReadFile("/proc/net/dev")
	if err != nil {
		return nil
	}

	var result []NetworkInfo
	for _, line := range strings.Split(string(data), "\n") {
		if !strings.Contains(line, ":") {
			continue
		}

		parts := strings.SplitN(line, ":", 2)
		name := strings.TrimSpace(parts[0])
		fields := strings.Fields(parts[1])
		if len(fields) < 16 {
			continue
		}

		rx, _ := strconv.ParseUint(fields[0], 10, 64)
		tx, _ := strconv.ParseUint(fields[8], 10, 64)
		result = append(result, NetworkInfo{
			Interface: name,
			RxBytes:   rx,
			TxBytes:   tx,
		})
	}
	return result
}

func dockerContainers() []ContainerInfo {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	containers, err := dockerapi.New().Containers(ctx)
	if err != nil {
		return []ContainerInfo{{
			Name:   "docker",
			Status: err.Error(),
		}}
	}

	var result []ContainerInfo
	for _, container := range containers {
		name := dockerContainerName(container.Names)
		if name != "amnezia-awg2" && name != "amnezia-wireguard" {
			continue
		}
		result = append(result, ContainerInfo{
			Name:   name,
			Status: container.Status,
			Image:  container.Image,
		})
	}
	return result
}

func dockerContainerName(names []string) string {
	if len(names) == 0 {
		return ""
	}
	return strings.TrimPrefix(names[0], "/")
}
