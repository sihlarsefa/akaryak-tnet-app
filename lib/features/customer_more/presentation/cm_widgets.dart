import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/app_failure.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/utils/external_activity.dart';
import '../../../core/utils/format.dart';
import '../copy.dart';

/// Destek kodu: iz kimliğinin ilk 8 karakteri (spec C.7).
String? supportCode(AppFailure f) {
  final t = f.traceId;
  if (t == null || t.isEmpty) return null;
  return t.length <= 8 ? t : t.substring(0, 8);
}

/// Kullanıcıya gösterilecek kısa hata metni (tasarım v2 §10.2: ne başarısız oldu, ne yapmalı).
String failureText(AppFailure f) => switch (f) {
  OfflineFailure() =>
    'Bağlantı yok. Bağlantı gelince tekrar deneyin; girdikleriniz bu ekranda duruyor.',
  TimeoutFailure() =>
    'Sunucu zamanında yanıt vermedi. Birkaç dakika sonra tekrar deneyin.',
  RateLimitedFailure(:final retryAfter) =>
    retryAfter == null
        ? 'Çok fazla deneme. Biraz sonra tekrar deneyin.'
        : 'Çok fazla deneme. ${retryAfter.inSeconds} sn sonra tekrar deneyin.',
  ConflictFailure(:final isConcurrency) =>
    isConcurrency
        ? 'Bu kayıt siz bakarken değişti. Güncel hâli yüklendi; tekrar deneyin.'
        : f.message,
  ServerFailure() =>
    supportCode(f) == null
        ? 'Sunucuya şu an ulaşılamıyor. Birkaç dakika sonra tekrar deneyin.'
        : 'Sunucuya şu an ulaşılamıyor. Birkaç dakika sonra tekrar deneyin. Destek kodu: ${supportCode(f)}',
  ValidationFailure(:final fieldErrors) =>
    fieldErrors.values.expand((e) => e).firstOrNull ?? f.message,
  _ => f.message,
};

/// İşlem hatası bildirimi. 403 için çekirdek zaten "Bu işlem için yetkiniz yok." gösterir.
void showFailureToast(BuildContext context, Object error) {
  final f = AppFailure.from(error);
  if (f is ForbiddenFailure) return;
  if (f is UnknownFailure && f.cancelled) return;
  AppToast.error(failureText(f), context: context);
}

/// İlk yükleme hatasının ekranı (çevrimdışı / yetki / bulunamadı / sunucu).
/// Alt eylem çubuğu içeriği: yüksekliğini çocuğundan alır (genişleyen [AknButton] içindeki `Align`
/// çubuğu ekran boyu büyütmesin).
Widget cmBar(Widget child) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [child],
);

/// Bölüm seçici ([AknSegmented], tasarım v2 §6.11): Beton iz, beyaz başparmak; 20 px kenar.
class CmSegmented<T> extends StatelessWidget {
  const CmSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.margin = const EdgeInsets.symmetric(horizontal: 20),
  });

  final List<FilterOption<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => AknSegmented<T>(
    segments: segments,
    value: value,
    onChanged: onChanged,
    margin: margin,
  );
}

/// Arama kuyusu (tasarım v2 §6.10): Beton, r12, büyüteç 20 soluk, ipucu soluk; odakta beyaz ve
/// 2 px turuncu çerçeve. Yüksekliği 48 (dokunma alanı en az 48 dp, WCAG / Android yönergesi).
/// Yazdıkça [debounce] sonra [onChanged] (kırpılmış).
class CmSearchField extends StatefulWidget {
  const CmSearchField({
    super.key,
    required this.hint,
    this.onChanged,
    this.debounce = const Duration(milliseconds: 300),
  });

  final String hint;
  final ValueChanged<String>? onChanged;
  final Duration debounce;

  @override
  State<CmSearchField> createState() => _CmSearchFieldState();
}

