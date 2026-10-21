import '../../../core/models/enums.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/turkish_text.dart';
import '../data/documents.dart';
import '../data/window_time.dart';
import 'doc_spec.dart';

/// Belge metin biçimleri (sunucu `DocumentText`, tr-TR): `12.500 L`, `1.234,56 TL`, `42,1255 TL/L`.
abstract final class DocText {
  static String liters(num? v) =>
      v == null ? Fmt.dash : Fmt.number(v, maxFraction: 3);
  static String signedLiters(num v) => '${v > 0 ? '+' : ''}${liters(v)}';
  static String money(num? v) =>
      v == null ? Fmt.dash : Fmt.number(v, minFraction: 2, maxFraction: 2);
  static String unitPrice(num v) =>
      Fmt.number(v, minFraction: 2, maxFraction: 4);
  static String signedUnitPrice(num v) => '${v > 0 ? '+' : ''}${unitPrice(v)}';
  static String date(DateTime? v) => Fmt.date(v);
  static String dateTime(DateTime? v) => Fmt.dateTime(v);
  static String upper(String? v) => TurkishText.upper((v ?? '').trim());
  static String orDash(String? v) => Fmt.orDash(v);
  static String plate(String? v) =>
      v == null || v.trim().isEmpty ? '' : Fmt.plate(v);

  /// Sunucu `DocumentText.ShipmentStatusLabel`.
  static String shipmentStatus(ShipmentStatus s) => switch (s) {
    ShipmentStatus.planned => 'Planlandı',
    ShipmentStatus.inTransit => 'Yolda',
    ShipmentStatus.reported => 'Kabul bekliyor',
    ShipmentStatus.accepted => 'Teslim alındı',
    ShipmentStatus.disputed => 'İtirazlı',
    ShipmentStatus.cancelled => 'İptal',
    ShipmentStatus.unknown => Fmt.dash,
  };

  static String orderStatus(OrderStatus s) => s.label;

  /// Belge metinleri (sunucu `DocumentOptions`; "irsaliye" kelimesi yalnızca alt bilgide geçer).
  static const priceNote = 'Fiyatlara KDV dahildir.';
  static const quoteNote = 'Bu teklif fatura değildir, mali değeri yoktur.';
  static const waybillDisclaimer =
      'Bu sevk belgesi bilgi amaçlıdır; resmî taşıma ve ADR evrakı yerine geçmez. Fiyat bilgisi içermez.';
  static const receiptNote =
      'Taraflar yukarıdaki miktarın eksiksiz teslim edildiğini / teslim alındığını kabul eder. Farklılık varsa açıklama alanına yazılır.';
  static const reconciliationNote =
      'Tutar yalnızca alıcının kabul ettiği teslimatlar için hesaplanır; süreçteki ve itirazlı sevkiyatlar tutara dahil değildir. Bu mutabakat fatura değildir.';

  /// Şoförün teslim referansı (web "İrsaliye no"; uygulama belgelerinde "irsaliye" etiketi kullanılmaz).
  static const deliveryRefLabel = 'Teslim belge no';
}

/// Belge oluşturma bağlamı.
class DocContext {
  const DocContext({required this.portalBaseUrl});

  /// Web portalı kökü (sonu `/`): QR "Aç" bağlantısı.
  final String portalBaseUrl;

  String orderOpenUrl(int orderId) => '${portalBaseUrl}Documents/Open/$orderId';
  String shipmentOpenUrl(int shipmentId) =>
      '${portalBaseUrl}Documents/OpenShipment/$shipmentId';
}

/// Web `Views/Documents/{Order, Quote, Reconciliation, Receipt, Waybill}.cshtml` portları.
/// Aynı kodlar, bölümler ve imza kutuları; fiyatlar web gibi "TL" ile basılır.
abstract final class DocBuilders {
  // ------------------------------------------------------------------ Ortak parçalar

  static DocPartyCard party(DocParty p, String heading, {bool brand = false}) {
    final tax = joinNonEmpty(' · ', [p.taxNumber, p.taxOffice]);
    final contact = joinNonEmpty(' · ', [p.phone, p.email]);
    final address = joinNonEmpty(' · ', [p.address, p.cityDistrict]);
    final showSub =
        p.legalTitle != null &&
        TurkishText.lower(p.legalTitle!) != TurkishText.lower(p.title);
    return DocPartyCard(
      heading: heading,
      brand: brand,
      code: p.code,
      title: DocText.orDash(p.displayTitle),
      subtitle: showSub ? p.title : null,
      rows: [
        if (tax.isNotEmpty) DocKv('VKN / VD', tax),
        if (p.epdkLicenseNo != null) DocKv('EPDK lisans', p.epdkLicenseNo!),
        if (p.erpCode != null) DocKv('ERP kodu', p.erpCode!),
        if (p.contactName != null) DocKv('Yetkili', p.contactName!),
        if (contact.isNotEmpty) DocKv('İletişim', contact),
        if (address.isNotEmpty) DocKv('Adres', address),
        if (p.note != null) DocKv('Not', p.note!),
      ],
    );
  }

