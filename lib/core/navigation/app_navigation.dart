import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppDestinationType {
  home,
  search,
  library,
  artists,
  albums,
  genres,
  playlist,
  queue,
  folders,
  settings,
  diagnostics,
}

@immutable
class AppDestination {
  const AppDestination._(this.type, [this.playlistId, this.name, this.artist]);

  static const home = AppDestination._(AppDestinationType.home);
  static const search = AppDestination._(AppDestinationType.search);
  static const library = AppDestination._(AppDestinationType.library);
  static const artists = AppDestination._(AppDestinationType.artists);
  static const albums = AppDestination._(AppDestinationType.albums);
  static const genres = AppDestination._(AppDestinationType.genres);
  static const queue = AppDestination._(AppDestinationType.queue);
  static const folders = AppDestination._(AppDestinationType.folders);
  static const settings = AppDestination._(AppDestinationType.settings);
  static const diagnostics = AppDestination._(AppDestinationType.diagnostics);

  factory AppDestination.playlist(int id) =>
      AppDestination._(AppDestinationType.playlist, id);
  factory AppDestination.artist(String name) =>
      AppDestination._(AppDestinationType.artists, null, name);
  factory AppDestination.album(String title, String artist) =>
      AppDestination._(AppDestinationType.albums, null, title, artist);
  factory AppDestination.genre(String name) =>
      AppDestination._(AppDestinationType.genres, null, name);
  factory AppDestination.folder(String path) =>
      AppDestination._(AppDestinationType.folders, null, path);

  final AppDestinationType type;
  final int? playlistId;
  final String? name;
  final String? artist;

  int get navigationIndex => switch (type) {
    AppDestinationType.home => 0,
    AppDestinationType.search => 1,
    AppDestinationType.library ||
    AppDestinationType.artists ||
    AppDestinationType.albums ||
    AppDestinationType.genres ||
    AppDestinationType.playlist ||
    AppDestinationType.queue ||
    AppDestinationType.folders ||
    AppDestinationType.settings => 2,
    AppDestinationType.diagnostics => 2,
  };

  @override
  bool operator ==(Object other) =>
      other is AppDestination &&
      other.type == type &&
      other.playlistId == playlistId && other.name == name && other.artist == artist;

  @override
  int get hashCode => Object.hash(type, playlistId, name, artist);
}

final appDestinationProvider = NotifierProvider<AppNavigation, AppDestination>(
  AppNavigation.new,
);

class AppNavigation extends Notifier<AppDestination> {
  final List<AppDestination> _history = [];

  @override
  AppDestination build() => AppDestination.home;

  bool get canGoBack => _history.isNotEmpty;

  void select(AppDestination destination) {
    if (destination == state) return;
    if (destination.type == AppDestinationType.playlist ||
        (destination.type == AppDestinationType.artists && destination.name != null) ||
        (destination.type == AppDestinationType.albums && destination.name != null) ||
        (destination.type == AppDestinationType.genres && destination.name != null) ||
        (destination.type == AppDestinationType.folders && destination.name != null) ||
        destination.type == AppDestinationType.queue ||
        destination.type == AppDestinationType.folders ||
        destination.type == AppDestinationType.settings ||
        destination.type == AppDestinationType.diagnostics) {
      _history.add(state);
    } else {
      _history.clear();
    }
    state = destination;
  }

  void back() {
    state = _history.isEmpty ? AppDestination.library : _history.removeLast();
  }
}
