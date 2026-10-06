#!/bin/bash
# Script para mantener SoundDrop activo

APP_DIR="/home/ubuntu/services/wave"
PID_FILE="/tmp/sounddrop.pid"
LOG_FILE="/tmp/sounddrop.log"

# Verificar si el proceso está corriendo
check_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            # Verificar si responde HTTP
            if curl -s -o /dev/null -w "%{http_code}" http://localhost:5000 | grep -q "200"; then
                return 0
            fi
        fi
    fi
    return 1
}

# Iniciar el servidor
start_server() {
    echo "$(date): Iniciando SoundDrop..." >> "$LOG_FILE"
    cd "$APP_DIR" || exit 1
    source venv/bin/activate
    nohup python app.py >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    sleep 3
    
    if check_running; then
        echo "$(date): SoundDrop iniciado correctamente (PID: $(cat $PID_FILE))" >> "$LOG_FILE"
    else
        echo "$(date): ERROR - No se pudo iniciar SoundDrop" >> "$LOG_FILE"
    fi
}

# Main
if ! check_running; then
    start_server
fi
