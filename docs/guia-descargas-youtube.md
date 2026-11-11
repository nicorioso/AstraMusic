# Guía propuesta: importar audio descargado de YouTube

Estado: análisis y diseño; no hay implementación. Revisado el 11 de noviembre de 2026 contra AstraMusic 1.1.0 y el árbol local de `DVideos` (que tenía cambios sin confirmar en `app/downloader.py`). La evaluación no incluye una descarga real ni una prueba en Android o Windows.

## Decisión técnica

La integración es viable, pero conviene **reutilizar el comportamiento y los contratos de DVideos**, no copiar su interfaz ni llamar directamente su módulo Python desde Flutter. Para Linux y Windows, la primera implementación puede usar un adaptador que ejecute `yt-dlp` como proceso local y observe su salida. Android requiere otro adaptador y una prueba de concepto independiente: el proyecto actual no trae Python, `yt-dlp`, FFmpeg ni un motor JavaScript empaquetados para el APK. Mantener el contrato Dart común permite cambiar el motor sin tocar la biblioteca ni las pantallas.

La primera entrega debería descargar **solo audio**, un video por URL, en un formato que AstraMusic ya admita. Luego agregar playlists de YouTube y finalmente Android. Convertir todo a MP3 reproduce el comportamiento de DVideos, pero exige FFmpeg, más tiempo, espacio temporal y una posible pérdida de calidad. La alternativa de conservar el audio original necesita probar contenedor y códec reales con `just_audio` en cada plataforma. No asumir que cualquier salida de `bestaudio` es reproducible.

## Lo que ya existe

| Proyecto | Pieza | Uso posible |
| --- | --- | --- |
| DVideos | `app/downloader.py`: `analyze_video`, `analyze_playlist`, `download_video`, `download_playlist` | Referencia para extracción de metadatos, selección de audio, progreso, cancelación y resultados parciales. |
| DVideos | `app/utils.py`: `valid_youtube_url`, `is_playlist_url`, `safe_error_message` | Portar la validación de URL y la clasificación de errores a Dart; no reutilizar `open_folder`. |
| DVideos | `app/ui.py` | Referencia de estados y mensajes. Es CustomTkinter con hilos y cola, así que no se puede incrustar en Flutter. |
| AstraMusic | `lib/features/library/presentation/library_controller.dart` | La ruta `addFiles` / `_importPickedFiles` lee etiquetas y registra pistas locales. Extraer su parte común para que la descarga también la use. |
| AstraMusic | `lib/features/library/domain/track_repository.dart` y `lib/features/library/domain/track.dart` | Persistir la pista; la identidad actual de la tabla es `uri`, no ID de YouTube. |
| AstraMusic | `lib/features/playlists/domain/playlist_repository.dart` | Crear playlist y añadir IDs de pistas, sin exponer filas Drift a la UI. |
| AstraMusic | `lib/features/settings/portable_library_tools.dart` y `lib/features/playlists/application/smart_package_service.dart` | Ejemplo de archivos propios en `getApplicationSupportDirectory()` y de rollback al registrar audio. No reutilizar el formato `.amplaylist` como formato de descarga. |
| AstraMusic | `lib/core/platform/tag_reader.dart`, `lib/core/platform/track_availability.dart` | Etiquetas y verificación de existencia de rutas locales. |

Los escaneos actuales no resuelven la incorporación: escritorio escanea carpetas elegidas y Android consulta MediaStore. Un archivo descargado en el directorio privado de la app se debe **registrar de forma explícita** en `TrackRepository`; esperar un escaneo lo dejaría fuera de la biblioteca. `lib/core/db/library_backup_service.dart` respalda tablas, no los bytes de audio, de modo que restaurar el respaldo en otro dispositivo puede dejar pistas no disponibles. La exportación `.amplaylist` sí puede servir para trasladar una playlist terminada.

## Limitaciones concretas de DVideos que hay que corregir

