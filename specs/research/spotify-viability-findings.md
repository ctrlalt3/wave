# Investigacion — Viabilidad de Spotify en Wave

Estado: HECHO (evidencia, no propuesta)
Fecha: 2026-08-05
Maquina: servidor de Wave (`/home/ubuntu/services/wave`)
Relacionado: [`../feature/spotify-and-share-links.md`](../feature/spotify-and-share-links.md)

Este documento guarda las comprobaciones que sustentan el plan. Sin esto, el plan parece
una eleccion de diseño arbitraria; con esto se ve que es la unica via que queda.

Reproducible con: `python3 specs/research/verify_providers.py`

---

## 1. Conectividad de salida

```
POST accounts.spotify.com/api/token   -> 403 Forbidden
GET  api.spotify.com/v1/albums/<id>   -> 403 Forbidden
GET  open.spotify.com/                -> 200
GET  music.youtube.com/               -> 200
GET  soundcloud.com/                  -> 200
```

Los dos 403 devuelven una pagina de error de Google (`<h1>Error: Forbidden</h1>` /
"Your client does not have permission to get URL ... from this server"), no un JSON de
Spotify. Es bloqueo en el edge por IP de datacenter, previo a cualquier autenticacion.

**Consecuencia: la Spotify Web API no es utilizable desde este servidor.** Dar de alta
una app en el dashboard de Spotify y poner client_id/secret en `.env` no cambiaria nada,
porque el 403 ocurre antes de validar credenciales.

## 2. spotdl (4.4.3, instalado via pipx en `~/.local/bin/spotdl`)

Dos intentos, dos fallos distintos:

```
$ spotdl save "https://open.spotify.com/album/4aawyAB9vmqN3uQ7FjRGTy" --save-file -
DownloaderError: You are blocked by YouTube Music. Please use a VPN, change
youtube-music to piped, or use other audio providers

$ spotdl save "...same..." --save-file - --audio soundcloud
<html>... Error: Forbidden ... /api/token ...</html>, error_description: None
```

El primero es un `check_ytmusic_connection()` que spotdl ejecuta en el entry point aunque
el provider de audio sea otro. El segundo es el mismo 403 del punto 1.

**Consecuencia: spotdl queda descartado.** No es un problema de flags ni de config.

## 3. Endpoint de embed (la via que si funciona)

```
GET https://open.spotify.com/embed/album/4aawyAB9vmqN3uQ7FjRGTy   -> 200, 38 KB
```

El HTML trae `<script id="__NEXT_DATA__" type="application/json">`. Ruta util:

```
props.pageProps.state.data.entity
```

Claves de `entity`:

```
type, name, uri, id, title, subtitle, isPreRelease, releaseDate, duration,
isPlayable, playabilityReason, isExplicit, hasVideo, relatedEntityUri,
trackList, visualIdentity
```

Cada elemento de `trackList`:

```
uri, uid, title, subtitle, isExplicit, isNineteenPlus, contentRatings,
duration, isPlayable, playabilityReason, audioPreview, entityType
```

Ejemplo real (album Global Warming, 18 tracks):

```
title:    "Global Warming (feat. Sensato)"
subtitle: "Pitbull, Sensato"          <- artistas, separados por coma
uri:      "spotify:track:6OmhkSOpvYBokMKQxpIGx2"
duration: 85400                        <- milisegundos
```

`subtitle` + `title` + `duration` es todo lo que hace falta para buscar en SoundCloud.
No requiere credenciales.

### Playlists

```
GET open.spotify.com/embed/playlist/37i9dQZF1DXcBWIGoYBM5M -> 200, "Today's Top Hits", 50 tracks
GET open.spotify.com/embed/playlist/37i9dQZEVXbMDoHDwVN2tF -> 200, "Top 50 - Global",   50 tracks
```

**PENDIENTE / riesgo abierto:** las dos tienen 50 tracks de verdad, asi que este resultado
no distingue "tamaño real" de "el embed corta en 50". Hay que medirlo con una playlist
publica de mas de 100 canciones antes de escribir codigo de produccion. Es el paso 1 del
plan de implementacion.

### Fragilidad

Es scraping de un HTML que Spotify no documenta ni garantiza. Puede romperse sin aviso.
El plan exige que el fallo sea un error legible (`spotify_parse_failed`), no un 500.

## 4. Busqueda en SoundCloud

`~/.config/scdl/scdl.cfg` tiene `client_id` y `auth_token` **vacios** (scdl scrapea el
client_id en cada ejecucion). Una llamada a `api-v2.soundcloud.com` sin client_id da 401.

Scraping del client_id, verificado:

1. `GET https://soundcloud.com/discover` con User-Agent de navegador.
2. Extraer los `<script src="https://a-v2.sndcdn.com/assets/*.js">` -> 8 resultados.
3. Recorrerlos del ultimo al primero buscando `client_id:"<alfanumerico 20+>"`.
4. Aparecio en `55-bd40086a.js` (el nombre del bundle cambia con cada deploy, por eso hay
   que recorrerlos, no hardcodear).

Con ese client_id:

```
GET api-v2.soundcloud.com/search/tracks?q=...&client_id=... -> 200
```

## 5. Matching por duracion — prueba real

Query `"Pitbull Global Warming Sensato"`. Spotify dice 85400 ms.

| # | Titulo en SoundCloud | Uploader | Duracion | Veredicto |
|---|---|---|---|---|
| 1 | Global Warming (feat. Sensato) | Pitbull | 30000 ms | descartado, preview |
| 2 | Pitbull ft. Sensato - Global Warming (Prod. by Bass ill Euro) (2012) | Bass ill Euro | 85446 ms | **elegido**, delta 46 ms |
| 3 | Pitbull-Global Warming MACARENA Remix (Dj Alonso Curiel) | Alonso Curiel Gomez | 184732 ms | descartado, remix |

Dos cosas que confirma esta prueba:

- El resultado **oficial del artista es un preview de 30 s** y es el primero de la lista.
  Ordenar por relevancia y coger el primero produce una biblioteca de clips de 30 s.
- La duracion resuelve el caso limpiamente. Es el filtro principal, no un desempate.

Umbral propuesto en el plan: descartar si `|dur_sc - dur_sp| > 15 s`.

## 6. Links de compartir

```
GET https://spotify.link/test123 -> 307 -> https://spotify.app.link/IurbCpfD3kb?_p=...
```

Confirma que `spotify.link` redirige por HTTP a `spotify.app.link` (Branch). No se pudo
seguir la cadena completa por falta de un link real; Branch a veces entrega el deep link
por JS en vez de por `Location`, de ahi el fallback a parsear `og:url` del HTML que
recoge el plan.

Formatos a soportar y su estado hoy en el codigo:

| URL | `_is_soundcloud_url` (`app.py:385`) | Cliente (`index.html:3691`) |
|---|---|---|
| `soundcloud.com/u/sets/x` | pasa | pasa |
| `m.soundcloud.com/...` | pasa | pasa |
| `on.soundcloud.com/xxxx` | pasa, pero `resolve_soundcloud_url` usa HEAD | pasa |
| `soundcloud.app.goo.gl/xxxx` | **falla** | **falla** |
| cualquier URL de Spotify | **falla** | **falla** |
