# Wave para iPhone e iPad · 0.5.0 (build 5)

Esta actualización incluye el proyecto `Wave.xcodeproj`, las fuentes y `Info.plist`. Se puede abrir directamente en Xcode: **no hace falta ejecutar XcodeGen**. Se mantiene el identificador `app.wave.music.ios` para actualizar la app instalada sin borrar sus archivos importados.

## Instalar la actualización en el Mac

1. Cierra Xcode por completo con `⌘Q`.
2. Descomprime `Wave-iOS-0.5.0.zip` en una carpeta nueva. No lo mezcles con la copia antigua.
3. Dentro de `Wave-iOS-0.5.0`, abre **Wave.xcodeproj**.
4. En TARGETS → Wave → Signing & Capabilities, activa Automatically manage signing y selecciona tu Team.
5. Arriba, selecciona el scheme **Wave** y tu iPhone o iPad conectado.
6. Pulsa Ejecutar (`⌘R`).

La app nueva muestra **WAVE 0.5** arriba y cinco secciones: **Servidor**, **Mi iPhone/Mi iPad**, **Playlists**, **Spotify** y **Ajustes**. Ajustes muestra la versión del bundle `0.5.0`, build `5`. Si solo ves la lista antigua de carpetas sin estas secciones, esa ejecución sigue usando la versión anterior. Rebuild y Relaunch recompilan/reabren el proyecto seleccionado; no copian las fuentes del servidor al Mac. Verifica la carpeta del proyecto con Show in Finder sobre el proyecto en Xcode.

No desinstales la app para actualizarla si quieres conservar tus archivos importados. La app instalada puede abrirse sin el cable de Xcode; el servidor y los contenidos en la nube necesitan conexión de red.

## Corrección de navegación y carátulas

Se conserva la navegación original: pestañas nativas de Apple en iPhone y barra lateral en pantallas anchas. El mini reproductor se inserta dentro del contenido de la pestaña, por encima de la barra nativa. La vista ampliada ocupa esa misma zona y deja accesible la navegación. Minimizar conserva la carpeta abierta; cambiar de sección muestra esa biblioteca sin interrumpir el audio.

Las carátulas de Música, servidor y cola se pasan al componente de imagen. Los archivos importados leen su imagen incrustada, incluidos los que ya estaban importados. Si el servidor omite `coverUrl`, se consulta el endpoint de artwork de la canción. Los archivos sin imagen incrustada muestran el símbolo de música.

Se ha validado la sintaxis Swift y se han comprobado tres respuestas de carátulas del servidor (HTTP 200, JPEG). La compilación, los XCTest y la interacción en iPhone/iPad requieren Xcode y siguen pendientes.

## Cambios en 0.5

- **Descubre** aparece como subsección plegable dentro de Servidor y Mi iPhone/Mi iPad. El selector de rueda usa vibración de selección nativa. Elige una carpeta y abre un feed de canciones a pantalla completa con reproducción automática y portada grande.
- Deslizar a la izquierda descarta para esta sesión; a la derecha guarda Me gusta y pasa a la siguiente. Los botones ofrecen las mismas acciones. Arriba pasa a la siguiente, abajo vuelve a la anterior. Descartar conserva canciones y favoritos existentes. Guardar una canción ya marcada conserva el corazón. El último paso muestra cuántas canciones se han guardado.
- Los favoritos locales se comparten con las demás vistas locales y el reproductor. Los del servidor se guardan en su API y son visibles en las demás apps que usan esos likes. Los fallos al guardar mantienen la canción abierta para reintentar.
- En **iOS 26 con Xcode 26 o posterior**, el mini reproductor ocupa el accesorio nativo de la barra de pestañas con Liquid Glass. La barra se compacta al bajar y el reproductor aparece a su lado; al subir se expande. Las versiones anteriores mantienen las pestañas nativas y usan un mini reproductor flotante con material translúcido. iPad con barra lateral conserva el reproductor flotante.
- Todas las secciones usan un encabezado con 20 puntos de margen superior. Los buscadores siguen fijos y se mantiene el espacio desplazable inferior.

