import '../../models/json.dart';

/// Siparişin teslimle tamamlanma kuralının sahte karşılığı: sunucunun `OrderCompletionRules`
/// (elle "Tamamla", teslim kabulüyle kendiliğinden tamamlanma) ve `FulfillmentService`
/// `CompletionHintAsync` (`shipments/order/{id}` → `completionHint`) kuralları; metinler
/// sunucuyla aynıdır. Teslim toleransı Sistem Ayarları varsayılanıdır (%1).
///
/// Sevkiyat durumları: 0 planlı, 1 yolda, 2 kabul bekliyor, 3 kabul edildi, 4 itirazlı, 5 iptal.
abstract final class FakeCompletion {
  /// Sistem Ayarları › "Teslim toleransı (%)" varsayılanı.
  static const double tolerancePercent = 1;

  static const notApproved = 'Yalnızca onaylanmış siparişler tamamlanabilir.';
  static const openShipments =
      'Açık sevkiyat var; sipariş, tüm litre müşteri tarafından teslim alınınca kendiliğinden tamamlanır.';
  static const noShipment =
      'Müşteri onaylı sipariş, tüm litre teslim alınınca otomatik tamamlanır; önce sevkiyat planlayın.';

  /// Tolerans içindeki eksik teslimde yönetene giden çağrı.
  static const invitation =
      'Teslim alınan litre teslim toleransı içinde; siparişi sipariş detayındaki "Tamamla" ile kapatabilirsiniz.';

  static int _status(JsonMap s) => (s['status'] as num?)?.toInt() ?? 0;

  static List<JsonMap> _active(Iterable<JsonMap> shipments) => [
    for (final s in shipments)
      if (_status(s) != 5) s,
  ];

  /// Kabul edilen litre (iptal dışı, kabul edilmiş sevkiyatların teslim litresi).
  static double acceptedLiters(Iterable<JsonMap> shipments) =>
      _active(shipments)
          .where((s) => _status(s) == 3)
          .fold<double>(0, (sum, s) => sum + _delivered(s));

  static double _delivered(JsonMap s) =>
      (s['deliveredLiters'] as num?)?.toDouble() ?? 0;

  /// Siparişi tolerans içinde kapatan en az kabul edilen litre.
  static double minimumCompletingLiters(double ordered) =>
      ordered * (1 - tolerancePercent / 100);

  /// Teslim edilmiş sayılır mı (`OrderCompletionRules.IsFulfilled`): tüm litre kabul edildi; ya da
  /// açık sevkiyat kalmadı ve kabul edilen litre tolerans içinde.
  static bool isFulfilled(double ordered, Iterable<JsonMap> shipments) {
    final active = _active(shipments);
    final accepted = acceptedLiters(active);
    if (accepted <= 0) return false;
    if (accepted >= ordered) return true;
    if (active.any((s) => _status(s) != 3)) return false;
    return accepted >= minimumCompletingLiters(ordered);
  }

  /// `OrderCompletionRules.BlockReason`: null ise sipariş elle tamamlanabilir.
  static String? blockReason({
    required int status,
    required bool hasAcceptedQuote,
    required double ordered,
    required Iterable<JsonMap> shipments,
  }) {
    if (status != 3) return notApproved;
    final active = _active(shipments);
    if (active.isEmpty && !hasAcceptedQuote) return null;
    if (isFulfilled(ordered, active)) return null;
    if (active.any((s) => _status(s) != 3)) return openShipments;
    if (active.isEmpty) return noShipment;
    final accepted = acceptedLiters(active);
    return 'Teslim alınan ${_liters(accepted)} L, sipariş ${_liters(ordered)} L: '
        'eksik ${_liters(ordered - accepted)} L, teslim toleransını '
        '(%${_percent(tolerancePercent)}; en az ${_liters(minimumCompletingLiters(ordered))} L) aşıyor. '
        'Kalan litre için sevkiyat planlayın; tüm litre ya da tolerans içindeki miktar teslim alınınca '
        'sipariş otomatik tamamlanır.';
  }

  /// `FulfillmentService.CompletionHintAsync`: kısmi teslim kabul edildi ve açık sevkiyat yok ama
  /// sipariş "Onaylandı"da. Yönetene engel ya da "Tamamla" çağrısı; müşteriye kalan litrenin bayinin
  /// yeni sevkiyatıyla geleceği (tolerans içindeyse null). [shipments]: siparişin tüm sevkiyatları.
  static String? hint({
    required int status,
    required bool hasAcceptedQuote,
    required double ordered,
    required List<JsonMap> shipments,
    required bool canManage,
  }) {
    if (status != 3 ||
        !shipments.any((s) => _status(s) == 3 && _delivered(s) > 0) ||
        shipments.any((s) => _status(s) != 3 && _status(s) != 5)) {
      return null;
    }
    final reason = blockReason(
      status: status,
      hasAcceptedQuote: hasAcceptedQuote,
      ordered: ordered,
      shipments: shipments,
    );
    if (reason == null) return canManage ? invitation : null;
    if (canManage) return reason;
    final accepted = acceptedLiters(shipments);
    return 'Teslim alınan ${_liters(accepted)} L, sipariş ${_liters(ordered)} L: '
        'eksik ${_liters(ordered - accepted)} L, teslim toleransını '
        '(%${_percent(tolerancePercent)}) aşıyor. Kalan litre bayinin yeni sevkiyatıyla gelir; '
        'sipariş, kalan litre teslim alınınca kendiliğinden tamamlanır.';
  }

  /// Sunucunun litre metni (`#,##0.###`, tr-TR): "7.985", "7.985,5".
  static String _liters(double v) {
    final fixed = v.abs().toStringAsFixed(3).split('.');
    final whole = fixed[0];
    final frac = fixed[1].replaceFirst(RegExp(r'0+$'), '');
    final grouped = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) grouped.write('.');
      grouped.write(whole[i]);
    }
    return '${v < 0 ? '-' : ''}$grouped${frac.isEmpty ? '' : ',$frac'}';
  }

  /// Yüzde metni (`0.##`): "1", "1,5".
  static String _percent(double v) {
    final s = v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return s.replaceAll('.', ',');
  }
}
