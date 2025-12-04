package main

import (
	"encoding/json"
	"log"
	"net/http"
	"runtime"
	"time"

	"github.com/shirou/gopsutil/cpu"
	"github.com/shirou/gopsutil/disk"
	"github.com/shirou/gopsutil/host"
	"github.com/shirou/gopsutil/mem"
	"github.com/shirou/gopsutil/net"
)

type SystemInfo struct {
	CPUUsage         float64 `json:"cpu_usage"`
	CPUCores         int     `json:"cpu_cores"`
	CPUThreads       int     `json:"cpu_threads"`
	MemoryUsed       float64 `json:"memory_used"`
	MemoryTotal      float64 `json:"memory_total"`
	MemoryUsedBytes  uint64  `json:"memory_used_bytes"`
	MemoryTotalBytes uint64  `json:"memory_total_bytes"`
	MemoryPercent    float64 `json:"memory_percent"`
	DiskUsed         float64 `json:"disk_used"`
	DiskTotal        float64 `json:"disk_total"`
	DiskUsedBytes    uint64  `json:"disk_used_bytes"`
	DiskTotalBytes   uint64  `json:"disk_total_bytes"`
	DiskPercent      float64 `json:"disk_percent"`
	NetworkSent      uint64  `json:"network_sent"`
	NetworkRecv      uint64  `json:"network_recv"`
	Uptime           string  `json:"uptime"`
	UptimeSeconds    uint64  `json:"uptime_seconds"`
	Hostname         string  `json:"hostname"`
	Platform         string  `json:"platform"`
	OS               string  `json:"os"`
	Timestamp        int64   `json:"timestamp"`
}

type DiskDevice struct {
	Device      string  `json:"device"`
	Mountpoint  string  `json:"mountpoint"`
	Fstype      string  `json:"fstype"`
	TotalBytes  uint64  `json:"total_bytes"`
	UsedBytes   uint64  `json:"used_bytes"`
	FreeBytes   uint64  `json:"free_bytes"`
	UsedPercent float64 `json:"used_percent"`
}

type NetworkStats struct {
	Interface   string `json:"interface"`
	BytesSent   uint64 `json:"bytes_sent"`
	BytesRecv   uint64 `json:"bytes_recv"`
	PacketsSent uint64 `json:"packets_sent"`
	PacketsRecv uint64 `json:"packets_recv"`
}

var history []SystemInfo

func getPrimaryDisk() (*disk.UsageStat, error) {
	if runtime.GOOS == "darwin" {
		if usage, err := disk.Usage("/System/Volumes/Data"); err == nil && usage.Total > 0 {
			return usage, nil
		}
	}

	if usage, err := disk.Usage("/"); err == nil && usage.Total > 0 {
		return usage, nil
	}

	return &disk.UsageStat{Total: 0, Used: 0}, nil
}

func getSystemInfo() SystemInfo {
	cpuPercent, _ := cpu.Percent(time.Second, false)
	vm, _ := mem.VirtualMemory()
	h, _ := host.Info()
	cpuCores, _ := cpu.Counts(false)
	cpuThreads, _ := cpu.Counts(true)

	const gib = 1024.0 * 1024.0 * 1024.0

	dk, err := getPrimaryDisk()
	if err != nil || dk.Total == 0 {
		dk = &disk.UsageStat{Total: 0, Used: 0}
	}

	netStats, _ := net.IOCounters(false)
	var netSent, netRecv uint64
	if len(netStats) > 0 {
		netSent = netStats[0].BytesSent
		netRecv = netStats[0].BytesRecv
	}

	return SystemInfo{
		CPUUsage:         cpuPercent[0],
		CPUCores:         cpuCores,
		CPUThreads:       cpuThreads,
		MemoryUsed:       float64(vm.Used) / gib,
		MemoryTotal:      float64(vm.Total) / gib,
		MemoryUsedBytes:  vm.Used,
		MemoryTotalBytes: vm.Total,
		MemoryPercent:    vm.UsedPercent,
		DiskUsed:         float64(dk.Used) / gib,
		DiskTotal:        float64(dk.Total) / gib,
		DiskUsedBytes:    dk.Used,
		DiskTotalBytes:   dk.Total,
		DiskPercent:      dk.UsedPercent,
		NetworkSent:      netSent,
		NetworkRecv:      netRecv,
		Uptime:           (time.Duration(h.Uptime) * time.Second).String(),
		UptimeSeconds:    h.Uptime,
		Hostname:         h.Hostname,
		Platform:         h.Platform,
		OS:               h.OS,
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

	mux.HandleFunc("/api/disks", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		parts, err := disk.Partitions(false)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		var devices []DiskDevice
		seen := make(map[string]bool)

		for _, p := range parts {
			if seen[p.Mountpoint] || p.Fstype == "devfs" || p.Fstype == "autofs" {
				continue
			}
			seen[p.Mountpoint] = true

			du, err := disk.Usage(p.Mountpoint)
			if err != nil || du.Total == 0 {
				continue
			}

			devices = append(devices, DiskDevice{
				Device:      p.Device,
				Mountpoint:  p.Mountpoint,
				Fstype:      p.Fstype,
				TotalBytes:  du.Total,
				UsedBytes:   du.Used,
				FreeBytes:   du.Free,
				UsedPercent: du.UsedPercent,
			})
		}

		json.NewEncoder(w).Encode(devices)
	})

	mux.HandleFunc("/api/network", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")

		netIO, err := net.IOCounters(true)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		var stats []NetworkStats
		for _, io := range netIO {
			if io.Name == "lo" || io.Name == "lo0" || (io.BytesSent == 0 && io.BytesRecv == 0) {
				continue
			}

			stats = append(stats, NetworkStats{
				Interface:   io.Name,
				BytesSent:   io.BytesSent,
				BytesRecv:   io.BytesRecv,
				PacketsSent: io.PacketsSent,
				PacketsRecv: io.PacketsRecv,
			})
		}

		json.NewEncoder(w).Encode(stats)
	})

	mux.HandleFunc("/api/system", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(history)
	})

	handler := enableCORS(mux)

	log.Println("🚀 Server running on http://0.0.0.0:3000")
	log.Printf("📊 System: %s - %s cores", runtime.GOOS, runtime.NumCPU())
	log.Println("📡 Dashboard: http://localhost:3000")
	log.Fatal(http.ListenAndServe(":3000", handler))
}