## Cambios en 0.4

- El reproductor ampliado se muestra sobre las bibliotecas, con la navegación nativa siempre accesible. Minimizar restaura la navegación anterior. Cambiar de sección minimiza el reproductor y conserva el audio y su cola.
- **Mi iPhone → Añadir → Añadir carpeta** abre el selector de carpetas de Archivos. La sección Añadir se puede plegar y recuerda su estado. Importa una copia de los audios y usa la carpeta seleccionada como contenedor y guarda sus carpetas hijas como playlists. Por ejemplo, sesion/House y sesion/Techno aparecen como House y Techno. Si no hay subcarpetas, la carpeta seleccionada se convierte en playlist. La cuadrícula usa el mismo diseño que Servidor; cada carpeta abre directamente sus canciones y subcarpetas. Mis playlist y la pestaña Playlists muestran las playlists hijas del contenedor importado; las subcarpetas más profundas aparecen dentro de cada playlist. Las carpetas ya importadas se pueden guardar como playlist sin volver a copiar los archivos.
- **Mi iPhone → Mis playlist** muestra las carpetas importadas con la portada de la primera canción de la carpeta o de su primera subcarpeta. Al pulsar se abren directamente sus canciones y las subcarpetas, respetando la jerarquía original. Música de tu dispositivo aparece al final.
- El buscador de las bibliotecas permanece fijo bajo el título. Las playlists permiten ordenar A–Z/Z–A y filtrar carpetas con favoritos; las canciones permiten filtrar favoritas y ordenar por nombre, artista, duración o el orden personalizado. Los títulos y secciones tienen más separación. Todas las listas y la cola tienen 32 puntos de espacio desplazable al final, además del espacio reservado al reproductor y la navegación, para dejar accesible el último elemento.
- En una carpeta del servidor, pulsa el botón **Añadir carpeta como playlist** de la barra superior. La playlist guarda la dirección del servidor original y consulta la carpeta al abrirse.
- **Playlists** reúne las carpetas guardadas y los apartados Me gusta para archivos de Wave, biblioteca Música y servidor. Reproducir playlist carga las canciones visibles de esa carpeta en la cola, respetando el orden y la ocultación.
- Los botones de corazón están en las filas de canciones, el reproductor compacto, el ampliado y la cola. Los likes del servidor se leen y guardan con `/api/likes` y `/api/like`, compartidos con Wave web. Los likes de archivos importados y biblioteca Música se guardan en el dispositivo, sin modificar los favoritos de Apple Music.
- El botón Eliminar playlist está visible en la cuadrícula, la pestaña Playlists y la carpeta guardada. Elimina el acceso guardado y conserva audios y likes. La eliminación persiste al reiniciar. Volver a importar puede añadir ese acceso otra vez, sin duplicar canciones.

Las carpetas locales se reproducen desde las copias importadas en Wave; no se vigilan cambios posteriores en la carpeta de origen. La reproducción de Música, servidor, importaciones y Spotify conserva las condiciones descritas abajo.

## Ver la música del iPhone/iPad

Abre **Mi iPhone → Biblioteca de Música → Permitir acceso a Música**. Wave consulta las canciones, álbumes, artistas y playlists de la app Música mediante MediaPlayer. El permiso incluye la explicación `NSAppleMusicUsageDescription`. Si lo deniegas, la pantalla permite abrir los ajustes de Wave; si el dispositivo lo restringe, muestra esa situación.

Dentro de las canciones, **Solo en el dispositivo** está activado inicialmente. Desactívalo para ver también contenidos en iCloud. Se muestran las portadas disponibles y puedes buscar por canción, artista o álbum. La reproducción de esta biblioteca usa el reproductor nativo de Apple; el acceso a canciones protegidas o en la nube depende de su disponibilidad y de la cuenta de Música. No copia ni extrae esos archivos protegidos.

