/**
 * Fichier : app.js (Version fusionnée)
 * Conserve les graphiques d'origine + les nouveaux outils.
 */

let charts = {};
let currentPage = 'dashboard';
let intervalID;
let selectedDisk = null; 
let unitPref = 'binary'; 
let currentSort = 'cpu'; // Ajout pour le tri des processus

// --- Utilitaires ---

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

// --- Initialisation ---

function initPrefs() {
    try {
        unitPref = localStorage.getItem('unitPref') || 'binary';
        const storedDisk = localStorage.getItem('selectedDisk');
        if (storedDisk && storedDisk !== 'null') {
            selectedDisk = JSON.parse(storedDisk);
        }
    } catch (e) { console.error("Erreur préférences:", e); }
}

function initNav() {
  document.querySelectorAll('.menu-item').forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const page = item.getAttribute('data-page');
      if (page) switchPage(page);
    });
  });

  // Listeners pour les nouvelles pages
  document.getElementById('scan-network-btn')?.addEventListener('click', scanNetwork);
  document.getElementById('sort-cpu-btn')?.addEventListener('click', () => setProcessSort('cpu'));
  document.getElementById('sort-mem-btn')?.addEventListener('click', () => setProcessSort('mem'));
}

function switchPage(page) {
  currentPage = page;
  
  // UI Updates
  document.querySelectorAll('.menu-item').forEach(i => i.classList.remove('active'));
  const active = document.querySelector(`[data-page="${page}"]`);
  if (active) active.classList.add('active');
  
  document.getElementById('page-title').textContent = page.charAt(0).toUpperCase() + page.slice(1) + ' Monitor';
  
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  const activePage = document.getElementById(`${page}-page`);
  if (activePage) activePage.classList.add('active');
  
  // Logic Dispatch
  if (page === 'settings') {
    updateSettingsPage();
  } else if (page === 'scanner') {
    // Rien à charger auto pour scanner
  } else if (page === 'processes') {
    fetchProcesses();
  } else if (page === 'alerts') {
    fetchAlerts();
  } else {
    if (page === 'disk' || page === 'network') fetchDisks();
    fetchData(); 
  }
}

// --- Récupération des Données Système (Graphiques) ---

async function fetchData() {
  try {
    const res = await fetch('/api/system');
    if (!res.ok) throw new Error('Échec fetch system');
    const data = await res.json();
    
    const minutes = parseInt(document.getElementById('interval').value);
    const cutoff = Date.now() / 1000 - minutes * 60;
    const filtered = data.filter(d => d.timestamp >= cutoff);
    
    if (filtered.length === 0) return;
    const latest = filtered[filtered.length - 1];
    
    // Switch vers vos fonctions originales
    switch(currentPage) {
      case 'dashboard': updateDashboard(filtered, latest); break;
      case 'cpu':       updateCPU(filtered, latest); break;
      case 'memory':    updateMemory(filtered, latest); break;
      case 'disk':      updateDisk(filtered, latest); break;
      case 'network':   updateNetwork(filtered, latest); break;
      case 'uptime':    updateUptime(filtered, latest); break;
    }
  } catch (err) { console.error('Erreur data:', err); }
}

async function fetchDisks() {
    try {
        const res = await fetch('/api/disks');
        if (res.ok) return await res.json();
    } catch (err) { return []; }
}

// --- Vos fonctions de mise à jour ORIGINALES (pour garder les graphs) ---

