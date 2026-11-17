class YoutubeUrl {
  const YoutubeUrl._(this.uri, this.isPlaylist);
  final Uri uri;
  final bool isPlaylist;

  static YoutubeUrl? parse(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return null;
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (host != 'youtu.be' &&
        host != 'youtube.com' &&
        !host.endsWith('.youtube.com')) {
      return null;
    }
    if (uri.userInfo.isNotEmpty || uri.pathSegments.isEmpty) return null;
    final list = uri.queryParameters['list'];
    final playlist =
        (list != null && list.isNotEmpty) || uri.path == '/playlist';
    if (uri.path == '/playlist' && (list == null || list.isEmpty)) return null;
    if (host == 'youtu.be' && uri.pathSegments.first.isEmpty) return null;
    if (uri.path == '/watch' &&
        (uri.queryParameters['v']?.isEmpty ?? true) &&
        !playlist) {
      return null;
    }
    return YoutubeUrl._(uri, playlist);
  }
}

String friendlyDownloadError(String detail) {
  final lines = detail.split(RegExp(r'\r?\n')).map((line) => line.trim().replaceFirst(RegExp(r'^(Bad state:|StateError:)\s*', caseSensitive: false), '')).toList();
  final errors = lines.where((line) => line.startsWith(RegExp(r'ERROR:', caseSensitive: false))).toList();
  final relevant = errors.isNotEmpty ? errors : lines.where((line) =>
      !line.startsWith(RegExp(r'WARNING:', caseSensitive: false))).toList();
  final diagnostic = relevant.isEmpty ? 'yt-dlp no informó un error específico.' : relevant.take(3).join(' ');
  final lower = diagnostic.toLowerCase();
  if ([
    'unknownhostexception',
    'connectexception',
    'sockettimeoutexception',
    'noroutetohostexception',
    'failed to resolve',
    'name or service not known',
    'temporary failure in name resolution',
    'socket closed',
  ].any(lower.contains)) {
    return 'Sin conexión a internet. Comprueba tu conexión e inténtalo de nuevo.';
  }
  if ([
    'private video',
    'video unavailable',
    'not available',
    'age-restricted',
    'geo restricted',
  ].any(lower.contains)) {
    return 'El video no está disponible o tiene una restricción de acceso.';
  }
  if ([
    'permission',
    'access is denied',
    'no space left',
    'disk full',
  ].any(lower.contains)) {
    return 'No se puede escribir en la carpeta temporal o no hay espacio suficiente.';
  }
  final clean = diagnostic.replaceAll(RegExp(r'\s+'), ' ').trim();
  return clean.isEmpty
      ? 'Ocurrió un error inesperado.'
      : clean.substring(0, clean.length.clamp(0, 180));
}