Para MP3, WAV y otros archivos accesibles desde Archivos, usa **Mi iPhone → Añadir → Importar canciones** o **Añadir carpeta**. Wave crea copias propias, importa subcarpetas, lee metadatos y permite escucharlas sin internet después de la importación. Los originales permanecen en su ubicación. Reimportar la misma carpeta omite archivos con la misma carpeta, nombre original y contenido SHA-256. Al actualizar, los duplicados anteriores se retiran automáticamente de la biblioteca y los favoritos se trasladan a la copia conservada. Se preservan los archivos de audio y respaldos del registro previo para recuperar la organización si fuera necesario. Desinstalar Wave elimina sus copias.

## Bibliotecas y reproductor

- **Servidor:** explorador de carpetas con portadas, todas las canciones, búsqueda, orden personalizado/nombre/duración. Avanzada muestra archivos y canciones ocultas. Desliza una fila para ocultarla o mostrarla; Editar permite cambiar el orden personalizado. Los cambios se guardan en la organización del servidor compartida con la app de Mac.
- **Archivos de Wave:** carpetas, todas las canciones, búsqueda, ocultar/mostrar y orden editable. Avanzada recupera canciones ocultas. El orden y la biblioteca persisten al volver a abrir.
- **Biblioteca de Música:** canciones, álbumes, artistas, playlists, portadas y reproducción nativa. Los cambios de organización de Wave no modifican esta biblioteca del sistema.
- **Spotify:** búsqueda con mercado y paginación; abre resultados en Spotify para escucharlos, como la versión de Mac. Las credenciales permanecen en el servidor, que entrega un token temporal. No integra reproducción completa de Spotify dentro de Wave.
- **Reproductor:** continúa al navegar. Compacto y ampliado, cola, reproducción/pausa, anterior/siguiente, progreso, búsqueda temporal, aleatorio y repetición de cola. Comandos multimedia, audio en segundo plano y gestión básica de interrupciones.
- **Diseño:** fondo cálido y acento verde de Wave para Mac; pestañas nativas de Apple en iPhone y barra lateral en pantallas anchas. iPhone e iPad declaran las cuatro orientaciones.

## Qué se ha comprobado

En Linux se ha analizado la sintaxis de todos los archivos Swift y se ha leído el proyecto con un parser OpenStep independiente. Se ha comprobado que cada archivo Swift pertenece al target correcto, el scheme ejecuta Wave y los permisos, versión y orientaciones coinciden. También se valida la estructura e integridad del ZIP de entrega. Los tests de Descubre comprueban direcciones y umbrales de gestos para evitar guardar por un desplazamiento vertical o un gesto corto.

**No se ha compilado con Xcode ni ejecutado los XCTest ni la app en un dispositivo desde este entorno.** Esas comprobaciones requieren un Mac y un iPhone/iPad. El análisis de sintaxis no comprueba todos los tipos ni sustituye al compilador de Swift.

Con un simulador instalado, puedes ejecutar los tests:

```sh
xcodebuild -project Wave.xcodeproj -scheme Wave -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Ajusta el nombre del simulador. Los tests añadidos de preferencias cubren persistencia de likes, separación por origen, duplicados de playlists, eliminación sin perder likes, sincronización del servidor y conservación de datos corruptos. Los demás tests cubren rutas/prefijo de servidor, portadas, contrato JSON, orden/ocultación, peticiones de organización, importación WAV, copia independiente del original, persistencia, subcarpetas, audio inválido y conservación de un manifiesto corrupto. La biblioteca Música del dispositivo necesita probarse en hardware real; el simulador no contiene la biblioteca del iPhone.

## Desarrollo

`project.yml` sigue disponible para usuarios de XcodeGen. Alternativamente, `python3 scripts/generate-project.py` regenera el proyecto incluido usando solo la biblioteca estándar de Python. Regenerar puede borrar la selección local de Team; selecciona tu equipo de nuevo. No se incluye ninguna cuenta, certificado ni credencial de Apple en el paquete.

Quedan pendientes la bandeja de copias y edición de archivos como en Mac, las descargas del servidor para escucha sin conexión, las formas de onda y la paridad completa con todas las funciones de escritorio. Tampoco se actualizan todavía los contadores de reproducciones del servidor.
