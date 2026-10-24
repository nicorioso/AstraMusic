# Diseño de AstraMusic (referencia: Spotify oscuro + Gargantua)

## Paleta (tokens)
| Token | Hex | Uso |
|---|---|---|
| void | #050506 | Fondo base de la app |
| surface | #0F0D0C | Paneles (barra lateral, centro) |
| surface-raised | #1A1613 | Tarjetas, tiles, mini-reproductor |
| surface-hover | #241E19 | Hover y selección |
| divider | #2B231C | Separadores |
| accent (disco de acreción) | #F2A33A | Play, elemento activo, canción actual |
| accent-hover | #FFB95A | Hover del acento |
| ember | #D9531E | Degradados, detalles secundarios |
| photon | #FFE7BF | Barra de progreso, brillo del "núcleo" |
| text | #F5EBDD | Texto principal |
| text-muted | #A99B8C | Texto secundario |
| text-disabled | #6B5F54 | Deshabilitado |
| error | #E5484D | Errores |
- Contraste (cálculo propio, verificar): acento sobre void ≈ 9:1; text-muted sobre surface ≈ 7:1. Mínimo AA.
- Degradado superior del panel central: de #3D2410 (≈35% de opacidad) a transparente en los primeros ~300 dp.
- Solo tema oscuro por defecto (ThemeMode.dark). Tokens en un ThemeExtension y ColorScheme.dark (primary = accent, onPrimary = #1A0F02).
- Tipografía: Inter incluida como asset (sin descargas en ejecución), con fuente de respaldo CJK (hay títulos en japonés).

## Estructura responsive
- Ancho ≥ 840 dp: shell de escritorio. Menor: shell móvil. (Aplica también a tablets y ventanas redimensionadas.)

## Escritorio
- Barra lateral izquierda: "Tu biblioteca" con las playlists del usuario (portada o mosaico, nombre, nº de canciones), botón Crear, plegable a solo iconos (72 dp; expandida ~300 dp).
- Centro (panel redondeado 8 dp, márgenes de 8 dp): campo de búsqueda arriba; rejilla de accesos rápidos (últimas playlists escuchadas, 2 filas × hasta 4, tile de 64 dp con portada y título); debajo, tabla de canciones recientes (#, título con portada, álbum, duración; fila de 56 dp; hover; canción actual en acento con indicador).
- Barra inferior (88 dp, ancho completo): izquierda portada 56 dp + título + artista; centro aleatorio, anterior, play (círculo), siguiente, repetir, y debajo barra de progreso con tiempos; derecha SOLO volumen (icono mute + slider). Sin cola, letras, pantalla completa ni otros botones.
- Pendiente de decidir en 6A: dónde se abre la cola (propuesta: clic en la portada o título de la barra abre el panel "Reproduciendo" con la cola).

## Celular
- Inicio: accesos rápidos (2 columnas × hasta 4 filas, últimas playlists) y debajo lista de canciones recientes.
- Menú inferior de 3 elementos: Inicio, Buscar (busca en la lista de canciones), Biblioteca. Sin Premium ni Crear.
- Biblioteca: playlists del usuario con botón "+" (Crear playlist) en la cabecera, favoritos y acceso a Ajustes (carpetas de música, escanear).
- Mini-reproductor flotante sobre el menú (portada, título, artista, play); al tocarlo abre el reproductor a pantalla completa (portada grande, progreso, controles, cola).

## Componentes y comportamiento
- Portada de playlist: mosaico 2×2 de las primeras 4 portadas distintas; si no hay, degradado con nota musical en acento.
- Play, canción actual y elementos activos en acento; aleatorio y repetir activos en acento con punto indicador.
- Barra de progreso: photon (blanco cálido), acento al pasar el ratón.
- Animaciones suaves (150-200 ms), sin efectos pesados. Áreas táctiles ≥ 48 dp, foco visible con teclado en escritorio, tooltips.