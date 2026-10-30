// Canlı sözleşme fikstürleri: yerel sandbox API'sinden (portal + mobil API, aynı veritabanı) uygulamanın gönderdiği
// isteklerle alınmış GERÇEK yanıtlar uygulamanın kendi okuyucularıyla (fromJson / parse) okunur. Ağ gerekmez.
//
// - `test/contract/fixtures/index.json`: her fikstürün ucu, yöntemi, gönderilen sorgu, kullanıcı / rol ve HTTP durumu.
// - Okuma sırasında JSON haritaları kaydedici bir haritaya sarılır; uygulamanın sorduğu her anahtar, okuyucu yöntemi
//   (`str`, `dateTr`, `enumOf` …) ve modeldeki satırı yığından alınır. Böylece:
//   1. sunucunun HİÇ göndermediği bir alanı okuyan model (ad uyuşmazlığı) → [_knownMissing] dışındaysa test kırılır;
//   2. JSON tipi okuyucuyla uyuşmayan alan (ör. ondalık değere tamsayı okuyucu, metne tarih okuyucu) → [_knownTypeIssues]
//      dışındaysa kırılır;
//   3. her fikstür bir okuyucuyla eşleşir ve istisnasız okunur; hata gövdeleri doğru `AppFailure` türüne düşer.
//   Bilinen listeler kesin eşleşmelidir: bir boşluk kapanınca (uygulama ya da sunucu düzeltilince) listeden silinmelidir.
// - `--dart-define=AKN_CONTRACT_REPORT=<dosya.json>`: ayrıntılı rapor (okunmayan sunucu alanları, hep null gelen alanlar,
//   ofsetsiz tarih alanları ve okuyucuları) yazılır.
// - Fikstürleri yenilemek: sözleşme denetçisinin yakalama betiği (sandbox'a karşı); bkz. index.json `generatedBy`.
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:akaryakitnet/core/models/app_config.dart';
import 'package:akaryakitnet/core/models/attachment.dart';
import 'package:akaryakitnet/core/models/auth_models.dart';
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/models/order.dart';
import 'package:akaryakitnet/core/models/paged_result.dart';
import 'package:akaryakitnet/core/models/shipment.dart';
import 'package:akaryakitnet/core/models/unread_count.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/features/approvals/data/approval_models.dart';
import 'package:akaryakitnet/features/assistant/data/assistant_models.dart';
import 'package:akaryakitnet/features/auth/data/auth_api.dart';
import 'package:akaryakitnet/features/bayi/data/customer_models.dart';
import 'package:akaryakitnet/features/bayi/data/desk_models.dart';
import 'package:akaryakitnet/features/bayi/data/dispatch_models.dart' as bayi;
import 'package:akaryakitnet/features/bayi/data/home_models.dart';
import 'package:akaryakitnet/features/bayi/data/order_models.dart';
import 'package:akaryakitnet/features/bayi/data/staff_models.dart';
import 'package:akaryakitnet/features/customer_more/data/company.dart';
import 'package:akaryakitnet/features/customer_more/data/customer_more_repository.dart';
import 'package:akaryakitnet/features/customer_more/data/delivery_point.dart';
import 'package:akaryakitnet/features/customer_more/data/documents.dart';
import 'package:akaryakitnet/features/customer_more/data/finance_info.dart';
import 'package:akaryakitnet/features/customer_more/data/order_requests.dart';
import 'package:akaryakitnet/features/customer_more/data/shipments.dart'
    as customer;
import 'package:akaryakitnet/features/customer_more/data/spending.dart';
import 'package:akaryakitnet/features/customer_orders/data/customer_orders_repository.dart'
    as orders_repo;
import 'package:akaryakitnet/features/customer_orders/data/form_models.dart';
import 'package:akaryakitnet/features/customer_orders/data/home_models.dart'
    as customer_home;
import 'package:akaryakitnet/features/customer_orders/data/order_models.dart';
import 'package:akaryakitnet/features/customer_orders/data/payment_models.dart'
    as order_pay;
