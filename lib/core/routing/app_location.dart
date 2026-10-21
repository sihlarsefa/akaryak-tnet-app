import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Uygulama içi bir konumu açar (bildirim, push dokunuşu, bildirim balonu "Aç", zil).
///
/// Hedef alt menünün bir sekmesi (kabuğun içindeki bir rota) ise `go` kullanılır: sekme değişir,
/// üstteki tam ekran sayfalar kapanır. Tam ekran bir sayfanın üstüne `push` ile bir sekme rotası
/// açmak kabuğu kök gezginde ikinci kez kurar (aynı anahtarlı iki sayfa, QA SC-01). Diğer hedefler
/// (kök gezgindeki ayrıntı ve sihirbaz sayfaları) `push` ile açılır, geri tuşu önceki sayfaya döner.
void openAppLocation(GoRouter router, String location) {
  if (isShellLocation(router, location)) {
    router.go(location);
  } else {
    unawaited(router.push<Object?>(location));
  }
}

/// [location] kabuğun (alt menü sekmeleri) içinde mi açılır?
bool isShellLocation(GoRouter router, String location) {
  final uri = Uri.tryParse(location);
  if (uri == null) return false;
  try {
    final match = router.configuration.findMatch(uri);
    if (match.isError || match.matches.isEmpty) return false;
    return match.matches.last is ShellRouteMatch;
  } on Object {
    return false;
  }
}

extension AppLocationContext on BuildContext {
  /// [openAppLocation] bu bağlamın yönlendiricisiyle.
  void openAppLocation(String location) =>
      openAppLocationWith(GoRouter.of(this), location);
}

/// [openAppLocation] için ad çakışmasız takma ad (uzantı içinden çağrılır).
void openAppLocationWith(GoRouter router, String location) =>
    openAppLocation(router, location);
