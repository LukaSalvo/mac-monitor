let cpuChart, memoryChart;
let cpuDetailChart, cpuDistChart;
let memDetailChart, memPieChart;
let diskPieChart, diskBarChart;
let currentPage = 'dashboard';

// Navigation
function initNavigation() {
  const menuItems = document.querySelectorAll('.menu-item[data-page]');
  
  menuItems.forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const page = item.getAttribute('data-page');
      switchPage(page);
    });
  });
}

// Format bytes into human-friendly strings using binary units (KiB, MiB, GiB, TiB)
function formatBytes(bytes) {
  if (bytes === undefined || bytes === null) return '0 B';
  const b = Number(bytes);
  if (isNaN(b)) return '0 B';
  // Respect user's unit preference (stored in localStorage 'unitPref'):
  // 'binary' => 1024-based (KiB, MiB...), 'decimal' => 1000-based (KB, MB...)
  let pref = 'binary';
  try { const p = localStorage.getItem('unitPref'); if (p) pref = p; } catch (e) {}
  const thresh = pref === 'decimal' ? 1000 : 1024;
  if (b < thresh) return b + ' B';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  let u = -1;
  let value = b;
  do {
    value = value / thresh;
    u++;
  } while (value >= thresh && u < units.length - 1);
  // show one decimal for >10 units, else 0 decimals when integer
  const decimals = value < 10 ? 1 : 0;
  return value.toFixed(decimals) + ' ' + units[u];
}

function getSelectedDiskFromStorage() {
  try {
    const raw = localStorage.getItem('selectedDisk');
    if (!raw) return null;
    return JSON.parse(raw);
  } catch (e) {
    return null;
  }
}

// Settings page: populate controls and save/reset preferences
async function updateSettingsPage() {
  // set radio based on stored preference
  try {
    const p = localStorage.getItem('unitPref') || 'binary';
    const radios = document.getElementsByName('unit-pref');
    for (const r of radios) { r.checked = (r.value === p); }
  } catch (e) {}

  // populate disk select in settings
  try {
    const res = await fetch('/api/disks');
    const devices = await res.json();
    const sel = document.getElementById('settings-disk-select');
    sel.innerHTML = '';
    devices.forEach((d, idx) => {
      const opt = document.createElement('option');
      const name = d.device || d.mountpoint || `disk-${idx}`;
      const totalLabel = d.total_bytes ? formatBytes(d.total_bytes) : 'unknown';
      opt.value = idx;
      opt.textContent = `${name} — ${d.mountpoint || '/'} — ${totalLabel}`;
      opt.dataset.device = JSON.stringify(d);
      sel.appendChild(opt);
    });

    // try to preselect previously chosen disk
    try {
      const stored = localStorage.getItem('selectedDisk');
      if (stored) {
        const sd = JSON.parse(stored);
        for (let i = 0; i < sel.options.length; i++) {
          const o = JSON.parse(sel.options[i].dataset.device);
          if ((sd.mountpoint && o.mountpoint === sd.mountpoint) || (sd.device && o.device === sd.device) || (sd.total_bytes && o.total_bytes === sd.total_bytes)) {
            sel.selectedIndex = i; break;
          }
        }
      }
    } catch (e) {}

    // Save settings
    const saveBtn = document.getElementById('save-settings');
    if (saveBtn) saveBtn.onclick = () => {
      const radios = document.getElementsByName('unit-pref');
      let chosen = 'binary';
      for (const r of radios) if (r.checked) chosen = r.value;
      try { localStorage.setItem('unitPref', chosen); } catch (e) {}

      const selOpt = sel.options[sel.selectedIndex];
      if (selOpt) {
        const dev = JSON.parse(selOpt.dataset.device);
        try { localStorage.setItem('selectedDisk', JSON.stringify(dev)); } catch (e) {}
      }
      const info = document.getElementById('settings-info');
      if (info) info.innerText = 'Settings saved.';
      fetchSystem();
    };

    const resetBtn = document.getElementById('reset-settings');
    if (resetBtn) resetBtn.onclick = () => {
      try { localStorage.removeItem('unitPref'); localStorage.removeItem('selectedDisk'); } catch (e) {}
      const info = document.getElementById('settings-info');
      if (info) info.innerText = 'Settings reset to defaults.';
      // reset radios
      const radios = document.getElementsByName('unit-pref');
      for (const r of radios) r.checked = (r.value === 'binary');
      fetchSystem();
    };

  } catch (err) {
    console.error('Error fetching disks for settings:', err);
    const info = document.getElementById('settings-info');
    if (info) info.innerText = 'Could not load disks.';
  }
}

