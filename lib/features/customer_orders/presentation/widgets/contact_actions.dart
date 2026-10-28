import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/external_activity.dart';
import '../../../../core/utils/log.dart';
import '../../copy.dart';
import '../../data/home_models.dart';

/// Dış uygulama açıcı (telefon, WhatsApp, harita). Testler geçersiz kılar.
typedef ExternalLauncher = Future<bool> Function(Uri uri);

final a2LauncherProvider = Provider<ExternalLauncher>(
  (ref) => (uri) async {
    try {
      return await launchExternal(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLog.debug('Bağlantı açılamadı: $e');
      return false;
    }
  },
);

/// Telefon, WhatsApp ve harita bağlantıları.
abstract final class ContactLinks {
  static Uri? tel(String? number) {
    final d = (number ?? '').replaceAll(RegExp(r'[^\d+]'), '');
    if (d.isEmpty) return null;
    return Uri(scheme: 'tel', path: d);
  }

  /// `https://wa.me/905321112233?text=…` (WhatsApp yoksa tarayıcıda açılır).
  static Uri? whatsapp(String? e164, {String? text}) {
    if (e164 == null || e164.isEmpty) return null;
    return Uri.https('wa.me', '/$e164', {
      if (text != null && text.isNotEmpty) 'text': text,
    });
  }

  /// Koordinat ya da adres için harita (her iki platformda tarayıcı / uygulama).
  static Uri? map({double? lat, double? lng, String? address}) {
    if (lat != null && lng != null) {
      return Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '$lat,$lng',
      });
    }
    final a = address?.trim();
    if (a == null || a.isEmpty) return null;
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': a,
    });
  }
}

Future<void> openExternal(
  BuildContext context,
  WidgetRef ref,
  Uri? uri, {
  required String failMessage,
}) async {
  if (uri == null) {
    AppToast.warning(failMessage, context: context);
    return;
  }
  final ok = await ref.read(a2LauncherProvider)(uri);
  if (!ok && context.mounted) AppToast.warning(failMessage, context: context);
}

/// "Bayiyi ara / WhatsApp" düğmeleri (ana sayfanın varsayılan bayisi): ikincil düğmeler, bir
/// satıra sığmazsa alta kayar. [leading] aynı akışta öne eklenen düğmelerdir ("Haritada aç").
class StationContactButtons extends ConsumerWidget {
  const StationContactButtons({
    super.key,
    required this.station,
    this.message,
    this.dense = false,
    this.leading = const [],
  });

  final StationContact? station;

  /// WhatsApp'ta hazır metin (ör. sipariş numarası).
  final String? message;
  final bool dense;
  final List<Widget> leading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = station;
    final call = s?.callNumber;
    final wa = s?.whatsappNumber;
    if (call == null && wa == null && leading.isEmpty) {
      return const SizedBox.shrink();
    }
    final size = dense ? AknButtonSize.small : AknButtonSize.medium;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ...leading,
        if (call != null)
          AknButton.secondary(
            label: OrdersCopy.callStation,
            icon: PhosphorIconsRegular.phone,
            size: size,
            semanticLabel: '${s!.title} bayisini ara',
            onPressed: () => openExternal(
              context,
              ref,
              ContactLinks.tel(call),
              failMessage: 'Arama başlatılamadı.',
            ),
          ),
        if (wa != null)
          AknButton.secondary(
            label: OrdersCopy.whatsapp,
            icon: PhosphorIconsRegular.chatCircle,
            size: size,
            semanticLabel: '${s!.title} bayisine WhatsApp ile yaz',
            onPressed: () => openExternal(
              context,
              ref,
              ContactLinks.whatsapp(wa, text: message),
              failMessage: 'WhatsApp açılamadı.',
            ),
          ),
      ],
    );
  }
}
