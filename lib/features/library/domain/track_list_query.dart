enum TrackSort { title, dateAdded, artist, year, duration }

class TrackListQuery {
  const TrackListQuery({
    this.search = '',
    this.favoritesOnly = false,
    this.availableOnly = false,
    this.sort = TrackSort.title,
  });

  final String search;
  final bool favoritesOnly;
  final bool availableOnly;
  final TrackSort sort;

  TrackListQuery copyWith({bool? favoritesOnly, bool? availableOnly, TrackSort? sort}) => TrackListQuery(
    search: search, favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    availableOnly: availableOnly ?? this.availableOnly, sort: sort ?? this.sort,
  );
}
