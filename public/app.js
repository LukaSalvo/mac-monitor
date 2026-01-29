let charts = {};
let currentPage = 'dashboard';
let intervalID;
let selectedDisk = null;
let unitPref = 'binary';
let currentSort = 'cpu';

function formatBytes(bytes) {
  if (bytes === 0 || bytes === null || bytes === undefined) return '0 B';
  const k = unitPref === 'decimal' ? 1000 : 1024;
  const binarySizes = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  const decimalSizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const sizes = unitPref === 'decimal' ? decimalSizes : binarySizes;
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  const index = Math.min(i, sizes.length - 1);
  return (bytes / Math.pow(k, index)).toFixed(2) + ' ' + sizes[index];
}

function formatDuration(seconds) {
  if (seconds < 60) return `${seconds.toFixed(0)}s`;
  let days = Math.floor(seconds / (3600 * 24));
  let hours = Math.floor((seconds % (3600 * 24)) / 3600);
  let minutes = Math.floor((seconds % 3600) / 60);
  let parts = [];
  if (days > 0) parts.push(days + 'd');
  if (hours > 0) parts.push(hours + 'h');
  if (minutes > 0) parts.push(minutes + 'm');
  if (parts.length === 0) return '0s';
  return parts.join(' ');
}

function initPrefs() {
  try {
    unitPref = localStorage.getItem('unitPref') || 'binary';
    const storedDisk = localStorage.getItem('selectedDisk');
    if (storedDisk && storedDisk !== 'null') {
      selectedDisk = JSON.parse(storedDisk);
    }
  } catch (e) {
    console.error("Erreur préférences:", e);
  }
}

function initNav() {
  document.querySelectorAll('.menu-item').forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const page = item.getAttribute('data-page');
      if (page) switchPage(page);
    });
  });

  document.getElementById('scan-network-btn')?.addEventListener('click', scanNetwork);
  document.getElementById('sort-cpu-btn')?.addEventListener('click', () => setProcessSort('cpu'));
  document.getElementById('sort-mem-btn')?.addEventListener('click', () => setProcessSort('mem'));
  document.getElementById('refresh')?.addEventListener('click', () => fetchData(true));
  document.getElementById('interval')?.addEventListener('change', () => fetchData());
}

function switchPage(page) {
  currentPage = page;

  document.querySelectorAll('.menu-item').forEach(i => i.classList.remove('active'));
  const active = document.querySelector(`[data-page="${page}"]`);
  if (active) active.classList.add('active');

  const titles = {
    'dashboard': 'Tableau de bord',
    'cpu': 'Moniteur CPU',
    'memory': 'Moniteur Mémoire',
    'disk': 'Moniteur Disque',
    'uptime': 'Disponibilité',
    'network': 'Moniteur Réseau',
    'scanner': 'Scanner Réseau',
    'processes': 'Gestionnaire Tâches',
    'alerts': 'Alertes Système',
    'tickets': 'Tickets Incidents',
    'logs': 'Journaux App',
    'settings': 'Paramètres'
  };
  document.getElementById('page-title').textContent = titles[page] || 'Moniteur Système';

  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  const activePage = document.getElementById(`${page}-page`);
  if (activePage) activePage.classList.add('active');

  if (page === 'settings') {
    updateSettingsPage();
  } else if (page === 'scanner') {
  } else if (page === 'processes') {
    fetchProcesses();
  } else if (page === 'alerts') {
    fetchAlerts();
  } else if (page === 'tickets') {
    fetchTickets();
  } else if (page === 'logs') {
    fetchLogs();
  } else {
    if (page === 'disk' || page === 'network') fetchDisks();
    fetchData();
  }
}

