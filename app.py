import os
import re
import json
import time
import subprocess
import threading
import uuid
import hashlib
import shutil
import requests
from io import BytesIO
from pathlib import Path
from urllib.parse import urljoin, urlparse, parse_qs, urlencode, urlunparse, quote
from flask import Flask, request, jsonify, send_file, send_from_directory, Response
from flask_cors import CORS
from mutagen.mp3 import MP3
from mutagen.id3 import ID3

app = Flask(__name__, static_folder="static")
CORS(app)

BASE_DIR = Path(__file__).parent.resolve()
from desktop_api import register_desktop_api
register_desktop_api(app, BASE_DIR)
DOWNLOAD_DIR = BASE_DIR / "downloads"
DOWNLOAD_DIR.mkdir(exist_ok=True)
STATS_FILE = BASE_DIR / "play_stats.json"
SOURCES_FILE = BASE_DIR / "sources.json"
METADATA_CACHE = BASE_DIR / "metadata_cache.json"
# ════════════════════════════════════════════════════════
# PLAY STATS & METADATA
# ════════════════════════════════════════════════════════
_stats_lock = threading.Lock()
_sources_lock = threading.Lock()
_meta_lock = threading.Lock()
from cloud_api import register_cloud_api
resolve_cloud_track = register_cloud_api(app, BASE_DIR, _stats_lock)


def _load_stats():
    if STATS_FILE.exists():
        try:
            return json.loads(STATS_FILE.read_text())
        except Exception:
            pass
    return {}


def _save_stats(stats):
    temporary = STATS_FILE.with_name('.wave-stats-' + uuid.uuid4().hex + '.tmp')
    temporary.write_text(json.dumps(stats, ensure_ascii=False, indent=1))
    os.replace(temporary, STATS_FILE)


def _load_sources():
    if SOURCES_FILE.exists():
        try:
            data = json.loads(SOURCES_FILE.read_text())
            return data if isinstance(data, dict) else {}
        except Exception:
            pass
    return {}


def _save_sources(sources):
    SOURCES_FILE.write_text(json.dumps(sources, ensure_ascii=False, indent=1))


def _set_source(folder, url, **updates):
    """Create or update a playlist's server-side source record."""
    with _sources_lock:
        sources = _load_sources()
        source = sources.get(folder, {})
        source.update(updates)
        if url is not None:
            source["url"] = url
        source.setdefault("added", time.time())
        sources[folder] = source
        _save_sources(sources)
        return source.copy()


def _load_meta_cache():
    if METADATA_CACHE.exists():
        try:
            return json.loads(METADATA_CACHE.read_text())
        except Exception:
            pass
    return {}


def _save_meta_cache(cache):
    METADATA_CACHE.write_text(json.dumps(cache, ensure_ascii=False))


def _extract_metadata(filepath: Path):
    """Extract title, artist, duration from MP3 ID3 tags."""
    try:
        audio = MP3(str(filepath))
        tags = ID3(str(filepath))
        title = str(tags.get("TIT2", "")) or None
        artist = str(tags.get("TPE1", "")) or None
        duration = audio.info.length if audio.info else 0
        has_art = any(k.startswith("APIC") for k in tags.keys())
        return {"title": title, "artist": artist, "duration": round(duration, 1), "has_art": has_art}
    except Exception:
        return {"title": None, "artist": None, "duration": 0, "has_art": False}


def _get_track_key(folder, filename):
    """Stable key for a track."""
    return f"{folder}/{filename}"

# ════════════════════════════════════════════════════════
# DOWNLOAD JOBS
# ════════════════════════════════════════════════════════
jobs = {}
jobs_lock = threading.Lock()
_syncing_folders = set()
_syncing_lock = threading.Lock()


def _resolve_scdl_bin():
    """Find scdl even when the service starts with a minimal PATH."""
    configured = os.environ.get("SCDL_BIN", "").strip()
    candidates = [configured, shutil.which("scdl"), str(Path.home() / ".local/bin/scdl")]
    return next((candidate for candidate in candidates if candidate and Path(candidate).is_file()), "scdl")


SCDL_BIN = _resolve_scdl_bin()


def resolve_soundcloud_url(url: str) -> str:
    if "on.soundcloud.com" in url:
        try:
            r = requests.head(url, headers={'User-Agent': 'Mozilla/5.0'}, allow_redirects=True, timeout=10)
            url = r.url
        except Exception:
            pass
    parsed = urlparse(url)
    clean_url = urlunparse((parsed.scheme, parsed.netloc, parsed.path, '', '', ''))
    return clean_url


