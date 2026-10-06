# Wave para iPhone e iPad · 0.11.5 (build 33)

## Correcciones de biblioteca y acceso · 0.11.5

- Navegación por carpeta → subcarpeta, pulsando o deslizando a la izquierda sobre una carpeta; deslizar a la derecha vuelve a la carpeta superior. La ruta y la flecha atrás comparten fila.
- Se publican todas las carpetas de la música importada, incluso las que no pertenecen a una playlist seleccionada. Los cambios de carpetas sin canciones visibles también actualizan el catálogo. Las filas y carátulas quedan pegadas al borde izquierdo del panel.
- Dirección compartida del servidor para app y widgets: una configuración vacía recupera el servidor habitual y se conserva una dirección personalizada. Se ha comprobado aquí que sus endpoints de carpetas y canciones responden.
- Se eliminan los títulos generales de página. Las filas se alinean a la izquierda; cambiar de carpeta mantiene la estructura estable mientras carga y evita que una actualización antigua sustituya la nueva lista.
- Widget pequeño: anterior, reproducir/pausar, siguiente y corazón sin texto en una fila. El selector Local/Servidor está al lado de Actualizar.
- Wave ya no muestra un bloqueo propio al abrir la app ni solicita Face ID para entrar.

Los controles del widget siguen sujetos a las reglas que iOS aplica cuando el dispositivo está bloqueado.

**Fuentes sin verificar en Xcode:** se validan estructura y sintaxis en Linux; la compilación, XCTest y revisión en dispositivo quedan pendientes. Ejecuta `python3 scripts/validate-xcode.py` en un Mac antes de considerar esta entrega verificada.


## Ajustes de En reposo y controles del widget · 0.11.3

Esta variante continúa sobre la base 0.11, con la presentación a pantalla completa de 0.11.2 y los ajustes solicitados:

- Se elimina el encabezado general Biblioteca y su fila. El cierre se integra en los controles del selector.
- El selector gana 12 puntos de margen superior y 10 a la izquierda; títulos y subtítulos se alinean explícitamente a la izquierda. Las canciones muestran una miniatura de 44 puntos: imagen incrustada para archivos locales y carátula de Wave para canciones del servidor. Si no hay imagen, se mantiene el símbolo de música.
- El nombre de biblioteca es un menú **Local / Servidor**. La segunda zona es un menú de **carpetas** de la fuente actual, con ruta, inicio y salto directo entre carpetas conocidas; la flecha permite subir al padre.
- Separación entre paneles de 14 puntos y reproductor 18 puntos más ancho que en 0.11.2. La lista conserva sus filas y páginas de 24 elementos.
- Reproductor con nombre/artista arriba, portada mayor en el centro y barra y controles abajo. Me gusta sigue en la fila de transporte; no se añade scroll independiente al reproductor.
- Atenuación de la vista de Wave tras 20 segundos sin tocar; tocar o desplazar ilumina de nuevo. Ajustes permite desactivarla. No se modifica el brillo global ni el bloqueo automático del dispositivo.
- **Widget Wave · Reproduciendo**: anterior, reproducir/pausar, siguiente y Me gusta en el pequeño; corazón operativo en formatos mayores y controles compactos en el rectangular de pantalla bloqueada. El formato circular sigue dedicado a reproducir/pausar y el formato en línea es informativo.

El corazón del widget usa el mismo almacenamiento de favoritos que Wave y confirma el estado solicitado en lugar de invertirlo varias veces si se repite una acción. Una representación vieja no puede marcar por error una canción nueva. En las canciones vinculadas a un servidor, guardar Me gusta requiere que el servidor confirme la operación. Los controles se ejecutan mediante App Intents.

Los controles multimedia del sistema (el reproductor de iOS, fuera del widget Wave) los presenta Apple. Wave registra los comandos anterior y Me gusta, pero iOS decide qué botones muestra en cada superficie.

Esta entrega es un **candidato de fuentes** pendiente de compilación y revisión visual en Xcode. Aquí se comprueban proyecto, sintaxis y bloqueo de publicación. Se incluyen XCTest de favoritos idempotentes y salto entre carpetas para ejecutar en Mac.

Antes de publicar una versión verificada:

```sh
python3 scripts/validate-xcode.py
python3 scripts/package-release.py --output releases/verified
```