async function fetchData(force = false) {
  try {
    const res = await fetch('/api/system');
    if (!res.ok) throw new Error('Échec fetch system');
    const data = await res.json();

    document.getElementById('cpu-temp').textContent = data.length > 0 && data[data.length - 1].cpu_temp ?
      `${data[data.length - 1].cpu_temp}°C` : '--';

    const minutes = parseInt(document.getElementById('interval').value);
    const cutoff = Date.now() / 1000 - minutes * 60;
    const filtered = data.filter(d => d.timestamp >= cutoff);

    if (filtered.length === 0) {
      return;
    }
    const latest = filtered[filtered.length - 1];

    switch (currentPage) {
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
    console.error('Erreur data:', err);
  }
}

async function fetchDisks() {
  try {
    const res = await fetch('/api/disks');
    if (res.ok) return await res.json();
  } catch (err) {
    return [];
  }
}

function updateDashboard(filtered, latest) {
  const k = unitPref === 'decimal' ? 1e9 : 1024 ** 3;
  const unit = unitPref === 'decimal' ? 'GB' : 'GiB';

  document.getElementById('sys-hostname').textContent = latest.hostname || 'Inconnu';
  document.getElementById('sys-platform').textContent = latest.platform ? `${latest.platform} ${latest.os || ''}` : 'Inconnu';
  document.getElementById('sys-cores').textContent = latest.cpu_cores ? `${latest.cpu_cores} cœurs` : 'Inconnu';

  document.getElementById('cpu').textContent = (latest.cpu_usage || 0).toFixed(1) + '%';
  document.getElementById('memory').textContent = `${formatBytes(latest.memory_used_bytes)} / ${formatBytes(latest.memory_total_bytes)}`;

  const diskData = selectedDisk || {
    used_bytes: latest.disk_used_bytes,
    total_bytes: latest.disk_total_bytes
  };
  document.getElementById('disk').textContent = `${formatBytes(diskData.used_bytes)} / ${formatBytes(diskData.total_bytes)}`;
  document.getElementById('uptime').textContent = formatDuration(latest.uptime_seconds);

  const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());

  updateChart('cpuChart', {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: 'CPU %',
        data: filtered.map(d => d.cpu_usage || 0),
        borderColor: '#ff6b35',
        backgroundColor: 'rgba(255, 107, 53, 0.1)',
        tension: 0.4,
        fill: true
      }]
    },
    options: getChartOptions({
      max: 100
    })
  });

  const totalRam = (latest.memory_total_bytes || 1) / k;
  updateChart('memoryChart', {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: `Mémoire ${unit}`,
        data: filtered.map(d => (d.memory_used_bytes || 0) / k),
        borderColor: '#4ec9b0',
        backgroundColor: 'rgba(78, 201, 176, 0.1)',
        tension: 0.4,
        fill: true
      }]
    },
    options: getChartOptions({
      max: Math.ceil(totalRam)
    })
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

  updateChart('cpuDetailChart', {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: 'Utilisation CPU %',
        data: cpuValues,
        borderColor: '#ff6b35',
        backgroundColor: 'rgba(255, 107, 53, 0.2)',
        tension: 0.4,
        fill: true
      }]
    },
    options: getChartOptions({
      max: 100
    })
  });

  const high = cpuValues.filter(v => v > 80).length;
  const medium = cpuValues.filter(v => v >= 50 && v <= 80).length;
  const low = cpuValues.filter(v => v < 50).length;
  const total = cpuValues.length;

  document.getElementById('cpu-high').textContent = (high / total * 100).toFixed(1) + '%';
  document.getElementById('cpu-medium').textContent = (medium / total * 100).toFixed(1) + '%';
  document.getElementById('cpu-low').textContent = (low / total * 100).toFixed(1) + '%';

  updateChart('cpuDistChart', {
    type: 'doughnut',
    data: {
      labels: ['Élevée', 'Moyenne', 'Faible'],
      datasets: [{
        data: [high, medium, low],
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
            color: '#d8d9da'
          },
          position: 'bottom'
        }
      }
    }
  });
}

