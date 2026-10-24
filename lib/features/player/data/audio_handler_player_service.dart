import 'dart:async';
import 'dart:io';

import 'package:astramusic/core/platform/audio_player_service.dart';
import 'package:astramusic/core/platform/artwork_provider.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/player/data/astra_audio_handler.dart';
import 'package:astramusic/features/player/data/serial_command_queue.dart';
import 'package:audio_service/audio_service.dart';

final class AudioHandlerPlayerService implements AudioPlayerService {
  AudioHandlerPlayerService(this._handler, {ArtworkProvider? artworkProvider})
    : _artworkProvider = artworkProvider {
    if (artworkProvider != null) {
      _handler.mediaItem.listen((item) {
        if (item != null && item.artUri == null) {
          unawaited(_attachArtwork(item));
        }
      });
    }
  }

  final AstraAudioHandler _handler;
  final ArtworkProvider? _artworkProvider;
  final SerialCommandQueue _commands = SerialCommandQueue();

  @override
  Stream<AudioPlaybackState> get playbackStateStream =>
      _handler.playbackState.map(_toPlaybackState).distinct(_sameState);

  @override
  Stream<Duration> get positionStream => _handler.positionStream;

  @override
  Stream<Duration?> get durationStream => _handler.durationStream;

  @override
  Stream<AudioItem?> get currentItemStream => _handler.mediaItem.map(
    (item) => item == null ? null : _toAudioItem(item),
  );

  @override
  Stream<List<Track>> get queueStream =>
      _handler.queue.map((items) => List.unmodifiable(items.map(_toTrack)));

  @override
  Stream<int?> get currentIndexStream =>
      _handler.playbackState.map((state) => state.queueIndex).distinct();

  @override
  Stream<bool> get shuffleEnabledStream => _handler.playbackState
      .map((state) => state.shuffleMode == AudioServiceShuffleMode.all)
      .distinct();

  @override
  Stream<RepeatMode> get repeatModeStream =>
      _handler.playbackState.map(_toRepeatMode).distinct();

  @override
  Stream<AudioPlaybackFailure> get failureStream => _handler.failureStream.map(
    (failure) => AudioPlaybackFailure(
      track: _toTrack(failure.item),
      message: failure.message,
    ),
  );

  @override
  Future<void> loadFile({required String path, required String title}) {
    return _commands.run(
      () => _playQueue([
        Track(uri: path, title: title, dateAdded: DateTime.now()),
      ]),
    );
  }

