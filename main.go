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
	MemoryUsed  float64 `json:"memory_used"`  // en GB
	MemoryTotal float64 `json:"memory_total"` // en GB
	DiskUsed    float64 `json:"disk_used"`    // en GB
	DiskTotal   float64 `json:"disk_total"`   // en GB
	Uptime      string  `json:"uptime"`
	Timestamp   int64   `json:"timestamp"`
}

// Historique pour stocker les métriques
var history []SystemInfo

func getSystemInfo() SystemInfo {
	cpuPercent, _ := cpu.Percent(0, false)
	vm, _ := mem.VirtualMemory()
	dk, _ := disk.Usage("/")
	h, _ := host.Info()

	return SystemInfo{
		CPUUsage:    cpuPercent[0],
		MemoryUsed:  float64(vm.Used) / 1e9,
		MemoryTotal: float64(vm.Total) / 1e9,
		DiskUsed:    float64(dk.Used) / 1e9,
		DiskTotal:   float64(dk.Total) / 1e9,
		Uptime:      (time.Duration(h.Uptime) * time.Second).String(),
		Timestamp:   time.Now().Unix(),
	}
}

func collectMetrics() {
	ticker := time.NewTicker(1 * time.Second)
	for range ticker.C {
		info := getSystemInfo()
		history = append(history, info)
		if len(history) > 300*60 { // max 5h d'historique à 1 point/sec
			history = history[len(history)-300*60:]
		}
	}
}

func main() {
	go collectMetrics() // démarre la collecte en arrière-plan

	fs := http.FileServer(http.Dir("web"))
	http.Handle("/", fs)

	http.HandleFunc("/api/system", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(history)
	})

	log.Println("Server running on http://0.0.0.0:3000")
	log.Fatal(http.ListenAndServe(":3000", nil))
}