class _CmSearchFieldState extends State<CmSearchField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final Debouncer _debouncer = Debouncer(widget.debounce);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_rebuild);
    _focus.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _changed(String s) {
    final cb = widget.onChanged;
    if (cb == null) return;
    _debouncer(() => cb(s.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final text = t.body.copyWith(height: 20 / 15, color: c.ink);
    OutlineInputBorder border(BorderSide side) =>
        OutlineInputBorder(borderRadius: AknRadius.input, borderSide: side);
    return TextField(
      controller: _controller,
      focusNode: _focus,
      textInputAction: TextInputAction.search,
      onChanged: _changed,
      onSubmitted: (s) {
        _debouncer.cancel();
        widget.onChanged?.call(s.trim());
      },
      onTapOutside: (_) => _focus.unfocus(),
      style: text,
      cursorColor: c.brand,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: text.copyWith(color: c.dim),
        isDense: true,
        filled: true,
        fillColor: _focus.hasFocus ? c.surface : c.surfaceAlt,
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.fromLTRB(0, 14, 12, 14),
        prefixIcon: Icon(Icons.search_rounded, color: c.dim, size: 20),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 48,
        ),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Temizle',
                icon: Icon(Icons.close_rounded, color: c.dim, size: 20),
                onPressed: () {
                  _controller.clear();
                  _debouncer.cancel();
                  widget.onChanged?.call('');
                },
              ),
        border: border(BorderSide.none),
        enabledBorder: border(BorderSide.none),
        focusedBorder: border(BorderSide(color: c.brand, width: 2)),
      ),
    );
  }
}

/// Büyük yazı (≥ 1,6×): plakalar destedeki gibi sıkı düzene geçer (§5.3, §12).
bool cmLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) >= 16;

/// Bir plaka: normal yazıda okumalar kuralın altında; büyük yazıda plaka sıkı düzende (baş ve rakam)
/// kalır ve okumalar plakanın altında etiket / değer satırları olarak yazılır (uzun değerler
/// sarılır, kesilmez).
class CmPlate extends StatelessWidget {
  const CmPlate({
    super.key,
    required this.head,
    required this.figure,
    required this.readouts,
    this.semanticLabel,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 0),
  });

  final Widget head;
  final Widget figure;
  final List<PlateReadout> readouts;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final large = cmLargeText(context);
    final plate = AknPlate(
      semanticLabel: semanticLabel,
      compact: large,
      head: head,
      figure: figure,
      below: large ? null : PlateReadouts(items: readouts),
    );
    if (!large) return Padding(padding: padding, child: plate);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          plate,
          const SizedBox(height: 8),
          for (final r in readouts)
            FactRow(
              label: r.label,
              value: r.unit == null || r.unit!.isEmpty
                  ? r.value
                  : '${r.value} ${r.unit}',
            ),
        ],
      ),
    );
  }
}

/// Kart başlığı + sağda rozet: sığmadığında (büyük yazı boyutu, uzun başlık) rozet alt satıra
/// iner; taşma olmaz.
class CmHeadRow extends StatelessWidget {
  const CmHeadRow({super.key, required this.title, required this.trailing});

  final Widget title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 4,
    children: [title, trailing],
  );
}

class CmFailureView extends StatelessWidget {
  const CmFailureView({
    super.key,
    required this.failure,
    this.onRetry,
    this.compact = false,
  });