function updateMemory(filtered, latest) {
  const k = unitPref === 'decimal' ? 1e9 : 1024 ** 3;
  const unit = unitPref === 'decimal' ? 'GB' : 'GiB';
  const memUsedBytes = latest.memory_used_bytes || 0;
  const memTotalBytes = latest.memory_total_bytes || 0;
  const memAvailableBytes = memTotalBytes - memUsedBytes;
  const memValues = filtered.map(d => (d.memory_used_bytes || 0) / k);
  const avg = memValues.reduce((a, b) => a + b, 0) / memValues.length;

  document.getElementById('mem-used').textContent = formatBytes(memUsedBytes);
  document.getElementById('mem-percent').textContent = (latest.memory_percent || 0).toFixed(1) + '%';
  document.getElementById('mem-total').textContent = formatBytes(memTotalBytes);
  document.getElementById('mem-available').textContent = formatBytes(memAvailableBytes);
  document.getElementById('mem-max').textContent = formatBytes(Math.max(...memValues.map(v => v * k)));
  document.getElementById('mem-avg').textContent = avg.toFixed(2) + ' ' + unit;
  document.getElementById('mem-growth').textContent = '0 MB/min';
  document.getElementById('mem-estimate').textContent = 'Jamais';

  updateChart('memDetailChart', {
    type: 'line',
    data: {
      labels: filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString()),
      datasets: [{
        label: `Mémoire ${unit}`,
        data: memValues,
        borderColor: '#4ec9b0',
        backgroundColor: 'rgba(78, 201, 176, 0.2)',
        tension: 0.4,
        fill: true
      }]
    },
    options: getChartOptions()
  });

  updateChart('memPieChart', {
    type: 'doughnut',
    data: {
      labels: ['Utilisée', 'Disponible'],
      datasets: [{
        data: [memUsedBytes, memAvailableBytes],
        backgroundColor: ['#ff6b35', '#4ec9b0']
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          labels: {
            color: '#d8d9da'
          }
        }
      }
    }
  });
}

