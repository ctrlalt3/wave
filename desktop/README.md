# Wave para macOS · 1.5

## Cambios en 1.5

- Nube común para iOS y Mac: subidas de carpetas conservando subcarpetas y descargas verificadas con SHA-256. Se omiten archivos idénticos.
- Me gusta compartidos para canciones del servidor y copias locales de la nube, con actualización cada 15 segundos y al volver a la app. Corazón en lista y reproductor; filtro Me gusta.
- Descubre con selector de carpeta, reproducción, posición, saltos de 10 segundos, Me gusta y descartar. «Enviar a…» mueve la canción del servidor a la carpeta elegida. Aviso durante 15 segundos, con cierre manual.
- Historial persistente de actualizaciones del servidor; deshacer durante 30 minutos desde cualquiera de las plataformas. Descargas locales con recuperación durante 30 minutos. Se rechaza deshacer si existen cambios posteriores.
- Preferencias de apariencia Sistema/Claro/Oscuro y colores de acento, además de los controles, onda, navegación y reproducción continua anteriores.

Selecciona una carpeta local y pulsa **Subir / actualizar carpeta en la nube**. La subida automática al añadir carpetas está pendiente de autorización del servidor de destino. En otro dispositivo pulsa **Descargar / actualizar** para guardar su copia. Las carpetas del servidor son las playlists compartidas; la selección personal de playlists de iOS y las playlists externas de Música/Spotify no se sincronizan como archivos.

Paquetes de prueba: `static/desktop-releases/1.5.0/Wave-1.5.0-arm64-mac.zip` y `Wave-1.5.0-x64-mac.zip`. Firma ad hoc; apertura en un Mac y notarización de Apple pendientes. La nube usa el almacenamiento del servidor Wave, sin proveedor externo adicional.

## Cambios en 1.4

- Navegación inmediata entre carpetas y canciones, sin animar el contenido ni la interfaz completa.
- Vista avanzada en columnas al iniciar. El explorador ocupa el espacio disponible y no duplica las canciones en una tabla inferior; la vista Lista sigue disponible.
- Arrastre de canciones dentro de la columna actual para guardar un orden personalizado. Casillas para seleccionar canciones y usar la bandeja o cambiar su visibilidad.
- Barra de ventana propia con minimizar, ampliar/restaurar y cerrar. La barra se puede arrastrar para mover la ventana.
- Carátulas incrustadas o archivos cover/folder JPG y PNG para música local; carátulas de la API para música del servidor. Imagen en explorador, reproductor y vista de canción.
- Almacenamientos externos en la barra lateral local: seleccionar un disco lee sus carpetas y canciones. Actualización de dispositivos manual y al volver a la app. Desconectar un disco puede requerir seleccionar otra biblioteca; los errores de acceso se muestran en pantalla.
- Flechas normales para navegar atrás y adelante, separadas de los controles del reproductor.

## Cambios en 1.3

- Historial de navegación entre bibliotecas, carpetas, vista normal/avanzada, listas/columnas y vista de canción. Atrás y adelante restauran filtros, orden y posición de desplazamiento sin pausar el audio.
- Gestos horizontales de trackpad, gestos táctiles, botones de navegación, botones laterales del ratón y atajos `⌘[` / `⌘]` o `Alt+←` / `Alt+→`. Los eventos nativos de swipe de macOS se gestionan cuando la configuración del trackpad los emite. Cada gesto recorre una entrada; los campos de texto y las regiones con desplazamiento horizontal conservan su interacción.
- Transiciones breves en navegación, filas al reordenar, controles, selección, carpetas, bandeja, avisos y reproductor. Los cambios por teclado se aplican directamente; la preferencia del sistema de reducir movimiento desactiva las animaciones.
- Spotify conserva su búsqueda y apertura externa anteriores. Las mejoras de reproducción de Spotify y la migración a iOS quedan fuera de esta versión.

