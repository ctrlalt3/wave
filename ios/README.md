# Wave para iPhone e iPad · 0.7.6 (build 19)

Esta actualización incluye el proyecto `Wave.xcodeproj`, las fuentes y `Info.plist`. Se puede abrir directamente en Xcode: **no hace falta ejecutar XcodeGen**. Se mantiene el identificador `app.wave.music.ios` para actualizar la app instalada sin borrar sus archivos importados.

## Instalar la actualización en el Mac

1. Cierra Xcode por completo con `⌘Q`.
2. Descomprime `Wave-iOS-0.7.6.zip` en una carpeta nueva. No lo mezcles con la copia antigua.
3. Dentro de `Wave-iOS-0.7.6`, abre **Wave.xcodeproj**.
4. En TARGETS → Wave → Signing & Capabilities, activa Automatically manage signing y selecciona tu Team.
5. Arriba, selecciona el scheme **Wave** y tu iPhone o iPad conectado.
6. Pulsa Ejecutar (`⌘R`).

La app nueva muestra **WAVE 0.7.6** arriba y cinco secciones: **Servidor**, **Mi iPhone/Mi iPad**, **Playlists**, **Spotify** y **Ajustes**. Ajustes muestra la versión del bundle `0.7.6`, build `19`. Si solo ves la lista antigua de carpetas sin estas secciones, esa ejecución sigue usando la versión anterior. Rebuild y Relaunch recompilan/reabren el proyecto seleccionado; no copian las fuentes del servidor al Mac. Verifica la carpeta del proyecto con Show in Finder sobre el proyecto en Xcode.

No desinstales la app para actualizarla si quieres conservar tus archivos importados. La app instalada puede abrirse sin el cable de Xcode; el servidor y los contenidos en la nube necesitan conexión de red.

## Carátula y favoritos en los controles de iOS (0.7.6)

Los metadatos de reproducción incluyen la carátula del servidor, la imagen incrustada en archivos locales o la portada de Música del dispositivo. La carga usa la caché existente, no bloquea la reproducción y descarta resultados antiguos al cambiar de canción.

El comando nativo Me gusta utiliza los mismos favoritos persistentes de Wave. Su estado se actualiza al cambiar de canción y al marcar/desmarcar desde la app. Durante un guardado se desactiva para evitar operaciones duplicadas. iOS decide la presentación y disponibilidad de este comando en cada superficie del sistema.

Se mantiene la navegación y el mini reproductor restaurados en 0.7.5. Sintaxis y paquete comprobados en Linux; compilación y validación en pantalla bloqueada/Centro de control pendientes de Xcode e iPhone.

## Restauración de navegación y mini reproductor (0.7.5)

Se parte de las fuentes de Claude 0.7.4 y se recuperan de 0.5 el comportamiento de navegación y el accesorio del mini reproductor:

- La barra usa directamente la contracción nativa de iOS 26 (`onScrollDown`), sin seguimiento paralelo del scroll ni cambios temporizados de comportamiento.
- El mini reproductor vuelve a su disposición original según la colocación nativa, con portada, título y pausa; en la colocación ampliada muestra también artista, corazón y siguiente. Se elimina el cálculo manual de anchos y la animación superpuesta.
- El reproductor ampliado se abre dentro de la pestaña y conserva visible la navegación; al cerrarlo se recupera la biblioteca y su posición. Se retira la presentación modal con zoom y el desplazamiento global de la navegación por gestos de cabecera, recuperando el comportamiento de 0.5.
- Se conservan las funciones y el diagnóstico de favoritos de Claude 0.7.4, las cabeceras fijas, los márgenes, la onda, las mejoras de rendimiento y los gestos de portada del reproductor.

Comprobados sintaxis Swift, referencias del proyecto y contenido del paquete en Linux. La compilación, los XCTest y la transición visual nativa requieren validación en Xcode/iOS; no se han ejecutado en este entorno.

## Diagnóstico del Me gusta de Descubre que no aparece en su carpeta (0.7.4)

