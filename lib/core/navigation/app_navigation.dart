import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppDestinationType {
  home,
  search,
  library,
  playlist,
  queue,
  folders,
  settings,
}

@immutable
class AppDestination {
  const AppDestination._(this.type, [this.playlistId]);

  static const home = AppDestination._(AppDestinationType.home);
  static const search = AppDestination._(AppDestinationType.search);
  static const library = AppDestination._(AppDestinationType.library);
  static const queue = AppDestination._(AppDestinationType.queue);
  static const folders = AppDestination._(AppDestinationType.folders);
  static const settings = AppDestination._(AppDestinationType.settings);

  factory AppDestination.playlist(int id) =>
      AppDestination._(AppDestinationType.playlist, id);

  final AppDestinationType type;
  final int? playlistId;

  int get navigationIndex => switch (type) {
    AppDestinationType.home => 0,
    AppDestinationType.search => 1,
    AppDestinationType.library ||
    AppDestinationType.playlist ||
    AppDestinationType.queue ||
    AppDestinationType.folders ||
    AppDestinationType.settings => 2,
  };

  @override
  bool operator ==(Object other) =>
      other is AppDestination &&
      other.type == type &&
      other.playlistId == playlistId;

  @override
  int get hashCode => Object.hash(type, playlistId);
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
        destination.type == AppDestinationType.queue ||
        destination.type == AppDestinationType.folders ||
        destination.type == AppDestinationType.settings) {
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
