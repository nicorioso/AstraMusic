# AstraMusic
Reproductor de música LOCAL, gratuito. Android, Linux, Windows. Flutter 3.47.x / Dart 3.13.x (no actualizar SDK).
Detalle histórico por fase: docs/historial-agents.md (leer solo si es necesario).

## Respuesta
- Español. Informe final ≤10 líneas: qué cambió, resultado de analyze/test, dudas. No pegues diffs ni logs.

## Ahorro de tokens
- No leas *.g.dart, build/, .dart_tool/, pubspec.lock ni docs/ salvo que la tarea lo exija.
- Busca con rg y lee solo los archivos necesarios. No audites todo lib/.
- Salida silenciosa: `flutter analyze --no-pub`, `flutter test --reporter failures-only`, y `| tail -n 30` en comandos largos.
- Por tarea ejecuta SOLO analyze y test. Builds (linux/apk) solo si la tarea lo pide.

## Reglas
- el arranque nunca depende de archivos del usuario; restauraciones y verificaciones corren tras el primer frame y con try/catch.
- diálogos y paneles: contenido acotado y contexts capturados antes de await; todo flujo de UI tiene test por su camino real, no solo con fakes.
- Sin sudo. No ejecutes la app. No compiles Windows.
- Dependencias solo con `flutter pub add`; no inventes APIs: lee el paquete en ~/.pub-cache. permission_handler fijado en 12.0.3.
- Un commit pequeño por tarea; nunca commitear secretos.
- Si algo falla, repórtalo; no lo sustituyas en silencio. Cada bug corregido lleva un test.

## Arquitectura
lib/core (platform, db, utils) y lib/features (library, player, playlists, settings). Riverpod 3.x, drift, just_audio + audio_service.
- Playlists usa modelos/repositorios de dominio; la UI nunca recibe filas de drift.
- La navegación admite destinos de playlist y conserva una pila simple en escritorio.
- pantallas secundarias en móvil viven dentro del shell (pila del provider); solo el reproductor completo es ruta aparte.
- UI no usa tipos de drift. Lo específico de plataforma va detrás de interfaces en core/platform.
- El tema Gargantua vive en `core/theme`; usa `AstraColors` y no colores fijos en widgets.
- Los fondos decorativos van en Stack, nunca envolviendo el contenido con altura fija.
- La raíz responsive usa `DesktopShell` y `MobileShell` con navegación Riverpod.
- Breakpoint único: escritorio desde 840 dp; móvil por debajo de 840 dp.
- La rejilla de Inicio muestra hasta 8 playlists: recientes primero; si faltan,
  favoritos y luego las más nuevas por creación, sin duplicados.
- El color dinámico se cachea por carátula, se oscurece y solo se usa con contraste ≥ 4,5; en otro caso conserva Gargantua.
- Toda animación de UI respeta `MediaQuery.disableAnimations` y evita reconstrucciones por ticks fuera del widget de progreso.
- Cambio de esquema: migración con backfill + test + build_runner + commitear lo generado.

## Audio (no romper)
- Aleatorio = permutación manual de la cola; NUNCA setShuffleModeEnabled/shuffle() (media_kit lo ignora). No ConcatenatingAudioSource.
- Slider: seek SOLO en onChangeEnd; seeks pendientes se coalescen (gana el último).
- Errores: fatales (canción actual) saltan a la siguiente; no fatales muestran mensaje y NO deshabilitan controles.
- Búsqueda: usar search_text y normalizeForSearch; orden por sort_title.
- Borrar es solo de la app; excluded_uris evita que los escaneos revivan canciones.
- Favoritos: `is_favorite` es verdadero si y solo si `favorited_at` no es nulo.
- Playlists: `markPlayed` registra el inicio desde una playlist y `watchRecent` excluye las nunca reproducidas.

Diseño: docs/diseno-ui.md (leer solo en tareas de UI)
