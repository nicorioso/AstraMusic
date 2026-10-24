# AstraMusic

AstraMusic es un reproductor de música local, gratuito y multiplataforma para Android, Linux y Windows. Usa un único código base Flutter y reproduce archivos que ya existen en el dispositivo; no incluye servidor ni streaming.

## Estado actual

- Fase 3B-2a completada: etiquetas de escritorio, reescaneo incremental, búsqueda normalizada y control seguro de cancelación.
- Fase 4A.1 completada: cola en memoria con aleatorio manual uniforme, errores auxiliares no fatales y auditoría de estabilidad.
- No hay persistencia de la cola, reanudación tras cerrar la app, carátulas ni lógica de playlists.

## Versiones fijadas

- Flutter 3.47.x.
- Dart 3.13.x.
- No actualizar Flutter, Dart ni cambiar el canal del SDK.

## Reglas de trabajo

- Añadir dependencias exclusivamente con `flutter pub add <paquete>` y usar `--dev` cuando corresponda.
- Consultar la documentación y el README local del paquete antes de configurar APIs o integración nativa; no inventar APIs.
- No modificar `android/`, `linux/` ni `windows/` salvo que una tarea lo solicite explícitamente.
- Mantener los cambios pequeños y hacer un commit por tarea.
- Nunca versionar keystores, `key.properties`, credenciales ni secretos.
- No implementar reproducción, biblioteca, playlists o persistencia fuera del alcance explícito de una tarea.
- Si cambian las tablas de drift, ejecutar `dart run build_runner build --delete-conflicting-outputs` y commitear los archivos `.g.dart` generados.
- Todo cambio de esquema requiere incrementar `schemaVersion` y escribir una migración que conserve los datos existentes.
- Toda migración que añada columnas derivadas requiere backfill y un test desde el esquema anterior.
- La UI y el reproductor trabajan únicamente con modelos de dominio; los tipos generados por drift no deben salir de la capa de datos.
- Toda consulta de biblioteca usa `search_text`, normalizado con la misma función que se usa al insertar o actualizar canciones.
- Nunca usar `AudioPlayer.shuffle()` ni `setShuffleModeEnabled()`: el aleatorio es una permutación manual de la cola porque `just_audio_media_kit` ignora `shuffleOrder` y no implementa `setShuffleOrder`.
- Un error fatal impide reproducir la canción, la marca como no disponible y avanza sin crear bucles; un error no fatal de una operación auxiliar solo informa al usuario y no deshabilita controles.
- Con aleatorio activo, añadir agrega al final de ambos órdenes, “reproducir a continuación” inserta después de la actual en ambos, quitar elimina de ambos y mover cambia únicamente el orden de reproducción. Al desactivar se restaura el orden original restante.
- Mantener activos los lints adicionales de `analysis_options.yaml`: tipos estrictos, `avoid_print`, `cancel_subscriptions`, `close_sinks`, `prefer_const_constructors`, `unawaited_futures` y `use_build_context_synchronously`.
- El slider de posición nunca llama a `seek` desde `onChanged`: actualiza solo su estado local y confirma un único seek en `onChangeEnd`. Los seeks pendientes se coalescen y gana siempre el último.

## Arquitectura

- `lib/core/`: infraestructura compartida, plataforma, base de datos y utilidades.
- `lib/features/`: módulos de biblioteca, reproductor, playlists y ajustes.
- Riverpod para gestión de estado.
- Drift para persistencia SQLite.
- `just_audio` para reproducción y `audio_service` para segundo plano y controles del sistema.
- `just_audio_media_kit` como implementación de audio para Linux y Windows.
- `AudioPlayerService` desacopla la UI y Riverpod del motor de audio.
- `AstraAudioHandler` contiene el `AudioPlayer` y es la única fuente del estado de reproducción. El reproductor vive en el handler para que los controles de la UI, Android y MPRIS operen sobre la misma instancia incluso en segundo plano.
- La cola vive en el reproductor y se refleja en `queue`, `mediaItem` y `PlaybackState` de `audio_service`; no se persiste todavía.
- Las listas usan las APIs actuales de `just_audio`; no usar `ConcatenatingAudioSource`, que está deprecado. El aleatorio reordena la lista en Dart y recarga conservando canción, posición y estado play/pausa.
- `QueueLoadStrategy` aísla la carga completa mediante `setAudioSources` y mide su duración en debug para poder cambiar la estrategia si las bibliotecas grandes lo requieren.
- `LibraryScanner` abstrae el escaneo cancelable: `DesktopLibraryScanner` recorre carpetas en un isolate y `AndroidMediaStoreLibraryScanner` usa un MethodChannel hacia MediaStore.
- `TagReader` abstrae etiquetas; en archivos nuevos o cambiados, escritorio extrae la carátula original con `audio_metadata_reader` y la deduplica en caché.
- `ArtworkProvider` y `TrackArtwork` resuelven carátulas sin bloquear la UI; `MediaItem.artUri` reutiliza el archivo local para notificación y MPRIS.
- `LibrarySyncService` sincroniza los resultados por lotes y actualiza la disponibilidad sin exponer tipos drift.

## Esquema de base de datos

- `tracks`: ubicación opaca única, datos básicos, disponibilidad y favorito; `date_modified` permite detectar cambios y `search_text`/`sort_title` soportan búsqueda y orden normalizados.
- `playlists`: nombre y fechas de creación y actualización.
- `playlist_tracks`: relación ordenada entre playlists y canciones, con borrado en cascada.
- `library_folders`: carpetas de escritorio únicas, fecha de adición y último escaneo.
- Versión actual del esquema: 3.

## Comandos habituales

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```