1. El destino usa `%(title)s.%(ext)s` y `overwrites: True`: títulos repetidos pueden reemplazar música previa. Usar un nombre estable que incluya ID de YouTube y no sobrescribir el destino final sin decisión explícita.
2. Tras el posprocesamiento, se deduce la ruta cambiando la extensión a `.mp3`; se debe verificar que el archivo final exista, sea audio válido y tenga tamaño mayor que cero antes de registrarlo.
3. La cancelación borra algunos nombres observados por los hooks, pero puede dejar archivos intermedios del posprocesador. Trabajar por descarga en una carpeta temporal propia y eliminarla completa al cancelar o fallar.
4. `analyze_playlist` usa extracción plana y `ignoreerrors: True`; las entradas pueden venir incompletas. Validar cada URL/ID al descargar y reportar fallos por elemento.
5. Las pruebas de DVideos son principalmente scripts manuales; no hay pruebas automáticas del flujo completo de descarga y rollback. Tomar la lógica como referencia, no como componente ya verificado.
6. `requirements.txt` declara `yt-dlp>=2024.10.22`, sin límite superior: el comportamiento puede cambiar entre instalaciones. Fijar y verificar versiones compatibles para el adaptador que se distribuya.

## Diseño propuesto

### Contrato común

Crear un puerto en `lib/core/platform` (por ejemplo `audio_download_backend.dart`) con operaciones para verificar disponibilidad del motor, analizar URL, descargar audio y cancelar. Los tipos de dominio deben incluir:

- `SourcePreview`: ID de origen, título, autor/canal, duración opcional, portada opcional y tipo `video`/`playlist`.
- `DownloadRequest`: URL validada, formato elegido, carpeta temporal y opción de playlist.
- `DownloadEvent`: estado (`analizando`, `descargando`, `procesando`, `registrando`, `terminado`, `fallido`, `cancelado`), bytes recibidos y totales opcionales, índice de pista y error legible.
- `DownloadedAudio`: ID de origen, ruta temporal **comprobada**, título y metadatos opcionales.
- `DownloadBatchResult`: éxitos, errores por elemento y cancelación, sin ocultar canciones ya completadas.

En `lib/features/library/application`, crear un servicio que coordine `backend → archivo temporal → validación → carpeta definitiva → lectura de etiquetas → TrackRepository → PlaylistRepository`. Mantener el progreso en un provider Riverpod separado de `LibraryController`: `actionsDisabled` representa escaneo/importación y no debería congelar toda la biblioteca durante una descarga larga. La UI solo observa el estado; no ejecuta procesos ni escribe en Drift.

### Identidad, ubicación y consistencia

Guardar audios terminados en una subcarpeta de `getApplicationSupportDirectory()`, por ejemplo `downloaded_audio/`, separada de `imported_audio/`. Usar un directorio temporal por trabajo y un nombre seguro con ID de origen; no confiar en el título como ruta. Evitar colisiones entre dos descargas simultáneas del mismo ID y definir si una segunda descarga se omite, reemplaza o crea otra versión. Recomendación inicial: una sola descarga activa y omitir duplicados ya registrados tras comprobar el archivo.

Registrar la pista con URI local consistente (preferiblemente `file://`, como `SmartPackageService`), `dateAdded`, tamaño, duración y carátula. Leer etiquetas con el servicio existente y usar los datos de YouTube solo como respaldo si faltan. Antes de llamar `upsertAll`, consultar por URI para no borrar favoritos u otros metadatos del usuario: el `upsert` por `uri` reemplaza columnas. Para playlist, recuperar los IDs registrados y pasar solo esos IDs a `addTracks`. Si falla el registro de una pista nueva, eliminar su archivo definitivo; si una playlist falla a mitad, conservar las pistas completas y presentar claramente el resultado parcial o aplicar rollback según una regla elegida antes de implementar.

El borrado actual de la biblioteca quita la referencia, no necesariamente el archivo. Definir una acción específica para «eliminar descarga del dispositivo» y mantener la acción normal de «quitar de la biblioteca». No eliminar archivos externos ni borrar una pista compartida por otras playlists. La restauración de respaldo debe tratar las rutas de descargas como rutas locales que pueden faltar.

### Motores por plataforma

**Linux y Windows.** Preferir un proceso hijo `yt-dlp` con argumentos separados, sin shell, y una salida de progreso y resultado final que se pueda analizar de forma estable. Resolver el ejecutable desde una ruta configurada o empaquetada; verificar su versión y la presencia de FFmpeg antes de iniciar. Si se busca compatibilidad amplia con YouTube, revisar también `yt-dlp-ejs` y un motor JavaScript, según la documentación actual de yt-dlp. Capturar `stdout` y `stderr` sin bloquear, limitar el tamaño del log mostrado y cerrar el proceso al cancelar. La distribución en Windows debe verificarse en Windows; no asumir que el binario Linux sirve allí. Una vía alternativa es ejecutar el código Python existente como proceso auxiliar, pero eso obligaría a distribuir y mantener Python y sus dependencias en cada escritorio, por lo que ofrece menos ventajas para esta app.

