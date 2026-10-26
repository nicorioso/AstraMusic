# AstraMusic — Documentación técnica

> Estado documentado a partir del código fuente, `pubspec.yaml`, `AGENTS.md` y
> `docs/diseno-ui.md`. Este documento describe lo implementado actualmente; no
> es una hoja de ruta.

## 1. Visión general y propósito

AstraMusic es un reproductor gratuito de música **local** para Android, Linux y
Windows. Está dirigido a personas que administran archivos de audio propios y
quieren escucharlos sin depender de una cuenta, un catálogo remoto o una
suscripción.

Su propuesta de valor actual combina:

- biblioteca local indexada y persistente;
- reproducción en primer y segundo plano con controles del sistema;
- experiencia responsive para celular y escritorio;
- playlists, favoritos, búsqueda y una cola editable;
- funcionamiento local: el código no implementa cuentas, sincronización en la
  nube, streaming de catálogo ni telemetría remota.

La aplicación tiene la versión `1.0.0+1` en `pubspec.yaml` y usa el identificador
`com.nicorioso.astramusic` en Android y Linux.

## 2. Stack tecnológico

### Plataforma y lenguaje

| Área | Tecnología | Uso comprobado |
|---|---|---|
| UI multiplataforma | Flutter 3.47.x | Interfaz Material 3 para Android, Linux y Windows |
| Lenguaje | Dart 3.13.x (`sdk: ^3.13.5`) | Aplicación, dominio, persistencia y pruebas |
| Android nativo | Kotlin/JVM 17 | Escaneo de MediaStore y obtención de carátulas mediante canales de plataforma |
| Linux | C++/CMake, GTK 3 | Runner de escritorio |
| Windows | C++/CMake | Runner Win32 |

El SDK de Flutter/Dart está fijado por política del proyecto y no debe
actualizarse como parte de cambios ordinarios.

### Librerías principales

| Dependencia | Responsabilidad |
|---|---|
| `flutter_riverpod` 3.x | Inyección de dependencias, estado reactivo y navegación interna |
| `drift` + `drift_flutter` | Base de datos SQLite tipada, consultas reactivas y migraciones |
| `just_audio` | Motor de reproducción |
| `audio_service` | `AudioHandler`, notificación, controles multimedia y reproducción en segundo plano |
| `just_audio_media_kit` | Backend de `just_audio` para Linux y Windows |
| `media_kit_libs_linux` / `media_kit_libs_windows_audio` | Bibliotecas nativas de audio de escritorio |
| `audio_session` | Sesión de música, interrupciones y evento de desconexión de audífonos |
| `audio_service_mpris` | Integración MPRIS declarada para Linux; no hay configuración Dart explícita adicional |
| `audio_metadata_reader` | Lectura de etiquetas y carátulas embebidas de archivos locales |
| `file_picker` | Selección de carpetas y archivos |
| `permission_handler` 12.0.3 | Permisos de audio/notificaciones y apertura de ajustes |
| `path` / `path_provider` | Rutas y directorios de datos/caché de la aplicación |
| `diacritic` | Normalización de búsqueda sin diacríticos |

### Herramientas de desarrollo

- `flutter_lints` con casts, inferencia y tipos raw en modo estricto.
- `build_runner` + `drift_dev` para generar el código de Drift.
- `flutter_test` y `fake_async` para pruebas unitarias y de widgets.
- `flutter_launcher_icons` para regenerar iconos desde
  `assets/branding/logo.png`.
- Gradle/Kotlin para Android y CMake para Linux/Windows.

## 3. Arquitectura del software

### Enfoque

La aplicación usa una arquitectura **feature-first por capas**, inspirada en
Clean Architecture, pero no es una implementación canónica completa. Las
entidades y contratos de dominio están separados de Drift y de los plugins;
Riverpod ensambla adaptadores, repositorios, controladores y UI.

```text
Widget / pantalla
      │ observa e invoca
      ▼
Provider + controller (presentación)
      │ coordina casos de uso
      ▼
Servicio de aplicación / contrato de dominio
      │
      ├── Repositorio Drift ──► SQLite local
      └── Interfaz de plataforma ──► plugin o canal nativo
```

La UI consume modelos `Track`, `Playlist` y `LibraryFolder`; no recibe filas
generadas por Drift. Los mappers convierten entre ambos mundos.

### Estructura de carpetas

