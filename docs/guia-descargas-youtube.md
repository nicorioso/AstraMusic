# Descargas de audio de YouTube

Estado: implementado en Android, Linux y Windows en la rama `feature/youtube-audio-downloader`. La aplicación sigue siendo un reproductor de archivos locales: el resultado de cada descarga se incorpora a la biblioteca privada de AstraMusic.

## Uso y motores

La pantalla `AudioDownloadScreen` permite analizar una URL de video o playlist, elegir la playlist completa cuando corresponda, iniciar la descarga, seguir el progreso y cancelar. Presenta las pistas completadas y los errores por elemento. El estado y las acciones viven en `AudioDownloadController`, separado de `LibraryController`.

`AudioDownloadBackend` es el contrato común. `DesktopYtDlpBackend` usa procesos `yt-dlp` en Linux/Windows y verifica la disponibilidad de `yt-dlp` y FFmpeg. `AndroidYtDlpBackend` habla con `AndroidYtDlpChannel` por canales Flutter; el canal Kotlin usa el motor integrado y ejecuta la inicialización de YoutubeDL y FFmpeg una sola vez por sesión. Ambos motores prefieren `bestaudio[ext=m4a]/bestaudio[ext=mp3]/bestaudio`, usan `--concurrent-fragments 4` y `--buffer-size 16K`, y conservan miniaturas auxiliares en su formato original. No se fuerza una conversión completa a MP3.

En Android, el botón de actualización del motor llama a `updateEngine`. Kotlin intenta el canal nightly de yt-dlp y, si falla, el estable. La pantalla muestra la versión devuelta o el error y puede reintentar la descarga. La actualización es una acción explícita del usuario; el arranque no depende de la red.

## Registro y consistencia

`AudioDownloadService` analiza cada video, valida el ID, crea una carpeta temporal por trabajo y comprueba que el archivo final sea audio admitido, no esté vacío y permanezca dentro de esa carpeta. Lo mueve a `downloaded_audio/<ID>.<ext>` bajo el directorio de soporte de la app. Lee etiquetas y carátulas; usa los datos de YouTube como respaldo. En Android puede pedir la miniatura por HTTP en paralelo a la descarga cuando hay una URL confiable, y solo la usa si falta una imagen local válida.

Antes de descargar, busca una pista registrada con cualquiera de las extensiones admitidas para ese ID y verifica que el archivo exista. Si existe, devuelve el duplicado sin reemplazar sus etiquetas, favoritos ni otros datos. Un archivo de destino sin registro produce una colisión explícita; no se sobrescribe. Se repite la consulta por URI antes del `upsertAll` para evitar sustituir una fila creada en paralelo.

Si falla o se cancela el registro de una pista nueva, el servicio elimina el audio recién movido, la carátula nueva y el directorio temporal. Las pistas completadas antes de un fallo de lote se conservan. La playlist local incluye solo éxitos y duplicados válidos, en el orden de la fuente: escritorio descarga hasta dos pistas a la vez y Android procesa una. Los errores quedan asociados al ID de cada entrada. Si falla `addTracks`, se borra la playlist recién creada; las pistas individuales ya registradas permanecen en la biblioteca.

La exportación `.amplaylist` sirve para trasladar playlists con audio. Un respaldo de la base de datos por sí solo no contiene los bytes de las descargas.
