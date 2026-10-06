# specs/

Especificaciones de Wave. Una propuesta se escribe aqui **antes** de tocar codigo, y se
queda como registro de por que se hizo asi.

```
specs/
├── design/      cambios de UI/UX
├── feature/     funcionalidad nueva (backend + frontend)
└── research/    evidencia y pruebas que sustentan un plan
```

Cada documento abre con `Estado:` — `PROPUESTO` (pendiente de aprobacion), `APROBADO`,
`HECHO` o `DESCARTADO` — mas fecha y alcance (ficheros que toca).

## Indice

| Documento | Estado | Que es |
|---|---|---|
| [`design/wave-redesign.md`](design/wave-redesign.md) | ver fichero | Rediseño de la interfaz |
| [`feature/sounddrop-playlist-sync.md`](feature/sounddrop-playlist-sync.md) | PROPUESTO (implementado: `sources.json` y `/api/sources` ya existen) | Registro server-side de playlists y boton de re-sync por fila |
| [`feature/spotify-and-share-links.md`](feature/spotify-and-share-links.md) | PROPUESTO | Playlists de Spotify + links de compartir de SoundCloud/Spotify |
| [`research/spotify-viability-findings.md`](research/spotify-viability-findings.md) | HECHO | Evidencia: la API de Spotify esta bloqueada en este servidor y spotdl no sirve |
| [`research/verify_providers.py`](research/verify_providers.py) | herramienta | Reproduce esa evidencia. Es el instrumento del paso 1 del plan de Spotify |

## Estado de la propuesta de Spotify

Bloqueada a la espera de una decision y de un dato:

1. **Dato pendiente:** si el `trackList` del embed de Spotify corta a las 50 o 100
   canciones. Se mide con
   `python3 specs/research/verify_providers.py --spotify <url de playlist de +100 tracks>`.
   Si corta, el alcance cambia.
2. **Decision pendiente:** aprobar el enfoque de scraping del embed, asumiendo que
   Spotify puede romperlo sin aviso.
