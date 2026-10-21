// Sözleşme örnekleri (spec D.3 A-INT, D.4): sunucu yanıtları uygulamanın Dart modelleriyle okunur ve
// önemli alanlar beklenen değeri verir. Bir alan adı sunucuda değişirse ya da modelde yanlış yazılırsa
// bu test kırılır.
//
// - `test/contract/server/`: arka ucun gerçek koduyla ürettiği örnekler (B-INT,
//   `tests/AkaryakitNet.Tests/MobileContractSamplesTests.cs`) ve `index.json`. Her dosyanın bir okuyucusu
//   ([_serverParsers]) olmalı; değer denetimleri [_serverChecks]. Yenilemek için
//   `tool/sync_contract_samples.sh`. Arka ucun çıktı klasörü bu makinedeyse
//   (`$W/akn-mobile/contract-samples` ya da `--dart-define=AKN_CONTRACT_SAMPLES=<klasör>`) oradaki
//   dosyalar da okunur (kopya eskidiyse yeni dosya okuyucu ister).
// - `stats-bayi.json` / `stats-customer.json`: arka ucun `MobileStatsTests` sınıfının aynı klasöre yazdığı
//   istatistik örnekleri (`AKN_WRITE_STATS_SAMPLES=1`; index.json'da yer almaz). [_statsSamples] ile
//   uygulamanın `BayiStats` / `CustomerStats` modelleriyle okunur.
// - `test/contract/samples/*.json`: C# DTO sınıflarından elle çıkarılmış örnekler (sunucunun henüz örnek
//   üretmediği yanıtlar: şoför teslimat detayı, bildirimler, okunmamış sayıları).
// - Enum kodları sunucudaki `Core/Enums` değerleriyle karşılaştırılır (anlık görüntü).
import 'dart:convert';
import 'dart:io';

import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/permissions.dart';
import 'package:akaryakitnet/core/models/app_config.dart';
import 'package:akaryakitnet/core/models/auth_models.dart';
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/models/paged_result.dart';
import 'package:akaryakitnet/core/models/unread_count.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/failure_copy.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/approvals/data/approval_models.dart';
import 'package:akaryakitnet/features/bayi/data/desk_models.dart';
import 'package:akaryakitnet/features/bayi/data/dispatch_models.dart' as bayi;
import 'package:akaryakitnet/features/customer_more/data/finance_info.dart';
import 'package:akaryakitnet/features/customer_more/data/shipments.dart'
    as customer;
import 'package:akaryakitnet/features/driver/data/driver_models.dart';
import 'package:akaryakitnet/features/notifications/data/notification_models.dart';
import 'package:akaryakitnet/features/stats/data/stats_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _externalDir = String.fromEnvironment('AKN_CONTRACT_SAMPLES');
const _defaultExternal =
    '/Users/f2gomac/.claude/projects/-Users-f2gomac-Desktop-Akaryak-tNet/work/akn-mobile/contract-samples';

Object? _sample(String name) =>
    jsonDecode(File('test/contract/samples/$name.json').readAsStringSync());

/// Örnek adı → okuma ve temel denetim (B-INT örnekleri için de kullanılır).
final Map<String, void Function(Object? json)> _parsers = {
  'me_access': (j) {
    final m = MeAccess.fromJson(j);
    expect(m.userId, isNotEmpty);
    expect(m.persona, isNot(Persona.unknown));
  },
  'app_config': (j) {
    final c = AppConfig.fromJson(j);
    expect(c.minBuild, greaterThanOrEqualTo(1));
    expect(c.contractVersion, anyOf(isNull, 'mobile-v1'));
  },
  'auth_result_ok': (j) => expect(AuthResult.fromJson(j).isOk, isTrue),
  'auth_result_two_factor': (j) =>
      expect(AuthResult.fromJson(j).needsCode, isTrue),
  'finance_info': (j) => expect(FinanceInfo.fromJson(j), isNotNull),
  'shipment_detail_customer': (j) =>
      expect(customer.ShipmentDetail.fromJson(j).id, greaterThan(0)),
  'shipment_detail_bayi': (j) =>
      expect(bayi.ShipmentDetail.fromJson(j).id, greaterThan(0)),
  'approval_detail_condition': (j) =>
      expect(ApprovalDetail.fromJson(j).row.id, greaterThan(0)),
  'driver_shipment_detail': (j) =>
      expect(DriverShipmentDetail.fromJson(j).row.id, greaterThan(0)),
  'bayi_quote_desk': (j) => expect(DeskPage.fromJson(j), isNotNull),
  'notifications_page': (j) => expect(
    PagedResult.fromJson(j, UserNotification.fromJson).items,
    isNotEmpty,
  ),
  'unread_count': (j) => expect(UnreadCount.fromJson(j), isNotNull),
};

const _serverDir = 'test/contract/server';

Set<String> _jsonFilesIn(Directory dir) => {
  for (final f in dir.listSync().whereType<File>())
    if (f.path.endsWith('.json') && !f.path.endsWith('/index.json'))
      f.uri.pathSegments.last,
};

/// İstatistik örnekleri (arka uç `MobileStatsTests`, index.json dışında): dosya → okuyucu.
final Map<String, Object Function(Object? json)> _statsSamples = {
  'stats-bayi.json': (j) => BayiStats.fromJson(j),
  'stats-customer.json': (j) => CustomerStats.fromJson(j),
};

