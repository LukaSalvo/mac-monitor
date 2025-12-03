package main

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"github.com/shirou/gopsutil/cpu"
	"github.com/shirou/gopsutil/disk"
	"github.com/shirou/gopsutil/host"
	"github.com/shirou/gopsutil/mem"
)

type SystemInfo struct {
	CPUUsage    float64 `json:"cpu_usage"`
	MemoryUsed  float64 `json:"memory_used"`
	MemoryTotal float64 `json:"memory_total"`
	// Raw byte values for flexible client-side formatting
	MemoryUsedBytes  uint64  `json:"memory_used_bytes"`
	MemoryTotalBytes uint64  `json:"memory_total_bytes"`
	DiskUsed         float64 `json:"disk_used"`
	DiskTotal        float64 `json:"disk_total"`
	DiskUsedBytes    uint64  `json:"disk_used_bytes"`
	DiskTotalBytes   uint64  `json:"disk_total_bytes"`
	Uptime           string  `json:"uptime"`
	Timestamp        int64   `json:"timestamp"`
}

var history []SystemInfo

// DiskDevice represents a detected disk/partition with sizes in bytes
type DiskDevice struct {
	Device     string `json:"device"`
	Mountpoint string `json:"mountpoint"`
	Fstype     string `json:"fstype"`
	TotalBytes uint64 `json:"total_bytes"`
	UsedBytes  uint64 `json:"used_bytes"`
}

func getSystemInfo() SystemInfo {
	cpuPercent, _ := cpu.Percent(time.Second, false)
	vm, _ := mem.VirtualMemory()
	dk, _ := disk.Usage("/")
	h, _ := host.Info()

	// Use GiB (1024^3) for more conventional binary-based sizing on desktop OSs.
	const gib = 1024.0 * 1024.0 * 1024.0

	return SystemInfo{
		CPUUsage:    cpuPercent[0],
		MemoryUsed:  float64(vm.Used) / gib,
		MemoryTotal: float64(vm.Total) / gib,
		// include raw byte counts so the front-end can choose units dynamically
		MemoryUsedBytes:  vm.Used,
		MemoryTotalBytes: vm.Total,
		DiskUsed:         float64(dk.Used) / gib,
		DiskTotal:        float64(dk.Total) / gib,
		DiskUsedBytes:    dk.Used,
		DiskTotalBytes:   dk.Total,
		Uptime:           (time.Duration(h.Uptime) * time.Second).String(),
		Timestamp:        time.Now().Unix(),
	}
}

func collectMetrics() {
	ticker := time.NewTicker(1 * time.Second)
	for range ticker.C {
		info := getSystemInfo()
		history = append(history, info)
		if len(history) > 300*60 {
			history = history[len(history)-300*60:]
		}
	}
}

// Middleware CORS
func enableCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func main() {
	go collectMetrics()

	mux := http.NewServeMux()

	fs := http.FileServer(http.Dir("web"))
	mux.Handle("/", fs)

	// List disks/partitions endpoint
	mux.HandleFunc("/api/disks", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		parts, err := disk.Partitions(true)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		var devices []DiskDevice
		for _, p := range parts {
			// try to get usage for the mountpoint; skip if it fails
			du, err := disk.Usage(p.Mountpoint)
			if err != nil {
				// Some partitions may not be accessible; include basic info with zeros
				devices = append(devices, DiskDevice{
					Device:     p.Device,
					Mountpoint: p.Mountpoint,
					Fstype:     p.Fstype,
					TotalBytes: 0,
					UsedBytes:  0,
				})
				continue
			}
			devices = append(devices, DiskDevice{
				Device:     p.Device,
				Mountpoint: p.Mountpoint,
				Fstype:     p.Fstype,
				TotalBytes: du.Total,
				UsedBytes:  du.Used,
			})
		}

		json.NewEncoder(w).Encode(devices)
	})

	mux.HandleFunc("/api/system", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(history)
	})

	handler := enableCORS(mux)

	log.Println("Server running on http://0.0.0.0:3000")
	log.Fatal(http.ListenAndServe(":3000", handler))
}
