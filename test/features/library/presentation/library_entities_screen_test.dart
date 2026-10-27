import 'package:astramusic/core/navigation/app_navigation.dart';
import 'package:astramusic/features/library/domain/library_group.dart';
import 'package:astramusic/features/library/domain/library_grouping_repository.dart';
import 'package:astramusic/features/library/domain/track.dart';
import 'package:astramusic/features/library/presentation/library_entities_screen.dart';
import 'package:astramusic/features/library/presentation/library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra artistas y abre su detalle', (tester) async {
    final container = ProviderContainer(
      overrides: [
        libraryGroupingRepositoryProvider.overrideWithValue(const _Groups()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ArtistsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Aurora'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('artist-Aurora')));
    expect(
      container.read(appDestinationProvider),
      AppDestination.artist('Aurora'),
    );
  });

  testWidgets('el detalle de álbum conserva el orden de pista', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryGroupingRepositoryProvider.overrideWithValue(const _Groups()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AlbumsScreen(title: 'Luz', artist: 'Aurora'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = tester.widget<ListTile>(find.byType(ListTile).first);
    expect((first.title! as Text).data, 'Primera');
  });

  testWidgets('el detalle de artista permite volver a la biblioteca', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        libraryGroupingRepositoryProvider.overrideWithValue(const _Groups()),
      ],
    );
    addTearDown(container.dispose);
    container.read(appDestinationProvider);
    container
        .read(appDestinationProvider.notifier)
        .select(AppDestination.artists);
    container
        .read(appDestinationProvider.notifier)
        .select(AppDestination.artist('Aurora'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ArtistsScreen(artist: 'Aurora')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('library-entity-back-button')));
    expect(container.read(appDestinationProvider), AppDestination.artists);
  });
}

final class _Groups implements LibraryGroupingRepository {
  const _Groups();
  @override
  Stream<List<ArtistGroup>> watchArtists() => Stream.value(const [
    ArtistGroup(name: 'Aurora', trackCount: 2, albumCount: 1),
  ]);
  @override
  Stream<List<AlbumGroup>> watchAlbums() => Stream.value(const [
    AlbumGroup(title: 'Luz', artist: 'Aurora', trackCount: 2),
  ]);
  @override
  Stream<List<GenreGroup>> watchGenres() => Stream.value(const []);
  @override
  Stream<List<FolderGroup>> watchFolders() => Stream.value(const []);
  @override
  Stream<List<Track>> watchArtistTracks(String artist) =>
      watchAlbumTracks(title: 'Luz', artist: artist);
  @override
  Stream<List<Track>> watchAlbumTracks({
    required String title,
    required String artist,
  }) => Stream.value([
    Track(
      uri: 'file:///1',
      title: 'Primera',
      trackNumber: 1,
      dateAdded: DateTime(2026),
    ),
    Track(
      uri: 'file:///2',
      title: 'Segunda',
      trackNumber: 2,
      dateAdded: DateTime(2026),
    ),
  ]);
  @override
  Stream<List<Track>> watchGenreTracks(String genre) => Stream.value(const []);
  @override
  Stream<List<Track>> watchFolderTracks(String path) => Stream.value(const []);
}