## Cambios en 1.2

- La reproducción y su cola continúan al cambiar entre bibliotecas, Spotify y Ajustes, navegar por carpetas y minimizar la ventana. Actualizar una carpeta conserva la canción si sigue existiendo.
- Reproductor compacto con progreso, salto de posición, controles de transporte y acceso a la canción. El reproductor expandido añade volumen, aleatorio y repetición de cola. Los controles multimedia del sistema admiten reproducción, pausa, anterior, siguiente y búsqueda temporal.
- Vista de canción con forma de onda calculada desde el audio, clic para avanzar y cola de siguientes canciones. La onda se carga al abrir esta vista; admite archivos de hasta 32 MB y formatos decodificables por Electron. Si no está disponible, el audio y la barra de progreso siguen funcionando.
- Vista avanzada con filas compactas, metadatos de archivo, canciones ocultas y exploración de carpetas en listas o columnas. La vista y el volumen se recuerdan entre sesiones.
- Botones nativos de ventana ocultos en macOS.


Tres secciones con interfaz propia instalada en el Mac: **Servidor Wave**, **Música de este Mac** y **Spotify**. La sección del servidor consume la API de Wave; no carga ni incrusta su página web.

## Instalar

Los paquetes 1.4 están en `desktop/dist/`. Descarga el ZIP para tu arquitectura, descomprímelo y mueve **Wave.app** a **Aplicaciones**:

- `Wave-1.4.0-arm64-mac.zip`: Apple Silicon (M1 y posteriores).
- `Wave-1.4.0-x64-mac.zip`: Intel.

