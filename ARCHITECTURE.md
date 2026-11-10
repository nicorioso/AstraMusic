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

La aplicación tiene la versión `1.1.0+2` en `pubspec.yaml` y usa el identificador
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
| `desktop_drop` 0.8.4 | Entrega nativa de archivos y carpetas en escritorio; adaptador en `core/platform/desktop_drop_import.dart` |
| `permission_handler` 12.0.3 | Permisos de audio/notificaciones y apertura de ajustes |
| `archive` | Creación y lectura de paquetes ZIP `.amplaylist` |
| `window_manager` | Ventana de escritorio sin marco y controles de la barra de título |
| `path` / `path_provider` | Rutas y directorios de datos/caché de la aplicación |
| `diacritic` | Normalización de búsqueda sin diacríticos |

### Herramientas de desarrollo

- `flutter_lints` con casts, inferencia y tipos raw en modo estricto.
- `build_runner` + `drift_dev` para generar el código de Drift.
- `flutter_test` y `fake_async` para pruebas unitarias y de widgets.
- `flutter_launcher_icons` para regenerar iconos desde
  `assets/branding/logo.png`.
- Gradle/Kotlin para Android y CMake para Linux/Windows.
- Inno Setup 6.3 o posterior para el instalador `.exe` de Windows;
  `windows/build-installer.ps1` comprueba análisis, pruebas y archivos antes de empaquetar.

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
    └── settings/                     # herramientas de portabilidad y controles de Ajustes