El arreglo de 0.7.1 (recursión por subcarpetas + método compartido `LocalLibrary.songs(in:recursive:advanced:)`) no resolvió el caso reportado: una canción que ya vive en una carpeta/playlist concreta, al recibir Me gusta desde Descubre, sigue sin aparecer en la lista de **esa misma carpeta**, aunque sí aparece correctamente en Playlists → "Archivos que te gustan" (el listado global, sin filtrar por carpeta).

Que aparezca en el listado global descarta un fallo de guardado: la clave de favorito se guarda bien. El problema solo puede estar en el filtro por carpeta exacta (`song.folder == folder`) de esa canción en concreto, y sin ver los datos reales del dispositivo no se puede confirmar a ciegas — ya se gastaron dos intentos (0.7.1) sin acertar.

Para cortar la adivinanza, la vista **Avanzada** de Mi iPhone/Playlists ahora muestra, bajo cada canción, su carpeta real (`LocalSong.folder`). Antes de seguir cambiando lógica de filtrado, compara ese texto con el nombre/ruta exacta de la carpeta que tienes abierta (mayúsculas, subcarpetas, espacios) para la canción que "desaparece", y repórtalo: con ese dato se puede aplicar el arreglo correcto con certeza, en vez de otra suposición.

## Corrección de expansión y contracción en 0.7.3

El accesorio nativo tenía una segunda animación de SwiftUI aplicada a su contenido. Al cambiar el estado de colocación, los controles adicionales se insertaban antes de que el contenedor alcanzara su ancho final, y los títulos conservaban espacio intrínseco mientras el ancho se reducía.

- Se conserva la transición exterior de iOS; se retiran las animaciones de geometría superpuestas sobre el contenido y el cambio de comportamiento de la barra.
- El contenido se calcula desde el ancho que propone el contenedor en cada instante. Los controles adicionales solo aparecen en estado expandido cuando el ancho disponible es al menos 280 puntos; reproducir/pausar permanece accesible en el estado compacto.
- Los títulos tienen un ancho explícito, una línea y truncamiento final. La portada y los controles reservan su espacio. El artista conserva una estructura estable y se oculta en el estado compacto. Todo el contenido se recorta dentro de sus límites.
- Los controles del accesorio tienen 44 × 44 puntos y su altura es constante (52 puntos incluidos los márgenes). El corazón conserva su tamaño anterior en las filas de canciones. Los títulos del reproductor de iOS 17–25 también pueden comprimirse.
- Se conservan favoritos de 0.7.1, navegación, reproductor ampliado, onda, progreso, cola y los gestos de 0.7.2.

Se añaden XCTest que recorren 0–500 puntos de ancho para ambos estados, incluidos los anchos intermedios de expansión/contracción, y verifican que las dimensiones no exceden el contenedor. Sintaxis Swift, referencias del proyecto y ZIP verificados en Linux. Estos XCTest y la transición visual nativa no se han ejecutado aquí: requieren Xcode y un iPhone con iOS 26. Probar títulos y artistas largos, scroll en ambos sentidos desde mitad de la lista, varias inversiones seguidas, tamaños de texto grandes y cambios de orientación.

## Cambios en 0.7.2

- Cabeceras opacas y fijas para WAVE y Reproduciendo/Volver/Cerrar, sin Liquid Glass. Títulos y buscadores permanecen fuera del contenido que se desplaza; el buscador de Spotify ahora usa esa cabecera común. Listas con 16 puntos de margen superior.
- Encabezados de Playlists y Carpetas con fondo opaco, conservando la fijación nativa de las secciones de List. Las filas, favoritos y acciones siguen dentro de sus secciones.
- Expansión/contracción del accesorio del reproductor con la misma curva de 240 ms en ambos sentidos. Se conserva TabView y la contracción nativa de iOS 26; el comportamiento visual nativo requiere validación en ese sistema.
- Deslizar la cabecera WAVE cambia a la sección adyacente con respuesta breve, sin interferir con la onda, acciones de las filas ni el gesto nativo de volver. No salta de la última sección a la primera.
- La portada del reproductor sigue el dedo: izquierda/derecha cambia de canción; arrastrar hacia abajo cierra. Transiciones de portada de 180 ms; cancelar un gesto restablece su posición automáticamente. Descubre conserva sus acciones de guardar/descartar con respuesta discreta de la portada. Reducir movimiento desactiva estos desplazamientos.
- Tocar/soltar la onda actualiza inmediatamente la posición visible. Las respuestas antiguas y el temporizador no sobrescriben una búsqueda pendiente; las búsquedas posteriores cancelan la anterior. El buffering de la red sigue dependiendo de la conexión.
- Carátulas remotas y locales decodificadas fuera del hilo principal y limitadas a 1024 píxeles; las de Música no se regeneran en cada evaluación de la vista. Resúmenes de carpeta se calculan cuando cambia la colección, y las pantallas filtran una vez por evaluación.
- Se conservan la biblioteca importada, favoritos, playlists, cola, reproducción en segundo plano, menús, orden y los ajustes. Se mantienen las correcciones de favoritos que se incorporaron simultáneamente en 0.7.1.

