import 'dart:async';

import 'package:astramusic/core/navigation/app_navigation.dart';
import 'package:astramusic/core/platform/audio_download_backend.dart';
import 'package:astramusic/core/platform/youtube_download_utils.dart';
import 'package:astramusic/core/theme/astra_colors.dart';
import 'package:astramusic/features/library/application/audio_download_controller.dart';
import 'package:astramusic/features/library/application/audio_download_service.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AudioDownloadScreen extends ConsumerStatefulWidget {
  const AudioDownloadScreen({super.key});

  @override
  ConsumerState<AudioDownloadScreen> createState() =>
      _AudioDownloadScreenState();
}

class _AudioDownloadScreenState extends ConsumerState<AudioDownloadScreen> {
  final _url = TextEditingController();
  String? _analyzedUrl;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref
              .read(audioDownloadControllerProvider.notifier)
              .refreshAvailability(),
        );
      }
    });
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    setState(() {
      _url.text = data!.text!.trim();
      _analyzedUrl = null;
      _inputError = null;
    });
  }

  Future<void> _analyze() async {
    final url = _url.text.trim();
    if (YoutubeUrl.parse(url) == null) {
      setState(() => _inputError = 'Ingresa una URL válida de YouTube.');
      return;
    }
    setState(() {
      _inputError = null;
      _analyzedUrl = null;
    });
    await ref.read(audioDownloadControllerProvider.notifier).analyze(url);
    if (!mounted || _url.text.trim() != url) return;
    if (ref.read(audioDownloadControllerProvider).preview != null) {
      setState(() => _analyzedUrl = url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.astraColors;
    final main = ref.watch(
      audioDownloadControllerProvider.select(
        (value) => (
          availability: value.availability,
          preview: value.preview,
          status: value.status,
          error: value.error,
          result: value.result,
          isBusy: value.isBusy,
        ),
      ),
    );
    final available = main.availability?.available == true;
    final preview = _analyzedUrl == _url.text.trim() ? main.preview : null;
    final playlist = YoutubeUrl.parse(_url.text)?.isPlaylist == true;
    final onlyPlaylist = YoutubeUrl.parse(_url.text)?.uri.path == '/playlist';
    final result = main.result;
    final busy = main.isBusy;

    return Material(
      color: colors.surface,
      child: Column(
        key: const Key('audio-download-screen'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
            child: Row(
              children: [
                IconButton(
                  key: const Key('download-back-button'),
                  tooltip: 'Volver a Biblioteca',
                  onPressed: ref.read(appDestinationProvider.notifier).back,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    'Descargar audio',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  'Importa una pista de YouTube a tu biblioteca local.',
                  style: TextStyle(color: colors.textMuted),
                ),
                const SizedBox(height: 16),
                if (main.availability == null)
                  const Text('Comprobando yt-dlp y FFmpeg…')
                else if (!available)
                  _Notice(
                    key: const Key('download-unavailable'),
                    icon: Icons.info_outline,
                    message:
                        main.availability!.error ??
                        'Descargas no disponibles en este dispositivo.',
                  ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('download-url-field'),
                  controller: _url,
                  enabled: !busy,
                  keyboardType: TextInputType.url,
                  onChanged: (_) => setState(() {
                    _analyzedUrl = null;
                    _inputError = null;
                  }),
                  decoration: InputDecoration(
                    labelText: 'URL de YouTube',
                    hintText: 'https://www.youtube.com/watch?v=…',
                    errorText: _inputError,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: const Key('download-paste-button'),
                          tooltip: 'Pegar URL',
                          onPressed: busy ? null : _paste,
                          icon: const Icon(Icons.content_paste),
                        ),
                        IconButton(
                          key: const Key('download-clear-button'),
                          tooltip: 'Limpiar URL',
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                  _url.clear();
                                  _analyzedUrl = null;
                                  _inputError = null;
                                }),
                          icon: const Icon(Icons.clear),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    key: const Key('download-analyze-button'),
                    onPressed: available && !busy ? _analyze : null,
                    icon: const Icon(Icons.search),
                    label: const Text('Analizar'),
                  ),
                ),
                if (preview != null) ...[
                  const SizedBox(height: 20),
                  _PreviewCard(preview: preview),
                  if (playlist) ...[
                    const SizedBox(height: 12),
                    const _Notice(
                      key: Key('download-playlist-notice'),
                      icon: Icons.playlist_play,
                      message: 'Esta versión descargará únicamente la pista individual. Las playlists llegarán después.',
                    ),
                  ],
                  if (onlyPlaylist) ...[
                    const SizedBox(height: 8),
                    const _Notice(
                      icon: Icons.info_outline,
                      message: 'Abre un video de esa playlist y pega su enlace para descargar una pista.',
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      key: const Key('download-start-button'),
                      onPressed: available && !busy && !onlyPlaylist
                          ? () => unawaited(
                              ref
                                  .read(
                                    audioDownloadControllerProvider.notifier,
                                  )
                                  .start(_analyzedUrl!),
                            )
                          : null,
                      icon: const Icon(Icons.download),
                      label: const Text('Descargar'),
                    ),
                  ),
                ],
                if (busy || main.status != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _statusText(main.status),
                    key: const Key('download-status'),
                    style: TextStyle(color: colors.text),
                  ),
                  if (busy) ...[
                    const SizedBox(height: 8),
                    const _DownloadProgress(),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('download-cancel-button'),
                        onPressed: () => unawaited(
                          ref
                              .read(audioDownloadControllerProvider.notifier)
                              .cancel(),
                        ),
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'),
                      ),
                    ),
                  ],
                ],
                if (main.error != null &&
                    (available || main.availability == null)) ...[
                  const SizedBox(height: 12),
                  _Notice(
                    key: const Key('download-error'),
                    icon: Icons.error_outline,
                    message: main.error!,
                  ),
                ],
                if (result != null &&
                    result.status != AudioImportStatus.canceled) ...[
                  const SizedBox(height: 12),
                  _Notice(
                    key: const Key('download-result'),
                    icon: result.status == AudioImportStatus.duplicate
                        ? Icons.info_outline
                        : Icons.check_circle_outline,
                    message: result.status == AudioImportStatus.duplicate
                        ? 'Esta pista ya está en tu biblioteca. Se conservaron tus cambios.'
                        : 'La pista se añadió a tu biblioteca.',
                  ),
                  if (result.track != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('download-play-button'),
                        onPressed: () => unawaited(
                          ref.read(playerControllerProvider.notifier).playQueue(
                            [result.track!],
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Reproducir pista'),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});
  final SourcePreview preview;

  @override
  Widget build(BuildContext context) {
    final colors = context.astraColors;
    final thumbnail = preview.thumbnailUrl;
    return Container(
      key: const Key('download-preview'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: thumbnail == null
                ? Icon(Icons.music_note, color: colors.accent)
                : Image.network(
                    thumbnail,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Icon(Icons.music_note, color: colors.accent),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  preview.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textMuted),
                ),
                if (preview.duration != null)
                  Text(
                    _duration(preview.duration!),
                    style: TextStyle(color: colors.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadProgress extends ConsumerWidget {
  const _DownloadProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(
      audioDownloadControllerProvider.select(
        (value) => (bytes: value.downloadedBytes, total: value.totalBytes),
      ),
    );
    final total = progress.total;
    final ratio = total == null || total <= 0
        ? 0.0
        : ((progress.bytes ?? 0) / total).clamp(0.0, 1.0);
    final colors = context.astraColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          key: const Key('download-progress'),
          value: ratio,
          backgroundColor: colors.surfaceHover,
          color: colors.photon,
        ),
        if (total != null && total > 0)
          Text(
            '${(ratio * 100).round()} %',
            style: TextStyle(color: colors.textMuted),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message, super.key});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.astraColors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: colors.text)),
          ),
        ],
      ),
    );
  }
}

String _duration(Duration duration) {
  final seconds = duration.inSeconds;
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return '$minutes:${remaining.toString().padLeft(2, '0')}';
}

String _statusText(DownloadStatus? status) => switch (status) {
  DownloadStatus.analyzing => 'Analizando URL…',
  DownloadStatus.downloading => 'Descargando audio…',
  DownloadStatus.processing => 'Procesando audio…',
  DownloadStatus.registering => 'Registrando en la biblioteca…',
  DownloadStatus.completed => 'Terminado',
  DownloadStatus.failed => 'Fallido',
  DownloadStatus.canceled => 'Cancelado',
  null => '',
};
