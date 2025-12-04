/**
 * Fichier : app.js
 * Description : Logique front-end pour le tableau de bord de surveillance système.
 * Gère la navigation, la récupération des données, les graphiques Chart.js et les préférences utilisateur (Unités, Disques, Taux de rafraîchissement).
 */

let charts = {};
let currentPage = 'dashboard';
let intervalID;
let selectedDisk = null; // Stocke l'objet disque sélectionné (depuis les paramètres)
let unitPref = 'binary'; // 'binary' (1024) ou 'decimal' (1000)

// --- Utilitaires ---

/**
 * Formate une taille de fichier en une chaîne lisible (ex: 5.23 GiB).
 * Utilise la préférence d'unité de l'utilisateur (binaire ou décimale).
 */
function formatBytes(bytes) {
  if (bytes === 0 || bytes === null || bytes === undefined) return '0 B';
  
  // k est 1024 pour binaire (défaut) ou 1000 pour décimal
  const k = unitPref === 'decimal' ? 1000 : 1024;
  
  const binarySizes = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  const decimalSizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const sizes = unitPref === 'decimal' ? decimalSizes : binarySizes;
  
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  // Assure que l'indice ne dépasse pas la taille maximale du tableau
  const index = Math.min(i, sizes.length - 1); 
  return (bytes / Math.pow(k, index)).toFixed(2) + ' ' + sizes[index];
}

/**
 * Formate une durée en secondes en une chaîne lisible (ex: 2d 5h 30m).
 */
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

// --- Préférences et Initialisation ---

/**
 * Charge les préférences utilisateur depuis le stockage local.
 */
function initPrefs() {
    try {
        unitPref = localStorage.getItem('unitPref') || 'binary';
        const storedDisk = localStorage.getItem('selectedDisk');
        if (storedDisk && storedDisk !== 'null') {
            selectedDisk = JSON.parse(storedDisk);
        }
    } catch (e) {
        console.error("Erreur de chargement des préférences:", e);
    }
}

/**
 * Initialise les écouteurs d'événements pour la navigation latérale.
 */
function initNav() {
  document.querySelectorAll('.menu-item').forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const page = item.getAttribute('data-page');
      if (page) switchPage(page);
    });
  });
}

/**
 * Change la page active du tableau de bord.
 */
function switchPage(page) {
  currentPage = page;
  
  // Met à jour l'élément de menu actif
  document.querySelectorAll('.menu-item').forEach(i => i.classList.remove('active'));
  const active = document.querySelector(`[data-page="${page}"]`);
  if (active) active.classList.add('active');
  
  // Met à jour le titre de la page
  const titles = {
    'dashboard': 'System Monitor Dashboard',
    'cpu': 'CPU Analysis',
    'memory': 'Memory Analysis',
    'disk': 'Disk Analysis',
    'network': 'Network Analysis',
    'uptime': 'System Uptime',
    'settings': 'Application Settings'
  };
  
  document.getElementById('page-title').textContent = titles[page] || 'Monitor';
  
  // Affiche la bonne page
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  const activePage = document.getElementById(`${page}-page`);
  if (activePage) activePage.classList.add('active');
  
  // Initialisation spécifique à la page
  if (page === 'settings') {
    updateSettingsPage();
  } else {
    // Si on est sur les pages Disk ou Network, on peut avoir besoin de fetchDisks() ou des interfaces réseau
    if (page === 'disk' || page === 'network') {
        fetchDisks(); // Pour le dashboard Disk
    }
    fetchData(); 
  }
}

// --- Récupération des Données ---

/**
 * Récupère l'historique des métriques système et met à jour la page active.
 */