Comprueba en dispositivo el tamaño de la portada, la posición inferior de los controles, la alineación de las filas, las miniaturas, el cambio Local/Servidor y el nuevo corazón en widgets pequeños y rectangulares.


## Pantalla completa real y controles en una fila · 0.11.2

Esta variante continúa sobre 0.11 y no incluye funciones de 0.12. Cambia únicamente la presentación En reposo de Wave:

- Se presenta con `fullScreenCover` fuera de la superposición de la biblioteca y su `GeometryReader` mide el área completa de la ventana.
- El fondo y las filas de biblioteca se extienden hasta los laterales, con sólo 6 puntos de margen exterior. El texto de las filas y los controles respetan la zona de cámara y el indicador inferior.
- Se mantiene la biblioteca como panel principal, con las mismas filas y páginas de 24 elementos. El espacio recuperado se reparte entre biblioteca y reproductor.
- Se elimina el `ScrollView` independiente del reproductor. Portada y metadatos se compactan en una fila; anterior, reproducir/pausar, siguiente y Me gusta comparten otra fila.

Compilación y revisión visual pendientes de Xcode. Esta descarga es un candidato de fuentes; el empaquetador sigue exigiendo compilación y XCTest para una versión verificada.


## Ajuste exclusivo de ancho · 0.11.1

Esta variante parte de las fuentes exactas de 0.11.0, sin incluir cambios de 0.12. Sólo modifica la distribución horizontal de En reposo de Wave:

- Márgenes laterales de 16 a 6 puntos.
- Separación entre paneles de 16 a 8 puntos.
- Los 36 puntos recuperados se asignan al reproductor, conservando el ancho anterior de la biblioteca.
- Lista, filas, scroll, páginas de 24 elementos y distribución vertical permanecen como en 0.11.

Fuentes pendientes de compilación y comprobación visual con Xcode. El empaquetado verificado sigue bloqueado sin la validación real.


## Espacio horizontal, navegación y biblioteca En reposo · 0.11.0

Esta entrega incluye las correcciones de carátulas opcionales de 0.9.1 y de coordinación de archivos de 0.10.1. El acceso compartido utiliza `NSFileCoordinator`; no vuelve a invocar `Darwin.flock`.

Cambios de interfaz:

- Fondo y contenedores de Wave ocupan el área completa, incluidas las zonas seguras que antes podían mostrar una franja negra en horizontal. Los controles siguen respetando la cámara y los márgenes del dispositivo.
- Se retiran el banner superior fijo y la cabecera fija adicional de las listas. El nombre de la página ocupa la fila nativa de navegación, a la misma altura que Atrás. El buscador usa el cajón nativo con presentación automática, que se contrae al desplazarse. El título compacto permanece en la fila de navegación para identificar la carpeta actual.
- Navegación lateral centrada, con 12 puntos de margen horizontal, 16 verticales, separación entre bibliotecas y utilidades y controles de al menos 44 puntos. En ventanas bajas el menú se puede desplazar para acceder a todas sus opciones.
- **En reposo de Wave muestra siempre la biblioteca navegable**, con Local/Servidor, carpeta superior y canciones. Se eliminan reloj, fecha y el modo que ocultaba la biblioteca.
- La biblioteca ocupa la mayor parte del ancho; el reproductor queda en un panel menor, con portada de 88 puntos, controles centrados y barra de reproducción. Las listas presentan filas más legibles y hasta 24 elementos por página, con scroll dentro de esa página.
- En el reproductor ampliado también se reemplaza la onda por una barra y se centran los controles; en horizontal se limita la portada para dejar más ancho a la cola. Descubre conserva su propia onda.

La presentación En reposo del sistema iOS sigue bajo control de Apple; estos cambios en reloj y distribución corresponden a la vista En reposo **dentro de Wave**. Sus widgets de biblioteca y reproducción continúan conectados.

### Compilación antes de publicar

Esta descarga se genera como **candidato de fuentes**, no como una versión compilada. En Linux se comprueban el proyecto, la sintaxis y el bloqueo de empaquetado. Se incluyen XCTest para los rangos de la barra, orientación y navegación de páginas de 24 elementos, pero no se han ejecutado aquí.

En un Mac con Xcode completo:

```sh
python3 scripts/validate-xcode.py
python3 scripts/package-release.py --output releases/verified
```

El primer comando compila Wave y WaveWidgets y ejecuta XCTest. Si falla, el empaquetador no permite una versión verificada. Un cambio de fuentes invalida el resultado anterior. Consulta `validation/xcode-build.log` para el diagnóstico.

