import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppDestination { home, search, library }

final appDestinationProvider = NotifierProvider<AppNavigation, AppDestination>(
  AppNavigation.new,
);

class AppNavigation extends Notifier<AppDestination> {
  @override
  AppDestination build() => AppDestination.home;

  void select(AppDestination destination) => state = destination;
}