function updateDashboard(filtered, latest) {
  const k = unitPref === 'decimal' ? 1e9 : 1024**3;
  const unit = unitPref === 'decimal' ? 'GB' : 'GiB';

  document.getElementById('sys-hostname').textContent = latest.hostname || 'Inconnu';
  document.getElementById('sys-platform').textContent = latest.platform ? `${latest.platform} ${latest.os || ''}` : 'Inconnu';
  document.getElementById('sys-cores').textContent = latest.cpu_cores ? `${latest.cpu_cores} cœurs` : 'Inconnu';
  
  document.getElementById('cpu').textContent = (latest.cpu_usage || 0).toFixed(1) + '%';
  document.getElementById('memory').textContent = `${formatBytes(latest.memory_used_bytes)} / ${formatBytes(latest.memory_total_bytes)}`;
  
  const diskData = selectedDisk || { used_bytes: latest.disk_used_bytes, total_bytes: latest.disk_total_bytes };
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
        tension: 0.4, fill: true
      }]
    },
    options: getChartOptions({ max: 100 })
  });
  
  updateChart('memoryChart', {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: `Mémoire ${unit}`,
        data: filtered.map(d => (d.memory_used_bytes || 0) / k),
        borderColor: '#4ec9b0',
        backgroundColor: 'rgba(78, 201, 176, 0.1)',
        tension: 0.4, fill: true
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
  
  updateChart('cpuDetailChart', {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: 'Utilisation CPU %',
        data: cpuValues,
        borderColor: '#ff6b35',
        backgroundColor: 'rgba(255, 107, 53, 0.2)',
        tension: 0.4, fill: true
      }]
    },
    options: getChartOptions({ max: 100 })
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
      labels: ['High', 'Medium', 'Low'],
      datasets: [{
        data: [high, medium, low],
        backgroundColor: ['#ff6b35', '#ffcc00', '#4ec9b0'],
        borderWidth: 2, borderColor: '#111217'
      }]
    },
    options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { labels: { color: '#d8d9da' }, position: 'bottom' } } }
  });
}

function updateMemory(filtered, latest) {
  const k = unitPref === 'decimal' ? 1e9 : 1024**3;
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
  document.getElementById('mem-estimate').textContent = 'Never';

  updateChart('memDetailChart', {
    type: 'line',
    data: {
      labels: filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString()),
      datasets: [{ label: `Mémoire ${unit}`, data: memValues, borderColor: '#4ec9b0', backgroundColor: 'rgba(78, 201, 176, 0.2)', tension: 0.4, fill: true }]
    },
    options: getChartOptions()
  });

  updateChart('memPieChart', {
    type: 'doughnut',
    data: {
      labels: ['Utilisée', 'Disponible'],
      datasets: [{ data: [memUsedBytes, memAvailableBytes], backgroundColor: ['#ff6b35', '#4ec9b0'] }]
    },
    options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { labels: { color: '#d8d9da' } } } }
  });
}

function updateDisk(filtered, latest) {
    const disk = selectedDisk || { used_bytes: latest.disk_used_bytes || 0, total_bytes: latest.disk_total_bytes || 0, used_percent: latest.disk_percent || 0 };
    const used = disk.used_bytes;
    const total = disk.total_bytes;
    const free = total - used;
    
    document.getElementById('disk-used').textContent = formatBytes(used);
    document.getElementById('disk-percent').textContent = ((used / total) * 100).toFixed(1) + '%';
    document.getElementById('disk-total').textContent = formatBytes(total);
    document.getElementById('disk-free').textContent = formatBytes(free);
    document.getElementById('disk-status').textContent = ((used/total) > 0.9) ? 'Critique' : 'OK';
    document.getElementById('disk-info').textContent = `Volume: ${formatBytes(free)} libre.`;
    
    updateChart('diskPieChart', {
      type: 'doughnut',
      data: { labels: ['Utilisé', 'Libre'], datasets: [{ data: [used, free], backgroundColor: ['#ff6b35', '#4ec9b0'] }] },
      options: { responsive: true, maintainAspectRatio: false, plugins: { legend: { labels: { color: '#d8d9da' } } } }
    });

    updateChart('diskBarChart', {
        type: 'bar',
        data: {
            labels: ['Espace'],
            datasets: [ { label: 'Utilisé', data: [used], backgroundColor: '#ff6b35' }, { label: 'Libre', data: [free], backgroundColor: '#4ec9b0' } ]
        },
        options: { indexAxis: 'y', responsive: true, maintainAspectRatio: false, scales: { x: { stacked: true, ticks: { color: '#9fa0a4' }, grid: { color: '#2a2b2f' } }, y: { stacked: true, ticks: { color: '#9fa0a4' }, grid: { color: '#2a2b2f' } } }, plugins: { legend: { labels: { color: '#d8d9da' } } } }
    });
}

