import 'dart:collection';
import 'dart:math';

final class ManualQueueOrder<T> {
  ManualQueueOrder(Iterable<T> items, {Random? random})
    : _random = random ?? Random() {
    final entries = items.map(_QueueEntry<T>.new).toList();
    _original.addAll(entries);
    _playback.addAll(entries);
  }

  final Random _random;
  final List<_QueueEntry<T>> _original = [];
  final List<_QueueEntry<T>> _playback = [];
  bool _shuffleEnabled = false;

  bool get shuffleEnabled => _shuffleEnabled;
  int get length => _playback.length;
  bool get isEmpty => _playback.isEmpty;

  List<T> get original =>
      UnmodifiableListView(_original.map((entry) => entry.item));

  List<T> get playback =>
      UnmodifiableListView(_playback.map((entry) => entry.item));

  T operator [](int index) => _playback[index].item;

  int setShuffle({required bool enabled, required int currentIndex}) {
    if (_playback.isEmpty) return 0;
    final safeCurrentIndex = currentIndex.clamp(0, _playback.length - 1);
    final current = _playback[safeCurrentIndex];
    if (enabled == _shuffleEnabled) return safeCurrentIndex;

    _shuffleEnabled = enabled;
    if (enabled) {
      final remainder = _original.where((entry) => entry != current).toList()
        ..shuffle(_random);
      _playback
        ..clear()
        ..add(current)
        ..addAll(remainder);
      return 0;
    }

    _playback
      ..clear()
      ..addAll(_original);
    return _playback.indexOf(current);
  }

  void add(T item) {
    final entry = _QueueEntry(item);
    _original.add(entry);
    _playback.add(entry);
  }

  void addAll(Iterable<T> items) {
    for (final item in items) {
      add(item);
    }
  }

  void insertNext({required int currentIndex, required T item}) {
    final insertionIndex = (currentIndex + 1).clamp(0, _playback.length);
    insertAt(insertionIndex, item);
  }

  void insertAt(int playbackIndex, T item) {
    final safeIndex = playbackIndex.clamp(0, _playback.length);
    final entry = _QueueEntry(item);

    if (_playback.isEmpty) {
      _playback.add(entry);
      _original.add(entry);
      return;
    }

    final originalIndex = safeIndex == 0
        ? _original.indexOf(_playback.first)
        : _original.indexOf(_playback[safeIndex - 1]) + 1;
    _playback.insert(safeIndex, entry);
    _original.insert(originalIndex.clamp(0, _original.length), entry);
  }

  T removeAt(int playbackIndex) {
    final entry = _playback.removeAt(playbackIndex);
    _original.remove(entry);
    return entry.item;
  }

  void move(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final entry = _playback.removeAt(oldIndex);
    _playback.insert(newIndex, entry);
    if (!_shuffleEnabled) {
      _original
        ..clear()
        ..addAll(_playback);
    }
  }

  int indexWhere(bool Function(T item) predicate) {
    return _playback.indexWhere((entry) => predicate(entry.item));
  }

  void replaceAt(int playbackIndex, T item) {
    final entry = _playback[playbackIndex];
    entry.item = item;
  }

  void clear() {
    _original.clear();
    _playback.clear();
    _shuffleEnabled = false;
  }
}

final class _QueueEntry<T> {
  _QueueEntry(this.item);

  T item;
}