  final AppFailure failure;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final f = failure;
    return switch (f) {
      OfflineFailure() => EmptyState(
        title: CmCopy.offlineEmpty,
        message: CmCopy.offlineEmptyMessage,
        illustration: AknIllustration.offline,
        actionLabel: onRetry == null ? null : CmCopy.retry,
        onAction: onRetry,
        compact: compact,
      ),
      ForbiddenFailure() => EmptyState(
        title: CmCopy.forbiddenTitle,
        message: CmCopy.forbiddenMessage,
        illustration: AknIllustration.error,
        compact: compact,
      ),
      NotFoundFailure() => EmptyState(
        title: CmCopy.notFound,
        message: f.message,
        illustration: AknIllustration.search,
        compact: compact,
      ),
      ServerFailure() => ErrorState(
        title: 'Sunucuya ulaşılamıyor',
        message:
            'Sunucuya şu an ulaşılamıyor. Birkaç dakika sonra tekrar deneyin.',
        traceId: supportCode(f),
        onRetry: onRetry,
        compact: compact,
      ),
      TimeoutFailure() => ErrorState(
        title: 'Sunucu zamanında yanıt vermedi',
        message:
            'Bağlantınız yavaş olabilir. Birkaç dakika sonra tekrar deneyin.',
        onRetry: onRetry,
        compact: compact,
      ),
      _ => ErrorState(
        message: failureText(f),
        onRetry: onRetry,
        compact: compact,
      ),
    };
  }
}

/// "Son güncelleme 14:30" (çevrimdışıyken önbellekten gösterilen veri).
class CachedNote extends StatelessWidget {
  const CachedNote({super.key, required this.storedAt});

  final DateTime? storedAt;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final when = storedAt == null
        ? 'kayıtlı veri'
        : (Fmt.dayLabel(storedAt) == 'Bugün'
              ? Fmt.time(storedAt)
              : Fmt.dateTime(storedAt));
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 16, color: c.dim),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Son güncelleme $when, çevrimdışı gösteriliyor',
                style: t.caption.copyWith(color: c.dim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sonsuz kaydırma alt bilgisi: yükleniyor / hata + tekrar dene.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    super.key,
    required this.loading,
    this.error,
    this.onRetry,
  });

  final bool loading;
  final AppFailure? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: ChevronSpinner(size: 22)),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: AknButton.ghost(
            label: CmCopy.retry,
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// Sayfa bölümü (tasarım v2 §4.5 "Section"): başlık (`title` 20/26), isteğe bağlı açıklama ve sağda
/// bir denetim, altında içerik — kutu yok, gölge yok. İçerik 20 px kenarla girintilenir; ledger
/// satırları gibi kenardan kenara içerik için [bleed] true verin. [padding] ve [accent] v2'de
/// kullanılmaz (API kararlılığı için duruyor).
class CmSection extends StatelessWidget {
  const CmSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = AknSpace.cardPadding,
    this.accent,
    this.bleed = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final AknTone? accent;

  /// İçerik kenardan kenara (satırlar kendi 20 px dolgusunu taşır).
  final bool bleed;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 24, trailing == null ? 20 : 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title, style: t.title.copyWith(color: c.ink)),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: t.bodySmall.copyWith(color: c.dim),
                        ),
                      ),
                  ],
                ),
              ),
              // Kendi düğümü: başlığa karışmadan ayrıca odaklanır.
              if (trailing != null) Semantics(container: true, child: trailing),
            ],
          ),
        ),
        if (bleed)
          child
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: child,
          ),
      ],
    );
  }
}

/// Konumu harici harita uygulamasında açar (iOS Apple Haritalar, Android geo:, yedek Google Haritalar).
Future<bool> openInMaps(double lat, double lng, {String? label}) async {
  final q = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
  final name = Uri.encodeComponent(label ?? 'Teslimat noktası');
  final native = defaultTargetPlatform == TargetPlatform.iOS
      ? Uri.parse('https://maps.apple.com/?ll=$q&q=$name')
      : Uri.parse('geo:$q?q=$q($name)');
  try {
    if (await launchExternal(native, mode: LaunchMode.externalApplication)) {
      return true;
    }
  } catch (_) {}
  try {
    return await launchExternal(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// Telefon araması (`tel:`).
Future<bool> callPhone(String phone) async {
  final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.isEmpty) return false;
  try {
    return await launchExternal(Uri(scheme: 'tel', path: digits));
  } catch (_) {
    return false;
  }
}

/// Metni panoya kopyalar ve bildirir.
Future<void> copyText(BuildContext context, String text, String toast) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) AppToast.success(toast, context: context);
}
