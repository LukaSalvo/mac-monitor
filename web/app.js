let charts = {};
let currentPage = 'dashboard';
let previousNetData = null;

// Format bytes
function formatBytes(bytes) {
  if (!bytes) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i];
}

// Navigation
function initNav() {
  document.querySelectorAll('.menu-item').forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const page = item.getAttribute('data-page');
      if (page) switchPage(page);
    });
  });
}

function switchPage(page) {
  currentPage = page;
  
  document.querySelectorAll('.menu-item').forEach(i => i.classList.remove('active'));
  const active = document.querySelector(`[data-page="${page}"]`);
  if (active) active.classList.add('active');
  
  const titles = {
    'dashboard': 'System Monitor Dashboard',
    'cpu': 'CPU Analysis',
    'memory': 'Memory Analysis',
    'disk': 'Disk Analysis',
    'network': 'Network Analysis',
    'uptime': 'System Uptime'
  };
  
  document.getElementById('page-title').textContent = titles[page] || 'Monitor';
  
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  const activePage = document.getElementById(`${page}-page`);
  if (activePage) activePage.classList.add('active');
  
  fetchData();
}

// Fetch and update data
async function fetchData() {
  try {
    const res = await fetch('/api/system');
    if (!res.ok) throw new Error('Failed to fetch');
    const data = await res.json();
    
    const minutes = parseInt(document.getElementById('interval').value);
    const cutoff = Date.now() / 1000 - minutes * 60;
    const filtered = data.filter(d => d.timestamp >= cutoff);
    
    if (filtered.length === 0) return;
    
    const latest = filtered[filtered.length - 1];
    
    switch(currentPage) {
      case 'dashboard':
        updateDashboard(filtered, latest);
        break;
      case 'cpu':
        updateCPU(filtered, latest);
        break;
      case 'memory':
        updateMemory(filtered, latest);
        break;
      case 'disk':
        updateDisk(filtered, latest);
        break;
      case 'network':
        updateNetwork(filtered, latest);
        break;
      case 'uptime':
        updateUptime(filtered, latest);
        break;
    }
  } catch (err) {
    console.error('Fetch error:', err);
  }
}

function updateDashboard(filtered, latest) {
  // System info
  document.getElementById('sys-hostname').textContent = latest.hostname || 'Unknown';
  document.getElementById('sys-platform').textContent = latest.platform ? `${latest.platform} ${latest.os || ''}` : 'Unknown';
  document.getElementById('sys-cores').textContent = latest.cpu_cores ? `${latest.cpu_cores} cores` : 'Unknown';
  
  // Metrics
  document.getElementById('cpu').textContent = (latest.cpu_usage || 0).toFixed(1) + '%';
  document.getElementById('memory').textContent = formatBytes(latest.memory_used_bytes);
  document.getElementById('disk').textContent = formatBytes(latest.disk_used_bytes);
  document.getElementById('uptime').textContent = latest.uptime || '0s';
  
  // Charts
  const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());
  const cpuData = filtered.map(d => d.cpu_usage || 0);
  const memData = filtered.map(d => d.memory_used || 0);
  
  updateChart('cpuChart', {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: 'CPU %',
        data: cpuData,
        borderColor: '#ff6b35',
        backgroundColor: 'rgba(255, 107, 53, 0.1)',
        tension: 0.4,
        fill: true
      }]
    },
    options: getChartOptions({ max: 100 })
  });
  
  updateChart('memoryChart', {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: 'Memory GB',
        data: memData,
        borderColor: '#4ec9b0',
        backgroundColor: 'rgba(78, 201, 176, 0.1)',
        tension: 0.4,
        fill: true
      }]
    },
    options: getChartOptions()
  });
}

