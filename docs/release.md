# Instalación y empaquetado de AstraMusic

Usa Flutter 3.47.x, Dart 3.13.x y los SDK de Android y Linux indicados en
`README.md`. Desde la raíz del proyecto:

```bash
flutter clean
flutter pub get
flutter analyze --no-pub
flutter test --reporter failures-only
flutter build apk --release
flutter build linux --release
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`. La carpeta
`build/linux/x64/release/bundle/` contiene el ejecutable `astramusic`, los
recursos y las bibliotecas; distribúyela completa. En Linux, descomprime el
paquete y ejecuta `./astramusic` desde esa carpeta.

## Firma de Android

Para distribuir el APK, crea un almacén de claves privado y el archivo
`android/key.properties` con estos cuatro valores:

```properties
storeFile=/ruta/privada/astramusic-release.jks
storePassword=CLAVE_DEL_ALMACEN
keyAlias=astramusic
keyPassword=CLAVE_DE_LA_LLAVE
```

Vuelve a compilar con `flutter build apk --release`. Sin `key.properties`,
Gradle genera un APK de release **sin firmar**, útil para comprobar la
compilación, pero no apto para instalar o distribuir. Conserva el almacén y
sus claves fuera del repositorio; ambos archivos están excluidos por Git.
La versión publicada se define en `pubspec.yaml` (`versionName+versionCode`)
y el identificador Android es `com.nicorioso.astramusic`.

Antes de distribuir a terceros, define y publica una licencia de software;
el repositorio aún no incluye `LICENSE`.
