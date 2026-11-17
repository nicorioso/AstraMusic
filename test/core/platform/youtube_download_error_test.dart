import 'package:astramusic/core/platform/youtube_download_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('solo fallos genuinos de red se clasifican como desconexión', () {
    for (final detail in ['HTTP Error 403', 'FFmpeg failed: conversion error', 'YoutubeDLException: unexpected failure']) {
      expect(friendlyDownloadError(detail), isNot(contains('Sin conexión')));
    }
    for (final detail in ['UnknownHostException', 'ConnectException', 'SocketTimeoutException', 'NoRouteToHostException', 'socket closed', 'Failed to resolve host']) {
      expect(friendlyDownloadError(detail), contains('Sin conexión'));
    }
  });
}