function updateCPU(filtered, latest) {
  const cpuValues = filtered.map(d => d.cpu_usage || 0);
  const avg = cpuValues.reduce((a, b) => a + b, 0) / cpuValues.length;
  
  document.getElementById('cpu-current').textContent = (latest.cpu_usage || 0).toFixed(1) + '%';
  document.getElementById('cpu-avg').textContent = avg.toFixed(1) + '%';
  document.getElementById('cpu-max').textContent = Math.max(...cpuValues).toFixed(1) + '%';
  document.getElementById('cpu-min').textContent = Math.min(...cpuValues).toFixed(1) + '%';
  
  const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());
  
  // Timeline chart
  updateChart('cpuDetailChart', {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: 'CPU Usage %',
        data: cpuValues,
        borderColor: '#ff6b35',
        backgroundColor: 'rgba(255, 107, 53, 0.2)',
        tension: 0.4,
        fill: true
      }]
    },
    options: getChartOptions({ max: 100 })
  });

  // Calculate distribution
  const totalPoints = cpuValues.length;
  const highCount = cpuValues.filter(v => v > 80).length;
  const mediumCount = cpuValues.filter(v => v >= 50 && v <= 80).length;
  const lowCount = cpuValues.filter(v => v < 50).length;
  
  const highPercent = (highCount / totalPoints * 100).toFixed(1);
  const mediumPercent = (mediumCount / totalPoints * 100).toFixed(1);
  const lowPercent = (lowCount / totalPoints * 100).toFixed(1);

  document.getElementById('cpu-high').textContent = highPercent + '%';
  document.getElementById('cpu-medium').textContent = mediumPercent + '%';
  document.getElementById('cpu-low').textContent = lowPercent + '%';
  
  // Distribution doughnut chart
  updateChart('cpuDistChart', {
    type: 'doughnut',
    data: {
      labels: ['High (>80%)', 'Medium (50-80%)', 'Low (<50%)'],
      datasets: [{
        data: [highCount, mediumCount, lowCount],
        backgroundColor: ['#ff6b35', '#ffcc00', '#4ec9b0'],
        borderWidth: 2,
        borderColor: '#111217'
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          labels: { 
            color: '#d8d9da',
            font: { size: 12 },
            padding: 15
          },
          position: 'bottom'
        },
        tooltip: {
          callbacks: {
            label: function(context) {
              const label = context.label || '';
              const value = context.parsed || 0;
              const total = context.dataset.data.reduce((a, b) => a + b, 0);
              const percentage = total > 0 ? ((value / total) * 100).toFixed(1) : 0;
              return label + ': ' + value + ' points (' + percentage + '%)';
            }
          }
        }
      }
    }
  });
}

function updateMemory(filtered, latest) {
  const memValues = filtered.map(d => d.memory_used || 0);
  const avg = memValues.reduce((a, b) => a + b, 0) / memValues.length;
  const availableBytes = (latest.memory_total_bytes || 0) - (latest.memory_used_bytes || 0);
  
  document.getElementById('mem-used').textContent = formatBytes(latest.memory_used_bytes);
  document.getElementById('mem-percent').textContent = (latest.memory_percent || 0).toFixed(1) + '%';
  document.getElementById('mem-total').textContent = formatBytes(latest.memory_total_bytes);
  document.getElementById('mem-max').textContent = Math.max(...memValues).toFixed(2) + ' GB';
  document.getElementById('mem-avg').textContent = avg.toFixed(2) + ' GB';
  document.getElementById('mem-available').textContent = formatBytes(availableBytes);
  document.getElementById('mem-growth').textContent = '0 MB/min';
  document.getElementById('mem-estimate').textContent = 'Never';
  
  const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());
  
  updateChart('memDetailChart', {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: 'Memory GB',
        data: memValues,
        borderColor: '#4ec9b0',
        backgroundColor: 'rgba(78, 201, 176, 0.2)',
        tension: 0.4,
        fill: true
      }]
    },
    options: getChartOptions()
  });

  // Memory pie chart
  updateChart('memPieChart', {
    type: 'doughnut',
    data: {
      labels: ['Used', 'Available'],
      datasets: [{
        data: [latest.memory_used_bytes, availableBytes],
        backgroundColor: ['#ff6b35', '#4ec9b0']
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          labels: { color: '#d8d9da' }
        }
      }
    }
  });
}

