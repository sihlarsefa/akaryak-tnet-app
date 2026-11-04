/// A5 sahte deposu (Onaylarım, Finans, Tahsilat; spec D.4). Ortak dünyayı ([FakeWorld]) okur ve
/// değiştirir: finans kararı siparişin finans durumunu, tahsilat durumu siparişin ödeme durumunu,
/// şirket içi talebin onayı yeni siparişi dünyaya yazar.
///
/// Ek kayıtlar (onay talepleri, finans kartları, çek / senet portföyü) ilk A5 isteğinde eklenir
/// (`world.bag('a5.store')`); böylece A5 uçlarını çağırmayan testler etkilenmez, dev menüsünden
/// "sahte verileri sıfırla" sonrasında depo yeniden tohumlanır.
///
/// Diğer ajanlarla paylaşılan torba: `company.orderRequests` (`CustomerOrderRequestDto` JSON listesi;
/// A3'ün "Talepler" sahteleri aynı torbayı kullanmalıdır, bkz. contract-changes.md A5).
library;

import 'dart:convert';
import 'dart:math';

import '../../../core/auth/permissions.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/models/me_access.dart';
import '../../../core/network/fake/core_fakes.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../customer_orders/customer_orders_fake.dart' show A2Fake;
import '../../field/fake/field_fake_state.dart' show FieldFakeState;
import 'fake_documents.dart';

/// Onay talebinin A5'e özgü sahte durumu (dünyadaki kayıt sunucu satır alanlarını taşır).
class A5ApprovalExtra {
  A5ApprovalExtra({
    required this.token,
    List<JsonMap> steps = const [],
    List<JsonMap>? events,
    this.formKind = 'none',
    JsonMap form = const {},
    this.headline = '',
    this.subline,
    List<JsonMap> facts = const [],
    this.customerFacts,
    List<JsonMap> costFacts = const [],
    List<JsonMap> lines = const [],
    List<String> warnings = const [],
    this.band,
    JsonMap links = const {},
    this.existsElsewhere = false,
  }) : steps = List.of(steps),
       events = List.of(events ?? const <JsonMap>[]),
       form = Map.of(form),
       facts = List.of(facts),
       costFacts = List.of(costFacts),
       lines = List.of(lines),
       warnings = List.of(warnings),
       links = Map.of(links);

  String token;
  final List<JsonMap> steps;
  final List<JsonMap> events;
  final Set<String> deciders = {};
  JsonMap? infoRequest;
  String? decidedAt;
  String? decidedByUserId;
  String? decidedByName;
  String? decisionNote;
  bool conditional = false;

  /// 'payment' (yöntem / vade), 'credit' (limit, yöntemler …) ya da 'none'.
  final String formKind;
  final JsonMap form;
  String headline;
  String? subline;
  final List<JsonMap> facts;

  /// Cari görünümünün satırları (yalnızca cariye yöneltilen türlerde).
  final List<JsonMap>? customerFacts;

  /// Maliyet satırları: yalnızca o formun kararını verebilene (spec B.8).
  final List<JsonMap> costFacts;
  final List<JsonMap> lines;
  final List<String> warnings;
  final JsonMap? band;
  final JsonMap links;

  /// Ön kaydın VKN'si başka bayide kayıtlı ("Merkeze ilet").
  final bool existsElsewhere;
}

class A5FakeStore {
  A5FakeStore._(this.world);

  final FakeWorld world;

  /// Dünyanın deposu (yoksa oluşturup tohumlar).
  static A5FakeStore of(FakeWorld world) =>
      world.bag<A5FakeStore>('a5.store', () => A5FakeStore._(world).._seed());

  /// A3 ile paylaşılan şirket içi sipariş talepleri torbası.
  static const companyRequestsBag = 'company.orderRequests';

  final Map<int, A5ApprovalExtra> approvalExtras = {};

  /// Ön kayıt (yalnızca "Merkeze ilet" alanları; asıl ön kayıt sahteleri A6'nındır).
  final Map<int, JsonMap> leads = {};

  /// Finans kartı ayrıntıları (StationCustomer kimliği → kart alanları, karar ve rapor geçmişi).
  final Map<int, JsonMap> financeCards = {};

  /// Siparişlerin eşzamanlılık belirteçleri (tahsilat durumu).
  final Map<int, String> orderTokens = {};
  final Map<int, List<JsonMap>> paymentHistory = {};
  final List<JsonMap> instruments = [];

  List<JsonMap> get companyRequests =>
      world.bag<List<JsonMap>>(companyRequestsBag, () => <JsonMap>[]);

  final Random _random = Random(41);

  String newToken() => newIdempotencyKey(_random);

  /// Dünyanın sayacıyla çakışmayan yeni sipariş kimliği.
  int newOrderId() {
    var id = world.nextId('order', start: 12001);
    while (world.order(id) != null) {
      id = world.nextId('order', start: 12001);
    }
    return id;
  }

  DateTime _h(num hours) =>
      world.seededAt.add(Duration(minutes: (hours * 60).round()));

  static String utc(DateTime t) => FakeWorld.utc(t);
  static String local(DateTime t) => FakeWorld.local(t);

  // ═══════════════════════════════════════════════════════════════ Tohum

  void _seed() {
    _seedLeads();
    // Roller v5: şirket içi talepler (3001, 2987) ve onların aynaları (9003, 9013) yalnızca eski akışta.
    if (world.companyApprovals) _seedCompanyRequests();
    _seedApprovals();
    _bumpApprovalIds();
    _seedFinanceCards();
    _seedPayments();
  }

  /// Dünyanın onay kimlik sayacı A5'in sabit kimliklerinin (9005–9013) ötesine geçer: sonradan açılan
  /// talepler (ör. teklif limit aşımında finans onayı) aynı kimliği almaz. v4'te depo oturum açılır
  /// açılmaz kurulur (rozet `notifications/unread-count` Bende'yi sayar), teklif akışından önce.
  void _bumpApprovalIds() {
    // 9013 (eski akışın şirket talebi) tohumlanmasa da kimliği ayrılır: yeni talepler iki dünyada aynı
    // kimliği alır.
    var max = 9013;
    for (final a in world.approvals) {
      final id = a['id'];
      if (id is int && id > max) max = id;
    }
    while (world.nextId('approval', start: 9001) < max) {}
  }

  void _seedLeads() {
    leads.addAll({
      8001: {
        'id': 8001,
        'status': LeadStatus.infoRequested.code,
        'title': 'Başkent Yapı Market',
        'existsElsewhere': false,
        'isForwardedToHq': false,
      },
      8002: {
        'id': 8002,
        'status': LeadStatus.submitted.code,
        'title': 'Yıldız Hırdavat Ltd. Şti.',
        'existsElsewhere': false,
        'isForwardedToHq': false,
      },
      8003: {
        'id': 8003,
        'status': LeadStatus.inReview.code,
        'title': 'Akdeniz Gıda Dağıtım A.Ş.',
        'existsElsewhere': true,
        'isForwardedToHq': false,
      },
    });
  }

  void _seedCompanyRequests() {
    final list = companyRequests;
    final o3 = world.orders.where((o) => o['status'] == 3).first;
    JsonMap line({
      required int productId,
      required int pointId,
      required double liters,
      required DateTime date,
      double? price,
      int? orderId,
      String? orderNumber,
      String? error,
    }) => {
      'stationId': 1,
      'productId': productId,
      'deliveryPointId': pointId,
      'quantityLiters': liters,
      'requestedDeliveryDate': local(TrTime.startOfDay(date)),
      'estimatedUnitPrice': price,
      'orderId': orderId,
      'orderNumber': orderNumber,
      'error': error,
      'stationTitle': world.stationTitle(1),
      'productName': world.product(productId)?['name'],
      'deliveryPointName': world.deliveryPoint(pointId)?['name'],
    };
    if (!list.any((r) => r['id'] == 3001)) {
      list.add({
        'id': 3001,
        'concurrencyToken': newToken(),
        'customerId': 101,
        'requestedByUserId': 'u-talep',
        'requestedByName': 'Burak Yılmaz',
        'status': CustomerOrderRequestStatus.pending.code,
        'statusLabel': CustomerOrderRequestStatus.pending.label,
        'totalLiters': 30000.0,
        'estimatedAmount': 1263000.0,
        'note': 'Ay sonu stok için; iki noktaya ayrı teslim.',
        'decidedByName': null,
        'decidedAt': null,
        'decisionNote': null,
        'createdOrderIds': <int>[],
        'createdAt': utc(_h(-0.5)),
        'lines': [
          line(
            productId: 1,
            pointId: 1001,
            liters: 20000,
            date: _h(48),
            price: 42.10,
          ),
          line(
            productId: 3,
            pointId: 1002,
            liters: 10000,
            date: _h(48),
            price: 42.10,
          ),
        ],
        'canDecide': false,
        'canCancel': false,
        'paymentMethodCode': 'HAVALE',
        'paymentMethodName': 'Havale',
        'paymentDisplay': 'Havale / EFT (peşin)',
      });
    }
    // 2987: customer_more sahtesindeki kısmi sonuçlu talep ile aynı numara (birleşik uygulamada
    // `customers/me/order-requests/{id}` onların ucundan okunur).
    if (!list.any((r) => r['id'] == 2987)) {
      list.add({
        'id': 2987,
        'concurrencyToken': newToken(),
        'customerId': 101,
        'requestedByUserId': 'u-talep',
        'requestedByName': 'Burak Yılmaz',
        'status': CustomerOrderRequestStatus.approved.code,
        'statusLabel': CustomerOrderRequestStatus.approved.label,
        'totalLiters': 32000.0,
        'estimatedAmount': 1347200.0,
        'note': null,
        'decidedByName': 'Selin Aydın',
        'decidedAt': utc(_h(-25)),
        'decisionNote':
            'Onaylandı; ikinci satır limit nedeniyle sonra verilecek.',
        'createdOrderIds': [o3['id']],
        'createdAt': utc(_h(-27)),
        'lines': [
          line(
            productId: 1,
            pointId: 1001,
            liters: 20000,
            date: _h(0),
            price: 41.90,
            orderId: o3['id'] as int,
            orderNumber: o3['orderNumber'] as String,
          ),
          line(
            productId: 1,
            pointId: 1002,
            liters: 12000,
            date: _h(24),
            price: 42.10,
            error: 'Aylık limit aşılıyor (2.500.000 ₺).',
          ),
        ],
        'canDecide': false,
        'canCancel': false,
        'paymentMethodCode': 'ACIK_HESAP',
        'paymentMethodName': 'Açık hesap',
        'paymentDisplay': 'Açık hesap · 30 gün',
      });
    }
  }

  JsonMap _fact(String label, String value, [String tone = 'neutral']) => {
    'label': label,
    'value': value,
    'tone': tone,
  };

  JsonMap _step(
    int id,
    int level,
    String name,
    String cap, {
    required int status,
    double? minAmount,
    DateTime? dueAt,
    List<String> eligible = const [],
    String? decidedBy,
    DateTime? decidedAt,
    String? note,
  }) {
    final p = decidedBy == null ? null : world.persona(decidedBy);
    return {
      'id': id,
      'levelNo': level,
      'name': name,
      'capabilityCode': cap,
      'minAmount': minAmount,
      'status': status,
      'dueAt': dueAt == null ? null : utc(dueAt),
      'decidedByUserId': p?.userId,
      'decidedByName': p?.displayName,
      'decidedAt': decidedAt == null ? null : utc(decidedAt),
      'note': note,
      'eligible': [for (final k in eligible) 'u-$k'],
    };
  }

  int _eventSeq = 70000;

  JsonMap event(
    ApprovalEventKind kind, {
    String? userKey,
    String? userId,
    String? userName,
    DateTime? at,
    String? note,
    String? attachmentPublicId,
    String? attachmentFileName,
  }) {
    final p = userKey == null ? null : world.persona(userKey);
    return {
      'id': ++_eventSeq,
      'eventType': kind.code,
      'label': kind.label,
      'stepId': null,
      'userId': p?.userId ?? userId,
      'userName': p?.displayName ?? userName,
      'onBehalfOfUserId': null,
      'onBehalfOfName': null,
      'attachmentPublicId': attachmentPublicId,
      'attachmentFileName': attachmentFileName,
      'note': note,
      'occurredAt': utc(at ?? DateTime.now()),
    };
  }

  JsonMap _approvalRecord({
    required int id,
    required int type,
    required int status,
    required String subjectType,
    required int subjectId,
    String? subjectNumber,
    required String title,
    String? summary,
    double? amount,
    double? liters,
    int? customerId,
    String? customerTitle,
    required String requestedByUserId,
    required String requestedByName,
    required DateTime createdAt,
    DateTime? dueAt,
    int levelCount = 1,
    List<String> eligible = const [],
  }) => {
    'id': id,
    'type': type,
    'status': status,
    'isMirror': type <= 3,
    'stationId': 1,
    'stationTitle': world.stationTitle(1),
    'customerId': customerId,
    'customerTitle': customerTitle ?? world.customerTitle(customerId),
    'subjectType': subjectType,
    'subjectId': subjectId,
    'subjectNumber': subjectNumber,
    'title': title,
    'summary': summary,
    'amount': amount,
    'liters': liters,
    'requestedByUserId': requestedByUserId,
    'requestedByName': requestedByName,
    'createdAt': utc(createdAt),
    'dueAt': dueAt == null ? null : utc(dueAt),
    'slaState': 1,
    'currentLevelNo': 1,
    'levelCount': levelCount,
    'eligibleUserIds': [for (final k in eligible) 'u-$k'],
  };