function updateDisk(filtered, latest) {
  const diskToMonitor = selectedDisk || {
    used_bytes: latest.disk_used_bytes || 0,
    total_bytes: latest.disk_total_bytes || 0,
    used_percent: latest.disk_percent || 0,
    mountpoint: 'Disque Principal'
  };

  const used = diskToMonitor.used_bytes;
  const total = diskToMonitor.total_bytes;
  const free = total - used;
  const percent = total > 0 ? ((used / total) * 100).toFixed(1) : '0.0';

  document.getElementById('disk-used').textContent = formatBytes(used);
  document.getElementById('disk-percent').textContent = percent + '%';
  document.getElementById('disk-total').textContent = formatBytes(total);
  document.getElementById('disk-free').textContent = formatBytes(free);
  document.getElementById('disk-status').textContent = (parseFloat(percent) > 90) ? 'Critique' : 'OK';
  document.getElementById('disk-info').textContent = `Volume: ${diskToMonitor.mountpoint || 'N/A'} - ${formatBytes(free)} libre.`;

  updateChart('diskPieChart', {
    type: 'doughnut',
    data: {
      labels: ['Utilisé', 'Libre'],
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
          labels: {
            color: '#d8d9da'
          }
        }
      }
    }
  });

  updateChart('diskBarChart', {
    type: 'bar',
    data: {
      labels: ['Espace'],
      datasets: [{
        label: 'Utilisé',
        data: [used],
        backgroundColor: '#ff6b35'
      }, {
        label: 'Libre',
        data: [free],
        backgroundColor: '#4ec9b0'
      }]
    },
    options: {
      indexAxis: 'y',
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: {
          stacked: true,
          ticks: {
            color: '#9fa0a4'
          },
          grid: {
            color: '#2a2b2f'
          }
        },
        y: {
          stacked: true,
          ticks: {
            color: '#9fa0a4'
          },
          grid: {
            color: '#2a2b2f'
          }
        }
      },
      plugins: {
        legend: {
          labels: {
            color: '#d8d9da'
          }
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

  const recent = filtered.slice(-10);
  let upSpeed = 0,
    downSpeed = 0;
  if (recent.length >= 2) {
    const last = recent[recent.length - 1];
    const prev = recent[recent.length - 2];
    const timeDiff = last.timestamp - prev.timestamp;
    if (timeDiff > 0) {
      upSpeed = Math.max(0, (last.network_sent - prev.network_sent) / timeDiff);
      downSpeed = Math.max(0, (last.network_recv - prev.network_recv) / timeDiff);
    }
  }
  document.getElementById('net-up-speed').textContent = formatBytes(upSpeed) + '/s';
  document.getElementById('net-down-speed').textContent = formatBytes(downSpeed) + '/s';

  const k = unitPref === 'decimal' ? 1000 : 1024;
  const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());

  const sentData = filtered.map((d, i) => {
    if (i === 0) return 0;
    const prev = filtered[i - 1];
    const time = d.timestamp - prev.timestamp;
    return time > 0 ? ((d.network_sent - prev.network_sent) / time) / k : 0;
  });

  const recvData = filtered.map((d, i) => {
    if (i === 0) return 0;
    const prev = filtered[i - 1];
    const time = d.timestamp - prev.timestamp;
    return time > 0 ? ((d.network_recv - prev.network_recv) / time) / k : 0;
  });

  updateChart('networkChart', {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: `Envoi (${unitPref === 'decimal' ? 'KB/s' : 'KiB/s'})`,
        data: sentData,
        borderColor: '#ff6b35',
        backgroundColor: 'rgba(255, 107, 53, 0.1)',
        tension: 0.4,
        fill: true
      },
      {
        label: `Réception (${unitPref === 'decimal' ? 'KB/s' : 'KiB/s'})`,
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

  try {
    const res = await fetch('/api/network');
    const interfaces = await res.json();
    const container = document.getElementById('network-interfaces');
    if (container) {
      if (interfaces.length > 0) {
        let html = '<div class="chart-header"><h3><i class="fas fa-list"></i> Détails Interfaces</h3></div><div class="stats-container">';
        interfaces.forEach(iface => {
          html += `<div class="stat-item"><span class="stat-label"><i class="fas fa-ethernet"></i> ${iface.interface}</span><span class="stat-value">↑ ${formatBytes(iface.bytes_sent)} / ↓ ${formatBytes(iface.bytes_recv)}</span></div>`;
        });
        html += '</div>';
        container.innerHTML = html;
      } else {
        container.innerHTML = '<div class="chart-header"><h3><i class="fas fa-list"></i> Détails Interfaces</h3></div><p style="padding: 20px; color: #9fa0a4;">Aucune interface réseau trouvée (hors loopback).</p>';
      }
    }
  } catch (err) {
    console.error('Erreur interfaces réseau', err);
  }
}

function updateUptime(filtered, latest) {
  const uptimeSeconds = latest.uptime_seconds || 0;
  document.getElementById('uptime-current').textContent = formatDuration(uptimeSeconds);

  const days = Math.floor(uptimeSeconds / (3600 * 24));
  document.getElementById('uptime-days').textContent = days;
  document.getElementById('uptime-hours').textContent = Math.floor((uptimeSeconds % (3600 * 24)) / 3600);
  document.getElementById('uptime-minutes').textContent = Math.floor((uptimeSeconds % 3600) / 60);
  document.getElementById('uptime-reliability').textContent = '100%';

  const circle = document.getElementById('uptime-circle');
  if (circle) {
    const maxSeconds = 30 * 24 * 3600;
    const circumference = 2 * Math.PI * 90;
    const progress = Math.min(uptimeSeconds / maxSeconds, 1);
    circle.style.strokeDasharray = circumference;
    circle.style.strokeDashoffset = circumference - progress * circumference;
  }
}

async function scanNetwork() {
  const btn = document.getElementById('scan-network-btn');
  const status = document.getElementById('scan-status');
  const container = document.getElementById('network-devices-container');

  btn.disabled = true;
  btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Scan en cours...';
  status.textContent = 'Scan du réseau...';

  try {
    const res = await fetch('/api/network/scan');
    const data = await res.json();

    if (data.devices && data.devices.length > 0) {
      let html = '<table class="styled-table"><thead><tr><th>Statut</th><th>Adresse IP</th><th>Nom d\'hôte</th><th>MAC</th><th>Vendeur</th></tr></thead><tbody>';
      data.devices.forEach(dev => {
        const isLocal = dev.is_local ? ' (Ce Mac)' : '';
        html += `<tr>
            <td><span class="status-badge up">En ligne</span></td>
            <td style="color:#4ec9b0; font-family:monospace;">${dev.ip}</td>
            <td>${dev.hostname || '--'}${isLocal}</td>
            <td style="font-family:monospace;">${dev.mac || '--'}</td>
            <td>${dev.vendor || '--'}</td>
        </tr>`;
      });
      html += '</tbody></table>';
      container.innerHTML = html;
      status.textContent = `${data.devices.length} appareils trouvés. IP Locale: ${data.local_ip || 'N/A'}`;
    } else {
      container.innerHTML = '<div class="empty-state"><p>Aucun appareil trouvé.</p></div>';
      status.textContent = 'Scan terminé. Aucun appareil trouvé.';
    }
  } catch (err) {
    status.textContent = 'Erreur pendant le scan.';
  }
  btn.disabled = false;
  btn.innerHTML = '<i class="fas fa-search"></i> Scanner Réseau';
}

function setProcessSort(sort) {
  currentSort = sort;
  document.getElementById('sort-cpu-btn').classList.toggle('active', sort === 'cpu');
  document.getElementById('sort-mem-btn').classList.toggle('active', sort === 'mem');
  fetchProcesses();
}

async function fetchProcesses() {
  try {
    const res = await fetch(`/api/processes?sort=${currentSort}&limit=20`);
    const data = await res.json();
    const container = document.getElementById('processes-table-container');

    document.getElementById('process-count').textContent = data.processes && data.processes.length > 0 ?
      `Top ${data.processes.length} par ${currentSort.toUpperCase()}` : 'Aucun processus trouvé';

    if (data.processes && data.processes.length > 0) {
      let html = '<table class="styled-table"><thead><tr><th>PID</th><th>Utilisateur</th><th>CPU</th><th>MEM</th><th>Commande</th><th>Action</th></tr></thead><tbody>';
      data.processes.forEach(proc => {
        const cpuClass = proc.cpu > 50 ? 'high' : (proc.cpu > 20 ? 'medium' : 'low');
        const memClass = proc.mem > 50 ? 'high' : (proc.mem > 20 ? 'medium' : 'low');
        html += `<tr>
            <td style="color:#9fa0a4;">${proc.pid}</td>
            <td>${proc.user}</td>
            <td><span class="metric-badge ${cpuClass}">${proc.cpu.toFixed(1)}%</span></td>
            <td><span class="metric-badge ${memClass}">${proc.mem.toFixed(1)}%</span></td>
            <td style="font-family:monospace; max-width:200px; overflow:hidden; white-space:nowrap; text-overflow:ellipsis;" title="${proc.command}">${proc.command}</td>
            <td><button class="btn-kill" onclick="killProcess(${proc.pid})"><i class="fas fa-times"></i></button></td>
        </tr>`;
      });
      html += '</tbody></table>';
      container.innerHTML = html;
    } else {
      container.innerHTML = '<div class="empty-state"><p>Aucun processus trouvé.</p></div>';
    }
  } catch (err) {
    console.error(err);
  }
}

async function fetchAlerts() {
  try {
    const res = await fetch('/api/alerts');
    const data = await res.json();
    const container = document.getElementById('alerts-container');

    document.getElementById('alert-count').textContent = data.alerts.length;
    document.getElementById('system-status').textContent = data.alerts.length > 0 ? 'Attention' : 'OK';
    document.getElementById('last-check').textContent = new Date().toLocaleTimeString();

    if (data.alerts.length > 0) {
      let html = '<div class="alerts-list">';
      data.alerts.forEach(alert => {
        const type = alert.type === 'critical' ? 'critical' : 'warning';
        const icon = alert.type === 'critical' ? 'radiation' : 'exclamation-triangle';
        html += `<div class="alert-item ${type}">
            <div class="alert-icon"><i class="fas fa-${icon}"></i></div>
            <div class="alert-content">
                <strong>ALERTE ${alert.category.toUpperCase()}</strong>
                <p>${alert.message}</p>
                <div class="alert-time"><i class="far fa-clock"></i> ${new Date(alert.timestamp * 1000).toLocaleTimeString()}</div>
            </div>
        </div>`;
      });
      html += '</div>';
      container.innerHTML = html;
    } else {
      container.innerHTML = `<div class="empty-state"><i class="fas fa-check-circle" style="color:#4ec9b0;"></i><p>Système sain.</p></div>`;
    }
  } catch (err) {
    console.error(err);
  }
}

async function fetchLogs() {
  try {
    const res = await fetch('/api/logs');
    const data = await res.json();
    const container = document.getElementById('logs-table-container');

    if (data.logs && data.logs.length > 0) {
      let html = '<table class="styled-table"><thead><tr><th style="width:15%">Niveau</th><th>Message</th></tr></thead><tbody>';
      data.logs.forEach(log => {
        const levelClass = log.level === 'ERROR' ? 'high' : 'low';
        html += `<tr>
            <td><span class="metric-badge ${levelClass}">${log.level}</span></td>
            <td style="font-family:monospace; font-size:12px; white-space: pre-wrap; word-break: break-all;">${log.message}</td>
        </tr>`;
      });
      html += '</tbody></table>';
      container.innerHTML = html;
    } else {
      container.innerHTML = `<div class="empty-state"><p>${data.error || 'Aucun journal trouvé ou fichier vide. Vérifiez la config server.rb.'}</p></div>`;
    }
  } catch (err) {
    console.error("Erreur fetch logs:", err);
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
        labels: {
          color: '#d8d9da',
          font: {
            size: 12
          }
        }
      }
    },
    scales: {
      x: {
        ticks: {
          color: '#9fa0a4',
          maxRotation: 45,
          minRotation: 45
        },
        grid: {
          color: '#2a2b2f'
        }
      },
      y: {
        ticks: {
          color: '#9fa0a4'
        },
        grid: {
          color: '#2a2b2f'
        },
        beginAtZero: true,
        ...extra
      }
    }
  };
}

function updateSettingsPage() {
  initPrefs();
  fetchDisks().then(devices => {
    const sel = document.getElementById('settings-disk-select');
    if (!sel) return;
    sel.innerHTML = '';
    const def = document.createElement('option');
    def.text = "Disque Principal OS (Défaut)";
    def.value = "default";
    const isDefaultSelected = !selectedDisk;
    def.selected = isDefaultSelected;
    sel.add(def);

    devices.forEach(d => {
      const opt = document.createElement('option');
      opt.text = `${d.mountpoint} (${formatBytes(d.total_bytes)})`;
      opt.value = JSON.stringify(d);
      if (selectedDisk && selectedDisk.mountpoint === d.mountpoint) {
        opt.selected = true;
      }
      sel.add(opt);
    });

    document.querySelector(`input[name="unit-pref"][value="${unitPref}"]`).checked = true;
    const storedRate = localStorage.getItem('refreshRate') || '5000';
    document.getElementById('settings-refresh-rate').value = storedRate;

    document.getElementById('save-settings')?.addEventListener('click', saveSettings);
    document.getElementById('reset-settings')?.addEventListener('click', resetSettings);
  });
}

function saveSettings() {
  localStorage.setItem('unitPref', document.querySelector('input[name="unit-pref"]:checked').value);
  const sel = document.getElementById('settings-disk-select');
  if (sel.value !== 'default') {
    localStorage.setItem('selectedDisk', sel.value);
    selectedDisk = JSON.parse(sel.value);
  } else {
    localStorage.removeItem('selectedDisk');
    selectedDisk = null;
  }
  localStorage.setItem('refreshRate', document.getElementById('settings-refresh-rate').value);

  initPrefs();
  clearInterval(intervalID);
  intervalID = setInterval(mainLoop, parseInt(localStorage.getItem('refreshRate')));
  switchPage(currentPage);
  alert('Paramètres Enregistrés');
}

function resetSettings() {
  localStorage.clear();
  location.reload();
}

async function fetchTickets() {
  try {
    const res = await fetch('/api/tickets');
    const tickets = await res.json();
    const container = document.getElementById('tickets-container');

    if (tickets.length > 0) {
      let html = '<table class="styled-table"><thead><tr><th>ID</th><th>Date</th><th>Niveau</th><th>Titre</th><th>Message</th><th>Statut</th></tr></thead><tbody>';
      tickets.forEach(ticket => {
        const levelClass = ticket.level === 'critical' ? 'critical' : 'warning';
        const dateStr = new Date(ticket.timestamp * 1000).toLocaleString();
        html += `<tr>
            <td style="color:#9fa0a4;">#${ticket.id}</td>
            <td>${dateStr}</td>
            <td><span class="metric-badge ${levelClass}">${ticket.level}</span></td>
            <td><strong>${ticket.title}</strong></td>
            <td>${ticket.description}</td>
            <td><span class="status-badge ${ticket.status === 'open' ? 'down' : 'up'}">${ticket.status.toUpperCase()}</span></td>
        </tr>`;
      });
      html += '</tbody></table>';
      container.innerHTML = html;
    } else {
      container.innerHTML = '<div class="empty-state"><p>Aucun ticket ouvert.</p></div>';
    }
  } catch (err) { console.error(err); }
}

function mainLoop() {
  if (['dashboard', 'cpu', 'memory', 'disk', 'network', 'uptime'].includes(currentPage)) fetchData();
  if (currentPage === 'processes') fetchProcesses();
  if (currentPage === 'alerts') fetchAlerts();
  if (currentPage === 'tickets') fetchTickets();
  if (currentPage === 'logs') fetchLogs();
}

document.getElementById('export-json')?.addEventListener('click', () => {
  window.location.href = '/api/system';
});

document.addEventListener('DOMContentLoaded', () => {
  initPrefs();
  initNav();

  updateSettingsPage();

  switchPage('dashboard');
  const rate = parseInt(localStorage.getItem('refreshRate') || '5000');

  intervalID = setInterval(mainLoop, rate);

  fetchData();
});

// --- FONCTION DE VÉRIFICATION DES MISES À JOUR ---
async function checkUpdates() {
  try {
    const res = await fetch('/api/check_update');
    if (!res.ok) return; // Évite les logs d'erreurs si la route n'est pas encore prête
    const data = await res.json();

    if (data.update_available) {
      // Vérifie si la bannière n'existe pas déjà
      if (document.getElementById('update-banner')) return;

      const banner = document.createElement('div');
      banner.id = 'update-banner';
      banner.style.cssText = `
        background: #ff6b35;
        color: white;
        padding: 12px;
        text-align: center;
        font-weight: bold;
        position: sticky;
        top: 0;
        z-index: 10001;
        box-shadow: 0 2px 10px rgba(0,0,0,0.3);
        font-family: sans-serif;
      `;
      banner.innerHTML = `
        <i class="fas fa-cloud-download-alt"></i> 
        Une nouvelle version <span style="text-decoration: underline;">${data.remote}</span> est disponible ! 
        Lancez <code>git pull</code> & <code>./deploy.sh</code> pour mettre à jour.
        <button onclick="this.parentElement.remove()" style="margin-left:15px; background:transparent; border:1px solid white; color:white; border-radius:4px; cursor:pointer; padding:2px 8px;">Ignorer</button>
      `;
      document.body.prepend(banner);
    }
  } catch (e) {
    console.log("Vérification maj : serveur non prêt.");
  }
}

// --- INITIALISATION UNIQUE ---
document.addEventListener('DOMContentLoaded', () => {
  // 1. Charger les préférences utilisateur
  initPrefs();

  // 2. Initialiser la navigation
  initNav();

  // 3. Préparer la page des paramètres (chargement des disques)
  updateSettingsPage();

  // 4. Afficher le Dashboard par défaut
  switchPage('dashboard');

  // 5. Lancer la boucle de rafraîchissement
  const rate = parseInt(localStorage.getItem('refreshRate') || '5000');
  intervalID = setInterval(mainLoop, rate);

  // 6. Premier chargement des données
  fetchData();

  // 7. Vérifier les mises à jour GitHub (Nouveau)
  checkUpdates();
});