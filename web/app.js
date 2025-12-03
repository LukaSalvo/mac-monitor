let cpuChart, memoryChart;

async function fetchSystem() {
  try {
    const res = await fetch('http://localhost:3000/api/system');
    const data = await res.json();

    const intervalSelect = document.getElementById('interval');
    const minutes = parseInt(intervalSelect.value);

    const cutoff = Date.now() / 1000 - minutes * 60;
    const filtered = data.filter(d => d.timestamp >= cutoff);

    if (filtered.length === 0) return;

    const latest = filtered[filtered.length - 1];

    document.getElementById('cpu').innerText = latest.cpu_usage.toFixed(1) + '%';
    document.getElementById('memory').innerText = `${latest.memory_used.toFixed(1)} GB / ${latest.memory_total.toFixed(1)} GB`;
    document.getElementById('disk').innerText = `${latest.disk_used.toFixed(1)} GB / ${latest.disk_total.toFixed(1)} GB`;
    document.getElementById('uptime').innerText = latest.uptime;

    const labels = filtered.map(d => new Date(d.timestamp * 1000).toLocaleTimeString());
    const cpuData = filtered.map(d => d.cpu_usage);
    const memoryData = filtered.map(d => d.memory_used);

    if (!cpuChart) {
      const ctxCpu = document.getElementById('cpuChart').getContext('2d');
      cpuChart = new Chart(ctxCpu, {
        type: 'line',
        data: { labels, datasets: [{ label: 'CPU Usage %', data: cpuData, borderColor: 'red', fill: false }] },
        options: { responsive: true, scales: { y: { beginAtZero: true, max: 100 } } }
      });

      const ctxMem = document.getElementById('memoryChart').getContext('2d');
      memoryChart = new Chart(ctxMem, {
        type: 'line',
        data: { labels, datasets: [{ label: 'Memory Usage GB', data: memoryData, borderColor: 'blue', fill: false }] },
        options: { responsive: true, scales: { y: { beginAtZero: true } } }
      });
    } else {
      cpuChart.data.labels = labels;
      cpuChart.data.datasets[0].data = cpuData;
      cpuChart.update();

      memoryChart.data.labels = labels;
      memoryChart.data.datasets[0].data = memoryData;
      memoryChart.update();
    }

  } catch (err) {
    console.error('Error fetching system info:', err);
  }
}

document.getElementById('interval').addEventListener('change', fetchSystem);

setInterval(fetchSystem, 5000);
fetchSystem();