Comprueba en iPhone e iPad:

1. Girar en Local, Servidor, Playlists, Spotify y Ajustes; comprobar el fondo hasta los bordes y que no existe una columna negra junto al menú.
2. Entrar en una subcarpeta: comprobar que título y Atrás comparten fila, desplazar la lista y verificar la contracción del buscador nativo.
3. Abrir En reposo: no debe mostrar reloj ni fecha. Navegar por Local/Servidor y subcarpetas, seleccionar una canción y pasar páginas de 24 elementos.
4. Arrastrar la barra de progreso, pausar, cambiar de canción y confirmar que los controles permanecen centrados; probar también VoiceOver y Texto grande.
5. Repetir en un iPhone pequeño, con teclado abierto y reduciendo el movimiento. Los elementos que no caben deben poder alcanzarse por scroll.

Referencia: [buscador nativo y ocultación automática](https://developer.apple.com/documentation/swiftui/searchfieldplacement/navigationbardrawer).


## Selector de música en widgets y En reposo · 0.10.0

Esta versión incorpora la corrección de carátulas opcionales de **0.9.1** y permite explorar carpetas y seleccionar canciones sin abrir la interfaz de Wave al pulsar los botones del widget.

### Qué widget elegir

- **Wave · Reproduciendo**: reproductor con los controles existentes y la canción seleccionada en la biblioteca.
- **Wave · Elegir canción**: sustituye al widget Tu biblioteca, conservando su identificador para actualizarlo. Permite cambiar entre **Local** y **Servidor**, abrir carpetas, subir a la carpeta superior, pasar páginas y tocar una canción para reproducirla. Tamaños pequeño, mediano, grande y extra grande; el formato rectangular de pantalla bloqueada ofrece controles compactos. El formato en línea permanece de lectura y acceso, porque iOS no admite botones de navegación en esa familia.
- **Wave · Biblioteca y reproductor**: widget grande/extra grande con selector y controles de audio en una sola pieza, para Inicio o iPad.

En **En reposo de iOS**, coloca **Reproduciendo** en un lado y **Elegir canción** en el otro. iOS admite dos widgets pequeños lado a lado, no un widget grande que ocupe toda esa pantalla. El selector pequeño muestra un elemento por vez: carpeta o canción, con flechas para recorrer la lista. Las acciones se realizan por botones y páginas; no se simula una lista con scroll ni un campo de búsqueda que WidgetKit no pueda ejecutar.

Dentro de **En reposo de Wave**, con la app abierta, sí hay una vista completa con biblioteca a la izquierda y reproductor a la derecha. Elige Local o Servidor y una canción sin cerrar esa vista. El botón Solo reproductor permite ocultar la biblioteca y recuperarla después. La onda y los controles se mantienen.

### Preparar y usar

1. Instala **Wave-iOS-0.10.0.zip** desde `Wave.xcodeproj`, con el mismo Team y el App Group **group.app.wave.music** en Wave y WaveWidgets. Consulta más abajo las instrucciones de firma.
2. Abre Wave una vez para publicar las carpetas locales. Los archivos importados permanecen en el contenedor privado; el widget comparte títulos, artistas, identificadores y pequeñas páginas de metadatos, no archivos de audio.
3. Guarda la dirección HTTPS del servidor en Ajustes. El selector usa esa dirección y mantiene la subruta del servidor, por ejemplo `/wave/`.
4. Añade **Elegir canción** y **Reproduciendo** desde la galería de widgets, o el widget grande **Biblioteca y reproductor**.
5. Pulsa **Local / Servidor** para cambiar de biblioteca. Pulsa una carpeta para entrar, la flecha de volver para subir y las flechas de página para recorrer sus elementos. En el widget pequeño, Actualizar aparece al estar en la raíz; en los formatos más grandes hay un botón independiente.
6. Pulsa una canción para reproducirla y crear la cola con las canciones visibles de esa carpeta. El otro widget se actualiza con su título y controles. Navegar o actualizar la biblioteca no cambia la cola hasta elegir una canción.
7. En reposo de iOS: carga el iPhone horizontal, bloquea la pantalla y añade los dos widgets pequeños. Los controles funcionan mediante App Intents; iOS puede solicitar autenticación antes de ejecutar una interacción en un dispositivo bloqueado.

La carpeta, biblioteca y página del selector se comparten entre los widgets y la vista En reposo de Wave. Si una acción llega desde una representación antigua del widget, se rechaza para evitar saltos dobles o entrar en otra carpeta. Al cambiar el servidor en Ajustes, una selección antigua no puede reproducir accidentalmente desde el servidor nuevo.

El catálogo local se puede recorrer sin red después de publicarlo. Las canciones del servidor requieren conexión para reproducirse. Las carpetas del servidor visitadas se conservan en caché: ante un fallo de red pueden seguir mostrándose con un mensaje y un botón de actualización. Los formatos grandes y la vista de Wave muestran varias canciones por página; los pequeños y rectangulares muestran una.

### Validación de esta entrega

Se han ejecutado las comprobaciones del proyecto generado y se han analizado todas las fuentes Swift y las referencias de Xcode. Se incluyen XCTest para jerarquías locales, páginas que cruzan archivos de caché, dos navegadores conectados, botones antiguos, carpetas eliminadas, reducción de listas, rechazo de rutas, subruta HTTPS del servidor, canciones ocultas y caché sin conexión.

**La compilación con el SDK de Apple, los XCTest y las pruebas visuales siguen pendientes de Xcode/iPhone.** Este entorno es Linux. Prueba especialmente:

- Elegir una canción local desde el widget con Wave en segundo plano y comprobar que no abre su interfaz y que se escucha en el reproductor.
- Recorrer Local → carpeta → canción, volver y cambiar a Servidor sin interrumpir la música actual.
- Reproducir una canción del servidor y comprobar la cola de su carpeta, la misma carátula y los controles del otro widget.
- Desconectar la red después de visitar una carpeta remota: comprobar el mensaje, mantener la copia de metadatos y volver a Local.
- Cambiar el servidor, esconder o quitar una canción y confirmar que una selección antigua no reproduce un archivo distinto.
- Probar dos widgets en En reposo de iOS y la vista completa de En reposo de Wave, incluidos Texto grande, modo nocturno y bloqueo/autenticación.

Referencias: [widgets en En reposo](https://developer.apple.com/documentation/widgetkit/adding-standby-and-carplay-support-to-your-widget), [botones interactivos y acciones de audio](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).


## Horizontal, widgets y En reposo · 0.9.0

La app conserva las mismas pestañas al girar el dispositivo. En horizontal, el menú queda a la izquierda: iconos en iPhone y ventanas cortas, iconos con nombres en iPad amplio. Las cabeceras, búsquedas, espacios de listas y mini reproductor se ajustan a la altura disponible. El reproductor ampliado coloca la portada a la izquierda y los controles, onda y cola a la derecha; Descubre usa portada y controles separados. La reproducción continúa al girar y los controles conservan un área táctil de al menos 44 puntos.

Incluye la extensión **WaveWidgets** con dos widgets:

- **Wave · Reproduciendo**: pequeño, mediano y grande; formatos circular, rectangular y línea en pantalla bloqueada. Los formatos con botones permiten reproducir/pausar y cambiar de canción usando `AudioPlaybackIntent` en el proceso de la app. Al tocar el resto se abre el reproductor.
- **Wave · Tu biblioteca**: Me gusta, playlists y archivos del dispositivo; accesos a Playlists y Mi música. Tamaños pequeño/mediano y formatos rectangular/línea en pantalla bloqueada.

Los widgets pequeños admiten **En reposo de iOS (StandBy)**, con fondo removible y representación monocroma del sistema. La actualización visual de widgets la programa iOS: no es una vista de la app que se refresque continuamente. Los controles multimedia nativos de pantalla bloqueada mantienen el progreso y la carátula en directo.

**En reposo dentro de Wave** muestra reloj, fecha, portada y controles de reproducción sobre fondo oscuro cuando el dispositivo está cargando en horizontal y la app está abierta. Se puede cerrar manualmente, abrir desde el menú izquierdo o desactivar en Ajustes. No bloquea el reposo del dispositivo ni reproduce música automáticamente al conectar el cargador. Esta pantalla no sustituye la pantalla En reposo del sistema: al bloquear el iPhone, iOS presenta sus propios widgets y controles.

### Instalar y conectar los widgets

1. Descomprime **Wave-iOS-0.11.0-fuentes-sin-verificar.zip** en una carpeta nueva y abre `Wave.xcodeproj`.
2. Selecciona el mismo **Team** y firma automática en los targets **Wave** y **WaveWidgets**.
3. En Signing & Capabilities → **App Groups**, registra/selecciona **group.app.wave.music** en ambos targets. El proyecto ya contiene los entitlements y embebe `WaveWidgets.appex`. Si ese grupo pertenece a otro Team, usa un identificador de grupo de tu Team y reemplázalo también en `Shared/WaveWidgetState.swift` y ambos entitlements. Para regenerar el proyecto, actualiza igualmente `project.yml` y `scripts/generate-project.py`.
4. Si Xcode informa de que tu Team no admite App Groups, ese Team no puede firmar esta variante con datos compartidos: necesitas un Team que admita esa capacidad. No se oculta el fallo compartiendo datos en un contenedor que los widgets no puedan leer.
5. Ejecuta el scheme **Wave** en el iPhone. No desinstales la versión anterior si quieres conservar tu música.
6. Abre Wave y elige una canción para publicar su estado. La cola se guarda en el contenedor privado de la app; el App Group contiene solo metadatos y miniaturas de portada.
7. Inicio: mantén pulsada la pantalla → añadir widget → **Wave** → elige Reproduciendo o Tu biblioteca.
8. Pantalla bloqueada: mantén pulsada → Personalizar → Pantalla bloqueada → añadir widgets → **Wave**. iOS decide cuándo una interacción requiere desbloquear el dispositivo.
9. En reposo: habilítalo en Ajustes de iOS, conecta el iPhone al cargador, colócalo horizontal y bloquea la pantalla. Mantén pulsado el área de widgets y añade el widget pequeño de Wave. No hay una familia de widgets separada para StandBy.

### Comprobaciones y pruebas en dispositivo

En Linux se comprueban sintaxis Swift, referencias Xcode, App Groups, flags de compilación de los intents, extensión embebida, versiones de los targets y proyecto reproducible. **No se ha ejecutado `xcodebuild` ni XCTest**, ni se ha validado la interfaz visual en un iPhone: esas comprobaciones requieren Xcode y dispositivos Apple.

El proyecto incluye XCTest para orientación de iPhone/iPad, ventanas pequeñas, snapshots compartidos, enlaces de widgets, límites de progreso y rutas de miniaturas. Ejecuta `⌘U` en Xcode. Prueba además:

- Girar en una subcarpeta mientras suena música; comprobar que conserva carpeta, posición de lista, cola y reproducción.
- Abrir el reproductor en horizontal, buscar en la onda, cambiar canción por gesto, cerrar y volver a la biblioteca; repetir con Texto grande y Reducir movimiento.
- Descubre en horizontal: reproducir/pausar, guardar, descartar y Enviar a…; comprobar que la onda no compite con los gestos de portada.
- Añadir cada widget, cambiar canción/Me gusta en Wave y comprobar los controles con app visible, en segundo plano y después de que el sistema termine el proceso. Tras reiniciar el dispositivo puede ser necesario desbloquearlo una vez para acceder a datos protegidos.
- Cargar en horizontal con Wave abierta: cerrar En reposo y comprobar que no vuelve a abrirse hasta cambiar la condición de carga/orientación. Abrir el teclado en vertical mientras carga no debe activar En reposo.
- Bloquear el iPhone cargando en horizontal y comprobar ambos widgets pequeños en StandBy, incluido su modo nocturno y tamaños de texto.

Regenerar el proyecto y paquete completo desde cualquier sistema con Python:

```sh
python3 scripts/test-project.py
python3 scripts/package-release.py
```

Referencias: [widgets interactivos y acciones de audio](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups), [widgets de En reposo](https://developer.apple.com/documentation/widgetkit/adding-standby-and-carplay-support-to-your-widget).


Esta actualización incluye el proyecto `Wave.xcodeproj`, las fuentes y `Info.plist`. Se puede abrir directamente en Xcode: **no hace falta ejecutar XcodeGen**. Se mantiene el identificador `app.wave.music.ios` para actualizar la app instalada sin borrar sus archivos importados.

## Nube y conexión con Mac en 0.8.0

En **Mi iPhone / Mi iPad → Nube · iOS y Mac**, sube las carpetas importadas o descarga/actualiza toda la nube o una carpeta concreta. Guarda primero la dirección de tu servidor Wave en Ajustes. La subida automática al importar una carpeta está pendiente de confirmar el servidor de destino; esta entrega usa botones manuales.

Las carpetas se guardan en el servidor Wave conservando las subcarpetas; son las listas comunes para ambos dispositivos. Las copias locales conservan la identidad de Me gusta del servidor. Los favoritos se actualizan cada 15 segundos mientras la app está abierta y al volver a ella. La migración de favoritos locales se realiza una sola vez al vincular sus archivos a la nube.

**Historial de actualizaciones** permite deshacer cambios del servidor durante 30 minutos, también si los hizo un Mac. **Deshacer descarga** recupera el manifiesto local anterior durante 30 minutos; los archivos anteriores se conservan para recuperación. Si hay cambios posteriores, deshacer se rechaza para protegerlos.

En **Descubre**, **Enviar a…** abre el selector de carpetas. La canción se relocaliza y conserva los favoritos; las copias de otros dispositivos se actualizan al descargar. El aviso dura 15 segundos y tiene cierre manual. Las canciones locales sin vínculo de nube se recolocan dentro de su manifiesto local.

Las listas personales elegidas en iOS y los recursos de Música/Spotify permanecen en su plataforma. Se conserva el reproductor, la navegación y los controles de iOS de 0.7.7. Validación de sintaxis y proyecto en Linux; compilación, XCTest y prueba de interconexión en iPhone/Mac pendientes de Xcode y dispositivos reales.

### Probar la interconexión

1. Instala macOS 1.5.0 y iOS 0.8.0 sin desinstalar la app iOS anterior.
2. Guarda la misma dirección de servidor en Ajustes de ambas apps.
3. En Mac elige una carpeta de prueba y pulsa Subir / actualizar carpeta en la nube.
4. En iOS selecciona esa carpeta en Nube y pulsa Descargar / actualizar. Marca Me gusta; comprueba el corazón en el Mac después de 15 segundos o al volver a la ventana.
5. En Descubre envía una canción a otra carpeta. Actualiza la copia en el otro dispositivo y comprueba su nueva ubicación.
6. Dentro de 30 minutos, usa Historial para deshacer la actualización del servidor o Deshacer descarga para restaurar la copia local.

## Instalar la actualización en el Mac

1. Cierra Xcode por completo con `⌘Q`.
2. Descomprime `Wave-iOS-0.11.0-fuentes-sin-verificar.zip` en una carpeta nueva. No lo mezcles con la copia antigua.
3. Dentro de `Wave-iOS-0.11.0`, abre **Wave.xcodeproj**.
4. En TARGETS → Wave → Signing & Capabilities, activa Automatically manage signing y selecciona tu Team.
5. Arriba, selecciona el scheme **Wave** y tu iPhone o iPad conectado.
6. Pulsa Ejecutar (`⌘R`).

La app nueva muestra **WAVE 0.11.0** arriba y cinco secciones: **Servidor**, **Mi iPhone/Mi iPad**, **Playlists**, **Spotify** y **Ajustes**. Ajustes muestra la versión del bundle `0.11.0`, build `26`. Si solo ves la lista antigua de carpetas sin estas secciones, esa ejecución sigue usando la versión anterior. Rebuild y Relaunch recompilan/reabren el proyecto seleccionado; no copian las fuentes del servidor al Mac. Verifica la carpeta del proyecto con Show in Finder sobre el proyecto en Xcode.

No desinstales la app para actualizarla si quieres conservar tus archivos importados. La app instalada puede abrirse sin el cable de Xcode; el servidor y los contenidos en la nube necesitan conexión de red.

## Volver desde el reproductor grande (0.8.0)

Desliza hacia la derecha desde el borde izquierdo (24 puntos) para cerrar el reproductor y regresar a la biblioteca. También puedes arrastrar hacia abajo la cabecera Reproduciendo, además de la portada. Los gestos siguen el dedo y vuelven a su posición si no superan el umbral o se cancelan; respetan Reducir movimiento.

Tocar cualquier icono de navegación cierra el reproductor grande y muestra esa sección, también al tocar la pestaña que ya estaba seleccionada. La biblioteca conserva su posición. La selección nativa de pestañas y su delegado se mantienen.

Se conservan los cambios de canción al deslizar la portada, la onda, los controles de iOS y la navegación de 0.5. Los gestos nuevos no se aplican al área de la onda ni a toda la lista de la cola. Sintaxis y paquete comprobados en Linux; compilación y prueba de gestos requieren Xcode/iPhone.

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