function switchPage(page) {
  currentPage = page;
  
  // Update active menu item
  document.querySelectorAll('.menu-item[data-page]').forEach(item => {
    item.classList.remove('active');
  });
  document.querySelector(`[data-page="${page}"]`).classList.add('active');
  
  // Update page title
  const titles = {
    'dashboard': 'System Monitor Dashboard',
    'cpu': 'CPU Analysis',
    'memory': 'Memory Analysis',
    'disk': 'Disk Analysis',
    'uptime': 'System Uptime'
  };
  document.getElementById('page-title').textContent = titles[page];
  
  // Switch pages
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.getElementById(`${page}-page`).classList.add('active');
  
  // Fetch data for the new page
  fetchSystem();
  if (page === 'disk') {
    // populate device list and display the selected device
    fetchDisks();
  }
  if (page === 'settings') {
    updateSettingsPage();
  }
}

// Fetch available disks/partitions from the server and populate the select
async function fetchDisks() {
  try {
    const res = await fetch('/api/disks');
    const devices = await res.json();

    const sel = document.getElementById('disk-device-select');
    if (!sel) return;
    sel.innerHTML = '';

    devices.forEach((d, idx) => {
      const opt = document.createElement('option');
      const name = d.device || d.mountpoint || `disk-${idx}`;
      const totalLabel = d.total_bytes ? formatBytes(d.total_bytes) : 'unknown';
      opt.value = idx;
      opt.textContent = `${name} — ${d.mountpoint || '/'} — ${totalLabel}`;
      // store detail as JSON on option for convenience
      opt.dataset.device = JSON.stringify(d);
      sel.appendChild(opt);
    });

    // choose a sensible default:
    // prefer '/System/Volumes/Data' (common on macOS), then '/', then first non-empty total
    let initialIndex = 0;
    for (let i = 0; i < sel.options.length; i++) {
      const di = JSON.parse(sel.options[i].dataset.device);
      if (di.mountpoint === '/System/Volumes/Data') { initialIndex = i; break; }
      if (di.mountpoint === '/') { initialIndex = i; }
    }
    // if still zero and first has no total, pick first with total
    if ((JSON.parse(sel.options[initialIndex].dataset.device).total_bytes || 0) === 0) {
      for (let i = 0; i < sel.options.length; i++) {
        const di = JSON.parse(sel.options[i].dataset.device);
        if (di.total_bytes && di.total_bytes > 0) { initialIndex = i; break; }
      }
    }
    sel.selectedIndex = initialIndex;
    // display initial device and remember selection
    const initialDevice = JSON.parse(sel.options[sel.selectedIndex].dataset.device);
    displayDiskDevice(initialDevice);
    try { localStorage.setItem('selectedDisk', JSON.stringify(initialDevice)); } catch(e) {}

    // listen to changes
    sel.onchange = () => {
      const dev = JSON.parse(sel.options[sel.selectedIndex].dataset.device);
      displayDiskDevice(dev);
      try { localStorage.setItem('selectedDisk', JSON.stringify(dev)); } catch(e) {}
    };

  } catch (err) {
    console.error('Error fetching disks:', err);
  }
}

