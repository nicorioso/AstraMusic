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
```

Crea `android/key.properties` con estos cuatro valores reales:

```properties
storeFile=/ruta/privada/astramusic-release.jks
storePassword=CLAVE_DEL_ALMACEN
keyAlias=astramusic
keyPassword=CLAVE_DE_LA_LLAVE
```

Escribe las contraseñas sin comillas: en un archivo `.properties`, las comillas
se interpretan como parte del valor y la firma falla aunque la clave sea correcta.
`storeFile` puede ser absoluto o relativo a `android/` o `android/app/`.
Después de configurar la firma, ejecuta `flutter clean`, `flutter pub get` y
compila con `flutter build apk --release` o `flutter build appbundle --release`.
El AAB queda en `build/app/outputs/bundle/release/`. Gradle exige una firma
para `release`; sin un almacén válido, la compilación debe fallar.
Si Gradle informa `keystore password was incorrect`, comprueba que
`storePassword` corresponda al almacén indicado por `storeFile`; `keyPassword`
corresponde a la llave de `keyAlias`. No publiques ni registres esas claves.
Conserva el almacén y sus claves fuera del repositorio; ambos archivos están
excluidos por Git. No uses la clave de depuración para publicar.
La versión publicada se define en `pubspec.yaml` (`versionName+versionCode`)
y el identificador Android es `com.nicorioso.astramusic`.

Para instalación local, usa el APK y verifica su firma antes de instalar:

```bash
apksigner verify --verbose build/app/outputs/flutter-apk/app-release.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Un `.aab` no se instala con `adb install`: está destinado a una tienda o a la
generación de APKs mediante `bundletool`. Si `adb install -r` informa
`INSTALL_FAILED_UPDATE_INCOMPATIBLE`, la versión instalada usa otra clave.
Conserva la misma clave para actualizarla o desinstala la versión anterior
solo después de respaldar los datos de la aplicación.

## Licencias en los paquetes

`LICENSE` (MIT) y `assets/fonts/OFL.txt` (SIL OFL 1.1 de Inter) se incluyen
como recursos de Flutter en Android y Linux. El bundle de Linux también coloca
`LICENSE` en la raíz y `licenses/Inter-OFL.txt` junto al ejecutable. Distribuye
el bundle completo y conserva ambos avisos al crear otro formato de paquete.