  void _seedApprovals() {
    final now = world.seededAt;
    final byId = {for (final a in world.approvals) a['id'] as int: a};

    // ---- 9001 Sipariş finans (Marmara İnşaat, bekliyor) ----
    final financeOrder = world.orders.firstWhere(
      (o) => o['financeStatus'] == 1,
    );
    final a9001 = byId[9001];
    if (a9001 != null) {
      final orderNo = financeOrder['orderNumber'] as String;
      // Gerekçeler finans kapısının sırası ve biçimiyle (sunucu `OrderFinanceGate`): bağlantı limiti
      // 1.000.000 ₺, kullanılan 940.000 ₺ (Finans kartıyla aynı) → bu sipariş limiti aşar; çek vadeli
      // yöntemdir; kart koşullu onaylıdır.
      final link = world.link(1, 102);
      final limit = (link?['limitAmount'] as num?)?.toDouble() ?? 0;
      final used = (link?['used'] as num?)?.toDouble() ?? 0;
      final estimated = (financeOrder['estimatedAmount'] as num).toDouble();
      final overrun = used + estimated - limit;
      final reasons = [
        if (overrun > 0) 'Limit aşımı ${Fmt.number(overrun.round())} TL',
        'Vadeli yöntem (Çek, 60 gün)',
        'Koşullu onaylı cari',
      ].join(' · ');
      financeOrder['financeReasons'] = reasons;
      // Satırın özeti sunucunun biçimiyle (`OrderFinanceGate.OrderCommand`).
      a9001['summary'] =
          '${world.customerTitle(102)} · Motorin · ${Fmt.number(25000)} L · Çek 60 gün · '
          'tahmini ${Fmt.number(estimated, minFraction: 2, maxFraction: 2)} TL · Gerekçe: $reasons';
      approvalExtras[9001] = A5ApprovalExtra(
        token: newToken(),
        steps: [
          _step(
            90011,
            1,
            'Finans onayı',
            Caps.approveFinanceOrder,
            status: 1,
            dueAt: _h(5),
            eligible: const ['finans', 'mudur', 'sahip', 'finansuzman'],
          ),
        ],
        events: [
          event(
            ApprovalEventKind.created,
            userName: 'Sistem',
            at: _h(-3),
            note: reasons,
          ),
          event(ApprovalEventKind.viewed, userKey: 'mudur', at: _h(-2)),
        ],
        formKind: 'payment',
        form: const {'method': 'CEK', 'term': 60},
        headline: '$orderNo · Marmara İnşaat Taahhüt Ltd. Şti.',
        subline:
            'Motorin · 25.000 L · teslim ${Fmt.date(TrTime.parseLocal(financeOrder['requestedDeliveryDate'] as String?))}',
        // Bayi / merkez özeti siparişten, bağlantı limitinden ve finans kartından kurulur
        // ([_orderFinanceSummary]); cari görünümünün satırları burada.
        customerFacts: [
          _fact('Sipariş no', orderNo),
          _fact('Bayi', world.stationTitle(1) ?? 'Bayi'),
          _fact('Ürün', 'Motorin'),
          _fact('Miktar', Fmt.liters(25000)),
          _fact('Ödeme', 'Çek · 60 gün'),
        ],
        links: {
          'orderId': financeOrder['id'],
          'customerId': 102,
          'stationCustomerId': 502,
        },
      );
    }

    // ---- 9002 Saha formu kârlılık (Ege Tarım, bekliyor) ----
    if (byId[9002] != null) {
      // QA LF-4: saha sahtesindeki formun numarası ve band sözcüğü (Onaylarım'da tek biçim).
      final n9002 = FieldFakeState.seedFormNumber(world, 7001);
      byId[9002]!
        ..['subjectNumber'] = n9002
        ..['summary'] =
            'Ege Tarım Kooperatifi · 18.000 L · ${FieldFakeState.bandManager}';
      approvalExtras[9002] = A5ApprovalExtra(
        token: newToken(),
        steps: [
          _step(
            90021,
            1,
            FieldFakeState.bandManager,
            Caps.approveFieldManager,
            status: 1,
            dueAt: _h(22.5),
            eligible: const ['satis', 'mudur', 'sahip'],
          ),
        ],
        events: [
          event(ApprovalEventKind.created, userKey: 'saha', at: _h(-1.5)),
        ],
        headline: '$n9002 · Ege Tarım Kooperatifi',
        subline: '2 kalem · 18.000 L · Açık hesap 30 gün',
        facts: [
          _fact('Form no', n9002),
          _fact('Temsilci', 'Deniz Koç'),
          _fact('Toplam miktar', Fmt.liters(18000)),
          _fact('Toplam tutar', Fmt.money(702000)),
          _fact('Ödeme', 'Açık hesap · 30 gün'),
          _fact('Tedarik', 'Tüpraş İzmit · kendi nakliye'),
        ],
        costFacts: [
          _fact('Kâr', Fmt.money(21060), 'ok'),
          _fact('Kâr oranı', '%3', 'warn'),
          _fact(
            'Barem kuralı',
            '${FieldFakeState.bandManager}: %2,5 – %4',
            'warn',
          ),
        ],
        lines: [
          {
            'title': 'Motorin',
            'subtitle': '12.000 L · 39,15 ₺/L',
            'value': Fmt.money(469800),
          },
          {
            'title': 'Kalorifer Yakıtı',
            'subtitle': '6.000 L · 38,70 ₺/L',
            'value': Fmt.money(232200),
          },
        ],
        band: const {
          'key': 'mid',
          'label': FieldFakeState.bandManager,
          'tone': 'warn',
        },
        links: const {'fieldOrderId': 7001, 'customerId': 103},
      );
    }

    // ---- 9003 Şirket içi sipariş talebi (bekliyor) ----
    if (byId[9003] != null) {
      final req = companyRequests.firstWhere((r) => r['id'] == 3001);
      approvalExtras[9003] = A5ApprovalExtra(
        token: newToken(),
        steps: [
          _step(
            90031,
            1,
            'Şirket içi onay',
            Caps.approveCompanyOrder,
            status: 1,
            eligible: const ['onay', 'musteri'],
          ),
        ],
        events: [
          event(ApprovalEventKind.created, userKey: 'talep', at: _h(-0.5)),
        ],
        headline: 'Sipariş talebi #3001 · Burak Yılmaz',
        subline: '2 satır · 30.000 L · tahmini ${Fmt.money(1263000)}',
        facts: [
          _fact('Talep eden', 'Burak Yılmaz'),
          _fact('Durum', 'Onay bekliyor'),
          _fact('Toplam miktar', Fmt.liters(30000)),
          _fact('Tahmini tutar', Fmt.money(1263000)),
          _fact('Ödeme', 'Havale / EFT (peşin)'),
          _fact('Onaylayana not', req['note'] as String),
          _fact('Talep tarihi', Fmt.dateTime(_h(-0.5))),
        ],
        lines: _companyLines(req),
        links: const {'companyRequestId': 3001},
      );
    }

    // ---- 9004 Ön kayıt finans (ek bilgi istendi) ----
    final a9004 = byId[9004];
    if (a9004 != null) {
      final tax = fakeAttachment(
        world,
        ownerType: AttachmentOwnerType.customerLead.code,
        ownerId: 8001,
        kind: AttachmentKind.taxPlate.code,
        fileName: 'vergi-levhasi.png',
        contentType: 'image/png',
        bytes: fakeDocumentPng(accent: 0x64748B, lines: 4),
        uploadedBy: world.persona('saha'),
      );
      tax['createdAt'] = utc(_h(-30));
      tax['canDelete'] = false;
      // Satırlar ek bilgi isteyen tarafı: talep sahibi saha temsilcisi.
      final x = A5ApprovalExtra(
        token: newToken(),
        steps: [
          _step(
            90041,
            1,
            'Ön kayıt finans onayı',
            Caps.approveFinanceLead,
            status: 1,
            dueAt: _h(20),
            eligible: const ['finans', 'sahip'],
          ),
        ],
        events: [
          event(ApprovalEventKind.created, userKey: 'saha', at: _h(-28)),
          event(
            ApprovalEventKind.attachmentViewed,
            userKey: 'finans',
            at: _h(-6),
            attachmentPublicId: tax['publicId'] as String,
            attachmentFileName: 'vergi-levhasi.png',
          ),
          event(
            ApprovalEventKind.infoRequested,
            userKey: 'finans',
            at: _h(-5),
            note:
                'Vergi levhası okunmuyor; güncel ve net bir görüntü yükleyin. · İstenen belge: Vergi levhası',
          ),
        ],
        formKind: 'credit',
        form: {
          'limit': 250000.0,
          'period': 'Aylık',
          'maxTerm': 30,
          'methods': 'HAVALE,CEK',
          'collateral': 0.0,
          'collateralMax': 500,
          'reviewSuggestion': TrTime.isoDate(TrTime.addDays(now, 365)),
          'currentPrefix': 'Talep',
        },
        headline: 'ONK-00008 · Başkent Yapı Market',
        subline: 'Ankara / Çankaya · aylık 40.000 L',
        facts: [
          _fact('Durum', 'Ek bilgi istendi', 'info'),
          _fact('Temsilci', 'Deniz Koç'),
          _fact('VKN', '12******08'),
          _fact('İl / ilçe', 'Ankara / Çankaya'),
          _fact('Aylık ihtiyaç', Fmt.liters(40000)),
          _fact('Talep edilen limit', Fmt.money(250000)),
          _fact('Talep edilen yöntemler', 'Havale / EFT, Çek'),
          _fact('Talep edilen vade', '30 gün'),
          _fact('Risk raporu', 'Bu ön kayıt için risk raporu çekilmedi.'),
        ],
        warnings: const [
          'Temsilciden istenen: vergi levhasının güncel ve okunur görüntüsü.',
        ],
        links: const {'leadId': 8001},
      );
      x.infoRequest = {
        'note': 'Vergi levhası okunmuyor; güncel ve net bir görüntü yükleyin.',
        'kind': AttachmentKind.taxPlate.code,
        'at': utc(_h(-5)),
      };
      approvalExtras[9004] = x;
      a9004['summary'] = 'Başkent Yapı Market · vergi levhası bekleniyor';
    }

    // ---- 9005 Sipariş finans (Anadolu Lojistik; carinin yanıtı bekleniyor) ----
    final infoOrderId = newOrderId();
    final infoOrder = world.newOrder(
      id: infoOrderId,
      customerId: 101,
      stationId: 1,
      deliveryPointId: 1001,
      productId: 1,
      liters: 12000,
      status: OrderStatus.awaitingQuote.code,
      createdAt: _h(-6),
      expiresAt: _h(18),
      requestedDeliveryDate: _h(48),
      paymentMethodCode: 'CEK',
      paymentTermDays: 45,
      financeStatus: OrderFinanceStatus.infoRequested.code,
      financeReasons: 'Vadeli yöntem (Çek, 45 gün)',
      createdByUserId: 'u-musteri',
    );
    infoOrder['financeApprovalRequestId'] = 9005;
    world.orders.add(infoOrder);
    final infoNo = infoOrder['orderNumber'] as String;
    world.approvals.add(
      _approvalRecord(
        id: 9005,
        type: ApprovalType.orderFinance.code,
        status: ApprovalStatus.infoRequested.code,
        subjectType: 'Order',
        subjectId: infoOrderId,
        subjectNumber: infoNo,
        title: 'Sipariş finans onayı',
        summary:
            '${world.customerTitle(101)} · Motorin · ${Fmt.number(12000)} L · Çek 45 gün · '
            'tahmini ${Fmt.number(infoOrder['estimatedAmount'] as double, minFraction: 2, maxFraction: 2)} TL · '
            'Gerekçe: Vadeli yöntem (Çek, 45 gün)',
        amount: infoOrder['estimatedAmount'] as double,
        liters: 12000,
        customerId: 101,
        requestedByUserId: 'u-system',
        requestedByName: 'Anadolu Lojistik (müşteri siparişi)',
        createdAt: _h(-6),
        dueAt: _h(18),
        eligible: const ['finans', 'mudur', 'sahip'],
      ),
    );
    approvalExtras[9005] =
        A5ApprovalExtra(
            token: newToken(),
            steps: [
              _step(
                90051,
                1,
                'Finans onayı',
                Caps.approveFinanceOrder,
                status: 1,
                dueAt: _h(18),
                eligible: const ['finans', 'mudur', 'sahip'],
              ),
            ],
            events: [
              event(
                ApprovalEventKind.created,
                userName: 'Sistem',
                at: _h(-6),
                note: 'Vadeli yöntem (Çek, 45 gün)',
              ),
              event(
                ApprovalEventKind.infoRequested,
                userKey: 'finans',
                at: _h(-2),
                note:
                    'Çek görselini yükleyin; keşide tarihi ve tutar okunur olmalı. · İstenen belge: Çek görseli',
              ),
            ],
            formKind: 'payment',
            form: const {'method': 'CEK', 'term': 45},
            headline: '$infoNo · Anadolu Lojistik A.Ş.',
            subline: 'Motorin · 12.000 L · Çek 45 gün',
            customerFacts: [
              _fact('Sipariş no', infoNo),
              _fact('Bayi', world.stationTitle(1) ?? 'Bayi'),
              _fact('Ürün', 'Motorin'),
              _fact('Miktar', Fmt.liters(12000)),
              _fact('Teslimat noktası', 'Pendik Lojistik Merkezi'),
              _fact(
                'Tahmini tutar',
                Fmt.money(infoOrder['estimatedAmount'] as num),
              ),
              _fact('Ödeme', 'Çek · 45 gün'),
            ],
            links: {
              'orderId': infoOrderId,
              'customerId': 101,
              'stationCustomerId': 501,
            },
          )
          ..infoRequest = {
            'note':
                'Çek görselini yükleyin; keşide tarihi ve tutar okunur olmalı.',
            'kind': AttachmentKind.chequeImage.code,
            'at': utc(_h(-2)),
          };

    // ---- 9006 Saha formu finans (Körfez Nakliyat; süresi geçti) ----
    // Roller v5: finans onayı tek kademe "Finans birimi" (tek imza her tutarı kapsar); eski akışta iki
    // kademe (Finans uzmanı → Finans müdürü 750.000 ₺ üzeri).
    final singleLevel = world.v5Station;
    final n9006 = FieldFakeState.seedFormNumber(world, 7002);
    world.approvals.add(
      _approvalRecord(
        id: 9006,
        type: ApprovalType.fieldFormFinance.code,
        status: ApprovalStatus.pending.code,
        subjectType: 'FieldOrderForm',
        subjectId: 7002,
        subjectNumber: n9006,
        title: 'Saha formu finans onayı',
        summary: 'Açık hesap 30 gün · 20.000 L · limit kullanımı %86',
        amount: 840000,
        liters: 20000,
        customerId: 104,
        requestedByUserId: 'u-saha',
        requestedByName: 'Deniz Koç',
        createdAt: _h(-9),
        dueAt: _h(-1),
        levelCount: singleLevel ? 1 : 2,
        eligible: const ['finans', 'sahip'],
      ),
    );
    approvalExtras[9006] = A5ApprovalExtra(
      token: newToken(),
      steps: [
        _step(
          90061,
          1,
          singleLevel ? 'Finans birimi' : 'Finans uzmanı',
          Caps.approveFinanceOrder,
          status: 1,
          dueAt: _h(-1),
          eligible: const ['finans', 'sahip'],
        ),
        if (!singleLevel)
          _step(
            90062,
            2,
            'Finans müdürü (750.000 ₺ üzeri)',
            Caps.approveFinanceOrder,
            status: 0,
            minAmount: 750000,
            eligible: const ['finans', 'sahip'],
          ),
      ],
      events: [
        event(ApprovalEventKind.created, userKey: 'saha', at: _h(-9)),
        event(
          ApprovalEventKind.reminded,
          userName: 'Sistem',
          at: _h(-3),
          note: 'SLA hatırlatması',
        ),
      ],
      formKind: 'payment',
      form: const {'method': 'ACIK_HESAP', 'term': 30},
      headline: '$n9006 · Körfez Nakliyat ve Ticaret',
      subline: 'Motorin · 20.000 L · Açık hesap 30 gün',
      facts: [
        _fact('Form no', n9006),
        _fact('Temsilci', 'Deniz Koç'),
        _fact('Toplam miktar', Fmt.liters(20000)),
        _fact('Toplam tutar', Fmt.money(840000)),
        _fact('Ödeme', 'Açık hesap · 30 gün'),
        _fact(
          'Finans gerekçesi',
          'Limit kullanımı %86 (750.000 ₺ limit)',
          'warn',
        ),
        _fact('Karşılıksız çek', '1 adet (son 30 gün)', 'danger'),
      ],
      warnings: const [
        'Carinin son 30 günde karşılıksız çeki var (185.000 ₺).',
      ],
      band: const {'key': 'risk-b', 'label': 'Risk sınıfı B', 'tone': 'info'},
      links: const {
        'fieldOrderId': 7002,
        'customerId': 104,
        'stationCustomerId': 504,
      },
    );

    // ---- 9007 Yeni cari finans (Doğu Marmara Gıda; sanal bağlantı 506) ----
    world.approvals.add(
      _approvalRecord(
        id: 9007,
        type: ApprovalType.customerOnboarding.code,
        status: ApprovalStatus.pending.code,
        subjectType: 'StationCustomer',
        subjectId: 506,
        subjectNumber: 'Doğu Marmara Gıda',
        title: 'Yeni cari finans onayı',
        summary: 'Talep edilen limit 400.000 ₺ · risk raporu B',
        amount: 400000,
        customerId: null,
        customerTitle: 'Doğu Marmara Gıda San. A.Ş.',
        requestedByUserId: 'u-satis',
        requestedByName: 'Emre Çelik',
        createdAt: _h(-20),
        dueAt: _h(28),
        eligible: const ['finans', 'sahip'],
      ),
    );
    approvalExtras[9007] = A5ApprovalExtra(
      token: newToken(),
      steps: [
        _step(
          90071,
          1,
          'Yeni cari finans onayı',
          Caps.approveFinanceOnboarding,
          status: 1,
          dueAt: _h(28),
          eligible: const ['finans', 'sahip'],
        ),
      ],
      events: [event(ApprovalEventKind.created, userKey: 'satis', at: _h(-20))],
      formKind: 'credit',
      form: {
        'limit': 400000.0,
        'period': 'Aylık',
        'maxTerm': 30,
        'methods': 'HAVALE,CEK',
        'risk': 2,
        'collateral': 10.0,
        'collateralSuggestion': 25.0,
        'collateralMax': 100,
        'reviewSuggestion': TrTime.isoDate(TrTime.addDays(now, 365)),
        'riskSuggestion': 2,
        'currentPrefix': 'Kartta',
      },
      headline: 'Doğu Marmara Gıda San. A.Ş.',
      subline: 'Yeni cari · Kocaeli / Gebze',
      facts: [
        _fact('VKN', '56******36'),
        _fact('Talep eden', 'Emre Çelik'),
        _fact('Talep edilen limit', Fmt.money(400000)),
        _fact('Önerilen yöntemler', 'Havale / EFT, Çek'),
        _fact('En uzun vade', '30 gün'),
        _fact('Teminat', '%10 · teminat mektubu bekleniyor'),
        _fact('Risk raporu', 'Sınıf B · skor 712 · gecikme yok', 'info'),
      ],
      band: const {'key': 'risk-b', 'label': 'Risk sınıfı B', 'tone': 'info'},
      links: const {'stationCustomerId': 506},
    );

    // ---- 9008 Ön kayıt finans (Yıldız Hırdavat; bekliyor) ----
    world.approvals.add(
      _approvalRecord(
        id: 9008,
        type: ApprovalType.leadFinance.code,
        status: ApprovalStatus.pending.code,
        subjectType: 'CustomerLead',
        subjectId: 8002,
        subjectNumber: 'ONK-00012',
        title: 'Ön kayıt finans onayı',
        summary: 'Yıldız Hırdavat · talep 150.000 ₺ · teminat %150',
        amount: 150000,
        requestedByUserId: 'u-saha',
        requestedByName: 'Deniz Koç',
        createdAt: _h(-4),
        dueAt: _h(44),
        eligible: const ['finans', 'sahip'],
      ),
    );
    approvalExtras[9008] = A5ApprovalExtra(
      token: newToken(),
      steps: [
        _step(
          90081,
          1,
          'Ön kayıt finans onayı',
          Caps.approveFinanceLead,
          status: 1,
          dueAt: _h(44),
          eligible: const ['finans', 'sahip'],
        ),
      ],
      events: [event(ApprovalEventKind.created, userKey: 'saha', at: _h(-4))],
      formKind: 'credit',
      form: {
        'limit': 150000.0,
        'period': 'Aylık',
        'maxTerm': 15,
        'methods': 'HAVALE,KART',
        'collateral': 150.0,
        'collateralMax': 500,
        'reviewSuggestion': TrTime.isoDate(TrTime.addDays(now, 180)),
        'currentPrefix': 'Talep',
      },
      headline: 'ONK-00012 · Yıldız Hırdavat Ltd. Şti.',
      subline: 'Bursa / Osmangazi · aylık 8.000 L',
      facts: [
        _fact('Durum', 'Finansa gönderildi', 'info'),
        _fact('Temsilci', 'Deniz Koç'),
        _fact('VKN', '78******14'),
        _fact('Aylık ihtiyaç', Fmt.liters(8000)),
        _fact('Talep edilen limit', Fmt.money(150000)),
        _fact('Talep edilen yöntemler', 'Havale / EFT, Kredi / banka kartı'),
        _fact('Teminat önerisi', 'Teminat mektubu %150'),
        _fact('Risk raporu', 'Sınıf A · skor 801', 'ok'),
      ],
      band: const {'key': 'risk-a', 'label': 'Risk sınıfı A', 'tone': 'ok'},
      links: const {'leadId': 8002},
    );

    // ---- 9009 Ön kayıt finans (Akdeniz Gıda; VKN başka bayide → merkeze ilet) ----
    world.approvals.add(
      _approvalRecord(
        id: 9009,
        type: ApprovalType.leadFinance.code,
        status: ApprovalStatus.pending.code,
        subjectType: 'CustomerLead',
        subjectId: 8003,
        subjectNumber: 'ONK-00014',
        title: 'Ön kayıt finans onayı',
        summary: 'Akdeniz Gıda · VKN başka bayide kayıtlı',
        amount: 300000,
        requestedByUserId: 'u-saha',
        requestedByName: 'Deniz Koç',
        createdAt: _h(-2),
        dueAt: _h(46),
        eligible: const ['finans', 'sahip'],
      ),
    );
    approvalExtras[9009] = A5ApprovalExtra(
      token: newToken(),
      steps: [
        _step(
          90091,
          1,
          'Ön kayıt finans onayı',
          Caps.approveFinanceLead,
          status: 1,
          dueAt: _h(46),
          eligible: const ['finans', 'sahip'],
        ),
      ],
      events: [event(ApprovalEventKind.created, userKey: 'saha', at: _h(-2))],
      headline: 'ONK-00014 · Akdeniz Gıda Dağıtım A.Ş.',
      subline: 'Antalya / Kepez · aylık 15.000 L',
      facts: [
        _fact('Durum', 'Finans incelemesinde', 'info'),
        _fact('Temsilci', 'Deniz Koç'),
        _fact('VKN', '34******52'),
        _fact('Talep edilen limit', Fmt.money(300000)),
      ],
      warnings: [
        world.firstStageApprovals
            ? 'Bu VKN sistemde başka bir bayide kayıtlı. Cari başka bayiye aktif bağlıysa onaylanamaz (tek bayi kuralı); bu durumda reddedin.'
            : 'Bu VKN sistemde başka bir bayide kayıtlı; cari açılışı merkez onayıyla yapılır. Bayi kademesinde onay verilemez; "Merkeze ilet" ile merkeze iletin ya da reddedin.',
      ],
      links: const {'leadId': 8003},
      existsElsewhere: true,
    );

    // ---- 9010 Limit talebi (bayinin Finans birimi onaylar; sahip kararı 02.11.2026) ----
    // "Limiti de aynı şekilde": limit talebine bayi karar verir, merkez yalnızca izler (sunucu
    // `ApprovalTypes.IsBayiDecided`). Tek kademe "Finans birimi" (approve.finance.limit); Roller v5'te
    // birimin onaycısı (finans) imzalar, talep eden (sahip) imzalamaz. Bayi sahtesinin bekleyen talebi
    // (Marmara İnşaat, `bayi.limitRequests`) bu kayda bağlıdır: karar talebe ve cari limitine geçer.
    world.approvals.add(
      _approvalRecord(
        id: 9010,
        type: ApprovalType.limitChange.code,
        status: ApprovalStatus.pending.code,
        subjectType: 'LimitChangeRequest',
        subjectId: 4001,
        subjectNumber: 'LMT-00041',
        title: 'Limit talebi',
        summary: 'Yeni şantiye; aylık tüketim 35.000 L',
        amount: 1500000,
        customerId: 102,
        requestedByUserId: 'u-sahip',
        requestedByName: 'Mehmet Demir',
        createdAt: _h(-30),
        dueAt: _h(18),
        eligible: const ['finans', 'sahip'],
      ),
    );
    approvalExtras[9010] = A5ApprovalExtra(
      token: newToken(),
      steps: [
        _step(
          90101,
          1,
          'Finans birimi',
          Caps.approveFinanceLimit,
          status: 1,
          dueAt: _h(18),
          eligible: const ['finans', 'sahip'],
        ),
      ],
      events: [event(ApprovalEventKind.created, userKey: 'sahip', at: _h(-30))],
      // Sunucu `LimitChangeSummaryBuilder`: cari · bayi, alt satır, satırlar ve bağlantılar.
      headline:
          'Marmara İnşaat Taahhüt Ltd. Şti. · ${world.stationTitle(1) ?? 'Bayi'}',
      subline: 'Limit değişikliği talebi · bayi Finans birimi onayı',
      facts: [
        _fact('Cari', 'Marmara İnşaat Taahhüt Ltd. Şti.'),
        _fact('Mevcut limit', 'Aylık ${Fmt.moneyWhole(1000000)}'),
        _fact('Talep edilen limit', 'Aylık ${Fmt.moneyWhole(1500000)}', 'info'),
        _fact(
          'Geçerli dönem kullanımı',
          '${Fmt.moneyWhole(940000)} / ${Fmt.moneyWhole(1000000)} · %94 · Aylık',
          'warn',
        ),
        _fact('Gerekçe', 'Yeni şantiye; aylık tüketim 35.000 L'),
        _fact('Talep eden', 'Mehmet Demir'),
        _fact('Durum', 'Bekliyor'),
      ],
      links: const {
        'customerId': 102,
        'stationCustomerId': 502,
        'limitRequestId': 4001,
      },
    );

    // ---- 9011 Karar verilmiş: sipariş finans onaylandı (finans, 2 gün önce) ----
    world.approvals.add(
      _approvalRecord(
        id: 9011,
        type: ApprovalType.orderFinance.code,
        status: ApprovalStatus.approved.code,
        subjectType: 'Order',
        subjectId:
            world.orders.firstWhere((o) => o['status'] == 3)['id'] as int,
        subjectNumber:
            world.orders.firstWhere((o) => o['status'] == 3)['orderNumber']
                as String,
        title: 'Sipariş finans onayı',
        summary: 'Açık hesap · 30 gün',
        amount: 838000,
        liters: 20000,
        customerId: 101,
        requestedByUserId: 'u-system',
        requestedByName: 'Anadolu Lojistik (müşteri siparişi)',
        createdAt: _h(-50),
        eligible: const [],
      )..['slaState'] = 0,
    );
    approvalExtras[9011] =
        A5ApprovalExtra(
            token: newToken(),
            steps: [
              _step(
                90111,
                1,
                'Finans onayı',
                Caps.approveFinanceOrder,
                status: 2,
                decidedBy: 'finans',
                decidedAt: _h(-48),
                note: 'Limit ve vade uygun.',
              ),
            ],
            events: [
              event(ApprovalEventKind.created, userName: 'Sistem', at: _h(-50)),
              event(
                ApprovalEventKind.approved,
                userKey: 'finans',
                at: _h(-48),
                note: 'Limit ve vade uygun.',
              ),
            ],
            headline:
                '${world.orders.firstWhere((o) => o['status'] == 3)['orderNumber']} · Anadolu Lojistik A.Ş.',
            subline: 'Motorin · 20.000 L',
            facts: [
              _fact('Ürün', 'Motorin'),
              _fact('Miktar', Fmt.liters(20000)),
              _fact('Ödeme', 'Açık hesap · 30 gün'),
              _fact('Finans durumu', 'Finans onaylandı', 'ok'),
            ],
            customerFacts: [
              _fact('Ürün', 'Motorin'),
              _fact('Miktar', Fmt.liters(20000)),
              _fact('Ödeme', 'Açık hesap · 30 gün'),
            ],
            links: {
              'orderId': world.orders.firstWhere((o) => o['status'] == 3)['id'],
              'customerId': 101,
              'stationCustomerId': 501,
            },
          )
          ..deciders.add('u-finans')
          ..decidedAt = utc(_h(-48))
          ..decidedByUserId = 'u-finans'
          ..decidedByName = 'Can Öztürk'
          ..decisionNote = 'Limit ve vade uygun.';

    // ---- 9012 Karar verilmiş: saha formu reddedildi (satış müdürü) ----
    final n9012 = FieldFakeState.seedFormNumber(world, 6998);
    world.approvals.add(
      _approvalRecord(
        id: 9012,
        type: ApprovalType.fieldOrderProfit.code,
        status: ApprovalStatus.rejected.code,
        subjectType: 'FieldOrderForm',
        subjectId: 6998,
        subjectNumber: n9012,
        title: 'Saha formu kârlılık onayı',
        summary:
            'Körfez Nakliyat ve Ticaret · 9.000 L · ${FieldFakeState.bandManager}',
        amount: 362000,
        liters: 9000,
        customerId: 104,
        requestedByUserId: 'u-saha',
        requestedByName: 'Deniz Koç',
        createdAt: _h(-80),
        eligible: const [],
      )..['slaState'] = 0,
    );
    approvalExtras[9012] =
        A5ApprovalExtra(
            token: newToken(),
            steps: [
              _step(
                90121,
                1,
                FieldFakeState.bandManager,
                Caps.approveFieldManager,
                status: 3,
                decidedBy: 'satis',
                decidedAt: _h(-76),
                note: 'Fiyat barem dışında; yeni teklifle tekrar gönderin.',
              ),
            ],
            events: [
              event(ApprovalEventKind.created, userKey: 'saha', at: _h(-80)),
              event(
                ApprovalEventKind.rejected,
                userKey: 'satis',
                at: _h(-76),
                note: 'Fiyat barem dışında; yeni teklifle tekrar gönderin.',
              ),
            ],
            headline: '$n9012 · Körfez Nakliyat ve Ticaret',
            subline: 'Motorin · 9.000 L',
            facts: [
              _fact('Form no', n9012),
              _fact('Toplam tutar', Fmt.money(362000)),
              _fact('Ödeme', 'Açık hesap · 45 gün'),
            ],
            band: const {
              'key': 'mid',
              'label': FieldFakeState.bandManager,
              'tone': 'warn',
            },
            links: const {'fieldOrderId': 6998, 'customerId': 104},
          )
          ..deciders.add('u-satis')
          ..decidedAt = utc(_h(-76))
          ..decidedByUserId = 'u-satis'
          ..decidedByName = 'Emre Çelik'
          ..decisionNote =
              'Fiyat barem dışında; yeni teklifle tekrar gönderin.';

    // ---- 9013 Karar verilmiş: şirket içi talep onaylandı (kısmi; yalnızca eski akışta) ----
    if (world.companyApprovals) _seedCompanyDecision();
  }

