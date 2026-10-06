# Wave — Playlists de Spotify + links de compartir

Estado: PROPUESTO (pendiente de aprobacion)
Fecha: 2026-08-05
Alcance: `app.py`, nuevo `providers.py`, `static/index.html`, `requirements.txt`

## Objetivo

1. Aceptar en SoundDrop el link de **compartir/copiar link** (el corto de la app movil),
   no solo el que sale en la barra del navegador. SoundCloud y Spotify.
2. Importar **playlists de Spotify** a la biblioteca del servidor, reusando el pipeline
   `scdl` que ya existe.

---

## 0. Hallazgos verificados en este servidor (2026-08-05)

Esto condiciona toda la arquitectura. Comprobado con curl/python desde la maquina:

| Endpoint | Resultado |
|---|---|
| `accounts.spotify.com/api/token` | **403 Forbidden** (pagina de error de Google, bloqueo por IP de datacenter) |
| `api.spotify.com/v1/...` | **403 Forbidden** (mismo bloqueo) |
| `open.spotify.com/embed/<tipo>/<id>` | **200**, con `__NEXT_DATA__` completo |
| `api-v2.soundcloud.com/search/tracks` | **200** con `client_id` scrapeado del web player |
| `music.youtube.com` | 200, pero `spotdl` falla su propio `check_ytmusic_connection()` |

Consecuencias:

- **`spotdl` (4.4.3, ya instalado via pipx) no sirve.** Probado: falla dos veces, primero
  por el chequeo de YouTube Music y luego por 403 en el token de Spotify. No es
  configuracion, es la IP del servidor. Descartado.
- **La API oficial de Spotify no es alcanzable.** No tiene sentido pedir client_id/secret
  al usuario ni montar OAuth: el 403 es previo a la autenticacion.
- La via viable es el **endpoint de embed** del web player, que no pide credenciales y
  devuelve el tracklist con titulo, artistas y duracion en ms.

Estructura real devuelta por el embed (verificada):

```
props.pageProps.state.data.entity
  .name        -> "Global Warming"
  .type        -> "album" | "playlist" | "track"
  .trackList[] -> { uri: "spotify:track:...", title, subtitle: "Artista1, Artista2",
                    duration: 85400 }
```

### Como se descarga entonces

Spotify sirve audio con DRM y no se toca en ningun momento. Solo se usa como **lista de
canciones**. El audio sigue saliendo de SoundCloud con el `scdl` de siempre:

```
link Spotify -> metadata (embed) -> por cada track: buscar en SoundCloud -> scdl -l <url>
```

Prueba real del matching (Pitbull - Global Warming feat. Sensato, Spotify dice 85400 ms):

```
1. "Global Warming (feat. Sensato)" / Pitbull          -> 30000 ms   DESCARTADO (preview)
2. "Pitbull ft. Sensato - Global Warming (Prod...)"    -> 85446 ms   ELEGIDO (delta 46 ms)
3. "...MACARENA Remix"                                 -> 184732 ms  DESCARTADO
```

La duracion es el filtro que descarta previews de 30 s y remixes. Sin ella el matching es
basura.

### Riesgo abierto que hay que cerrar ANTES de implementar

Las dos playlists de prueba devolvieron exactamente **50 tracks**. Ambas tienen 50 de
verdad, asi que no distingo "es su tamaño real" de "el embed corta en 50". **Paso 1 del
plan = medir esto con una playlist de mas de 100 canciones.** Si hay tope, el alcance
cambia (habria que documentar el limite en la UI) y conviene saberlo antes de escribir
codigo.

---

## 1. Normalizador de URLs (`providers.py`)

Hoy el manejo de URLs esta repartido y es fragil:

- `app.py:127` `resolve_soundcloud_url()` solo contempla `on.soundcloud.com` y usa
  `requests.head()`. Muchos acortadores ignoran HEAD.
- `app.py:385` `_is_soundcloud_url()` acepta `*.soundcloud.com`, asi que `m.` y `on.`
  pasan, pero `soundcloud.app.goo.gl` no.
- `index.html:3691` valida con `url.includes('soundcloud.com')` en el cliente. Rechaza
  cualquier link de Spotify y cualquier `goo.gl`.
- `index.html:3638` `sdSuggestFolder()` deduce el nombre de carpeta del path. Con un link
  corto (`on.soundcloud.com/aB3xY`) propone `aB3xY` como nombre de carpeta.

Funcion unica:

```python
normalize_source_url(url) -> {
    "platform": "soundcloud" | "spotify",
    "kind":     "playlist" | "album" | "track" | "user",
    "id":       str | None,
    "canonical_url": str,
}
```

Entradas que debe aceptar:

