import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:astramusic/features/player/presentation/player_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryViewState>(
      LibraryController.new,
    );

class LibraryViewState {
  const LibraryViewState({this.isBusy = false, this.message});

  final bool isBusy;
  final String? message;

  LibraryViewState copyWith({bool? isBusy, Object? message = _notProvided}) {
    return LibraryViewState(
      isBusy: isBusy ?? this.isBusy,
      message: message == _notProvided ? this.message : message as String?,
    );
  }

  static const _notProvided = Object();
}

final class LibraryController extends Notifier<LibraryViewState> {
  @override
  LibraryViewState build() => const LibraryViewState();

  Future<void> addFiles() async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, message: null);

    try {
      final files = await ref.read(audioFilePickerProvider).pickAudioFiles();
      if (files.isEmpty || !ref.mounted) return;

      final addedAt = DateTime.now();
      final tracks = files
          .map(
            (file) =>
                Track(uri: file.path, title: file.title, dateAdded: addedAt),
          )
          .toList(growable: false);
      await ref.read(trackRepositoryProvider).upsertAll(tracks);
    } catch (error) {
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
    } finally {
      if (ref.mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> playTrack(Track track) async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, message: null);

    try {
      final service = ref.read(audioPlayerServiceProvider);
      await service.loadFile(path: track.uri, title: track.title);
      await service.play();
    } catch (error) {
      if (!ref.mounted) return;
      await ref.read(trackRepositoryProvider).markUnavailable({track.uri});
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
    } finally {
      if (ref.mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> loadDebugTracks() async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, message: null);

    try {
      final addedAt = DateTime.now();
      final tracks = List.generate(
        50,
        (index) => Track(
          uri: 'file:///astramusic-debug/track-${index + 1}.mp3',
          title: 'Canción de prueba ${index + 1}',
          artist: 'Artista ${(index % 10) + 1}',
          album: 'Álbum ${(index % 5) + 1}',
          duration: Duration(seconds: 120 + index),
          dateAdded: addedAt,
        ),
      );
      await ref.read(trackRepositoryProvider).upsertAll(tracks);
    } catch (error) {
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
    } finally {
      if (ref.mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> deleteAll() async {
    if (state.isBusy) return;
    state = state.copyWith(isBusy: true, message: null);

    try {
      await ref.read(trackRepositoryProvider).deleteAll();
    } catch (error) {
      if (ref.mounted) state = state.copyWith(message: _messageFor(error));
    } finally {
      if (ref.mounted) state = state.copyWith(isBusy: false);
    }
  }

  void clearMessage() {
    if (state.message != null) state = state.copyWith(message: null);
  }

  String _messageFor(Object error) {
    final message = error.toString();
    return message.isEmpty ? 'Ocurrió un error inesperado.' : message;
  }
}
