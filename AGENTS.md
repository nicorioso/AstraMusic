# AstraMusic

AstraMusic es un reproductor de música local, gratuito y multiplataforma para Android, Linux y Windows. Usa un único código base Flutter y reproduce archivos que ya existen en el dispositivo; no incluye servidor ni streaming.

## Estado actual

- Fase 3A completada: biblioteca persistente con drift, búsqueda, selección manual de varios archivos y reproducción desde la lista.
- No hay escaneo automático, lectura de metadatos, carátulas, lógica de playlists, cola, aleatorio ni repetición.

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
- La UI y el reproductor trabajan únicamente con modelos de dominio; los tipos generados por drift no deben salir de la capa de datos.

## Arquitectura

- `lib/core/`: infraestructura compartida, plataforma, base de datos y utilidades.
- `lib/features/`: módulos de biblioteca, reproductor, playlists y ajustes.
- Riverpod para gestión de estado.
- Drift para persistencia SQLite.
- `just_audio` para reproducción y `audio_service` para segundo plano y controles del sistema.
- `just_audio_media_kit` como implementación de audio para Linux y Windows.
- `AudioPlayerService` desacopla la UI y Riverpod del motor de audio.
- `AstraAudioHandler` contiene el `AudioPlayer` y es la única fuente del estado de reproducción. El reproductor vive en el handler para que los controles de la UI, Android y MPRIS operen sobre la misma instancia incluso en segundo plano.

## Esquema de base de datos

- `tracks`: ubicación opaca única, datos básicos de la canción, disponibilidad, favorito y fecha de adición.
- `playlists`: nombre y fechas de creación y actualización.
- `playlist_tracks`: relación ordenada entre playlists y canciones, con borrado en cascada.

## Comandos habituales

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```
