"""Desktop library organization and Spotify token relay. No secrets in the app bundle."""
import json
import os
import re
import threading
import time
import uuid
from collections import defaultdict, deque
from pathlib import Path

import requests
from flask import Blueprint, jsonify, request


def register_desktop_api(app, base_dir):
    base_dir = Path(base_dir)
    library = (base_dir / 'downloads').resolve()
    state_file = library / '.wave-library.json'
    lock = threading.Lock()
    token_lock = threading.Lock()
    token = {'access_token': '', 'expires_at': 0}
    attempts = defaultdict(deque)
    attempt_lock = threading.Lock()
    api = Blueprint('desktop_api', __name__)

    def credentials():
        values = {}
        env = base_dir / '.env'
        if env.exists():
            for line in env.read_text().splitlines():
                if line.strip().startswith('#') or '=' not in line:
                    continue
                key, value = line.split('=', 1)
                values[key.strip()] = value.strip().strip('\"\'')
        return (os.environ.get('SPOTIFY_CLIENT_ID') or values.get('SPOTIFY_CLIENT_ID', ''),
                os.environ.get('SPOTIFY_CLIENT_SECRET') or values.get('SPOTIFY_CLIENT_SECRET', ''))

    def read_state():
        if not state_file.exists():
            return {'hidden': [], 'orders': {}}
        if state_file.is_symlink():
            raise ValueError('Archivo de organización no válido.')
        value = json.loads(state_file.read_text())
        return {'hidden': value.get('hidden', []), 'orders': value.get('orders', {})}

    def valid_track(value):
        if not isinstance(value, str) or len(value) > 2000 or '\\' in value:
            return False
        parts = Path(value)
        if parts.is_absolute() or '..' in parts.parts:
            return False
        target = (library / parts).resolve()
        try:
            target.relative_to(library)
        except ValueError:
            return False
        return target.is_file() and target.suffix.lower() in {'.mp3', '.m4a', '.flac', '.wav', '.ogg', '.opus', '.aac', '.aiff', '.webm'}

    @api.route('/api/desktop/state', methods=['GET', 'POST'])
    def library_state():
        with lock:
            try:
                state = read_state()
                if request.method == 'POST':
                    data = request.get_json(silent=True) or {}
                    paths = data.get('paths')
                    if not isinstance(paths, list) or len(paths) > 50000 or any(not valid_track(p) for p in paths) or len(set(paths)) != len(paths):
                        return jsonify(error='Selección de canciones no válida.'), 400
                    if data.get('action') == 'hidden' and paths and isinstance(data.get('hidden'), bool):
                        hidden = set(state['hidden'])
                        for item in paths:
                            if data['hidden']:
                                hidden.add(item)
                            else:
                                hidden.discard(item)
                        state['hidden'] = sorted(hidden)
                    elif data.get('action') == 'order':
                        scope = data.get('scope')
                        if not isinstance(scope, str) or len(scope) > 2000 or scope.startswith('/') or '\\' in scope or '..' in Path(scope).parts:
                            return jsonify(error='Carpeta no válida.'), 400
                        if scope != '*':
                            target = (library / scope).resolve()
                            try:
                                target.relative_to(library)
                            except ValueError:
                                return jsonify(error='Carpeta no válida.'), 400
                            if not target.is_dir():
                                return jsonify(error='Carpeta no válida.'), 400
                        state['orders'][scope] = paths
                    else:
                        return jsonify(error='Operación no válida.'), 400
                    temp = state_file.with_name('.wave-state-' + uuid.uuid4().hex + '.tmp')
                    try:
                        temp.write_text(json.dumps(state, ensure_ascii=False, indent=2))
                        temp.replace(state_file)
                    finally:
                        temp.unlink(missing_ok=True)
                return jsonify(state)
            except (OSError, ValueError, TypeError):
                return jsonify(error='No se pudo leer o guardar la organización de la biblioteca.'), 500

    @api.get('/api/spotify/status')
    def spotify_status():
        client_id, secret = credentials()
        return jsonify(configured=bool(client_id and secret), mode='desktop-catalog-search')

    @api.post('/api/spotify/search-token')
    def spotify_token():
        # Only an app-scoped, short-lived token; never user credentials or the client secret.
        # Cache tokens and limit requests per caller to protect the Spotify app quota.
        now = time.time()
        caller = request.remote_addr or 'unknown'
        with attempt_lock:
            if len(attempts) > 1000:
                for key in list(attempts):
                    if not attempts[key] or attempts[key][-1] < now - 60:
                        del attempts[key]
            queue = attempts[caller]
            while queue and queue[0] < now - 60:
                queue.popleft()
            if len(queue) >= 20:
                return jsonify(error='Demasiadas solicitudes. Espera un minuto.'), 429, {'Retry-After': '60'}
            queue.append(now)
        client_id, secret = credentials()
        if not client_id or not secret:
            return jsonify(error='Spotify no está configurado en el servidor.'), 503
        with token_lock:
            if token['expires_at'] > now + 60:
                return jsonify(access_token=token['access_token'], expires_in=int(token['expires_at'] - now)), 200, {'Cache-Control': 'no-store'}
            try:
                response = requests.post('https://accounts.spotify.com/api/token', auth=(client_id, secret), data={'grant_type': 'client_credentials'}, timeout=15)
                if response.status_code == 429:
                    return jsonify(error='Spotify ha limitado temporalmente las solicitudes.'), 429, {'Retry-After': response.headers.get('Retry-After', '60')}
                if not response.ok:
                    return jsonify(error='Spotify no ha aceptado las credenciales del servidor.'), 502
                data = response.json()
                token.update(access_token=data['access_token'], expires_at=time.time() + int(data['expires_in']))
                return jsonify(access_token=token['access_token'], expires_in=int(data['expires_in'])), 200, {'Cache-Control': 'no-store'}
            except (requests.RequestException, ValueError, KeyError):
                return jsonify(error='No se pudo obtener una sesión de búsqueda de Spotify.'), 502

    app.register_blueprint(api)