import 'package:akaryakitnet/features/customer_orders/data/place_models.dart';
import 'package:akaryakitnet/features/driver/data/driver_models.dart';
import 'package:akaryakitnet/features/driver/data/driver_repository.dart';
import 'package:akaryakitnet/features/field/data/field_models.dart';
import 'package:akaryakitnet/features/field/data/field_repository.dart';
import 'package:akaryakitnet/features/field/data/lead_models.dart';
import 'package:akaryakitnet/features/finance/data/finance_models.dart';
import 'package:akaryakitnet/features/notifications/data/notification_models.dart';
import 'package:akaryakitnet/features/payments/data/payment_models.dart'
    as payments;
import 'package:akaryakitnet/features/profile/data/profile_models.dart';
import 'package:akaryakitnet/features/stats/data/stats_models.dart';
import 'package:akaryakitnet/features/stats/data/stats_repository.dart';
import 'package:akaryakitnet/features/weather/data/weather_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = 'test/contract/fixtures';
const _reportPath = String.fromEnvironment('AKN_CONTRACT_REPORT');

// ═══════════════════════════════════════════════════════════════════ Okuyucular

typedef _Parse = Object? Function(Object? json);

PagedResult<T> _paged<T>(Object? j, T Function(JsonReader r) item) =>
    PagedResult.fromJson(j, item);

List<T> _list<T>(Object? j, T Function(JsonReader r) item) =>
    JsonReader.parseList(j, item);