/// Sözleşmenin şekli: her bölüm dolu okunur, dönem ve karşılaştırma tarihleri gelir (değerlerden bağımsız;
/// arka ucun güncel çıktısı için de geçerli).
void _checkStatsShape(String file, Object parsed) {
  void period(StatsPeriodInfo p) {
    expect(p.key, StatsPeriod.month, reason: '$file period.key');
    expect(p.label, isNotNull, reason: '$file period.label');
    expect(p.from, isNotNull, reason: '$file period.from');
    expect(p.to, isNotNull, reason: '$file period.to');
    expect(p.compareLabel, isNotNull, reason: '$file period.compareLabel');
    expect(p.compareFrom, isNotNull, reason: '$file period.compareFrom');
    expect(p.compareTo, isNotNull, reason: '$file period.compareTo');
  }

  void months(List<StatsMonth> m) {
    expect(m, hasLength(6), reason: '$file months');
    for (final x in m) {
      expect(x.month, inInclusiveRange(1, 12));
      expect(x.label, isNotNull, reason: '$file months[].label');
    }
  }

  switch (parsed) {
    case final BayiStats b:
      expect(b.stationId, isNotNull);
      expect(b.stationTitle, isNotNull);
      expect(b.scope, anyOf('station', 'own'));
      expect(b.generatedAt, isNotNull);
      expect(b.generatedAt!.isUtc, isTrue);
      period(b.period);
      expect(b.sales, isNotNull, reason: '$file sales');
      months(b.months);
      expect(b.products, isNotEmpty, reason: '$file products');
      expect(b.topCustomers, isNotEmpty, reason: '$file topCustomers');
      expect(b.funnel, isNotNull, reason: '$file funnel');
      expect(b.deliveries, isNotNull, reason: '$file deliveries');
      expect(b.collections, isNotNull, reason: '$file collections');
      expect(b.team, isNotEmpty, reason: '$file team');
      expect(b.risk, isNotNull, reason: '$file risk');
      expect(b.failedSections, isEmpty);
      expect(b.isBlank, isFalse);
    case final CustomerStats c:
      expect(c.customerId, isNotNull);
      expect(c.customerTitle, isNotNull);
      expect(c.generatedAt, isNotNull);
      expect(c.generatedAt!.isUtc, isTrue);
      period(c.period);
      expect(c.spending, isNotNull, reason: '$file spending');
      months(c.months);
      expect(c.products, isNotEmpty, reason: '$file products');
      expect(c.stations, isNotEmpty, reason: '$file stations');
      expect(c.deliveryPoints, isNotEmpty, reason: '$file deliveryPoints');
      expect(c.orders, isNotNull, reason: '$file orders');
      expect(c.limits, isNotEmpty, reason: '$file limits');
      expect(c.failedSections, isEmpty);
      expect(c.isBlank, isFalse);
    default:
      fail('$file: beklenmeyen model ${parsed.runtimeType}');
  }
}

/// `index.json` satırı: dosya → uç nokta, DTO.
class _ServerEntry {
  const _ServerEntry(this.file, this.endpoint, this.dto);

  final String file;

  /// `GET api/v1/...` ya da hata örneklerinde `429 rate_limited`.
  final String endpoint;
  final String dto;

  Object? read(Directory dir) =>
      jsonDecode(File('${dir.path}/$file').readAsStringSync());
}

class _ServerIndex {
  const _ServerIndex(this.contractVersion, this.entries);

  factory _ServerIndex.read(Directory dir) {
    final j = JsonReader.of(
      jsonDecode(File('${dir.path}/index.json').readAsStringSync()),
    );
    return _ServerIndex(j.str('contractVersion'), [
      for (final s in j.list('samples', (r) => r))
        _ServerEntry(s.str('file'), s.str('endpoint'), s.str('dto')),
    ]);
  }

  static _ServerEntry entry(_ServerIndex index, String file) =>
      index.entries.firstWhere((e) => e.file == file);

  final String contractVersion;
  final List<_ServerEntry> entries;

  List<String> get files => [for (final e in entries) e.file];
}

/// Hata örnekleri: durum kodu `endpoint`in ilk sözcüğüdür (`400 validation`). Başlık yok; 429'da bekleme
/// gövdedeki `retryAfter`dan okunur.
AppFailure _problem(Object? json, String endpoint) =>
    AppFailure.fromResponse(int.parse(endpoint.split(' ').first), json);

AccessPolicy _policy(Object? json) => AccessPolicy(MeAccess.fromJson(json));

/// Sunucu örneği → uygulama modeli (ekranların kullandığı okuyucular).
final Map<String, Object? Function(Object? json, String endpoint)>
_serverParsers = {
  'shipments-id-detail.bayi.json': (j, _) => bayi.ShipmentDetail.fromJson(j),
  'shipments-id-detail.customer.json': (j, _) =>
      customer.ShipmentDetail.fromJson(j),
  'bayi-quote-desk.json': (j, _) => DeskPage.fromJson(j),
  'bayi-quote-desk-counts.json': (j, _) => DeskCountsResult.fromJson(j),
  'bayi-quote-desk-submit.json': (j, _) =>
      JsonReader.parseList(j, DeskSubmitResult.fromJson),
  'customers-me-finance-info.json': (j, _) => FinanceInfo.fromJson(j),
  'approvals-id.order-finance.json': (j, _) => ApprovalDetail.fromJson(j),
  'approvals-condition-form.customer-onboarding.json': (j, _) =>
      ConditionForm.fromJson(JsonReader.of(j)),
  'me-access.bayi.json': (j, _) => _policy(j),
  'me-access.customer.json': (j, _) => _policy(j),
  'app-config.json': (j, _) => AppConfig.fromJson(j),
  'auth-login.ok.json': (j, _) => AuthResult.fromJson(j),
  'auth-login.two-factor.json': (j, _) => AuthResult.fromJson(j),
  'problem.validation.json': _problem,
  'problem.business-rule.json': _problem,
  'problem.concurrency-conflict.json': _problem,
  'problem.rate-limited.json': _problem,
  'problem.session-revoked.json': _problem,
};

