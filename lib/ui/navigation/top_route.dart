import 'package:go_router/go_router.dart';

// RouteMatchList.uri ignores pages added with push(), so while the player is
// pushed over /home it still reads /home. The last match is the page on top.
String topRoutePath(RouteMatchList config) {
  final top = config.lastOrNull;
  if (top == null) return config.uri.path;
  return Uri.parse(top.matchedLocation).path;
}

Object? topRoutePageKey(RouteMatchList config) => config.lastOrNull?.pageKey;

bool isPlayerPath(String path) =>
    path.startsWith('/player/') ||
    path == '/live-tv/player' ||
    path.startsWith('/game-player/');
