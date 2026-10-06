"""Versioned, additive folder uploads shared by Wave desktop and iOS."""
import hashlib
import json
import os
import shutil
import threading
import time
import uuid
from pathlib import Path
from urllib.parse import quote
from flask import Blueprint, jsonify, request, send_file

AUDIO = {'.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.opus', '.aiff', '.aif', '.webm'}


def register_cloud_api(app, base, stats_lock):
    base = Path(base)
    library = (base / 'downloads').resolve()
    cloud = base / '.wave-cloud'
    blobs = cloud / 'blobs'
    journals = cloud / 'operations'
    for directory in (blobs, journals):
        directory.mkdir(parents=True, exist_ok=True)
    cache_file = cloud / 'hash-cache.json'
    hashes = json.loads(cache_file.read_text()) if cache_file.exists() else {}
    aliases_file = cloud / 'aliases.json'
    lock = threading.RLock()
    api = Blueprint('cloud', __name__)

    def atomic(file, value):
        temp = file.with_name(file.name + '.' + uuid.uuid4().hex + '.tmp')
        temp.write_text(json.dumps(value, ensure_ascii=False))
        os.replace(temp, file)

    def target(value, audio=True):
        if not isinstance(value, str) or not value or len(value) > 1500 or '\\' in value:
            raise ValueError('Ruta no válida.')
        parts = value.split('/')
        if len(parts) < (2 if audio else 1) or any(not p or p in ('.', '..') or p.startswith('.') for p in parts):
            raise ValueError('Ruta no válida.')
        result = library.joinpath(*parts)
        if not result.resolve().is_relative_to(library) or any(p.is_symlink() for p in [result, *result.parents] if p != library.parent):
            raise ValueError('Ruta fuera de la biblioteca.')
        if audio and result.suffix.lower() not in AUDIO:
            raise ValueError('Formato no admitido.')
        return result

    def digest(file):
        h = hashlib.sha256()
        with file.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                h.update(chunk)
        return h.hexdigest()

    def store(file):
        key = digest(file)
        dest = blobs / key
        if not dest.exists():
            tmp = blobs / (key + '.' + uuid.uuid4().hex)
            shutil.copyfile(file, tmp)
            os.replace(tmp, dest)
        return key

    def current(path):
        file = target(path)
        return digest(file) if file.is_file() else None

    def install(path, key):
        file = target(path)
        if key is None:
            file.unlink(missing_ok=True)
            return
        file.parent.mkdir(parents=True, exist_ok=True)
        temp = file.with_name('.wave-' + uuid.uuid4().hex)
        shutil.copyfile(blobs / key, temp)
        os.replace(temp, file)

    alias_cache = {'mtime': None, 'value': {}}
    def canonical(path):
        mtime = aliases_file.stat().st_mtime_ns if aliases_file.exists() else None
        if alias_cache['mtime'] != mtime:
            alias_cache['value'] = json.loads(aliases_file.read_text()) if mtime else {}
            alias_cache['mtime'] = mtime
        aliases = alias_cache['value']
        seen = set()
        while path in aliases and path not in seen:
            seen.add(path)
            path = aliases[path]
        return path

    def operation(identifier):
        if not isinstance(identifier, str) or not identifier.isalnum() or len(identifier) != 32:
            raise ValueError('Actualización no válida.')
        file = journals / (identifier + '.json')
        if not file.exists():
            raise ValueError('Actualización no encontrada.')
        return file, json.loads(file.read_text())

    def commit(changes):
        before = {p: current(p) for p in changes}
        changed = {p: key for p, key in changes.items() if before[p] != key}
        for p in changed:
            if before[p] is not None:
                store(target(p))
        identifier = uuid.uuid4().hex
        value = {'id': identifier, 'created': time.time(), 'expires': time.time() + 1800,
                 'before': {p: before[p] for p in changed}, 'after': changed, 'status': 'prepared'}
        journal = journals / (identifier + '.json')
        atomic(journal, value)
        try:
            for p, key in changed.items():
                install(p, key)
            value['status'] = 'committed'
            atomic(journal, value)
        except Exception:
            for p, key in value['before'].items():
                install(p, key)
            value['status'] = 'failed'
            atomic(journal, value)
            raise
        return {'id': identifier, 'expires': value['expires'], 'changed': len(changed)}

    # Recover a file transaction interrupted during process shutdown.
    for journal in journals.glob('*.json'):
        value = json.loads(journal.read_text())
        if value.get('status') == 'prepared':
            for p, key in value['before'].items():
                install(p, key)
            value['status'] = 'failed'
            atomic(journal, value)

    @api.errorhandler(ValueError)
    def invalid(error):
        return jsonify(error=str(error)), 400

    @api.get('/api/cloud/manifest')
    def manifest():
        with lock:
            tracks = []
            for file in sorted(library.rglob('*')):
                if not file.is_file() or file.suffix.lower() not in AUDIO:
                    continue
                path = file.relative_to(library).as_posix()
                try:
                    target(path)
                except ValueError:
                    continue
                signature = [file.stat().st_size, file.stat().st_mtime_ns, file.stat().st_ino]
                cached = hashes.get(path, {})
                key = cached.get('hash') if cached.get('signature') == signature else digest(file)
                hashes[path] = {'signature': signature, 'hash': key}
                tracks.append({'path': path, 'hash': key, 'size': file.stat().st_size,
                               'url': '/api/cloud/blob/' + key})
            atomic(cache_file, hashes)
            revision = hashlib.sha256(json.dumps(tracks, sort_keys=True).encode()).hexdigest()
            return jsonify(revision=revision, tracks=tracks, folders=sorted({t['path'].split('/')[0] for t in tracks})), 200, {'Cache-Control': 'no-store'}

    @api.get('/api/cloud/blob/<key>')
    def blob(key):
        if len(key) != 64 or any(c not in '0123456789abcdef' for c in key):
            return jsonify(error='Audio no encontrado.'), 404
        with lock:
            file = blobs / key
            if not file.is_file():
                file = None
                for relative, cached in hashes.items():
                    if cached['hash'] == key:
                        candidate = target(relative)
                        if candidate.is_file() and digest(candidate) == key:
                            file = candidate
                            break
                if file is None:
                    return jsonify(error='El audio ha cambiado. Actualiza de nuevo.'), 409
            return send_file(file, mimetype='application/octet-stream', conditional=True)

    @api.post('/api/cloud/upload')
    def begin():
        identifier = uuid.uuid4().hex
        atomic(journals / (identifier + '.json'), {'id': identifier, 'created': time.time(), 'status': 'uploading', 'files': {}, 'expected': {}})
        return jsonify(id=identifier)

    @api.put('/api/cloud/upload/<identifier>')
    def upload(identifier):
        path = request.args.get('path')
        target(path)
        with lock:
            journal, value = operation(identifier)
            if value['status'] != 'uploading' or time.time() - value['created'] > 86400:
                return jsonify(error='La subida ha caducado.'), 409
            # Limit individual uploads without loading audio into memory.
            temp = cloud / ('upload-' + uuid.uuid4().hex)
            try:
                size = 0
                with temp.open('wb') as out:
                    while True:
                        chunk = request.stream.read(1024 * 1024)
                        if not chunk:
                            break
                        size += len(chunk)
                        if size > 512 * 1024 * 1024:
                            return jsonify(error='El archivo supera 512 MB.'), 413
                        if shutil.disk_usage(cloud).free < len(chunk) + 50 * 1024 * 1024:
                            return jsonify(error='El servidor no tiene espacio suficiente para esta subida.'), 507
                        out.write(chunk)
                if size == 0:
                    raise ValueError('Archivo vacío.')
                key = digest(temp)
                if not (blobs / key).exists():
                    os.replace(temp, blobs / key)
                value['files'][path] = key
                value['expected'].setdefault(path, current(path))
                atomic(journal, value)
                return jsonify(hash=key)
            finally:
                temp.unlink(missing_ok=True)

    @api.post('/api/cloud/upload/<identifier>/commit')
    def finish(identifier):
        with lock:
            journal, value = operation(identifier)
            if value['status'] == 'finished':
                return jsonify(value['result'])
            if value['status'] != 'uploading' or not value['files'] or time.time() - value['created'] > 86400:
                return jsonify(error='Subida incompleta o caducada.'), 409
            if any(current(p) not in (value['expected'][p], key) for p, key in value['files'].items()):
                return jsonify(error='Otra plataforma ha actualizado esta carpeta. Vuelve a subirla.'), 409
            result = commit(value['files'])
            value.update(status='finished', result=result)
            atomic(journal, value)
            return jsonify(result)

    @api.get('/api/cloud/history')
    def history():
        with lock:
            values = [json.loads(p.read_text()) for p in journals.glob('*.json')]
            return jsonify([{'id': v['id'], 'expires': v['expires'], 'changed': len(v['after'])}
                            for v in sorted(values, key=lambda v: v['created'], reverse=True)
                            if v['status'] == 'committed' and v['expires'] > time.time()]), 200, {'Cache-Control': 'no-store'}

    @api.post('/api/cloud/undo/<identifier>')
    def undo(identifier):
        with lock:
            journal, value = operation(identifier)
            if value['status'] == 'undone':
                return jsonify(ok=True)
            if value['status'] != 'committed' or time.time() > value['expires']:
                return jsonify(error='El plazo de 30 minutos ha terminado.'), 409
            if any(current(p) != key for p, key in value['after'].items()):
                return jsonify(error='Hay cambios posteriores. No se pueden sobrescribir al deshacer.'), 409
            # A second journal makes undo itself recoverable after a crash.
            commit(value['before'])
            if 'relocation' in value:
                source, destination = value['relocation']
                with stats_lock:
                    stats_file = base / 'play_stats.json'
                    stats = json.loads(stats_file.read_text()) if stats_file.exists() else {}
                    if destination in stats:
                        stats[source] = dict(stats[destination])
                        atomic(stats_file, stats)
                    aliases = json.loads(aliases_file.read_text()) if aliases_file.exists() else {}
                    aliases.pop(source, None)
                    aliases[destination] = source
                    atomic(aliases_file, aliases)
            value['status'] = 'undone' 
            atomic(journal, value)
            return jsonify(ok=True)

    @api.post('/api/cloud/relocate')
    def relocate():
        data = request.get_json(silent=True) or {}
        source = data.get('track')
        file = target(source)
        folder = data.get('folder')
        dest = target(folder, audio=False)
        if not file.is_file() or not dest.is_dir():
            raise ValueError('Canción o carpeta no encontrada.')
        destination = folder + '/' + file.name
        with lock, stats_lock:
            if destination == source:
                return jsonify(path=source, changed=0)
            if target(destination).exists():
                return jsonify(error='Ya existe una canción con ese nombre en el destino.'), 409
            result = commit({source: None, destination: store(file)})
            # Keep both heart aliases so reverting the file move preserves likes.
            stats_file = base / 'play_stats.json'
            stats = json.loads(stats_file.read_text()) if stats_file.exists() else {}
            if source in stats:
                stats[destination] = dict(stats[source])
                atomic(stats_file, stats)
            aliases = json.loads(aliases_file.read_text()) if aliases_file.exists() else {}
            aliases.pop(destination, None)
            aliases[source] = destination
            atomic(aliases_file, aliases)
            journal, value = operation(result['id'])
            value['relocation'] = [source, destination]
            atomic(journal, value)
            return jsonify(path=destination, **result)

    app.register_blueprint(api)
    return canonical