/// Fikstür adı (ya da noktayla ayrılmış ön eki) → uygulamanın o yanıt için kullandığı okuyucu(lar).
/// Birden çok ekranın aynı yanıtı farklı modelle okuduğu yerlerde hepsi çağrılır.
final Map<String, _Parse> _parsers = {
  // Çekirdek
  'app-config': (j) => AppConfig.fromJson(j),
  'me-access': (j) => [MeAccess.fromJson(j), PhoneStatus.fromAccessJson(j)],
  'me-profile': (j) => UserProfile.fromJson(j),
  'auth-sessions': (j) => _list(j, SessionInfo.fromJson),
  'auth-login': (j) => AuthResult.fromJson(j),
  'auth-refresh': (j) => AuthResult.fromJson(j),
  'auth-verify': (j) => AuthResult.fromJson(j),
  'auth-otp-send': (j) => OtpChallenge.fromJson(JsonReader.of(j)),
  'auth-challenge-resend': (j) => OtpChallenge.fromJson(JsonReader.of(j)),
  'phone-verify-start': (j) => OtpChallenge.fromJson(JsonReader.of(j)),
  'notifications-unread-count': (j) => UnreadCount.fromJson(j),
  'notifications': (j) => _paged(j, UserNotification.fromJson),
  'notifications-preferences': (j) => _list(j, NotificationPreference.fromJson),
  'notifications-test': (j) => NotificationTestResult.fromJson(j),
  'approvals-badge': (j) => ApprovalBadge.fromJson(j),
  'assistant-disclosure': (j) => AssistantDisclosure.fromJson(j),
  'assistant-suggestions': (j) => _list(j, SuggestionGroup.fromJson),
  'weather': (j) => WeatherReport.tryParse(j),
  'deletion-request': (j) => AccountDeletionResult.fromJson(j),
  // Müşteri
  'home-customer': (j) => customer_home.CustomerHomeData.fromJson(j),
  'ordering-status': (j) => customer_home.OrderingStatus.parse(j),
  'spending.months': (j) =>
      JsonReader.of(j).list('months', orders_repo.SpendingMonth.fromJson),
  'spending': (j) => SpendingReport.fromJson(j),
  'customer-orders': (j) => _paged(j, CustomerOrderRow.fromJson),
  'catalog-order-form': (j) => OrderFormOptions.fromJson(j),
  'payments-options': (j) => order_pay.CustomerPaymentOptions.fromJson(j),
  'place-order': (j) => PlaceOrderResult.fromJson(j),
  'payment-document-target': (j) => [
    order_pay.PaymentUploadTarget.tryParse(j),
    PaymentUploadTarget.tryParse(j),
  ],
  'order-detail': (j) => OrderDetail.fromJson(j),
  'order-tracking': (j) => OrderTracking.fromJson(j),
  'attachments': (j) => _list(j, Attachment.fromJson),
  'attachment-upload': (j) => AttachmentUploadResult.fromJson(j),
  'templates': (j) => _list(j, TemplateListItem.fromJson),
  'template-detail': (j) => OrderTemplate.fromJson(j),
  'template-save': (j) => OrderTemplate.fromJson(j),
  'template-from-order': (j) => OrderTemplate.fromJson(j),
  'order-requests': (j) => [
    _paged(j, OrderRequest.fromJson),
    JsonReader.of(j).list('items', OrderRequestSnapshot.fromJson),
  ],
  'order-request': (j) => [
    OrderRequestSnapshot.parse(j),
    OrderRequest.fromJson(JsonReader.of(j)),
  ],
  'company-request': (j) => CompanyRequest.fromJson(j),
  'shipments.customer': (j) => customer.ShipmentListPage.fromJson(j),
  'shipment-detail.customer': (j) => customer.ShipmentDetail.fromJson(j),
  'documents': (j) => DocumentArchivePage.fromJson(j),
  'document-order': (j) => OrderDocument.fromJson(j),
  'document-shipment': (j) => ShipmentDocument.fromJson(j),
  'delivery-points': (j) => CustomerMoreRepository.parseDeliveryPoints(j),
  'delivery-point': (j) => DeliveryPoint.fromJson(JsonReader.of(j)),
  // CustomerMoreRepository.saveDeliveryPoint / deactivateDeliveryPoint
  'delivery-point-save': (j) => JsonReader.of(j).integer('id'),
  'delivery-point-deactivate': (j) => JsonReader.of(j).nonEmpty('message'),
  'finance-info': (j) => FinanceInfo.fromJson(j),
  'company-users': (j) => _list(j, CompanyUser.fromJson),
  'company-user': (j) => CompanyUser.fromJson(JsonReader.of(j)),
  'approval-settings': (j) => ApprovalThresholds.fromJson(j),
  'stats-customer': (j) => CustomerStats.fromJson(j),
  // Bayi
  'home-bayi': (j) => [
    BayiHomeData.fromJson(j),
    switch (JsonReader.of(j).obj('sections').objOrNull('field')) {
      final JsonReader f => StatsFieldSummary.fromJson(f),
      null => null,
    },
  ],
  'stats-bayi': (j) => BayiStats.fromJson(j),
  'quote-desk': (j) => DeskPage.fromJson(j),
  'quote-desk-counts': (j) => DeskCountsResult.fromJson(j),
  'quote-desk-facets': (j) => DeskFacets.fromJson(j),
  'quote-desk-submit': (j) => _list(j, DeskSubmitResult.fromJson),
  'bayi-orders': (j) => _paged(j, BayiOrderRow.fromJson),
  'bayi-orders-counts': (j) => BayiOrderCounts.fromJson(j),
  'order-timeline': (j) => _list(j, OrderTimelineItem.fromJson),
  'fulfillment': (j) => Fulfillment.fromJson(j),
  'bayi-customers': (j) => _paged(j, BayiCustomerRow.fromJson),
  'bayi-customers.search': (j) => [
    _paged(j, BayiCustomerRow.fromJson),
    _paged(j, payments.CustomerOption.fromJson),
  ],
  'customer-summary': (j) => CustomerSummary.fromJson(j),
  'customer-summary.field': (j) => FieldCustomerSummary.fromJson(j),
  'customer-notes': (j) => _list(j, CustomerNote.fromJson),
  'customer-note': (j) => CustomerNote.fromJson(JsonReader.of(j)),
  'shipments-board': (j) => bayi.ShipmentBoard.fromJson(j),
  'board-suggestions': (j) => bayi.BoardSuggestions.fromJson(j),
  'drivers': (j) => _list(j, bayi.StationDriver.fromJson),
  'shipments.bayi': (j) => bayi.ShipmentListPage.fromJson(j),
  'shipment-detail.bayi': (j) => bayi.ShipmentDetail.fromJson(j),
  'staff': (j) => _list(j, StaffMember.fromJson),
  'payments': (j) => _paged(j, payments.PaymentRow.fromJson),
  'payment-detail': (j) => payments.PaymentDetail.fromJson(j),
  'instruments': (j) => _paged(j, payments.Instrument.fromJson),
  'finance-customers': (j) => _paged(j, FinanceListItem.fromJson),
  'finance-card': (j) => FinanceCard.fromJson(j),
  'approvals': (j) => _paged(j, ApprovalRow.fromJson),
  'approval-detail': (j) => ApprovalDetail.fromJson(j),
  'approval-decide': (j) => ApprovalDecisionResult.fromJson(j),
  // Saha
  'field-orders': (j) => FieldFormsPage.fromJson(j),
  'field-order': (j) => FieldFormDetail.fromJson(j),
  'field-order-save': (j) => FieldForm.fromJson(j),
  'field-order-submit': (j) => FieldSubmitResult.fromJson(j),
  'field-preview': (j) => FieldPreview.fromJson(j),
  'field-order-document': (j) => FieldDocument.fromJson(j),
  'portfolio': (j) => SkipTakePage.fromJson(j, PortfolioRow.fromJson),
  'field-options-v2': (j) => FieldOptions.fromJson(j),
  'field-supply-options': (j) => _list(j, FieldSupplyOption.fromJson),
  'field-customers-search': (j) => _list(j, IdName.fromJson),
  'field-reps': (j) => _list(j, IdName.fromJson),
  'leads': (j) => FieldRepository.parseLeads(j),
  'lead-detail': (j) => [LeadDetail.fromJson(j), LeadForwardInfo.fromJson(j)],
  'lead-save': (j) => LeadSaveResult.fromJson(j),
  'lead-options': (j) => LeadOptions.fromJson(j),
  'lead-check-duplicate': (j) => LeadDuplicateCheck.fromJson(j),
  'lead-stats': (j) => LeadStats.fromJson(j),
  // Şoför
  'driver-shipments': (j) => [
    _paged(j, DriverShipmentRow.fromJson),
    DriverListData.fromJson(j),
  ],
  'driver-shipment': (j) => DriverShipmentDetail.fromJson(j),
};