```text
lib/
├── main.dart                         # arranque, recursos y ProviderScope
├── core/
│   ├── db/                           # esquema Drift y migraciones
│   ├── diagnostics/                  # métricas locales de rendimiento
│   ├── navigation/                   # destinos e historial simple
│   ├── platform/                     # puertos y adaptadores de SO/plugins
│   ├── theme/                        # Gargantua, contraste y color dinámico
│   ├── utils/                        # búsqueda y throttling
│   └── widgets/                      # shell responsive y widgets compartidos
└── features/
    ├── library/
    │   ├── application/              # sincronización y backfill de carátulas
    │   ├── data/                     # repositorios Drift y mappers
    │   ├── domain/                   # Track, carpetas y contratos
    │   └── presentation/             # providers, controller y pantallas
    ├── player/
    │   ├── application/              # persistencia de sesión
    │   ├── data/                     # AudioHandler y adaptadores
    │   ├── domain/                   # reglas puras de cola/interrupciones
    │   └── presentation/             # controller, reproductor, cola y seek
    ├── playlists/                    # dominio, Drift y widgets/pantallas
    └── settings/                     # reservado; UI actual vive en el shell
```

### Ensamblaje y arranque

`main.dart` inicializa bindings, diagnósticos, backend de escritorio,
`AudioService`, sesión de audio y Drift. `StartupGate` ejecuta la inicialización
después del primer frame, aplica un timeout y ofrece reintento en caso de error.
Después arranca, sin bloquear la UI, la restauración de reproducción y la
verificación de disponibilidad de archivos. `ProviderScope` inyecta las
instancias compartidas.

### Flujo de datos

- Los repositorios Drift exponen `Stream` reactivos.
- `StreamProvider` transforma esos streams en estado consumible por widgets.
- Los `Notifier` (`LibraryController`, `PlayerController`, `AppNavigation`)
  coordinan acciones y publican estados inmutables de vista.
- Los contratos en `core/platform` aíslan selección de archivos, permisos,
  escaneo, audio, carátulas y persistencia de reproducción.
- Los comandos de audio que alteran estado se serializan; la posición se limita
  a una actualización cada 250 ms y se escucha solo con la app en primer plano.

### Persistencia local

`AppDatabase` usa Drift/SQLite con esquema versión 8:

| Tabla | Contenido |
|---|---|
| `tracks` | URI, metadatos, claves de búsqueda/orden, disponibilidad, favorito y carátula |
| `playlists` | Nombre, creación, actualización y última reproducción |
| `playlist_tracks` | Relación ordenada playlist–canción, sin duplicados |
| `library_folders` | Carpetas de escritorio y última fecha de escaneo |
| `playback_state` | Índice, posición, aleatorio, repetición y actualización |
| `queue_items` | Cola persistida y posición original para aleatorio |
| `excluded_uris` | Canciones borradas de la app que el escaneo no debe revivir |

Las migraciones incluyen backfills de búsqueda y favoritos, índices, claves
foráneas y limpieza de duplicados. El estado de reproducción restaura cola,
índice, posición, repetición y orden aleatorio.

### Navegación

No se usa un router externo. `AppNavigation` conserva el destino actual y una
pila simple para pantallas secundarias. Los destinos son Inicio, Buscar,
Biblioteca, Playlist, Cola, Carpetas, Ajustes y Diagnóstico. En móvil estas
pantallas permanecen dentro del shell; el reproductor completo es una ruta
`Navigator` independiente. Escape cierra o vuelve en flujos de escritorio.

## 4. Funcionalidades principales

### Biblioteca e importación

- **Android:** escanea el catálogo mediante MediaStore y un `MethodChannel`.
  Solicita permiso de audio, admite progreso/cancelación y obtiene carátulas
  nativas desde URI `content://`.
- **Linux/Windows:** permite registrar varias carpetas, las recorre en un
  isolate sin seguir enlaces simbólicos y admite MP3, FLAC, M4A, AAC, OGG,
  Opus y WAV.
- **Importación manual:** permite añadir archivos individuales en todas las
  plataformas.
- Extrae título, artista, álbum, duración, número de pista, año y carátula; si
  fallan las etiquetas usa el nombre del archivo e informa el error parcial.
- La sincronización incremental compara tamaño y fecha de modificación,
  actualiza por lotes de 500 y marca como no disponibles los archivos ausentes.
- Borrar una canción la elimina solo de AstraMusic, la quita de la cola y guarda
  su URI en exclusiones. Volver a añadirla manualmente restaura la exclusión.

### Búsqueda, orden y favoritos

- Búsqueda reactiva con debounce de 300 ms por título, artista o álbum.
- Texto normalizado a minúsculas, sin diacríticos y con espacios compactados;
  se consulta `search_text` y se ordena por `sort_title` e ID.
- Búsqueda de playlists por nombre desde la pantalla de búsqueda.
- Favoritos persistentes ordenados por `favorited_at`; la playlist virtual
  “Canciones que te gustan” reutiliza esos resultados.

### Reproducción y segundo plano

- Reproduce archivos locales y colas mediante `just_audio`.
- `audio_service` publica controles, metadatos, carátula y notificación de
  reproducción en Android, además de aceptar botones multimedia.
