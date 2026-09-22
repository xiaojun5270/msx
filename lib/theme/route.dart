import 'theme.dart';

/// Navigation destination — mirrors Swift `enum Route`.
/// Implemented as a sealed class hierarchy with value equality so it can key
/// a Navigator page stack.
sealed class AppRoute {
  const AppRoute();
  String get heroId;
}

class PlaylistRoute extends AppRoute {
  final String platform;
  final String id;
  final ListKind kind;
  final bool fromLibrary;
  const PlaylistRoute({required this.platform, required this.id, required this.kind, required this.fromLibrary});
  @override
  String get heroId => 'playlist:$platform:$id:${kind.name}';
  @override
  bool operator ==(Object o) =>
      o is PlaylistRoute && o.platform == platform && o.id == id && o.kind == kind && o.fromLibrary == fromLibrary;
  @override
  int get hashCode => Object.hash(platform, id, kind, fromLibrary);
}

class AlbumRoute extends AppRoute {
  final String platform;
  final String id;
  const AlbumRoute({required this.platform, required this.id});
  @override
  String get heroId => 'album:$platform:$id';
  @override
  bool operator ==(Object o) => o is AlbumRoute && o.platform == platform && o.id == id;
  @override
  int get hashCode => Object.hash(platform, id);
}

class ArtistRoute extends AppRoute {
  final String platform;
  final String id;
  const ArtistRoute({required this.platform, required this.id});
  @override
  String get heroId => 'artist:$platform:$id';
  @override
  bool operator ==(Object o) => o is ArtistRoute && o.platform == platform && o.id == id;
  @override
  int get hashCode => Object.hash(platform, id);
}

class GenreRoute extends AppRoute {
  final String platform;
  final String id;
  const GenreRoute({required this.platform, required this.id});
  @override
  String get heroId => 'genre:$platform:$id';
  @override
  bool operator ==(Object o) => o is GenreRoute && o.platform == platform && o.id == id;
  @override
  int get hashCode => Object.hash(platform, id);
}

class LibrarySectionRoute extends AppRoute {
  final LibrarySection section;
  const LibrarySectionRoute(this.section);
  @override
  String get heroId => 'library:${section.name}';
  @override
  bool operator ==(Object o) => o is LibrarySectionRoute && o.section == section;
  @override
  int get hashCode => section.hashCode;
}

class LocalFolderRoute extends AppRoute {
  final String path;
  const LocalFolderRoute(this.path);
  @override
  String get heroId => 'files:$path';
  @override
  bool operator ==(Object o) => o is LocalFolderRoute && o.path == path;
  @override
  int get hashCode => path.hashCode;
}

class SubscriptionDetailRoute extends AppRoute {
  final String id;
  const SubscriptionDetailRoute(this.id);
  @override
  String get heroId => 'subscription:$id';
  @override
  bool operator ==(Object o) => o is SubscriptionDetailRoute && o.id == id;
  @override
  int get hashCode => id.hashCode;
}

class SettingsPlatformRoute extends AppRoute {
  final String id;
  const SettingsPlatformRoute(this.id);
  @override
  String get heroId => 'settings-platform:$id';
  @override
  bool operator ==(Object o) => o is SettingsPlatformRoute && o.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// Simple singleton routes.
class SimpleRoute extends AppRoute {
  final String name;
  const SimpleRoute(this.name);
  @override
  String get heroId => name;
  @override
  bool operator ==(Object o) => o is SimpleRoute && o.name == name;
  @override
  int get hashCode => name.hashCode;

  static const daily = SimpleRoute('daily');
  static const explorePlaylists = SimpleRoute('explore-playlists');
  static const exploreAlbums = SimpleRoute('explore-albums');
  static const genres = SimpleRoute('genres');
  static const favorites = SimpleRoute('favorites');
  static const localFiles = SimpleRoute('files');
  static const ingestRecords = SimpleRoute('ingest-records');
  static const subscriptions = SimpleRoute('subscriptions');
  static const serverLogs = SimpleRoute('server-logs');
  static const clientLogs = SimpleRoute('client-logs');
  static const account = SimpleRoute('account');
  static const settings = SimpleRoute('settings');
  static const settingsProfile = SimpleRoute('settings-profile');
  static const settingsAutomation = SimpleRoute('settings-automation');
  static const settingsSources = SimpleRoute('settings-sources');
}
