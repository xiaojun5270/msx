import '../stores/player_store.dart';
import '../stores/ui_store.dart';
import '../theme/route.dart';
import '../theme/theme.dart';

/// Handles `musicx://` deep links. Mirrors Swift `DeepLink`.
class DeepLink {
  static const scheme = 'musicx';

  static void open(Uri url, {required PlayerStore player, required UIStore ui}) {
    if (url.scheme != scheme) return;
    switch (url.host) {
      case 'now-playing':
        player.setNowPlayingOpen(true);
        break;
      case 'playlist':
        final platform = url.queryParameters['platform'] ?? '';
        final id = url.queryParameters['id'] ?? '';
        final type = url.queryParameters['type'] ?? '';
        if (id.isEmpty) return;
        final AppRoute route;
        switch (type) {
          case 'album':
            route = AlbumRoute(platform: platform, id: id);
            break;
          case 'artist':
            route = ArtistRoute(platform: platform, id: id);
            break;
          case 'chart':
            route = PlaylistRoute(platform: platform, id: id, kind: ListKind.chart, fromLibrary: false);
            break;
          default:
            route = PlaylistRoute(platform: platform, id: id, kind: ListKind.platform, fromLibrary: false);
        }
        ui.open(route);
        break;
      default:
        break;
    }
  }
}