function displayDiskDevice(d) {
  if (!d) return;
  const totalBytes = d.total_bytes || 0;
  const usedBytes = d.used_bytes || 0;
  const freeBytes = totalBytes > usedBytes ? totalBytes - usedBytes : 0;

  // show human-friendly strings
  document.getElementById('disk-used').innerText = formatBytes(usedBytes);
  document.getElementById('disk-total').innerText = formatBytes(totalBytes);
  document.getElementById('disk-free').innerText = formatBytes(freeBytes);

  const totalGB = totalBytes / (1024 * 1024 * 1024) || 0.0;
  const usedGB = usedBytes / (1024 * 1024 * 1024) || 0.0;
  const freeGB = totalGB - usedGB;
  const percent = totalGB > 0 ? ((usedGB / totalGB) * 100).toFixed(1) : '0.0';
  document.getElementById('disk-percent').innerText = percent + '%';

  let status = 'OK';
  if (Number(percent) > 90) status = 'Critical';
  else if (Number(percent) > 80) status = 'Warning';
  document.getElementById('disk-status').innerText = status;

  const info = Number(percent) > 80
    ? `⚠️ Your disk (${d.device || d.mountpoint}) is ${percent}% full. Consider freeing up space.`
    : `✓ Your disk (${d.device || d.mountpoint}) has ${formatBytes(freeBytes)} of free space available.`;
  document.getElementById('disk-info').innerText = info;

  // update charts (keep GB values for chart scale compatibility)
  if (!diskPieChart) {
    // create charts by delegating to updateDiskPage flow using a tiny wrapper
    // prepare a fake latest object compatible with updateDiskPage expectations
    const fakeLatest = {
      disk_used: usedGB,
      disk_total: totalGB,
      disk_used_bytes: usedBytes,
      disk_total_bytes: totalBytes
    };
    updateDiskPage([], fakeLatest);
  } else {
    diskPieChart.data.datasets[0].data = [usedGB, freeGB];
    diskPieChart.update('none');
    diskBarChart.data.datasets[0].data = [usedGB];
    diskBarChart.data.datasets[1].data = [freeGB];
    diskBarChart.update('none');
  }
}

async function fetchSystem() {
  try {
    const res = await fetch('/api/system');
    const data = await res.json();

    const intervalSelect = document.getElementById('interval');
    const minutes = parseInt(intervalSelect.value);

    const cutoff = Date.now() / 1000 - minutes * 60;
    const filtered = data.filter(d => d.timestamp >= cutoff);

    if (filtered.length === 0) {
      console.log('No data available yet');
      return;
    }

    const latest = filtered[filtered.length - 1];

    // Update based on current page
    switch(currentPage) {
      case 'dashboard':
        updateDashboard(filtered, latest);
        break;
      case 'cpu':
        updateCPUPage(filtered, latest);
        break;
      case 'memory':
        updateMemoryPage(filtered, latest);
        break;
      case 'disk':
        updateDiskPage(filtered, latest);
        break;
      case 'uptime':
        updateUptimePage(filtered, latest);
        break;
    }

  } catch (err) {
    console.error('Error fetching system info:', err);
  }
}