Estos paquetes se generan en Linux con firma local ad hoc para la app, sus ejecutables, permisos y recursos. No tienen firma Developer ID ni notarización de Apple. Se han probado las funciones con Electron en Linux; su apertura en macOS queda pendiente de comprobar. Si macOS bloquea la app, consulta [las instrucciones oficiales de Apple](https://support.apple.com/es-es/102445). Para distribución firmada, compila y firma desde un Mac con Apple Developer.

## Bibliotecas

- **Servidor Wave** (`⌘1`): carpetas, canciones y reproducción desde la API, con la misma interfaz y controles que la música local.
- **Música de este Mac** (`⌘2`): elige tu biblioteca; navega por carpetas y subcarpetas desde el explorador, las tarjetas o la ruta. «Todas las canciones» reúne toda la biblioteca.
- **Spotify** (`⌘3`): busca canciones, cambia de mercado, pagina resultados y abre canciones en Spotify para escucharlas. La búsqueda se ejecuta desde la conexión del Mac. Las credenciales permanecen en el servidor, que entrega un token temporal al proceso principal. El token y el secreto no se muestran en la interfaz. La reproducción completa de Spotify no está integrada.

## Orden, vistas y canciones ocultas

La vista **Normal** muestra las canciones visibles. La vista **Avanzada** añade archivo/carpeta, formato y tamaño/fecha (local) o duración/reproducciones (servidor). También muestra las canciones ocultas para poder recuperarlas.

Selecciona «Personalizado», arrastra filas o usa las flechas para reordenar. El orden se guarda en la biblioteca actual. También puedes ordenar por nombre, archivo, carpeta y otros campos.

Pulsa el icono de ocultar o selecciona varias canciones y usa «Ocultar selección». Los archivos permanecen en disco. Para restaurarlos, cambia a Avanzada y usa el icono de mostrar o «Mostrar selección».

El orden y las canciones ocultas se guardan en `.wave-library.json`, dentro de la carpeta raíz de la biblioteca local o de `downloads/` en el servidor. No se renombra ni elimina el audio al ordenar u ocultar.

## Bandeja de copias y edición real de archivos

Selecciona canciones de tu Mac mediante las casillas y pulsa **Copiar a bandeja** (`⌘C`). Puedes seleccionar todas las canciones de la vista con `⌘A`.

- **Pegar en esta carpeta** (`⌘V`): copia las canciones de la bandeja a la carpeta abierta de tu biblioteca.
- **Elegir destino…**: abre el selector de carpetas del Mac y permite copiar a cualquier carpeta elegida.
- **Al pegar, se sobrescriben los archivos que tengan el mismo nombre**, editando la biblioteca actual. La bandeja permanece disponible para repetir la copia.
- Si una canción ya está en la carpeta de destino, se omite la copia de ese mismo archivo. Los errores se muestran por archivo; las copias correctas permanecen.

Los archivos se copian primero a un temporal de destino y después reemplazan el archivo final. La música local se sube al servidor al pulsar el botón de nube. La compatibilidad de reproducción depende del motor multimedia de Electron.

## Configuración

En **Ajustes** (`⌘,`) puedes cambiar la URL del servidor. El valor inicial es `https://tulopetas.duckdns.org/wave/`.

Las credenciales Spotify se guardan solo en `/home/ubuntu/services/wave/.env`, ignorado por Git y con permisos privados. `.env.example` contiene únicamente los nombres de variables. No empaquetes `.env` ni credenciales en la app.

Los endpoints nuevos se registran desde `desktop_api.py`:

- `GET/POST /api/desktop/state`: organización persistente de la biblioteca del servidor.
- `GET /api/spotify/status`: estado de configuración, sin secretos.
- `POST /api/spotify/search-token`: token de catálogo temporal, almacenado en caché, con limitación de solicitudes y respuesta `no-store`. No da acceso a recursos privados de usuarios de Spotify.

## Desarrollo y empaquetado

```sh
npm ci
npm test
python3 -m unittest discover -s test -p 'test_desktop_api.py'
npm start
```

Prueba de interfaz con carpetas temporales, API controlada y búsqueda Spotify simulada:

```sh
npm run test:smoke
```

En Linux sin pantalla:

```sh
xvfb-run -a node_modules/.bin/electron --no-sandbox test/smoke.cjs
```

La opción `--no-sandbox` se utiliza solo en esta prueba de Linux; la app distribuida conserva sandbox y aislamiento.

Generar ZIP para Apple Silicon e Intel desde Linux:

```sh
CSC_IDENTITY_AUTO_DISCOVERY=false npm run dist:zip
```

Generar DMG y ZIP desde macOS:

```sh
npm run dist:mac
```

Los ZIP se crean con `ditto` en macOS y `zip -y` en Linux, conservando los enlaces simbólicos de los frameworks. En Linux necesitas el comando `zip`. Los resultados aparecen en `dist/` por defecto; `WAVE_RELEASE_DIR` permite cambiar la carpeta de salida del empaquetador.

## Firma local y apertura en macOS

El empaquetado ZIP requiere firmar y verificar los bundles antes de comprimirlos. En Linux, `scripts/sign-mac.cjs` usa `rcodesign` (Apple Codesign 0.29.0), descargado de la release oficial y comprobado con su SHA-256. Configura `WAVE_RCODESIGN` si está instalado en otra ruta. En macOS, electron-builder aplica firma ad hoc con los entitlements de Electron y el script valida con `codesign --verify --deep --strict`. Para distribuir con Developer ID, sustituye la identidad local y configura notarización.

`scripts/verify-mac.py` comprueba los hashes de las páginas de código, permisos, Info.plist, recursos y componentes anidados. No sustituye a Gatekeeper ni a la prueba de apertura en un Mac.

Si macOS bloquea esta build local después de instalarla en Aplicaciones, usa Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente. Si sigue indicando que esta app está dañada, y estás usando el paquete generado aquí, puedes retirar la marca de cuarentena únicamente de Wave:

```sh
xattr -dr com.apple.quarantine "/Applications/Wave.app"
```

Los paquetes finales con firma local se publican en `static/desktop-releases/1.4.0/`, junto a `SHA256SUMS.txt`.