async function updateNetwork(filtered, latest) {
  const sent = latest.network_sent || 0;
  const recv = latest.network_recv || 0;
  document.getElementById('net-sent').textContent = formatBytes(sent);
  document.getElementById('net-recv').textContent = formatBytes(recv);
  
  const recent = filtered.slice(-10); 
  let upSpeed = 0, downSpeed = 0;
  if (recent.length >= 2) {
    const last = recent[recent.length - 1];
    const prev = recent[recent.length - 2]; // Comparaison avec N-1
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
  
  // Recalcul des vitesses pour tout l'historique
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
      datasets: [
        { label: 'Envoi', data: sentData, borderColor: '#ff6b35', backgroundColor: 'rgba(255, 107, 53, 0.1)', tension: 0.4, fill: true },
        { label: 'Réception', data: recvData, borderColor: '#4ec9b0', backgroundColor: 'rgba(78, 201, 176, 0.1)', tension: 0.4, fill: true }
      ]
    },
    options: getChartOptions()
  });
  
  // Interface Details
  try {
    const res = await fetch('/api/network');
    const interfaces = await res.json();
    const container = document.getElementById('network-interfaces');
    if (container && interfaces.length > 0) {
      let html = '<div class="stats-container">';
      interfaces.forEach(iface => {
        html += `<div class="stat-item"><span class="stat-label"><i class="fas fa-ethernet"></i> ${iface.interface}</span><span class="stat-value">↑ ${formatBytes(iface.bytes_sent)} / ↓ ${formatBytes(iface.bytes_recv)}</span></div>`;
      });
      html += '</div>';
      container.innerHTML = html;
    }
  } catch (err) {}
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
    const circumference = 2 * Math.PI * 90;
    const progress = Math.min(uptimeSeconds / (30 * 24 * 3600), 1);
    circle.style.strokeDasharray = circumference;
    circle.style.strokeDashoffset = circumference - progress * circumference;
  }
}

// --- NOUVELLES FONCTIONS (Scanner, Processus, Alertes) ---

async function scanNetwork() {
  const btn = document.getElementById('scan-network-btn');
  const status = document.getElementById('scan-status');
  const container = document.getElementById('network-devices-container');
  
  btn.disabled = true;
  btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Scanning...';
  status.textContent = 'Scanning network...';
  
  try {
    const res = await fetch('/api/network/scan');
    const data = await res.json();
    
    if (data.devices && data.devices.length > 0) {
      let html = '<table class="styled-table"><thead><tr><th>Status</th><th>IP Address</th><th>Hostname</th><th>MAC</th><th>Vendor</th></tr></thead><tbody>';
      data.devices.forEach(dev => {
        const isLocal = dev.is_local ? ' (This Mac)' : '';
        html += `<tr>
            <td><span class="status-badge up">Online</span></td>
            <td style="color:#4ec9b0; font-family:monospace;">${dev.ip}</td>
            <td>${dev.hostname || '--'}${isLocal}</td>
            <td style="font-family:monospace;">${dev.mac || '--'}</td>
            <td>${dev.vendor || '--'}</td>
        </tr>`;
      });
      html += '</tbody></table>';
      container.innerHTML = html;
      status.textContent = `Found ${data.devices.length} devices.`;
    } else {
        container.innerHTML = '<div class="empty-state"><p>No devices found.</p></div>';
        status.textContent = 'Scan finished.';
    }
  } catch (err) { status.textContent = 'Error during scan.'; }
  btn.disabled = false; btn.innerHTML = '<i class="fas fa-search"></i> Scan Network';
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
    
    if (data.processes && data.processes.length > 0) {
      let html = '<table class="styled-table"><thead><tr><th>PID</th><th>User</th><th>CPU</th><th>MEM</th><th>Command</th><th>Action</th></tr></thead><tbody>';
      data.processes.forEach(proc => {
        const cpuClass = proc.cpu > 50 ? 'high' : (proc.cpu > 20 ? 'medium' : 'low');
        html += `<tr>
            <td style="color:#9fa0a4;">${proc.pid}</td>
            <td>${proc.user}</td>
            <td><span class="metric-badge ${cpuClass}">${proc.cpu.toFixed(1)}%</span></td>
            <td><span class="metric-badge low">${proc.mem.toFixed(1)}%</span></td>
            <td style="font-family:monospace; max-width:200px; overflow:hidden; white-space:nowrap; text-overflow:ellipsis;">${proc.command}</td>
            <td><button class="btn-kill" onclick="killProcess(${proc.pid})"><i class="fas fa-times"></i></button></td>
        </tr>`;
      });
      html += '</tbody></table>';
      container.innerHTML = html;
      document.getElementById('process-count').textContent = `Top 20 by ${currentSort.toUpperCase()}`;
    }
  } catch (err) { console.error(err); }
}