function updateDashboard(filtered, latest) {
  // Update metrics
  document.getElementById('cpu').innerText = latest.cpu_usage.toFixed(1) + '%';
  // Use byte-based formatting so users with TB or GB see the correct unit
  document.getElementById('memory').innerText = `${formatBytes(latest.memory_used_bytes)} / ${formatBytes(latest.memory_total_bytes)}`;
  // If user selected a disk, prefer its totals for dashboard display (helps show physical SSD size)
  const selDisk = getSelectedDiskFromStorage();
  if (selDisk && selDisk.total_bytes && selDisk.total_bytes > 0) {
    document.getElementById('disk').innerText = `${formatBytes(selDisk.used_bytes)} / ${formatBytes(selDisk.total_bytes)}`;
  } else {
    document.getElementById('disk').innerText = `${formatBytes(latest.disk_used_bytes)} / ${formatBytes(latest.disk_total_bytes)}`;
  }
  document.getElementById('uptime').innerText = latest.uptime;

  const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());
  const cpuData = filtered.map(d => d.cpu_usage);
  const memoryData = filtered.map(d => d.memory_used);

  const chartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        labels: {
          color: '#d8d9da',
          font: { size: 12 }
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
        grid: { color: '#2a2b2f' }
      },
      y: {
        ticks: { color: '#9fa0a4' },
        grid: { color: '#2a2b2f' }
      }
    }
  };

  if (!cpuChart) {
    const ctxCpu = document.getElementById('cpuChart').getContext('2d');
    cpuChart = new Chart(ctxCpu, {
      type: 'line',
      data: {
        labels,
        datasets: [{
          label: 'CPU Usage %',
          data: cpuData,
          borderColor: '#ff6b35',
          backgroundColor: 'rgba(255, 107, 53, 0.1)',
          tension: 0.4,
          fill: true
        }]
      },
      options: {
        ...chartOptions,
        scales: {
          ...chartOptions.scales,
          y: {
            ...chartOptions.scales.y,
            beginAtZero: true,
            max: 100
          }
        }
      }
    });

    const ctxMem = document.getElementById('memoryChart').getContext('2d');
    memoryChart = new Chart(ctxMem, {
      type: 'line',
      data: {
        labels,
        datasets: [{
          label: 'Memory Usage GB',
          data: memoryData,
          borderColor: '#4ec9b0',
          backgroundColor: 'rgba(78, 201, 176, 0.1)',
          tension: 0.4,
          fill: true
        }]
      },
      options: {
        ...chartOptions,
        scales: {
          ...chartOptions.scales,
          y: {
            ...chartOptions.scales.y,
            beginAtZero: true
          }
        }
      }
    });
  } else {
    cpuChart.data.labels = labels;
    cpuChart.data.datasets[0].data = cpuData;
    cpuChart.update('none');

    memoryChart.data.labels = labels;
    memoryChart.data.datasets[0].data = memoryData;
    memoryChart.update('none');
  }
}