async function fetchData() {
  try {
    const res = await fetch('/api/system');
    if (!res.ok) throw new Error('Échec de la récupération des données système');
    const data = await res.json();
    
    const minutes = parseInt(document.getElementById('interval').value);
    const cutoff = Date.now() / 1000 - minutes * 60;
    
    // Filtre les données selon la plage de temps sélectionnée
    const filtered = data.filter(d => d.timestamp >= cutoff);
    
    if (filtered.length === 0) return;
    
    const latest = filtered[filtered.length - 1];
    
    // Met à jour la page active
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
    console.error('Erreur de récupération des données:', err);
  }
}

/**
 * Récupère la liste de tous les disques/partitions pour les paramètres.
 */
async function fetchDisks() {
    try {
        const res = await fetch('/api/disks');
        if (!res.ok) throw new Error('Échec de la récupération des disques');
        return await res.json();
    } catch (err) {
        console.error('Erreur de récupération des disques:', err);
        return [];
    }
}

// --- Mise à Jour des Pages ---

function updateDashboard(filtered, latest) {
  const k = unitPref === 'decimal' ? 1e9 : 1024**3;
  const unit = unitPref === 'decimal' ? 'GB' : 'GiB';

  // Infos Système
  document.getElementById('sys-hostname').textContent = latest.hostname || 'Inconnu';
  document.getElementById('sys-platform').textContent = latest.platform ? `${latest.platform} ${latest.os || ''}` : 'Inconnu';
  document.getElementById('sys-cores').textContent = latest.cpu_cores ? `${latest.cpu_cores} cœurs` : 'Inconnu';
  
  // Métriques
  document.getElementById('cpu').textContent = (latest.cpu_usage || 0).toFixed(1) + '%';
  document.getElementById('memory').textContent = `${formatBytes(latest.memory_used_bytes)} / ${formatBytes(latest.memory_total_bytes)}`;
  
  // Disque : Utilise le disque sélectionné si défini, sinon les données par défaut
  const diskData = selectedDisk || {
      used_bytes: latest.disk_used_bytes,
      total_bytes: latest.disk_total_bytes,
  };
  
  document.getElementById('disk').textContent = `${formatBytes(diskData.used_bytes)} / ${formatBytes(diskData.total_bytes)}`;
  document.getElementById('uptime').textContent = formatDuration(latest.uptime_seconds);
  
  // Graphiques
  const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());
  const cpuData = filtered.map(d => d.cpu_usage || 0);
  // Utilise les bytes pour le graphique de mémoire et divise par k pour GB/GiB
  const memData = filtered.map(d => (d.memory_used_bytes || 0) / k); 
  
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
        label: `Mémoire ${unit}`,
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
        label: 'Utilisation CPU %',
        data: cpuValues,
        borderColor: '#ff6b35',
        backgroundColor: 'rgba(255, 107, 53, 0.2)',
        tension: 0.4,
        fill: true
      }]
    },
    options: getChartOptions({ max: 100 })
  });

  // Calculs pour les statistiques
  const totalPoints = cpuValues.length;
  const high = cpuValues.filter(v => v > 80).length;
  const medium = cpuValues.filter(v => v >= 50 && v <= 80).length;
  const low = cpuValues.filter(v => v < 50).length;

  const highPercent = (high / totalPoints * 100).toFixed(1);
  const mediumPercent = (medium / totalPoints * 100).toFixed(1);
  const lowPercent = (low / totalPoints * 100).toFixed(1);

  document.getElementById('cpu-high').textContent = highPercent + '%';
  document.getElementById('cpu-medium').textContent = mediumPercent + '%';
  document.getElementById('cpu-low').textContent = lowPercent + '%';
  
  // Distribution doughnut chart
  updateChart('cpuDistChart', {
    type: 'doughnut',
    data: {
      labels: ['High (>80%)', 'Medium (50-80%)', 'Low (<50%)'],
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
            color: '#d8d9da',
            font: { size: 12 },
            padding: 15
          },
          position: 'bottom'
        }
      }
    }
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
  // Conversion inverse pour les max/avg car memValues est en GB/GiB
  document.getElementById('mem-max').textContent = formatBytes(Math.max(...memValues.map(v => v * k))); 
  document.getElementById('mem-avg').textContent = avg.toFixed(2) + ' ' + unit;
  
  // Laisser '0 MB/min' et 'Never' comme placeholders simples pour l'instant
  document.getElementById('mem-growth').textContent = '0 MB/min';
  document.getElementById('mem-estimate').textContent = 'Never';

  const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());
  
  updateChart('memDetailChart', {
    type: 'line',
    data: {
      labels,
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

  // Memory pie chart
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
        legend: { labels: { color: '#d8d9da' } }
      }
    }
  });
}