function updateDisk(filtered, latest) {
  const used = latest.disk_used || 0;
  const total = latest.disk_total || 0;
  const free = total - used;
  const percent = total > 0 ? ((used / total) * 100).toFixed(1) : 0;
  
  document.getElementById('disk-used').textContent = formatBytes(latest.disk_used_bytes);
  document.getElementById('disk-percent').textContent = percent + '%';
  document.getElementById('disk-total').textContent = formatBytes(latest.disk_total_bytes);
  document.getElementById('disk-free').textContent = formatBytes(latest.disk_total_bytes - latest.disk_used_bytes);
  
  let status = 'OK';
  if (percent > 90) status = 'Critical';
  else if (percent > 80) status = 'Warning';
  document.getElementById('disk-status').textContent = status;
  
  const info = percent > 80 
    ? `⚠️ Your disk is ${percent}% full. Consider freeing up space.`
    : `✓ Your disk has ${free.toFixed(1)} GB free.`;
  document.getElementById('disk-info').textContent = info;
  
  updateChart('diskPieChart', {
    type: 'doughnut',
    data: {
      labels: ['Used', 'Free'],
      datasets: [{
        data: [used, free],
        backgroundColor: ['#ff6b35', '#4ec9b0']
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          labels: { color: '#d8d9da' }
        }
      }
    }
  });

  // Disk bar chart
  updateChart('diskBarChart', {
    type: 'bar',
    data: {
      labels: ['Disk Space'],
      datasets: [
        {
          label: 'Used',
          data: [used],
          backgroundColor: '#ff6b35'
        },
        {
          label: 'Free',
          data: [free],
          backgroundColor: '#4ec9b0'
        }
      ]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          labels: { color: '#d8d9da' }
        }
      },
      scales: {
        x: {
          ticks: { color: '#9fa0a4' },
          grid: { color: '#2a2b2f' }
        },
        y: {
          ticks: { color: '#9fa0a4' },
          grid: { color: '#2a2b2f' },
          beginAtZero: true
        }
      }
    }
  });
}

async function updateNetwork(filtered, latest) {
  const sent = latest.network_sent || 0;
  const recv = latest.network_recv || 0;
  
  document.getElementById('net-sent').textContent = formatBytes(sent);
  document.getElementById('net-recv').textContent = formatBytes(recv);
  
  // Calculate speeds from history
  if (filtered.length >= 2) {
    const recent = filtered.slice(-10);
    if (recent.length >= 2) {
      const first = recent[0];
      const last = recent[recent.length - 1];
      const timeDiff = last.timestamp - first.timestamp;
      
      if (timeDiff > 0) {
        const upSpeed = (last.network_sent - first.network_sent) / timeDiff;
        const downSpeed = (last.network_recv - first.network_recv) / timeDiff;
        document.getElementById('net-up-speed').textContent = formatBytes(Math.max(0, upSpeed)) + '/s';
        document.getElementById('net-down-speed').textContent = formatBytes(Math.max(0, downSpeed)) + '/s';
      }
    }
  }
  
  // Chart
  const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());
  const sentData = filtered.map((d, i) => {
    if (i === 0) return 0;
    const prev = filtered[i - 1];
    const diff = d.network_sent - prev.network_sent;
    const time = d.timestamp - prev.timestamp;
    return time > 0 ? (diff / time) / 1024 : 0;
  });
  
  const recvData = filtered.map((d, i) => {
    if (i === 0) return 0;
    const prev = filtered[i - 1];
    const diff = d.network_recv - prev.network_recv;
    const time = d.timestamp - prev.timestamp;
    return time > 0 ? (diff / time) / 1024 : 0;
  });
  
  updateChart('networkChart', {
    type: 'line',
    data: {
      labels,
      datasets: [
        {
          label: 'Upload KB/s',
          data: sentData,
          borderColor: '#ff6b35',
          backgroundColor: 'rgba(255, 107, 53, 0.1)',
          tension: 0.4,
          fill: true
        },
        {
          label: 'Download KB/s',
          data: recvData,
          borderColor: '#4ec9b0',
          backgroundColor: 'rgba(78, 201, 176, 0.1)',
          tension: 0.4,
          fill: true
        }
      ]
    },
    options: getChartOptions()
  });
  
  // Fetch interfaces
  try {
    const res = await fetch('/api/network');
    if (!res.ok) throw new Error('Network API failed');
    const interfaces = await res.json();
    const container = document.getElementById('network-interfaces');
    
    if (!container) return;
    
    if (interfaces && interfaces.length > 0) {
      let html = '<div style="padding: 20px;"><h3 style="margin-bottom: 15px; color: #fff;">Active Network Interfaces</h3>';
      interfaces.forEach(iface => {
        html += `
          <div style="display: flex; justify-content: space-between; padding: 12px 0; border-bottom: 1px solid #2a2b2f;">
            <span style="color: #d8d9da;"><i class="fas fa-ethernet"></i> ${iface.interface}</span>
            <span style="color: #9fa0a4;">↑ ${formatBytes(iface.bytes_sent)} / ↓ ${formatBytes(iface.bytes_recv)}</span>
          </div>
        `;
      });
      html += '</div>';
      container.innerHTML = html;
    } else {
      container.innerHTML = '<p style="padding: 20px; color: #9fa0a4;">No active network interfaces found.</p>';
    }
  } catch (err) {
    console.error('Network interfaces error:', err);
  }
}

