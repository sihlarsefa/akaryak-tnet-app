import 'dart:async';

import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/utils/turkish_text.dart';
import 'package:akaryakitnet/features/customer_more/application/documents_controller.dart';
import 'package:akaryakitnet/features/customer_more/data/customer_more_repository.dart';
import 'package:akaryakitnet/features/customer_more/data/documents.dart';
import 'package:akaryakitnet/features/customer_more/documents/doc_builders.dart';
import 'package:akaryakitnet/features/customer_more/documents/doc_renderer.dart';
import 'package:akaryakitnet/features/customer_more/documents/doc_spec.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'cm_test_utils.dart';

/// "irsaliye" yalnızca alt bilgideki yasal notta geçebilir (spec A.4 A3).
bool _mentionsIrsaliye(String s) =>
    TurkishText.searchKey(s).contains('irsaliye');

Future<Set<int>> _fontRunes(String asset) async {
  final data = await rootBundle.load(asset);
  final ttf = TtfParser(data);
  return ttf.charToGlyphIndexMap.keys.toSet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CmEnv env;
  late ProviderContainer c;

  setUp(() async {
    env = await CmEnv.create();
    c = env.container;
    addTearDown(env.dispose);
  });

  Future<List<DocSpec>> allSpecs() async {
    final repo = c.read(customerMoreRepositoryProvider);
    final page = DocumentArchivePage.fromJson(
      await repo.documentArchiveJson(const DocumentArchiveQuery(), take: 100),
    );
    expect(page.items, isNotEmpty);
    final service = c.read(documentPdfServiceProvider);
    final specs = <DocSpec>[];
    final seenOrders = <int>{};
    for (final row in page.items) {
      if (seenOrders.add(row.orderId)) {
        specs.add(
          await service.spec(OrderDocRequest(row.orderId, row.orderNumber)),
        );
        final doc = await repo.orderDocument(row.orderId);
        for (final q in doc.quotes) {
          specs.add(
            await service.spec(
              QuoteDocRequest(row.orderId, row.orderNumber, q.version),
            ),
          );
        }
        if (row.canReconcile) {
          specs.add(
            await service.spec(
              ReconciliationDocRequest(row.orderId, row.orderNumber),
            ),
          );
        }
      }
      if (row.canReceipt) {
        specs.add(await service.spec(ReceiptDocRequest(row.shipmentId!)));
      }
      if (row.canWaybill) {
        specs.add(await service.spec(WaybillDocRequest(row.shipmentId!)));
      }
    }
    return specs;
  }

  test(
    'her belge türü üretilir: kodlar, bölümler ve imza kutuları web ile aynı',
    () async {
      final specs = await allSpecs();
      final kinds = specs.map((s) => s.kind).toSet();
      expect(kinds, containsAll(DocKind.values));

      for (final s in specs) {
        switch (s.kind) {
          case DocKind.order:
            expect(s.title, 'Sipariş formu');
            expect(s.numberLabel, 'Sipariş no');
            expect(s.code, matches(RegExp(r'^SIP-\d{8}-\d{5}$')));
            expect(s.blocks.whereType<DocSignaturesBlock>(), isEmpty);
            expect(
              s.blocks.whereType<DocKvBlock>().single.heading,
              'Ödeme şekli',
            );
          case DocKind.quote:
            expect(s.title, 'Fiyat teklifi');
            expect(s.code, matches(RegExp(r'^SIP-\d{8}-\d{5}-T\d+$')));
            expect(
              s.blocks.whereType<DocSignaturesBlock>().single.boxes.map(
                (b) => b.title,
              ),
              ['Teklif veren', 'Onaylayan'],
            );
          case DocKind.reconciliation:
            expect(s.title, 'Teslimat mutabakatı');
            expect(
              s.blocks.whereType<DocSignaturesBlock>().single.boxes.map(
                (b) => b.title,
              ),
              ['Bayi', 'Cari'],
            );
          case DocKind.receipt:
            expect(s.title, 'Teslim tutanağı');
            expect(s.code, matches(RegExp(r'^TT-\d{8}$')));
            expect(s.barcode, matches(RegExp(r'^SVK-\d{8}$')));
            expect(
              s.blocks.whereType<DocSignaturesBlock>().single.boxes.map(
                (b) => b.title,
              ),
              ['Teslim eden', 'Teslim alan'],
            );
          case DocKind.waybill:
            expect(s.title, 'Sevk belgesi');
            expect(s.code, matches(RegExp(r'^SVK-\d{8}$')));
            expect(s.kicker, 'Bilgi amaçlıdır · fiyat içermez');
            expect(
              s.blocks.whereType<DocSignaturesBlock>().single.boxes.map(
                (b) => b.title,
              ),
              ['Hazırlayan', 'Sürücü', 'Teslim alan'],
            );
        }
        expect(s.fileName, endsWith('_${s.kind.fileSuffix}.pdf'));
      }
    },
  );

  test('"irsaliye" etiketi yok; alt bilgi mali belge notu', () async {
    final specs = await allSpecs();
    expect(
      DocSpec.legalFooter,
      'Mali belge değildir; e-irsaliye/e-fatura yerine geçmez.',
    );
    for (final s in specs) {
      final texts = docTexts(s, includeFooter: false);
      final offenders = texts.where(_mentionsIrsaliye).toList();
      expect(offenders, isEmpty, reason: '${s.kind}: $offenders');
    }
    // Teslim referansı "Teslim belge no" olarak basılır.
    final receipt = specs.firstWhere((s) => s.kind == DocKind.receipt);
    expect(docTexts(receipt), contains(DocText.deliveryRefLabel));
  });

  test('PDF çizilir; Türkçe karakterler gömülü yazı tipinde mevcut', () async {
    final specs = await allSpecs();
    final regular = await _fontRunes('assets/fonts/Roboto-Regular.ttf');
    final bold = await _fontRunes('assets/fonts/Roboto-Bold.ttf');
    for (final s in specs) {
      for (final text in docTexts(s)) {
        for (final r in text.runes) {
          if (r == 0x0A) continue;
          expect(
            regular.contains(r) && bold.contains(r),
            isTrue,
            reason:
                '${s.kind}: "${String.fromCharCode(r)}" (U+${r.toRadixString(16)}) in "$text"',
          );
        }
      }
    }
    expect(regular.containsAll('İıŞşĞğÜüÖöÇç₺'.runes), isTrue);

    final printed = <String>[];
    await runZoned(
      () async {
        for (final kind in DocKind.values) {
          final spec = specs.firstWhere((s) => s.kind == kind);
          final bytes = await DocRenderer.render(spec);
          expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
          expect(bytes.length, greaterThan(15000));
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );
    expect(
      printed.where((l) => l.contains('Unable to find a font')),
      isEmpty,
      reason: 'eksik glif',
    );
    expect(
      printed.where((l) => l.contains('has no Unicode support')),
      isEmpty,
      reason: 'gömülü olmayan Type1 yazı tipi (ör. barkod metni)',
    );
  });

  test('üretilen belge saklanır; çevrimdışı saklanan sürüm açılır', () async {
    final repo = c.read(customerMoreRepositoryProvider);
    final row = DocumentArchivePage.fromJson(
      await repo.documentArchiveJson(const DocumentArchiveQuery()),
    ).items.firstWhere((r) => r.canReceipt);
    final service = c.read(documentPdfServiceProvider);
    final req = ReceiptDocRequest(row.shipmentId!);
    final fresh = await service.generate(req);
    expect(fresh.fromCache, isFalse);
    expect(await service.cached(req), isNotNull);

    env.harness.server.failureMode = FakeFailureMode.offline;
    final offline = await service.generate(req);
    expect(offline.fromCache, isTrue);
    expect(offline.bytes, fresh.bytes);
    expect(offline.fileName, req.fileName);
  });

  test('teklif belgesi sürüm başına; geçersiz sürüm mühürlenir', () async {
    final repo = c.read(customerMoreRepositoryProvider);
    final world = env.world;
    // Bir siparişe ikinci teklif sürümü ekle (v1 geçersiz olur).
    final o = world.orders.firstWhere((x) => x['status'] == 2);
    final quotes = (o['quotes'] as List).cast<Map<String, dynamic>>();
    quotes.add({
      ...quotes.first,
      'id': 39999,
      'version': 2,
      'unitPriceTry': 42.05,
      'totalAmountTry': 336400.0,
      'revisionNote': 'Fiyat güncellendi.',
    });
    final doc = await repo.orderDocument(o['id'] as int);
    const ctx = DocContext(portalBaseUrl: 'https://portal.example/');
    final v1 = DocBuilders.quote(doc, ctx, version: 1)!;
    final v2 = DocBuilders.quote(doc, ctx, version: 2)!;
    expect(v1.code, endsWith('-T1'));
    expect(v1.stamp!.text, 'GEÇERSİZ');
    expect(v1.watermark, 'GEÇERSİZ');
    expect(v2.stamp!.text, 'ONAY BEKLİYOR');
    expect(
      v2.blocks.whereType<DocTableBlock>().any(
        (t) => t.heading == 'Sürüm geçmişi',
      ),
      isTrue,
    );
    expect(v2.qrUrl, 'https://portal.example/Documents/Open/${o['id']}');
    expect(DocBuilders.quote(doc, ctx, version: 9), isNull);
  });
}
