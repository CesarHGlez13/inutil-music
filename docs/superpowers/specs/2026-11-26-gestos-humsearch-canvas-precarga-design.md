# Especificación de Diseño: Gestos, Búsqueda por Tarareo, Canvas Cinemático y Precarga Instantánea

**Fecha:** 2026-11-26  
**Proyecto:** Inutix Music (`inutil_music`)  
**Autor:** Antigravity & Cesar

---

## 1. Intención y Justificación

Inutix Music ha alcanzado independencia de infraestructura (backend propio, autenticación directa y distribución OTA probada). Sin embargo, la experiencia de reproducción y descubrimiento en el día a día presenta tres fricciones críticas:
1. **Control de reproducción rígido:** El reproductor a pantalla completa depende exclusivamente de botones pequeños; no ofrece gestos naturales para cambiar de pista, retroceder/adelantar o minimizar con una mano.
2. **Descubrimiento musical limitado:** Cuando el usuario recuerda el ritmo o la melodía de una canción pero no el título ni la letra, no existe forma de buscarla tarareando directamente en la app.
3. **Canvas obsoleto y con fallas:** El motor actual dependía del dominio externo `spotycovs.lol`, el cual quedó fuera de servicio. Esto produce pantallas negras o la reproducción de vídeos de canciones equivocadas por colisión de títulos.
4. **Latencia al reproducir (1.5 - 3 s de espera):** Cada vez que se pulsa una canción o avanza la cola, el reproductor debe resolver la URL y llenar el búfer desde cero.

Este diseño unifica las 4 soluciones bajo la identidad visual oscura y neón de Inutix Music, con costo $0 en servicios externos y rendimiento optimizado para procesadores móviles como el MediaTek Helio G81 del Moto g05.

---

## 2. Objetivos, No-Objetivos y Anti-Objetivos

### Objetivos (Goals)
* **Gestos táctiles completos:**
  * Swipe horizontal sobre la carátula/lienzo para pista siguiente (izquierda) o anterior (derecha) con inercia física y carrusel continuo.
  * Swipe vertical hacia abajo para minimizar suavemente al mini-reproductor.
  * Swipe vertical hacia arriba sobre la carátula o área de reproducción para abrir inmediatamente la letra sincronizada en tiempo real (`onOpenLyrics`).
  * Doble toque lateral tipo YouTube (derecha: +10 s; izquierda: -10 s) con retroalimentación háptica y ondas neón.
  * Deslizamiento vertical en bordes para volumen (derecho) y atenuador de pantalla (izquierdo).
* **Búsqueda por tarareo/canto/voz integrada y gratuita:**
  * Botón en barra de búsqueda que despliega modal con espectrograma de ondas neón vivas (`#00E5FF` y `#7C4DFF` sobre fondo `#0A0B10`).
  * Indicador de acción claro para el usuario: **«Di, canta o tararea un fragmento de la canción»**.
  * Grabación y resolución melódica en 5 a 8 segundos vía InnerTube Sound Search.
  * Resultados en tarjetas de canción con reproducción inmediata a un toque.
* **Canvas Cinemático 100 % autónomo (Eliminación de `spotycovs.lol`):**
  * Desconexión total del scraper obsoleto de Spotify.
  * *Capa 1 (Universal):* Canvas Generativo Líquido en GPU (malla de gradientes fluidos y partículas sutiles basadas en la paleta de la carátula) que garantiza que el 100 % de las canciones tengan fondo dinámico.
  * *Capa 2 (Vídeo oficial):* Extracción de loop silenciado desde el vídeo oficial de YouTube cuando esté disponible (cero riesgo de mezclar canciones distintas).
* **Precarga instantánea de Audio y Canvas (*Zero-Latency*):**
  * Precarga en segundo plano de los primeros 512 KB a 1 MB de la pista `N+1` en la cola.
  * Reproducción instantánea (0 ms perceptibles) al pulsar «Siguiente» o al terminar la pista.
  * Precalentamiento del Canvas de la siguiente pista para transición sin parpadeo.

### No-Objetivos (Non-Goals)
* No se reemplaza el mini-reproductor existente ni su lógica de reanudación exacta.
* No se crearán cuentas de Spotify ni suscripciones a servicios comerciales de reconocimiento como ACRCloud o Shazam API.
* No se obligará al usuario a mantener activado el Canvas si prefiere ver únicamente la carátula fija (el selector de modo seguirá disponible en Ajustes).

### Anti-Objetivos (Anti-Goals)
* **No usar colores fuera de la paleta de la app:** Prohibido usar estilos blancos lechosos o *liquid glass* descontextualizados (como ocurrió en el tutorial interactivo). Todo componente debe respetar la paleta oscura: fondo `#0A0B10`, acentos `#00E5FF` y `#7C4DFF`.
* **No bloquear el hilo principal de Flutter:** La precarga de audio y la grabación del micrófono deben correr en segundo plano sin producir tirones (framerate de 60/120 fps constante en el scroll).

---

## 3. Restricciones Técnicas