  static String _issuerLine(OrderDocument o) =>
      joinNonEmpty(' · ', [o.station.cityDistrict, o.station.phone]);

  static String _issuerLineEpdk(OrderDocument o) => joinNonEmpty(' · ', [
    o.station.epdkLicenseNo == null ? null : 'EPDK ${o.station.epdkLicenseNo}',
    o.station.phone,
  ]);

  static String? _brand(OrderDocument o) =>
      o.distributorBrand.trim().isEmpty ? null : o.distributorBrand.trim();

  /// `DocumentStamps.ForOrder`.
  static DocStamp orderStamp(OrderDocument o) {
    DocTimelineItem? completed;
    for (final t in o.timeline) {
      if (t.toStatus == OrderStatus.completed) completed = t;
    }
    return switch (o.status) {
      OrderStatus.completed => DocStamp(
        'TAMAMLANDI',
        sub: DocText.date(completed?.changedAt),
        tone: DocTone.ok,
      ),
      OrderStatus.approved => DocStamp(
        'ONAYLANDI',
        sub: DocText.date(o.approvedEvent?.changedAt),
        tone: DocTone.ok,
      ),
      OrderStatus.rejected => const DocStamp(
        'GEÇERSİZ',
        sub: 'Reddedildi',
        tone: DocTone.danger,
      ),
      OrderStatus.expired => const DocStamp(
        'GEÇERSİZ',
        sub: 'Süresi doldu',
        tone: DocTone.danger,
      ),
      OrderStatus.awaitingApproval => const DocStamp(
        'ONAY BEKLİYOR',
        sub: 'Müşteri onayı',
        tone: DocTone.warn,
      ),
      OrderStatus.revisionRequested => const DocStamp(
        'ONAY BEKLİYOR',
        sub: 'Revize istendi',
        tone: DocTone.warn,
      ),
      _ => const DocStamp(
        'ONAY BEKLİYOR',
        sub: 'Teklif bekleniyor',
        tone: DocTone.warn,
      ),
    };
  }

  /// `DocumentStamps.ForQuote`.
  static DocStamp quoteStamp(OrderDocument o, DocQuote q) {
    if (o.isVoid) {
      return DocStamp('GEÇERSİZ', sub: o.displayStatus, tone: DocTone.danger);
    }
    final latest = o.quotes.isEmpty ? null : o.quotes.last;
    if (o.isApproved) {
      return o.selectedQuote?.id == q.id
          ? DocStamp(
              'ONAYLANDI',
              sub: DocText.date(o.approvedEvent?.changedAt),
              tone: DocTone.ok,
            )
          : const DocStamp(
              'GEÇERSİZ',
              sub: 'Sonraki sürüm onaylandı',
              tone: DocTone.danger,
            );
    }
    if (latest != null && latest.id != q.id) {
      return const DocStamp(
        'GEÇERSİZ',
        sub: 'Yeni sürüm verildi',
        tone: DocTone.danger,
      );
    }
    return const DocStamp(
      'ONAY BEKLİYOR',
      sub: 'Müşteri onayı',
      tone: DocTone.warn,
    );
  }

  /// `DocumentStamps.ForShipment`.
  static DocStamp? shipmentStamp(DocShipment s) => switch (s.status) {
    ShipmentStatus.accepted => DocStamp(
      'TESLİM ALINDI',
      sub: DocText.date(s.acceptedAt ?? s.deliveredAt),
      tone: DocTone.ok,
    ),
    ShipmentStatus.disputed => const DocStamp(
      'İTİRAZLI',
      sub: 'Müşteri itirazı',
      tone: DocTone.danger,
    ),
    ShipmentStatus.cancelled => const DocStamp('İPTAL', tone: DocTone.danger),
    ShipmentStatus.reported => const DocStamp(
      'ONAY BEKLİYOR',
      sub: 'Teslim bildirildi',
      tone: DocTone.warn,
    ),
    ShipmentStatus.inTransit => DocStamp(
      'YOLDA',
      sub: DocText.date(s.scheduledAt),
    ),
    _ => null,
  };

  static DocTone shipTone(ShipmentStatus s) => switch (s) {
    ShipmentStatus.accepted => DocTone.ok,
    ShipmentStatus.disputed => DocTone.danger,
    ShipmentStatus.reported => DocTone.warn,
    ShipmentStatus.inTransit => DocTone.brand,
    _ => DocTone.neutral,
  };