```

### Ensamblaje y arranque

`main.dart` prepara bindings y diagnósticos y monta `StartupGate` antes de
abrir archivos del usuario. Tras el primer frame, el gate inicializa el backend
de escritorio, `AudioService`, sesión de audio y Drift; aplica un timeout de 15 s
y ofrece reintento. La restauración de cola y la verificación de disponibilidad
arrancan después en segundo plano con manejo de errores. `ProviderScope`
inyecta la base, el servicio de audio y el proveedor de carátulas compartidos;
`StartupResources.dispose` cierra coordinador, servicio y base en ese orden.

### Flujo de datos

- Los repositorios Drift exponen `Stream` reactivos; Riverpod administra sus
  suscripciones mientras los widgets observan los providers.
- La biblioteca principal observa ventanas de 100 canciones y amplía la
  consulta al acercarse al final; búsquedas y cambios de datos conservan la
  reactividad sin cargar el catálogo completo al entrar a la pantalla.
- `StreamProvider` transforma esos streams en estado consumible por widgets.
- Los `Notifier` (`LibraryController`, `PlayerController`, `AppNavigation`)
  coordinan acciones y publican estados inmutables de vista.
- Los contratos en `core/platform` aíslan selección de archivos, permisos,
  escaneo, audio, carátulas y persistencia de reproducción.
- Los comandos de audio que alteran estado se serializan; la posición se limita
  a una actualización cada 250 ms y se escucha solo con la app en primer plano.

| Flujo | Persistencia y adaptación | Estado observado por la vista |
|---|---|---|
| Biblioteca y búsqueda | `DriftTrackRepository` consulta `tracks` y `tracks_fts`; `track_mapper` produce `Track` | `libraryTracksProvider` entrega una ventana y `LibraryController` coordina acciones |
| Playlists manuales | `DriftPlaylistRepository` une `playlists`, `playlist_tracks` y `tracks`; entrega modelos `Playlist` y `Track` | `playlistsProvider`, `playlistTracksProvider` y destinos del shell |
| Playlists inteligentes | `DriftSmartPlaylistRepository` consulta `tracks` y, para Recientes, `play_history` | `smartPlaylistTracksProvider` cancela la observación al dejar la selección; Inicio trata listas vacías por separado |
| Reproducción | `AstraAudioHandler` publica cola, ítem y estado; `AudioHandlerPlayerService` los adapta | `PlayerController` une streams en `PlayerViewState`; el progreso se observa aparte |
| Historial | `PlayerController` detecta un inicio con ID de pista y llama `recordPlay` | La transacción actualiza `play_count` y `play_history`, lo que invalida las consultas reactivas |

### Modelos y estado global

- `Track` es la entidad de canción que usan biblioteca, cola y UI; contiene
  URI, etiquetas, duración, fechas, disponibilidad, favorito y carátula. El
  contador vive en la tabla `tracks` y se consulta para ordenar las listas
  inteligentes; no forma parte del modelo `Track` actual.
- `Playlist` y `LibraryFolder` representan listas manuales y carpetas. Los
  grupos `ArtistGroup`, `AlbumGroup`, `GenreGroup` y `FolderGroup` proyectan
  agrupaciones para Biblioteca. `SmartPlaylist` es un enum de consultas
  virtuales, no una entidad persistida.
- `PlayerViewState` publica estado, posición, duración, ítem actual, cola,
  índice, aleatorio, repetición, volumen y mensaje de error. `LibraryViewState`
  concentra escaneo y acciones de biblioteca. `AppDestination` y
  `AppNavigation` conservan destino y pila simple.
- `appDatabaseProvider` se sobrescribe con la instancia creada en el arranque;
  los providers de repositorio reciben esa misma base. `libraryTracksProvider`
  usa filtros, búsqueda y límite de ventana; `smartPlaylistTracksProvider`
  recibe un `SmartPlaylist`; `playlistsProvider`, `favoriteTracksProvider` y
  los providers de grupos exponen otras proyecciones reactivas.

### Persistencia local

`AppDatabase` usa Drift/SQLite con esquema versión **13** (`schema_versions/13.json`):

| Tabla | Contenido |
|---|---|
| `tracks` | URI, metadatos, claves de búsqueda/orden, disponibilidad, favorito, carátula y `play_count` (entero, 0 por defecto) |
| `playlists` | Nombre, ruta de carátula personalizada, creación, actualización y última reproducción |
| `playlist_tracks` | Relación ordenada playlist–canción, sin duplicados |
| `play_history` | Un evento por inicio de pista: `track_id`, `played_at` e ID de evento; FK con borrado en cascada |
| `library_folders` | Carpetas de escritorio y última fecha de escaneo |
| `playback_state` | Índice, posición, aleatorio, repetición y actualización |
| `queue_items` | Cola persistida y posición original para aleatorio |
| `excluded_uris` | Canciones borradas de la app que el escaneo no debe revivir |

Las migraciones incluyen backfills de búsqueda, favoritos y fecha de adición de
playlists, índices y limpieza de duplicados. La v13 agrega `play_count` con
backfill a cero y crea `play_history`; índices cubren contador, fecha e ID de
pista. `recordPlay` actualiza contador e inserta historial en una transacción
asíncrona; no registra pistas ausentes de la biblioteca. Las FK se habilitan
antes de abrir la base, por lo que borrar una pista elimina su historial.
El estado de reproducción restaura cola, índice, posición, repetición y orden
aleatorio.

### Playlists inteligentes y estadísticas

`SmartPlaylistRepository` define las cuatro consultas y `recordPlay`;
`DriftSmartPlaylistRepository` implementa ambas operaciones. El
`smartPlaylistTracksProvider` parametrizado entrega `Stream<List<Track>>` a
Inicio. Las consultas limitan a 100 pistas disponibles: `Recientes` toma la
última fecha por pista y desempata con el ID del último evento;
`Más escuchadas` ordena por `play_count` descendente; `Nunca reproducidas`
filtra contador cero; `Añadidas recientemente` ordena por `date_added`
descendente. La pestaña inicial de Inicio usa `homeRecentTracksProvider`, que
aplica el mismo orden de adición y tiene fallback para repositorios de prueba.
No son filas de la tabla `playlists` ni se editan como listas manuales.

`PlayerController` escucha estado, cola e índice del servicio y registra el
inicio cuando hay reproducción activa y un ID de biblioteca válido. Evita
recontar pausas, reanudaciones y reordenaciones, y suprime emisiones
intermedias al reemplazar la cola. Al iniciar otra cola reinicia la deduplicación
para contar también una nueva reproducción de la misma pista. El guardado no
bloquea la acción de audio;
si falla, muestra un error no fatal. `play_history` conserva todos los eventos:
no hay política de retención implementada.

### Navegación

No se usa un router externo. `AppNavigation` conserva el destino actual y una
pila simple para pantallas secundarias. Los destinos son Inicio, Buscar,
Biblioteca, Playlist, Cola, Carpetas, Ajustes y Diagnóstico. En móvil estas
pantallas permanecen dentro del shell; el reproductor completo es una ruta
`Navigator` independiente. Escape cierra o vuelve en flujos de escritorio.

## 4. Funcionalidades principales

### Biblioteca e importación

- **Android:** escanea el catálogo mediante MediaStore y un `MethodChannel`.
  Consulta fuera del hilo principal, entrega resultados en lotes de 100,
  admite progreso/cancelación y obtiene carátulas nativas desde URI `content://`.
