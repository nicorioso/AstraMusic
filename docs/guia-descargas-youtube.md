# Descargas de audio de YouTube

Estado: incluido en AstraMusic v1.2.0 para Android, Linux y Windows. La aplicación sigue siendo un reproductor de archivos locales: el resultado de cada descarga se incorpora a la biblioteca privada de AstraMusic.

## Uso y motores

La pantalla `AudioDownloadScreen` permite analizar una URL de video o playlist, elegir la playlist completa cuando corresponda, iniciar la descarga, seguir el progreso y cancelar. Presenta las pistas completadas y los errores por elemento. El estado y las acciones viven en `AudioDownloadController`, separado de `LibraryController`.

`AudioDownloadBackend` es el contrato común. `DesktopYtDlpBackend` usa procesos `yt-dlp` en Linux/Windows y verifica la disponibilidad de `yt-dlp` y FFmpeg en el `PATH`. `AndroidYtDlpBackend` habla con `AndroidYtDlpChannel` por canales Flutter; el APK integra `youtubedl-android` y FFmpeg. El canal Kotlin inicializa ambos una sola vez por sesión. Los motores prefieren `bestaudio[ext=m4a]/bestaudio[ext=mp3]/bestaudio`, usan `--concurrent-fragments 4` y `--buffer-size 16K`, y conservan miniaturas auxiliares en su formato original. El selector genérico también puede producir `.opus`; no se fuerza una conversión completa a MP3. La implementación actual no pasa `--force-ipv4`.

En Android, el botón de actualización del motor llama a `updateEngine`. Kotlin intenta el canal nightly de yt-dlp y, si falla, el estable. La pantalla muestra la versión devuelta o el error y puede reintentar la descarga. La actualización es una acción explícita del usuario; el arranque no depende de la red.

El manifiesto Android declara `INTERNET`. El tipo `release` referencia `proguard-rules.pro` para conservar clases del motor y usa `jniLibs.useLegacyPackaging`; no activa explícitamente la minificación. El canal registra en Logcat tiempos de inicialización, extracción, transferencia y posprocesamiento, bytes y tasa aproximada. Esa telemetría es local, sin envío a un servidor.

## Estados y errores

`AudioDownloadController` es un `Notifier` de Riverpod. `AudioDownloadState` expone disponibilidad, previsualización, estado, bytes, progreso y resultado del lote, errores y ocupación. El flujo pasa por análisis, descarga, procesamiento y registro; termina en completado, fallido o cancelado. El controlador cancela el servicio al desecharse. Los backends priorizan líneas `ERROR:` frente a `WARNING:` al presentar fallos; cada elemento de una playlist conserva su propio error.

## Registro y consistencia

`AudioDownloadService` analiza cada video, valida el ID, crea una carpeta temporal por trabajo y comprueba que el archivo final sea audio admitido, no esté vacío y permanezca dentro de esa carpeta. En Android, el canal nativo localiza el archivo válido dentro de esa carpeta después de ejecutar yt-dlp. El servicio lo mueve a `downloaded_audio/<ID>.<ext>` bajo el directorio de soporte de la app. Lee etiquetas y carátulas; usa los datos de YouTube como respaldo. En Android puede pedir la miniatura por HTTPS en paralelo a la descarga cuando el dominio es confiable y la prefiere para M4A. Si falta una imagen válida, prueba la carátula incrustada, la miniatura auxiliar y la URL. Guarda una copia JPEG persistente en `downloaded_artwork/`.

Antes de descargar, busca una pista registrada con cualquiera de las extensiones admitidas para ese ID y verifica que el archivo exista. Si existe, devuelve el duplicado sin reemplazar sus etiquetas, favoritos ni otros datos. Un archivo de destino sin registro produce una colisión explícita; no se sobrescribe. Se repite la consulta por URI antes del `upsertAll` para evitar sustituir una fila creada en paralelo.

Si falla o se cancela el registro de una pista nueva, el servicio elimina el audio recién movido, la carátula nueva y el directorio temporal. Las pistas completadas antes de un fallo de lote se conservan. La playlist local incluye solo éxitos y duplicados válidos, en el orden de la fuente: escritorio descarga hasta dos pistas a la vez y Android procesa una. Los errores quedan asociados al ID de cada entrada. Si falla `addTracks`, se borra la playlist recién creada; las pistas individuales ya registradas permanecen en la biblioteca.

La exportación `.amplaylist` sirve para trasladar playlists con audio. Un respaldo de la base de datos por sí solo no contiene los bytes de las descargas.