/// Hata gövdeleri (HTTP ≥ 400): ProblemDetails + uygulamanın hata eşlemesi.
Object? _parseProblem(int status, Object? j) =>
    AppFailure.fromResponse(status, j);

/// Fikstür adı için okuyucu anahtarı: tam ad, sonra sondan birer `.parça` atılarak.
String? _parserKey(String name) {
  var n = name;
  while (true) {
    if (_parsers.containsKey(n)) return n;
    final i = n.lastIndexOf('.');
    if (i <= 0) return null;
    n = n.substring(0, i);
  }
}

// ═══════════════════════════════════════════════════════════════════ Kaydedici

class _Access {
  _Access(
    this.path,
    this.key,
    this.present,
    this.value,
    this.reader,
    this.site,
  );

  final String path;
  final String key;
  final bool present;
  final Object? value;
  final String reader;
  final String site;
}

class _Recorder {
  final accesses = <_Access>[];
  final presentKeys = <String, Set<String>>{};

  /// (yol, anahtar, tip, var mı) → (okuyucu, satır). Yığın her imza için bir kez çözülür.
  static final _siteCache = <String, (String, String)>{};
  String parser = '';

  void log(String path, String key, bool present, Object? value) {
    final sig = '$parser|$path|$key|${_jsonType(value)}|$present';
    final (reader, site) = _siteCache.putIfAbsent(sig, _callSite);
    accesses.add(_Access(path, key, present, value, reader, site));
  }

  static final _frame = RegExp(r'^#\d+\s+(.+?) \((.+?):(\d+)(?::\d+)?\)$');

  /// Yığından okuyucu yöntemi (JsonReader'ın en dıştaki çağrısı) ve modeldeki çağrı satırı.
  static (String, String) _callSite() {
    final lines = StackTrace.current.toString().split('\n');
    String? reader;
    for (final line in lines) {
      final m = _frame.firstMatch(line.trim());
      if (m == null) continue;
      final member = m[1]!;
      final file = m[2]!;
      if (file.contains('live_contract_fixtures_test.dart') ||
          file.startsWith('dart:')) {
        continue;
      }
      if (file.endsWith('core/models/json.dart')) {
        final name = member.split('.').last;
        if (name != '_value' && !name.startsWith('<')) reader = name;
        continue;
      }
      final site = file
          .replaceFirst('package:akaryakitnet/', 'lib/')
          .replaceFirst(RegExp(r'^file://.*?/akaryakitnet-mobile/'), '');
      return (reader ?? '[]', '$site:${m[3]}');
    }
    return (reader ?? '[]', '?');
  }
}