| Plataforma | Formato | Nota |
|---|---|---|
| SoundCloud | `soundcloud.com/user/sets/x` | ya funciona |
| SoundCloud | `m.soundcloud.com/...` | movil, ya se usa en `sources.json` |
| SoundCloud | `on.soundcloud.com/xxxx` | **el de "Copiar link"** |
| SoundCloud | `soundcloud.app.goo.gl/xxxx` | hoy rechazado por `_is_soundcloud_url` |
| Spotify | `open.spotify.com/playlist/<id>` | barra del navegador |
| Spotify | `open.spotify.com/intl-es/playlist/<id>` | **el de compartir lleva el locale** |
| Spotify | `spotify:playlist:<id>` | URI nativo |
| Spotify | `spotify.link/xxxx` | **el de "Compartir"**, verificado: 307 -> `spotify.app.link` |

Reglas:

- Resolucion de acortadores con `GET stream=True, allow_redirects=True` (no HEAD), leer
  solo cabeceras, cerrar. Timeout 10 s.
- Si tras los redirects seguimos en `spotify.app.link` (Branch usa JS, no siempre corta en
  HTTP), parsear el HTML buscando `og:url`, `open.spotify.com/...` o `spotify:...:`.
- Quitar siempre `?si=`, `utm_*` y el segmento `/intl-XX/`.
- Cache en memoria de las resoluciones (dict con TTL 1 h): el usuario pega la misma URL
  varias veces mientras rellena el formulario.

## 2. Cliente de Spotify sin credenciales (`providers.py`)

```python
spotify_info(kind, id) -> {"name": str, "tracks": [{"title","artists","duration_ms"}]}
```

- `GET https://open.spotify.com/embed/{kind}/{id}` con User-Agent de navegador.
- Regex sobre `<script id="__NEXT_DATA__">`, `json.loads`, leer `entity`.
- Cache en `spotify_cache.json` (mismo patron que `metadata_cache.json`, `app.py:77`),
  TTL 6 h. Evita repetir la peticion entre el preview y la descarga.
- Si el HTML cambia de forma (Spotify no garantiza nada aqui), fallar con
  `spotify_parse_failed` y mensaje claro en la UI. Es scraping: hay que asumir que algun
  dia se rompe y que el error sea legible, no un 500.

## 3. Busqueda y matching en SoundCloud (`providers.py`)

```python
sc_client_id()               -> str          # scrapeado + cacheado
sc_search(query, limit=8)    -> list[track]
match_track(sp_track, cands) -> track | None
```

`sc_client_id()`: bajar `https://soundcloud.com/discover`, sacar los `<script src>` de
`a-v2.sndcdn.com/assets/*.js`, recorrerlos del ultimo al primero y buscar
`client_id:"..."`. Verificado hoy: 8 scripts, el client_id sale en `55-*.js`. Cachear en
disco con TTL 12 h y re-scrapear ante un 401.

`match_track()`, en orden:

1. Descartar candidatos con `|dur_sc - dur_sp| > 15 s` (mata previews de 30 s).
2. Puntuar por similitud del titulo normalizado (`difflib.SequenceMatcher`, reusando la
   normalizacion de `_normalize_track_name`, `app.py:377`).
3. Bonus si el artista de Spotify aparece en el `username` o en el titulo de SoundCloud.
4. Umbral minimo 0.55. Por debajo -> `not_found`, se registra y se sigue.

Consultas: primero `"{artista} {titulo}"`, y si no hay match, `"{titulo}"` a secas.

Detalle que muerde: el `subtitle` del embed separa artistas con **espacio duro**
(`"Pitbull,\xa0Sensato"`, verificado). Hay que normalizar `\xa0` a espacio antes de
construir la query o la busqueda sale vacia.

## 4. Backend (`app.py`)

### Endpoint nuevo

| Metodo | Ruta | Comportamiento |
|---|---|---|
| POST | `/api/resolve` | `{url}` -> `{platform, kind, canonical_url, title, track_count, suggested_folder, existing}`. Sustituye la adivinanza del cliente y le da nombre de carpeta real (el titulo de la playlist, no el slug). |

`/api/playlist/info` (`app.py:580`) queda absorbido por este: hoy solo cuenta ficheros
locales e ignora la URL. Se mantiene la ruta como alias durante una version para no
romper nada.

### Cambios en los existentes

- `/api/playlist/download` (`app.py:477`): sustituir la guarda `_is_soundcloud_url` por
  `normalize_source_url`. Si `platform == "spotify"` lanzar `run_spotify_playlist`, si no
  el `run_scdl_playlist` de siempre.
- `/api/sources` POST (`app.py:524`) y `/api/playlist/sync` (`app.py:550`): misma
  sustitucion, si no las playlists de Spotify no se pueden re-sincronizar.
- `sources.json`: añadir `"platform"` a cada entrada. Las que no lo tengan =
  `"soundcloud"` (retrocompatible, no hay migracion).