- En Android declara servicio foreground de tipo `mediaPlayback`, `WAKE_LOCK`
  y receptor de botones multimedia.
- La sesión de audio responde a interrupciones permanentes, transitorias y
  ducking mediante una política pura; desconectar audífonos pausa.
- Controles: reproducir/pausar, anterior, siguiente, seek, volumen/silencio,
  repetir todo/una y aleatorio.
- El aleatorio permuta manualmente la cola conservando la pista y posición
  actuales; al desactivarlo recupera el orden original.
- Los seeks se envían únicamente al terminar el gesto y solicitudes pendientes
  se coalescen para que gane la última.
- Un fallo fatal de la canción actual intenta avanzar a una pista reproducible;
  avisos no fatales mantienen controles utilizables. Una carga de más de diez
  segundos muestra una advertencia recuperable.
- Cola editable: añadir al final, reproducir a continuación, saltar, eliminar,
  vaciar y reordenar con arrastre.

### Playlists

- Crear, renombrar y eliminar playlists sin borrar archivos de audio.
- Añadir canciones sin duplicarlas, quitar canciones y reordenarlas.
- Reproducir en orden o aleatorio; el inicio registra `lastPlayedAt`.
- Portada tipo mosaico 2×2 con hasta cuatro carátulas distintas y fallback
  visual cuando no existen.
- Inicio presenta hasta ocho accesos: playlists reproducidas recientemente,
  luego Favoritos y finalmente las más nuevas, sin duplicados.

### Carátulas y caché

- En escritorio se extrae arte embebido y también se detectan `cover`, `folder`
  o `front` en JPG/PNG junto al audio.
- En Android se generan miniaturas de MediaStore en buckets de 128, 256 y
  640 px.
- `CachedArtworkProvider` deduplica cargas, limita concurrencia a tres y usa un
  LRU en memoria de 8 MiB; las miniaturas Android también se guardan en disco.
- Un backfill posterior al primer frame completa carátulas antiguas.
- El diagnóstico mide el caché; borrar una canción elimina arte no compartido y
  vaciar la biblioteca limpia todo el caché de carátulas.
- **No existe caché de audio**: la reproducción siempre usa archivos locales.

### Ajustes y diagnóstico

- Gestión de carpetas, actualización de biblioteca y adición manual de archivos.
- Advertencia y acceso a ajustes cuando faltan notificaciones en Android.
- Acceso a ajustes de optimización de batería sin solicitar el permiso
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.
- Eliminación total confirmada de canciones, playlists, cola, carpetas,
  exclusiones y caché, sin borrar archivos del dispositivo.
- En debug: datos de prueba y métricas de primer frame, carga de biblioteca,
  carga de cola, cachés y reconstrucciones.

### Capacidades no encontradas

- Letras sincronizadas o no sincronizadas: **[Por definir / Pendiente]**.
- Streaming, descarga o caché de audio: **[Por definir / Pendiente]**.
- Ecualizador, velocidad de reproducción y crossfade: **[Por definir / Pendiente]**.
- Sincronización entre dispositivos, cuentas o respaldo en nube:
  **[Por definir / Pendiente]**.

## 5. Sistema de diseño y UI

### Principios

El sistema “Gargantua” toma como referencia una interfaz musical oscura. Usa
Material 3, solo tema oscuro, tipografía Inter incluida como asset y fallbacks
CJK del sistema. Los colores viven en `AstraColors`, una `ThemeExtension`; los
widgets no deben introducir colores fijos.

| Token | Color | Uso principal |
|---|---:|---|
| `void` | `#050506` | Fondo base |
| `surface` | `#0F0D0C` | Paneles |
| `surfaceRaised` | `#1A1613` | Tarjetas y reproductor |
| `surfaceHover` | `#241E19` | Hover y selección |
| `divider` | `#2B231C` | Separadores |
| `accent` | `#F2A33A` | Acción primaria, activo y pista actual |
| `accentHover` | `#FFB95A` | Hover del acento |
| `ember` | `#D9531E` | Detalle secundario y degradados |
| `photon` | `#FFE7BF` | Progreso y brillo |
| `text` | `#F5EBDD` | Texto principal |
| `textMuted` | `#A99B8C` | Texto secundario |
| `textDisabled` | `#6B5F54` | Estado deshabilitado |
| `error` | `#E5484D` | Errores y acciones destructivas |

El fondo dinámico extrae color de la carátula, lo oscurece hasta luminosidad
HSL 0,2 y lo usa solo si alcanza contraste 4,5:1 con el texto. El resultado se
cachea con capacidad de 48 entradas; si falla, conserva Gargantua.

### Responsive y navegación visual

El único breakpoint es **840 dp**:

