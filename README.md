# 🎵 SOUNDDROP — Music Downloader

Web app para descargar música de SoundCloud usando `scdl`.

## Estructura

```
music-downloader/
├── app.py              ← Backend Flask
├── requirements.txt
├── static/
│   └── index.html      ← Frontend
└── downloads/          ← Se crea automáticamente
```

## Instalación

```bash
# 1. Instalar dependencias
pip install -r requirements.txt

# 2. Iniciar el servidor
python app.py
```

Abre tu navegador en: **http://localhost:5000**

## Uso

1. Pega una URL de SoundCloud (canción o playlist)
2. Pulsa **DESCARGAR**
3. Espera a que termine y descarga el archivo(s)

## Ejemplos de URLs compatibles

- Canción: `https://soundcloud.com/artista/nombre-cancion`
- Playlist: `https://soundcloud.com/artista/sets/nombre-playlist`
- Usuario (todas sus canciones): `https://soundcloud.com/artista`

## Producción (opcional)

Para servir con gunicorn:

```bash
pip install gunicorn
gunicorn -w 4 -b 0.0.0.0:5000 app:app
```

O con nginx como proxy inverso apuntando al puerto 5000.

> **Nota**: Los archivos descargados se guardan en la carpeta `downloads/` del servidor.
> Puedes añadir limpieza periódica con un cron job si el espacio es limitado.