  void _seedCompanyDecision() {
    final done = companyRequests.firstWhere((r) => r['id'] == 2987);
    world.approvals.add(
      _approvalRecord(
        id: 9013,
        type: ApprovalType.companyOrderRequest.code,
        status: ApprovalStatus.approved.code,
        subjectType: 'CustomerOrderRequest',
        subjectId: 2987,
        subjectNumber: 'TLP-00029',
        title: 'Şirket içi sipariş talebi',
        summary: '32.000 L Motorin · 2 nokta',
        amount: 1347200,
        liters: 32000,
        customerId: 101,
        requestedByUserId: 'u-talep',
        requestedByName: 'Burak Yılmaz',
        createdAt: _h(-27),
        eligible: const [],
      )..['slaState'] = 0,
    );
    approvalExtras[9013] =
        A5ApprovalExtra(
            token: newToken(),
            steps: [
              _step(
                90131,
                1,
                'Şirket içi onay',
                Caps.approveCompanyOrder,
                status: 2,
                decidedBy: 'musteri',
                decidedAt: _h(-25),
              ),
            ],
            events: [
              event(ApprovalEventKind.created, userKey: 'talep', at: _h(-27)),
              event(
                ApprovalEventKind.approved,
                userKey: 'musteri',
                at: _h(-25),
                note: done['decisionNote'] as String?,
              ),
            ],
            headline: 'Sipariş talebi #2987 · Burak Yılmaz',
            subline: '2 satır · 32.000 L',
            facts: [
              _fact('Talep eden', 'Burak Yılmaz'),
              _fact('Durum', 'Onaylandı', 'ok'),
              _fact('Toplam miktar', Fmt.liters(32000)),
              _fact('Ödeme', 'Açık hesap · 30 gün'),
            ],
            lines: _companyLines(done),
            warnings: const [
              '1 satır siparişe dönüşemedi; başarısız satırları yeni siparişe aktarabilirsiniz.',
            ],
            links: {
              'companyRequestId': 2987,
              'orderId': (done['createdOrderIds'] as List).first,
            },
          )
          ..deciders.add('u-musteri')
          ..decidedAt = utc(_h(-25))
          ..decidedByUserId = 'u-musteri'
          ..decidedByName = 'Selin Aydın'
          ..decisionNote = done['decisionNote'] as String?;
  }

  List<JsonMap> _companyLines(JsonMap req) => [
    for (final l in (req['lines'] as List).cast<JsonMap>())
      {
        'title': l['productName'] ?? 'Ürün',
        'subtitle': [
          l['stationTitle'],
          l['deliveryPointName'],
          Fmt.date(TrTime.parseLocal(l['requestedDeliveryDate'] as String?)),
        ].whereType<String>().join(' · '),
        'value': [
          Fmt.liters(l['quantityLiters'] as num),
          if (l['estimatedUnitPrice'] != null)
            Fmt.unitPrice(l['estimatedUnitPrice'] as num),
          if (l['orderNumber'] != null) 'Sipariş ${l['orderNumber']}',
          if (l['orderNumber'] == null && l['error'] != null)
            'Oluşturulamadı: ${l['error']}',
        ].join(' · '),
      },
  ];

  // ═══════════════════════════════════════════════════════════════ Onay kuralları

  A5ApprovalExtra extraOf(JsonMap a) => approvalExtras.putIfAbsent(
    a['id'] as int,
    () => A5ApprovalExtra(
      token: newToken(),
      headline: (a['subjectNumber'] ?? a['title'] ?? '') as String,
      events: [
        event(
          ApprovalEventKind.created,
          userId: a['requestedByUserId'] as String?,
          userName: a['requestedByName'] as String?,
          at: TrTime.parseUtc(a['createdAt'] as String?),
        ),
      ],
    ),
  );

  static bool _isOpen(JsonMap a) => a['status'] == 0 || a['status'] == 4;

  static bool isFinanceType(int type) =>
      type == ApprovalType.orderFinance.code ||
      type == ApprovalType.fieldFormFinance.code ||
      type == ApprovalType.customerOnboarding.code ||
      type == ApprovalType.leadFinance.code;

  /// Bayide karara bağlanan türler (sunucu `ApprovalTypes.IsBayiDecided`; sahip kararı 04.11.2026 "admin
  /// onayı olmaz"): şirket içi talep dışında tümü. Merkez karar vermez, yalnızca izler. Eski akış
  /// ([FakeWorld.firstStageApprovals] kapalı): limit talebi ve yeni cari onayı.
  bool isBayiDecided(int type) => world.firstStageApprovals
      ? type != ApprovalType.companyOrderRequest.code
      : type == ApprovalType.limitChange.code ||
            type == ApprovalType.customerOnboarding.code;

  static bool isCustomerAddressed(int type) =>
      type == ApprovalType.orderFinance.code ||
      type == ApprovalType.customerOnboarding.code;

  /// Talebi görebilir mi (gelen kutusu kapsamı).
  bool visible(FakePersona p, JsonMap a) {
    // Sahip kararı 04.11.2026: limit, saha formu finansı ve yeni cari onayı artık açılmaz; eski örnekler görünmez.
    if (world.firstStageApprovals && const {2, 5, 6}.contains(a['type'])) {
      return false;
    }
    switch (p.persona) {
      case Persona.platform:
        return true;
      case Persona.bayi:
        // Şirket içi sipariş talebi carinin kendi onayıdır; bayi görmez.
        return a['stationId'] == p.stationId &&
            a['type'] != ApprovalType.companyOrderRequest.code &&
            p.can(Pg.stationApprovals);
      case Persona.customer:
        if (a['customerId'] != p.customerId) return false;
        final type = a['type'] as int;
        if (type == ApprovalType.companyOrderRequest.code) {
          return p.can(Pg.customerApprovals);
        }
        return isCustomerAddressed(type);
      case Persona.unknown:
        return false;
    }
  }

  /// Cari görünümü: cari kullanıcısı bayi tarafındaki bir talebe bakıyor.
  static bool customerView(FakePersona p, JsonMap a) =>
      p.persona == Persona.customer &&
      a['type'] != ApprovalType.companyOrderRequest.code;

  /// Sahip kararı 04.11.2026 (sunucu `ApprovalEligibility.Check`): Bayi yöneticisi kendi bayisinde her bayi onayını
  /// verir; birim onaycısı, dört göz ve kendi talebi kuralı ona uygulanmaz.
  bool _managerSigns(FakePersona p, JsonMap a) =>
      world.isBayiManager(p) &&
      a['stationId'] == p.stationId &&
      isBayiDecided(a['type'] as int);

  bool _eligible(FakePersona p, JsonMap a) {
    if (_managerSigns(p, a)) return true;
    // Limit talebi ve yeni cari onayında merkez karar vermez (yükseltilse de; sunucu `Check`).
    if (p.persona == Persona.platform && isBayiDecided(a['type'] as int)) {
      return false;
    }
    if (_listed(p, a)) return world.signsStep(p, _stepCapability(a));
    return p.persona == Persona.platform && a['escalated'] == true;
  }

  /// Talebin uygunlar listesinde mi (yetkinliği taşıyanlar; roller v5 süzgecinden önce).
  static bool _listed(FakePersona p, JsonMap a) =>
      ((a['eligibleUserIds'] as List?) ?? const []).contains(p.userId);

  /// Şu anki kademenin yetkinliği (adım yoksa talebin türünden).
  String? _stepCapability(JsonMap a) {
    final level = (a['currentLevelNo'] as int?) ?? 1;
    final step = approvalExtras[a['id']]?.steps
        .where((s) => s['levelNo'] == level)
        .firstOrNull;
    final code = step?['capabilityCode'] as String?;
    return code == null || code.isEmpty
        ? FakeWorld.approvalCapability(a)
        : code;
  }

  /// Roller v5: personanın imzasını engelleyen birim onaycısı (listede ama birimin onaycısı başkası);
  /// ipucu "Bu birimin onaycısı {Ad}; talebi o onaylar." (sunucu `ApprovalDecisionHints.UnitApprover`).
  FakePersona? _blockingApprover(FakePersona p, JsonMap a) {
    if (!_listed(p, a)) return null;
    final code = _stepCapability(a);
    if (world.signsStep(p, code)) return null;
    return world.blockingApprover(p, code);
  }

  /// Kademeye uygun yetkinliğin tutar sınırı aşılıyor mu.
  bool _overLimit(FakePersona p, JsonMap a) {
    if (p.persona == Persona.platform) return false;
    final cap = switch (a['type'] as int) {
      4 || 5 => Caps.approveFinanceOrder,
      6 => Caps.approveFinanceOnboarding,
      7 => Caps.approveFinanceLead,
      _ => null,
    };
    if (cap == null || !p.capabilities.containsKey(cap)) return false;
    final limit = p.capabilities[cap];
    final amount = (a['amount'] as num?)?.toDouble() ?? 0;
    return limit != null && amount > limit;
  }

  /// Talep eden tarafı mı (ek bilgi yanıtını verir).
  bool isRespondent(FakePersona p, JsonMap a) {
    if (a['status'] != ApprovalStatus.infoRequested.code) return false;
    if (a['requestedByUserId'] == p.userId) return true;
    return p.persona == Persona.customer &&
        isCustomerAddressed(a['type'] as int) &&
        a['customerId'] == p.customerId;
  }

  List<int> modesFor(FakePersona p, JsonMap a) {
    if (!_isOpen(a) || !visible(p, a)) return const [];
    if (customerView(p, a)) return const [];
    final x = extraOf(a);
    final manager = _managerSigns(p, a);
    if (!manager && a['requestedByUserId'] == p.userId) return const [];
    if (!manager && x.deciders.contains(p.userId)) return const [];
    if (!_eligible(p, a)) return const [];
    if (a['status'] == ApprovalStatus.infoRequested.code) {
      return [ApprovalDecision.reject.code];
    }
    if (_overLimit(p, a)) return const [];
    final type = a['type'] as int;
    if (isFinanceType(type)) {
      if (x.existsElsewhere) {
        return [
          ApprovalDecision.requestInfo.code,
          ApprovalDecision.reject.code,
        ];
      }
      return [
        ApprovalDecision.approve.code,
        ApprovalDecision.conditionalApprove.code,
        ApprovalDecision.requestInfo.code,
        ApprovalDecision.reject.code,
      ];
    }
    return [ApprovalDecision.approve.code, ApprovalDecision.reject.code];
  }

  bool canResume(FakePersona p, JsonMap a) =>
      a['status'] == ApprovalStatus.infoRequested.code &&
      visible(p, a) &&
      !customerView(p, a) &&
      !isRespondent(p, a) &&
      _eligible(p, a);

  bool canProvide(FakePersona p, JsonMap a) =>
      visible(p, a) && isRespondent(p, a);

  /// Ek bilgi yanıtı bu kadar saat gelmeyince onaylayan tarafı da talebi Bende'de görür (sunucu
  /// `ApprovalEngine.InfoReminderHours`).
  static const infoReminderHours = 48;

  /// Ek bilginin istendiği an (sunucuda `UpdatedAt ?? CreatedAt`).
  DateTime? _infoAskedAt(JsonMap a) =>
      TrTime.parseUtc(extraOf(a).infoRequest?['at'] as String?) ??
      TrTime.parseUtc(a['updatedAt'] as String?) ??
      TrTime.parseUtc(a['createdAt'] as String?);

  /// Kullanıcıdan bir işlem bekleniyor mu ("Bende", rozet; sunucu
  /// `ApprovalInboxService.ActionableAsync`, v4 B5). Bekleyen talepte: karar verebiliyorsa. Ek bilgi
  /// bekleyen talepte: yanıtı o veriyorsa (talep eden tarafı); onaylayan tarafına yalnızca talebin
  /// talep edeni yoksa ya da yanıt [infoReminderHours] saattir gelmediyse ("Bilgi alındı" ya da
  /// ret). Başkasının yanıtını bekleyen talep (saha temsilcisinin vergi levhası, carinin çeki) Bende'de
  /// görünmez ve sayılmaz.
  bool needsAction(FakePersona p, JsonMap a) {
    if (a['status'] == ApprovalStatus.infoRequested.code) {
      if (canProvide(p, a)) return true;
      if (!canResume(p, a)) return false;
      final requester = a['requestedByUserId'] as String?;
      if (requester == null || requester.isEmpty) return true;
      final asked = _infoAskedAt(a);
      return asked != null &&
          !asked.isAfter(
            DateTime.now().toUtc().subtract(
              const Duration(hours: infoReminderHours),
            ),
          );
    }
    return modesFor(p, a).isNotEmpty;
  }

