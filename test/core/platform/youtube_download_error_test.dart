import 'package:astramusic/core/platform/youtube_download_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prioriza ERROR sobre WARNING y descarta avisos sin fallo', () {
    const warning = 'WARNING: Your yt-dlp version is older than 90 days!';
    expect(friendlyDownloadError('$warning\nERROR: HTTP Error 403'), contains('HTTP Error 403'));
    expect(friendlyDownloadError('$warning\nERROR: ffmpeg failed'), contains('ffmpeg failed'));
    expect(friendlyDownloadError('$warning\nDescarga completada'), isNot(contains('WARNING')));
  });
  test('solo fallos genuinos de red se clasifican como desconexión', () {
    for (final detail in ['HTTP Error 403', 'FFmpeg failed: conversion error', 'YoutubeDLException: unexpected failure']) {
      expect(friendlyDownloadError(detail), isNot(contains('Sin conexión')));
    }
    for (final detail in ['UnknownHostException', 'ConnectException', 'SocketTimeoutException', 'NoRouteToHostException', 'socket closed', 'Failed to resolve host']) {
      expect(friendlyDownloadError(detail), contains('Sin conexión'));
    }
  });
}

