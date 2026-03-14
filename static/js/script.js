const API = '';
let pollTimer = null;
let currentJobId = null;
let currentFiles = [];
let selectedPlatform = 'soundcloud'; // default

// ── Platform config ──
const PLATFORMS = {
    soundcloud: {
        name: 'SoundCloud',
        color: '#ff5500',
        rgb: '255,85,0',
        placeholder: 'https://soundcloud.com/artista/cancion',
        blob1: '#ff4d4d',
        blob2: '#ff8c42',
    },
    spotify: {
        name: 'Spotify',
        color: '#1db954',
        rgb: '29,185,84',
        placeholder: 'https://open.spotify.com/track/...',
        blob1: '#1db954',
        blob2: '#17a348',
    },
    youtube: {
        name: 'YouTube',
        color: '#ff0000',
        rgb: '255,0,0',
        placeholder: 'https://www.youtube.com/watch?v=...',
        blob1: '#ff0000',
        blob2: '#ff5500',
    },
    youtubemusic: {
        name: 'YT Music',
        color: '#ff0000',
        rgb: '255,0,0',
        placeholder: 'https://music.youtube.com/watch?v=...',
        blob1: '#ff0000',
        blob2: '#cc0000',
    },
    applemusic: {
        name: 'Apple Music',
        color: '#fc3c44',
        rgb: '252,60,68',
        placeholder: 'https://music.apple.com/album/...',
        blob1: '#fc3c44',
        blob2: '#ff6b6b',
    },
    deezer: {
        name: 'Deezer',
        color: '#a238ff',
        rgb: '162,56,255',
        placeholder: 'https://www.deezer.com/track/...',
        blob1: '#a238ff',
        blob2: '#7b2fe8',
    },
};

// ── File System Access API support check ──
const hasFSA = ('showDirectoryPicker' in window);

function ui(id) { return document.getElementById(id); }

if (!hasFSA) ui('folderHint').style.display = 'flex';

// ── Platform selection ──
function selectPlatform(platform) {
    selectedPlatform = platform;
    const cfg = PLATFORMS[platform];

    // Update button states
    document.querySelectorAll('.platform-btn').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.platform === platform);
    });

    // Update URL placeholder
    ui('urlInput').placeholder = cfg.placeholder;

    // Update CSS custom property for input focus color
    document.documentElement.style.setProperty('--active-platform-color', cfg.color);
    document.documentElement.style.setProperty('--active-platform-rgb', cfg.rgb);

    // Animate blobs to platform colors
    document.querySelector('.blob-1').style.background = cfg.blob1;
    document.querySelector('.blob-2').style.background = cfg.blob2;

    // Show/hide Spotify auth note
    const spNote = ui('spotifyNote');
    if (spNote) spNote.style.display = platform === 'spotify' ? 'flex' : 'none';
}

async function startDownload() {
    const url = ui('urlInput').value.trim();
    if (!url) { showError('Por favor pega una URL válida.'); return; }
    resetUI();
    ui('btnDownload').disabled = true;
    ui('statusPanel').classList.add('visible');
    ui('statusMsg').textContent = 'Enviando al servidor...';

    try {
        const res = await fetch(`${API}/api/download`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ url, platform: selectedPlatform })
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Error al iniciar descarga');
        pollStatus(data.job_id);
    } catch (e) {
        showError(e.message);
        ui('btnDownload').disabled = false;
    }
}

function pollStatus(jobId) {
    const msgs = {
        queued: 'En cola...',
        downloading: `Descargando desde ${PLATFORMS[selectedPlatform]?.name || 'la plataforma'}...`,
        processing: 'Procesando audio...',
    };

    pollTimer = setInterval(async () => {
        try {
            const res = await fetch(`${API}/api/status/${jobId}`);
            const job = await res.json();

            if (msgs[job.status]) ui('statusMsg').textContent = msgs[job.status];
            else if (job.status === 'done') {
                clearInterval(pollTimer);
                showDone(jobId, job.files);
            } else if (job.status === 'error') {
                clearInterval(pollTimer);
                showError(job.error || 'Error desconocido');
                ui('btnDownload').disabled = false;
                ui('statusPanel').classList.remove('visible');
            }
        } catch (e) {
            clearInterval(pollTimer);
            showError('No se pudo contactar al servidor');
            ui('btnDownload').disabled = false;
        }
    }, 1500);
}

