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
	CPUUsage         float64 `json:"cpu_usage"`
	MemoryUsed       float64 `json:"memory_used"`
	MemoryTotal      float64 `json:"memory_total"`
	MemoryUsedBytes  uint64  `json:"memory_used_bytes"`
	MemoryTotalBytes uint64  `json:"memory_total_bytes"`
	DiskUsed         float64 `json:"disk_used"`
	DiskTotal        float64 `json:"disk_total"`
	DiskUsedBytes    uint64  `json:"disk_used_bytes"`
	DiskTotalBytes   uint64  `json:"disk_total_bytes"`
	Uptime           string  `json:"uptime"`
	Timestamp        int64   `json:"timestamp"`
}

type DiskDevice struct {
	Device     string `json:"device"`
	Mountpoint string `json:"mountpoint"`
	Fstype     string `json:"fstype"`
	TotalBytes uint64 `json:"total_bytes"`
	UsedBytes  uint64 `json:"used_bytes"`
}

var history []SystemInfo

func getSystemInfo() SystemInfo {
	cpuPercent, _ := cpu.Percent(time.Second, false)
	vm, _ := mem.VirtualMemory()
	h, _ := host.Info()

	const gib = 1024.0 * 1024.0 * 1024.0

	// Try multiple mount points to find the primary disk
	// Priority: /System/Volumes/Data (macOS), / (Linux/Unix), /home
	var dk *disk.UsageStat
	mountPoints := []string{"/System/Volumes/Data", "/", "/home"}

	for _, mp := range mountPoints {
		if usage, err := disk.Usage(mp); err == nil && usage.Total > 0 {
			dk = usage
			break
		}
	}

	// Fallback if no valid disk found
	if dk == nil {
		dk = &disk.UsageStat{Total: 0, Used: 0}
	}

	return SystemInfo{
		CPUUsage:         cpuPercent[0],
		MemoryUsed:       float64(vm.Used) / gib,
		MemoryTotal:      float64(vm.Total) / gib,
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
		// Keep last 5 hours of data (300 minutes * 60 seconds)
		if len(history) > 300*60 {
			history = history[len(history)-300*60:]
		}
	}
}

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

	// Serve static files
	fs := http.FileServer(http.Dir("web"))
	mux.Handle("/", fs)

	// API endpoint: List all disks/partitions
	mux.HandleFunc("/api/disks", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		parts, err := disk.Partitions(true)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		var devices []DiskDevice
		for _, p := range parts {
			du, err := disk.Usage(p.Mountpoint)
			if err != nil {
				// Include partition even if usage fails
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

	// API endpoint: Get system metrics history
	mux.HandleFunc("/api/system", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(history)
	})

	handler := enableCORS(mux)

	log.Println("🚀 Server running on http://0.0.0.0:3000")
	log.Println("📊 Access dashboard at http://localhost:3000")
	log.Fatal(http.ListenAndServe(":3000", handler))
}