Validación en este entorno Linux: sintaxis de todos los archivos Swift con tree-sitter, referencias del proyecto Xcode e integridad del ZIP. Se añaden XCTest de navegación por gestos, búsqueda inmediata y resúmenes de carpeta. Pasan las nueve pruebas Python de favoritos/API del servidor. No se han ejecutado XCTest, compilado con SDK de iOS ni medido FPS/memoria en dispositivo. En tu Mac, ejecuta Product → Test y prueba con iPhone; usa Product → Profile para medir Time Profiler/Allocations sin confundir la lentitud del modo Debug con la build Release.

## Corrección del Me gusta de Descubre en 0.7.0/0.7.1

Desde la 0.6.4 quedaba pendiente investigar por qué un Me gusta guardado en Descubre no siempre aparecía al filtrar la playlist de origen. La causa: Descubre recorre una carpeta **y sus subcarpetas** al armar el mazo de canciones, pero el filtro "Solo favoritas" de esa misma carpeta en Mi iPhone/Playlists solo miraba las canciones de esa carpeta exacta, sin bajar a las subcarpetas. El corazón sí se guardaba (se veía marcado dentro de Descubre), pero la canción vivía en una subcarpeta y la lista de esa playlist la dejaba fuera al filtrar.

La 0.7.1 va más allá de ajustar el filtro: Descubre y las playlists/carpetas locales ahora llaman al mismo método (`LocalLibrary.songs(in:recursive:advanced:)`) para decidir qué canciones pertenecen a una carpeta, en vez de reimplementar el recorrido por separado en cada sitio. El chequeo de "¿esta canción tiene Me gusta?" también pasa por un único punto (`LocalLibrary.liked(_:in:)`). Así, Descubre y la lista nunca pueden quedar desincronizados sobre qué cuenta como parte de una carpeta.

También se añade el mismo filtro "Solo favoritas" a Mi iPhone → Biblioteca de Música (álbumes, artistas, playlists y Todas las canciones), con el mismo comportamiento que ya tenían las playlists de archivos y de servidor.

## Corrección de navegación y carátulas

La 0.6.5 recupera la navegación nativa y el accesorio de reproducción de la 0.6.2. En iOS 26, el seguimiento del scroll solicita que la barra se expanda al subir desde cualquier posición. En pantallas anchas se conserva la barra lateral. La vista ampliada se presenta por separado y sus botones Volver/Cerrar restauran la biblioteca y carpeta abiertas. Minimizar conserva la carpeta abierta; cambiar de sección muestra esa biblioteca sin interrumpir el audio.

Las carátulas de Música, servidor y cola se pasan al componente de imagen. Los archivos importados leen su imagen incrustada, incluidos los que ya estaban importados. Si el servidor omite `coverUrl`, se consulta el endpoint de artwork de la canción. Los archivos sin imagen incrustada muestran el símbolo de música.

Se ha validado la sintaxis Swift y se han comprobado tres respuestas de carátulas del servidor (HTTP 200, JPEG). La compilación, los XCTest y la interacción en iPhone/iPad requieren Xcode y siguen pendientes.

## Scroll en ambas direcciones en 0.6.6