String _jsonType(Object? v) => switch (v) {
  null => 'null',
  bool() => 'bool',
  int() => 'int',
  double() => 'double',
  String() => 'string',
  List() => 'list',
  Map() => 'map',
  _ => 'other',
};

/// Sunucudan gelen haritayı saran kaydedici: `containsKey` (JsonReader her okumada önce bunu sorar) ve
/// doğrudan `[]` okumaları kaydedilir. İç haritalar ve diziler de sarılır.
class _RecMap extends MapBase<String, dynamic> {
  _RecMap(this._m, this._path, this._rec);

  final Map<String, dynamic> _m;
  final String _path;
  final _Recorder _rec;
  String? _probed;

  @override
  bool containsKey(Object? key) {
    final has = _m.containsKey(key);
    if (key is String && key.isNotEmpty) {
      _probed = key;
      if (_isCamel(key)) _rec.log(_path, key, has, _m[key]);
    }
    return has;
  }

  @override
  dynamic operator [](Object? key) {
    if (key is String && key.isNotEmpty && _probed == null && _isCamel(key)) {
      _rec.log(_path, key, _m.containsKey(key), _m[key]);
    }
    _probed = null;
    return _m[key];
  }

  static bool _isCamel(String k) => k[0] != k[0].toUpperCase();

  @override
  void operator []=(String key, dynamic value) => _m[key] = value;

  @override
  void clear() => _m.clear();

  @override
  Iterable<String> get keys => _m.keys;

  @override
  dynamic remove(Object? key) => _m.remove(key);
}

Object? _wrap(Object? v, String path, _Recorder rec) {
  if (v is Map) {
    final m = <String, dynamic>{
      for (final e in v.entries)
        '${e.key}': _wrap(e.value, '$path.${e.key}', rec),
    };
    rec.presentKeys.putIfAbsent(path, () => <String>{}).addAll(m.keys);
    return _RecMap(m, path, rec);
  }
  if (v is List) return <dynamic>[for (final e in v) _wrap(e, '$path[]', rec)];
  return v;
}

// ═══════════════════════════════════════════════════════════════════ Uyum

/// Okuyucu ile JSON değeri uyumsuzsa nedeni (null = uyumlu).
String? _typeIssue(String reader, Object? v) {
  if (v == null) return null;
  switch (reader) {
    case 'str' || 'strOrNull' || 'nonEmpty':
      return v is String || v is num || v is bool ? null : 'metin bekleniyor';
    case 'integer' || 'intOrNull' || 'enumOf':
      if (JsonReader.toInt(v) == null) return 'tamsayı bekleniyor';
      if (v is double && v != v.truncateToDouble()) {
        return 'kesirli değer tamsayıya kırpılıyor';
      }
      if (v is String) return 'sayı metin olarak geliyor';
      return null;
    case 'dec' || 'decOrNull':
      if (JsonReader.toDouble(v) == null) return 'sayı bekleniyor';
      return v is String ? 'sayı metin olarak geliyor' : null;
    case 'boolean' || 'boolOrNull':
      return v is bool ? null : 'mantıksal değer bekleniyor';
    case 'dateTr' || 'dateUtc' || 'date':
      if (v is! String) return 'tarih metni bekleniyor';
      return DateTime.tryParse(
                v.replaceFirstMapped(RegExp(r'(\.\d{6})\d+'), (m) => m[1]!),
              ) ==
              null
          ? 'tarih okunamıyor'
          : null;
    case 'obj' || 'objOrNull' || 'map':
      return v is Map ? null : 'nesne bekleniyor';
    case 'list' || 'listOf' || 'strings' || 'ints':
      return v is List ? null : 'dizi bekleniyor';
  }
  return null;
}

/// Yolun dizi kısımlarını tek biçime indirger (`.items[].lines[]`).
String _shape(String path) => path;

// ═══════════════════════════════════════════════════════════════════ Bilinen boşluklar