  /// Kararlarım (sunucu `DecidedByMe`): bir kademesine karar verdiğim, sonuçlandırdığım ya da ek
  /// bilgi istediğim talepler — ek bilgi isteyen, yanıt bekleyen talebi burada bulur.
  bool decidedBy(FakePersona p, JsonMap a) {
    final x = extraOf(a);
    return x.deciders.contains(p.userId) ||
        x.decidedByUserId == p.userId ||
        x.events.any(
          (e) =>
              e['eventType'] == ApprovalEventKind.infoRequested.code &&
              e['userId'] == p.userId,
        );
  }

  String? hintFor(FakePersona p, JsonMap a) {
    if (!_isOpen(a) || modesFor(p, a).isNotEmpty) return null;
    final x = extraOf(a);
    final type = a['type'] as int;
    if (customerView(p, a)) {
      if (a['status'] == ApprovalStatus.infoRequested.code) {
        return canProvide(p, a)
            ? 'Sizden ek bilgi istendi; istenen bilgiyi ya da belgeyi ekleyip yanıtlayın.'
            : 'Talep ek bilgi bekliyor; yanıt gelince bayi değerlendirmeyi sürdürür.';
      }
      return 'Talep bayinin ${isFinanceType(type) ? 'finans ekibinde' : 'yetkililerinde'} değerlendiriliyor; sonuç size bildirilir.';
    }
    if (a['status'] == ApprovalStatus.infoRequested.code) {
      return canProvide(p, a)
          ? 'Sizden ek bilgi istendi; istenen bilgiyi ya da belgeyi ekleyip yanıtlayın.'
          : 'Talep ek bilgi bekliyor; yanıt gelince karar verilebilir.';
    }
    // Sahip kararı 02.11.2026: merkez limit talebini ve yeni cari onayını izler, kararı bayi verir
    // (sunucu `ApprovalDecisionHints.BayiDecides`).
    if (p.persona == Persona.platform && isBayiDecided(type)) {
      return 'Bu talebe bayi karar verir; merkez yalnızca izler.';
    }
    if (!_managerSigns(p, a) && a['requestedByUserId'] == p.userId) {
      return 'Kendi talebinizi onaylayamazsınız.';
    }
    if (x.deciders.contains(p.userId)) {
      return 'Bu talepte bir kademeyi zaten onayladınız; sonraki kademeyi başka biri onaylamalı.';
    }
    if (type == ApprovalType.companyOrderRequest.code) {
      return 'Sipariş talebini şirketinizin onaylayanı ya da yöneticisi onaylar.';
    }
    final designee = _blockingApprover(p, a);
    if (designee != null) {
      return 'Bu birimin onaycısı ${designee.displayName}; talebi o onaylar.';
    }
    if (_eligible(p, a) && _overLimit(p, a)) {
      return 'Tutar onay sınırınızı aşıyor.';
    }
    if (type == ApprovalType.fieldOrderProfit.code) {
      return 'Bu kademede karar verme yetkiniz yok.';
    }
    return 'Bu kademede karar verme yetkiniz yok.';
  }

  int _sla(JsonMap a) {
    if (!_isOpen(a)) return ApprovalSlaState.none.code;
    final due = TrTime.parseUtc(a['dueAt'] as String?);
    if (due == null) return ApprovalSlaState.none.code;
    final left = due.difference(DateTime.now().toUtc());
    if (left.isNegative) return ApprovalSlaState.overdue.code;
    if (left < const Duration(hours: 6)) return ApprovalSlaState.dueSoon.code;
    return ApprovalSlaState.onTime.code;
  }

  /// Kapsama göre görünen talepler (Bende: süre sırası; diğerleri yeniden eskiye).
  List<JsonMap> inbox(FakePersona p, int scope) {
    final list = <JsonMap>[];
    for (final a in world.approvals) {
      if (!visible(p, a)) continue;
      final ok = switch (scope) {
        0 => needsAction(p, a),
        1 => a['requestedByUserId'] == p.userId,
        2 => decidedBy(p, a),
        _ => true,
      };
      if (ok) list.add(a);
    }
    int created(JsonMap a) =>
        TrTime.parseUtc(a['createdAt'] as String?)?.millisecondsSinceEpoch ?? 0;
    if (scope == 0) {
      int due(JsonMap a) =>
          TrTime.parseUtc(a['dueAt'] as String?)?.millisecondsSinceEpoch ??
          (1 << 52);
      list.sort((a, b) {
        final c = due(a).compareTo(due(b));
        return c != 0 ? c : created(b).compareTo(created(a));
      });
    } else {
      list.sort((a, b) => created(b).compareTo(created(a)));
    }
    return list;
  }

  bool _isCompanyUser(FakePersona viewer, String? userId) {
    if (userId == null) return false;
    final other = world.personaByUserId(userId);
    return other != null &&
        other.persona == Persona.customer &&
        other.customerId == viewer.customerId;
  }

  /// `ApprovalInboxRowDto` JSON (cari tarafında ayıklanmış).
  JsonMap row(FakePersona p, JsonMap a) {
    final cv = customerView(p, a);
    final type = ApprovalType.fromCode(a['type'] as int?);
    final status = ApprovalStatus.fromCode(a['status'] as int?);
    final requesterVisible =
        !cv || _isCompanyUser(p, a['requestedByUserId'] as String?);
    return {
      'id': a['id'],
      'type': a['type'],
      'typeLabel': type.shortLabel,
      'status': a['status'],
      'statusLabel': status.label,
      'isMirror': a['isMirror'] ?? false,
      'stationId': a['stationId'],
      'stationTitle': a['stationTitle'],
      'customerId': a['customerId'],
      'customerTitle': a['customerTitle'],
      'subjectType': a['subjectType'],
      'subjectId': a['subjectId'],
      'subjectNumber': a['subjectNumber'],
      'title': a['title'],
      'summary': cv ? null : a['summary'],
      'amount': cv && type == ApprovalType.customerOnboarding
          ? null
          : a['amount'],
      'liters': a['liters'],
      'requestedByUserId': requesterVisible ? a['requestedByUserId'] : null,
      'requestedByName': requesterVisible ? a['requestedByName'] : null,
      'createdAt': a['createdAt'],
      'dueAt': cv ? null : a['dueAt'],
      'slaState': cv ? 0 : _sla(a),
      'currentLevelNo': cv ? 1 : a['currentLevelNo'] ?? 1,
      'levelCount': cv ? 1 : a['levelCount'] ?? 1,
      'canDecide': modesFor(p, a).isNotEmpty,
    };
  }

  /// `ApprovalMobileDetailDto` JSON.
  JsonMap detail(FakePersona p, JsonMap a) {
    final x = extraOf(a);
    final cv = customerView(p, a);
    final modes = modesFor(p, a);
    final type = a['type'] as int;
    final base = row(p, a);
    final attachments = [
      for (final att in world.attachments)
        if (att['isActive'] == true &&
            ((att['ownerType'] == AttachmentOwnerType.approvalRequest.code &&
                    att['ownerId'] == a['id']) ||
                _subjectAttachment(a, att)))
          {...att, 'canDelete': att['uploadedByUserId'] == p.userId},
    ];
    JsonMap? info;
    final ir = x.infoRequest;
    if (a['status'] == ApprovalStatus.infoRequested.code && ir != null) {
      final kind = ir['kind'] as int?;
      final at = TrTime.parseUtc(ir['at'] as String?);
      info = {
        'note': ir['note'],
        'requiredAttachmentKind': kind,
        'requiredKindLabel': kind == null
            ? null
            : AttachmentKind.fromCode(kind).label,
        'requestedAt': ir['at'],
        'requiredKindUploaded':
            kind != null &&
            attachments.any(
              (att) =>
                  att['kind'] == kind &&
                  (TrTime.parseUtc(
                        att['createdAt'] as String?,
                      )?.isAfter(at ?? DateTime(2000)) ??
                      false),
            ),
      };
    }
    final steps = cv
        ? [
            for (final s in x.steps)
              {
                ...s,
                'name': 'Bayi değerlendirmesi',
                'capabilityCode': '',
                'decidedByUserId': null,
                'decidedByName': null,
                'onBehalfOfUserId': null,
                'onBehalfOfName': null,
                'note': null,
                'eligible': null,
              },
          ]
        : [for (final s in x.steps) Map.of(s)..remove('eligible')];
    final events = cv
        ? [
            for (final e in x.events)
              if (e['eventType'] == ApprovalEventKind.created.code ||
                  e['eventType'] == ApprovalEventKind.infoRequested.code ||
                  e['eventType'] == ApprovalEventKind.infoProvided.code)
                {
                  ...e,
                  'userId': _isCompanyUser(p, e['userId'] as String?)
                      ? e['userId']
                      : null,
                  'userName': _isCompanyUser(p, e['userId'] as String?)
                      ? e['userName']
                      : null,
                  'note': e['eventType'] == ApprovalEventKind.infoProvided.code
                      ? (_isCompanyUser(p, e['userId'] as String?)
                            ? e['note']
                            : null)
                      : e['note'],
                },
          ]
        : x.events;
    final decisionVisible = !cv || a['status'] == ApprovalStatus.rejected.code;
    return {
      ...base,
      'summaryText': cv ? null : a['summary'],
      'concurrencyToken': x.token,
      'contextJson': null,
      'decidedAt': x.decidedAt,
      'decidedByUserId': cv ? null : x.decidedByUserId,
      'decidedByName': cv ? null : x.decidedByName,
      'decisionNote': decisionVisible ? x.decisionNote : null,
      'steps': steps,
      'events': events,
      'attachments': attachments,
      'modes': modes,
      'modeLabels': [for (final m in modes) ApprovalDecision.fromCode(m).label],
      'onBehalfOfUserId': null,
      'onBehalfOfName': null,
      'canProvideInfo': canProvide(p, a),
      'canResumeInfo': canResume(p, a),
      'summary': _summary(p, a, x, canDecide: modes.isNotEmpty),
      'customerView': cv,
      'infoRequest': info,
      'conditionForm':
          !cv && modes.contains(ApprovalDecision.conditionalApprove.code)
          ? _conditionForm(type, x)
          : null,
      'decisionHint': hintFor(p, a),
    };
  }

  bool _subjectAttachment(JsonMap a, JsonMap att) {
    final subjectType = a['subjectType'] as String?;
    final id = a['subjectId'];
    return switch (subjectType) {
      'Order' =>
        att['ownerType'] == AttachmentOwnerType.order.code &&
            att['ownerId'] == id,
      'CustomerLead' =>
        att['ownerType'] == AttachmentOwnerType.customerLead.code &&
            att['ownerId'] == id,
      'FieldOrderForm' =>
        att['ownerType'] == AttachmentOwnerType.fieldOrderForm.code &&
            att['ownerId'] == id,
      _ => false,
    };
  }

  JsonMap _summary(
    FakePersona p,
    JsonMap a,
    A5ApprovalExtra x, {
    required bool canDecide,
  }) {
    final cv = customerView(p, a);
    final status = ApprovalStatus.fromCode(a['status'] as int?);
    if (cv) {
      final statusText = switch (status) {
        ApprovalStatus.pending =>
          isFinanceType(a['type'] as int)
              ? 'Bayinin finans değerlendirmesinde'
              : 'Bayinin değerlendirmesinde',
        ApprovalStatus.infoRequested =>
          canProvide(p, a)
              ? 'Sizden ek bilgi bekleniyor'
              : 'Bayi ek bilgi bekliyor',
        ApprovalStatus.approved =>
          x.conditional ? 'Koşullu onaylandı' : 'Onaylandı',
        ApprovalStatus.rejected => 'Reddedildi',
        _ => 'Kapatıldı',
      };
      final orderNo = a['subjectNumber'] as String?;
      return {
        'headline': [
          ?orderNo,
          a['stationTitle'] as String?,
        ].whereType<String>().join(' · '),
        'subline': status == ApprovalStatus.infoRequested
            ? 'Finans ekibi siparişiniz için ek bilgi / belge istedi. Belgeyi ekleyip yanıtlayın.'
            : 'Siparişiniz bayinin finans değerlendirmesinden geçiyor.',
        'amount': a['type'] == ApprovalType.customerOnboarding.code
            ? null
            : a['amount'],
        'liters': a['liters'],
        'facts': [
          ...?x.customerFacts,
          _fact('Durum', statusText, switch (status) {
            ApprovalStatus.approved => 'ok',
            ApprovalStatus.rejected => 'danger',
            ApprovalStatus.infoRequested => 'info',
            _ => 'warn',
          }),
        ],
        'lines': const <JsonMap>[],
        'warnings': const <String>[],
        'band': null,
        'links': {
          if (x.links['orderId'] != null) 'orderId': x.links['orderId'],
          if (x.links['companyRequestId'] != null)
            'companyRequestId': x.links['companyRequestId'],
        },
      };
    }
    // Sipariş finansı (bayi / merkez): sunucunun `OrderFinanceSummaryBuilder` aynası — satırlar
    // anahtarlı, `summary.finance` dolu; sipariş, bağlantı limiti ve finans kartından her istekte
    // yeniden kurulur (karardan sonra da güncel).
    final order = a['type'] == ApprovalType.orderFinance.code
        ? _subjectOrder(a)
        : null;
    if (order != null && order['financeApprovalRequestId'] == a['id']) {
      return _orderFinanceSummary(p, a, x, order);
    }
    final facts = [
      ...x.facts,
      // Marj satırları yalnızca bu formun kararını verebilene.
      if (canDecide) ...x.costFacts,
    ];
    return {
      'headline': x.headline,
      'subline': x.subline,
      'amount': a['amount'],
      'liters': a['liters'],
      'facts': facts,
      'lines': x.lines,
      'warnings': x.warnings,
      'band': x.band,
      'links': x.links,
    };
  }

  JsonMap _key(
    String label,
    String value,
    String key, [
    String tone = 'neutral',
  ]) => {'label': label, 'value': value, 'tone': tone, 'key': key};

  /// Sunucu `ApprovalText.ReasonTone`: limit aşımı tehlike, vadeli uyarı, diğerleri bilgi.
  static String _reasonTone(String r) => r.startsWith('Limit aşımı')
      ? 'danger'
      : (r.startsWith('Vadeli') ? 'warn' : 'info');

  /// Sunucu `ApprovalFinanceReasonKinds.Of`.
  static String _reasonKind(String r) {
    bool s(String p) => r.startsWith(p);
    if (s('Limit aşımı')) return 'limitOverrun';
    if (s('Vadeli yöntem') || s('Finans onaylı yöntem') || s('Vadeli satış')) {
      return 'paymentMethod';
    }
    if (s('Tutar eşiği') || s('Tutar bilinmiyor')) return 'amountThreshold';
    if (s('İlk ') && r.contains(' sipariş')) return 'firstOrders';
    if (s('Yüksek risk')) return 'highRisk';
    if (s('Tüm siparişler')) return 'allOrders';
    if (s('Koşullu onaylı cari') || s('Finans kartı askıda')) {
      return 'cardStatus';
    }
    if (s('Finans önceden onaylı')) return 'preApproved';
    return 'other';
  }

  static const _riskShort = {1: 'A', 2: 'B', 3: 'C', 4: 'D'};

  static String _riskTone(int? risk) => switch (risk) {
    1 => 'ok',
    2 => 'info',
    3 => 'warn',
    4 => 'danger',
    _ => 'neutral',
  };

