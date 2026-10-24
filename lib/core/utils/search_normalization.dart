import 'package:diacritic/diacritic.dart';

final RegExp _collapsedWhitespace = RegExp(r'\s+');

String normalizeForSearch(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  return removeDiacritics(trimmed.toLowerCase())
      .replaceAll(_collapsedWhitespace, ' ');
}

String buildTrackSearchText({
  required String title,
  String? artist,
  String? album,
}) {
  return normalizeForSearch([title, ?artist, ?album].join(' '));
}