/// Değer denetimleri (`test/contract/server/` kopyasına göre).
final Map<String, void Function(Object? parsed)> _serverChecks = {
  'shipments-id-detail.bayi.json': (o) {
    final s = o! as bayi.ShipmentDetail;
    expect(s.viewerSide, 'bayi');
    expect(s.code, 'SVK-00000001');
    expect(s.status, ShipmentStatus.reported);
    expect(s.scheduledAt, DateTime.utc(2026, 10, 21, 6));
    expect(s.deliveredAt, DateTime.utc(2026, 10, 21, 7, 5));
    expect(s.timeSource, 'device');
    expect(s.driverUserId, isNotEmpty);
    expect(s.isAppDriver, isTrue);
    expect(s.driverLabel, 'Ali Yılmaz');
    expect(s.signatureWaiverLabel, 'İmzadan imtina');
    expect(s.deliveredAccuracyMeters, 12.4);
    expect(s.distanceToDeliveryPointMeters, 41);
    expect(s.reportedByName, 'Ali Yılmaz');
    expect(s.deliveryPoint.name, 'Aliağa Depo');
    expect(s.deliveryPoint.windowEnd, '17:30');
    expect(s.proofAttachments.map((a) => a.kind), [
      AttachmentKind.deliveryPhoto,
      AttachmentKind.deliverySignature,
    ]);
    expect(s.disputeAttachments, isEmpty);
    expect(s.actions.canDispatch, isFalse);
    expect(s.actions.canReassign, isFalse);
  },
  'shipments-id-detail.customer.json': (o) {
    final s = o! as customer.ShipmentDetail;
    expect(s.viewerSide, 'customer');
    expect(s.status, ShipmentStatus.reported);
    expect(s.deliveredLiters, 7985.5);
    expect(s.differenceLiters, -14.5);
    expect(s.deviceDeliveredAtUtc, DateTime.utc(2026, 10, 21, 7, 5));
    expect(s.deliveryDocumentNo, 'IRS-2026-0042');
    expect(s.recipientName, 'Mehmet Kaya');
    expect(s.signatureWaiverLabel, 'İmzadan imtina');
    expect(s.place.windowStart, '08:00');
    expect(s.attachments, hasLength(2));
    expect(s.actions.canAccept, isTrue);
    expect(s.actions.canDispute, isTrue);
    expect(s.actions.canAddDisputePhoto, isTrue);
    expect(s.isDelivered, isTrue);
  },
  'bayi-quote-desk.json': (o) {
    final p = o! as DeskPage;
    expect(p.header.expiryEnabled, isTrue);
    expect(p.header.financeHeld, 2);
    expect(p.header.canSubmit, isTrue);
    expect(p.header.maxBatch, 50);
    expect(p.view, DeskView.all);
    expect(p.sort, DeskSort.expiry);
    expect(p.serverTime, DateTime.utc(2026, 10, 21, 7, 30));
    final first = p.rows.first;
    expect(first.status, OrderStatus.awaitingQuote);
    expect(first.expiresAt, DateTime.utc(2026, 10, 21, 9, 5));
    expect(first.suggestedUnitPrice, 44.95);
    expect(first.suggestedLabel, 'cariye özel fiyat');
    expect(first.defaultDeliveryDate, DateTime.utc(2026, 10, 21, 21));
    expect(first.secondsLeft, 5700);
    expect(first.recentPrices.map((r) => r.unitPriceTry), [44.85, 44.1]);
    expect(first.payChip!.tone, 'warn');
    final revision = p.rows.last;
    expect(revision.isRevision, isTrue);
    expect(revision.latestUnitPriceTry, 45.4);
    expect(revision.latestRevisionNote, contains('yüksek'));
    expect(revision.paymentTermDays, 60);
    expect(revision.payChip!.financeLabel, 'Finans onaylandı');
    expect(p.counts.of(DeskView.expiringSoon), 1);
    expect(p.counts.financeHeld, 2);
    expect(p.today.avgFirstQuoteMinutes, 21);
    expect(p.hasMore, isFalse);
  },
  'bayi-quote-desk-counts.json': (o) {
    final c = o! as DeskCountsResult;
    expect(c.expiryEnabled, isTrue);
    expect(c.counts.all, 2);
    expect(c.counts.revision, 1);
    expect(c.counts.expiringSoon, 1);
    expect(c.today.ordersToday, 9);
  },
  'bayi-quote-desk-submit.json': (o) {
    final r = o! as List<DeskSubmitResult>;
    expect(r.map((x) => x.outcome), [
      DeskOutcome.quoted,
      DeskOutcome.routedToFinance,
    ]);
    expect(r.map((x) => x.success), [true, false]);
    expect(r.last.label, 'Finans onayına gönderildi');
    expect(r.last.message, contains('finans onayına'));
  },
  'customers-me-finance-info.json': (o) {
    final f = o! as FinanceInfo;
    expect(f.links, hasLength(2));
    final blocked = f.links.first;
    expect(blocked.status.canOrder, isFalse);
    expect(blocked.status.profileStatus, FinanceProfileStatus.infoRequested);
    expect(blocked.status.openApprovalRequestId, 1);
    expect(blocked.requestStatus, ApprovalStatus.infoRequested);
    expect(blocked.requiredKind, AttachmentKind.taxPlate);
    expect(blocked.kindLabel, 'Vergi levhası');
    expect(blocked.canReply, isTrue);
    expect(blocked.needsReply, isTrue);
    final open = f.links.last;
    expect(open.status.canOrder, isTrue);
    expect(open.requestId, isNull);
    expect(open.needsReply, isFalse);
    final order = f.orders.single;
    expect(order.requestId, 2);
    expect(order.requiredKind, AttachmentKind.chequeImage);
    expect(order.createdAt, DateTime.utc(2026, 10, 21, 5, 30));
    expect(f.pendingReplies, 2);
  },
  'approvals-id.order-finance.json': (o) {
    final a = o! as ApprovalDetail;
    expect(a.row.id, 9101);
    expect(a.row.type, ApprovalType.orderFinance);
    expect(a.row.status, ApprovalStatus.pending);
    expect(a.row.canDecide, isTrue);
    expect(a.row.amount, 899000);
    expect(a.row.dueAt, DateTime.utc(2026, 10, 22, 5, 30));
    expect(a.concurrencyToken, startsWith('2f6d7c9e'));
    expect(a.modes, [
      ApprovalDecision.approve,
      ApprovalDecision.conditionalApprove,
      ApprovalDecision.requestInfo,
      ApprovalDecision.reject,
    ]);
    expect(a.modeLabels, hasLength(4));
    expect(a.summary.headline, startsWith('AYN-20261021-0107'));
    expect(a.summary.facts.map((f) => f.label), contains('Limit kullanımı'));
    expect(a.summary.band?.key, 'limit');
    expect(a.summary.links.orderId, 107);
    expect(a.summary.links.stationCustomerId, 31);
    expect(a.summary.warnings, hasLength(1));
    final form = a.conditionForm!;
    expect(form.keys, {'methodCode', 'termDays'});
    expect(form.methodName('ACIK_HESAP'), 'Açık hesap');
    expect(
      form.methodOptions.firstWhere((m) => m.code == 'CEK').maxTermDays,
      120,
    );
    expect(a.decisionHint, isNull);
    expect(a.customerView, isFalse);
  },
  'approvals-condition-form.customer-onboarding.json': (o) {
    final f = o! as ConditionForm;
    const known = {
      ConditionFieldTypes.method,
      ConditionFieldTypes.integer,
      ConditionFieldTypes.money,
      ConditionFieldTypes.period,
      ConditionFieldTypes.riskClass,
      ConditionFieldTypes.percent,
      ConditionFieldTypes.date,
      ConditionFieldTypes.methods,
    };
    for (final field in f.fields) {
      expect(known, contains(field.type), reason: field.key);
    }
    expect(f.keys, {
      'limitAmount',
      'limitPeriod',
      'maxTermDays',
      'allowedMethodCodes',
      'riskClass',
      'collateralRatioPercent',
      'nextReviewDate',
    });
    final risk = f.fields.firstWhere((x) => x.key == 'riskClass');
    expect(risk.current, '2');
    expect(risk.suggestion, '3');
    expect(f.riskClassOptions.map((c) => c.code), ['1', '2', '3', '4']);
    expect(f.periodOptions.first.code, 'Aylık');
    expect(f.fields.first.max, 999999999999);
    expect(f.hint, isNotNull);
  },
  'me-access.bayi.json': (o) {
    final p = o! as AccessPolicy;
    final m = p.access!;
    expect(m.persona, Persona.bayi);
    expect(m.stationId, 1);
    expect(m.isStationOwner, isTrue);
    expect(m.isFieldSalesFlag, isFalse);
    expect(m.phoneVerified, isFalse);
    expect(m.accessVersion, 'cbf104ee483484bf');
    // Rol ataması olmayan sahip: kod gelmez, owner ön ayarı kullanılır.
    expect(m.bayiRoleCodes, isEmpty);
    expect(p.rolePreset, RolePreset.owner);
    expect(p.isApprover, isTrue);
    expect(p.capLimit('approve.finance.order'), isNull);
    expect(p.can(Pg.stationQuoteDesk, Perm.create), isTrue);
    expect(p.canSeeDeliveries, isFalse);
    final layout = buildNavLayout(p, const AppFeatures());
    expect(layout.bar.first.id, DestinationId.home);
    expect(layout.inBar(DestinationId.quoteDesk), isTrue);
    expect(layout.inBar(DestinationId.bayiOrders), isTrue);
    // Onaylarım sayfa yetkisiyle görünür (StationApprovals:Gorur bu örnekte yok).
    expect(layout.contains(DestinationId.approvals), isFalse);
  },
  'me-access.customer.json': (o) {
    final p = o! as AccessPolicy;
    final m = p.access!;
    expect(m.persona, Persona.customer);
    expect(m.customerId, 1);
    expect(m.customerUserRole, CustomerUserRole.requester);
    expect(m.customerUserRoleLabel, 'Talep eden');
    expect(p.rolePreset, RolePreset.customerRequester);
    expect(p.isApprover, isFalse);
    final layout = buildNavLayout(p, const AppFeatures());
    expect(layout.center?.label, 'Sipariş ver');
    expect(layout.inBar(DestinationId.myOrders), isTrue);
    expect(layout.contains(DestinationId.approvals), isFalse);
    expect(layout.contains(DestinationId.financeInfo), isTrue);
    expect(layout.contains(DestinationId.templates), isTrue);
  },
  'app-config.json': (o) {
    final c = o! as AppConfig;
    expect(c.minBuild, 1);
    expect(c.latestBuild, 1);
    expect(c.storeUrl, contains('com.ortakplatform.akaryakitnet'));
    expect(c.features.otpLogin, isTrue);
    expect(c.features.assistant, isFalse);
    expect(c.features.payments, isTrue);
    expect(c.features.orderExpiry, isTrue);
    expect(c.features.deliveryGpsRequired, isFalse);
    expect(c.support.url, endsWith('/legal/support'));
    expect(c.support.phone, isNull);
    expect(c.legal.accountDeletionUrl, endsWith('/legal/account-deletion'));
    expect(c.assistantConsentVersion, '1');
    expect(c.maintenance.active, isFalse);
    expect(c.apiBuild, '17.11.1');
    expect(c.contractMatches, isTrue);
    expect(c.serverTimeUtc, DateTime.utc(2026, 10, 21, 7, 16, 42, 618, 120));
  },
  'auth-login.ok.json': (o) {
    final a = o! as AuthResult;
    expect(a.isOk, isTrue);
    expect(a.needsCode, isFalse);
    expect(a.tokens!.accessExpiresAt, DateTime.utc(2026, 10, 21, 10, 45));
    expect(a.tokens!.refreshExpiresAt, DateTime.utc(2026, 10, 22, 10, 30));
    expect(a.tokens!.userId, '4d70e58b-f794-492a-a028-e3736b5c104a');
    expect(a.tokens!.displayName, 'BAYI');
  },
  'auth-login.two-factor.json': (o) {
    final a = o! as AuthResult;
    expect(a.needsCode, isTrue);
    expect(a.tokens, isNull);
    expect(a.challenge!.maskedPhone, '9053*****07');
    expect(a.challenge!.expiresInSeconds, 300);
    expect(a.challenge!.resendInSeconds, 60);
  },
  'problem.validation.json': (o) {
    final f = o! as ValidationFailure;
    expect(f.code, 'validation');
    expect(f.errorFor('quantityLiters'), "Miktar 0'dan büyük olmalı.");
    expect(f.traceId, 'ornek-iz-0001');
  },
  'problem.business-rule.json': (o) {
    final f = o! as BusinessFailure;
    expect(f.message, startsWith('Bu sipariş şirket içi onaya tabidir'));
    expect(FailureCopy.message(f), f.message);
  },
  'problem.concurrency-conflict.json': (o) {
    final f = o! as ConflictFailure;
    expect(f.isConcurrency, isTrue);
    expect(FailureCopy.title(f), 'Bu kayıt sizden sonra güncellendi');
  },
  'problem.rate-limited.json': (o) {
    final f = o! as RateLimitedFailure;
    expect(f.retryAfter, const Duration(seconds: 42));
    expect(f.isTransient, isTrue);
    expect(
      FailureCopy.message(f),
      'Çok fazla deneme. 42 sn sonra tekrar deneyin.',
    );
  },
  'problem.session-revoked.json': (o) {
    final f = o! as UnauthorizedFailure;
    expect(f.isSessionRevoked, isTrue);
    expect(f.message, startsWith('Oturumunuz sonlandırıldı'));
  },
};