  /// `summary` (bayi / merkez) — sipariş finansı.
  JsonMap _orderFinanceSummary(
    FakePersona p,
    JsonMap a,
    A5ApprovalExtra x,
    JsonMap order,
  ) {
    final platform = p.persona == Persona.platform;
    final orderId = order['id'] as int;
    final stationId = order['stationId'] as int;
    final customerId = order['customerId'] as int;
    final link = world.link(stationId, customerId);
    final linkId = link?['id'] as int?;
    final card = linkId == null ? null : financeCards[linkId];
    final orderNo = order['orderNumber'] as String;
    final liters = (order['quantityLiters'] as num).toDouble();
    JsonMap? quote;
    for (final q in ((order['quotes'] as List?) ?? const []).cast<JsonMap>()) {
      if (q['isSelected'] == true) quote = q;
    }
    final quoted = (quote?['totalAmountTry'] as num?)?.toDouble();
    final estimated = (order['estimatedAmount'] as num?)?.toDouble();
    final method = order['paymentMethodCode'] as String?;
    final methodName = method == null
        ? 'Belirtilmemiş'
        : (FakeWorld.paymentMethodNames[method] ?? method);
    final deferred = _methodTerms[method]?.$3 ?? false;
    final term = order['paymentTermDays'] as int?;
    final due = TrTime.parseLocal(order['paymentDueDate'] as String?);
    final payStatus = (order['paymentStatus'] as int?) ?? 0;
    final delivery = TrTime.parseLocal(
      order['requestedDeliveryDate'] as String?,
    );
    final reasons = [
      for (final r in ((order['financeReasons'] as String?) ?? '').split(' · '))
        if (r.trim().isNotEmpty) r.trim(),
    ];
    // Sipariş anında istenen belge (sunucu `OrderTimeDocument`): çek / senet zorunlu, dekont isteğe bağlı.
    final (int? docKind, bool docRequired) = switch (method) {
      'CEK' => (AttachmentKind.chequeImage.code, true),
      'SENET' => (AttachmentKind.promissoryNoteImage.code, true),
      'HAVALE' => (AttachmentKind.transferReceipt.code, false),
      _ => (null, false),
    };
    final hasDoc =
        docKind != null &&
        world.attachments.any(
          (att) =>
              att['isActive'] == true &&
              att['kind'] == docKind &&
              ((att['ownerType'] == AttachmentOwnerType.approvalRequest.code &&
                      att['ownerId'] == a['id']) ||
                  (att['ownerType'] == AttachmentOwnerType.order.code &&
                      att['ownerId'] == orderId)),
        );
    final docMissing =
        docRequired && (payStatus == 0 || payStatus == 1) && !hasDoc;
    final financeStatus = (order['financeStatus'] as int?) ?? 0;
    final financeLabel = OrderFinanceStatus.fromCode(financeStatus).label;
    final financeTone = switch (financeStatus) {
      2 || 3 => 'ok',
      4 => 'info',
      5 => 'danger',
      _ => 'warn',
    };
    String paymentLine() => [
      methodName,
      if ((term ?? 0) > 0) '$term gün',
      if (due != null) 'vade ${Fmt.date(due)}',
      PaymentStatus.fromCode(payStatus).label,
    ].join(' · ');

    final facts = <JsonMap>[
      _key('Sipariş no', orderNo, 'order.number'),
      if (platform)
        _key('Bayi', world.stationTitle(stationId) ?? 'Bayi', 'order.station'),
      _key(
        'Ürün',
        (order['productName'] as String?) ?? 'Ürün',
        'order.product',
      ),
      _key('Miktar', Fmt.liters(liters), 'order.quantity'),
      if (delivery != null)
        _key('Teslim', Fmt.date(delivery), 'order.deliveryDate'),
      _key(
        'Teslimat noktası',
        (order['deliveryPointName'] as String?) ?? Fmt.dash,
        'order.deliveryPoint',
      ),
      if (quoted != null)
        _key('Teklif tutarı', Fmt.money(quoted), 'order.quoteAmount'),
      if (estimated != null)
        _key('Tahmini tutar', Fmt.money(estimated), 'order.estimatedAmount'),
      _key('Ödeme', paymentLine(), 'payment.line'),
      _key('Finans durumu', financeLabel, 'finance.status', financeTone),
      for (final r in reasons)
        _key('Gerekçe', r, 'finance.reason', _reasonTone(r)),
    ];
    final warnings = <String>[
      if (docMissing && docKind != null)
        '${AttachmentKind.fromCode(docKind).label} yüklenmedi. Bu ödeme yönteminde belge zorunlu; onaydan önce "Ek bilgi iste" ile isteyin (İstenen belge: ${AttachmentKind.fromCode(docKind).label}).',
    ];

    JsonMap? finance;
    JsonMap? band;
    final review = <String, Object?>{
      'financeStatus': financeStatus,
      'financeStatusLabel': financeLabel,
      'amountIsEstimate': quoted == null,
      'estimatedAmount': estimated,
      'quotedAmount': quoted,
      'reasons': [
        for (final r in reasons)
          {'text': r, 'kind': _reasonKind(r), 'tone': _reasonTone(r)},
      ],
      'payment': {
        'methodCode': method,
        'methodName': methodName,
        'isDeferred': deferred,
        'termDays': term,
        'dueDate': due == null ? null : TrTime.isoDate(due),
        'installments': order['paymentInstallments'],
        'status': payStatus,
        'statusLabel': PaymentStatus.fromCode(payStatus).label,
        'documentKind': docKind,
        'documentLabel': docKind == null
            ? null
            : AttachmentKind.fromCode(docKind).label,
        'documentRequired': docRequired,
        'documentMissing': docMissing,
      },
      'limit': null,
      'profile': null,
      'riskReport': null,
      'history': null,
      'paymentGroup': const <JsonMap>[],
    };
    if (link != null && card != null) {
      final risk = (link['riskClass'] as int?) ?? 0;
      final status = (link['financeStatus'] as int?) ?? 1;
      final limitAmount = (link['limitAmount'] as num?)?.toDouble();
      final limitType = link['limitType'] as String?;
      final litre = limitType == 'Litre';
      final used = (link['used'] as num?)?.toDouble() ?? 0;
      final thisOrder = litre ? liters : (quoted ?? estimated ?? 0);
      final total = used + thisOrder;
      final hasLimit = limitAmount != null && limitAmount > 0;
      final unit = litre ? 'L' : 'TL';
      double money(num v) => v.toDouble();
      final unpriced = litre
          ? 0.0
          : world.orders
                .where(
                  (o) =>
                      o['id'] != orderId &&
                      o['stationId'] == stationId &&
                      o['customerId'] == customerId &&
                      (o['status'] == 1 || o['status'] == 5) &&
                      ((o['quotes'] as List?) ?? const []).isEmpty,
                )
                .fold<double>(
                  0,
                  (sum, o) => sum + ((o['estimatedAmount'] as num?) ?? 0),
                );
      final collaterals = ((card['collaterals'] as List?) ?? const [])
          .cast<JsonMap>()
          .where((c) => c['status'] == 1)
          .toList();
      final review0 = TrTime.parseLocal(card['nextReviewDate'] as String?);
      final reviewLate =
          review0 != null && TrTime.dayDiff(TrTime.todayStart(), review0) < 0;
      final reports = ((card['riskReports'] as List?) ?? const [])
          .cast<JsonMap>();
      final report = reports.isEmpty ? null : reports.first;
      final overdue = (card['overdueAmount'] as num?)?.toDouble();
      final allowed = ((card['allowedMethodCodes'] as List?) ?? const [])
          .cast<String>();
      final maxTerm = card['maxTermDays'] as int?;
      final suggested = (card['suggestedCollateralRatioPercent'] as num?)
          ?.toDouble();
      final ratio = (card['collateralRatioPercent'] as num?)?.toDouble() ?? 0;
      final bounced = card['hasBouncedCheque'] == true;
      final protested = card['hasProtestedNote'] == true;
      final statusLabel = FinanceProfileStatus.fromCode(status).label;
      // Kart satırları (sunucu `FinanceSnapshotLoader.AppendFacts`).
      facts.addAll([
        _key('Cari finans durumu', statusLabel, 'card.status', switch (status) {
          1 => 'ok',
          2 => 'info',
          0 || 3 => 'warn',
          _ => 'danger',
        }),
        _key(
          'Risk sınıfı',
          RiskClass.fromCode(risk).label,
          'card.riskClass',
          _riskTone(risk),
        ),
        _key(
          'Limit kullanımı',
          hasLimit
              ? '${litre ? Fmt.liters(used) : Fmt.moneyWhole(used)} / ${litre ? Fmt.liters(limitAmount) : Fmt.moneyWhole(limitAmount)} (%${(used / limitAmount * 100).round()})'
              : 'Limit yok',
          'card.limitUsage',
          !hasLimit
              ? 'neutral'
              : (used / limitAmount >= 1
                    ? 'danger'
                    : (used / limitAmount >= 0.8 ? 'warn' : 'ok')),
        ),
        _key(
          'Onaylanan limit',
          Fmt.money(card['approvedLimitAmount'] as num?),
          'card.approvedLimit',
        ),
        _key(
          'Teminat oranı',
          suggested != null && suggested != ratio
              ? '${Fmt.percent(ratio)} (öneri ${Fmt.percent(suggested)})'
              : Fmt.percent(ratio),
          'card.collateralRatio',
        ),
        _key(
          'Gecikmiş',
          Fmt.money(overdue ?? 0),
          'card.overdue',
          (overdue ?? 0) > 0 ? 'danger' : 'neutral',
        ),
        _key(
          'İzinli yöntemler',
          allowed.isEmpty
              ? 'Bayide açık tümü'
              : allowed
                    .map((c) => FakeWorld.paymentMethodNames[c] ?? c)
                    .join(', '),
          'card.allowedMethods',
        ),
        _key(
          'En uzun vade',
          maxTerm == null ? 'Sınır yok' : '$maxTerm gün',
          'card.maxTerm',
        ),
        _key(
          'Gözden geçirme',
          Fmt.date(review0),
          'card.review',
          reviewLate ? 'danger' : 'neutral',
        ),
        _key(
          'Geçerli teminat',
          '${collaterals.length} adet',
          'card.collaterals',
        ),
        if (card['isStrategicPricing'] == true)
          _key('Fiyatlama', 'Stratejik müşteri', 'card.pricing', 'info'),
        _key(
          'Son risk raporu',
          report == null
              ? 'Çekilmedi'
              : [
                  'Sınıf ${_riskShort[report['suggestedRiskClass']] ?? '-'}',
                  'skor ${report['score']}',
                  if (((report['bouncedChequeCount'] as int?) ?? 0) > 0)
                    'karşılıksız çek ${report['bouncedChequeCount']}',
                  Fmt.date(TrTime.parseUtc(report['requestedAt'] as String?)),
                ].join(' · '),
          'card.riskReport',
          report == null
              ? 'neutral'
              : _riskTone(report['suggestedRiskClass'] as int?),
        ),
      ]);
      if (reviewLate) {
        warnings.add('Finans kartının gözden geçirme tarihi geçti.');
      }
      if (bounced) warnings.add('Karşılıksız çek kaydı var.');
      if (protested) warnings.add('Protestolu senet kaydı var.');
      band = {
        'key': 'risk-${(_riskShort[risk] ?? '-').asciiLower}',
        'label': 'Risk ${_riskShort[risk] ?? '-'}',
        'tone': _riskTone(risk),
      };

      // Geçmiş (bu sipariş hariç; reddedilen ve süresi dolanlar sayılmaz).
      final others = world.orders
          .where(
            (o) =>
                o['id'] != orderId &&
                o['stationId'] == stationId &&
                o['customerId'] == customerId &&
                o['status'] != OrderStatus.rejected.code &&
                o['status'] != OrderStatus.expired.code,
          )
          .toList();
      JsonMap? last;
      for (final o in others) {
        final at = TrTime.parseLocal(o['createdAt'] as String?);
        final lastAt = TrTime.parseLocal(last?['createdAt'] as String?);
        if (at != null && (lastAt == null || at.isAfter(lastAt))) last = o;
      }
      final today = TrTime.todayStart();
      var overdueCount = 0;
      var overdueAmount = 0.0;
      int? maxOverdueDays;
      for (final o in others) {
        final d = TrTime.parseLocal(o['paymentDueDate'] as String?);
        final ps = (o['paymentStatus'] as int?) ?? 0;
        if (d == null || (ps != 1 && ps != 2)) continue;
        final late = TrTime.dayDiff(d, today);
        if (late <= 0) continue;
        overdueCount++;
        JsonMap? q;
        for (final x in ((o['quotes'] as List?) ?? const []).cast<JsonMap>()) {
          if (x['isSelected'] == true) q = x;
        }
        overdueAmount +=
            ((q?['totalAmountTry'] ?? o['estimatedAmount']) as num?)
                ?.toDouble() ??
            0;
        if (maxOverdueDays == null || late > maxOverdueDays) {
          maxOverdueDays = late;
        }
      }
      final group = order['paymentGroupKey'] as String?;
      final lastAt = TrTime.parseLocal(last?['createdAt'] as String?);
      review
        ..['limit'] = {
          'hasLimit': hasLimit,
          'type': limitType,
          'period': link['limitPeriod'],
          'unit': unit,
          'limitAmount': limitAmount,
          'usedByOthers': used,
          'thisOrder': thisOrder,
          'unpricedOthers': unpriced,
          'available': hasLimit ? max(0.0, limitAmount - used) : null,
          'availableAfter': hasLimit ? max(0.0, limitAmount - total) : null,
          'usagePercentAfter': hasLimit
              ? min(999, (total / limitAmount * 100).round())
              : null,
          'wouldExceed': hasLimit && total > limitAmount,
          'overrunAmount': hasLimit && total > limitAmount
              ? money(total - limitAmount)
              : 0.0,
          'invalidReason': null,
        }
        ..['profile'] = {
          'status': status,
          'statusLabel': statusLabel,
          'hasCard': true,
          'isGrandfathered': false,
          'canOrder': status == 1 || status == 2,
          'blockReason': status == 1 || status == 2
              ? null
              : 'Cari finans kartı onaylı değil.',
          'riskClass': risk,
          'riskLabel': RiskClass.fromCode(risk).label,
          'approvedLimitAmount': card['approvedLimitAmount'],
          'openBalance': card['openBalance'],
          'overdueAmount': overdue,
          'collateralRatioPercent': ratio,
          'suggestedCollateralRatioPercent': suggested,
          'activeCollateralCount': collaterals.length,
          'activeCollateralAmount': collaterals.fold<double>(
            0,
            (sum, c) => sum + ((c['amount'] as num?) ?? 0),
          ),
          'maxTermDays': maxTerm,
          'allowedMethodCodes': allowed,
          'nextReviewDate': review0 == null ? null : TrTime.isoDate(review0),
          'reviewOverdue': reviewLate,
          'hasBouncedCheque': bounced,
          'hasProtestedNote': protested,
          'isStrategicPricing': card['isStrategicPricing'] == true,
        }
        ..['riskReport'] = report == null
            ? null
            : {
                'id': report['id'],
                'success': report['success'] ?? true,
                'score': report['score'],
                'riskClass': report['suggestedRiskClass'],
                'bouncedChequeCount': report['bouncedChequeCount'],
                'protestedNoteCount': report['protestedNoteCount'],
                'overdueAmount': report['overdueAmount'],
                'overdueCount': report['overdueCount'],
                'requestedAt': report['requestedAt'],
                'providerLabel': report['provider'],
                'isMock': false,
                'errorMessage': report['errorMessage'],
              }
        ..['history'] = {
          'orderCount': others.length,
          'completedCount': others
              .where((o) => o['status'] == OrderStatus.completed.code)
              .length,
          'lastOrderAt': lastAt == null ? null : FakeWorld.local(lastAt),
          'lastOrderNumber': last?['orderNumber'],
          'openFinanceCount': others
              .where((o) => o['financeStatus'] == 1 || o['financeStatus'] == 4)
              .length,
          'financeRejectedCount': world.orders
              .where(
                (o) =>
                    o['id'] != orderId &&
                    o['stationId'] == stationId &&
                    o['customerId'] == customerId &&
                    o['financeStatus'] == 5,
              )
              .length,
          'overdueCount': overdueCount,
          'overdueAmount': overdueAmount,
          'maxOverdueDays': maxOverdueDays,
          'bouncedCount': others.where((o) => o['paymentStatus'] == 4).length,
        }
        ..['paymentGroup'] = group == null
            ? const <JsonMap>[]
            : [
                for (final o in world.orders)
                  if (o['id'] != orderId && o['paymentGroupKey'] == group)
                    {
                      'orderId': o['id'],
                      'orderNumber': o['orderNumber'],
                      'productName': o['productName'],
                      'quantityLiters': o['quantityLiters'],
                      'amount': o['estimatedAmount'],
                      'financeStatus': o['financeStatus'] ?? 0,
                      'financeLabel': OrderFinanceStatus.fromCode(
                        (o['financeStatus'] as int?) ?? 0,
                      ).label,
                      'approvalRequestId': o['financeApprovalRequestId'],
                    },
              ];
    }
    finance = review;
    return {
      'headline': '$orderNo · ${order['customerTitle'] ?? a['customerTitle']}',
      'subline': [
        (order['productName'] as String?) ?? 'Ürün',
        Fmt.liters(liters),
        if (delivery != null) 'teslim ${Fmt.date(delivery)}',
      ].join(' · '),
      'amount': quoted ?? estimated ?? a['amount'],
      'liters': liters,
      'facts': facts,
      'lines': const <JsonMap>[],
      'warnings': warnings,
      'band': band,
      'links': {
        'orderId': orderId,
        'customerId': customerId,
        'stationCustomerId': linkId,
      },
      'finance': finance,
    };
  }

  static const _periods = ['Aylık', 'Haftalık', 'Günlük'];

  static const _methodNames = {
    'NAKIT': 'Nakit (peşin)',
    'HAVALE': 'Havale / EFT (peşin)',
    'KART': 'Kredi / banka kartı (POS)',
    'DBS': 'DBS',
    'CEK': 'Çek',
    'SENET': 'Senet',
    'ACIK_HESAP': 'Açık hesap (cari vadeli)',
    'TEMINAT': 'Teminat mektubu karşılığı',
  };

  static const _methodTerms = {
    'NAKIT': (0, 0, false),
    'HAVALE': (0, 0, false),
    'KART': (0, 0, false),
    'DBS': (1, 90, true),
    'CEK': (1, 120, true),
    'SENET': (1, 120, true),
    'ACIK_HESAP': (1, 90, true),
    'TEMINAT': (1, 90, true),
  };

  List<JsonMap> _methodOptions() => [
    for (final e in _methodNames.entries)
      {
        'code': e.key,
        'name': e.value,
        'isDeferred': _methodTerms[e.key]!.$3,
        'minTermDays': _methodTerms[e.key]!.$1,
        'maxTermDays': _methodTerms[e.key]!.$2,
      },
  ];

  JsonMap? _conditionForm(int type, A5ApprovalExtra x) {
    final f = x.form;
    final common = {
      'methodOptions': _methodOptions(),
      'periodOptions': [
        for (final p in _periods) {'code': p, 'label': p},
      ],
      'riskClassOptions': [
        for (final r in RiskClass.values)
          if (r.code >= 1 && r.code <= 4)
            {'code': '${r.code}', 'label': r.label},
      ],
    };
    if (type == ApprovalType.orderFinance.code ||
        type == ApprovalType.fieldFormFinance.code) {
      final method = f['method'] as String?;
      final term = f['term'] as int?;
      return {
        ...common,
        'fields': [
          {
            'key': 'methodCode',
            'label': 'Ödeme yöntemi',
            'type': 'method',
            'required': false,
            'current': method,
            'currentLabel': method == null
                ? 'Belirtilmemiş'
                : _methodNames[method] ?? method,
            'hint': 'Boş bırakılırsa yöntem değişmez.',
          },
          {
            'key': 'termDays',
            'label': 'Vade (gün)',
            'type': 'int',
            'required': false,
            'min': 0,
            'max': 365,
            'current': term?.toString(),
            'currentLabel': term == null || term == 0 ? 'Peşin' : '$term gün',
            'hint': 'Vadeli yöntemlerde 1–120 gün.',
          },
        ],
        'hint': type == ApprovalType.orderFinance.code
            ? 'Boş bırakılan alan değişmez. Yöntem / vade değişirse müşteriye bildirilir ve sipariş geçmişine yazılır.'
            : 'Boş bırakılan alan değişmez; değişiklik forma ve oluşacak siparişlere geçer.',
      };
    }
    if (type == ApprovalType.customerOnboarding.code ||
        type == ApprovalType.leadFinance.code) {
      final prefix = (f['currentPrefix'] as String?) ?? 'Kartta';
      final limit = (f['limit'] as num?)?.toDouble();
      final maxTerm = f['maxTerm'] as int?;
      final methods = f['methods'] as String?;
      final risk = f['risk'] as int?;
      final collateral = (f['collateral'] as num?)?.toDouble();
      final collateralSuggestion = (f['collateralSuggestion'] as num?)
          ?.toDouble();
      final riskSuggestion = f['riskSuggestion'] as int?;
      final review = f['review'] as String?;
      final reviewSuggestion = f['reviewSuggestion'] as String?;
      String canonical(double v) =>
          v == v.roundToDouble() ? '${v.round()}' : '$v';
      return {
        ...common,
        'fields': [
          {
            'key': 'limitAmount',
            'label': 'Onaylanan limit (₺)',
            'type': 'money',
            'min': 0,
            'max': 999999999999.99,
            'current': limit == null ? null : canonical(limit),
            'currentLabel': limit == null
                ? null
                : '$prefix: ${Fmt.money(limit)}',
          },
          {
            'key': 'limitPeriod',
            'label': 'Limit dönemi',
            'type': 'period',
            'current': f['period'],
            'currentLabel': f['period'],
            'hint': 'Boş bırakılırsa aylık.',
          },
          {
            'key': 'maxTermDays',
            'label': 'En uzun vade (gün)',
            'type': 'int',
            'min': 0,
            'max': 365,
            'current': maxTerm?.toString(),
            'currentLabel': maxTerm == null ? null : '$prefix: $maxTerm gün',
          },
          {
            'key': 'allowedMethodCodes',
            'label': 'İzinli ödeme yöntemleri',
            'type': 'methods',
            'current': methods,
            'currentLabel': methods == null
                ? null
                : '$prefix: ${methods.split(',').map((c) => _methodNames[c] ?? c).join(', ')}',
            'hint': prefix == 'Kartta'
                ? 'Seçilmezse kartta olduğu gibi kalır.'
                : 'Seçilmezse talep edilen yöntemler geçerlidir.',
          },
          {
            'key': 'riskClass',
            'label': 'Risk sınıfı',
            'type': 'riskClass',
            'current': risk?.toString(),
            'currentLabel': risk == null
                ? null
                : RiskClass.fromCode(risk).label,
            'suggestion': riskSuggestion?.toString(),
            'suggestionLabel': riskSuggestion == null
                ? null
                : 'Rapor önerisi: ${RiskClass.fromCode(riskSuggestion).label}',
          },
          {
            'key': 'collateralRatioPercent',
            'label': 'Teminat oranı (%)',
            'type': 'percent',
            'min': 0,
            'max': f['collateralMax'] ?? 100,
            'current': collateral == null ? null : canonical(collateral),
            'currentLabel': collateral == null
                ? null
                : '$prefix: ${Fmt.percent(collateral)}',
            'suggestion': collateralSuggestion == null
                ? null
                : canonical(collateralSuggestion),
            'suggestionLabel': collateralSuggestion == null
                ? null
                : 'Öneri: ${Fmt.percent(collateralSuggestion)}',
          },
          {
            'key': 'nextReviewDate',
            'label': 'Sonraki gözden geçirme',
            'type': 'date',
            'current': review,
            'currentLabel': review == null
                ? null
                : '$prefix: ${Fmt.date(TrTime.parseDate(review))}',
            'suggestion': reviewSuggestion,
            'suggestionLabel': reviewSuggestion == null
                ? null
                : 'Öneri: ${Fmt.date(TrTime.parseDate(reviewSuggestion))}',
          },
        ],
        'hint': type == ApprovalType.customerOnboarding.code
            ? 'Boş bırakılan alan kartta olduğu gibi kalır. Kart "koşullu onaylı" olur; carinin siparişleri finans incelemesinden geçer.'
            : 'Boş bırakılan alanda ön kaydın talebi geçerlidir. Onayda cari bu şartlarla açılır ve finans kartı "koşullu onaylı" olur.',
      };
    }
    return null;
  }

