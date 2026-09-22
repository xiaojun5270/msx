import 'package:flutter/material.dart';

import '../theme/route.dart';
import 'account_view.dart';
import 'detail_views.dart';
import 'explore_views.dart';
import 'ingest_records_view.dart';
import 'library_view.dart';
import 'local_files_view.dart';
import 'logs_view.dart';
import 'placeholders.dart';
import 'settings_views.dart';
import 'source_organization_view.dart';
import 'subscriptions_view.dart';

/// Maps an [AppRoute] to its destination widget. Mirrors Swift `RoutePage`.
class RoutePage extends StatelessWidget {
  final AppRoute route;
  const RoutePage({super.key, required this.route});

  @override
  Widget build(BuildContext context) {
    final r = route;
    switch (r) {
      case PlaylistRoute():
        return PlaylistDetailView(
            platform: r.platform, id: r.id, kind: r.kind, fromLibrary: r.fromLibrary);
      case AlbumRoute():
        return AlbumDetailView(platform: r.platform, id: r.id);
      case ArtistRoute():
        return ArtistDetailView(platform: r.platform, id: r.id);
      case GenreRoute():
        return GenreDetailView(platform: r.platform, id: r.id);
      case LibrarySectionRoute():
        return LibraryBrowseView(section: r.section);
      case LocalFolderRoute():
        return LocalFilesView(path: r.path);
      case SubscriptionDetailRoute():
        return SubscriptionDetailView(subscriptionId: r.id);
      case SettingsPlatformRoute():
        return PlatformSettingsView(id: r.id);
      case SimpleRoute():
        return _simple(r.name);
    }
  }

  Widget _simple(String name) {
    switch (name) {
      case 'daily':
        return const DailyView();
      case 'explore-playlists':
        return const ExplorePlaylistsView();
      case 'explore-albums':
        return const ExploreAlbumsView();
      case 'genres':
        return const GenresView();
      case 'favorites':
        return const FavoritesView();
      case 'files':
        return const LocalFilesView(path: '');
      case 'ingest-records':
        return const IngestRecordsView();
      case 'subscriptions':
        return const SubscriptionsView();
      case 'source-runs':
        return const SourceRunsView();
      case 'server-logs':
        return const ServerLogsView();
      case 'client-logs':
        return const ClientLogsView();
      case 'recents':
        return const RecentsView();
      case 'account':
        return const AccountView();
      case 'settings':
        return const SettingsView();
      case 'settings-profile':
        return const ProfileSettingsView();
      case 'settings-automation':
        return const AutomationView();
      case 'settings-sources':
        return const CustomSourcesView();
      default:
        return const PlaceholderScreen('未知页面');
    }
  }
}