* **Plataforma objetivo:** Android 7 a 15 (mínimo SDK 24, target SDK 35), Linux y soporte de escritorio.
* **Consumo de recursos:** Optimizado para dispositivos de gama de entrada (4 GB RAM, CPUs octa-core A75/A55) sin sobrecalentamiento.
* **Cero dependencias caídas:** Se erradica cualquier referencia a `spotycovs.lol`.

---

## 4. Enfoques Considerados y Selección

### Enfoque A: APIs comerciales (ACRCloud + Spotify Scrapers de pago)
* *Pros:* Rápido de conectar.
* *Contras:* Costo mensual recurrente en dólares, límites estrictos de cuota gratuita y riesgo de corte de servicio en cualquier momento.
* *Descartado.*

### Enfoque B: Reconocimiento acústico InnerTube + Canvas Generativo Nativo + Precarga Búfer Local (Seleccionado)
* *Pros:* 100 % gratis, cobertura del 100 % de canciones con Canvas dinámico, precisión máxima en tarareo, y control total del código en Flutter.
* *Contras:* Requiere implementación cuidadosa del búfer de audio en `just_audio` y del pintor de gradientes en GPU.
* *Seleccionado por unanimidad.*

---

## 5. Arquitectura de Implementación Detallada

### 5.1. Búsqueda por Tarareo (`HumToSearchSheet`)
1. **Entrada:** Icono de onda sonora en el campo de búsqueda (`search_page.dart`).
2. **UI:** `HumToSearchSheet` con micro-animación pulsante, espectrograma reactivo al micrófono (usando `record` o `audio_streamer`) y estados: `Escuchando...`, `Analizando melodía...`, `Canciones encontradas`.
3. **Resolución:** Llamada a `InnertubeSearchService.searchByAudio(bytes)` empaquetado en formato ligero y parseo de resultados a objetos `Song`.

### 5.2. Gestos del Reproductor (`PlayerGesturesWrapper`)
1. **Detector de gestos:** Envoltorio `GestureDetector` sobre la región de arte/canvas en `player_panel.dart` y `spotify_fullscreen_canvas_player.dart`.
2. **Física horizontal:** `HorizontalDragUpdate` con traslación `Transform.translate` y amortiguación elástica; al superar el 25 % del ancho o 800 px/s de velocidad, salta a la pista anterior o siguiente.
3. **Física vertical:** Deslizamiento hacia abajo superior a 120 px dispara `Navigator.maybePop(context)` o colapsa el modal.
4. **Doble tap:** Detector de posición `TapDownDetails`:
   * Si `x < width * 0.35`: retrocede 10 s y muestra animación `DoubleTapRipple(isForward: false)`.
   * Si `x > width * 0.65`: adelanta 10 s y muestra `DoubleTapRipple(isForward: true)`.
5. **Control de volumen y brillo:** Deslizamiento vertical en los márgenes laterales externos (±5 % del ancho de la pantalla) con indicador flotante vertical translúcido.

### 5.3. Nuevo Motor Canvas Cinemático (`CinematicCanvasEngine`)
1. **Limpieza:** Eliminar `SpotifyCanvasResolver` obsoleto (`spotycovs.lol`).
2. **Canvas Generativo Líquido:**
   * Widget `GenerativeMeshCanvas`: genera una paleta de 3 a 4 colores complementarios a partir de la carátula con `ColorScheme.fromImageProvider`.
   * Pinta un gradiente radial multidireccional con ruido armónico suave (`CustomPainter` con `Shader` optimizado) y animación de bucle infinito a 60 fps que consume menos de 2 % de CPU.
3. **Soporte de Video Loops:** Si la canción cuenta con videoclip oficial identificado por su `videoId`, se reproduce en bucle en el motor nativo silenciado.

### 5.4. Motor de Precarga Instantánea (`PlaybackPreloadCoordinator`)
1. **Escucha de cola:** Cuando el reproductor alcanza el estado de reproducción (`playing == true`), lee la pista `N+1` de la cola de reproducción activa.
2. **Pre-buffering de Audio:**
   * Llama a `getStreamUrl(trackNext)` de antemano.
   * Inicializa un búfer previo de 512 KB a 1 MB con `just_audio` o descarga en caché HTTP temporal.
   * Al recibir la orden de cambio de canción, sustituye la fuente por el búfer ya caliente: arranque inmediato en 0 ms.
3. **Pre-buffering de Canvas:**
   * Precarga la paleta cromática o el stream de video de la pista `N+1`.

---

## 6. Verificación y Criterios de Aceptación
1. **Consistencia de Color:** La hoja de búsqueda por tarareo coincide exactamente con los tonos de `AppColors` de Inutix Music.
2. **Latencia de gestos:** Transiciones de pista fluidas a 60 fps sin tirones visuales.
3. **Precisión de tarareo:** Reconocimiento exitoso de melodías populares tarareadas o silbadas de 5 segundos.
4. **Cero pantallas negras en Canvas:** Cada canción sin excepción muestra su fondo cinemático líquido en movimiento.
5. **Tiempo al primer audio:** El cambio de pista en cola ocurre en < 150 ms frente a los 2000 ms actuales.