function showDone(jobId, files) {
    currentJobId = jobId;
    currentFiles = files;

    const bar = ui('statusBar');
    bar.classList.remove('indeterminate');
    bar.style.width = '100%';
    bar.style.background = 'var(--green)';
    ui('statusDot').style.background = 'var(--green)';
    ui('statusDot').style.animation = 'none';
    ui('statusMsg').textContent = `${files.length} archivo(s) listo(s)`;

    const list = ui('fileList');
    list.innerHTML = '';
    files.forEach((fname, i) => {
        const div = document.createElement('div');
        div.className = 'file-item';
        div.id = `file-item-${i}`;
        div.innerHTML = `
      <span class="file-icon">🎵</span>
      <div style="flex:1;overflow:hidden">
        <span class="file-name" title="${fname}">${fname}</span>
        <div class="file-progress-bg"><div class="file-progress-fill" id="prog-${i}"></div></div>
      </div>
      <span class="file-status" id="status-${i}"></span>
      <button class="btn-get" onclick="downloadFile('${jobId}','${encodeURIComponent(fname)}')">OBTENER</button>
    `;
        list.appendChild(div);
    });

    ui('filesSection').style.display = 'block';
    ui('btnDownload').disabled = false;
}

function downloadFile(jobId, encodedName) {
    window.location.href = `${API}/api/file/${jobId}/${encodedName}`;
}

// ── Download All — con selector de carpeta ──
async function downloadAll() {
    if (!currentJobId || currentFiles.length === 0) return;

    const btn = ui('btnDownloadAll');
    btn.classList.add('busy');
    btn.disabled = true;

    if (hasFSA) {
        let dirHandle;
        try {
            dirHandle = await window.showDirectoryPicker({ mode: 'readwrite', startIn: 'music' });
        } catch (e) {
            btn.classList.remove('busy');
            btn.disabled = false;
            return;
        }

        ui('folderName').textContent = '📁 ' + dirHandle.name;
        ui('folderBadge').classList.add('visible');

        for (let i = 0; i < currentFiles.length; i++) {
            const fname = currentFiles[i];
            const item = ui(`file-item-${i}`);
            const prog = ui(`prog-${i}`);
            const stat = ui(`status-${i}`);

            if (item) { item.classList.remove('done-dl'); item.classList.add('downloading'); }
            if (stat) stat.textContent = 'descargando...';
            if (prog) prog.style.width = '10%';

            try {
                const response = await fetch(`${API}/api/file/${currentJobId}/${encodeURIComponent(fname)}`);
                if (!response.ok) throw new Error('HTTP ' + response.status);

                const total = parseInt(response.headers.get('Content-Length') || '0', 10);
                let received = 0;
                const reader = response.body.getReader();
                const chunks = [];

                while (true) {
                    const { done, value } = await reader.read();
                    if (done) break;
                    chunks.push(value);
                    received += value.length;
                    if (total && prog) prog.style.width = Math.min(95, Math.round(received / total * 100)) + '%';
                }

                const blob = new Blob(chunks);
                const fileHandle = await dirHandle.getFileHandle(fname, { create: true });
                const writable = await fileHandle.createWritable();
                await writable.write(blob);
                await writable.close();

                if (prog) prog.style.width = '100%';
                if (stat) { stat.textContent = '✓ guardado'; stat.className = 'file-status ok'; }
                if (item) { item.classList.remove('downloading'); item.classList.add('done-dl'); }
            } catch (err) {
                if (stat) { stat.textContent = '✕ error'; stat.className = 'file-status err'; }
                if (item) { item.classList.remove('downloading'); }
                console.error('Error al guardar', fname, err);
            }

            await delay(200);
        }
    } else {
        for (let i = 0; i < currentFiles.length; i++) {
            const fname = currentFiles[i];
            const item = ui(`file-item-${i}`);
            const stat = ui(`status-${i}`);

            if (item) { item.classList.remove('done-dl'); item.classList.add('downloading'); }
            if (stat) stat.textContent = 'descargando...';

            const a = document.createElement('a');
            a.href = `${API}/api/file/${currentJobId}/${encodeURIComponent(fname)}`;
            a.download = fname;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);

            await delay(800);
            if (stat) { stat.textContent = '✓'; stat.className = 'file-status ok'; }
            if (item) { item.classList.remove('downloading'); item.classList.add('done-dl'); }
            if (i < currentFiles.length - 1) await delay(400);
        }
    }

    btn.classList.remove('busy');
    btn.disabled = false;
}

function delay(ms) { return new Promise(r => setTimeout(r, ms)); }

function showError(msg) {
    ui('errorBox').textContent = '✕ ' + msg;
    ui('errorBox').classList.add('visible');
}

function resetUI() {
    clearInterval(pollTimer);
    currentJobId = null; currentFiles = [];
    ui('errorBox').classList.remove('visible');
    ui('statusPanel').classList.remove('visible');
    ui('filesSection').style.display = 'none';
    ui('folderBadge').classList.remove('visible');
    const bar = ui('statusBar');
    bar.style.width = '0%'; bar.style.background = '';
    bar.classList.add('indeterminate');
    ui('statusDot').style.background = ''; ui('statusDot').style.animation = '';
}

ui('urlInput').addEventListener('keydown', e => { if (e.key === 'Enter') startDownload(); });

// Init default platform
selectPlatform('soundcloud');