void main() {
  group('Elle çıkarılmış örnekler (C# DTO anahtarları)', () {
    test('me/access (MeAccessDto): yeni bayraklar dahil', () {
      final m = MeAccess.fromJson(_sample('me_access'));
      expect(m.persona, Persona.bayi);
      expect(m.stationId, 12);
      expect(m.bayiRoleCodes, ['owner']);
      expect(m.pages, contains('StationStaff:Duzenler'));
      expect(m.capabilities.first.code, 'approve.finance.order');
      expect(m.capabilities.first.limit, 500000);
      expect(m.delegations.single.approvalType, ApprovalType.orderFinance);
      expect(m.isStationOwner, isTrue);
      expect(m.assignedOpenShipments, 2);
      expect(m.phoneVerified, isTrue);
      expect(m.accessVersion, '9b1c2d3e');
      final p = AccessPolicy(m);
      expect(p.canSeeDeliveries, isTrue);
      expect(p.isApprover, isTrue);
      expect(p.rolePreset, RolePreset.owner);
    });

    test('app/config (AppConfigDto)', () {
      final c = AppConfig.fromJson(_sample('app_config'));
      expect(c.minBuild, 3);
      expect(c.latestBuild, 5);
      expect(c.features.orderExpiry, isTrue);
      expect(c.features.deliveryGpsRequired, isTrue);
      expect(c.support.url, endsWith('/legal/support'));
      expect(c.legal.accountDeletionUrl, endsWith('/legal/account-deletion'));
      expect(c.assistantConsentVersion, '2');
      expect(c.maintenance.active, isFalse);
      expect(c.apiBuild, 'fd59cc7');
      expect(c.contractMatches, isTrue);
      expect(c.serverTimeUtc, DateTime.utc(2026, 10, 21, 9, 15));
    });

    test('auth/login (AuthResultDto): 2FA ve belirteçler', () {
      final two = AuthResult.fromJson(_sample('auth_result_two_factor'));
      expect(two.needsCode, isTrue);
      expect(two.challenge!.challengeId, startsWith('3f1b5c2a'));
      expect(two.challenge!.resendInSeconds, 60);
      final ok = AuthResult.fromJson(_sample('auth_result_ok'));
      expect(ok.isOk, isTrue);
      expect(ok.tokens!.displayName, 'Mehmet Demir');
      expect(ok.tokens!.accessExpiresAt, DateTime.utc(2026, 10, 21, 9, 30));
    });

    test('customers/me/finance-info ({links, orders})', () {
      final f = FinanceInfo.fromJson(_sample('finance_info'));
      final l = f.links.single;
      expect(l.status.canOrder, isFalse);
      expect(l.status.profileStatus, FinanceProfileStatus.infoRequested);
      expect(l.status.openApprovalRequestId, 9004);
      expect(l.requestStatus, ApprovalStatus.infoRequested);
      expect(l.requiredKind, AttachmentKind.signatureCircular);
      expect(l.canReply, isTrue);
      expect(l.needsReply, isTrue);
      final o = f.orders.single;
      expect(o.requestId, 9001);
      expect(o.requiredKind, AttachmentKind.chequeImage);
      expect(f.pendingReplies, 2);
    });

    test('shipments/{id}/detail — müşteri görünümü (kanıt kartı)', () {
      final s = customer.ShipmentDetail.fromJson(
        _sample('shipment_detail_customer'),
      );
      expect(s.status, ShipmentStatus.reported);
      expect(s.viewerSide, 'customer');
      expect(s.deliveredLiters, 11950);
      expect(s.differenceLiters, -50);
      expect(s.deliveryDocumentNo, 'IRS-778812');
      expect(s.recipientName, 'Volkan Ateş');
      expect(s.timeSource, 'device');
      expect(s.place.windowStart, '08:00');
      expect(s.attachments, hasLength(2));
      expect(
        s.attachments.map((a) => a.kind),
        containsAll([
          AttachmentKind.deliveryPhoto,
          AttachmentKind.deliverySignature,
        ]),
      );
      expect(s.actions.canAccept, isTrue);
      expect(s.actions.canAddDisputePhoto, isTrue);
      expect(s.isDelivered, isTrue);
    });

    test('shipments/{id}/detail — bayi görünümü (şoför, konum)', () {
      final s = bayi.ShipmentDetail.fromJson(_sample('shipment_detail_bayi'));
      expect(s.viewerSide, 'bayi');
      expect(s.driverUserId, 'u-sofor');
      expect(s.isAppDriver, isTrue);
      expect(s.deliveredAccuracyMeters, 8.5);
      expect(s.reportedByName, 'Ahmet Kurt');
      expect(s.deliveryPoint.name, 'Pendik Lojistik Merkezi');
      expect(s.actions.canDispatch, isFalse);
    });

    test('approvals/{id} (ApprovalMobileDetailDto) + conditionForm', () {
      final a = ApprovalDetail.fromJson(_sample('approval_detail_condition'));
      expect(a.row.type, ApprovalType.orderFinance);
      expect(a.modes, [
        ApprovalDecision.approve,
        ApprovalDecision.conditionalApprove,
        ApprovalDecision.requestInfo,
        ApprovalDecision.reject,
      ]);
      expect(a.concurrencyToken, startsWith('6f1e2d3c'));
      expect(a.summary.headline, startsWith('SIP-2026-004005'));
      final form = a.conditionForm!;
      expect(form.fields.map((f) => f.key), ['methodCode', 'termDays']);
      expect(form.fields.last.max, 90);
      expect(form.fields.first.current, 'CEK');
      expect(form.methodOptions.map((m) => m.code), ['HAVALE', 'CEK']);
      expect(form.periodOptions.single.label, 'Aylık');
      expect(a.decisionHint, isNull);
      expect(a.customerView, isFalse);
    });

    test('driver/shipments/{id} (DriverShipmentDetailDto)', () {
      final d = DriverShipmentDetail.fromJson(
        _sample('driver_shipment_detail'),
      );
      expect(d.row.status, ShipmentStatus.inTransit);
      expect(d.row.plannedLiters, 8000);
      expect(d.tankCapacityLiters, 30000);
      expect(d.contactPhone, '05321112233');
      expect(d.accessNotes, contains('tank'));
      expect(d.requirements.photo, isTrue);
      expect(d.requirements.signature, isTrue);
      expect(d.requirements.gps, isFalse);
      expect(d.actions.canDeliver, isTrue);
      expect(d.actions.canStart, isFalse);
    });

    test('bayi/quote-desk (BayiQuoteDeskDto)', () {
      final p = DeskPage.fromJson(_sample('bayi_quote_desk'));
      expect(p.header.expiryEnabled, isTrue);
      expect(p.header.financeHeld, 1);
      expect(p.header.quotingBlocked, isFalse);
      expect(p.header.maxBatch, 50);
      final r = p.rows.single;
      expect(r.status, OrderStatus.awaitingQuote);
      expect(r.suggestedUnitPrice, 42.1);
      expect(r.suggestedLabel, 'Liste fiyatı');
      expect(r.secondsLeft, 46800);
      expect(r.payChip!.line, startsWith('Havale'));
      expect(r.recentPrices.single.unitPriceTry, 41.85);
      expect(p.counts.awaitingQuote, 1);
      expect(p.today.avgFirstQuoteMinutes, 37);
    });

    test(
      'notifications (PagedResult<UserNotificationDto>) ve unread-count',
      () {
        final page = PagedResult.fromJson(
          _sample('notifications_page'),
          UserNotification.fromJson,
        );
        expect(page.totalCount, 2);
        final n = page.items.first;
        expect(n.category, 'quotes');
        expect(n.label, 'Teklifler');
        expect(n.route, '/orders/4002');
        expect(n.isRead, isFalse);
        expect(n.createdAt, DateTime.utc(2026, 10, 21, 7, 10));
        expect(page.items.last.isRead, isTrue);
        final u = UnreadCount.fromJson(_sample('unread_count'));
        expect(u.notifications, 3);
        expect(u.approvals, 2);
      },
    );

    test('her örneğin bir okuyucusu var', () {
      final files = Directory('test/contract/samples')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
          .toSet();
      expect(files, _parsers.keys.toSet());
      for (final name in files) {
        _parsers[name]!(_sample(name));
      }
    });
  });

  group('Sunucu örnekleri (B-INT, test/contract/server/index.json)', () {
    final dir = Directory(_serverDir);
    final index = _ServerIndex.read(dir);

    test('index.json: sözleşme sürümü ve dosya listesi', () {
      expect(index.contractVersion, AppConfig.expectedContract);
      expect(index.files, isNotEmpty);
      expect(
        _jsonFilesIn(dir).difference(_statsSamples.keys.toSet()),
        index.files.toSet(),
        reason: 'index.json ile klasördeki dosyalar aynı olmalı',
      );
      final unread = index.files.toSet().difference(
        _serverParsers.keys.toSet(),
      );
      expect(unread, isEmpty, reason: 'Okuyucusu olmayan sunucu örneği');
      expect(
        _serverChecks.keys.toSet(),
        _serverParsers.keys.toSet(),
        reason: 'Her okuyucunun değer denetimi olmalı',
      );
    });

    for (final e in index.entries) {
      test(
        '${e.file} (${e.dto})',
        () {
          final parsed = _serverParsers[e.file]!(e.read(dir), e.endpoint);
          _serverChecks[e.file]!(parsed);
        },
        skip: _serverParsers.containsKey(e.file) ? false : 'okuyucu yok',
      );
    }

    test('429: Retry-After başlığı gövdeden önce gelir', () {
      final body = _ServerIndex.entry(
        index,
        'problem.rate-limited.json',
      ).read(dir);
      final f = AppFailure.fromResponse(429, body, retryAfterHeader: '7');
      expect(f.retryAfter, const Duration(seconds: 7));
    });
  });

  group('İstatistik örnekleri (MobileStatsTests, stats-*.json)', () {
    Object? read(String file) =>
        jsonDecode(File('$_serverDir/$file').readAsStringSync());

    test('iki örnek de kopyada var ve okunur', () {
      for (final file in _statsSamples.keys) {
        expect(
          File('$_serverDir/$file').existsSync(),
          isTrue,
          reason: 'Eksik örnek: $file (tool/sync_contract_samples.sh)',
        );
        _checkStatsShape(file, _statsSamples[file]!(read(file)));
      }
    });

    test('GET stats/bayi (BayiStatsDto) değerleri', () {
      final b = BayiStats.fromJson(read('stats-bayi.json'));
      expect(b.stationId, 1);
      expect(b.stationTitle, 'Merkez Petrol');
      expect(b.isOwn, isFalse);
      expect(b.generatedAt, DateTime.utc(2026, 10, 20, 11));
      expect(b.period.title, 'Bu ay');
      expect(b.period.from, TrTime.fromWall(2026, 10));
      expect(b.period.to, TrTime.fromWall(2026, 10, 20));
      expect(b.period.compareLabel, 'Geçen ayın aynı dönemi');
      expect(b.period.compareTo, TrTime.fromWall(2026, 9, 20));
      final s = b.sales!;
      expect(s.orders, 5);
      expect(s.liters, 21000);
      expect(s.amount, 872000);
      expect(s.prevAmount, 234000);
      expect(s.unitPrice, 41.52);
      expect(s.prevUnitPrice, 39);
      expect(s.activeCustomers, 4);
      expect(s.newCustomers, 1);
      expect(b.months.map((m) => m.month), [5, 6, 7, 8, 9, 10]);
      expect(b.months.last.shortLabel, 'Eki');
      expect(b.months.last.amount, 872000);
      expect(b.months[3].shortLabel, 'Ağu');
      expect(b.products.map((p) => p.name), ['Motorin', 'Benzin']);
      expect(b.products.first.share, closeTo(0.7454, 1e-9));
      expect(b.topCustomers.first.title, 'Acar Nakliyat');
      expect(b.topCustomers.map((c) => c.customerId), [1, 2, 3, 5]);
      final f = b.funnel!;
      expect([f.requests, f.quoted, f.accepted], [11, 8, 5]);
      expect(f.conversion, closeTo(0.4545, 1e-9));
      expect(f.avgFirstQuoteMinutes, 26);
      final d = b.deliveries!;
      expect(d.delivered, 4);
      expect(d.deliveredLiters, 19850);
      expect(d.onTimeRate, 0.75);
      expect(d.disputes, 1);
      final c = b.collections!;
      expect(c.overdueAmount, 400000);
      expect(c.dueSoonCount, 2);
      expect(c.dueSoonDays, 7);
      expect(b.team.map((t) => t.userId), ['rep', 'rep2']);
      expect(b.team.first.name, 'Rıza Saha');
      expect(b.team.first.conversion, 0.5);
      expect(b.risk!.nearLimitCount, 1);
      expect(b.risk!.nearLimit.single.usageRate, closeTo(5.602, 1e-9));
    });

    test('GET stats/customer (CustomerStatsDto) değerleri', () {
      final c = CustomerStats.fromJson(read('stats-customer.json'));
      expect(c.customerId, 1);
      expect(c.customerTitle, 'Acar Nakliyat');
      expect(c.generatedAt, DateTime.utc(2026, 10, 20, 11));
      expect(c.period.key, StatsPeriod.month);
      expect(c.period.compareFrom, TrTime.fromWall(2026, 9));
      final s = c.spending!;
      expect(s.orders, 3);
      expect(s.liters, 16000);
      expect(s.amount, 655000);
      expect(s.unitPrice, 40.94);
      expect(s.activeCustomers, isNull);
      expect(c.months.map((m) => m.amount), [0, 0, 0, 42000, 234000, 655000]);
      expect(c.products.map((p) => p.name), ['Motorin', 'Benzin']);
      expect(c.stations.map((x) => x.title), ['Merkez Petrol', 'Kuzey Petrol']);
      expect(c.stations.first.share, closeTo(0.8122, 1e-9));
      expect(c.deliveryPoints.first.name, 'Tuzla Depo');
      expect(c.deliveryPoints.first.city, 'İstanbul');
      final o = c.orders!;
      expect(o.awaitingQuote, 2);
      expect(o.awaitingDecision, 1);
      expect(o.awaitingCompanyApproval, 1);
      expect(o.inTransit, 1);
      expect(o.open, 5);
      expect(o.disputed, 1);
      final liters = c.limits.first;
      expect(liters.stationTitle, 'Kuzey Petrol');
      expect(liters.isLiters, isTrue);
      expect(liters.limit, 20000);
      expect(liters.used, 5000);
      expect(liters.available, 15000);
      expect(liters.usageRate, 0.25);
      final money = c.limits.last;
      expect(money.isLiters, isFalse);
      expect(money.isUnlimited, isFalse);
      expect(money.available, 0);
      expect(money.usageRate, closeTo(5.602, 1e-9));
    });
  });

  group('Arka ucun çıktı klasörü (varsa)', () {
    final dir = Directory(
      _externalDir.isEmpty ? _defaultExternal : _externalDir,
    );
    final available = File('${dir.path}/index.json').existsSync();
    test(
      'her örnek okunur (kopya eskidiyse: tool/sync_contract_samples.sh)',
      () {
        final index = _ServerIndex.read(dir);
        expect(index.contractVersion, AppConfig.expectedContract);
        for (final e in index.entries) {
          final parse = _serverParsers[e.file];
          expect(parse, isNotNull, reason: 'Okuyucu yok: ${e.file}');
          expect(() => parse!(e.read(dir), e.endpoint), returnsNormally);
        }
      },
      skip: available ? false : 'klasör yok (${dir.path})',
    );

    test(
      'istatistik örnekleri (stats-bayi.json, stats-customer.json) okunur',
      () {
        var read = 0;
        for (final file in _statsSamples.keys) {
          final f = File('${dir.path}/$file');
          if (!f.existsSync()) continue;
          final parsed = _statsSamples[file]!(jsonDecode(f.readAsStringSync()));
          _checkStatsShape(file, parsed);
          read++;
        }
        expect(read, greaterThan(0), reason: 'Klasörde istatistik örneği yok');
      },
      skip:
          available &&
              _statsSamples.keys.any((f) => File('${dir.path}/$f').existsSync())
          ? false
          : 'istatistik örneği yok (${dir.path})',
    );
  });

  group('Enum kodları sunucuyla aynı (Core/Enums)', () {
    // Sunucudaki değerlerin anlık görüntüsü (2026-10-21).
    final server = <String, Map<String, int>>{
      'AttachmentKind': {
        'chequeImage': 1, 'promissoryNoteImage': 2, 'transferReceipt': 3, //
        'posSlip': 4, 'letterOfGuarantee': 5, 'dbsContract': 6, 'taxPlate': 10,
        'signatureCircular': 11, 'tradeRegistryGazette': 12,
        'activityCertificate': 13, 'visitPhoto': 14, 'riskReportPdf': 20,
        'financeNote': 21, 'deliveryPhoto': 30, 'deliverySignature': 31,
        'disputePhoto': 32, 'other': 99,
      },
      'ApprovalStatus': {
        'pending': 0, 'approved': 1, 'rejected': 2, 'cancelled': 3, //
        'infoRequested': 4,
      },
      'ApprovalDecision': {
        'approve': 1,
        'conditionalApprove': 2,
        'requestInfo': 3,
        'reject': 4,
      },
      'ShipmentStatus': {
        'planned': 0, 'inTransit': 1, 'reported': 2, 'accepted': 3, //
        'disputed': 4, 'cancelled': 5,
      },
      'FinanceProfileStatus': {
        'pending': 0, 'approved': 1, 'conditional': 2, 'infoRequested': 3, //
        'rejected': 4, 'suspended': 5,
      },
      'CustomerUserRole': {'requester': 1, 'approver': 2, 'admin': 3},
    };

    Map<String, int> app(List<CodedEnum> values) => {
      for (final v in values)
        if (!v.isUnknown) (v as Enum).name: v.code,
    };

    final appEnums = <String, Map<String, int>>{
      'AttachmentKind': app(AttachmentKind.values),
      'ApprovalStatus': app(ApprovalStatus.values),
      'ApprovalDecision': app(ApprovalDecision.values),
      'ShipmentStatus': app(ShipmentStatus.values),
      'FinanceProfileStatus': app(FinanceProfileStatus.values),
      'CustomerUserRole': app(CustomerUserRole.values),
    };

    server.forEach((name, values) {
      test(name, () {
        final mine = appEnums[name]!;
        values.forEach((member, code) {
          expect(mine[member], code, reason: '$name.$member');
        });
      });
    });

    test('ApprovalType ve OrderStatus kodları', () {
      expect(ApprovalType.fieldOrderProfit.code, 1);
      expect(ApprovalType.companyOrderRequest.code, 3);
      expect(ApprovalType.orderFinance.code, 4);
      expect(ApprovalType.leadFinance.code, 7);
      expect(OrderStatus.awaitingQuote.code, 1);
      expect(OrderStatus.awaitingApproval.code, 2);
      expect(OrderStatus.completed.code, 7);
      expect(AttachmentOwnerType.shipment.code, 10);
      expect(AttachmentOwnerType.approvalRequest.code, 7);
      expect(JsonReader.of(const {'a': 1}).integer('a'), 1);
    });
  });
}