function updateCPUPage(filtered, latest) {
  const cpuValues = filtered.map(d => d.cpu_usage);
  const avg = cpuValues.reduce((a, b) => a + b, 0) / cpuValues.length;
  const max = Math.max(...cpuValues);
  const min = Math.min(...cpuValues);

  document.getElementById('cpu-current').innerText = latest.cpu_usage.toFixed(1) + '%';
  document.getElementById('cpu-avg').innerText = avg.toFixed(1) + '%';
  document.getElementById('cpu-max').innerText = max.toFixed(1) + '%';
  document.getElementById('cpu-min').innerText = min.toFixed(1) + '%';

  // Calculate distribution
  const high = cpuValues.filter(v => v > 80).length;
  const medium = cpuValues.filter(v => v >= 50 && v <= 80).length;
  const low = cpuValues.filter(v => v < 50).length;
  const total = cpuValues.length;

  document.getElementById('cpu-high').innerText = ((high / total) * 100).toFixed(1) + '%';
  document.getElementById('cpu-medium').innerText = ((medium / total) * 100).toFixed(1) + '%';
  document.getElementById('cpu-low').innerText = ((low / total) * 100).toFixed(1) + '%';

  const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());
  const cpuData = filtered.map(d => d.cpu_usage);

  const chartOptions = {
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
        grid: { color: '#2a2b2f' }
      }
    }
  };

  if (!cpuDetailChart) {
    const ctx = document.getElementById('cpuDetailChart').getContext('2d');
    cpuDetailChart = new Chart(ctx, {
      type: 'line',
      data: {
        labels,
        datasets: [{
          label: 'CPU Usage %',
          data: cpuData,
          borderColor: '#ff6b35',
          backgroundColor: 'rgba(255, 107, 53, 0.2)',
          tension: 0.4,
          fill: true
        }]
      },
      options: {
        ...chartOptions,
        scales: {
          ...chartOptions.scales,
          y: { ...chartOptions.scales.y, beginAtZero: true, max: 100 }
        }
      }
    });

    const ctxDist = document.getElementById('cpuDistChart').getContext('2d');
    cpuDistChart = new Chart(ctxDist, {
      type: 'doughnut',
      data: {
        labels: ['High (>80%)', 'Medium (50-80%)', 'Low (<50%)'],
        datasets: [{
          data: [high, medium, low],
          backgroundColor: ['#ff6b35', '#ffcc00', '#4ec9b0']
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
  } else {
    cpuDetailChart.data.labels = labels;
    cpuDetailChart.data.datasets[0].data = cpuData;
    cpuDetailChart.update('none');

    cpuDistChart.data.datasets[0].data = [high, medium, low];
    cpuDistChart.update('none');
  }
}

function updateMemoryPage(filtered, latest) {
  const memValues = filtered.map(d => d.memory_used);
  const avg = memValues.reduce((a, b) => a + b, 0) / memValues.length;
  const max = Math.max(...memValues);
  const available = latest.memory_total - latest.memory_used;
  const percent = ((latest.memory_used / latest.memory_total) * 100).toFixed(1);

  // Display human-friendly units using raw bytes
  document.getElementById('mem-used').innerText = formatBytes(latest.memory_used_bytes);
  document.getElementById('mem-percent').innerText = percent + '%';
  document.getElementById('mem-total').innerText = formatBytes(latest.memory_total_bytes);
  document.getElementById('mem-max').innerText = max.toFixed(1) + ' GB';
  document.getElementById('mem-avg').innerText = avg.toFixed(1) + ' GB';
  // available in bytes
  const availableBytes = latest.memory_total_bytes - latest.memory_used_bytes;
  document.getElementById('mem-available').innerText = formatBytes(availableBytes);

  // Calculate growth rate
  if (memValues.length > 60) {
    const oldVal = memValues[0];
    const newVal = memValues[memValues.length - 1];
    const growth = ((newVal - oldVal) / (memValues.length / 60)).toFixed(2);
    document.getElementById('mem-growth').innerText = growth + ' MB/min';
    
    if (growth > 0) {
      const timeToFull = (available * 1024) / parseFloat(growth);
      if (timeToFull < 1440) {
        document.getElementById('mem-estimate').innerText = timeToFull.toFixed(0) + ' min';
      } else {
        document.getElementById('mem-estimate').innerText = 'Never';
      }
    } else {
      document.getElementById('mem-estimate').innerText = 'Never';
    }
  }

  const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());
  const memData = filtered.map(d => d.memory_used);

  const chartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: { labels: { color: '#d8d9da' } }
    },
    scales: {
      x: {
        ticks: { color: '#9fa0a4', maxRotation: 45, minRotation: 45 },
        grid: { color: '#2a2b2f' }
      },
      y: {
        ticks: { color: '#9fa0a4' },
        grid: { color: '#2a2b2f' }
      }
    }
  };

  if (!memDetailChart) {
    const ctx = document.getElementById('memDetailChart').getContext('2d');
    memDetailChart = new Chart(ctx, {
      type: 'line',
      data: {
        labels,
        datasets: [{
          label: 'Memory Usage GB',
          data: memData,
          borderColor: '#4ec9b0',
          backgroundColor: 'rgba(78, 201, 176, 0.2)',
          tension: 0.4,
          fill: true
        }]
      },
      options: {
        ...chartOptions,
        scales: {
          ...chartOptions.scales,
          y: { ...chartOptions.scales.y, beginAtZero: true }
        }
      }
    });

    const ctxPie = document.getElementById('memPieChart').getContext('2d');
    memPieChart = new Chart(ctxPie, {
      type: 'pie',
      data: {
        labels: ['Used', 'Available'],
        datasets: [{
          // chart data uses GB numbers (keeps existing behavior)
          data: [latest.memory_used, available],
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
  } else {
    memDetailChart.data.labels = labels;
    memDetailChart.data.datasets[0].data = memData;
    memDetailChart.update('none');

    memPieChart.data.datasets[0].data = [latest.memory_used, available];
    memPieChart.update('none');
  }
}

function updateDiskPage(filtered, latest) {
  // Use bytes for display, but keep numeric GBs for charts
  const used = latest.disk_used; // GB (float)
  const total = latest.disk_total; // GB (float)
  const free = total - used; // GB
  const percent = ((used / total) * 100).toFixed(1);

  document.getElementById('disk-used').innerText = formatBytes(latest.disk_used_bytes);
  document.getElementById('disk-percent').innerText = percent + '%';
  document.getElementById('disk-total').innerText = formatBytes(latest.disk_total_bytes);
  const freeBytes = latest.disk_total_bytes - latest.disk_used_bytes;
  document.getElementById('disk-free').innerText = formatBytes(freeBytes);
  
  let status = 'OK';
  if (percent > 90) status = 'Critical';
  else if (percent > 80) status = 'Warning';
  document.getElementById('disk-status').innerText = status;
  
  const info = percent > 80 
    ? `⚠️ Your disk is ${percent}% full. Consider freeing up space.`
    : `✓ Your disk has ${free.toFixed(1)} GB of free space available.`;
  document.getElementById('disk-info').innerText = info;

  if (!diskPieChart) {
    const ctxPie = document.getElementById('diskPieChart').getContext('2d');
    diskPieChart = new Chart(ctxPie, {
      type: 'doughnut',
      data: {
        labels: ['Used', 'Free'],
        datasets: [{
          // keep chart numbers in GB to preserve scale (existing logic)
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

    const ctxBar = document.getElementById('diskBarChart').getContext('2d');
    diskBarChart = new Chart(ctxBar, {
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
          legend: { labels: { color: '#d8d9da' } }
        },
        scales: {
          x: {
            ticks: { color: '#9fa0a4' },
            grid: { color: '#2a2b2f' }
          },
          y: {
            ticks: { color: '#9fa0a4' },
            grid: { color: '#2a2b2f' }
          }
        }
      }
    });
  } else {
    diskPieChart.data.datasets[0].data = [used, free];
    diskPieChart.update('none');
    
    diskBarChart.data.datasets[0].data = [used];
    diskBarChart.data.datasets[1].data = [free];
    diskBarChart.update('none');
  }
}

function updateUptimePage(filtered, latest) {
  document.getElementById('uptime-current').innerText = latest.uptime;
  
  // Parse uptime string (format: "1h2m3s" or similar)
  const uptimeStr = latest.uptime;
  const days = uptimeStr.match(/(\d+)d/);
  const hours = uptimeStr.match(/(\d+)h/);
  const minutes = uptimeStr.match(/(\d+)m/);
  
  const totalDays = days ? parseInt(days[1]) : 0;
  const totalHours = hours ? parseInt(hours[1]) : 0;
  const totalMinutes = minutes ? parseInt(minutes[1]) : 0;
  
  document.getElementById('uptime-days').innerText = totalDays;
  document.getElementById('uptime-hours').innerText = totalHours;
  document.getElementById('uptime-minutes').innerText = totalMinutes;
  
  // Calculate reliability percentage (simplified)
  const reliability = 99.9;
  document.getElementById('uptime-reliability').innerText = reliability.toFixed(1) + '%';
  
  // Update circle progress
  const circle = document.getElementById('uptime-circle');
  const circumference = 2 * Math.PI * 90;
  const offset = circumference - (reliability / 100) * circumference;
  circle.style.strokeDashoffset = offset;
  
  const message = totalDays > 30 
    ? `Impressive! Your system has been running for over ${totalDays} days.`
    : `Your system is running smoothly. Current uptime: ${latest.uptime}`;
  document.getElementById('uptime-message').innerText = message;
}

// Event listeners
document.getElementById('interval').addEventListener('change', fetchSystem);
document.getElementById('refresh').addEventListener('click', () => {
  const btn = document.getElementById('refresh');
  btn.style.transform = 'rotate(360deg)';
  setTimeout(() => btn.style.transform = '', 300);
  fetchSystem();
});

// Initialize
initNavigation();
switchPage('dashboard');
setInterval(fetchSystem, 5000);
fetchSystem();