  @override
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) {
    return _commands.run(() => _playQueue(tracks, startIndex: startIndex));
  }

  Future<void> _playQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (startIndex < 0 || (tracks.isNotEmpty && startIndex >= tracks.length)) {
      throw RangeError.index(startIndex, tracks, 'startIndex');
    }
    final requestedTrack = tracks.isEmpty ? null : tracks[startIndex];
    final available = tracks.where((track) => track.isAvailable).toList();
    if (available.isEmpty) {
      await _handler.updateQueue(const []);
      throw const AudioPlayerException(
        'No hay canciones disponibles para reproducir.',
      );
    }
    final availableStartIndex = requestedTrack == null
        ? 0
        : available.indexWhere((track) => track.uri == requestedTrack.uri);
    await _handler.loadQueue(
      available.map(_toMediaItem).toList(growable: false),
      startIndex: availableStartIndex < 0 ? 0 : availableStartIndex,
    );
  }

  @override
  Future<void> play() => _commands.run(_handler.play);

  @override
  Future<void> pause() => _commands.run(_handler.pause);

  @override
  Future<void> stop() => _commands.run(_handler.stop);

  @override
  Future<void> seek(Duration position) => _handler.seek(position);

  @override
  Future<void> next() => _commands.run(_handler.skipToNext);

  @override
  Future<void> previous() => _commands.run(_handler.skipToPrevious);

  @override
  Future<void> skipToIndex(int index) =>
      _commands.run(() => _handler.skipToQueueItem(index));

  @override
  Future<void> setShuffle(bool enabled) => _commands.run(
    () => _handler.setShuffleMode(
      enabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    ),
  );

  @override
  Future<void> setRepeatMode(RepeatMode mode) => _commands.run(
    () => _handler.setRepeatMode(switch (mode) {
      RepeatMode.off => AudioServiceRepeatMode.none,
      RepeatMode.all => AudioServiceRepeatMode.all,
      RepeatMode.one => AudioServiceRepeatMode.one,
    }),
  );

  @override
  Future<void> addToQueue(Track track) async {
    if (!track.isAvailable) return;
    await _commands.run(() => _handler.addQueueItem(_toMediaItem(track)));
  }

  @override
  Future<void> playNext(Track track) async {
    if (!track.isAvailable) return;
    await _commands.run(() async {
      final currentIndex = _handler.playbackState.value.queueIndex ?? -1;
      await _handler.insertQueueItem(currentIndex + 1, _toMediaItem(track));
    });
  }

  @override
  Future<void> removeFromQueue(int index) =>
      _commands.run(() => _handler.removeQueueItemAt(index));

  @override
  Future<void> moveInQueue(int oldIndex, int newIndex) =>
      _commands.run(() => _handler.moveQueueItem(oldIndex, newIndex));

  @override
  Future<void> clearQueue() =>
      _commands.run(() => _handler.updateQueue(const []));

  MediaItem _toMediaItem(Track track) => MediaItem(
    id: track.uri,
    title: track.title,
    artist: track.artist,
    duration: track.duration,
    extras: {
      'trackId': track.id,
      'album': track.album,
      'trackNumber': track.trackNumber,
      'year': track.year,
      'fileSize': track.fileSize,
      'dateAddedMs': track.dateAdded.millisecondsSinceEpoch,
      'isFavorite': track.isFavorite,
      'artworkPath': track.artworkPath,
    },
    artUri: _existingArtworkUri(track.artworkPath),
  );

  Track _toTrack(MediaItem item) {
    final extras = item.extras ?? const <String, dynamic>{};
    return Track(
      id: extras['trackId'] as int?,
      uri: item.id,
      title: item.title,
      artist: item.artist,
      album: extras['album'] as String?,
      duration: item.duration,
      trackNumber: extras['trackNumber'] as int?,
      year: extras['year'] as int?,
      fileSize: extras['fileSize'] as int?,
      dateAdded: switch (extras['dateAddedMs']) {
        final int milliseconds => DateTime.fromMillisecondsSinceEpoch(
          milliseconds,
        ),
        _ => DateTime.fromMillisecondsSinceEpoch(0),
      },
      isFavorite: extras['isFavorite'] as bool? ?? false,
      artworkPath: extras['artworkPath'] as String?,
    );
  }

  AudioItem _toAudioItem(MediaItem item) => AudioItem(
    path: item.id,
    title: item.title,
    artist: item.artist,
    duration: item.duration,
    trackId: item.extras?['trackId'] as int?,
    artworkPath: item.extras?['artworkPath'] as String?,
  );

  Uri? _existingArtworkUri(String? artworkPath) {
    if (artworkPath == null) return null;
    final file = File(artworkPath);
    return file.existsSync() ? Uri.file(file.path) : null;
  }

  Future<void> _attachArtwork(MediaItem item) async {
    final provider = _artworkProvider;
    if (provider == null) return;
    final artworkPath = await provider.artworkFor(_toTrack(item), size: 512);
    if (artworkPath == null || !File(artworkPath).existsSync()) return;
    final updatedExtras = Map<String, dynamic>.of(item.extras ?? const {})
      ..['artworkPath'] = artworkPath;
    await _handler.updateMediaItem(
      item.copyWith(artUri: Uri.file(artworkPath), extras: updatedExtras),
    );
  }

  AudioPlaybackState _toPlaybackState(PlaybackState state) {
    final status = switch (state.processingState) {
      AudioProcessingState.loading ||
      AudioProcessingState.buffering => AudioPlaybackStatus.loading,
      AudioProcessingState.completed => AudioPlaybackStatus.completed,
      AudioProcessingState.error => AudioPlaybackStatus.error,
      AudioProcessingState.idle || AudioProcessingState.ready =>
        state.playing
            ? AudioPlaybackStatus.playing
            : AudioPlaybackStatus.paused,
    };

    return AudioPlaybackState(status, errorMessage: state.errorMessage);
  }

  RepeatMode _toRepeatMode(PlaybackState state) => switch (state.repeatMode) {
    AudioServiceRepeatMode.none => RepeatMode.off,
    AudioServiceRepeatMode.one => RepeatMode.one,
    AudioServiceRepeatMode.all ||
    AudioServiceRepeatMode.group => RepeatMode.all,
  };

  bool _sameState(AudioPlaybackState previous, AudioPlaybackState next) =>
      previous.status == next.status &&
      previous.errorMessage == next.errorMessage;
}
