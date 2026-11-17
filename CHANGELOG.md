# Historial de cambios

## [1.2.0] - 2026-11-17

### Added

- Subsistema de descargas de YouTube para Android, Linux y Windows:
  `AudioDownloadBackend`, `DesktopYtDlpBackend`, `AndroidYtDlpBackend`,
  `AudioDownloadService` y `AudioDownloadScreen`.
- Importación de pistas individuales y playlists completas con creación
  automática de una playlist local en Drift; vista previa de metadatos y
  carátulas, progreso, cancelación y errores por pista.
- Botón **Actualizar motor** en Android: intenta el canal nightly y, si falla,
  el estable.

### Changed / Performance

- Se prioriza el audio nativo (`.m4a`, `.mp3` y otros formatos admitidos como
  `.opus`) para evitar transcodificaciones innecesarias.
- `--concurrent-fragments 4` y búfer de 16K; hasta dos descargas simultáneas
  por playlist en escritorio y una en Android.
- Inicialización única de YoutubeDL y FFmpeg por sesión en Android y precarga
  paralela de miniaturas confiables. Logcat registra tiempos de inicialización,
  extracción, transferencia y posprocesamiento para diagnóstico local.

### Fixed

- Incrustación de carátulas cuando el motor lo permite y respaldo JPEG
  persistente en `downloaded_artwork/`, independiente de archivos temporales.
- Diagnósticos que priorizan errores `ERROR:` y filtran advertencias `WARNING:`.
- Localización del audio final por inspección del directorio temporal en Android
  y validación de ruta, extensión y contenido antes de registrarlo.
- Rollback de audio y carátula recién movidos si falla o se cancela el registro;
  los éxitos anteriores del lote permanecen en la biblioteca.
- Reglas R8/ProGuard referenciadas por el tipo `release` y
  `jniLibs.useLegacyPackaging` para empaquetar bibliotecas nativas de Android.

Nota: la implementación de v1.2.0 no incluye el argumento `--force-ipv4` y el
tipo `release` no activa explícitamente la minificación.