/// Uygulamanın okuduğu ama canlı sunucunun HİÇBİR fikstürde göndermediği alanlar (`okuyucu-anahtarı: yol.anahtar`).
/// Her satır bir bulguya ya da bilinçli bir yedek okumaya karşılık gelir; düzeltilince silinir.
const Map<String, String> _knownMissing = {
  // Problem.tryParse: eski uçların `{message}` / `{error}` gövdeleri için bilinçli yedek okuma; mobil v1 hep `detail` gönderir.
  'problem: .message': 'yedek okuma (eski gövde)',
  'problem: .error': 'yedek okuma (eski gövde)',
  // OrderFormOptions noktası: `deliveryWindowStart ?? windowStart` yedeği; sunucu yalnızca deliveryWindow* gönderir.
  'catalog-order-form: .deliveryPoints[].windowStart': 'yedek okuma',
  'catalog-order-form: .deliveryPoints[].windowEnd': 'yedek okuma',
  // StatsSummary bayi ve cari için ortak; cari istatistiğinde cari sayıları yok (null kalır, ekran göstermez).
  'stats-customer: .spending.activeCustomers': 'ortak model (yalnızca bayi)',
  'stats-customer: .spending.newCustomers': 'ortak model (yalnızca bayi)',
  // Roller v5 (sunucu: MeAccessDto, StationStaffDto, UserBayiRoleDto, CompanyUserDto alanları eklendi; fikstürler
  // 28.10 yakalaması). Sandbox Roller v5 sunucusuyla yeniden yakalanınca (me-access.*, staff, company-users.*)
  // bu satırlar silinir; test kapanan boşluğu ayrıca bildirir.
  'me-access: .signingCapabilities': 'roller v5: yeniden yakalanacak',
  'me-access: .approverUnits': 'roller v5: yeniden yakalanacak',
  'me-access: .companyApprovalsEnabled': 'roller v5: yeniden yakalanacak',
  'staff: [].approverOf': 'roller v5: yeniden yakalanacak',
  'staff: [].needsReview': 'roller v5: yeniden yakalanacak',
  'staff: [].bayiRoles[].isRetired': 'roller v5: yeniden yakalanacak',
  'company-users: [].isMainUser': 'roller v5: yeniden yakalanacak',
  // Kullanıcı adıyla giriş (sözleşme 2026-10-30, sunucu ekliyor): yeniden yakalanınca silinir.
  'company-users: [].userName': 'kullanıcı adı: yeniden yakalanacak',
  'staff: [].userName': 'kullanıcı adı: yeniden yakalanacak',
  'staff: [].isMainAccount': 'kullanıcı adı: yeniden yakalanacak',
};

/// Okuyucusu JSON tipiyle uyuşmayan alanlar (`okuyucu-anahtarı: yol.anahtar (okuyucu←tip)`).
const Map<String, String> _knownTypeIssues = {};

// ═══════════════════════════════════════════════════════════════════ Test

class _Fixture {
  _Fixture(this.meta, this.json);
  final Map<String, dynamic> meta;
  final Object? json;
  String get name => meta['name'] as String;
  int get status => meta['status'] as int;
}

List<_Fixture> _loadFixtures() {
  final index =
      jsonDecode(File('$_dir/index.json').readAsStringSync())
          as Map<String, dynamic>;
  return [
    for (final m in (index['fixtures'] as List).cast<Map<String, dynamic>>())
      _Fixture(
        m,
        jsonDecode(File('$_dir/${m['name']}.json').readAsStringSync()),
      ),
  ];
}