  /// Türün koşul anahtarları (sunucu `ApprovalConditionKeys.For`).
  static Set<String> conditionKeys(int type) {
    if (type == ApprovalType.orderFinance.code ||
        type == ApprovalType.fieldFormFinance.code) {
      return {'methodCode', 'termDays'};
    }
    if (type == ApprovalType.customerOnboarding.code ||
        type == ApprovalType.leadFinance.code) {
      return {
        'limitAmount',
        'limitPeriod',
        'maxTermDays',
        'allowedMethodCodes',
        'riskClass',
        'collateralRatioPercent',
        'nextReviewDate',
      };
    }
    return const {};
  }

  // ═══════════════════════════════════════════════════════════════ Karar

  /// `POST approvals/{id}/decide` (sunucu kurallarının sahte aynası).
  JsonMap decide(FakePersona p, JsonMap a, JsonReader body) {
    final x = extraOf(a);
    final decision = body.intOrNull('decision');
    final token = body.str('concurrencyToken');
    if (token.isEmpty) {
      throw FakeResponse.validation({
        'concurrencyToken': ['Talep sürümü okunamadı; ekranı yenileyin.'],
      });
    }
    if (token != x.token) {
      throw FakeResponse.conflict(
        'concurrency_conflict',
        'Talep siz bakarken değişti; güncel hâlini görüp yeniden deneyin.',
      );
    }
    final modes = modesFor(p, a);
    if (decision == null || !modes.contains(decision)) {
      throw FakeResponse.business('Bu talepte bu kararı veremezsiniz.');
    }
    final note = body.nonEmpty('note');
    final type = a['type'] as int;
    final rawConditions = body['conditions'];
    final conditions = rawConditions is Map
        ? JsonReader.asMap(rawConditions)
        : <String, dynamic>{};
    if (decision == ApprovalDecision.requestInfo.code && note == null) {
      throw FakeResponse.validation({
        'note': ['Ek bilgi isteğinde neyin istendiğini yazın.'],
      }, 'Ek bilgi isteğinde neyin istendiğini yazın.');
    }
    if (decision == ApprovalDecision.reject.code) {
      final min = ApprovalType.fromCode(
        type,
      ).minRejectNoteLength(isMirror: a['isMirror'] == true);
      if (note == null || note.length < min) {
        throw FakeResponse.validation({
          'note': [
            note == null
                ? 'Reddetmek için gerekçe yazın.'
                : 'Ret gerekçesi en az $min karakter olmalı.',
          ],
        }, 'Ret gerekçesini kontrol edin.');
      }
    }
    if (decision == ApprovalDecision.conditionalApprove.code) {
      final allowed = conditionKeys(type);
      for (final k in conditions.keys) {
        if (!allowed.contains(k)) {
          throw FakeResponse.validation({
            'conditions.$k': ['Bu alan bu talebin koşullu onay formunda yok.'],
          }, 'Bu alan bu talebin koşullu onay formunda yok.');
        }
      }
      if (conditions.isEmpty && note == null) {
        throw FakeResponse.validation({
          'conditions': [
            'Koşullu onay için en az bir koşul girin ya da koşulu karar notuna yazın.',
          ],
        }, 'Koşullu onay için en az bir koşul girin.');
      }
    } else if (conditions.isNotEmpty) {
      throw FakeResponse.validation({
        'conditions.${conditions.keys.first}': [
          'Koşullar yalnızca koşullu onayda gönderilir.',
        ],
      }, 'Koşullar yalnızca koşullu onayda gönderilir.');
    }

    final now = DateTime.now().toUtc();
    final kind = switch (decision) {
      1 => ApprovalEventKind.approved,
      2 => ApprovalEventKind.conditionallyApproved,
      3 => ApprovalEventKind.infoRequested,
      _ => ApprovalEventKind.rejected,
    };
    final requiredKind = decision == ApprovalDecision.requestInfo.code
        ? body.intOrNull('requiredAttachmentKind')
        : null;
    final eventNote = requiredKind == null
        ? note
        : '$note · İstenen belge: ${AttachmentKind.fromCode(requiredKind).label}';
    x.events.add(event(kind, userKey: p.key, at: now, note: eventNote));
    // Koşullu onayın olay notu koşul JSON'udur; yalnızca not verildiyse {"text": not} (sunucu
    // `ApprovalEngine.DecideNativeAsync`).
    if (decision == ApprovalDecision.conditionalApprove.code) {
      x.events.last['note'] = jsonEncode(
        conditions.isNotEmpty
            ? {for (final e in conditions.entries) e.key: '${e.value}'}
            : {'text': note},
      );
    }
    x.deciders.add(p.userId);
    x.token = newToken();

    var message = '';
    var isFinal = false;
    final level = (a['currentLevelNo'] as int?) ?? 1;
    final levels = (a['levelCount'] as int?) ?? 1;
    final step = x.steps.where((s) => s['levelNo'] == level).firstOrNull;

    void markStep(int status) {
      if (step == null) return;
      step['status'] = status;
      step['decidedByUserId'] = p.userId;
      step['decidedByName'] = p.displayName;
      step['decidedAt'] = utc(now);
      step['note'] = note;
    }

    void close(int status) {
      a['status'] = status;
      a['slaState'] = 0;
      x.decidedAt = utc(now);
      x.decidedByUserId = p.userId;
      x.decidedByName = p.displayName;
      x.decisionNote = note;
      isFinal = true;
    }

    switch (decision) {
      case 1 || 2:
        markStep(2);
        if (decision == 1 && level < levels) {
          final next = x.steps.where((s) => s['levelNo'] == level + 1).first;
          next['status'] = 1;
          a['currentLevelNo'] = level + 1;
          a['eligibleUserIds'] = [
            for (final u in (next['eligible'] as List? ?? const []))
              if (!x.deciders.contains(u)) u,
          ];
          message = 'Kademe onaylandı; talep bir sonraki kademeye geçti.';
        } else {
          x.conditional = decision == 2;
          close(ApprovalStatus.approved.code);
          message = decision == 2
              ? 'Talep koşullu onaylandı.'
              : 'Talep onaylandı.';
          message = _onApproved(p, a, x, conditions) ?? message;
        }
      case 3:
        a['status'] = ApprovalStatus.infoRequested.code;
        x.infoRequest = {'note': note, 'kind': requiredKind, 'at': utc(now)};
        x.deciders.remove(p.userId);
        message = 'Ek bilgi istendi; talep edene bildirildi.';
        _onInfoRequested(a);
      default:
        markStep(3);
        close(ApprovalStatus.rejected.code);
        message = 'Talep reddedildi.';
        _onRejected(a, note);
    }
    if (isFinal || decision == 3) _syncStatusFact(a, x);
    return {
      'requestId': a['id'],
      'status': a['status'],
      'isFinal': isFinal,
      'currentLevelNo': a['currentLevelNo'] ?? 1,
      'message': message,
      'concurrencyToken': x.token,
    };
  }

  /// Özetteki "Durum" satırı konunun güncel durumunu yansıtır (sunucu özeti konudan üretir).
  void _syncStatusFact(JsonMap a, A5ApprovalExtra x) {
    final i = x.facts.indexWhere((f) => f['label'] == 'Durum');
    if (i < 0) return;
    final (String value, String tone) = switch (ApprovalStatus.fromCode(
      a['status'] as int?,
    )) {
      ApprovalStatus.approved =>
        x.conditional ? ('Koşullu onaylandı', 'ok') : ('Onaylandı', 'ok'),
      ApprovalStatus.rejected => ('Reddedildi', 'danger'),
      ApprovalStatus.infoRequested => ('Ek bilgi istendi', 'info'),
      _ => ('İncelemede', 'info'),
    };
    x.facts[i] = {...x.facts[i], 'value': value, 'tone': tone};
  }

  JsonMap? _subjectOrder(JsonMap a) =>
      a['subjectType'] == 'Order' ? world.order(a['subjectId'] as int?) : null;

  void _notifyCustomer(JsonMap a, String title, String body) {
    final cid = a['customerId'];
    if (cid == null) return;
    for (final key in const ['musteri', 'talep', 'onay']) {
      final p = world.persona(key);
      if (p == null || p.customerId != cid) continue;
      world.addNotification(
        userId: p.userId,
        category: 'orders',
        eventCode: 'order.finance_info',
        title: title,
        body: body,
        route: '/approvals/${a['id']}',
        entityType: 'ApprovalRequest',
        entityId: a['id'] as int,
        severity: 2,
      );
    }
  }

  String? _onApproved(
    FakePersona p,
    JsonMap a,
    A5ApprovalExtra x,
    Map<String, dynamic> conditions,
  ) {
    final type = a['type'] as int;
    final order = _subjectOrder(a);
    if (order != null) {
      order['financeStatus'] = x.conditional
          ? OrderFinanceStatus.conditionallyApproved.code
          : OrderFinanceStatus.approved.code;
      final method = conditions['methodCode'];
      if (method is String) {
        order['paymentMethodCode'] = method;
        order['paymentMethodName'] =
            FakeWorld.paymentMethodNames[method] ?? method;
      }
      final term = conditions['termDays'];
      if (term is num) order['paymentTermDays'] = term.toInt();
      // Sahip kararı 04.11.2026: müşteri teklifi onaylamıştı, finans onayı siparişi "Onaylandı" yapar.
      if (order['status'] == OrderStatus.awaitingApproval.code &&
          order['acceptedQuoteId'] != null) {
        order['status'] = OrderStatus.approved.code;
        A2Fake.addHistory(
          world,
          order['id'] as int,
          OrderStatus.awaitingApproval.code,
          OrderStatus.approved.code,
          note: x.conditional ? 'Finans koşullu onayladı' : 'Finans onayladı',
          userId: p.userId,
        );
        _notifyCustomer(
          a,
          'Sipariş onaylandı: ${order['orderNumber']}',
          'Finans onayı tamamlandı; bayiniz sevkiyatı planlayacak.',
        );
      }
    }
    if (type == ApprovalType.customerOnboarding.code) {
      final card = financeCards[a['subjectId']];
      if (card != null) card['status'] = x.conditional ? 2 : 1;
    }
    if (type == ApprovalType.leadFinance.code) {
      final lead = leads[a['subjectId']];
      if (lead != null) lead['status'] = LeadStatus.approved.code;
    }
    if (type == ApprovalType.companyOrderRequest.code) {
      return _approveCompanyRequest(p, a, x);
    }
    return null;
  }

  void _onInfoRequested(JsonMap a) {
    final order = _subjectOrder(a);
    if (order != null) {
      order['financeStatus'] = OrderFinanceStatus.infoRequested.code;
      _notifyCustomer(
        a,
        'Finans ek bilgi istedi',
        '${a['subjectNumber']}: siparişiniz için ek bilgi / belge istendi.',
      );
    }
    final lead = leads[a['subjectId']];
    if (a['type'] == ApprovalType.leadFinance.code && lead != null) {
      lead['status'] = LeadStatus.infoRequested.code;
    }
  }

  void _onRejected(JsonMap a, String? note) {
    final order = _subjectOrder(a);
    if (order != null) {
      order['financeStatus'] = OrderFinanceStatus.rejected.code;
      order['status'] = OrderStatus.rejected.code;
    }
    if (a['type'] == ApprovalType.customerOnboarding.code) {
      final card = financeCards[a['subjectId']];
      if (card != null) card['status'] = 4;
    }
    final lead = leads[a['subjectId']];
    if (a['type'] == ApprovalType.leadFinance.code && lead != null) {
      lead['status'] = LeadStatus.rejected.code;
    }
    if (a['type'] == ApprovalType.companyOrderRequest.code) {
      final req = companyRequests
          .where((r) => r['id'] == a['subjectId'])
          .firstOrNull;
      if (req != null) {
        req['status'] = CustomerOrderRequestStatus.rejected.code;
        req['statusLabel'] = CustomerOrderRequestStatus.rejected.label;
        req['decisionNote'] = note;
        req['decidedAt'] = utc(DateTime.now());
      }
    }
  }