Se mantiene el aspecto nativo de la 0.6.2. Subir solicita expandir la barra con una excepción temporal de 240 ms; después se restablece automáticamente el comportamiento nativo de contracción al bajar. Cambiar hacia abajo cancela de inmediato la excepción, evitando que la barra quede fijada abierta. No hace falta llegar al comienzo de la lista ni cambiar de sección para repetir el ciclo. Se añade una prueba de cambios de dirección repetidos. La sintaxis y el ZIP están verificados; XCTest y comportamiento visual requieren Xcode e iPhone con iOS 26.

## Navegación restaurada en 0.6.5

Se recuperan el TabView, las pestañas nativas y el accesorio de reproducción de la 0.6.2. En iOS 26, bajar permite contraer la barra nativa y subir más de 16 puntos cambia el comportamiento a `never`, solicitando su expansión sin tener que alcanzar el comienzo de la lista. No se cambia el offset ni se reconstruye el TabView. En iOS anteriores se mantienen las pestañas nativas visibles y el reproductor flotante de la 0.6.2. Se retiran las barras personalizadas de las 0.6.3/0.6.4. El resto de funciones, corazones, progreso, menús y transición del reproductor se conservan.

Sintaxis y proyecto verificados. La expansión visual de la barra nativa requiere validar en un iPhone con iOS 26 y Xcode; no se ha ejecutado aquí.

## Ajuste de navegación en 0.6.4

La navegación y el mini reproductor vuelven a tener silueta de cápsula y comparten exactamente la misma anchura y márgenes en todos los estados. En iOS 26 usan Liquid Glass nativo; en versiones anteriores, material ultrafino. Al contraerse se ocultan las etiquetas de navegación y se conserva el ancho de ambos paneles, junto con los controles de la canción. El fondo común sigue retirado y el scroll hacia arriba expande la navegación en cualquier punto. La estructura permanece estable durante la transición para evitar reemplazos de vistas. Se mantiene la opción de desactivar efectos.

Esta revisión cambia exclusivamente la presentación de navegación y mini reproductor; la investigación del guardado de Me gusta en Descubre sigue pendiente.

## Cambios en 0.6.3

- Los favoritos locales anteriores conservan su identificador y su almacenamiento. Al conectar con cada servidor se reconcilian una sola vez los favoritos que constan en el dispositivo pero faltan en la respuesta del servidor. La marca de recuperación persiste para no restaurar favoritos que se quiten después. Un intento antiguo que no dejó ningún registro no puede reconstruirse. Los fallos de recuperación mantienen el registro para reintentar.
- Las filas de canciones ocupan toda la anchura y su rectángulo visible es pulsable, incluidas las separaciones. Los corazones tienen una zona de 48 × 56 puntos; seleccionados son rojos, sin seleccionar son blancos en oscuro y negros en claro, con sombra sutil. Durante la sincronización el toque queda en espera y muestra progreso en lugar de ignorarse.
- Fondos de página más claros en oscuro y controles con Liquid Glass nativo en iOS 26; versiones anteriores usan material translúcido. Ajustes → Apariencia → Liquid Glass y animación del reproductor desactiva los efectos personalizados y la transición zoom. Reducir transparencia y Reducir movimiento del sistema también se respetan. Los menús del sistema conservan su aspecto nativo de iOS.
- Menú contextual de las canciones y mini reproductor al mantener pulsado, con respuesta háptica: reproducir, cambiar Me gusta, reproducir después, añadir a la cola y pausar/continuar la canción actual. No se duplican canciones ya presentes en la cola ni se mezclan archivos de Wave con el reproductor Música.
- Navegación flotante de mayor ancho y mini reproductor más alto, sin placa de fondo común. Se contraen al bajar y se expanden al subir desde cualquier parte de la lista. La lista conserva su espacio inferior durante el cambio para evitar saltos. La transición de apertura/cierre del reproductor usa zoom nativo desde el mini reproductor en iOS 18 o posterior cuando los efectos están habilitados; iOS 17 usa la presentación estándar.
- Se mantienen el progreso independiente, la caché de portadas y el análisis compartido de ondas de la 0.6.2. Los menús construyen la cola cuando se ejecuta una acción, sin convertir toda la biblioteca por cada fila.