void main() {
  final fixtures = _loadFixtures();

  // Her fikstür için kayıt (okuyucu anahtarı → kayıtlar).
  final byParser = <String, List<_Recorder>>{};
  final failures = <String, Object>{};
  final appFailures = <String, AppFailure>{};

  setUpAll(() {
    for (final f in fixtures) {
      final rec = _Recorder();
      final isProblem = f.status >= 400;
      final key = isProblem ? 'problem' : _parserKey(f.name);
      if (key == null) continue;
      rec.parser = key;
      final wrapped = _wrap(f.json, '', rec);
      try {
        final out = isProblem
            ? _parseProblem(f.status, wrapped)
            : _parsers[key]!(wrapped);
        if (out is AppFailure) appFailures[f.name] = out;
      } catch (e, st) {
        failures[f.name] = '$e\n$st';
      }
      byParser.putIfAbsent(key, () => []).add(rec);
    }
  });

  test('fikstür klasörü dolu ve her fikstürün bir okuyucusu var', () {
    expect(fixtures.length, greaterThan(150));
    final orphans = [
      for (final f in fixtures)
        if (f.status < 400 && _parserKey(f.name) == null) f.name,
    ];
    expect(orphans, isEmpty, reason: 'okuyucusu olmayan fikstürler');
  });

  test('her yanıt uygulamanın okuyucusuyla istisnasız okunur', () {
    expect(failures, isEmpty);
  });

  test('hata gövdeleri doğru AppFailure türüne düşer', () {
    final expected = <String, Type>{};
    for (final f in fixtures.where((f) => f.status >= 400)) {
      final code = (f.json as Map?)?['code'];
      expected[f.name] = switch ((f.status, code)) {
        (400, 'validation') => ValidationFailure,
        (400, _) => BusinessFailure,
        (401, _) => UnauthorizedFailure,
        (403, _) => ForbiddenFailure,
        (404, _) => NotFoundFailure,
        (409, _) => ConflictFailure,
        (426, _) => UpdateRequiredFailure,
        (429, _) => RateLimitedFailure,
        _ => ServerFailure,
      };
    }
    expect(expected, isNotEmpty);
    for (final e in expected.entries) {
      final f = appFailures[e.key];
      expect(f.runtimeType, e.value, reason: e.key);
      expect(f!.message, isNotEmpty, reason: '${e.key}: kullanıcı mesajı');
      if (f is RateLimitedFailure) {
        expect(f.retryAfter, isNotNull, reason: '${e.key}: retryAfter');
      }
    }
  });

  test('uygulamanın okuduğu her alan sunucuda var (ad uyuşmazlığı yok)', () {
    final missing = _missingEverywhere(byParser);
    expect(
      missing.keys.toSet().difference(_knownMissing.keys.toSet()),
      isEmpty,
      reason:
          'Sunucunun hiç göndermediği alanlar okunuyor:\n${_fmt(missing, _knownMissing)}',
    );
    expect(
      _knownMissing.keys.toSet().difference(missing.keys.toSet()),
      isEmpty,
      reason: 'Bu boşluklar kapandı; _knownMissing listesinden silin.',
    );
  });

  test('okunan alanların JSON tipi okuyucuyla uyumlu', () {
    final issues = _typeIssues(byParser);
    expect(
      issues.keys.toSet().difference(_knownTypeIssues.keys.toSet()),
      isEmpty,
      reason: 'Tip uyuşmazlıkları:\n${_fmt(issues, _knownTypeIssues)}',
    );
    expect(
      _knownTypeIssues.keys.toSet().difference(issues.keys.toSet()),
      isEmpty,
      reason: 'Bu uyuşmazlıklar kapandı; _knownTypeIssues listesinden silin.',
    );
  });

  test('temel değerler varsayılana düşmeden okunur', () {
    for (final f in fixtures.where((f) => f.status < 400)) {
      final j = f.json;
      final key = _parserKey(f.name);
      switch (key) {
        case 'me-access':
          final m = MeAccess.fromJson(j);
          expect(m.persona, isNot(Persona.unknown), reason: f.name);
          expect(m.userId, isNotEmpty, reason: f.name);
        case 'app-config':
          final c = AppConfig.fromJson(j);
          expect(c.minBuild, greaterThanOrEqualTo(1), reason: f.name);
          expect(c.contractVersion, 'mobile-v1', reason: f.name);
        case 'order-detail':
          final o = OrderDetail.fromJson(j);
          expect(o.id, greaterThan(0), reason: f.name);
          expect(o.status, isNot(OrderStatus.unknown), reason: f.name);
        case 'customer-orders':
          for (final o in _paged(j, CustomerOrderRow.fromJson).items) {
            expect(o.status, isNot(OrderStatus.unknown), reason: f.name);
          }
        case 'bayi-orders':
          for (final o in _paged(j, BayiOrderRow.fromJson).items) {
            expect(o.status, isNot(OrderStatus.unknown), reason: f.name);
          }
        case 'driver-shipments':
          for (final s in _paged(j, DriverShipmentRow.fromJson).items) {
            expect(s.id, greaterThan(0), reason: f.name);
            expect(s.status, isNot(ShipmentStatus.unknown), reason: f.name);
          }
      }
    }
  });

  tearDownAll(() {
    if (_reportPath.isEmpty) return;
    File(_reportPath).writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(_report(byParser, failures)),
    );
  });
}