  static String _seq(DocShipment s) =>
      s.seq > 0 ? '${s.seq}/${s.seqCount}' : '';

  // ------------------------------------------------------------------ Sipariş formu

  /// `Order.cshtml`.
  static DocSpec order(OrderDocument o, DocContext ctx) {
    final q = o.pricesLoaded ? o.selectedQuote : null;
    final ships = o.activeShipments;
    final cancelled = o.shipments.length - ships.length;
    const timelineMax = 8;
    final timeline = o.timeline.length > timelineMax
        ? o.timeline.sublist(o.timeline.length - timelineMax)
        : o.timeline;
    final qty = o.quantityLiters <= 0 ? 1.0 : o.quantityLiters;
    final acceptedPct = (o.acceptedLiters / qty).clamp(0.0, 1.0);
    final processPct = (o.inProcessLiters / qty).clamp(0.0, 1.0 - acceptedPct);

    DocKv fourth;
    if (o.isApproved) {
      fourth = DocKv(
        'Onay',
        o.approvedEvent == null
            ? Fmt.dash
            : DocText.dateTime(o.approvedEvent!.changedAt),
      );
    } else if (o.expiryEnabled && !o.isVoid) {
      fourth = DocKv('Son geçerlilik', DocText.dateTime(o.expiresAt));
    } else {
      fourth = DocKv('Sevkiyat', '${ships.length} adet');
    }

    return DocSpec(
      kind: DocKind.order,
      code: o.orderNumber,
      kicker: 'Sipariş belgesi',
      title: 'Sipariş formu',
      subtitle: '${o.productName} · ${DocText.liters(o.quantityLiters)} L',
      numberLabel: 'Sipariş no',
      number: o.orderNumber,
      barcode: o.orderNumber,
      qrUrl: ctx.orderOpenUrl(o.id),
      qrCaption: 'Siparişi aç',
      issuerTitle: o.station.displayTitle,
      issuerLine: _issuerLine(o),
      brand: _brand(o),
      stamp: orderStamp(o),
      watermark: o.isVoid
          ? 'GEÇERSİZ'
          : (!o.isApproved ? 'ONAYLANMAMIŞ' : null),
      printedAt: o.printedAt,
      printedBy: o.printedBy,
      blocks: [
        DocMetaBlock([
          DocKv('Durum', o.displayStatus),
          DocKv('Sipariş tarihi', DocText.dateTime(o.createdAt)),
          DocKv(
            'İstenen teslim',
            DocText.date(o.requestedDeliveryDate),
            accent: true,
          ),
          fourth,
        ]),
        DocPartiesBlock(
          party(o.station, 'Gönderen bayi', brand: true),
          party(o.customer, 'Alıcı cari'),
        ),
        DocAddressBlock(
          heading: 'Teslimat noktası',
          small: 'Sipariş anındaki adres',
          name: DocText.orDash(o.deliveryPointName),
          address: DocText.orDash(o.deliveryAddress),
          city: DocText.upper(o.deliveryPointCity),
          district: DocText.orDash(o.deliveryPointDistrict),
        ),
        DocTableBlock(
          headers: [
            'Ürün',
            'Kod',
            'Miktar',
            if (q != null) ...['Birim fiyat (teklif v${q.version})', 'Tutar'],
          ],
          numeric: q == null ? const {2} : const {2, 3, 4},
          rows: [
            [
              o.productName,
              o.productCode,
              '${DocText.liters(o.quantityLiters)} L',
              if (q != null) ...[
                '${DocText.unitPrice(q.unitPriceTry)} TL/L',
                '${DocText.money(q.totalAmountTry)} TL',
              ],
            ],
          ],
        ),
        if (q != null)
          DocTotalBlock(
            label: 'Sipariş tutarı',
            hint:
                '${DocText.liters(o.quantityLiters)} L × ${DocText.unitPrice(q.unitPriceTry)} TL/L · ${DocText.priceNote}',
            value: '${DocText.money(q.totalAmountTry)} TL',
          ),
        DocKvBlock(
          heading: 'Ödeme şekli',
          small: o.hasPayment && o.paymentStatusText != null
              ? 'Ödeme durumu: ${o.paymentStatusText}'
              : null,
          rows: [
            DocKv('Ödeme', o.paymentLine),
            if (o.hasPayment && o.paymentDueDate != null)
              DocKv('Ödeme tarihi', DocText.date(o.paymentDueDate)),
            for (final d in o.paymentDetails) DocKv(d.label, d.value),
          ],
        ),
        if (o.isApproved || ships.isNotEmpty) ...[
          DocKpisBlock(
            heading: 'Sevkiyat özeti',
            small:
                '${ships.length} sevkiyat${cancelled > 0 ? ' · $cancelled iptal' : ''}',
            [
              DocKpi('Sipariş', DocText.liters(o.quantityLiters), unit: 'L'),
              DocKpi(
                'Teslim alınan',
                DocText.liters(o.acceptedLiters),
                unit: 'L',
                tone: DocTone.ok,
              ),
              DocKpi(
                'Süreçte',
                DocText.liters(o.inProcessLiters),
                unit: 'L',
                tone: DocTone.warn,
              ),
              DocKpi(
                'Planlanmamış',
                DocText.liters(o.unplannedLiters),
                unit: 'L',
                tone: DocTone.brand,
              ),
            ],
            progress: (accepted: acceptedPct, inProcess: processPct),
          ),
          if (ships.isNotEmpty)
            DocTableBlock(
              headers: const [
                'Sevk kodu',
                'Plan',
                'Plaka',
                'Şoför',
                'Plan L',
                'Teslim L',
                'Durum',
              ],
              numeric: const {4, 5},
              rows: [
                for (final s in ships)
                  [
                    s.code,
                    DocText.date(s.scheduledAt),
                    DocText.orDash(DocText.plate(s.vehiclePlate)),
                    DocText.orDash(s.driverName),
                    DocText.liters(s.plannedLiters),
                    DocText.liters(s.deliveredLiters),
                    DocText.shipmentStatus(s.status),
                  ],
              ],
            ),
        ],
        if (timeline.isNotEmpty)
          DocTimelineBlock(
            heading: 'Durum geçmişi',
            small: '${o.timeline.length} kayıt',
            items: [
              for (final t in timeline)
                DocTimelineEntry(
                  time: DocText.dateTime(t.changedAt),
                  what: t.fromStatus != t.toStatus
                      ? '${DocText.orderStatus(t.toStatus)} (önceki: ${DocText.orderStatus(t.fromStatus)})'
                      : DocText.orderStatus(t.toStatus),
                  note: t.note,
                  who: t.changedByDisplay.trim().isEmpty
                      ? null
                      : t.changedByDisplay,
                ),
            ],
            more: o.timeline.length > timeline.length
                ? 'İlk ${o.timeline.length - timeline.length} kayıt gösterilmedi.'
                : null,
          ),
      ],
    );
  }