async function killProcess(pid) {
    if(!confirm(`Terminate process ${pid}?`)) return;
    await fetch(`/api/processes/${pid}/kill`, { method: 'POST' });
    fetchProcesses();
}

async function fetchAlerts() {
  try {
    const res = await fetch('/api/alerts');
    const data = await res.json();
    const container = document.getElementById('alerts-container');
    
    document.getElementById('alert-count').textContent = data.alerts.length;
    document.getElementById('system-status').textContent = data.alerts.length > 0 ? 'Warning' : 'OK';
    document.getElementById('last-check').textContent = new Date().toLocaleTimeString();

    if (data.alerts.length > 0) {
      let html = '<div class="alerts-list">';
      data.alerts.forEach(alert => {
        const type = alert.type === 'critical' ? 'critical' : 'warning';
        const icon = alert.type === 'critical' ? 'radiation' : 'exclamation-triangle';
        html += `<div class="alert-item ${type}">
            <div class="alert-icon"><i class="fas fa-${icon}"></i></div>
            <div class="alert-content">
                <strong>${alert.category.toUpperCase()} ALERT</strong>
                <p>${alert.message}</p>
                <div class="alert-time"><i class="far fa-clock"></i> ${new Date(alert.timestamp * 1000).toLocaleTimeString()}</div>
            </div>
        </div>`;
      });
      html += '</div>';
      container.innerHTML = html;
    } else {
        container.innerHTML = `<div class="empty-state"><i class="fas fa-check-circle" style="color:#4ec9b0;"></i><p>System healthy.</p></div>`;
    }
  } catch (err) { console.error(err); }
}

// --- Chart.js & Settings (Original) ---

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
    responsive: true, maintainAspectRatio: false,
    plugins: { legend: { labels: { color: '#d8d9da', font: { size: 12 } } } },
    scales: {
      x: { ticks: { color: '#9fa0a4', maxRotation: 45, minRotation: 45 }, grid: { color: '#2a2b2f' } },
      y: { ticks: { color: '#9fa0a4' }, grid: { color: '#2a2b2f' }, beginAtZero: true, ...extra }
    }
  };
}

// Settings Logic (Simplifié pour tenir ici, mais fonctionnel)
function updateSettingsPage() {
    initPrefs();
    // Re-fill disk select logic similar to original...
    fetchDisks().then(devices => {
        const sel = document.getElementById('settings-disk-select');
        if(!sel) return;
        sel.innerHTML = '';
        const def = document.createElement('option');
        def.text = "Primary OS Disk"; def.value = "default";
        sel.add(def);
        devices.forEach(d => {
            const opt = document.createElement('option');
            opt.text = `${d.mountpoint} (${formatBytes(d.total_bytes)})`;
            opt.value = JSON.stringify(d);
            sel.add(opt);
        });
    });
}

document.getElementById('save-settings')?.addEventListener('click', () => {
    localStorage.setItem('unitPref', document.querySelector('input[name="unit-pref"]:checked').value);
    const sel = document.getElementById('settings-disk-select');
    if(sel.value !== 'default') localStorage.setItem('selectedDisk', sel.value);
    else localStorage.removeItem('selectedDisk');
    localStorage.setItem('refreshRate', document.getElementById('settings-refresh-rate').value);
    
    initPrefs(); 
    clearInterval(intervalID);
    intervalID = setInterval(fetchData, parseInt(localStorage.getItem('refreshRate')));
    fetchData();
    alert('Settings Saved');
});

document.getElementById('export-json').addEventListener('click', () => { window.location.href = '/api/system'; });

// --- Start ---
initPrefs();
initNav();
switchPage('dashboard');
const rate = parseInt(localStorage.getItem('refreshRate') || '5000');
intervalID = setInterval(() => {
    if(['dashboard','cpu','memory','disk','network','uptime'].includes(currentPage)) fetchData();
    if(currentPage === 'processes') fetchProcesses();
    if(currentPage === 'alerts') fetchAlerts();
}, rate);
fetchData();


