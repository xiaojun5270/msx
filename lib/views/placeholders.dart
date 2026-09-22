import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Temporary scaffolding for screens not yet ported. Tasks #9–#11 replace each
/// of these with the real view (same class name, so the shell/route mapper need
/// no changes). Keeping them in one file makes the remaining surface obvious.
class PlaceholderScreen extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool appBar;
  const PlaceholderScreen(this.title, {super.key, this.subtitle, this.appBar = true});

  @override
  Widget build(BuildContext context) {
    final body = Container(
      color: Colors.transparent,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: TextStyle(color: MX.fg, fontSize: 22, fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: TextStyle(color: MX.mute, fontSize: 14)),
          ],
          const SizedBox(height: 6),
          Text('待移植', style: TextStyle(color: MX.mute.withOpacity(0.6), fontSize: 12)),
        ],
      ),
    );
    if (!appBar) return body;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: MX.fg,
        title: Text(title),
      ),
      body: body,
    );
  }
}

// --- Detail + management routes (task #11) ----------------------------------
// GenreDetailView, DailyView, ExplorePlaylistsView, ExploreAlbumsView,
// GenresView, FavoritesView now live in explore_views.dart.

// LocalFilesView now lives in local_files_view.dart.
// IngestRecordsView now lives in ingest_records_view.dart.

// SubscriptionsView + SubscriptionDetailView now live in subscriptions_view.dart.

// ServerLogsView + ClientLogsView now live in logs_view.dart.
// SourceRunsView now lives in source_organization_view.dart.
// SettingsView / ProfileSettingsView / PlatformSettingsView / AutomationView /
// CustomSourcesView now live in settings_views.dart.