  /// Şirket içi talebin onayı: ilk satır siparişe döner, ikinci satır fiyat yokluğundan oluşturulamaz.
  String _approveCompanyRequest(FakePersona p, JsonMap a, A5ApprovalExtra x) {
    final req = companyRequests
        .where((r) => r['id'] == a['subjectId'])
        .firstOrNull;
    if (req == null) return 'Talep onaylandı.';
    final lines = (req['lines'] as List).cast<JsonMap>();
    final created = <int>[];
    var failed = 0;
    final now = DateTime.now().toUtc();
    for (final l in lines) {
      if (l['orderId'] != null) continue;
      if (l['productId'] == 3) {
        l['error'] = 'Bu bayide Kalorifer Yakıtı için geçerli fiyat yok.';
        failed++;
        continue;
      }
      final id = newOrderId();
      final order = world.newOrder(
        id: id,
        customerId: req['customerId'] as int,
        stationId: l['stationId'] as int,
        deliveryPointId: l['deliveryPointId'] as int,
        productId: l['productId'] as int,
        liters: (l['quantityLiters'] as num).toDouble(),
        status: OrderStatus.awaitingQuote.code,
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 24)),
        requestedDeliveryDate:
            TrTime.parseLocal(l['requestedDeliveryDate'] as String?) ??
            now.add(const Duration(days: 2)),
        paymentMethodCode: (req['paymentMethodCode'] as String?) ?? 'HAVALE',
        createdByUserId: req['requestedByUserId'] as String?,
      );
      world.orders.add(order);
      l['orderId'] = id;
      l['orderNumber'] = order['orderNumber'];
      l['error'] = null;
      created.add(id);
    }
    req['status'] = created.isEmpty
        ? CustomerOrderRequestStatus.pending.code
        : CustomerOrderRequestStatus.approved.code;
    req['statusLabel'] = CustomerOrderRequestStatus.fromCode(
      req['status'] as int,
    ).label;
    req['createdOrderIds'] = [
      ...((req['createdOrderIds'] as List?) ?? const []),
      ...created,
    ];
    req['decidedByName'] = p.displayName;
    req['decidedAt'] = utc(now);
    req['decisionNote'] = x.decisionNote;
    x.lines
      ..clear()
      ..addAll(_companyLines(req));
    if (created.isNotEmpty) {
      x.links['orderId'] = created.first;
    }
    if (failed > 0) {
      x.warnings
        ..clear()
        ..add(
          '$failed satır siparişe dönüşemedi; başarısız satırları yeni siparişe aktarabilirsiniz.',
        );
    }
    final talep = world.personaByUserId(req['requestedByUserId'] as String?);
    if (talep != null) {
      world.addNotification(
        userId: talep.userId,
        category: 'approvals',
        eventCode: 'company_request.decided',
        title: 'Sipariş talebiniz onaylandı',
        body: 'Talep #${req['id']}: ${created.length} sipariş bayiye iletildi.',
        route: '/company/requests/${req['id']}',
        entityType: 'CustomerOrderRequest',
        entityId: req['id'] as int,
        severity: 1,
      );
    }
    return failed == 0
        ? 'Talep onaylandı: ${created.length} sipariş oluşturuldu.'
        : 'Talep onaylandı: ${created.length} sipariş oluşturuldu, $failed satır oluşturulamadı.';
  }

  /// `POST approvals/{id}/provide-info`.
  String provideInfo(FakePersona p, JsonMap a, JsonReader body) {
    if (a['status'] != ApprovalStatus.infoRequested.code) {
      throw FakeResponse.conflict(
        'concurrency_conflict',
        'Talep ek bilgi beklemiyor; ekranı yenileyin.',
      );
    }
    final x = extraOf(a);
    final note = body.nonEmpty('note');
    final respondent = isRespondent(p, a);
    if (!respondent && !canResume(p, a)) {
      throw FakeResponse.forbidden('Bu talebe ek bilgi yanıtı veremezsiniz.');
    }
    final now = DateTime.now().toUtc();
    x.events.add(
      event(
        ApprovalEventKind.infoProvided,
        userKey: p.key,
        at: now,
        note: respondent ? note : (note ?? 'Bilgi alındı'),
      ),
    );
    x.infoRequest = null;
    x.token = newToken();
    a['status'] = ApprovalStatus.pending.code;
    _syncStatusFact(a, x);
    final order = _subjectOrder(a);
    if (order != null) {
      order['financeStatus'] = OrderFinanceStatus.pending.code;
    }
    final lead = leads[a['subjectId']];
    if (a['type'] == ApprovalType.leadFinance.code && lead != null) {
      lead['status'] = LeadStatus.inReview.code;
    }
    if (!respondent) {
      return 'Bilgi alındı olarak kaydedildi; talep yeniden incelemede.';
    }
    return p.persona == Persona.customer
        ? 'Yanıtınız finans ekibine iletildi; inceleme yeniden başladı.'
        : 'Yanıtınız iletildi; talep yeniden onaya düştü.';
  }

  /// `POST leads/{id}/forward-hq` (yedek: A6 kaydetmezse).
  String forwardLead(FakePersona p, int leadId) {
    if (world.firstStageApprovals) {
      throw FakeResponse.business(
        'Merkeze iletme kaldırıldı; bu ön kayda bayinin finansı karar verir.',
      );
    }
    if (!p.hasCap(Caps.approveFinanceLead) || p.persona == Persona.platform) {
      throw FakeResponse.forbidden(
        'Merkeze iletmek için ön kayıt finans onay yetkisi gerekir.',
      );
    }
    final lead = leads[leadId];
    if (lead == null) throw FakeResponse.business('Ön kayıt bulunamadı.');
    final status = lead['status'] as int;
    if (status != LeadStatus.submitted.code &&
        status != LeadStatus.inReview.code) {
      throw FakeResponse.business(
        'Yalnızca finans onayı bekleyen ön kayıt merkeze iletilebilir.',
      );
    }
    if (lead['existsElsewhere'] != true) {
      throw FakeResponse.business(
        'Merkeze iletme yalnızca VKN\'si başka bayide kayıtlı ön kayıtlar içindir; diğerlerine bayi finansı karar verir.',
      );
    }
    if (lead['isForwardedToHq'] == true) {
      throw FakeResponse.business('Talep zaten merkeze iletildi.');
    }
    lead['isForwardedToHq'] = true;
    for (final a in world.approvals) {
      if (a['subjectType'] == 'CustomerLead' && a['subjectId'] == leadId) {
        final x = extraOf(a);
        a['eligibleUserIds'] = ['u-merkez'];
        a['escalated'] = true;
        x.token = newToken();
        x.events.add(
          event(
            ApprovalEventKind.escalated,
            userKey: p.key,
            note: 'Merkeze iletildi',
          ),
        );
        x.warnings
          ..clear()
          ..add(
            'Bu VKN sistemde başka bir bayide kayıtlı; cari açılışı merkez onayıyla yapılır. Talep merkez onayına iletildi.',
          );
      }
    }
    return 'Ön kayıt merkez onayına iletildi.';
  }

  /// `GET leads/{id}` (yedek; yalnızca "Merkeze ilet" alanları).
  JsonMap leadJson(FakePersona p, int id) {
    final lead = leads[id];
    if (lead == null) throw FakeResponse.notFound('Ön kayıt bulunamadı.');
    final status = lead['status'] as int;
    final financeViewer = p.hasCap(Caps.approveFinanceLead);
    final awaiting =
        status == LeadStatus.submitted.code ||
        status == LeadStatus.inReview.code;
    return {
      'id': id,
      'status': status,
      'statusLabel': LeadStatus.fromCode(status).label,
      'companyTitle': lead['title'],
      'existsElsewhere': lead['existsElsewhere'],
      'isForwardedToHq': lead['isForwardedToHq'],
      'isFinanceViewer': financeViewer,
      'canForwardToHq':
          !world.firstStageApprovals &&
          financeViewer &&
          p.persona != Persona.platform &&
          awaiting &&
          lead['existsElsewhere'] == true &&
          lead['isForwardedToHq'] != true,
    };
  }

  // ═══════════════════════════════════════════════════════════════ Finans kartları

  void _seedFinanceCards() {
    final now = world.seededAt;
    JsonMap review(
      int id,
      int decision,
      String by,
      DateTime at, {
      String? note,
      String? conditions,
    }) => {
      'id': id,
      'subjectType': 'StationCustomer',
      'subjectId': 0,
      'stationId': 1,
      'decision': decision,
      'conditionsJson': conditions,
      'note': note,
      'decidedByUserId': world.persona(by)?.userId,
      'decidedByDisplay': world.persona(by)?.displayName,
      'decidedAt': utc(at),
    };
    JsonMap report(
      int id,
      int stationCustomerId, {
      required int score,
      required int risk,
      required double bankLimit,
      required double bankRisk,
      double overdue = 0,
      int bounced = 0,
      int protested = 0,
      required DateTime at,
      String provider = 'Findeks',
    }) => {
      'id': id,
      'stationId': 1,
      'stationCustomerId': stationCustomerId,
      'taxNumber': '',
      'provider': provider,
      'success': true,
      'score': score,
      'suggestedRiskClass': risk,
      'totalBankLimit': bankLimit,
      'totalBankRisk': bankRisk,
      'overdueAmount': overdue,
      'overdueCount': overdue > 0 ? 1 : 0,
      'bouncedChequeCount': bounced,
      'protestedNoteCount': protested,
      'lines': [
        {
          'bankName': 'Ziraat Bankası',
          'limit': bankLimit * 0.5,
          'risk': bankRisk * 0.45,
          'overdue': overdue,
        },
        {
          'bankName': 'İş Bankası',
          'limit': bankLimit * 0.3,
          'risk': bankRisk * 0.35,
          'overdue': 0,
        },
        {
          'bankName': 'Garanti BBVA',
          'limit': bankLimit * 0.2,
          'risk': bankRisk * 0.2,
          'overdue': 0,
        },
      ],
      'pdfAttachmentPublicId': null,
      'errorMessage': null,
      'requestedByUserId': 'u-finans',
      'requestedAt': utc(at),
    };
    financeCards.addAll({
      501: {
        'allowedMethodCodes': ['HAVALE', 'CEK', 'ACIK_HESAP', 'DBS'],
        'maxTermDays': 60,
        'collateralRatioPercent': 20.0,
        'suggestedCollateralRatioPercent': 24.0,
        'approvedLimitAmount': 2500000.0,
        'isStrategicPricing': true,
        'openBalance': 1180000.0,
        'overdueAmount': 0.0,
        'nextReviewDate': local(TrTime.startOfDay(TrTime.addDays(now, 120))),
        'notes': 'Kurumsal filo müşterisi; ödemeler düzenli.',
        'decidedAt': utc(TrTime.addDays(now, -245)),
        'collaterals': [
          {
            'id': 1,
            'kind': 2,
            'bankName': 'Ziraat Bankası',
            'amount': 500000.0,
            'validUntil': local(TrTime.startOfDay(TrTime.addDays(now, 300))),
            'status': 1,
            'note': 'DBS limiti',
          },
        ],
        'reviews': [
          review(
            1,
            1,
            'finans',
            TrTime.addDays(now, -245),
            note: 'Yıllık gözden geçirme.',
          ),
        ],
        'riskReports': [
          report(
            1,
            501,
            score: 742,
            risk: 2,
            bankLimit: 9500000,
            bankRisk: 4100000,
            at: TrTime.addDays(now, -245),
          ),
        ],
      },
      502: {
        'allowedMethodCodes': ['HAVALE', 'CEK'],
        'maxTermDays': 45,
        'collateralRatioPercent': 35.0,
        'suggestedCollateralRatioPercent': 50.0,
        'approvedLimitAmount': 1000000.0,
        'isStrategicPricing': false,
        'firstNOrdersRequireFinance': 3,
        'openBalance': 940000.0,
        // Bayinin kendi vadesi geçmiş alacağı yok (Tahsilat'ta Marmara'nın geciken ödemesi yok;
        // gecikmeler banka raporunda): ana sayfa, Tahsilat ve Finans aynı hikâyeyi söyler (v4 tur 2).
        'overdueAmount': 0.0,
        'nextReviewDate': local(TrTime.startOfDay(TrTime.addDays(now, -5))),
        'notes': 'Gecikmeler nedeniyle koşullu onaylı; vade 45 günle sınırlı.',
        'decidedAt': utc(TrTime.addDays(now, -90)),
        'collaterals': [
          {
            'id': 2,
            'kind': 1,
            'bankName': 'İş Bankası',
            'amount': 500000.0,
            'validUntil': local(TrTime.startOfDay(TrTime.addDays(now, 200))),
            'status': 1,
            'note': null,
          },
        ],
        'reviews': [
          review(
            2,
            2,
            'finans',
            TrTime.addDays(now, -90),
            note: 'Gecikmeler nedeniyle koşullu onay.',
            conditions:
                '{"maxTermDays":"45","allowedMethodCodes":["HAVALE","CEK"],"collateralRatioPercent":"35"}',
          ),
          review(3, 1, 'finans', TrTime.addDays(now, -400)),
        ],
        'riskReports': [
          report(
            2,
            502,
            score: 588,
            risk: 3,
            bankLimit: 4200000,
            bankRisk: 3650000,
            overdue: 120000,
            at: TrTime.addDays(now, -92),
          ),
        ],
      },
      503: {
        'allowedMethodCodes': ['NAKIT', 'HAVALE', 'KART'],
        'maxTermDays': 0,
        'collateralRatioPercent': 0.0,
        'approvedLimitAmount': null,
        'isStrategicPricing': false,
        'openBalance': 0.0,
        'overdueAmount': 0.0,
        'nextReviewDate': local(TrTime.startOfDay(TrTime.addDays(now, 300))),
        'decidedAt': utc(TrTime.addDays(now, -65)),
        'collaterals': <JsonMap>[],
        'reviews': [review(4, 1, 'finans', TrTime.addDays(now, -65))],
        'riskReports': <JsonMap>[],
      },
      504: {
        'allowedMethodCodes': ['HAVALE', 'CEK', 'ACIK_HESAP'],
        'maxTermDays': 30,
        'collateralRatioPercent': 15.0,
        'approvedLimitAmount': 750000.0,
        'isStrategicPricing': false,
        // Açık bakiyenin tamamı, vadesi 7 gün geçen açık hesap faturası (6.000 L × 41,20 = 247.200 ₺;
        // bayi tohumu): ana sayfanın "Vadesi geçen 1 ödeme 247.200 ₺"ı ile Finans aynı tutarı söyler.
        'openBalance': 247200.0,
        'overdueAmount': 247200.0,
        'hasBouncedCheque': true,
        'nextReviewDate': local(TrTime.startOfDay(TrTime.addDays(now, 30))),
        'notes': 'Karşılıksız çek sonrası yeni siparişlerde peşin önerilir.',
        'decidedAt': utc(TrTime.addDays(now, -180)),
        'collaterals': <JsonMap>[],
        'reviews': [review(5, 1, 'finans', TrTime.addDays(now, -180))],
        'riskReports': [
          report(
            3,
            504,
            score: 655,
            risk: 2,
            bankLimit: 2100000,
            bankRisk: 1450000,
            bounced: 1,
            at: TrTime.addDays(now, -12),
          ),
        ],
      },
      506: {
        'virtual': true,
        'customerId': 105,
        'customerTitle': 'Doğu Marmara Gıda San. A.Ş.',
        'taxNumber': '5678901236',
        'status': 0,
        'riskClass': 0,
        'limitAmount': null,
        'allowedMethodCodes': ['HAVALE', 'CEK'],
        'maxTermDays': 30,
        'collateralRatioPercent': 10.0,
        'suggestedCollateralRatioPercent': 25.0,
        'approvedLimitAmount': null,
        'openBalance': 0.0,
        'overdueAmount': 0.0,
        'nextReviewDate': null,
        'notes': 'Yeni cari; finans onayı bekliyor.',
        'collaterals': <JsonMap>[],
        'reviews': <JsonMap>[],
        'riskReports': [
          report(
            4,
            506,
            score: 712,
            risk: 2,
            bankLimit: 3000000,
            bankRisk: 1200000,
            at: TrTime.addDays(now, -1),
          ),
        ],
      },
    });
  }

  /// Bayinin finans kartı kimlikleri (bağlantılar + sanal yeni cari).
  List<int> financeLinkIds(int stationId) => [
    for (final l in world.links)
      if (l['stationId'] == stationId) l['id'] as int,
    if (stationId == 1) 506,
  ];

  JsonMap? _link(int id) {
    for (final l in world.links) {
      if (l['id'] == id) return l;
    }
    return null;
  }

  /// `CustomerFinanceListItemDto`.
  JsonMap? financeListItem(int linkId) {
    final card = financeCards[linkId] ?? const <String, dynamic>{};
    final link = _link(linkId);
    if (link == null && card['virtual'] != true) return null;
    final customerId = (link?['customerId'] ?? card['customerId']) as int?;
    final customer = world.customer(customerId);
    final limitType = link?['limitType'] as String?;
    return {
      'stationCustomerId': linkId,
      'profileId': linkId + 1000,
      'customerId': customerId,
      'customerTitle': customer?['title'] ?? card['customerTitle'],
      'taxNumber': customer?['taxNumber'] ?? card['taxNumber'],
      'status': card['status'] ?? link?['financeStatus'],
      'isGrandfathered': false,
      'riskClass': card['riskClass'] ?? link?['riskClass'] ?? 0,
      'limitAmount': link?['limitAmount'] ?? card['limitAmount'],
      'limitUsed': link?['used'],
      'limitUnit': limitType == 'Litre'
          ? 'L'
          : (limitType == null ? null : 'TL'),
      'nextReviewDate': card['nextReviewDate'],
      'isStrategicPricing': card['isStrategicPricing'] ?? false,
      'hasBouncedCheque': card['hasBouncedCheque'] ?? false,
      'hasProtestedNote': card['hasProtestedNote'] ?? false,
      'overdueAmount': card['overdueAmount'],
    };
  }

  /// `FinanceCustomerCardDto`.
  JsonMap? financeCard(int linkId) {
    final item = financeListItem(linkId);
    if (item == null) return null;
    final card = financeCards[linkId] ?? const <String, dynamic>{};
    final link = _link(linkId);
    final limitType = link?['limitType'] as String?;
    final limitAmount = (link?['limitAmount'] as num?)?.toDouble();
    final used = (link?['used'] as num?)?.toDouble() ?? 0;
    return {
      'profile': {
        'id': linkId + 1000,
        'stationCustomerId': linkId,
        'stationId': 1,
        'customerId': item['customerId'],
        'customerTitle': item['customerTitle'],
        'taxNumber': item['taxNumber'],
        'status': item['status'],
        'isGrandfathered': false,
        'riskClass': item['riskClass'],
        'approvedLimitAmount': card['approvedLimitAmount'],
        'limitUsage': limitAmount == null
            ? {'hasLimit': false, 'used': used, 'requested': 0, 'unit': ''}
            : {
                'hasLimit': true,
                'limitType': limitType,
                'limitPeriod': link?['limitPeriod'],
                'limitAmount': limitAmount,
                'used': used,
                'requested': 0,
                'available': max(0, limitAmount - used),
                'wouldExceed': false,
                'overrunAmount': 0,
                'unit': limitType == 'Litre' ? 'L' : 'TL',
              },
        'allowedMethodCodes': card['allowedMethodCodes'] ?? const <String>[],
        'maxTermDays': card['maxTermDays'],
        'collateralRatioPercent': card['collateralRatioPercent'] ?? 0,
        'suggestedCollateralRatioPercent':
            card['suggestedCollateralRatioPercent'],
        'isStrategicPricing': card['isStrategicPricing'] ?? false,
        'firstNOrdersRequireFinance': card['firstNOrdersRequireFinance'],
        'openBalance': card['openBalance'],
        'overdueAmount': card['overdueAmount'],
        'hasBouncedCheque': card['hasBouncedCheque'] ?? false,
        'hasProtestedNote': card['hasProtestedNote'] ?? false,
        'nextReviewDate': card['nextReviewDate'],
        'lastRiskReportId': null,
        'notes': card['notes'],
        'decidedByUserId': 'u-finans',
        'decidedAt': card['decidedAt'],
        'collaterals': card['collaterals'] ?? const <JsonMap>[],
        'concurrencyToken':
            '00000000-0000-4000-8000-0000000${linkId.toString().padLeft(5, '0')}',
      },
      'reviews': card['reviews'] ?? const <JsonMap>[],
      'riskReports': card['riskReports'] ?? const <JsonMap>[],
    };
  }

  // ═══════════════════════════════════════════════════════════════ Tahsilat

  void _seedPayments() {
    final now = world.seededAt;
    JsonMap? orderWhere(bool Function(JsonMap o) test) {
      for (final o in world.orders) {
        if (test(o)) return o;
      }
      return null;
    }

    final chequeOrder = orderWhere(
      (o) => o['paymentMethodCode'] == 'CEK' && o['status'] == 2,
    );
    final financeOrder = orderWhere((o) => o['financeStatus'] == 1);
    final transferOrder = orderWhere(
      (o) => o['paymentMethodCode'] == 'HAVALE' && o['paymentStatus'] == 2,
    );
    final collected = orderWhere((o) => o['paymentStatus'] == 3);

    var seq = 600;
    JsonMap instrument({
      required int kind,
      required int customerId,
      int? orderId,
      String? orderNumber,
      String? serialNo,
      String? bankName,
      String? branchName,
      String? drawerName,
      String? debtorName,
      String? guarantorName,
      required double amount,
      required DateTime dueDate,
      required int status,
      String? note,
      required DateTime createdAt,
    }) => {
      'id': ++seq,
      'stationId': 1,
      'customerId': customerId,
      'customerTitle': world.customerTitle(customerId),
      'orderId': orderId,
      'orderNumber': orderNumber,
      'paymentGroupKey': null,
      'kind': kind,
      'serialNo': serialNo,
      'bankName': bankName,
      'branchName': branchName,
      'drawerName': drawerName,
      'debtorName': debtorName,
      'guarantorName': guarantorName,
      'amount': amount,
      'dueDate': local(TrTime.startOfDay(dueDate)),
      'status': status,
      'note': note,
      'createdAt': utc(createdAt),
    };

    if (chequeOrder != null) {
      final due = TrTime.addDays(
        TrTime.parseLocal(chequeOrder['requestedDeliveryDate'] as String?) ??
            now,
        30,
      );
      instruments.add(
        instrument(
          kind: 1,
          customerId: chequeOrder['customerId'] as int,
          orderId: chequeOrder['id'] as int,
          orderNumber: chequeOrder['orderNumber'] as String,
          serialNo: 'CK-4581207',
          bankName: 'Ziraat Bankası',
          branchName: 'Pendik',
          drawerName: 'Anadolu Lojistik A.Ş.',
          amount: 338800,
          dueDate: due,
          status: 1,
          createdAt: TrTime.addDays(now, -1),
        ),
      );
      final img = fakeAttachment(
        world,
        ownerType: AttachmentOwnerType.paymentInstrument.code,
        ownerId: seq,
        kind: AttachmentKind.chequeImage.code,
        fileName: 'cek-on-yuz.png',
        contentType: 'image/png',
        bytes: fakeDocumentPng(accent: 0x2B5C8A, lines: 5),
        uploadedBy: world.persona('musteri'),
      );
      img['canDelete'] = false;
    }
    if (financeOrder != null) {
      instruments.add(
        instrument(
          kind: 1,
          customerId: financeOrder['customerId'] as int,
          orderId: financeOrder['id'] as int,
          orderNumber: financeOrder['orderNumber'] as String,
          serialNo: 'CK-7712093',
          bankName: 'İş Bankası',
          branchName: 'İzmit',
          drawerName: 'Marmara İnşaat Taahhüt Ltd. Şti.',
          amount: (financeOrder['estimatedAmount'] as num).toDouble(),
          dueDate: TrTime.addDays(now, 62),
          status: 1,
          createdAt: now,
        ),
      );
    }
    instruments.addAll([
      instrument(
        kind: 1,
        customerId: 104,
        serialNo: 'CK-3301458',
        bankName: 'Garanti BBVA',
        branchName: 'Körfez',
        drawerName: 'Körfez Nakliyat ve Ticaret',
        amount: 185000,
        dueDate: TrTime.addDays(now, -10),
        status: 5,
        note: 'Karşılıksız: hesapta yeterli bakiye yok.',
        createdAt: TrTime.addDays(now, -55),
      ),
      instrument(
        kind: 2,
        customerId: 103,
        debtorName: 'Ege Tarım Kooperatifi',
        guarantorName: 'Hasan Er',
        amount: 96000,
        dueDate: TrTime.addDays(now, 2),
        status: 2,
        createdAt: TrTime.addDays(now, -40),
      ),
      instrument(
        kind: 1,
        customerId: 101,
        serialNo: 'CK-1188334',
        bankName: 'Akbank',
        branchName: 'Kurtköy',
        drawerName: 'Anadolu Lojistik A.Ş.',
        amount: 250000,
        dueDate: TrTime.addDays(now, 18),
        status: 3,
        createdAt: TrTime.addDays(now, -30),
      ),
      instrument(
        kind: 3,
        customerId: 102,
        bankName: 'İş Bankası',
        branchName: 'İzmit Ticari',
        amount: 500000,
        dueDate: TrTime.addDays(now, 200),
        status: 2,
        createdAt: TrTime.addDays(now, -120),
      ),
    ]);

    if (transferOrder != null) {
      final id = transferOrder['id'] as int;
      final dekont = fakeAttachment(
        world,
        ownerType: AttachmentOwnerType.order.code,
        ownerId: id,
        kind: AttachmentKind.transferReceipt.code,
        fileName: 'havale-dekontu.png',
        contentType: 'image/png',
        bytes: fakeDocumentPng(accent: 0x166534, lines: 6),
        uploadedBy: world.persona('musteri'),
      );
      dekont['canDelete'] = false;
      paymentHistory[id] = [
        {
          'fromStatus': 1,
          'toStatus': 2,
          'note': 'Dekont müşteri tarafından yüklendi.',
          'attachmentId': 1,
          'attachmentPublicId': dekont['publicId'],
          'changedByUserId': 'u-musteri',
          'changedByDisplay': 'Selin Aydın',
          'changedAt': utc(TrTime.addDays(now, -1)),
          'changedAtUtc': utc(TrTime.addDays(now, -1)),
          'fromStatusLabel': PaymentStatus.pending.label,
          'toStatusLabel': PaymentStatus.documentUploaded.label,
        },
      ];
    }
    if (collected != null) {
      paymentHistory[collected['id'] as int] = [
        {
          'fromStatus': 1,
          'toStatus': 3,
          'note': 'Havale hesaba geçti.',
          'attachmentId': null,
          'attachmentPublicId': null,
          'changedByUserId': 'u-muhasebe',
          'changedByDisplay': 'Zeynep Arslan',
          'changedAt': utc(TrTime.addDays(now, -6)),
          'changedAtUtc': utc(TrTime.addDays(now, -6)),
          'fromStatusLabel': PaymentStatus.pending.label,
          'toStatusLabel': PaymentStatus.collected.label,
        },
      ];
    }
  }

  String orderToken(int orderId) => orderTokens.putIfAbsent(orderId, newToken);

  static bool usesInstrument(String? method) =>
      method == 'CEK' || method == 'SENET';

  /// Sunucu `PaymentMethodCatalog.AllowedTransitions` aynası.
  static List<int> paymentTransitions(int from, String? method) {
    if (method == 'AVANS') return from == 3 ? const [5] : const [];
    final instrument = usesInstrument(method);
    return switch (from) {
      1 => const [2, 3, 6],
      2 => instrument ? const [3, 4, 6] : const [3, 6],
      3 => instrument ? const [5, 4] : const [5],
      4 => const [3],
      _ => const [],
    };
  }

  static bool paymentNoteRequired(int to) => to == 4 || to == 5 || to == 6;

  /// Sunucu `PaymentMethodCatalog.AllowedInstrumentTransitions` aynası.
  static List<int> instrumentTransitions(int from) => switch (from) {
    1 => const [2, 3, 4, 5, 6],
    2 => const [3, 4, 5, 6],
    3 => const [4, 5, 6],
    5 => const [7, 4, 6],
    7 => const [4, 6],
    _ => const [],
  };

  static bool instrumentNoteRequired(int to) => to == 5 || to == 6 || to == 7;

  static bool canUpdatePayments(FakePersona p) =>
      p.can(Pg.stationPayments, Perm.edit) &&
      p.hasCap(Caps.paymentStatusUpdate);

  static bool canManageInstruments(FakePersona p) =>
      p.can(Pg.stationPayments, Perm.edit) &&
      (p.hasCap(Caps.paymentInstrumentManage) ||
          p.hasCap(Caps.paymentStatusUpdate));

  /// Yöntemin belge türü ("Dekont ekle").
  static (int?, bool) documentOf(String? method) => switch (method) {
    'HAVALE' => (AttachmentKind.transferReceipt.code, false),
    'KART' => (AttachmentKind.posSlip.code, false),
    'DBS' => (AttachmentKind.dbsContract.code, false),
    'CEK' => (AttachmentKind.chequeImage.code, true),
    'SENET' => (AttachmentKind.promissoryNoteImage.code, true),
    'TEMINAT' => (AttachmentKind.letterOfGuarantee.code, false),
    _ => (null, false),
  };

  static String methodShort(String? code) => switch (code) {
    'NAKIT' => 'Nakit',
    'HAVALE' => 'Havale',
    'KART' => 'Kart',
    'DBS' => 'DBS',
    'CEK' => 'Çek',
    'SENET' => 'Senet',
    'ACIK_HESAP' => 'Açık hesap',
    'TEMINAT' => 'Teminat',
    'UTTS' => 'UTTS',
    'AVANS' => 'Avans',
    _ => code ?? 'Belirtilmemiş',
  };

  /// `PaymentListItemMobileDto`.
  JsonMap paymentRow(JsonMap o) {
    final status = (o['paymentStatus'] as int?) ?? 0;
    final due = TrTime.parseLocal(o['paymentDueDate'] as String?);
    final today = TrTime.todayStart();
    final open = status == 1 || status == 2 || status == 4;
    final days = due == null ? null : TrTime.dayDiff(today, due);
    final overdue = open && days != null && days < 0;
    final method = o['paymentMethodCode'] as String?;
    final term = o['paymentTermDays'] as int?;
    final quotes = (o['quotes'] as List?)?.cast<JsonMap>() ?? const [];
    final latest = quotes.isEmpty ? null : quotes.last;
    final financeStatus = (o['financeStatus'] as int?) ?? 0;
    return {
      'orderId': o['id'],
      'orderNumber': o['orderNumber'],
      'stationId': o['stationId'],
      'stationTitle': o['stationTitle'],
      'customerId': o['customerId'],
      'customerTitle': o['customerTitle'],
      'orderStatus': o['status'],
      'methodCode': method,
      'methodName': FakeWorld.paymentMethodNames[method] ?? method,
      'termDays': term,
      'dueDate': o['paymentDueDate'],
      'installments': o['paymentInstallments'],
      'paymentStatus': status,
      'financeStatus': financeStatus,
      'estimatedAmount': o['estimatedAmount'],
      'amount': latest?['totalAmountTry'],
      'isOverdue': overdue,
      'createdAt': o['createdAt'],
      'paymentStatusLabel': method == null
          ? 'Belirtilmemiş'
          : PaymentStatus.fromCode(status).label,
      'financeLabel': financeStatus == 0
          ? null
          : OrderFinanceStatus.fromCode(financeStatus).label,
      'orderStatusLabel': OrderStatus.fromCode(o['status'] as int?).label,
      'paymentLine': [
        methodShort(method),
        if (term != null && term > 0) '$term gün',
        if (due != null) 'vade ${Fmt.date(due)}',
      ].join(' · '),
      'dueHint': !open || days == null
          ? null
          : days == 0
          ? 'bugün'
          : days > 0
          ? '$days gün kaldı'
          : '${-days} gün gecikti',
      'overdueDays': overdue ? -days : 0,
    };
  }

  JsonMap? instrumentOfOrder(int orderId) {
    for (final i in instruments) {
      if (i['orderId'] == orderId) return i;
    }
    return null;
  }

  /// `PaymentInstrumentMobileDto`.
  JsonMap instrumentJson(FakePersona p, JsonMap i) {
    final status = i['status'] as int;
    final allowed = canManageInstruments(p)
        ? instrumentTransitions(status)
        : const <int>[];
    final due = TrTime.parseLocal(i['dueDate'] as String?);
    final open = status == 1 || status == 2 || status == 3;
    final days = due == null ? null : TrTime.dayDiff(TrTime.todayStart(), due);
    return {
      ...i,
      'kindLabel': InstrumentKind.fromCode(i['kind'] as int?).label,
      'statusLabel': InstrumentStatus.fromCode(status).label,
      'allowedTransitions': allowed,
      'noteRequiredFor': [
        for (final s in allowed)
          if (instrumentNoteRequired(s)) s,
      ],
      'isOverdue': open && days != null && days < 0,
      'dueHint': !open || days == null
          ? null
          : days == 0
          ? 'bugün'
          : days > 0
          ? '$days gün kaldı'
          : '${-days} gün geçti',
      'createdAtUtc': i['createdAt'],
    };
  }

  /// `PaymentMobileDetailDto`.
  JsonMap paymentDetail(FakePersona p, JsonMap o) {
    final id = o['id'] as int;
    final row = paymentRow(o);
    final method = o['paymentMethodCode'] as String?;
    final status = (o['paymentStatus'] as int?) ?? 0;
    final effective = status;
    final allowed = canUpdatePayments(p) && status != 0
        ? paymentTransitions(effective, method)
        : const <int>[];
    final inst = instrumentOfOrder(id);
    final (docKind, docRequired) = documentOf(method);
    final documents = [
      for (final a in world.attachments.reversed)
        if (a['isActive'] == true &&
            ((a['ownerType'] == AttachmentOwnerType.order.code &&
                    a['ownerId'] == id) ||
                (inst != null &&
                    a['ownerType'] ==
                        AttachmentOwnerType.paymentInstrument.code &&
                    a['ownerId'] == inst['id'])))
          a,
    ];
    final details = <String, String>{};
    final lines = <JsonMap>[];
    if (inst != null) {
      void put(String key, String label, Object? v) {
        if (v == null) return;
        details[key] = '$v';
        lines.add({'label': label, 'value': '$v'});
      }

      put('serialNo', 'Çek / senet no', inst['serialNo']);
      put('bank', 'Banka', inst['bankName']);
      put('branch', 'Şube', inst['branchName']);
      put('drawer', 'Keşideci', inst['drawerName']);
      put('debtor', 'Borçlu', inst['debtorName']);
      lines.add({'label': 'Tutar', 'value': Fmt.money(inst['amount'] as num)});
      lines.add({
        'label': 'Vade tarihi',
        'value': Fmt.date(TrTime.parseLocal(inst['dueDate'] as String?)),
      });
    }
    return {
      ...row,
      'paymentGroupKey': null,
      'details': details,
      'detailLines': lines,
      'history': paymentHistory[id] ?? const <JsonMap>[],
      'instrument': inst == null ? null : instrumentJson(p, inst),
      'allowedTransitions': allowed,
      'noteRequiredFor': [
        for (final s in allowed)
          if (paymentNoteRequired(s)) s,
      ],
      'concurrencyToken': orderToken(id),
      'canEditInstrument': usesInstrument(method) && canManageInstruments(p),
      'documents': documents,
      'documentKind': docKind,
      'documentKindLabel': docKind == null
          ? null
          : AttachmentKind.fromCode(docKind).label,
      'documentRequired': docRequired,
      'notice': usesInstrument(method)
          ? 'Tahsil / karşılıksız / iade, aynı çek / senetle ödenen grup siparişlerine de uygulanır.'
          : null,
    };
  }

  /// `POST payments/{orderId}/status`.
  void changePaymentStatus(FakePersona p, JsonMap o, JsonReader body) {
    final id = o['id'] as int;
    final token = body.str('concurrencyToken');
    if (token.isEmpty) {
      throw FakeResponse.validation({
        'concurrencyToken': ['Sipariş sürümü okunamadı; ekranı yenileyin.'],
      });
    }
    if (token != orderToken(id)) {
      throw FakeResponse.conflict(
        'concurrency_conflict',
        'Sipariş siz açtıktan sonra değişti; güncel hâlini görüp yeniden deneyin.',
      );
    }
    final from = (o['paymentStatus'] as int?) ?? 0;
    final to = body.intOrNull('toStatus') ?? 0;
    final allowed = canUpdatePayments(p)
        ? paymentTransitions(from, o['paymentMethodCode'] as String?)
        : const <int>[];
    if (!allowed.contains(to)) {
      throw FakeResponse.validation({
        'toStatus': [
          'Ödeme durumu "${PaymentStatus.fromCode(from).label}" → "${PaymentStatus.fromCode(to).label}" olarak değiştirilemez.',
        ],
      }, 'Bu durum değişikliği yapılamaz.');
    }
    final note = body.nonEmpty('note');
    if (paymentNoteRequired(to) && (note == null || note.length < 3)) {
      throw FakeResponse.validation({
        'note': [
          '"${PaymentStatus.fromCode(to).label}" için gerekçe girin (en az 3 karakter).',
        ],
      }, 'Gerekçe girin.');
    }
    final attachment = body.nonEmpty('attachmentPublicId');
    if (attachment != null) {
      final inst = instrumentOfOrder(id);
      final belongs = world.attachments.any(
        (a) =>
            a['publicId'] == attachment &&
            a['isActive'] == true &&
            ((a['ownerType'] == AttachmentOwnerType.order.code &&
                    a['ownerId'] == id) ||
                (inst != null &&
                    a['ownerType'] ==
                        AttachmentOwnerType.paymentInstrument.code &&
                    a['ownerId'] == inst['id'])),
      );
      if (!belongs) {
        throw FakeResponse.validation({
          'attachmentPublicId': ['Seçilen belge bu siparişe ait değil.'],
        }, 'Seçilen belge bu siparişe ait değil.');
      }
    }
    o['paymentStatus'] = to;
    orderTokens[id] = newToken();
    final now = DateTime.now().toUtc();
    (paymentHistory[id] ??= []).add({
      'fromStatus': from,
      'toStatus': to,
      'note': note,
      'attachmentId': attachment == null ? null : 1,
      'attachmentPublicId': attachment,
      'changedByUserId': p.userId,
      'changedByDisplay': p.displayName,
      'changedAt': utc(now),
      'changedAtUtc': utc(now),
      'fromStatusLabel': PaymentStatus.fromCode(from).label,
      'toStatusLabel': PaymentStatus.fromCode(to).label,
    });
    if (to == PaymentStatus.collected.code ||
        to == PaymentStatus.bounced.code) {
      for (final key in const ['musteri', 'onay', 'talep']) {
        final c = world.persona(key);
        if (c == null || c.customerId != o['customerId']) continue;
        world.addNotification(
          userId: c.userId,
          category: 'payments',
          eventCode: to == 3 ? 'payment.collected' : 'payment.bounced',
          title: to == 3 ? 'Ödemeniz alındı' : 'Ödeme durumunuz güncellendi',
          body: to == 3
              ? '${o['orderNumber']} ödemesi tahsil edildi.'
              : 'Ödeme durumunuz güncellendi; bayinizle görüşün.',
          route: '/orders/$id',
          entityType: 'Order',
          entityId: id,
          severity: to == 3 ? 1 : 2,
        );
      }
    }
  }

  /// Sunucunun `PaymentDocumentUploadListener` → `PaymentTrackingService.OnDocumentUploadedAsync`
  /// aynası: bekleyen ödemeye yöntemin belgesi (dekont, POS slibi, çek / senet görseli…) yüklenince
  /// ödeme ve aynı ödeme grubundaki bekleyen siparişler "Belge yüklendi" olur; her siparişin sürüm
  /// belirteci yenilenir (eski belirteçle durum değişikliği 409 alır).
  void onDocumentUploaded(JsonMap attachment, FakePersona? by) {
    final ownerType = attachment['ownerType'] as int?;
    final ownerId = attachment['ownerId'] as int?;
    int? orderId;
    if (ownerType == AttachmentOwnerType.order.code) {
      orderId = ownerId;
    } else if (ownerType == AttachmentOwnerType.paymentInstrument.code) {
      for (final i in instruments) {
        if (i['id'] == ownerId) orderId = i['orderId'] as int?;
      }
    }
    final o = world.order(orderId);
    if (o == null) return;
    bool pendingOpen(JsonMap x) =>
        x['paymentStatus'] == PaymentStatus.pending.code &&
        x['status'] != OrderStatus.rejected.code &&
        x['status'] != OrderStatus.expired.code;
    if (!pendingOpen(o)) return;
    final method = o['paymentMethodCode'] as String?;
    final (docKind, _) = documentOf(method);
    if (docKind == null || docKind != attachment['kind']) return;
    final group = o['paymentGroupKey'];
    final targets = [
      o,
      if (group != null)
        for (final x in world.orders)
          if (!identical(x, o) &&
              x['paymentGroupKey'] == group &&
              x['stationId'] == o['stationId'] &&
              x['paymentMethodCode'] == method &&
              pendingOpen(x))
            x,
    ];
    final now = DateTime.now().toUtc();
    final kindLabel = AttachmentKind.fromCode(docKind).label;
    for (final t in targets) {
      final id = t['id'] as int;
      t['paymentStatus'] = PaymentStatus.documentUploaded.code;
      orderTokens[id] = newToken();
      (paymentHistory[id] ??= []).add({
        'fromStatus': PaymentStatus.pending.code,
        'toStatus': PaymentStatus.documentUploaded.code,
        'note': 'Belge yüklendi: $kindLabel',
        'attachmentId': null,
        'attachmentPublicId': attachment['publicId'],
        'changedByUserId': by?.userId,
        'changedByDisplay': by?.displayName,
        'changedAt': utc(now),
        'changedAtUtc': utc(now),
        'fromStatusLabel': PaymentStatus.pending.label,
        'toStatusLabel': PaymentStatus.documentUploaded.label,
      });
    }
  }

  /// `POST payments/instruments/{id}/status`.
  void changeInstrumentStatus(FakePersona p, JsonMap i, JsonReader body) {
    final from = i['status'] as int;
    final to = body.intOrNull('toStatus') ?? 0;
    final allowed = canManageInstruments(p)
        ? instrumentTransitions(from)
        : const <int>[];
    if (!allowed.contains(to)) {
      throw FakeResponse.validation({
        'toStatus': [
          'Belge durumu "${InstrumentStatus.fromCode(from).label}" → "${InstrumentStatus.fromCode(to).label}" olarak değiştirilemez.',
        ],
      }, 'Bu durum değişikliği yapılamaz.');
    }
    final note = body.nonEmpty('note');
    if (instrumentNoteRequired(to) && (note == null || note.length < 3)) {
      throw FakeResponse.validation({
        'note': [
          '"${InstrumentStatus.fromCode(to).label}" için açıklama girin (en az 3 karakter).',
        ],
      }, 'Açıklama girin.');
    }
    i['status'] = to;
    if (note != null) i['note'] = note;
    final orderId = i['orderId'] as int?;
    final order = world.order(orderId);
    if (order != null) {
      if (to == InstrumentStatus.collected.code) {
        order['paymentStatus'] = PaymentStatus.collected.code;
      } else if (to == InstrumentStatus.bounced.code) {
        order['paymentStatus'] = PaymentStatus.bounced.code;
      }
      orderTokens[orderId!] = newToken();
    }
  }

  // ═══════════════════════════════════════════════════════════════ Ortak

  /// Sorgu metni eşleşiyor mu (Türkçe duyarsız: "ŞİŞLİ" ile "sisli" eşleşir).
  static bool matches(Iterable<Object?> fields, String? q) {
    final query = q?.trim() ?? '';
    if (query.isEmpty) return true;
    return fields.any((f) => f != null && TurkishText.matches('$f', query));
  }
}

/// Olay türleri (sahte günlük için; uygulamadaki ApprovalEventType ile aynı kodlar).
enum ApprovalEventKind {
  created(1, 'Oluşturuldu'),
  viewed(2, 'Görüntülendi'),
  attachmentViewed(3, 'Belge açıldı'),
  approved(5, 'Onaylandı'),
  conditionallyApproved(6, 'Koşullu onaylandı'),
  rejected(7, 'Reddedildi'),
  infoRequested(8, 'Ek bilgi istendi'),
  infoProvided(9, 'Ek bilgi verildi'),
  reminded(10, 'Hatırlatma gönderildi'),
  escalated(11, 'Üst kademeye yükseltildi');

  const ApprovalEventKind(this.code, this.label);
  final int code;
  final String label;
}
