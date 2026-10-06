#!/bin/bash
# preprocess.sh — Normaliza archivos de audio para carga rápida
# - Convierte a MP3 128kbps CBR (carga instantánea, tamaño reducido)
# - Mueve originales a .orig/ si se quieren conservar
# - Solo procesa archivos que no estén ya procesados (.processed marker)
#
# Uso: bash preprocess.sh [--keep-originals]
#   --keep-originals: guarda los originales en carpeta .orig/
#
# Ejecutar una vez. Los archivos procesados se cargan directo.

set -euo pipefail

DOWNLOADS="/home/ubuntu/services/wave/downloads"
KEEP_ORIGINALS=false
PROCESSED=0
SKIPPED=0
ERRORS=0

if [[ "${1:-}" == "--keep-originals" ]]; then
    KEEP_ORIGINALS=true
fi

# Verificar ffmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "ERROR: ffmpeg no está instalado. Instalar con: sudo apt install ffmpeg"
    exit 1
fi

echo "═══════════════════════════════════════════"
echo "  SoundDrop — Pre-procesador de audio"
echo "═══════════════════════════════════════════"
echo ""

# Recorrer todas las subcarpetas
for folder in "$DOWNLOADS"/*/; do
    [ -d "$folder" ] || continue
    folder_name=$(basename "$folder")
    echo "📁 $folder_name"

    for file in "$folder"*; do
        [ -f "$file" ] || continue
        filename=$(basename "$file")
        ext="${filename##*.}"
        ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

        # Solo procesar archivos de audio
        case "$ext_lower" in
            mp3|m4a|flac|wav|ogg|opus) ;;
            processed) SKIPPED=$((SKIPPED + 1)); continue ;;
            *) continue ;;
        esac

        # Verificar si ya está procesado (marker file)
        marker="$file.processed"
        if [ -f "$marker" ]; then
            SKIPPED=$((SKIPPED + 1))
            continue
        fi

        # Obtener tamaño
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
        size_mb=$((size / 1048576))

        # Si ya es MP3 < 8MB y CBR, marcar como procesado y skip
        if [[ "$ext_lower" == "mp3" ]] && [[ $size -lt 8388608 ]]; then
            touch "$marker"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi

        echo "  ⚙ Procesando: $filename (${size_mb}MB)"

        # Archivo temporal
        tmp_file="${file}.tmp.mp3"
        new_file="${file%.*}.mp3"

        # Convertir a MP3 128kbps CBR con ffmpeg
        if ffmpeg -y -i "$file" \
            -codec:a libmp3lame -b:a 128k -ac 2 -ar 44100 \
            -map_metadata 0 -id3v2_version 3 \
            "$tmp_file" </dev/null 2>/dev/null; then

            if $KEEP_ORIGINALS; then
                orig_dir="$folder.orig"
                mkdir -p "$orig_dir"
                mv "$file" "$orig_dir/$filename"
            fi

            # Si el original no era MP3, eliminar original y renombrar
            if [[ "$ext_lower" != "mp3" ]]; then
                if ! $KEEP_ORIGINALS; then
                    rm -f "$file"
                fi
                mv "$tmp_file" "$new_file"
                touch "$new_file.processed"
            else
                # Era MP3 pero grande — reemplazar
                if ! $KEEP_ORIGINALS; then
                    mv "$tmp_file" "$file"
                else
                    mv "$tmp_file" "$new_file"
                fi
                touch "${new_file:-$file}.processed"
            fi

            new_size=$(stat -c%s "$new_file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "?")
            new_mb=$((new_size / 1048576))
            echo "    ✓ ${size_mb}MB → ${new_mb}MB"
            PROCESSED=$((PROCESSED + 1))
        else
            rm -f "$tmp_file"
            echo "    ✗ Error al procesar"
            ERRORS=$((ERRORS + 1))
        fi
    done
done

echo ""
echo "═══════════════════════════════════════════"
echo "  Resultados:"
echo "  ✓ Procesados: $PROCESSED"
echo "  ⊘ Ya procesados: $SKIPPED"
echo "  ✗ Errores: $ERRORS"
echo "═══════════════════════════════════════════"