  // ------------------------------------------------------------------ Fiyat teklifi

  /// Teklif sürümü: verilen sürüm, yoksa seçili, yoksa son (web `ResolveQuote`).
  static DocQuote? resolveQuote(OrderDocument o, int? version) {
    if (o.quotes.isEmpty) return null;
    if (version != null) {
      for (final q in o.quotes) {
        if (q.version == version) return q;
      }
      return null;
    }
    return o.selectedQuote ?? o.quotes.last;
  }

  /// `Quote.cshtml` (sürüm başına bir belge). Teklif yoksa null.
  static DocSpec? quote(OrderDocument o, DocContext ctx, {int? version}) {
    final q = resolveQuote(o, version);
    if (q == null) return null;
    final code = DocCodes.quote(o.orderNumber, q.version);
    final stamp = quoteStamp(o, q);
    final approvedQuote = o.isApproved && o.selectedQuote?.id == q.id;
    final delivery = q.deliveryDate ?? o.requestedDeliveryDate;
    final showValidity = o.expiryEnabled && o.isBeforeApproval;
    final place = joinNonEmpty(' / ', [
      o.deliveryPointDistrict,
      DocText.upper(o.deliveryPointCity),
    ]);
    return DocSpec(
      kind: DocKind.quote,
      code: code,
      kicker: 'Teklif · sürüm ${q.version} / ${o.quotes.length}',
      title: 'Fiyat teklifi',
      subtitle: '${o.productName} · ${DocText.liters(o.quantityLiters)} L',
      numberLabel: 'Teklif no',
      number: code,
      barcode: code,
      qrUrl: ctx.orderOpenUrl(o.id),
      qrCaption: 'Siparişi aç',
      issuerTitle: o.station.displayTitle,
      issuerLine: _issuerLineEpdk(o),
      brand: _brand(o),
      stamp: stamp,
      watermark: stamp.tone == DocTone.danger ? 'GEÇERSİZ' : null,
      printedAt: o.printedAt,
      printedBy: o.printedBy,
      blocks: [
        DocMetaBlock([
          DocKv('Teklif tarihi', DocText.dateTime(q.createdAt)),
          DocKv(
            'Geçerlilik',
            showValidity
                ? DocText.dateTime(o.expiresAt)
                : (approvedQuote ? 'Onaylandı' : Fmt.dash),
          ),
          DocKv('Teslim tarihi', DocText.date(delivery), accent: true),
          DocKv('Teslim yeri', DocText.orDash(place)),
        ]),
        DocPartiesBlock(
          party(o.station, 'Teklif veren bayi', brand: true),
          party(o.customer, 'Sayın (alıcı cari)'),
        ),
        DocTableBlock(
          heading: 'Teklif kalemi',
          small: 'Sipariş ${o.orderNumber}',
          headers: const [
            'Ürün',
            'Teslim yeri',
            'Miktar',
            'Birim fiyat',
            'Tutar',
          ],
          numeric: const {2, 3, 4},
          rows: [
            [
              joinNonEmpty('\n', [o.productName, o.productCode]),
              joinNonEmpty('\n', [
                DocText.orDash(o.deliveryPointName),
                DocText.orDash(o.deliveryAddress),
              ]),
              '${DocText.liters(o.quantityLiters)} L',
              '${DocText.unitPrice(q.unitPriceTry)} TL/L',
              '${DocText.money(q.totalAmountTry)} TL',
            ],
          ],
        ),
        DocTotalBlock(
          label: 'Teklif tutarı',
          hint: DocText.priceNote,
          value: '${DocText.money(q.totalAmountTry)} TL',
        ),
        DocCalloutBlock(
          tone: DocTone.info,
          title: 'Ödeme şekli:',
          text: o.paymentLine,
        ),
        if (approvedQuote)
          DocCalloutBlock(
            tone: DocTone.ok,
            title: 'Onaylandı:',
            text: o.approvedEvent == null
                ? Fmt.dash
                : '${DocText.dateTime(o.approvedEvent!.changedAt)} · ${o.approvedEvent!.changedByDisplay}',
          ),
        if (q.revisionNote != null)
          DocCalloutBlock(
            tone: DocTone.warn,
            title: 'Revizyon notu:',
            text: q.revisionNote,
          ),
        if (o.quotes.length > 1)
          DocTableBlock(
            heading: 'Sürüm geçmişi',
            small: '${o.quotes.length} sürüm',
            headers: const [
              'Sürüm',
              'Tarih',
              'Teslim',
              'Birim fiyat',
              'Fark',
              'Tutar',
            ],
            numeric: const {3, 4, 5},
            highlightRow: o.quotes.indexWhere((v) => v.id == q.id),
            rows: [
              for (final v in o.quotes)
                [
                  'v${v.version}${o.selectedQuote?.id == v.id && o.isApproved ? ' · Onaylı' : ''}',
                  DocText.dateTime(v.createdAt),
                  DocText.date(v.deliveryDate),
                  DocText.unitPrice(v.unitPriceTry),
                  v.unitPriceDelta != null && v.unitPriceDelta != 0
                      ? DocText.signedUnitPrice(v.unitPriceDelta!)
                      : Fmt.dash,
                  DocText.money(v.totalAmountTry),
                ],
            ],
          ),
        const DocNotesBlock([
          '${DocText.quoteNote} ${DocText.priceNote}',
          'Teklif; belirtilen ürün, miktar, teslim tarihi ve teslim yeri için geçerlidir. Onay ${DocSpec.platformName} üzerinden müşteri tarafından verilir.',
        ]),
        const DocSignaturesBlock([
          DocSignBox('Teklif veren', sub: 'Bayi kaşe / imza'),
          DocSignBox('Onaylayan', sub: 'Alıcı cari kaşe / imza'),
        ]),
      ],
    );
  }

