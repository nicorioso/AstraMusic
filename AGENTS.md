# AstraMusic

AstraMusic es un reproductor de música local, gratuito y multiplataforma para Android, Linux y Windows. Usa un único código base Flutter y reproduce archivos que ya existen en el dispositivo; no incluye servidor ni streaming.

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

## Arquitectura

- `lib/core/`: infraestructura compartida, plataforma, base de datos y utilidades.
- `lib/features/`: módulos de biblioteca, reproductor, playlists y ajustes.
- Riverpod para gestión de estado.
- Drift para persistencia SQLite.
- `just_audio` para reproducción y `audio_service` para segundo plano y controles del sistema.
- `just_audio_media_kit` como implementación de audio para Linux y Windows.

## Comandos habituales

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```
