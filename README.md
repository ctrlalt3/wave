# 🎵 Wave

Reproductor y gestor de música personal con backend propio, apps nativas de iOS/macOS y cliente web. Incluye descarga desde SoundCloud (`scdl`) y sincronización en la nube entre dispositivos.

## Estructura del repo

```
wave/
├── app.py              ← Backend Flask (API, descargas, nube)
├── cloud_api.py         ← Endpoints de sincronización en la nube
├── desktop_api.py        ← Endpoints usados por la app de macOS
├── requirements.txt
├── static/               ← Frontend web (reproductor, descargador)
├── ios/                  ← App nativa iOS/iPadOS (SwiftUI) — versión actual: 0.12.0
├── desktop/              ← App nativa macOS (Electron) — versión actual: 1.5
├── tests/
└── downloads/            ← Se crea automáticamente (ignorado por git)
```

Este repo unifica las tres plataformas (iOS, macOS, Web). `main` siempre contiene la versión actual de cada una.

## Versionado de iOS

Cada versión histórica de la app iOS se conserva como rama independiente (snapshot completo de `ios/` en esa versión), en vez de carpetas o zips sueltos. `main` siempre tiene la versión actual (0.12.0).

## Instalación — Backend / Web

```bash
pip install -r requirements.txt
python app.py
```

Abre tu navegador en: **http://localhost:5000**

### Producción (opcional)

```bash
pip install gunicorn
gunicorn -w 4 -b 0.0.0.0:5000 app:app
```

O con nginx como proxy inverso apuntando al puerto 5000.

## App de macOS

Ver [`desktop/README.md`](desktop/README.md). Build con Electron (`desktop/package.json`).

## App de iOS

Ver [`ios/README.md`](ios/README.md). Proyecto Xcode generado con XcodeGen (`ios/project.yml`).

## Descarga desde SoundCloud

1. Pega una URL de SoundCloud (canción o playlist) en el frontend web
2. Pulsa **DESCARGAR**
3. Espera a que termine y descarga el archivo(s)

Ejemplos de URLs compatibles:

- Canción: `https://soundcloud.com/artista/nombre-cancion`
- Playlist: `https://soundcloud.com/artista/sets/nombre-playlist`
- Usuario (todas sus canciones): `https://soundcloud.com/artista`

> **Nota**: los archivos descargados se guardan en `downloads/` en el servidor y no se versionan en git.