  // ------------------------------------------------------------------ Teslimat mutabakatı

  /// `Reconciliation.cshtml`.
  static DocSpec reconciliation(OrderDocument o, DocContext ctx) {
    final active = o.activeShipments;
    final unit = o.pricesLoaded ? o.selectedQuote?.unitPriceTry : null;
    final planned = active.fold<double>(0, (s, x) => s + x.plannedLiters);
    final delivered = active.fold<double>(
      0,
      (s, x) => s + (x.deliveredLiters ?? 0),
    );
    final amount = unit == null ? null : o.acceptedAmountTry;
    return DocSpec(
      kind: DocKind.reconciliation,
      code: o.orderNumber,
      kicker: 'Mutabakat',
      title: 'Teslimat mutabakatı',
      subtitle: '${o.productName} · ${DocText.liters(o.quantityLiters)} L',
      numberLabel: 'Sipariş no',
      number: o.orderNumber,
      barcode: o.orderNumber,
      qrUrl: ctx.orderOpenUrl(o.id),
      qrCaption: 'Siparişi aç',
      issuerTitle: o.station.displayTitle,
      issuerLine: _issuerLine(o),
      brand: _brand(o),
      stamp: orderStamp(o),
      printedAt: o.printedAt,
      printedBy: o.printedBy,
      blocks: [
        DocKpisBlock([
          DocKpi('Sipariş', DocText.liters(o.quantityLiters), unit: 'L'),
          DocKpi(
            'Teslim alınan (kabul)',
            DocText.liters(o.acceptedLiters),
            unit: 'L',
            tone: DocTone.ok,
          ),
          DocKpi(
            'Süreçte',
            DocText.liters(o.inProcessLiters),
            unit: 'L',
            tone: DocTone.warn,
          ),
          DocKpi(
            'Kalan',
            DocText.liters(o.remainingLiters),
            unit: 'L',
            tone: DocTone.brand,
          ),
        ]),
        DocPartiesBlock(
          party(o.station, 'Bayi', brand: true),
          party(o.customer, 'Cari'),
        ),
        DocTableBlock(
          heading: 'Sevkiyatlar',
          small:
              '${active.length} sevkiyat · ${DocText.orDash(o.deliveryPointName)}',
          headers: [
            '#',
            'Sevk kodu',
            'Teslim',
            'Plaka',
            DocText.deliveryRefLabel,
            'Plan L',
            'Teslim L',
            if (unit != null) 'Tutar (TL)',
            'Durum',
          ],
          numeric: unit == null ? const {5, 6} : const {5, 6, 7},
          mutedRows: {
            for (var i = 0; i < active.length; i++)
              if (active[i].status != ShipmentStatus.accepted) i,
          },
          rows: [
            for (final s in active)
              [
                '${s.seq}',
                s.code,
                DocText.date(s.deliveredAt ?? s.scheduledAt),
                DocText.orDash(DocText.plate(s.vehiclePlate)),
                DocText.orDash(s.deliveryDocumentNo),
                DocText.liters(s.plannedLiters),
                DocText.liters(s.deliveredLiters),
                if (unit != null)
                  s.status == ShipmentStatus.accepted &&
                          s.deliveredLiters != null
                      ? DocText.money(
                          (s.deliveredLiters! * unit * 100).roundToDouble() /
                              100,
                        )
                      : Fmt.dash,
                DocText.shipmentStatus(s.status),
              ],
          ],
          footer: [
            'Toplam',
            '',
            '',
            '',
            '',
            DocText.liters(planned),
            DocText.liters(delivered),
            if (unit != null) DocText.money(amount),
            '',
          ],
        ),
        if (unit != null && amount != null)
          DocTotalBlock(
            label: 'Kabul edilen teslimat tutarı',
            hint:
                '${DocText.liters(o.acceptedLiters)} L × ${DocText.unitPrice(unit)} TL/L (teklif v${o.selectedQuote!.version}) · ${DocText.priceNote}',
            value: '${DocText.money(amount)} TL',
          ),
        const DocTextBlock(DocText.reconciliationNote, fine: true),
        DocSignaturesBlock([
          DocSignBox('Bayi', sub: o.station.displayTitle),
          DocSignBox('Cari', sub: o.customer.displayTitle),
        ]),
      ],
    );
  }