def run_scdl(job_id: str, url: str):
    job_dir = DOWNLOAD_DIR / job_id
    job_dir.mkdir(parents=True, exist_ok=True)
    with jobs_lock:
        jobs[job_id]["status"] = "downloading"
    try:
        resolved_url = resolve_soundcloud_url(url)
        cmd = [SCDL_BIN, "-l", resolved_url, "--path", str(job_dir), "--no-playlist-folder", "--onlymp3"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if result.returncode != 0:
            raise RuntimeError(result.stderr or "scdl error")
        files = list(job_dir.glob("*.mp3")) + list(job_dir.glob("*.m4a")) + list(job_dir.glob("*.flac"))
        if not files:
            raise RuntimeError("No files downloaded")
        with jobs_lock:
            jobs[job_id]["status"] = "done"
            jobs[job_id]["files"] = [f.name for f in files]
    except subprocess.TimeoutExpired:
        with jobs_lock:
            jobs[job_id]["status"] = "error"
            jobs[job_id]["error"] = "Timeout (5 min)"
    except Exception as e:
        with jobs_lock:
            jobs[job_id]["status"] = "error"
            jobs[job_id]["error"] = str(e)


# ════════════════════════════════════════════════════════
# ROUTES — Static & Library
# ════════════════════════════════════════════════════════

@app.route("/")
def index():
    return send_from_directory("static", "index.html")


def _dir_entries(path: Path):
    entries = []
    for f in sorted(path.iterdir(), key=lambda x: x.name):
        encoded = quote(f.name, safe='') + ("/" if f.is_dir() else "")
        entries.append({"name": f.name, "isDir": f.is_dir(), "href": encoded})
    return entries


AUDIO_EXTS = {'.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus', '.aiff', '.aif', '.webm'}


@app.route("/api/folders")
def list_folders():
    """Fast endpoint: list folders with track count only (no track details)."""
    folders = []
    for d in sorted(DOWNLOAD_DIR.rglob("*"), key=lambda x: str(x)):
        if d.is_symlink() or any(p.startswith(".") for p in d.relative_to(DOWNLOAD_DIR).parts):
            continue
        if not d.is_dir():
            continue
        count = sum(1 for f in d.iterdir() if f.suffix.lower() in AUDIO_EXTS)
        if count == 0:
            continue
        # Check if any track has artwork (sample first file)
        first_audio = next((f for f in d.iterdir() if f.suffix.lower() in AUDIO_EXTS), None)
        has_art = False
        if first_audio:
            try:
                tags = ID3(str(first_audio))
                has_art = any(k.startswith("APIC") for k in tags.keys())
            except Exception:
                pass
        folders.append({
            "name": d.relative_to(DOWNLOAD_DIR).as_posix(),
            "href": quote(d.relative_to(DOWNLOAD_DIR).as_posix(), safe='/') + "/",
            "count": count,
            "coverUrl": "/api/artwork/" + quote(d.relative_to(DOWNLOAD_DIR).as_posix(), safe='/') + "/" + quote(first_audio.name, safe='') if has_art and first_audio else None
        })
    return jsonify(folders)


@app.route("/api/folder/<path:folder_name>/tracks")
def folder_tracks(folder_name):
    """Get tracks for a specific folder with metadata."""
    safe_parts = Path(folder_name).parts
    target = DOWNLOAD_DIR.joinpath(*safe_parts).resolve()
    if not target.is_relative_to(DOWNLOAD_DIR) or not target.is_dir():
        return jsonify({"error": "Not found"}), 404

    with _meta_lock:
        cache = _load_meta_cache()
    with _stats_lock:
        stats = _load_stats()

    tracks = []
    updated = False
    for f in sorted(target.iterdir(), key=lambda x: x.name):
        if not f.is_file() or f.is_symlink() or f.suffix.lower() not in AUDIO_EXTS:
            continue
        rel = f"{folder_name}/{f.name}"
        mtime = str(f.stat().st_mtime)
        if rel in cache and cache[rel].get("_mtime") == mtime:
            meta = cache[rel]
        else:
            meta = _extract_metadata(f)
            meta["_mtime"] = mtime
            cache[rel] = meta
            updated = True
        track = {
            "name": meta.get("title") or f.stem,
            "artist": meta.get("artist") or folder_name,
            "duration": meta.get("duration", 0),
            "has_art": meta.get("has_art", False),
            "play_count": stats.get(rel, {}).get("count", 0),
            "relPath": rel,
            "filename": f.name,
            "href": quote(f.name, safe=''),
            "url": "/music/" + quote(folder_name, safe='') + "/" + quote(f.name, safe='')
        }
        if track["has_art"]:
            track["coverUrl"] = "/api/artwork/" + quote(rel, safe='/')
        tracks.append(track)

    if updated:
        with _meta_lock:
            _save_meta_cache(cache)

    return jsonify(tracks)


@app.route("/music/")
@app.route("/music/<path:filepath>")
def serve_music(filepath=""):
    """Directory listings only — audio files served by nginx."""
    if filepath:
        safe_parts = Path(filepath).parts
        target = DOWNLOAD_DIR.joinpath(*safe_parts).resolve()
        if not str(target).startswith(str(DOWNLOAD_DIR)):
            return "Forbidden", 403
        if target.is_file():
            # Fallback si nginx no lo sirvió (no debería pasar)
            return send_file(target, conditional=True)
        if target.is_dir():
            return jsonify(_dir_entries(target))
        return "Not found", 404
    else:
        return jsonify(_dir_entries(DOWNLOAD_DIR))


_zip_semaphore = threading.Semaphore(2)

@app.route("/api/folder/<path:folder_name>/zip")
def download_folder_zip(folder_name):
    """Stream zip usando el comando zip del sistema (rápido, sin compresión)."""
    from flask import stream_with_context
    safe = Path(folder_name).name
    folder_path = DOWNLOAD_DIR / safe
    if not folder_path.is_dir():
        return "Not found", 404

    audio_exts = {".mp3", ".m4a", ".flac", ".wav", ".ogg", ".opus", ".aac", ".wma", ".webm"}
    files = sorted([f.name for f in folder_path.iterdir()
                    if f.is_file() and f.suffix.lower() in audio_exts])
    if not files:
        return "No audio files", 404

    zip_name = safe + ".zip"

    def generate():
        with _zip_semaphore:
            proc = subprocess.Popen(
                ["zip", "-0", "-j", "-", "--names-stdin"],
                cwd=str(folder_path),
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
            )
            proc.stdin.write("\n".join(files).encode())
            proc.stdin.close()
            try:
                while True:
                    chunk = proc.stdout.read(256 * 1024)
                    if not chunk:
                        break
                    yield chunk
            finally:
                proc.wait()

    return Response(
        stream_with_context(generate()),
        mimetype="application/zip",
        headers={
            "Content-Disposition": f'attachment; filename="{zip_name}"',
            "X-Accel-Buffering": "no",
        }
    )


@app.route("/api/library")
def library():
    audio_exts = {'.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus'}
    tracks = []
    for folder in sorted(DOWNLOAD_DIR.iterdir(), key=lambda d: d.stat().st_mtime, reverse=True):
        if not folder.is_dir():
            continue
        for f in sorted(folder.iterdir(), key=lambda x: x.name):
            if f.suffix.lower() in audio_exts:
                tracks.append({"folder": folder.name, "filename": f.name, "size": f.stat().st_size,
                               "url": f"/api/file/{folder.name}/{f.name}"})
    return jsonify({"tracks": tracks, "total": len(tracks)})


# ════════════════════════════════════════════════════════
# ROUTES — Downloads
# ════════════════════════════════════════════════════════

def _sanitize_folder_name(name: str) -> str:
    """Convierte un nombre de playlist en un nombre de carpeta válido."""
    name = re.sub(r'[<>:"/\\|?*]', '', name)
    name = re.sub(r'\s+', ' ', name).strip()
    return name[:80] or "sounddrop"

def _sc_playlist_info(url: str) -> dict:
    """Obtiene info básica de una playlist de SoundCloud vía scdl --dump-json."""
    try:
        result = subprocess.run(
            [SCDL_BIN, "-l", url, "--dump-json"],
            capture_output=True, text=True, timeout=30
        )
        lines = [l for l in result.stdout.strip().split('\n') if l.strip().startswith('{')]
        tracks = []
        for line in lines:
            try:
                d = json.loads(line)
                tracks.append({
                    "id": str(d.get("id", "")),
                    "title": d.get("title", ""),
                    "permalink_url": d.get("permalink_url", ""),
                })
            except Exception:
                pass
        return {"tracks": tracks, "count": len(tracks)}
    except Exception as e:
        return {"tracks": [], "count": 0, "error": str(e)}

def _normalize_track_name(filename: str) -> str:
    """Normaliza el nombre del archivo para comparación (sin extensión, minúsculas, sin números de prefijo)."""
    name = Path(filename).stem.lower()
    name = re.sub(r'^\d+[\.\-_\s]+', '', name)  # eliminar prefijos numéricos (01. , 002-)
    name = re.sub(r'[^\w\s]', '', name)
    return re.sub(r'\s+', ' ', name).strip()


def _is_soundcloud_url(url: str) -> bool:
    try:
        host = (urlparse(url).hostname or "").lower()
        return host == "soundcloud.com" or host.endswith(".soundcloud.com")
    except Exception:
        return False


def _existing_playlist_folder(folder_name: str):
    """Resolve an existing direct child of downloads without allowing traversal."""
    if not folder_name or Path(folder_name).name != folder_name:
        return None
    candidate = (DOWNLOAD_DIR / folder_name).resolve()
    try:
        candidate.relative_to(DOWNLOAD_DIR)
    except ValueError:
        return None
    return candidate if candidate.is_dir() else None

def run_scdl_playlist(job_id: str, url: str, folder_name: str):
    """Descarga playlist de SoundCloud en carpeta nombrada, evitando duplicados."""
    folder_path = DOWNLOAD_DIR / folder_name
    folder_path.mkdir(parents=True, exist_ok=True)

    # Snapshot de archivos existentes ANTES de descargar
    audio_exts = {'.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus'}
    existing_files = set(f.name for f in folder_path.iterdir() if f.suffix.lower() in audio_exts)
    existing_normalized = set(_normalize_track_name(f) for f in existing_files)

    with jobs_lock:
        jobs[job_id].update({
            "status": "downloading",
            "folder": folder_name,
            "existing": len(existing_files),
        })

    try:
        resolved_url = resolve_soundcloud_url(url)

        # scdl --no-playlist-folder descarga en la carpeta dada
        # --onlymp3 convierte a mp3
        # Si el archivo ya existe, scdl normalmente lo salta — pero añadimos --flac como fallback
        cmd = [
            SCDL_BIN, "-l", resolved_url,
            "--path", str(folder_path),
            "--no-playlist-folder",
            "--onlymp3",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        if result.returncode != 0:
            raise RuntimeError((result.stderr or "scdl error").strip())

        # Detectar archivos nuevos comparando con el snapshot inicial
        files_after = set(f.name for f in folder_path.iterdir() if f.suffix.lower() in audio_exts)
        new_files = files_after - existing_files

        # Filtrar duplicados que scdl haya descargado igualmente (por nombre normalizado)
        truly_new = []
        duplicates_removed = []
        for fname in new_files:
            normalized = _normalize_track_name(fname)
            if normalized in existing_normalized:
                # Es un duplicado — eliminar
                (folder_path / fname).unlink(missing_ok=True)
                duplicates_removed.append(fname)
            else:
                truly_new.append(fname)
                existing_normalized.add(normalized)

        with jobs_lock:
            jobs[job_id].update({
                "status": "done",
                "files": truly_new,
                "new_count": len(truly_new),
                "skipped": len(existing_files),
                "duplicates_removed": len(duplicates_removed),
                "total_in_folder": len(files_after) - len(duplicates_removed),
            })
        _set_source(folder_name, url, last_sync=time.time(), last_new=len(truly_new), last_status="done")

    except subprocess.TimeoutExpired:
        with jobs_lock:
            jobs[job_id].update({"status": "error", "error": "Timeout (10 min)"})
        _set_source(folder_name, url, last_sync=time.time(), last_new=0, last_status="error")
    except Exception as e:
        with jobs_lock:
            jobs[job_id].update({"status": "error", "error": str(e)})
        _set_source(folder_name, url, last_sync=time.time(), last_new=0, last_status="error")
    finally:
        with _syncing_lock:
            _syncing_folders.discard(folder_name)

@app.route("/api/playlist/download", methods=["POST"])
def start_playlist_download():
    """Descarga una playlist de SoundCloud en una carpeta con deduplicación."""
    data = request.get_json() or {}
    url = data.get("url", "").strip()
    folder_name = _sanitize_folder_name(data.get("folder_name", "").strip())
    if not url or not _is_soundcloud_url(url):
        return jsonify({"error": "URL de SoundCloud requerida"}), 400
    if not folder_name:
        return jsonify({"error": "Nombre de carpeta requerido"}), 400

    _set_source(folder_name, url)
    job_id = str(uuid.uuid4())
    with jobs_lock:
        jobs[job_id] = {"status": "queued", "files": [], "error": None, "folder": folder_name}
    threading.Thread(target=run_scdl_playlist, args=(job_id, url, folder_name), daemon=True).start()
    return jsonify({"job_id": job_id, "folder": folder_name})


@app.route("/api/sources", methods=["GET"])
def list_sources():
    with _sources_lock:
        sources = _load_sources()
    folders = []
    for folder in sorted(DOWNLOAD_DIR.iterdir(), key=lambda p: p.name.lower()):
        if not folder.is_dir():
            continue
        audio = sorted(f for f in folder.iterdir() if f.is_file() and f.suffix.lower() in AUDIO_EXTS)
        if not audio:
            continue
        cover_url = None
        for track in audio:
            try:
                if any(key.startswith("APIC") for key in ID3(str(track)).keys()):
                    cover_url = "/api/artwork/" + quote(f"{folder.name}/{track.name}", safe='/')
                    break
            except Exception:
                continue
        source = sources.get(folder.name, {})
        folders.append({
            "folder": folder.name, "count": len(audio), "coverUrl": cover_url,
            "url": source.get("url"), "last_sync": source.get("last_sync"),
            "last_new": source.get("last_new"),
        })
    return jsonify(folders)


@app.route("/api/sources", methods=["POST"])
def save_source():
    data = request.get_json() or {}
    folder_name = str(data.get("folder_name", "")).strip()
    url = str(data.get("url", "")).strip()
    if _existing_playlist_folder(folder_name) is None:
        return jsonify({"error": "folder_not_found"}), 404
    if not _is_soundcloud_url(url):
        return jsonify({"error": "invalid_soundcloud_url"}), 400
    return jsonify({"folder": folder_name, **_set_source(folder_name, url)})


@app.route("/api/sources/<path:folder_name>", methods=["DELETE"])
def delete_source(folder_name):
    if _existing_playlist_folder(folder_name) is None:
        return jsonify({"error": "folder_not_found"}), 404
    with _sources_lock:
        sources = _load_sources()
        source = sources.get(folder_name)
        if source:
            source.pop("url", None)
            sources[folder_name] = source
            _save_sources(sources)
    return jsonify({"ok": True})


@app.route("/api/playlist/sync", methods=["POST"])
def sync_playlist():
    data = request.get_json() or {}
    folder_name = str(data.get("folder_name", "")).strip()
    if _existing_playlist_folder(folder_name) is None:
        return jsonify({"error": "folder_not_found"}), 404
    with _sources_lock:
        saved_url = _load_sources().get(folder_name, {}).get("url")
    url = str(data.get("url") or saved_url or "").strip()
    if not url:
        return jsonify({"error": "url_required"}), 409
    if not _is_soundcloud_url(url):
        return jsonify({"error": "invalid_soundcloud_url"}), 400
    with _syncing_lock:
        if folder_name in _syncing_folders:
            return jsonify({"error": "already_syncing"}), 409
        _syncing_folders.add(folder_name)
    if data.get("url"):
        _set_source(folder_name, url)
    job_id = str(uuid.uuid4())
    with jobs_lock:
        jobs[job_id] = {"status": "queued", "files": [], "error": None, "folder": folder_name}
    try:
        threading.Thread(target=run_scdl_playlist, args=(job_id, url, folder_name), daemon=True).start()
    except Exception:
        with _syncing_lock:
            _syncing_folders.discard(folder_name)
        raise
    return jsonify({"job_id": job_id})

@app.route("/api/playlist/info", methods=["POST"])
def playlist_info():
    """Devuelve info de una playlist + cuántas canciones ya están descargadas."""
    data = request.get_json() or {}
    url = data.get("url", "").strip()
    folder_name = _sanitize_folder_name(data.get("folder_name", "").strip())
    if not url:
        return jsonify({"error": "URL requerida"}), 400

    # Canciones ya en la carpeta
    existing = 0
    if folder_name:
        folder_path = DOWNLOAD_DIR / folder_name
        audio_exts = {'.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus'}
        if folder_path.is_dir():
            existing = sum(1 for f in folder_path.iterdir() if f.suffix.lower() in audio_exts)

    return jsonify({"existing": existing, "folder": folder_name})

@app.route("/api/download", methods=["POST"])
def start_download():
    data = request.get_json()
    url = (data or {}).get("url", "").strip()
    if not url or "soundcloud.com" not in url:
        return jsonify({"error": "URL de SoundCloud requerida"}), 400
    job_id = str(uuid.uuid4())
    with jobs_lock:
        jobs[job_id] = {"status": "queued", "files": [], "error": None}
    threading.Thread(target=run_scdl, args=(job_id, url), daemon=True).start()
    return jsonify({"job_id": job_id})


@app.route("/api/status/<job_id>")
def job_status(job_id):
    with jobs_lock:
        job = jobs.get(job_id)
    if not job:
        return jsonify({"error": "Not found"}), 404
    return jsonify(job)


@app.route("/api/file/<job_id>/<filename>")
def serve_file(job_id, filename):
    safe_name = Path(filename).name
    file_path = DOWNLOAD_DIR / job_id / safe_name
    if not file_path.exists():
        return jsonify({"error": "Not found"}), 404
    return send_file(file_path, as_attachment=True)


# ════════════════════════════════════════════════════════
# ARTWORK & METADATA
# ════════════════════════════════════════════════════════

@app.route("/api/artwork/<path:filepath>")
def get_artwork(filepath):
    """Extract and serve embedded artwork from MP3."""
    safe_parts = Path(filepath).parts
    target = DOWNLOAD_DIR.joinpath(*safe_parts).resolve()
    if not str(target).startswith(str(DOWNLOAD_DIR)) or not target.is_file():
        return "Not found", 404
    try:
        tags = ID3(str(target))
        for key in tags.keys():
            if key.startswith("APIC"):
                art = tags[key]
                return Response(art.data, mimetype=art.mime,
                                headers={"Cache-Control": "public, max-age=604800"})
    except Exception:
        pass
    return "No artwork", 404


@app.route("/api/metadata/<path:filepath>")
def get_metadata(filepath):
    """Get metadata for a single track."""
    safe_parts = Path(filepath).parts
    target = DOWNLOAD_DIR.joinpath(*safe_parts).resolve()
    if not str(target).startswith(str(DOWNLOAD_DIR)) or not target.is_file():
        return jsonify({"error": "Not found"}), 404
    meta = _extract_metadata(target)
    key = _get_track_key(*safe_parts[:2]) if len(safe_parts) >= 2 else filepath
    with _stats_lock:
        stats = _load_stats()
        meta["play_count"] = stats.get(key, {}).get("count", 0)
    return jsonify(meta)


@app.route("/api/metadata/batch", methods=["POST"])
def get_metadata_batch():
    """Get metadata for multiple tracks at once. Body: { paths: ["folder/file.mp3", ...] }"""
    data = request.get_json() or {}
    paths = data.get("paths", [])
    if not paths:
        return jsonify({})

    with _meta_lock:
        cache = _load_meta_cache()

    with _stats_lock:
        stats = _load_stats()

    result = {}
    updated = False
    for p in paths[:500]:  # limit
        safe_parts = Path(p).parts
        target = DOWNLOAD_DIR.joinpath(*safe_parts).resolve()
        if not str(target).startswith(str(DOWNLOAD_DIR)) or not target.is_file():
            continue
        mtime = str(target.stat().st_mtime)
        cache_key = p
        if cache_key in cache and cache[cache_key].get("_mtime") == mtime:
            meta = cache[cache_key]
        else:
            meta = _extract_metadata(target)
            meta["_mtime"] = mtime
            cache[cache_key] = meta
            updated = True
        key = _get_track_key(*safe_parts[:2]) if len(safe_parts) >= 2 else p
        entry = {k: v for k, v in meta.items() if k != "_mtime"}
        entry["play_count"] = stats.get(key, {}).get("count", 0)
        result[p] = entry

    if updated:
        with _meta_lock:
            _save_meta_cache(cache)

    return jsonify(result)


@app.route("/api/play", methods=["POST"])
def record_play():
    """Record a play event. Body: { track: "folder/file.mp3" }"""
    data = request.get_json() or {}
    track = data.get("track", "").strip()
    if not track:
        return jsonify({"error": "No track"}), 400
    with _stats_lock:
        stats = _load_stats()
        if track not in stats:
            stats[track] = {"count": 0, "first": time.time(), "last": 0}
        stats[track]["count"] += 1
        stats[track]["last"] = time.time()
        _save_stats(stats)
    return jsonify({"ok": True, "count": stats[track]["count"]})


@app.route("/api/stats")
def get_stats():
    """Get all play stats."""
    with _stats_lock:
        stats = _load_stats()
    return jsonify(stats)


# ════════════════════════════════════════════════════════
# LIKES
# ════════════════════════════════════════════════════════

@app.route("/api/likes", methods=["GET"])
def get_likes():
    """Return liked tracks as {relPath: true} — reads from play_stats.json."""
    with _stats_lock:
        stats = _load_stats()
    liked = {k: True for k in stats if isinstance(stats.get(resolve_cloud_track(k)), dict) and stats[resolve_cloud_track(k)].get("liked")}
    return jsonify(liked)


@app.route("/api/like", methods=["POST"])
def toggle_like():
    """Toggle like for a track inside play_stats.json. Body: {track: "folder/file.mp3"}"""
    data = request.get_json(force=True) or {}
    track = data.get("track", "").strip()
    if not track:
        return jsonify({"error": "missing track"}), 400
    desired = data.get("liked")
    if "liked" in data and not isinstance(desired, bool):
        return jsonify({"error": "liked must be a boolean"}), 400
    with _stats_lock:
        track = resolve_cloud_track(track)
        stats = _load_stats()
        entry = stats.get(track)
        if not isinstance(entry, dict):
            entry = {"count": entry if isinstance(entry, int) else 0}
        liked = desired if isinstance(desired, bool) else not entry.get("liked", False)
        entry["liked"] = liked
        stats[track] = entry
        _save_stats(stats)
    return jsonify({"ok": True, "liked": liked, "total": sum(1 for v in stats.values() if isinstance(v, dict) and v.get("liked"))})


# ════════════════════════════════════════════════════════
# ════════════════════════════════════════════════════════
# PLAYLISTS — per-user, stored as JSON in playlists/<user>/
# ════════════════════════════════════════════════════════
PLAYLISTS_DIR = BASE_DIR / "playlists"
PLAYLISTS_DIR.mkdir(exist_ok=True)


def _safe_name(s):
    """Sanitize to filesystem-safe name."""
    s = re.sub(r'[^\w\s\-]', '', s.strip())
    return s[:64] or "unnamed"


def _user_dir(user):
    d = PLAYLISTS_DIR / _safe_name(user)
    d.mkdir(exist_ok=True)
    return d


@app.route("/api/playlists/<user>")
def list_playlists(user):
    """List all playlists for a user."""
    d = _user_dir(user)
    playlists = []
    for f in sorted(d.glob("*.json")):
        try:
            data = json.loads(f.read_text())
            playlists.append({
                "id": f.stem,
                "name": data.get("name", f.stem),
                "count": len(data.get("tracks", [])),
                "created": data.get("created"),
                "updated": data.get("updated")
            })
        except Exception:
            continue
    return jsonify(playlists)


@app.route("/api/playlists/<user>/<playlist_id>")
def get_playlist(user, playlist_id):
    """Get a specific playlist with track references."""
    f = _user_dir(user) / (_safe_name(playlist_id) + ".json")
    if not f.exists():
        return jsonify({"error": "Not found"}), 404
    data = json.loads(f.read_text())
    return jsonify(data)


@app.route("/api/playlists/<user>", methods=["POST"])
def create_playlist(user):
    """Create a new playlist. Body: { name, tracks?: [...] }"""
    body = request.get_json() or {}
    name = (body.get("name") or "").strip()
    if not name:
        return jsonify({"error": "Name required"}), 400
    pid = _safe_name(name).lower().replace(" ", "-")
    f = _user_dir(user) / (pid + ".json")
    now = time.time()
    data = {
        "name": name,
        "tracks": body.get("tracks", []),
        "created": now,
        "updated": now
    }
    f.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    return jsonify({"ok": True, "id": pid, "name": name})


@app.route("/api/playlists/<user>/<playlist_id>", methods=["PUT"])
def update_playlist(user, playlist_id):
    """Update playlist. Body: { name?, tracks? }"""
    f = _user_dir(user) / (_safe_name(playlist_id) + ".json")
    if not f.exists():
        return jsonify({"error": "Not found"}), 404
    data = json.loads(f.read_text())
    body = request.get_json() or {}
    if "name" in body:
        data["name"] = body["name"]
    if "tracks" in body:
        data["tracks"] = body["tracks"]
    data["updated"] = time.time()
    f.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    return jsonify({"ok": True})


@app.route("/api/playlists/<user>/<playlist_id>/add", methods=["POST"])
def add_to_playlist(user, playlist_id):
    """Add tracks to playlist. Body: { tracks: ["folder/file.mp3", ...] }"""
    f = _user_dir(user) / (_safe_name(playlist_id) + ".json")
    if not f.exists():
        return jsonify({"error": "Not found"}), 404
    data = json.loads(f.read_text())
    body = request.get_json() or {}
    new_tracks = body.get("tracks", [])
    existing = set(data["tracks"])
    for t in new_tracks:
        if t not in existing:
            data["tracks"].append(t)
            existing.add(t)
    data["updated"] = time.time()
    f.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    return jsonify({"ok": True, "count": len(data["tracks"])})


@app.route("/api/playlists/<user>/<playlist_id>/remove", methods=["POST"])
def remove_from_playlist(user, playlist_id):
    """Remove tracks from playlist. Body: { tracks: ["folder/file.mp3", ...] }"""
    f = _user_dir(user) / (_safe_name(playlist_id) + ".json")
    if not f.exists():
        return jsonify({"error": "Not found"}), 404
    data = json.loads(f.read_text())
    body = request.get_json() or {}
    to_remove = set(body.get("tracks", []))
    data["tracks"] = [t for t in data["tracks"] if t not in to_remove]
    data["updated"] = time.time()
    f.write_text(json.dumps(data, ensure_ascii=False, indent=1))
    return jsonify({"ok": True, "count": len(data["tracks"])})


@app.route("/api/playlists/<user>/<playlist_id>", methods=["DELETE"])
def delete_playlist(user, playlist_id):
    """Delete a playlist."""
    f = _user_dir(user) / (_safe_name(playlist_id) + ".json")
    if f.exists():
        f.unlink()
    return jsonify({"ok": True})


# ════════════════════════════════════════════════════════
# PARTY MODE — Pure polling, ZERO long-lived connections
# ════════════════════════════════════════════════════════
party_rooms = {}   # { code: { host_id, state, members: {cid: last_seen_ts}, last_sync } }
party_lock = threading.Lock()


def _party_cleanup():
    """Remove inactive rooms (no sync in 5 min) and stale members (no poll in 30s)."""
    while True:
        time.sleep(30)
        now = time.time()
        with party_lock:
            # Clean stale members
            for code, room in list(party_rooms.items()):
                stale = [cid for cid, ts in room["members"].items() if now - ts > 30]
                for cid in stale:
                    del room["members"][cid]
            # Clean dead rooms
            dead = [c for c, r in party_rooms.items() if now - r.get("last_sync", 0) > 300]
            for c in dead:
                del party_rooms[c]

threading.Thread(target=_party_cleanup, daemon=True).start()


# ════════════════════════════════════════════════════════
# REMOTE CONTROL — for Siri Shortcuts / Apple Watch
# ════════════════════════════════════════════════════════
REMOTE_TOKEN_FILE = BASE_DIR / "remote_token.txt"


def _get_remote_token():
    env_token = os.environ.get("REMOTE_TOKEN", "").strip()
    if env_token:
        return env_token
    if REMOTE_TOKEN_FILE.exists():
        return REMOTE_TOKEN_FILE.read_text().strip()
    token = uuid.uuid4().hex
    REMOTE_TOKEN_FILE.write_text(token)
    return token


REMOTE_TOKEN = _get_remote_token()
remote_lock = threading.Lock()
remote_state = {"seq": 0, "url": None, "name": None, "folder": None, "filename": None, "sent_at": 0}


def _remote_authorized(data):
    token = (data or {}).get("token") or request.args.get("token") or request.headers.get("X-Remote-Token")
    return token == REMOTE_TOKEN


@app.route("/api/remote/play", methods=["POST"])
def remote_play():
    """Called by a Siri Shortcut to make the active player load & play a track."""
    data = request.get_json() or {}
    if not _remote_authorized(data):
        return jsonify({"error": "unauthorized"}), 401
    rel_path = data.get("relPath")
    if rel_path:
        folder, _, filename = rel_path.partition("/")
    else:
        folder, filename = data.get("folder"), data.get("filename")
    if not folder or not filename:
        return jsonify({"error": "relPath, or folder and filename, required"}), 400
    track_path = DOWNLOAD_DIR / folder / filename
    if not track_path.is_file():
        return jsonify({"error": "track not found"}), 404
    with remote_lock:
        remote_state["seq"] += 1
        remote_state.update({
            "url": f"/api/file/{folder}/{filename}",
            "name": track_path.stem,
            "folder": folder,
            "filename": filename,
            "sent_at": time.time(),
        })
        state = dict(remote_state)
    return jsonify({"ok": True, "seq": state["seq"]})


@app.route("/api/remote/poll")
def remote_poll():
    """Polled by the web player to pick up remote-play commands."""
    since = request.args.get("since", 0, type=int)
    with remote_lock:
        state = dict(remote_state)
    state["changed"] = state["seq"] > since
    return jsonify(state)


@app.route("/api/party/create", methods=["POST"])
def party_create():
    code = uuid.uuid4().hex[:6].upper()
    host_id = str(uuid.uuid4())
    with party_lock:
        party_rooms[code] = {
            "host_id": host_id,
            "members": {},
            "state": {"track_idx": -1, "track_url": None, "track_time": 0, "playing": False, "sent_at": time.time()},
            "last_sync": time.time(),
            "mode": "host_only"
        }
    return jsonify({"code": code, "host_id": host_id})


@app.route("/api/party/<code>/sync", methods=["POST"])
def party_sync(code):
    """Host pushes state. Returns member count."""
    data = request.get_json() or {}
    with party_lock:
        room = party_rooms.get(code)
        if not room:
            return jsonify({"error": "Room not found"}), 404
        if room["host_id"] != data.get("host_id"):
            return jsonify({"error": "Not host"}), 403
        prev_changed_by = room["state"].get("changed_by")
        new_state = {
            "track_idx": data.get("track_idx", -1),
            "track_url": data.get("track_url"),
            "track_time": data.get("track_time", 0),
            "playing": data.get("playing", False),
            "sent_at": time.time(),
            "changed_by": data.get("changed_by") or prev_changed_by
        }
        room["state"] = new_state
        room["last_sync"] = time.time()
        member_count = len(room["members"]) + 1
    return jsonify({"ok": True, "members": member_count})


@app.route("/api/party/<code>/request", methods=["POST"])
def party_request(code):
    """Any member can request a track change. Updates room state for all pollers."""
    data = request.get_json() or {}
    with party_lock:
        room = party_rooms.get(code)
        if not room:
            return jsonify({"error": "Room not found"}), 404
        # Register member if needed
        cid = data.get("client_id", "anon")
        room["members"][cid] = time.time()
        room["state"] = {
            "track_idx": data.get("track_idx", -1),
            "track_url": data.get("track_url"),
            "track_name": data.get("track_name", ""),
            "track_time": data.get("track_time", 0),
            "playing": data.get("playing", True),
            "sent_at": time.time(),
            "changed_by": data.get("name", "Alguien")
        }
        room["last_sync"] = time.time()
        member_count = len(room["members"]) + 1
    return jsonify({"ok": True, "members": member_count})


@app.route("/api/party/<code>/poll")
def party_poll(code):
    """Members poll this to get current state. Lightweight, instant response."""
    client_id = request.args.get("client_id", "anon")
    user_json = request.args.get("user")
    with party_lock:
        room = party_rooms.get(code)
        if not room:
            return jsonify({"error": "Room not found", "closed": True}), 404
        room["members"][client_id] = time.time()
        state = dict(room["state"])
        state["members"] = len(room["members"]) + 1
        state["mode"] = room.get("mode", "host_only")
    return jsonify(state)


@app.route("/api/party/<code>/set-mode", methods=["POST"])
def party_set_mode(code):
    data = request.get_json() or {}
    with party_lock:
        room = party_rooms.get(code)
        if not room:
            return jsonify({"error": "Room not found"}), 404
        if room["host_id"] != data.get("host_id"):
            return jsonify({"error": "Not host"}), 403
        room["mode"] = data.get("mode", "host_only")
    return jsonify({"ok": True, "mode": room["mode"]})


@app.route("/api/party/<code>/leave", methods=["POST"])
def party_leave(code):
    data = request.get_json() or {}
    with party_lock:
        room = party_rooms.get(code)
        if not room:
            return jsonify({"ok": True})
        if room["host_id"] == data.get("host_id"):
            del party_rooms[code]
        else:
            cid = data.get("client_id")
            if cid and cid in room["members"]:
                del room["members"][cid]
    return jsonify({"ok": True})


@app.route("/api/party/active", methods=["GET"])
def party_active():
    """Returns all active rooms for nearby scan."""
    now = time.time()
    result = []
    with party_lock:
        for code, room in party_rooms.items():
            if now - room.get("last_sync", 0) > 60:
                continue  # skip stale rooms
            state = room.get("state", {})
            result.append({
                "code": code,
                "members": len(room["members"]) + 1,
                "mode": room.get("mode", "host_only"),
                "host_name": room.get("host_name", "Unknown"),
                "host_avatar": room.get("host_avatar", "?"),
                "host_color": room.get("host_color", "#888"),
                "track_name": state.get("track_name", ""),
                "playing": state.get("playing", False),
                "last_sync": room.get("last_sync", 0)
            })
    result.sort(key=lambda x: -x["members"])
    return jsonify({"rooms": result})


@app.route("/api/party/<code>/announce", methods=["POST"])
def party_announce(code):
    """Host announces their name/avatar so nearby scan shows it."""
    data = request.get_json() or {}
    with party_lock:
        room = party_rooms.get(code)
        if not room:
            return jsonify({"error": "Room not found"}), 404
        if room["host_id"] != data.get("host_id"):
            return jsonify({"error": "Not host"}), 403
        room["host_name"] = data.get("name", "Host")
        room["host_avatar"] = data.get("initial", "?")
        room["host_color"] = data.get("color", "#888")
        # Also store current track name in state for display
        room["state"]["track_name"] = data.get("track_name", "")
    return jsonify({"ok": True})


# ════════════════════════════════════════════════════════
# Disabled endpoints (kept for compatibility)
# ════════════════════════════════════════════════════════
@app.route("/api/events")
def sse_disabled():
    return jsonify({"status": "disabled"}), 200


# ════════════════════════════════════════════════════════
# MAIN — Plain threaded Flask, no gevent needed
# ════════════════════════════════════════════════════════
if __name__ == "__main__":
    print("[SoundDrop] Starting on port 5002 (threaded, nginx proxy on 5000)")
    app.run(host="127.0.0.1", port=5002, debug=False, threaded=True)
