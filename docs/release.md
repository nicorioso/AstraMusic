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

Genera una clave de publicación privada. `keytool` solicitará las contraseñas
de forma interactiva; guarda el archivo y sus credenciales en un lugar seguro.

```bash
keytool -genkeypair -v -keystore /ruta/privada/astramusic-release.jks \
  -storetype PKCS12 -keyalg RSA -keysize 3072 -validity 10000 \
  -alias astramusic
cp android/key.properties.example android/key.properties
```

Edita `android/key.properties` con estos cuatro valores reales:

```properties
storeFile=/ruta/privada/astramusic-release.jks
storePassword=CLAVE_DEL_ALMACEN
keyAlias=astramusic
keyPassword=CLAVE_DE_LA_LLAVE
```

Compila con `flutter build apk --release` o `flutter build appbundle --release`.
El AAB queda en `build/app/outputs/bundle/release/`.
Sin `key.properties`, Gradle genera artefactos de release **sin firmar**,
útiles para comprobar la compilación, pero no aptos para distribuir.
Conserva el almacén y sus claves fuera del repositorio; ambos archivos están
excluidos por Git. No uses la clave de depuración para publicar.
La versión publicada se define en `pubspec.yaml` (`versionName+versionCode`)
y el identificador Android es `com.nicorioso.astramusic`.

## Licencias en los paquetes

`LICENSE` (MIT) y `assets/fonts/OFL.txt` (SIL OFL 1.1 de Inter) se incluyen
como recursos de Flutter en Android y Linux. El bundle de Linux también coloca
`LICENSE` en la raíz y `licenses/Inter-OFL.txt` junto al ejecutable. Distribuye
el bundle completo y conserva ambos avisos al crear otro formato de paquete.
