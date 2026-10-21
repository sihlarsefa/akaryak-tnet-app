import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/external_activity.dart';
import '../../../../core/utils/log.dart';
import '../../copy.dart';

/// Arama ve yol tarifi bağlantıları (Google / Apple Haritalar). Koordinat yoksa adresle aranır.
abstract final class DriverLinks {
  /// `tel:` bağlantısı (10 haneli numaraya baştaki 0 eklenir).
  static Uri? phone(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return null;
    final normalized = digits.length == 10 && digits.startsWith('5')
        ? '0$digits'
        : digits;
    return Uri(scheme: 'tel', path: normalized);
  }

  static String? _destination(double? lat, double? lng, String? address) {
    if (lat != null && lng != null) return '$lat,$lng';
    final a = address?.trim();
    return a == null || a.isEmpty ? null : a;
  }

  /// Google Haritalar yol tarifi (uygulama yüklüyse uygulamada açılır).
  static Uri? googleDirections({double? lat, double? lng, String? address}) {
    final d = _destination(lat, lng, address);
    if (d == null) return null;
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': d,
      'travelmode': 'driving',
    });
  }

  /// iOS Google Haritalar uygulaması.
  static Uri? googleApp({double? lat, double? lng, String? address}) {
    final d = _destination(lat, lng, address);
    if (d == null) return null;
    return Uri(
      scheme: 'comgooglemaps',
      queryParameters: {'daddr': d, 'directionsmode': 'driving'},
    );
  }

  /// Apple Haritalar yol tarifi.
  static Uri? appleDirections({double? lat, double? lng, String? address}) {
    final d = _destination(lat, lng, address);
    if (d == null) return null;
    return Uri.https('maps.apple.com', '/', {'daddr': d, 'dirflg': 'd'});
  }

  /// Haritada göster (pin).
  static Uri? showOnMap({double? lat, double? lng, String? address}) {
    final d = _destination(lat, lng, address);
    if (d == null) return null;
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': d,
    });
  }
}

Future<bool> _launch(Uri uri) async {
  try {
    return await launchExternal(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    AppLog.debug('Bağlantı açılamadı: $e');
    return false;
  }
}

/// Telefonla arar.
Future<void> callPhone(BuildContext context, String? phone) async {
  final uri = DriverLinks.phone(phone);
  final ok = uri != null && await _launch(uri);
  if (!ok && context.mounted) {
    AppToast.error(DriverCopy.callFailed, context: context);
  }
}

/// Haritada gösterir.
Future<void> showOnMap(
  BuildContext context, {
  double? lat,
  double? lng,
  String? address,
}) async {
  final uri = DriverLinks.showOnMap(lat: lat, lng: lng, address: address);
  final ok = uri != null && await _launch(uri);
  if (!ok && context.mounted) {
    AppToast.error(DriverCopy.navigateFailed, context: context);
  }
}

/// "Yol tarifi": iOS'ta Apple / Google seçimi, Android'de doğrudan Google Haritalar.
Future<void> openNavigation(
  BuildContext context, {
  double? lat,
  double? lng,
  String? address,
}) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    final uri = DriverLinks.googleDirections(
      lat: lat,
      lng: lng,
      address: address,
    );
    final ok = uri != null && await _launch(uri);
    if (!ok && context.mounted) {
      AppToast.error(DriverCopy.navigateFailed, context: context);
    }
    return;
  }
  await showAppSheet<void>(
    context: context,
    title: DriverCopy.actionNavigate,
    builder: (ctx) => _NavigationChoices(lat: lat, lng: lng, address: address),
  );
}

class _NavigationChoices extends StatelessWidget {
  const _NavigationChoices({this.lat, this.lng, this.address});

  final double? lat;
  final double? lng;
  final String? address;

  Future<void> _open(BuildContext context, List<Uri?> candidates) async {
    final nav = Navigator.of(context);
    for (final uri in candidates) {
      if (uri == null) continue;
      if (await _launch(uri)) {
        unawaited(nav.maybePop());
        return;
      }
    }
    if (context.mounted) {
      AppToast.error(DriverCopy.navigateFailed, context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AknListTile(
          leadingIcon: Icons.map_rounded,
          leadingTone: AknTone.info,
          title: DriverCopy.appleMaps,
          padding: const EdgeInsets.symmetric(vertical: 8),
          onTap: () => _open(context, [
            DriverLinks.appleDirections(lat: lat, lng: lng, address: address),
          ]),
        ),
        AknListTile(
          leadingIcon: Icons.navigation_rounded,
          leadingTone: AknTone.ok,
          title: DriverCopy.googleMaps,
          padding: const EdgeInsets.symmetric(vertical: 8),
          onTap: () => _open(context, [
            DriverLinks.googleApp(lat: lat, lng: lng, address: address),
            DriverLinks.googleDirections(lat: lat, lng: lng, address: address),
          ]),
        ),
        if (address != null && address!.trim().isNotEmpty)
          AknListTile(
            leadingIcon: Icons.copy_rounded,
            title: DriverCopy.copyAddress,
            padding: const EdgeInsets.symmetric(vertical: 8),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: address!.trim()));
              if (context.mounted) {
                AppToast.info(DriverCopy.addressCopied, context: context);
                unawaited(Navigator.of(context).maybePop());
              }
            },
          ),
      ],
    );
  }
}