Validación: sintaxis Swift, proyecto Xcode, integridad del ZIP y pruebas Flask. Se añaden XCTest de formato antiguo y recuperación única de favoritos. No se ha compilado, ejecutado XCTest ni probado hit targets, gestos, háptica o efectos en un iPhone/iPad: requieren Xcode y dispositivo. Liquid Glass nativo requiere compilar con Xcode 26.

## Correcciones en 0.6.2

- Descubre y los corazones de las listas usan una única operación de persistencia, para archivos locales y servidor. Guardar fija el corazón en activo; solo se retira la canción de Descubre cuando la escritura se confirma. Se conserva la carpeta y el ID de la canción.
- El servidor acepta `POST /api/like` con `{track, liked: true/false}` para fijar un favorito sin invertirlo al repetir la petición. El formato anterior `{track}` sigue alternando el corazón para los clientes web. La app comprueba la respuesta y es compatible con servidores antiguos que solo alternan.
- El progreso del audio se publica por separado: las bibliotecas y portadas no se invalidan cada medio segundo. Solo las barras de progreso y ondas siguen esos cambios. La frecuencia del progreso se conserva.
- Descubre conserva su lista entre cambios de favoritos, en lugar de refiltrar toda la carpeta durante cada movimiento del dedo. Las solicitudes simultáneas de una misma onda comparten la descarga y el análisis; el trabajo se cancela cuando no queda ninguna vista esperando.
- Se mantienen las pestañas nativas de la 0.5, los fondos unificados, las ondas reales, controles, búsqueda, cola y todas las demás funciones de la 0.6.

Validación de esta revisión: cinco pruebas del endpoint Flask pasan; sintaxis Swift, proyecto Xcode e integridad del ZIP validados. Se añaden XCTest de guardado remoto, compatibilidad, errores, progreso independiente y onda compartida. La compilación, estos XCTest y la medición de fluidez en dispositivo requieren Xcode y no se han ejecutado aquí.

## Cambios en 0.6

- Las bibliotecas de servidor, Mi iPhone/Mi iPad, Playlists, Música del dispositivo, resultados de Spotify y cola usan el mismo diseño de filas, portadas y espaciado. Se conserva la jerarquía dentro de las playlists. Los botones duplicados de Eliminar playlist se han retirado; Quitar playlist aparece al deslizar las filas guardadas y conserva el audio.
- La apariencia sigue iOS automáticamente, incluidos claro, oscuro y colores semánticos. Ajustes → Apariencia permite usar Sistema o elegir Claro/Oscuro y un color de acento.
- Descubre utiliza la portada como fondo de pantalla completa y un indicador de Guardar/Descartar mientras arrastras. Añade retroceder y adelantar 10 segundos y búsqueda con una forma de onda del audio.
- El reproductor ampliado muestra una portada grande, sin la etiqueta del origen. Volver y Cerrar devuelven a la carpeta abierta. Deslizar la portada a izquierda/derecha cambia de canción; hacia abajo cierra la vista. La cola usa las mismas filas que las bibliotecas.
- Ambos reproductores muestran una onda extraída del audio con AVAssetReader. Arrastrarla elige el punto de reproducción; la parte recorrida sigue el tiempo real. Para pistas del servidor se descarga temporalmente el audio para analizarlo, y se guarda solo la onda en caché durante 24 horas. Mientras carga o si el audio está protegido/no se puede analizar, se muestra una barra de progreso que permite buscar, sin inventar una onda.
- Las portadas usan una caché compartida y peticiones agrupadas; la contracción del mini reproductor conserva la imagen ya cargada.
- La 0.6.1 restaura las pestañas y el accesorio nativos de la 0.5, conservando el reproductor ampliado, las ondas y las demás funciones de la 0.6. Los contenedores, filas y cabeceras comparten el mismo fondo semántico en claro y oscuro. Descubre comparte la instancia de favoritos de la biblioteca; las lecturas de likes del servidor evitan la caché local.

## Cambios en 0.5

