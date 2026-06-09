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

  // Stress Test Controls
  document.getElementById('stress-start-btn')?.addEventListener('click', startStressTest);
  document.getElementById('stress-stop-btn')?.addEventListener('click', stopStressTest);
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

  const cpuVal = latest.cpu_usage || 0;
  document.getElementById('cpu').textContent = cpuVal.toFixed(1) + '%';
  setMetricBar('cpu-bar', cpuVal, 'cpu', 'card-cpu');

  document.getElementById('memory').textContent = `${formatBytes(latest.memory_used_bytes)} / ${formatBytes(latest.memory_total_bytes)}`;
  setMetricBar('memory-bar', latest.memory_percent || 0, 'memory', 'card-memory');

  const diskData = selectedDisk || {
    used_bytes: latest.disk_used_bytes,
    total_bytes: latest.disk_total_bytes
  };
  document.getElementById('disk').textContent = `${formatBytes(diskData.used_bytes)} / ${formatBytes(diskData.total_bytes)}`;
  const diskPercent = diskData.total_bytes > 0 ? (diskData.used_bytes / diskData.total_bytes * 100) : 0;
  setMetricBar('disk-bar', diskPercent, 'disk', 'card-disk');

  document.getElementById('uptime').textContent = formatDuration(latest.uptime_seconds);

  const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());

  updateChart('cpuChart', {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: 'CPU %',
        data: filtered.map(d => d.cpu_usage || 0),
        borderColor: '#7c8dff',
        backgroundColor: 'rgba(124, 141, 255, 0.12)',
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
        borderColor: '#2fe3bf',
        backgroundColor: 'rgba(47, 227, 191, 0.12)',
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
        borderColor: '#7c8dff',
        backgroundColor: 'rgba(124, 141, 255, 0.2)',
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
        backgroundColor: ['#ff5d73', '#ffc24b', '#2fe3bf'],
        borderWidth: 2,
        borderColor: '#0d1119'
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          labels: {
            color: '#9aa6b6'
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

  if (filtered.length >= 2) {
    const first = filtered[0];
    const last = filtered[filtered.length - 1];
    const timeDiffMin = (last.timestamp - first.timestamp) / 60;
    if (timeDiffMin > 0) {
      const bytesDiff = (last.memory_used_bytes || 0) - (first.memory_used_bytes || 0);
      const growthPerMin = bytesDiff / timeDiffMin;
      const sign = growthPerMin >= 0 ? '+' : '-';
      document.getElementById('mem-growth').textContent = sign + formatBytes(Math.abs(growthPerMin)) + '/min';
      if (growthPerMin > 0) {
        const bytesLeft = (last.memory_total_bytes || 0) - (last.memory_used_bytes || 0);
        const minLeft = bytesLeft / growthPerMin;
        document.getElementById('mem-estimate').textContent = minLeft > 60 ? `${(minLeft / 60).toFixed(1)}h` : `${minLeft.toFixed(0)}min`;
      } else {
        document.getElementById('mem-estimate').textContent = 'Jamais';
      }
    }
  } else {
    document.getElementById('mem-growth').textContent = '0 B/min';
    document.getElementById('mem-estimate').textContent = 'Jamais';
  }

  updateChart('memDetailChart', {
    type: 'line',
    data: {
      labels: filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString()),
      datasets: [{
        label: `Mémoire ${unit}`,
        data: memValues,
        borderColor: '#2fe3bf',
        backgroundColor: 'rgba(47, 227, 191, 0.2)',
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
        backgroundColor: ['#7c8dff', '#2fe3bf']
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          labels: {
            color: '#9aa6b6'
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
        backgroundColor: ['#7c8dff', '#2fe3bf']
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          labels: {
            color: '#9aa6b6'
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
        backgroundColor: '#7c8dff'
      }, {
        label: 'Libre',
        data: [free],
        backgroundColor: '#2fe3bf'
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
            color: '#9aa6b6'
          },
          grid: {
            color: 'rgba(255,255,255,0.06)'
          }
        },
        y: {
          stacked: true,
          ticks: {
            color: '#9aa6b6'
          },
          grid: {
            color: 'rgba(255,255,255,0.06)'
          }
        }
      },
      plugins: {
        legend: {
          labels: {
            color: '#9aa6b6'
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
        borderColor: '#7c8dff',
        backgroundColor: 'rgba(124, 141, 255, 0.12)',
        tension: 0.4,
        fill: true
      },
      {
        label: `Réception (${unitPref === 'decimal' ? 'KB/s' : 'KiB/s'})`,
        data: recvData,
        borderColor: '#2fe3bf',
        backgroundColor: 'rgba(47, 227, 191, 0.12)',
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
        container.innerHTML = '<div class="chart-header"><h3><i class="fas fa-list"></i> Détails Interfaces</h3></div><p style="padding: 20px; color: #9aa6b6;">Aucune interface réseau trouvée (hors loopback).</p>';
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

function deviceTypeChip(dev) {
  const type = dev.device_type || 'unknown';
  const label = dev.device_label || 'Inconnu';
  const icon = dev.device_icon || 'circle-question';
  // Apple / Windows sont des icônes "brand" (préfixe fab), les autres sont "solid" (fas)
  const brandIcons = ['apple', 'windows'];
  const prefix = brandIcons.includes(icon) ? 'fab' : 'fas';
  return `<span class="device-chip dt-${type}"><i class="${prefix} fa-${icon}"></i>${label}</span>`;
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
      let html = '<table class="styled-table"><thead><tr><th>Statut</th><th>Type</th><th>Adresse IP</th><th>Nom d\'hôte</th><th>MAC</th><th>Vendeur</th><th>Latence</th><th>Actions</th></tr></thead><tbody>';
      data.devices.forEach(dev => {
        const isLocal = dev.is_local ? ' (Ce Mac)' : '';
        const latency = (dev.latency_ms !== null && dev.latency_ms !== undefined) ? `${dev.latency_ms} ms` : '--';
        const macAttr = dev.mac ? dev.mac.replace(/'/g, '') : '';
        const ipAttr = dev.ip.replace(/'/g, '');
        const typeChip = deviceTypeChip(dev);

        let actions = '';
        if (dev.is_local) {
          actions = '<span style="color:#5b6675;">--</span>';
        } else {
          const wakeBtn = dev.mac
            ? `<button class="btn-net wake" title="Allumer (Wake-on-LAN)" onclick="wakeDevice('${macAttr}', '${ipAttr}')"><i class="fas fa-power-off"></i></button>`
            : '';
          const shutdownBtn = `<button class="btn-net shutdown" title="Éteindre / Redémarrer à distance" onclick="openShutdownModal('${ipAttr}')"><i class="fas fa-stop-circle"></i></button>`;
          actions = `<div class="net-actions">${wakeBtn}${shutdownBtn}</div>`;
        }

        html += `<tr>
            <td><span class="status-badge up">En ligne</span></td>
            <td>${typeChip}</td>
            <td style="color:#2fe3bf; font-family:monospace;">${dev.ip}</td>
            <td>${dev.hostname || '--'}${isLocal}</td>
            <td style="font-family:monospace;">${dev.mac || '--'}</td>
            <td>${dev.vendor || '--'}</td>
            <td style="font-family:monospace;">${latency}</td>
            <td>${actions}</td>
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

async function wakeDevice(mac, ip) {
  if (!mac) {
    showNotification('Adresse MAC inconnue pour cet appareil', 'error');
    return;
  }
  if (!confirm(`Envoyer un signal Wake-on-LAN à ${ip} (${mac}) ?`)) return;
  try {
    const res = await fetch('/api/network/wake', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ mac })
    });
    const data = await res.json();
    showNotification(data.message, data.success ? 'success' : 'error');
  } catch (err) {
    showNotification('Erreur de connexion', 'error');
  }
}

function openShutdownModal(ip) {
  // Supprime un éventuel modal existant
  document.getElementById('shutdown-modal')?.remove();

  const overlay = document.createElement('div');
  overlay.id = 'shutdown-modal';
  overlay.className = 'modal-overlay';
  overlay.innerHTML = `
    <div class="modal-card">
      <div class="modal-header">
        <h3><i class="fas fa-power-off"></i> Arrêt distant — ${ip}</h3>
        <button class="modal-close" onclick="document.getElementById('shutdown-modal').remove()">&times;</button>
      </div>
      <div class="modal-body">
        <label class="modal-label">Système cible</label>
        <select id="sd-os" class="settings-select">
          <option value="linux">Linux (SSH)</option>
          <option value="mac">macOS (SSH)</option>
          <option value="windows">Windows (SMB / net rpc)</option>
        </select>

        <label class="modal-label">Utilisateur</label>
        <input id="sd-user" type="text" class="modal-input" placeholder="ex: admin / root" autocomplete="off">

        <label class="modal-label">Mot de passe <span style="color:#9aa6b6; font-weight:400;">(vide = clé SSH)</span></label>
        <input id="sd-pass" type="password" class="modal-input" placeholder="••••••" autocomplete="off">

        <label class="modal-checkbox">
          <input id="sd-reboot" type="checkbox"> Redémarrer au lieu d'éteindre
        </label>

        <div class="alert-box" style="margin-top:14px;">
          <i class="fas fa-info-circle"></i>
          <div><p style="margin:0;">L'arrêt nécessite un accès SSH (Linux/macOS, avec sudo) ou un compte admin Windows (Samba installé côté serveur).</p></div>
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn-secondary" onclick="document.getElementById('shutdown-modal').remove()">Annuler</button>
        <button class="btn-primary" id="sd-confirm" style="background:#e74c3c;"><i class="fas fa-power-off"></i> Confirmer</button>
      </div>
    </div>`;

  document.body.appendChild(overlay);
  overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });
  document.getElementById('sd-confirm').addEventListener('click', () => submitShutdown(ip));
}

async function submitShutdown(ip) {
  const os = document.getElementById('sd-os').value;
  const user = document.getElementById('sd-user').value.trim();
  const password = document.getElementById('sd-pass').value;
  const reboot = document.getElementById('sd-reboot').checked;
  const action = reboot ? 'redémarrer' : 'éteindre';

  if (os !== 'windows' && !user) {
    showNotification('Utilisateur requis', 'error');
    return;
  }
  if (!confirm(`Confirmer : ${action} ${ip} ?`)) return;

  const btn = document.getElementById('sd-confirm');
  btn.disabled = true;
  btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Envoi...';

  try {
    const res = await fetch('/api/network/shutdown', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ip, os, user, password, reboot })
    });
    const data = await res.json();
    showNotification(data.message, data.success ? 'success' : 'error');
    if (data.success) document.getElementById('shutdown-modal')?.remove();
  } catch (err) {
    showNotification('Erreur de connexion', 'error');
  } finally {
    if (document.getElementById('sd-confirm')) {
      btn.disabled = false;
      btn.innerHTML = '<i class="fas fa-power-off"></i> Confirmer';
    }
  }
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
            <td style="color:#9aa6b6;">${proc.pid}</td>
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
      container.innerHTML = `<div class="empty-state"><i class="fas fa-check-circle" style="color:#2fe3bf;"></i><p>Système sain.</p></div>`;
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
          color: '#9aa6b6',
          font: {
            size: 12
          }
        }
      }
    },
    scales: {
      x: {
        ticks: {
          color: '#9aa6b6',
          maxRotation: 45,
          minRotation: 45
        },
        grid: {
          color: 'rgba(255,255,255,0.06)'
        }
      },
      y: {
        ticks: {
          color: '#9aa6b6'
        },
        grid: {
          color: 'rgba(255,255,255,0.06)'
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
      let html = '<table class="styled-table"><thead><tr><th>ID</th><th>Date</th><th>Niveau</th><th>Titre</th><th>Message</th><th>Statut</th><th>Actions</th></tr></thead><tbody>';
      tickets.forEach(ticket => {
        const levelClass = ticket.level === 'critical' ? 'critical' : 'warning';
        const dateStr = new Date(ticket.timestamp * 1000).toLocaleString();
        const closeBtn = ticket.status === 'open' ?
          `<button class="btn-close-ticket" onclick="closeTicket('${ticket.id}')">Fermer</button>` :
          '<span style="color:#666;">-</span>';

        html += `<tr>
            <td style="color:#9aa6b6;">#${ticket.id}</td>
            <td>${dateStr}</td>
            <td><span class="metric-badge ${levelClass}">${ticket.level}</span></td>
            <td><strong>${ticket.title}</strong></td>
            <td>${ticket.description}</td>
            <td><span class="status-badge ${ticket.status}">${ticket.status.toUpperCase()}</span></td>
            <td>${closeBtn}</td>
        </tr>`;
      });
      html += '</tbody></table>';
      container.innerHTML = html;
    } else {
      container.innerHTML = '<div class="empty-state"><p>Aucun ticket ouvert.</p></div>';
    }
  } catch (err) { console.error(err); }
}

async function closeTicket(ticketId) {
  if (!confirm('Fermer ce ticket ?')) return;
  try {
    const response = await fetch(`/api/tickets/${ticketId}/close`, { method: 'POST' });
    const data = await response.json();
    if (data.success) {
      fetchTickets();
      showNotification('Ticket fermé avec succès', 'success');
    } else {
      showNotification('Erreur lors de la fermeture', 'error');
    }
  } catch (error) {
    showNotification('Erreur de connexion', 'error');
  }
}

async function killProcess(pid) {
  if (!confirm(`Terminer le processus PID ${pid} ?`)) return;
  try {
    const res = await fetch(`/api/processes/${pid}`, { method: 'DELETE' });
    const data = await res.json();
    if (data.success) {
      showNotification(data.message, 'success');
      fetchProcesses();
    } else {
      showNotification(data.error || 'Permission refusée', 'error');
    }
  } catch (err) {
    showNotification('Erreur de connexion', 'error');
  }
}

function showNotification(message, type = 'success') {
  const notif = document.createElement('div');
  notif.className = `notification-toast ${type}`;
  notif.textContent = message;
  document.body.appendChild(notif);
  setTimeout(() => {
    notif.style.animation = 'toastSlideOut 0.3s ease forwards';
    setTimeout(() => notif.remove(), 300);
  }, 3000);
}

function setMetricBar(barId, percent, valueId, cardId) {
  const bar = document.getElementById(barId);
  if (!bar) return;
  const p = Math.min(100, Math.max(0, percent || 0));
  bar.style.width = p + '%';
  const color = p >= 85 ? '#ff5d73' : p >= 60 ? '#ffc24b' : '#2fe3bf';
  bar.style.backgroundColor = color;
  const val = document.getElementById(valueId);
  if (val) val.className = 'metric-value ' + (p >= 85 ? 'critical' : p >= 60 ? 'warning' : 'ok');
  const card = document.getElementById(cardId);
  if (card) card.classList.toggle('critical-state', p >= 85);
}

function startClock() {
  const el = document.getElementById('top-clock');
  if (!el) return;
  const tick = () => { el.textContent = new Date().toLocaleTimeString('fr-FR'); };
  tick();
  setInterval(tick, 1000);
}

// Stress Test Functions
async function startStressTest() {
  const startBtn = document.getElementById('stress-start-btn');
  const stopBtn = document.getElementById('stress-stop-btn');
  const status = document.getElementById('stress-status');

  startBtn.disabled = true;
  startBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Démarrage...';

  try {
    const res = await fetch('/api/stress-test/start', { method: 'POST' });
    const data = await res.json();

    if (data.success) {
      startBtn.disabled = true;
      stopBtn.disabled = false;
      status.textContent = '⚡ Stress test en cours...';
      status.style.color = '#7c8dff';
      startBtn.innerHTML = '<i class="fas fa-play"></i> Démarrer Stress Test';
    } else {
      status.textContent = '❌ ' + data.message;
      startBtn.disabled = false;
      startBtn.innerHTML = '<i class="fas fa-play"></i> Démarrer Stress Test';
    }
  } catch (err) {
    status.textContent = '❌ Erreur de connexion';
    startBtn.disabled = false;
    startBtn.innerHTML = '<i class="fas fa-play"></i> Démarrer Stress Test';
  }
}

async function stopStressTest() {
  const startBtn = document.getElementById('stress-start-btn');
  const stopBtn = document.getElementById('stress-stop-btn');
  const status = document.getElementById('stress-status');

  stopBtn.disabled = true;
  stopBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Arrêt...';

  try {
    const res = await fetch('/api/stress-test/stop', { method: 'POST' });
    const data = await res.json();

    if (data.success) {
      startBtn.disabled = false;
      stopBtn.disabled = true;
      status.textContent = '✅ Stress test arrêté';
      status.style.color = '#2fe3bf';
      stopBtn.innerHTML = '<i class="fas fa-stop"></i> Arrêter Stress Test';
    } else {
      status.textContent = '❌ ' + data.message;
      stopBtn.innerHTML = '<i class="fas fa-stop"></i> Arrêter Stress Test';
    }
  } catch (err) {
    status.textContent = '❌ Erreur de connexion';
    stopBtn.disabled = false;
    stopBtn.innerHTML = '<i class="fas fa-stop"></i> Arrêter Stress Test';
  }
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
  initPrefs();
  initNav();
  startClock();
  updateSettingsPage();
  switchPage('dashboard');

  const rate = parseInt(localStorage.getItem('refreshRate') || '5000');
  intervalID = setInterval(mainLoop, rate);

  fetchData();
  checkUpdates();
});

//test