- **Escritorio (≥ 840 dp):** barra lateral de biblioteca de 300 dp plegable a
  72 dp, panel central con margen y radio de 8 dp, búsqueda superior y barra de
  reproducción inferior de 88 dp. La zona derecha de esa barra contiene solo
  volumen.
- **Móvil (< 840 dp):** navegación inferior Inicio/Buscar/Biblioteca,
  mini-reproductor flotante de 64 dp y pantallas secundarias dentro del shell.
  Tocar el mini-reproductor abre la vista completa; también puede cerrarse por
  botón o gesto vertical.

Inicio usa una rejilla de dos columnas en móvil y hasta cuatro en escritorio.
Las listas muestran carátula, metadatos, disponibilidad, estado actual y menú de
acciones. La pantalla completa del reproductor incluye carátula grande,
progreso, controles y acceso a la cola; en escritorio la cola comparte espacio
con el reproductor.

### Comportamiento y accesibilidad

- Controles táctiles de al menos 48 dp, tooltips y foco de teclado visible.
- Animaciones breves; si `MediaQuery.disableAnimations` está activo, las
  transiciones se omiten o detienen.
- El progreso se aísla para evitar reconstruir pantallas completas por tick.
- La pista y modos activos usan acento; el progreso usa `photon` y cambia a
  acento con hover.
- Pantallas completas ofrecen salida visible y Escape en escritorio.
- Diálogos y paneles limitan su contenido; listas extensas usan vistas
  desplazables y cache extent controlado.

## 6. Guía de trabajo para agentes

### Restricciones obligatorias

1. Responder en español, de forma profesional, directa y concisa; el informe
   final no debe superar diez líneas ni incluir diffs o logs.
2. Mantener Flutter 3.47.x, Dart 3.13.x y `permission_handler` 12.0.3.
3. No usar `sudo`, no ejecutar la aplicación, no compilar Windows y no hacer
   builds salvo petición explícita.
4. Añadir dependencias únicamente mediante `flutter pub add` y verificar APIs
   desconocidas en `~/.pub-cache`.
5. Preservar cambios ajenos, no commitear secretos y hacer un commit pequeño
   por tarea.
6. Por tarea ejecutar solo:

   ```bash
   flutter analyze --no-pub
   flutter test --reporter failures-only
   ```

7. Todo bug corregido requiere una prueba; todo flujo UI debe probarse por su
   camino real, no únicamente con fakes.

### Convenciones arquitectónicas

- Mantener infraestructura transversal en `lib/core` y módulos funcionales en
  `lib/features`.
- La UI no puede importar filas de Drift. Playlists opera exclusivamente con
  modelos y repositorios de dominio.
- Encapsular todo comportamiento específico de plataforma detrás de interfaces
  en `core/platform`.
- Usar `DesktopShell` y `MobileShell`; no crear breakpoints adicionales.
- En móvil, conservar pantallas secundarias en el shell; solo el reproductor
  completo es una ruta separada.
- La navegación debe seguir aceptando destinos de playlist y una pila simple de
  retorno en escritorio.
- Usar `AstraColors`; los fondos decorativos van en un `Stack` y no deben fijar
  la altura del contenido.
- Respetar `MediaQuery.disableAnimations` y aislar los widgets que cambian por
  ticks de reproducción.
- Capturar `BuildContext`/`Navigator` antes de un `await`, comprobar `mounted` y
  acotar contenido de diálogos y paneles.

### Invariantes de dominio y audio

- El arranque no puede depender de archivos del usuario. Restauraciones,
  disponibilidad y backfills corren después del primer frame y con manejo de
  errores.
- `InterruptionPolicy` concentra pausa, reanudación y ducking; los plugins solo
  traducen eventos.
- Aleatorio es una permutación manual. No usar `shuffle()`,
  `setShuffleModeEnabled()` ni `ConcatenatingAudioSource`.
- Hacer seek solo en `onChangeEnd` y conservar la coalescencia de solicitudes.
- Un error fatal de la pista actual avanza; uno no fatal informa sin deshabilitar
  controles.
- Búsqueda usa `search_text`, `normalizeForSearch` y orden por `sort_title`.
- Borrar es solo de la app y debe alimentar `excluded_uris`.
- `is_favorite` es verdadero si y solo si `favorited_at` no es nulo.
- `markPlayed` registra el inicio desde una playlist y `watchRecent` excluye las
  nunca reproducidas.
- Nunca solicitar `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`; solo abrir ajustes.

### Cambios de base de datos y recursos

Todo cambio de esquema requiere migración, backfill cuando aplique, prueba de
migración, ejecución de `build_runner` y commit de los archivos generados. Los
iconos se regeneran con:

```bash
dart run flutter_launcher_icons
```

Antes de modificar audio, navegación, persistencia o UI responsive, revisar las
pruebas correspondientes en `test/` y ampliar la cobertura en el mismo cambio.