// Fonction pour récupérer et afficher les alertes
async function updateAlerts() {
    try {
        const response = await fetch('/api/alerts');
        const data = await response.json();
        
        const container = document.getElementById('alerts-container');
        const countBadge = document.getElementById('alert-count');
        const lastCheck = document.getElementById('last-check');
        
        // Mettre à jour le compteur global
        const alertCount = data.alerts ? data.alerts.length : 0;
        if(countBadge) countBadge.textContent = alertCount;
        
        // Mettre à jour l'heure du check
        const now = new Date();
        if(lastCheck) lastCheck.textContent = now.toLocaleTimeString();

        // Si aucune alerte
        if (!data.alerts || data.alerts.length === 0) {
            container.innerHTML = `
                <div class="empty-state">
                    <i class="fas fa-check-circle" style="color: #4ec9b0;"></i>
                    <p>Tout est calme. Aucune alerte.</p>
                </div>`;
            return;
        }

        // Si on a des alertes, on vide le conteneur et on remplit
        container.innerHTML = '';
        
        data.alerts.forEach(alert => {
            // Déterminer l'icône selon la catégorie
            let iconClass = 'fa-info-circle';
            if (alert.category === 'network') iconClass = 'fa-network-wired';
            if (alert.category === 'cpu') iconClass = 'fa-microchip';
            if (alert.category === 'disk') iconClass = 'fa-hdd';

            // Formater l'heure (Ruby envoie des secondes, JS veut des millisecondes)
            const timeDate = new Date(alert.timestamp * 1000);
            const timeString = timeDate.toLocaleTimeString();

            // Créer le HTML de la carte
            const alertCard = document.createElement('div');
            alertCard.className = `alert-card alert-type-${alert.type}`;
            
            alertCard.innerHTML = `
                <div class="alert-icon-wrapper">
                    <i class="fas ${iconClass}"></i>
                </div>
                <div class="alert-content-wrapper">
                    <div class="alert-title">${alert.category} Alert</div>
                    <div class="alert-message">${alert.message}</div>
                </div>
                <div class="alert-time">${timeString}</div>
            `;
            
            container.appendChild(alertCard);
        });

    } catch (error) {
        console.error("Erreur lors de la récupération des alertes:", error);
    }
}

// Lancer la mise à jour des alertes toutes les 2 secondes
setInterval(updateAlerts, 2000);

// Lancer une fois au démarrage
document.addEventListener('DOMContentLoaded', () => {
    updateAlerts();
});

async function autoUpdateNetworkTable() {
    try {
        const response = await fetch('/api/network/latest');
        const data = await response.json();

        // Si la liste est vide, on ne fait rien
        if (!data.devices || data.devices.length === 0) return;

        const container = document.getElementById('network-devices-container');
        
        // --- CHANGEMENT ICI : Utilisation de la classe "styled-table" du CSS ---
        let html = `
        <table class="styled-table">
            <thead>
                <tr>
                    <th>Status</th>
                    <th>IP Address</th>
                    <th>Hostname</th>
                    <th>MAC</th>
                    <th>Vendor</th>
                </tr>
            </thead>
            <tbody>
        `;

        data.devices.forEach(device => {
            // Style pour "(This Mac)" en orange comme le thème
            const isLocal = device.is_local ? ' <span style="color: #ff6b35; font-size: 0.9em; font-weight: bold;">(This Mac)</span>' : '';
            
            // Utilisation du badge CSS "status-badge up" (Vert avec le point lumineux)
            // Note : Le CSS gère le point vert automatiquement via ::before
            const statusHtml = device.status === 'up' 
                ? '<span class="status-badge up">Online</span>' 
                : '<span class="status-badge" style="color:#f44336; background:rgba(244,67,54,0.15)">Offline</span>';
            
            html += `
                <tr>
                    <td>${statusHtml}</td>
                    <td>${device.ip}</td>
                    <td><strong>${device.hostname}</strong>${isLocal}</td>
                    <td style="font-family: monospace; opacity: 0.8;">${device.mac}</td>
                    <td style="color: #9fa0a4;">${device.vendor}</td>
                </tr>
            `;
        });

        html += '</tbody></table>';
        
        container.innerHTML = html;
        
        // Mise à jour du timestamp
        const statusSpan = document.getElementById('scan-status');
        if(statusSpan) {
            const date = new Date(data.timestamp * 1000);
            statusSpan.textContent = "Last auto-scan: " + date.toLocaleTimeString();
        }

    } catch (error) {
        console.error("Erreur auto-update network:", error);
    }
}

// Lancer la vérification toutes les 10 secondes
// (Le serveur scanne toutes les 60s, inutile de rafraîchir chaque seconde)
setInterval(autoUpdateNetworkTable, 10000);

// Lancer une fois au chargement de la page
document.addEventListener('DOMContentLoaded', autoUpdateNetworkTable);