  // ------------------------------------------------------------------ Teslim tutanağı

  /// `Receipt.cshtml` (TT- kodu; barkod sevkiyat kodu). İptal edilmiş sevkiyatta üretilmez.
  static DocSpec receipt(ShipmentDocument d, DocContext ctx) {
    final s = d.shipment;
    final o = d.order;
    final plate = s.vehiclePlate.trim().isEmpty
        ? null
        : DocText.plate(s.vehiclePlate);
    final delivered = s.isDelivered;
    final diff = s.differenceLiters;
    final point = DocText.orDash(o.deliveryPointName);
    final statement = delivered
        ? '${DocText.dateTime(s.deliveredAt)} tarihinde ${plate ?? Fmt.dash} plakalı araç ile $point teslimat noktasına ${DocText.liters(s.deliveredLiters)} L ${o.productName} teslim edilmiştir.'
        : '…………… tarihinde saat ………’da ${plate ?? '……………'} plakalı araç ile $point teslimat noktasına …………… L ${o.productName} teslim edilmiştir.';
    return DocSpec(
      kind: DocKind.receipt,
      code: s.receiptCode,
      kicker: 'Teslim · kabul belgesi',
      title: 'Teslim tutanağı',
      subtitle: '${o.productName} · sipariş ${o.orderNumber}',
      numberLabel: 'Tutanak no',
      number: s.receiptCode,
      barcode: s.code,
      qrUrl: ctx.shipmentOpenUrl(s.id),
      qrCaption: 'Sevkiyatı aç',
      issuerTitle: o.station.displayTitle,
      issuerLine: _issuerLine(o),
      brand: _brand(o),
      seq: _seq(s).isEmpty ? null : 'Sevkiyat ${_seq(s)}',
      stamp: shipmentStamp(s),
      printedAt: o.printedAt,
      printedBy: o.printedBy,
      blocks: [
        DocTextBlock(statement, statement: true),
        DocKpisBlock([
          DocKpi('Planlanan', DocText.liters(s.plannedLiters), unit: 'L'),
          DocKpi(
            'Teslim edilen',
            delivered ? DocText.liters(s.deliveredLiters) : '……',
            unit: 'L',
            tone: delivered ? DocTone.ok : DocTone.neutral,
          ),
          DocKpi(
            'Fark',
            diff == null ? '……' : DocText.signedLiters(diff),
            unit: 'L',
            tone: diff != null && diff < 0 ? DocTone.danger : DocTone.neutral,
          ),
          DocKpi(
            DocText.deliveryRefLabel,
            DocText.orDash(s.deliveryDocumentNo),
          ),
        ]),
        DocPartiesBlock(
          party(o.station, 'Teslim eden (bayi)', brand: true),
          party(o.customer, 'Teslim alan (cari)'),
        ),
        DocTableBlock(
          heading: 'Sevkiyat',
          small: s.code,
          headers: const [
            'Teslimat noktası',
            'Plaka',
            'Sürücü',
            'Plan tarihi',
            'Plan',
            'Teslim',
          ],
          numeric: const {4, 5},
          rows: [
            [
              joinNonEmpty('\n', [
                point,
                DocText.orDash(
                  joinNonEmpty(' / ', [
                    o.deliveryPointDistrict,
                    o.deliveryPointCity,
                  ]),
                ),
              ]),
              DocText.orDash(plate),
              DocText.orDash(s.driverName),
              DocText.date(s.scheduledAt),
              '${DocText.liters(s.plannedLiters)} L',
              delivered ? '${DocText.liters(s.deliveredLiters)} L' : Fmt.dash,
            ],
          ],
        ),
        if (s.status == ShipmentStatus.accepted)
          DocCalloutBlock(
            tone: DocTone.ok,
            title: '${DocSpec.platformName} onayı:',
            text: s.acceptedByDisplay == null
                ? 'Alıcı teslimatı ${DocText.dateTime(s.acceptedAt)} tarihinde kabul etti.'
                : 'Alıcı teslimatı ${DocText.dateTime(s.acceptedAt)} tarihinde ${s.acceptedByDisplay} ile kabul etti.',
          )
        else if (s.status == ShipmentStatus.disputed)
          DocCalloutBlock(
            tone: DocTone.danger,
            title: 'İtirazlı teslimat.',
            text: DocText.orDash(s.disputeNote),
          )
        else if (s.status == ShipmentStatus.reported)
          const DocCalloutBlock(
            tone: DocTone.warn,
            title: 'Alıcı onayı bekleniyor.',
            text:
                'Teslim bildirildi; ${DocSpec.platformName} üzerinde kabul edildiğinde tutanak kesinleşir.',
          ),
        const DocFillBlock([
          DocFillCell('Teslim alınan miktar', unit: 'L'),
          DocFillCell('Sayaç ilk / son'),
          DocFillCell('Teslim saati'),
          DocFillCell('Mühür no'),
          DocFillCell('Açıklama / ihtirazi kayıt', full: true),
        ]),
        const DocTextBlock(DocText.receiptNote, fine: true),
        DocSignaturesBlock([
          DocSignBox(
            'Teslim eden',
            sub: 'Sürücü / bayi',
            name: s.driverName.trim().isEmpty ? null : s.driverName,
          ),
          const DocSignBox('Teslim alan', sub: 'Alıcı yetkilisi'),
        ]),
      ],
    );
  }

