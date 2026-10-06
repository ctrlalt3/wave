# SoundDrop — Sync de playlists desde la pestaña de descarga

Estado: PROPUESTO (pendiente de aprobacion)
Fecha: 2026-08-05
Alcance: `app.py`, `static/index.html`

## Objetivo

Usar la pestaña SoundDrop para añadir musica a la biblioteca del servidor (nunca al
dispositivo), con dos flujos:

1. Importar una playlist nueva de SoundCloud (ya existe).
2. Actualizar una playlist ya importada, mediante un boton dentro de su propia fila.
   Si la URL de origen no esta guardada, se pide al usuario en linea.

## Contexto verificado en el codigo actual

- `app.py:341` `run_scdl_playlist()` descarga server-side a `downloads/<carpeta>` con
  dedupe por nombre normalizado. Nada toca el dispositivo.
- `app.py:406` `/api/playlist/download` recibe `{url, folder_name}` pero **no persiste
  la URL**.
- La unica traza de la URL esta en `localStorage.sd_history` (`index.html:3299`), por
  device y limitada a 10 entradas.

Ese es el agujero: sin registro server-side no se puede actualizar una playlist
existente.

## 1. Registro de fuentes (backend, base de todo)

Nuevo `sources.json` en `BASE_DIR`, con lock igual que `play_stats.json`:

```json
{
  "2.3": {
    "url": "https://soundcloud.com/x/sets/2-3",
    "added": 1772302687.1,
    "last_sync": 1772302687.1,
    "last_new": 4,
    "last_status": "done"
  }
}
```

Helpers `_load_sources()` / `_save_sources()` / `_set_source(folder, url)` junto a los
de stats (`app.py:33-56`).

## 2. Endpoints nuevos

| Metodo | Ruta | Comportamiento |
|---|---|---|
| GET | `/api/sources` | Cruza `downloads/*` con `sources.json`. Devuelve **todas** las carpetas con audio: `{folder, count, coverUrl, url\|null, last_sync, last_new}`. Las carpetas sin URL salen con `url: null` para que la UI sepa que debe pedirla. |
| POST | `/api/sources` | `{folder_name, url}` -> valida `soundcloud.com`, guarda. Para carpetas legacy. |
| POST | `/api/playlist/sync` | `{folder_name, url?}`. Si no hay `url` en body ni en registro -> `409 {"error":"url_required"}`. Si viene `url`, la persiste antes de lanzar. Reutiliza `run_scdl_playlist` tal cual y devuelve `{job_id}`. |
| DELETE | `/api/sources/<folder>` | Desvincula la URL (no borra audio). |

Modificar `start_playlist_download` (`app.py:406`) para llamar `_set_source()`. A partir
de ahi toda descarga nueva queda registrada.

Guardas en `/api/playlist/sync`:

- `folder_name` resuelto con `.resolve()` y verificado dentro de `DOWNLOAD_DIR`
  (path traversal; el endpoint actual no lo comprueba porque solo crea).
- Set `_syncing_folders` para rechazar sync duplicado sobre la misma carpeta
  (`409 already_syncing`).
- `run_scdl_playlist` escribe `last_sync` / `last_new` en el registro al terminar.

## 3. UI — pestaña SoundDrop (`index.html:2291`)

Reestructurar en dos bloques.

### A. "Nueva playlist"

El formulario actual (URL + carpeta + boton), sin cambios funcionales.

### B. "En tu biblioteca"

Sustituye al historial de localStorage (`sdLoadHistory`, `index.html:3305`), que viola
la regla data-first. Se carga de `/api/sources` al entrar en la vista.

```
[cover] Nombre carpeta            [refresh]
        42 tracks - sync 5 ago
--------------------------------------------
[cover] esto es hard              [refresh]
        18 tracks - sin URL vinculada
```

- Boton refresh = SVG stroke `currentColor` 16px, sin emojis.
- **Con URL** -> `POST /api/playlist/sync {folder_name}` directo.
- **Sin URL** -> despliega en linea, dentro de la propia fila, un input
  `https://soundcloud.com/...` + boton Vincular. Al confirmar: `POST /api/sources` y
  encadena el sync. Sin `prompt()` (rompe la UX movil y el tema oscuro).
- Estado por fila: el boton pasa a spinner, el subtitulo muestra `Sincronizando...` ->
  `+3 nuevas` / `Sin cambios` / error. Poll por fila con su propio `job_id` en un `Map`,
  para permitir varias sincronizaciones a la vez.
- Al terminar: `loadMusic()` para refrescar la biblioteca.

### Migracion one-shot

Si existe `localStorage.sd_history` y aun no se migro: POST de cada `{folder, url}` a
`/api/sources`, marcar flag, borrar. Asi las playlists ya bajadas desde este device no
piden URL.

## 4. Nada llega al dispositivo

Este flujo no toca `/api/file/<job_id>/<filename>` (`app.py:464`) ni
`/api/folder/<f>/zip` (`app.py:240`). El unico boton de descarga a device es `dlFolder`
en la biblioteca (`index.html:2893`) y se deja intacto.

## 5. Orden de implementacion

1. `sources.json` + helpers + `_set_source` en `start_playlist_download` (backend
   aislado, no rompe nada).
2. `GET/POST /api/sources` + `/api/playlist/sync`. Verificar con curl sobre una carpeta
   real.
3. Bloque B en la UI + migracion de localStorage.
4. Reinicio del servicio y prueba end-to-end con una playlist real de las 20 carpetas
   existentes.

Sin dependencias nuevas. Estimado: ~120 lineas en `app.py`, ~90 en `index.html`.
