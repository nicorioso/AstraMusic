# AstraMusic

AstraMusic es un reproductor de música local, gratuito, 100 % open source y
sin ánimo de lucro. El proyecto nace para que cualquier persona pueda disfrutar
su propia biblioteca musical sin suscripciones, anuncios ni pagos para acceder
a las funciones del reproductor.

La aplicación reproduce archivos almacenados en el dispositivo: no ofrece un
catálogo de música, no descarga canciones y no incluye contenido protegido. La
persona usuaria conserva el control de sus archivos y es responsable de contar
con los permisos necesarios sobre ellos.

## Plataformas compatibles

- Android.
- Linux.
- Windows.

AstraMusic está construido con Flutter 3.47.x y Dart 3.13.x. Por ahora no se
publican APK, instaladores ni paquetes de escritorio; la aplicación debe
ejecutarse directamente desde el código fuente.

## Funciones principales

- Biblioteca local de canciones.
- Reproducción en segundo plano y controles multimedia del sistema.
- Cola de reproducción, modo aleatorio y repetición.
- Búsqueda, favoritos y playlists.
- Lectura de metadatos y carátulas incrustadas.
- Interfaz adaptable para dispositivos móviles y computadores.

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
verificar antes su compatibilidad.

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

El repositorio todavía no incluye un archivo `LICENSE`. Debe publicarse una
licencia de código abierto antes de distribuir el proyecto a terceros, para
dejar explícitos los permisos de uso, modificación y redistribución.