  // ------------------------------------------------------------------ Sevk belgesi

  /// `Waybill.cshtml` (bilgi amaçlı, fiyatsız; SVK- kodu).
  static DocSpec waybill(ShipmentDocument d, DocContext ctx) {
    final s = d.shipment;
    final o = d.order;
    final hasPlate = s.vehiclePlate.trim().isNotEmpty;
    final contact = joinNonEmpty(' · ', [
      o.deliveryPointContactName,
      o.deliveryPointContactPhone,
    ]);
    final window = o.deliveryWindowStart == null || o.deliveryWindowEnd == null
        ? null
        : '${o.deliveryWindowStart!.label}–${o.deliveryWindowEnd!.label}';
    final tank = o.deliveryPointTankLiters == null
        ? null
        : '${Fmt.number(o.deliveryPointTankLiters, maxFraction: o.deliveryPointTankLiters! % 1 == 0 ? 0 : 2)} L';
    final coords =
        o.deliveryPointLatitude == null || o.deliveryPointLongitude == null
        ? null
        : '${_coord(o.deliveryPointLatitude!)}, ${_coord(o.deliveryPointLongitude!)}';
    return DocSpec(
      kind: DocKind.waybill,
      code: s.code,
      kicker: 'Bilgi amaçlıdır · fiyat içermez',
      title: 'Sevk belgesi',
      subtitle: '${o.productName} · ${DocText.liters(s.plannedLiters)} L',
      numberLabel: 'Sevk no',
      number: s.code,
      barcode: s.code,
      qrUrl: ctx.shipmentOpenUrl(s.id),
      qrCaption: 'Sevkiyatı aç',
      issuerTitle: o.station.displayTitle,
      issuerLine: _issuerLineEpdk(o),
      brand: _brand(o),
      seq: _seq(s).isEmpty ? null : 'Sevkiyat ${_seq(s)}',
      stamp: shipmentStamp(s),
      watermark: s.isCancelled ? 'İPTAL' : null,
      printedAt: o.printedAt,
      printedBy: o.printedBy,
      blocks: [
        const DocCalloutBlock(
          tone: DocTone.warn,
          title: 'Sevk belgesi (bilgi amaçlıdır).',
          text: DocText.waybillDisclaimer,
        ),
        DocPartiesBlock(
          party(o.station, 'Gönderen (bayi)', brand: true),
          party(o.customer, 'Alıcı (cari)'),
        ),
        DocAddressBlock(
          heading: 'Teslimat noktası',
          name: DocText.orDash(o.deliveryPointName),
          address: DocText.orDash(o.deliveryAddress),
          city: DocText.upper(o.deliveryPointCity),
          district: DocText.orDash(o.deliveryPointDistrict),
          details: [
            if (contact.isNotEmpty) DocKv('Sorumlu', contact),
            if (window != null) DocKv('Kabul saati', window),
            if (tank != null) DocKv('Tank', tank),
            if (coords != null) DocKv('Konum', coords),
            if (o.deliveryPointAccessNotes != null)
              DocKv('Erişim notu', o.deliveryPointAccessNotes!),
          ],
        ),
        DocPlateBlock(
          heading: 'Araç ve sürücü',
          small: 'Boş kutular el ile doldurulur',
          plate: hasPlate ? DocText.plate(s.vehiclePlate) : null,
          fields: [
            DocKv('Sürücü', DocText.orDash(s.driverName)),
            DocKv('Plan tarihi', DocText.dateTime(s.scheduledAt)),
            DocKv('Sipariş no', o.orderNumber),
          ],
          fill: const [
            DocFillCell('Sürücü telefonu'),
            DocFillCell('Dorse plakası'),
            DocFillCell('Mühür no'),
            DocFillCell('Yola çıkış saati'),
            DocFillCell('Teslim yeri yetkilisi'),
          ],
        ),
        DocTableBlock(
          headers: const [
            'Yük (ürün)',
            'Kod',
            'Durum',
            'Planlanan',
            'Sipariş toplamı',
          ],
          numeric: const {3, 4},
          rows: [
            [
              o.productName,
              o.productCode,
              DocText.shipmentStatus(s.status),
              '${DocText.liters(s.plannedLiters)} L',
              '${DocText.liters(o.quantityLiters)} L',
            ],
          ],
        ),
        DocCalloutBlock(
          tone: DocTone.info,
          title: 'Ödeme şekli:',
          text: o.paymentLine,
        ),
        const DocFillBlock([
          DocFillCell('Sayaç ilk', unit: 'L'),
          DocFillCell('Sayaç son', unit: 'L'),
          DocFillCell('Sıcaklık', unit: '°C'),
          DocFillCell('Yoğunluk (15 °C)', unit: 'kg/m³'),
          DocFillCell('Varış saati'),
          DocFillCell('Boşaltma bitiş'),
          DocFillCell('Teslim edilen miktar', unit: 'L', wide: true),
          DocFillCell('Açıklama', full: true),
        ]),
        DocSignaturesBlock([
          const DocSignBox('Hazırlayan', sub: 'Bayi'),
          DocSignBox(
            'Sürücü',
            name: s.driverName.trim().isEmpty ? null : s.driverName,
          ),
          const DocSignBox('Teslim alan', sub: 'Alıcı yetkilisi'),
        ]),
      ],
    );
  }

  static String _coord(double v) {
    var s = v.toStringAsFixed(6);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}

/// Teslimat penceresi (belge kartı ve uygulama içinde aynı yazım).
String? docWindow(WindowTime? start, WindowTime? end) =>
    start == null || end == null ? null : '${start.label}–${end.label}';