- **Descubre** aparece como subsección plegable dentro de Servidor y Mi iPhone/Mi iPad. El selector de rueda usa vibración de selección nativa. Elige una carpeta y abre un feed de canciones a pantalla completa con reproducción automática y portada grande.
- Deslizar a la izquierda descarta para esta sesión; a la derecha guarda Me gusta y pasa a la siguiente. Los botones ofrecen las mismas acciones. Arriba pasa a la siguiente, abajo vuelve a la anterior. Descartar conserva canciones y favoritos existentes. Guardar una canción ya marcada conserva el corazón. El último paso muestra cuántas canciones se han guardado.
- Los favoritos locales se comparten con las demás vistas locales y el reproductor. Los del servidor se guardan en su API y son visibles en las demás apps que usan esos likes. Los fallos al guardar mantienen la canción abierta para reintentar.
- En **iOS 26 con Xcode 26 o posterior**, el mini reproductor ocupa el accesorio nativo de la barra de pestañas con Liquid Glass. La barra se compacta al bajar y el reproductor aparece a su lado; al subir se expande. Las versiones anteriores mantienen las pestañas nativas y usan un mini reproductor flotante con material translúcido. iPad con barra lateral conserva el reproductor flotante.
- Todas las secciones usan un encabezado con 20 puntos de margen superior. Los buscadores siguen fijos y se mantiene el espacio desplazable inferior.

## Cambios en 0.4

- El reproductor ampliado se abre sobre las bibliotecas y conserva su navegación al cerrarse. Minimizar restaura la navegación anterior. Cambiar de sección minimiza el reproductor y conserva el audio y su cola.
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
- **Diseño:** colores semánticos de iOS y acento configurable; dock adaptable en iPhone y barra lateral en pantallas anchas. iPhone e iPad declaran las cuatro orientaciones.

## Qué se ha comprobado

En Linux se ha analizado la sintaxis de todos los archivos Swift y se ha leído el proyecto con un parser OpenStep independiente. Se ha comprobado que cada archivo Swift pertenece al target correcto, el scheme ejecuta Wave y los permisos, versión y orientaciones coinciden. También se valida la estructura e integridad del ZIP de entrega. Los tests de Descubre comprueban direcciones y umbrales de gestos. Los tests de navegación comprueban que subir expande la barra sin volver al principio; los de audio usan un WAV con silencio y señal para comprobar que la onda refleja sus muestras reales. Estos XCTest aún requieren ejecutarse en Xcode.

**No se ha compilado con Xcode ni ejecutado los XCTest ni la app en un dispositivo desde este entorno.** Esas comprobaciones requieren un Mac y un iPhone/iPad. El análisis de sintaxis no comprueba todos los tipos ni sustituye al compilador de Swift.

Con un simulador instalado, puedes ejecutar los tests:

```sh
xcodebuild -project Wave.xcodeproj -scheme Wave -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Ajusta el nombre del simulador. Los tests añadidos de preferencias cubren persistencia de likes, separación por origen, duplicados de playlists, eliminación sin perder likes, sincronización del servidor y conservación de datos corruptos. Los demás tests cubren rutas/prefijo de servidor, portadas, contrato JSON, orden/ocultación, peticiones de organización, importación WAV, copia independiente del original, persistencia, subcarpetas, audio inválido y conservación de un manifiesto corrupto. La biblioteca Música del dispositivo necesita probarse en hardware real; el simulador no contiene la biblioteca del iPhone.

## Desarrollo

`project.yml` sigue disponible para usuarios de XcodeGen. Alternativamente, `python3 scripts/generate-project.py` regenera el proyecto incluido usando solo la biblioteca estándar de Python. Regenerar puede borrar la selección local de Team; selecciona tu equipo de nuevo. No se incluye ninguna cuenta, certificado ni credencial de Apple en el paquete.

Quedan pendientes la bandeja de copias y edición de archivos como en Mac, las descargas del servidor para escucha sin conexión, la paridad completa con todas las funciones de escritorio. Tampoco se actualizan todavía los contadores de reproducciones del servidor.

Descubre comparte los Me gusta de cada carpeta y excluye las canciones favoritas. Guardar una canción la retira del recorrido, incluso al volver atrás o reiniciarlo; quitarle el Me gusta en la playlist permite descubrirla de nuevo.