function updateUptime(filtered, latest) {
  const uptimeStr = latest.uptime || '0s';
  document.getElementById('uptime-current').textContent = uptimeStr;
  
  const days = uptimeStr.match(/(\d+)d/);
  const hours = uptimeStr.match(/(\d+)h/);
  const minutes = uptimeStr.match(/(\d+)m/);
  
  document.getElementById('uptime-days').textContent = days ? days[1] : '0';
  document.getElementById('uptime-hours').textContent = hours ? hours[1] : '0';
  document.getElementById('uptime-minutes').textContent = minutes ? minutes[1] : '0';
  
  const reliability = 99.9;
  document.getElementById('uptime-reliability').textContent = reliability.toFixed(1) + '%';
  
  const circle = document.getElementById('uptime-circle');
  if (circle) {
    const circumference = 2 * Math.PI * 90;
    const offset = circumference - (reliability / 100) * circumference;
    circle.style.strokeDashoffset = offset;
  }
}

function updateChart(id, config) {
  const canvas = document.getElementById(id);
  if (!canvas) return;
  
  if (charts[id]) {
    charts[id].data = config.data;
    charts[id].options = config.options;
    charts[id].update('none');
  } else {
    const ctx = canvas.getContext('2d');
    charts[id] = new Chart(ctx, config);
  }
}

function getChartOptions(extra = {}) {
  return {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        labels: { color: '#d8d9da', font: { size: 12 } }
      }
    },
    scales: {
      x: {
        ticks: { color: '#9fa0a4', maxRotation: 45, minRotation: 45 },
        grid: { color: '#2a2b2f' }
      },
      y: {
        ticks: { color: '#9fa0a4' },
        grid: { color: '#2a2b2f' },
        beginAtZero: true,
        ...extra
      }
    }
  };
}

// Export JSON
async function exportJSON() {
  try {
    const res = await fetch('/api/system');
    const data = await res.json();
    
    const minutes = parseInt(document.getElementById('interval').value);
    const cutoff = Date.now() / 1000 - minutes * 60;
    const filtered = data.filter(d => d.timestamp >= cutoff);
    
    if (filtered.length === 0) {
      alert('No data to export');
      return;
    }
    
    const latest = filtered[filtered.length - 1];
    
    const exportData = {
      metadata: {
        exported_at: new Date().toISOString(),
        hostname: latest.hostname || 'Unknown',
        platform: latest.platform || 'Unknown',
        time_range_minutes: minutes,
        data_points: filtered.length
      },
      system: {
        cpu: {
          cores: latest.cpu_cores || 0,
          threads: latest.cpu_threads || 0,
          current: latest.cpu_usage || 0
        },
        memory: {
          total_bytes: latest.memory_total_bytes || 0,
          used_bytes: latest.memory_used_bytes || 0,
          percent: latest.memory_percent || 0
        },
        disk: {
          total_bytes: latest.disk_total_bytes || 0,
          used_bytes: latest.disk_used_bytes || 0,
          percent: latest.disk_percent || 0
        },
        network: {
          sent: latest.network_sent || 0,
          recv: latest.network_recv || 0
        }
      },
      history: filtered
    };
    
    const blob = new Blob([JSON.stringify(exportData, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `system-metrics-${Date.now()}.json`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
    
    const btn = document.getElementById('export-json');
    const orig = btn.innerHTML;
    btn.innerHTML = '<i class="fas fa-check"></i> Exported!';
    btn.style.backgroundColor = '#5cb85c';
    setTimeout(() => {
      btn.innerHTML = orig;
      btn.style.backgroundColor = '';
    }, 2000);
  } catch (err) {
    console.error('Export error:', err);
    alert('Export failed: ' + err.message);
  }
}

// Event listeners
document.getElementById('interval').addEventListener('change', fetchData);
document.getElementById('refresh').addEventListener('click', () => {
  const btn = document.getElementById('refresh');
  btn.style.transform = 'rotate(360deg)';
  setTimeout(() => btn.style.transform = '', 300);
  fetchData();
});
document.getElementById('export-json').addEventListener('click', exportJSON);

// Initialize
initNav();
switchPage('dashboard');
setInterval(fetchData, 5000);
fetchData();