/// (okuyucu, yol, anahtar) → okunan ama hiçbir fikstürde bulunmayan alanlar ve çağrı satırı.
Map<String, String> _missingEverywhere(Map<String, List<_Recorder>> byParser) {
  final out = <String, String>{};
  byParser.forEach((parser, recs) {
    final seen = <String, bool>{};
    final sites = <String, Set<String>>{};
    for (final r in recs) {
      for (final a in r.accesses) {
        final k = '$parser: ${_shape(a.path)}.${a.key}';
        seen[k] = (seen[k] ?? false) || a.present;
        sites.putIfAbsent(k, () => {}).add('${a.reader} @ ${a.site}');
      }
    }
    seen.forEach((k, present) {
      if (!present) out[k] = sites[k]!.join(', ');
    });
  });
  return out;
}

Map<String, String> _typeIssues(Map<String, List<_Recorder>> byParser) {
  final out = <String, String>{};
  byParser.forEach((parser, recs) {
    for (final r in recs) {
      for (final a in r.accesses) {
        if (!a.present) continue;
        final issue = _typeIssue(a.reader, a.value);
        if (issue == null) continue;
        final k =
            '$parser: ${_shape(a.path)}.${a.key} (${a.reader}←${_jsonType(a.value)})';
        out.putIfAbsent(
          k,
          () => '$issue; ör. ${jsonEncode(a.value)} @ ${a.site}',
        );
      }
    }
  });
  return out;
}

String _fmt(Map<String, String> found, Map<String, String> known) => [
  for (final e in found.entries)
    if (!known.containsKey(e.key)) '  ${e.key}  ←  ${e.value}',
].join('\n');

Map<String, Object?> _report(
  Map<String, List<_Recorder>> byParser,
  Map<String, Object> failures,
) {
  final unread = <String, List<String>>{};
  final alwaysNull = <String, String>{};
  final dates = <String, Set<String>>{};
  byParser.forEach((parser, recs) {
    final read = <String, Set<String>>{};
    final present = <String, Set<String>>{};
    final nonNull = <String, bool>{};
    for (final r in recs) {
      r.presentKeys.forEach(
        (p, ks) => present.putIfAbsent(p, () => {}).addAll(ks),
      );
      for (final a in r.accesses) {
        read.putIfAbsent(a.path, () => {}).add(a.key);
        final k = '$parser: ${a.path}.${a.key}';
        if (a.present) {
          nonNull[k] = (nonNull[k] ?? false) || a.value != null;
          if (a.value != null) alwaysNull.remove(k);
          if (nonNull[k] == false) alwaysNull[k] = '${a.reader} @ ${a.site}';
        }
        if ({'dateTr', 'dateUtc', 'date'}.contains(a.reader) &&
            a.value is String) {
          final v = a.value! as String;
          final offset = RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(v)
              ? 'ofsetli'
              : (v.length <= 10 ? 'tarih' : 'OFSETSİZ');
          dates
              .putIfAbsent(
                '$parser: ${a.path}.${a.key} [${a.reader}] $offset',
                () => {},
              )
              .add('$v @ ${a.site}');
        }
      }
    }
    present.forEach((p, ks) {
      if (!read.containsKey(p)) return; // haritanın kendisi okunmadı
      final miss = ks.difference(read[p]!).toList()..sort();
      if (miss.isNotEmpty) unread['$parser: $p'] = miss;
    });
  });
  return {
    'failures': failures.map((k, v) => MapEntry(k, '$v')),
    'missing': _missingEverywhere(byParser),
    'typeIssues': _typeIssues(byParser),
    'alwaysNull': alwaysNull,
    'unreadServerFields': unread,
    'dates': dates.map((k, v) => MapEntry(k, v.take(2).toList())),
  };
}