### `run_spotify_playlist(job_id, url, folder_name)`

Mismo contrato que `run_scdl_playlist` (`app.py:404`): snapshot previo, dedupe por nombre
normalizado, `_set_source()` al terminar, `_syncing_folders` en el `finally`.

```
1. spotify_info() -> lista de tracks
2. jobs[job_id]["total"] = len(tracks)
3. por cada track:
   a. si su nombre normalizado ya esta en la carpeta -> skipped, siguiente
   b. sc_search + match_track
   c. sin match -> not_found.append(titulo), siguiente
   d. scdl -l <url_sc> --path <carpeta> --onlymp3   (timeout 120 s por track)
   e. jobs[job_id]["done"] += 1
   f. sleep 0.4 s entre tracks
4. status done, con {new_count, skipped, not_found[]}
```

Puntos que no se pueden saltar:

- **Timeout por track, no global.** El `timeout=600` actual (`app.py:433`) es para un solo
  `scdl` de playlist. Aqui son N invocaciones: una playlist de 200 tracks tarda mucho mas
  que 10 min y un track colgado no puede tumbar el job entero.
- **Cancelacion.** Un job de 200 tracks debe poder pararse: flag `cancel` en `jobs[job_id]`
  revisado en cada vuelta, y `POST /api/playlist/cancel {job_id}`.
- **Secuencial, no paralelo.** Cuatro hilos contra `api-v2.soundcloud.com` se comen un
  rate limit y perdemos el client_id.
- `not_found` se devuelve al cliente para que el usuario vea que falto y lo añada a mano.

## 5. Frontend (`static/index.html`)

- `sd-url` (`:2577`): label "URL de SoundCloud o Spotify", placeholder con los dos
  ejemplos. Texto de cabecera (`:2571`) actualizado.
- `sdUpdateFolder()` / `sdCheckExisting()` (`:3651`, `:3658`): pasan a llamar
  `/api/resolve` con debounce de 400 ms. El nombre de carpeta se autorrellena con el
  titulo real de la playlist. `sdSuggestFolder()` se borra.
- `sdStartDownload()` (`:3687`): fuera el `url.includes('soundcloud.com')`. La validacion
  la hace `/api/resolve`.
- **Progreso real.** Hoy la barra es decorativa: 10 / 20 / 60 / 100 % fijos
  (`:3696`, `:3724`, `:3728`, `:3731`). Con Spotify tenemos `done/total` de verdad ->
  `width: done/total*100 %` y log `"12/48 - 3 no encontradas"`. Para SoundCloud se queda
  como esta (`scdl` no reporta progreso parcial).
- Al terminar, si `not_found` no esta vacio, listarlas en el log en color warn.
- Boton cancelar mientras el job corre.
- Badge de plataforma por fila en "En tu biblioteca" (`:2609`): icono SVG stroke 14 px,
  sin emojis, segun `platform` de `/api/sources`.

## 6. Dependencias

Ninguna nueva. `requests` ya esta en `requirements.txt`; `difflib`, `re` y `json` son
stdlib. `spotdl` queda sin usar (se puede desinstalar del pipx, no lo toca nadie).

## 7. Orden de implementacion

1. **Spike del tope del embed** (30 min, sin codigo de produccion). Playlist publica de
   mas de 100 tracks -> contar `trackList`. Si corta, replantear alcance antes de seguir.
2. `providers.py` completo + tests manuales por CLI contra 6 URLs reales (las 4 formas de
   SoundCloud y las 4 de Spotify de la tabla del punto 1). Aislado, no toca `app.py`.
3. `/api/resolve` + relajar guardas en los 3 endpoints existentes. Verificar con curl que
   una playlist de SoundCloud sigue bajando exactamente igual que hoy (no regresion).
4. `run_spotify_playlist` + cancelacion. Probar con una playlist corta (10-15 tracks) y
   revisar a mano cuantos matches son correctos. **Aqui se decide si el matching es lo
   bastante bueno** o hay que ajustar umbrales.
5. UI: resolve, progreso real, cancelar, badges.
6. Reinicio del servicio y prueba end-to-end con link de compartir de la app movil, que es
   el caso que pediste.

Estimado: ~280 lineas en `providers.py`, ~120 en `app.py`, ~90 en `index.html`.

## 8. Lo que NO hace este plan

- No descarga audio de Spotify. No es posible sin romper el DRM, y no se va por ahi.
- No toca los endpoints de descarga al dispositivo (`/api/file/...`, `/api/folder/.../zip`).
  Todo se queda en la biblioteca del servidor, igual que el flujo actual.
- No garantiza el 100 % de matches. Canciones raras, no publicadas en SoundCloud o solo
  disponibles como preview de 30 s se reportan como `not_found`. Es una limitacion
  estructural del enfoque, no un bug a corregir despues.