**Android.** No usar `Process.start` esperando que haya `yt-dlp`, Python o FFmpeg en el teléfono. La prueba de concepto debe elegir y verificar una integración nativa o un runtime empaquetado mediante un plugin/canal Kotlin. Antes de adoptarlo, comprobar ABI, tamaño del APK, licencias de los binarios, versión mínima de Android, mantenimiento, permisos, soporte de FFmpeg y del motor JavaScript. El `AndroidManifest.xml` principal actualmente no declara `INTERNET`; se necesitaría para red en la versión instalada. Si se conserva audio en almacenamiento privado, registrarlo por ruta local; si se quiere que otras apps lo vean, habría que diseñar una exportación separada por MediaStore. Probar cancelación y continuación al pasar a segundo plano: el servicio actual de `audio_service` es de reproducción, no un servicio de descargas.

### Pantalla y estados

Añadir «Descargar audio» en la biblioteca o un destino secundario de navegación. Campo para URL, análisis previo, título/duración, botón de descarga, progreso y cancelación. Cuando la URL incluye `list=`, ofrecer «solo este video» o «playlist completa», como DVideos. Mostrar resultados parciales y errores por canción. En móvil, la pantalla secundaria debe quedar dentro del shell; en escritorio debe conservar Escape, botón visible de salida y la pila actual. Respetar `AstraColors`, el breakpoint de 840 dp y `MediaQuery.disableAnimations`; no reconstruir toda la pantalla por cada evento de bytes. Acotar diálogos y capturar contextos antes de `await`.

## Orden de implementación y criterios de salida

1. **Prueba de concepto de escritorio:** analizar y descargar una URL pública con el motor elegido; confirmar archivo final, etiquetas y reproducción en AstraMusic. Validar el proceso en Linux y, después, en Windows real. Si esto falla, no diseñar aún la UI final.
2. **Servicio y registro:** puerto de plataforma, carpeta temporal, validación, deduplicación, importación explícita y rollback. Pruebas con backend controlado para éxito, duplicado, archivo vacío, error y cancelación; prueba de repositorio real para identidad y favoritos.
3. **UI de una pista:** flujo completo desde pegar URL hasta verla y reproducirla en la biblioteca, con test de widget por la ruta real de UI; probar error y cancelación. Ejecutar `flutter analyze --no-pub` y `flutter test --reporter failures-only`.
4. **Playlists:** vista previa plana, límites razonables para listas extensas, descarga secuencial inicial, progreso por elemento, fallos parciales, creación de playlist local y prueba de orden/duplicados/rollback.
5. **Android:** prueba de concepto del motor y sus dependencias en un dispositivo real; implementar el adaptador y probar almacenamiento privado, reproducción, segundo plano, cancelación, red interrumpida y espacio insuficiente. Mantener la misma interfaz Dart.

No parece necesario cambiar el esquema Drift para la primera versión: URI, título, metadatos y playlists ya existen. Si luego se desea guardar ID/URL de origen, historial de trabajos o reintentos persistentes, hacer migración con backfill, prueba y código generado según las reglas del proyecto. No hacer depender el arranque de verificaciones de red, herramientas externas o archivos descargados.

## Alcance y decisiones pendientes

- Definir si la primera entrega será solo Linux/Windows o si Android es requisito desde el primer lanzamiento. La viabilidad de Android aún no está demostrada con una prueba real.
- Elegir MP3 siempre o conservar formatos originales compatibles tras medir reproducción, espacio y tiempo.
- Decidir qué hacer con un mismo video descargado dos veces y si una playlist fallida conserva sus canciones completas.
- Confirmar si los audios deben quedarse dentro de la app o aparecer en otras aplicaciones del dispositivo.

El uso personal y la distribución fuera de Google Play eliminan la revisión de esa tienda, pero no cambian las [condiciones de YouTube](https://es.youtube.com/t/terms). Si se usa la API oficial, sus [políticas](https://developers.google.com/youtube/terms/developer-policies) tampoco ofrecen descarga general de audio. La guía es técnica; antes de usar contenido ajeno, verificar los permisos aplicables.

Fuentes técnicas vigentes: [instalación de yt-dlp](https://github.com/yt-dlp/yt-dlp/wiki/Installation), [dependencias y soporte de YouTube](https://github.com/yt-dlp/yt-dlp/blob/master/README.md), [formatos y cambios de sitios](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md).