- **Linux/Windows:** permite registrar varias carpetas, las recorre en un
  isolate sin seguir enlaces simbólicos, entrega lotes de 100 y admite MP3,
  FLAC, M4A, AAC, OGG, Opus y WAV.
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

### Trayecto de un comando de audio

`PlayerController` recibe la acción de la vista y llama a `AudioPlayerService`.
La implementación `AudioHandlerPlayerService` adapta ese contrato a
`AstraAudioHandler`, que serializa órdenes, gestiona `just_audio`, publica
`queue`, `mediaItem` y `playbackState` en `audio_service` y traduce eventos de
sesión con `InterruptionPolicy`. `ManualQueueOrder` conserva el orden original
al activar aleatorio. `LatestSeekCoordinator` coalesce seeks pendientes.
`PlaybackPersistenceCoordinator` escucha el servicio y guarda cola/posición con
debounce y escritura serializada mediante `DriftPlaybackStateRepository`;
restaura en pausa tras el primer frame. El controller mantiene suscripciones
hasta `ref.onDispose`; el coordinador cancela timers y streams en `dispose`.
El provider parametrizado de listas inteligentes usa `autoDispose` para cancelar
su consulta al dejar de observar una selección; otros providers globales
permanecen vivos según el ciclo de vida del `ProviderScope`. El escáner de
Android cierra su `StreamController` al terminar, cancelar o fallar; el de
escritorio detiene su isolate.

La sesión de escaneo consume el stream con `await for` y espera cada escritura
de lote antes de seguir. `LibraryController` cancela el escaneo activo al
disponerse. `AudioHandlerPlayerService` cancela la escucha de carátulas y
`AstraAudioHandler` cancela las suscripciones del motor y de `audio_session` al
cerrarse. Las consultas sin filas producen listas vacías; Inicio y Biblioteca
muestran estados vacíos y las operaciones de reproducción rechazan una cola sin
pistas disponibles.

### Playlists

- Crear, renombrar y eliminar playlists sin borrar archivos de audio.
- Añadir canciones sin duplicarlas, quitar canciones y reordenarlas.
- Reproducir en orden o aleatorio; el inicio registra `lastPlayedAt`.
- Portada tipo mosaico 2×2 con hasta cuatro carátulas distintas y fallback
  visual cuando no existen; se puede elegir una carátula personalizada.
- Inicio presenta hasta ocho accesos a playlists manuales: reproducidas
  recientemente, luego Favoritos y finalmente las más nuevas, sin duplicados.
- Debajo, cuatro selecciones de canciones inteligentes reutilizan la lista
  responsive y sus acciones de reproducción. Una selección sin resultados
  muestra su propio estado vacío, sin declarar vacía toda la biblioteca.

### Paquetes autónomos `.amplaylist`

`SmartPackageService` exporta una playlist manual como archivo ZIP con esta
estructura (formato `version: 1`):

```text
playlist.json
audio/00000.mp3
audio/00001.flac
images/playlist_cover.png       # opcional
images/track_00000.jpg          # opcional
```

El manifiesto JSON conserva el orden de `tracks`; `description` es obligatorio
en el formato, aunque el exportador actual lo escribe como cadena vacía:

```json
{
  "version": 1,
  "name": "Viaje",
  "description": "",
  "coverImage": "images/playlist_cover.png",
  "tracks": [
    {
      "title": "Canción",
      "artist": "Artista",
      "album": "Álbum",
      "durationMs": 180000,
      "file": "audio/00000.mp3",
      "artUri": "images/track_00000.jpg"
    }
  ]
}
```

