# Plan de Rediseño y Nuevas Funcionalidades para Wave

## Objective
Rediseñar la interfaz de la aplicación de música "Wave" para optimizarla en dispositivos móviles y tablets. Además, se busca eliminar el color naranja por defecto, introduciendo temas personalizables (paletas de colores predefinidas) y un sistema de perfiles locales ("A" y "M") con bibliotecas de música independientes.

## Background & Motivation
Actualmente, Wave tiene una interfaz monolítica en `index.html` con un tema oscuro donde predomina el color naranja y carga todas las pistas del servidor por defecto. El usuario busca una experiencia más personalizada y responsiva, permitiendo que múltiples usuarios en el mismo dispositivo tengan sus propias bibliotecas vacías desde el inicio, y puedan explorar el catálogo del servidor para armar sus propias listas.

## Proposed Solution
1. **Rediseño Móvil/Tablet**:
   - Ajustar las *Media Queries* en el CSS dentro de `index.html` para asegurar que las barras de navegación, botones de reproducción y listas de canciones sean amigables con toques táctiles (*touch-friendly*).
   - Ocultar barras laterales en móvil y potenciar la barra de navegación inferior (Bottom Nav).

2. **Temas Personalizables**:
   - Reemplazar las variables CSS estáticas (ej. `--accent: #ff6b35`) por clases o atributos en la etiqueta `<html>` (ej. `data-theme="blue"`).
   - Añadir una sección de "Ajustes/Temas" donde el usuario pueda seleccionar botones de colores predefinidos (Azul, Verde, Morado, etc.) que actualizarán la variable `--accent` y se guardarán en `localStorage`.

3. **Sistema de Perfiles (A y M)**:
   - Al cargar la página por primera vez (si no hay perfil guardado), mostrar una pantalla inicial para elegir entre "Perfil A" o "Perfil M".
   - Guardar el perfil seleccionado en `localStorage` (como `_plUser = 'A'` o `'M'`).
   - Esta pantalla ocultará el reproductor hasta que se seleccione un perfil. Un botón de "Cambiar Perfil" estará en los ajustes.

4. **Biblioteca y Catálogo Unificados**:
   - En la vista principal, incluir un interruptor (Toggle: "Mi Biblioteca" / "Catálogo").
   - **Catálogo**: Mostrará todas las canciones/playlists disponibles en el servidor (el array `S.tracks` completo).
   - **Mi Biblioteca**: Mostrará solo los elementos que el perfil seleccionado ha agregado previamente (cargados desde un backend o guardados en una playlist especial asociada al usuario). Tendrá un estado "Vacío" por defecto.
   - Botón `+` en el "Catálogo" para añadir pistas a "Mi Biblioteca".

## Implementation Steps
1. **Actualizar CSS en `index.html`**:
   - Refactorizar las reglas responsivas.
   - Definir variables de colores dinámicos.
2. **Crear la Pantalla de Selección de Perfil**:
   - HTML para el modal/pantalla completa con los botones "A" y "M".
   - JS para interceptar el flujo de inicio y forzar la selección.
3. **Selector de Temas**:
   - HTML en ajustes para paletas.
   - JS para aplicar la paleta seleccionada y guardar en LocalStorage.
4. **Vista de Biblioteca con Toggle**:
   - Modificar la función de renderizado de la lista de canciones en JS.
   - Implementar la lógica del interruptor que filtra `S.tracks` entre "Catálogo completo" y "Tracks del Perfil".
   - Añadir lógica para que el botón "Añadir a mi biblioteca" guarde la referencia en el backend (usando la API de playlists actual) para el perfil A o M.

## Verification & Testing
- Abrir la interfaz en vista móvil (Chrome DevTools) y verificar el diseño.
- Seleccionar un color de tema y verificar que se guarda tras recargar la página.
- Seleccionar "Perfil A", ver que la biblioteca está vacía, agregar una canción del catálogo y verificar que aparece en la biblioteca.
- Cambiar a "Perfil M" y verificar que su biblioteca sea independiente (vacía).
- Reiniciar servidor y asegurar que el progreso de cada perfil se mantiene.