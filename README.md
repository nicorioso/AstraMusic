# AstraMusic 1.1.0

AstraMusic es un reproductor de música local, gratuito, 100 % open source y
sin ánimo de lucro. El proyecto nace para que cualquier persona pueda disfrutar
su propia biblioteca musical sin suscripciones, anuncios ni pagos para acceder
a las funciones del reproductor.

La aplicación reproduce archivos almacenados en el dispositivo: no ofrece un
catálogo de música, no descarga canciones y no incluye contenido protegido. La
persona usuaria conserva el control de sus archivos y es responsable de contar
con los permisos necesarios sobre ellos.

## Vista previa de la aplicación

Capturas de la interfaz de escritorio de AstraMusic.

![Pantalla de inicio de AstraMusic con playlists y canciones recientes](screenshots/inincio.png)

| Biblioteca | Playlist |
| --- | --- |
| ![Biblioteca con playlists y accesos a artistas, álbumes, géneros y carpetas](screenshots/biblioteca.png) | ![Detalle de una playlist con carátula y lista de canciones](screenshots/playlist.png) |
| **Reproductor y cola** | **Configuración** |
| ![Reproductor ampliado con la cola de reproducción](screenshots/vista%20grande%20cancion%20y%20cola.png) | ![Configuración con opciones de biblioteca y respaldo](screenshots/menu%20configuracion.png) |

## Plataformas compatibles

- Android.
- Linux.
- Windows.

AstraMusic está construido con Flutter 3.47.x y Dart 3.13.x.

## Descargas oficiales

Los binarios compilados se distribuyen directamente en el servidor oficial
**[AstraMusic Discord](https://discord.gg/pRpghjs34)**: APK para Android e
instalador `.exe` para Windows. Linux se puede ejecutar desde el código fuente;
las instrucciones de compilación están en [la guía de publicación](docs/release.md).

## Funciones principales

- Biblioteca local de canciones.
- Reproducción en segundo plano y controles multimedia del sistema.
- Cola de reproducción, modo aleatorio y repetición.
- Búsqueda, favoritos y playlists.
- Selección múltiple de canciones: pulsación prolongada y toques en Android;
  Ctrl/Cmd y Shift en escritorio para seleccionar y aplicar acciones en lote.
- Importación y exportación de playlists autónomas `.amplaylist`, con audios y
  carátulas opcionales; listas inteligentes basadas en historial y biblioteca.
- Lectura de metadatos y carátulas incrustadas.
- Interfaz adaptable para dispositivos móviles y computadores, con atajos de
  teclado y barra de título propia en escritorio.

## Requisitos generales

1. Instalar [Flutter](https://docs.flutter.dev/get-started/install) 3.47.x, que
   incluye Dart 3.13.x.
2. Agregar el directorio `bin` de Flutter al `PATH`.
3. Instalar Git y las herramientas correspondientes a la plataforma de destino.
4. Comprobar el entorno:

```bash
flutter --version
flutter doctor -v
```

No se deben actualizar Flutter, Dart ni las dependencias del proyecto sin
verificar antes su compatibilidad. Para compilar un APK release firmado, consulta
[la guía de publicación](docs/release.md).

## Obtener el proyecto

```bash
git clone https://github.com/nicorioso/AstraMusic.git
cd AstraMusic
flutter pub get
```

## Ejecutar en Linux

Se necesita un entorno Linux con soporte de escritorio de Flutter y las
herramientas nativas de compilación, entre ellas Clang, CMake, Ninja, pkg-config
y las cabeceras de GTK 3. Los nombres de los paquetes cambian según la
distribución.

```bash
flutter config --enable-linux-desktop
flutter doctor -v
flutter devices
flutter run -d linux
```

El último comando compila una versión de desarrollo y abre AstraMusic. Para
usar una carpeta musical, selecciónala desde la aplicación.

## Ejecutar en Windows

Se requiere Windows 10 u 11, Git, Flutter 3.47.x y Visual Studio 2022 con la
carga de trabajo **Desarrollo para el escritorio con C++**. Visual Studio Code
por sí solo no reemplaza las herramientas de compilación de Visual Studio.

En PowerShell, desde la raíz del proyecto:

```powershell
flutter config --enable-windows-desktop
flutter doctor -v
flutter devices
flutter run -d windows
```

El último comando compila y ejecuta la versión de desarrollo para Windows.

### Crear el instalador de Windows

En Windows, instala Inno Setup 6.3 o posterior y usa PowerShell desde la raíz del proyecto.
El script detiene el empaquetado si falla alguna verificación o faltan archivos
de la compilación. El instalador incluye toda la distribución de Flutter,
crea un acceso directo en el Menú Inicio y permite elegir uno en el Escritorio.
Inno Setup registra el desinstalador automáticamente.

```powershell
.\windows\build-installer.ps1
```

El instalador queda en `build/windows/installer/AstraMusic-Setup-1.1.0.exe`.
Si `ISCC.exe` no está en el `PATH`, pasa su ruta con `-Iscc`. Para compilar
solo el instalador después de construir Windows, usa
`ISCC.exe windows/installer.iss`.

## Ejecutar en Android

Se necesita Android Studio o el Android SDK configurado, además de un emulador
o dispositivo físico. En un teléfono real, activa las opciones de desarrollador
y la depuración USB, conecta el dispositivo y acepta la autorización mostrada
en su pantalla.

```bash
flutter doctor -v
flutter devices
flutter run -d <id-del-dispositivo>
```

Reemplaza `<id-del-dispositivo>` por el identificador que muestra
`flutter devices`. Al usar AstraMusic, concede los permisos de audio y
notificaciones que Android solicite. Las canciones se agregan mediante
**Añadir archivos**.

## Calidad del código

Antes de enviar cambios, ejecuta:

```bash
flutter analyze --no-pub
flutter test --reporter failures-only
```

## Código abierto y contribuciones

AstraMusic se desarrolla de forma abierta para que la comunidad pueda estudiar,
mejorar y adaptar el reproductor. Las contribuciones que mantengan su propósito
gratuito y sin ánimo de lucro son bienvenidas.

AstraMusic se distribuye bajo la [licencia MIT](LICENSE). La fuente Inter
conserva su [licencia SIL OFL 1.1](assets/fonts/OFL.txt). Al distribuir los
binarios, incluye ambos avisos de licencia.