`coverImage` y `artUri` se omiten si no hay imagen; `artist`, `album` y
`durationMs` aceptan `null`. El exportador copia los audios mediante
`PackageAudioExporter` (incluye URI `content://` de Android) y guarda imágenes
referenciadas por rutas relativas. La importación verifica el ZIP y el manifiesto,
rechaza entradas ajenas, duplicadas, enlaces simbólicos y referencias faltantes;
extrae cada paquete en una carpeta propia de la biblioteca, registra canciones y
playlist en Drift y revierte esos cambios si falla. Los paquetes de versión 1
sin imágenes siguen siendo válidos. No se incluyen rutas originales del usuario
ni se requiere que los archivos fuente sigan presentes después de importar.

### Límites observados en la auditoría

- `LibrarySyncService.startIncremental` carga el catálogo completo mediante
  `watchAll().first` y mantiene mapas de URI y conjuntos de pistas escaneadas
  durante el escaneo. El I/O del escáner de escritorio corre en un isolate y
  la escritura se agrupa; aun así, el uso de memoria del proceso crece con el
  tamaño total de la biblioteca. Una sincronización por páginas/consultas
  puntuales requeriría rediseñar el contrato del repositorio.
- El historial no tiene poda ni paginación administrativa. Su tabla crece con
  cada inicio, aunque las listas visibles solo consultan hasta 100 pistas.
  La consulta de Recientes calcula el último evento por pista; el costo de
  refresco puede crecer con el tamaño del catálogo y del historial.
- El contador representa inicios detectados, no minutos escuchados ni
  reproducciones completas. Una repetición automática de la misma pista sin
  cambio de índice/estado puede no generar un nuevo evento de historial.
- El escaneo de escritorio construye un mapa de metadatos de todos los archivos
  conocidos y la sincronización carga otra copia del catálogo. El recorrido de
  archivos corre en un isolate, pero la comparación de cada lote ocurre en el
  isolate de UI; con bibliotecas muy grandes conviene medir pausas y memoria.
- `PlaybackPersistenceCoordinator` encadena escrituras y descarta sus errores
  en `_writeChain`; un fallo de guardado de cola puede quedar sin aviso visible.
  Esto requiere un canal de error antes de cambiar la política de persistencia.
- `LibraryController.playPlaylist` llama `markPlayed` después de
  `PlayerController.playQueue`, cuyo contrato captura errores de reproducción y
  no devuelve éxito o fracaso. Por ello `lastPlayedAt` puede actualizarse aunque
  la pista no haya comenzado; el flujo necesita un resultado explícito para
  garantizar esa semántica.

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

### Portabilidad y recuperación local

- `M3uService` analiza M3U/M3U8 UTF-8, resuelve rutas relativas al archivo
  importado y enlaza únicamente URI presentes en la biblioteca. Exporta las
  pistas en orden de playlist; el selector del sistema guarda URI absolutas
  cuando la carpeta de destino no está disponible para calcular rutas relativas.
- `LibraryBackupService` guarda las ocho tablas Drift en un archivo JSON gzip
  local con versión de formato y esquema. Restaura en una transacción, valida
  tablas, columnas y claves foráneas, y revierte si encuentra datos inválidos.
  No incluye archivos de audio ni carátulas del dispositivo.
- `MissingTracksService` verifica archivos `file:` y busca nombres normalizados
  dentro de una carpeta elegida. Actualiza URI, carpeta y disponibilidad solo
  ante una coincidencia única; conserva IDs y relaciones de playlists.
- `PortableLibrarySection` presenta las acciones en Ajustes. Antes de restaurar
  se pide confirmación; después de restaurar se invalidan explícitamente
  repositorios, listas reactivas y estado del reproductor mediante
  `reloadAfterRestore`. La conexión Drift sigue abierta.

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

En listas de Biblioteca y playlists, una pulsación prolongada inicia la selección
múltiple táctil; los siguientes toques alternan pistas y muestran acciones en
lote. En escritorio, Ctrl/Cmd alterna una pista y Shift selecciona un rango
desde el ancla; el shell usa `Shortcuts` y `Actions` para Escape, espacio,
flechas y Ctrl/Cmd+F. Las acciones de selección operan sobre modelos de dominio.

En Linux y Windows, `SystemDesktopWindowController` usa `window_manager` para
quitar el marco nativo. `DesktopWindowFrame` inserta una barra de 48 dp sobre
el shell: el área de título arrastra la ventana, doble clic alterna maximización
y los botones minimizan, maximizan/restauran o cierran. El controlador de
plataforma permite probar estos flujos sin acoplar los widgets al plugin.

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