function updateDisk(filtered, latest) {
    // Utilise le disque sélectionné si défini, sinon les données par défaut
    const disk = selectedDisk || {
        mountpoint: '/',
        used_bytes: latest.disk_used_bytes || 0,
        total_bytes: latest.disk_total_bytes || 0,
        used_percent: latest.disk_percent || 0
    };
    
    const used = disk.used_bytes;
    const total = disk.total_bytes;
    const free = total - used;
    const percent = total > 0 ? ((used / total) * 100).toFixed(1) : 0;
    
    document.getElementById('disk-used').textContent = formatBytes(used);
    document.getElementById('disk-percent').textContent = percent + '%';
    document.getElementById('disk-total').textContent = formatBytes(total);
    document.getElementById('disk-free').textContent = formatBytes(free);
    
    let status = 'OK';
    if (percent > 90) status = 'Critique';
    else if (percent > 80) status = 'Avertissement';
    document.getElementById('disk-status').textContent = status;
    
    const info = percent > 80 
      ? `⚠️ Le disque monté sur ${disk.mountpoint || 'disque principal'} est plein à ${percent}%. Libérez de l'espace.`
      : `✓ Le disque monté sur ${disk.mountpoint || 'disque principal'} dispose de ${formatBytes(free)} d'espace libre.`;
    document.getElementById('disk-info').textContent = info;
    
    // Graphique en anneau (Pie)
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
          legend: { labels: { color: '#d8d9da' } }
        }
      }
    });

    // Graphique à barres (Stacked bar)
    updateChart('diskBarChart', {
        type: 'bar',
        data: {
            labels: ['Espace Disque'],
            datasets: [
                {
                    label: 'Utilisé',
                    data: [used],
                    backgroundColor: '#ff6b35',
                },
                {
                    label: 'Libre',
                    data: [free],
                    backgroundColor: '#4ec9b0',
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { labels: { color: '#d8d9da' } },
                tooltip: { mode: 'index', intersect: false }
            },
            scales: {
                x: {
                    stacked: true,
                    ticks: { color: '#9fa0a4' },
                    grid: { color: '#2a2b2f' }
                },
                y: {
                    stacked: true,
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
  
  // Calculer les vitesses sur les 10 dernières secondes (environ)
  const recent = filtered.slice(-10); 
  let upSpeed = 0;
  let downSpeed = 0;

  if (recent.length >= 2) {
    const first = recent[0];
    const last = recent[recent.length - 1];
    const timeDiff = last.timestamp - first.timestamp;
    
    if (timeDiff > 0) {
      upSpeed = Math.max(0, (last.network_sent - first.network_sent) / timeDiff);
      downSpeed = Math.max(0, (last.network_recv - first.network_recv) / timeDiff);
    }
  }

  document.getElementById('net-up-speed').textContent = formatBytes(upSpeed) + '/s';
  document.getElementById('net-down-speed').textContent = formatBytes(downSpeed) + '/s';
  
  // Données du graphique (conversion en KB/s ou KiB/s)
  const k = unitPref === 'decimal' ? 1000 : 1024;
  const unitLabel = unitPref === 'decimal' ? 'KB/s' : 'KiB/s';

  const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());
  
  const sentData = filtered.map((d, i) => {
    if (i === 0) return 0;
    const prev = filtered[i - 1];
    const diff = d.network_sent - prev.network_sent;
    const time = d.timestamp - prev.timestamp;
    // (octets / seconde) / k = KB/s ou KiB/s
    return time > 0 ? (diff / time) / k : 0; 
  });
  
  const recvData = filtered.map((d, i) => {
    if (i === 0) return 0;
    const prev = filtered[i - 1];
    const diff = d.network_recv - prev.network_recv;
    const time = d.timestamp - prev.timestamp;
    return time > 0 ? (diff / time) / k : 0;
  });
  
  updateChart('networkChart', {
    type: 'line',
    data: {
      labels,
      datasets: [
        {
          label: `Envoi (${unitLabel})`,
          data: sentData,
          borderColor: '#ff6b35',
          backgroundColor: 'rgba(255, 107, 53, 0.1)',
          tension: 0.4,
          fill: true
        },
        {
          label: `Réception (${unitLabel})`,
          data: recvData,
          borderColor: '#4ec9b0',
          backgroundColor: 'rgba(78, 201, 176, 0.1)',
          tension: 0.4,
          fill: true
        }
      ]
    },
    options: getChartOptions({ suggestedMax: Math.max(...sentData, ...recvData) * 1.2 || 100 })
  });
  
  // Récupérer et afficher les détails des interfaces
  try {
    const res = await fetch('/api/network');
    if (!res.ok) throw new Error('Échec de l\'API réseau');
    const interfaces = await res.json();
    const container = document.getElementById('network-interfaces');
    
    if (!container) return;
    
    if (interfaces && interfaces.length > 0) {
      let html = '<div class="stats-container">';
      interfaces.forEach(iface => {
        html += `
          <div class="stat-item">
            <span class="stat-label"><i class="fas fa-ethernet"></i> ${iface.interface}</span>
            <span class="stat-value">↑ ${formatBytes(iface.bytes_sent)} / ↓ ${formatBytes(iface.bytes_recv)}</span>
          </div>
        `;
      });
      html += '</div>';
      container.innerHTML = html;
    } else {
      container.innerHTML = '<p style="padding: 20px; color: #9fa0a4;">Aucune interface réseau active trouvée.</p>';
    }
  } catch (err) {
    console.error('Erreur interfaces réseau:', err);
    const container = document.getElementById('network-interfaces');
    if (container) {
      container.innerHTML = '<p style="padding: 20px; color: #ff6b35;">⚠️ Impossible de charger les interfaces réseau. Le backend a-t-il les droits suffisants ?</p>';
    }
  }
}

function updateUptime(filtered, latest) {
  const uptimeSeconds = latest.uptime_seconds || 0;
  const uptimeStr = formatDuration(uptimeSeconds);
  document.getElementById('uptime-current').textContent = uptimeStr;
  
  // Calculs pour les métriques
  const days = Math.floor(uptimeSeconds / (3600 * 24));
  const hours = Math.floor((uptimeSeconds % (3600 * 24)) / 3600);
  const minutes = Math.floor((uptimeSeconds % 3600) / 60);

  document.getElementById('uptime-days').textContent = days;
  document.getElementById('uptime-hours').textContent = hours;
  document.getElementById('uptime-minutes').textContent = minutes;
  
  // Fiabilité (placeholder)
  const reliability = 99.9; 
  document.getElementById('uptime-reliability').textContent = reliability.toFixed(1) + '%';
  
  const circle = document.getElementById('uptime-circle');
  if (circle) {
    const circumference = 2 * Math.PI * 90;
    // La progression est arbitraire ici, mais on l'utilise pour animer
    const progress = Math.min(uptimeSeconds / (30 * 24 * 3600), 1); // Progression sur 30 jours
    const offset = circumference - progress * circumference;
    circle.style.strokeDasharray = circumference;
    circle.style.strokeDashoffset = offset;
    circle.style.stroke = progress > 0.9 ? '#4ec9b0' : '#ff6b35';
  }
  
  const message = days > 30 
    ? "Votre système est en ligne depuis plus d'un mois. Pensez à redémarrer occasionnellement."
    : "Votre système fonctionne sans interruption. Tout est en ordre.";
  document.getElementById('uptime-message').textContent = message;
  document.querySelector('#uptime-page .alert-box').classList.toggle('success', days < 30);
}

// --- Paramètres (Settings) ---

async function updateSettingsPage() {
    // 1. Initialiser les préférences d'unité
    try {
        const p = localStorage.getItem('unitPref') || 'binary';
        const radios = document.getElementsByName('unit-pref');
        for (const r of radios) { r.checked = (r.value === p); }
    } catch (e) {}

    // 2. Remplir le sélecteur de disque
    try {
        const devices = await fetchDisks();
        const sel = document.getElementById('settings-disk-select');
        sel.innerHTML = '';
        
        // Ajouter une option pour le disque principal par défaut
        const defaultOpt = document.createElement('option');
        defaultOpt.value = 'default';
        defaultOpt.textContent = `(Default) Primary OS Disk`;
        sel.appendChild(defaultOpt);

        devices.forEach((d, idx) => {
            const opt = document.createElement('option');
            const name = d.device || d.mountpoint || `disk-${idx}`;
            // IMPORTANT : Utilise formatBytes() avec la préférence ACTUELLE.
            const totalLabel = d.total_bytes ? formatBytes(d.total_bytes) : 'inconnu'; 
            opt.value = JSON.stringify(d); // Stocke l'objet complet dans la valeur
            opt.textContent = `${name} — ${d.mountpoint || '/'} — ${totalLabel}`;
            sel.appendChild(opt);
        });

        // Pré-sélectionner le disque précédemment choisi
        try {
            const stored = localStorage.getItem('selectedDisk');
            if (stored && stored !== 'null') {
                const sd = JSON.parse(stored);
                let found = false;
                for (let i = 0; i < sel.options.length; i++) {
                    const optionValue = sel.options[i].value;
                    if (optionValue !== 'default') {
                        const o = JSON.parse(optionValue);
                        if ((sd.mountpoint && o.mountpoint === sd.mountpoint) || (sd.device && o.device === sd.device)) {
                            sel.selectedIndex = i; 
                            found = true;
                            break;
                        }
                    }
                }
                if (!found) sel.selectedIndex = 0;
            } else {
                sel.selectedIndex = 0; // Sélectionne 'default'
            }
        } catch (e) {}

        // 3. Initialiser le taux de rafraîchissement
        const refreshSelect = document.getElementById('settings-refresh-rate');
        const storedRate = localStorage.getItem('refreshRate') || '5000';
        refreshSelect.value = storedRate;
        
        const info = document.getElementById('settings-info');
        if (info) info.innerHTML = '<i class="fas fa-save"></i> Les préférences sont stockées localement dans votre navigateur.';


        // 4. Gestion de la sauvegarde
        const saveBtn = document.getElementById('save-settings');
        // IMPORTANT : S'assurer que l'écouteur est bien défini ici pour que les boutons fonctionnent.
        if (saveBtn) saveBtn.onclick = () => {
            const radios = document.getElementsByName('unit-pref');
            let chosenUnit = 'binary';
            for (const r of radios) if (r.checked) chosenUnit = r.value;
            
            const selOpt = sel.options[sel.selectedIndex];
            let chosenDisk = null;

            if (selOpt && selOpt.value !== 'default') {
                chosenDisk = JSON.parse(selOpt.value);
            }
            
            const chosenRate = refreshSelect.value;
            
            try { 
                localStorage.setItem('unitPref', chosenUnit); 
                localStorage.setItem('selectedDisk', JSON.stringify(chosenDisk)); 
                localStorage.setItem('refreshRate', chosenRate); 
                
                // Mettre à jour les variables globales et l'intervalle
                unitPref = chosenUnit;
                selectedDisk = chosenDisk;
                clearInterval(intervalID);
                intervalID = setInterval(fetchData, parseInt(chosenRate));

            } catch (e) {}
            
            if (info) info.innerHTML = '<i class="fas fa-check-circle"></i> Paramètres sauvegardés.';
            
            // Re-fetch data pour appliquer immédiatement les nouveaux paramètres
            fetchData();
        };

        // 5. Gestion de la réinitialisation
        const resetBtn = document.getElementById('reset-settings');
        if (resetBtn) resetBtn.onclick = () => {
            try { 
                localStorage.removeItem('unitPref'); 
                localStorage.removeItem('selectedDisk'); 
                localStorage.removeItem('refreshRate');
            } catch (e) {}
            
            if (info) info.innerHTML = '<i class="fas fa-redo"></i> Paramètres réinitialisés aux valeurs par défaut.';
            
            // Réinitialiser les contrôles visuels et les variables
            const radios = document.getElementsByName('unit-pref');
            for (const r of radios) r.checked = (r.value === 'binary');
            unitPref = 'binary';

            if(sel.options.length > 0) sel.selectedIndex = 0;
            selectedDisk = null;

            refreshSelect.value = '5000';
            
            // Réinitialiser l'intervalle de rafraîchissement
            clearInterval(intervalID);
            intervalID = setInterval(fetchData, 5000);

            fetchData();
        };

    } catch (err) {
        console.error('Erreur lors de la récupération des disques pour les paramètres:', err);
        const info = document.getElementById('settings-info');
        if (info) info.innerHTML = '<i class="fas fa-exclamation-triangle"></i> Impossible de charger les disques pour les paramètres.';
    }
}

// --- Gestion des Graphiques Chart.js ---

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

// --- Exportation des Données ---

async function exportJSON() {
  try {
    const res = await fetch('/api/system');
    const data = await res.json();
    
    const minutes = parseInt(document.getElementById('interval').value);
    const cutoff = Date.now() / 1000 - minutes * 60;
    const filtered = data.filter(d => d.timestamp >= cutoff);
    
    if (filtered.length === 0) {
      alert('Aucune donnée à exporter');
      return;
    }
    
    const latest = filtered[filtered.length - 1];
    
    const exportData = {
      metadata: {
        exported_at: new Date().toISOString(),
        hostname: latest.hostname || 'Inconnu',
        platform: latest.platform || 'Inconnu',
        time_range_minutes: minutes,
        data_points: filtered.length,
        disk_in_dashboard: selectedDisk ? (selectedDisk.mountpoint || selectedDisk.device) : 'Primary OS Disk'
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
    btn.innerHTML = '<i class="fas fa-check"></i> Exporté!';
    btn.style.backgroundColor = '#5cb85c';
    setTimeout(() => {
      btn.innerHTML = orig;
      btn.style.backgroundColor = '';
    }, 2000);
  } catch (err) {
    console.error('Erreur d\'exportation:', err);
    alert('Échec de l\'exportation: ' + err.message);
  }
}

// --- Écouteurs d'Événements Globaux ---

document.getElementById('interval').addEventListener('change', fetchData);
document.getElementById('refresh').addEventListener('click', () => {
  const btn = document.getElementById('refresh');
  btn.style.transform = 'rotate(360deg)';
  setTimeout(() => btn.style.transform = '', 300);
  fetchData();
});
document.getElementById('export-json').addEventListener('click', exportJSON);


// --- Démarrage de l'Application ---

initPrefs();
initNav();
switchPage('dashboard');

// Définir l'intervalle de rafraîchissement initial
const rate = parseInt(localStorage.getItem('refreshRate') || '5000');
intervalID = setInterval(fetchData, rate);
fetchData();