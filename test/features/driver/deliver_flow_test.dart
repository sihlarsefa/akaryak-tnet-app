import 'dart:convert';

import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/features/driver/application/deliver_flow.dart';
import 'package:akaryakitnet/features/driver/copy.dart';
import 'package:akaryakitnet/features/driver/data/deliver_draft.dart';
import 'package:akaryakitnet/features/driver/data/driver_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/driver_harness.dart';

DriverShipmentDetail _detail({
  int status = 1,
  bool photo = true,
  bool signature = true,
  bool gps = false,
  double planned = 8000,
  double? tank = 6000,
  double? delivered,
  List<Map<String, dynamic>> attachments = const [],
}) => DriverShipmentDetail.fromJson({
  'id': 5002,
  'code': 'SVK-00005002',
  'status': status,
  'plannedLiters': planned,
  'deliveredLiters': delivered,
  'tankCapacityLiters': tank,
  'deliveryDocumentNo': delivered == null ? null : 'IRS-1',
  'recipientName': delivered == null ? null : 'Volkan Ateş',
  'contactName': 'Murat Kaya',
  'attachments': attachments,
  'requirements': {'photo': photo, 'signature': signature, 'gps': gps},
  'actions': {'canDeliver': true},
});

void main() {
  group('LitersKeypad', () {
    String type(List<String> keys) {
      var s = '';
      for (final k in keys) {
        s = LitersKeypad.apply(s, k);
      }
      return s;
    }

    test('virgül, 3 ondalık, baştaki sıfır, sil', () {
      expect(type(['7', '9', '5', '0']), '7950');
      expect(type(['0', '7']), '7');
      expect(type([',']), '0,');
      expect(type(['1', ',', ',', '5']), '1,5');
      expect(type(['1', ',', '1', '2', '3', '4']), '1,123');
      expect(type(['1', '2', LitersKeypad.backspace]), '1');
      expect(type([LitersKeypad.backspace]), '');
      expect(type(List.filled(9, '9')), '9999999');
      expect(type(['x']), '');
    });

    test('görüntü: binlik nokta, ondalık yazıldığı gibi', () {
      expect(LitersKeypad.display(''), '0');
      expect(LitersKeypad.display('7950'), '7.950');
      expect(LitersKeypad.display('12500,5'), '12.500,5');
      expect(LitersKeypad.display('0,'), '0,');
      expect(LitersKeypad.parse('12500,75'), 12500.75);
      expect(LitersKeypad.parse(''), isNull);
    });
  });

  group('DeliverFlowModel', () {
    late DeliverDraftStore store;
    late TestFileStore files;
    late DriverHarness h;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      h = await DriverHarness.create(reusePrefs: prefs);
      files = TestFileStore(h.dir);
      store = DeliverDraftStore(PrefsStore(prefs), files);
    });

    tearDown(() => h.dispose());

    DeliverFlowModel model(DriverShipmentDetail d, {DeliverDraft? initial}) =>
        DeliverFlowModel(
          userId: 'u-sofor',
          detail: d,
          store: store,
          initial: initial,
          saveDelay: Duration.zero,
          correction: d.row.isDisputed,
        );

    test('litre: zorunlu, planlananı aşamaz; tank uyarısı engellemez', () {
      final m = model(_detail());
      expect(m.litersError, DriverCopy.litersRequired);
      for (final k in ['8', '0', '0', '1']) {
        m.key(k);
      }
      expect(m.litersError, DriverCopy.litersMax('8.000 L'));
      m.key(LitersKeypad.backspace);
      m.key('0');
      expect(m.liters, 8000);
      expect(m.litersError, isNull);
      expect(m.tankWarning, contains('6.000 L'));
      m.fillPlanned();
      expect(m.draft.litersText, '8000');
      expect(m.next(), isNull);
      expect(m.step, DeliverStep.document);
    });

    test('adım hatası ilerletmez; irsaliye zorunlu', () {
      final m = model(_detail());
      m.fillPlanned();
      m.next();
      expect(m.next(), DriverCopy.documentRequired);
      expect(m.step, DeliverStep.document);
      m.setDocument('IRS-778812');
      expect(m.next(), isNull);
      expect(m.step, DeliverStep.recipient);
      m.back();
      expect(m.step, DeliverStep.document);
      expect(m.reverse, isTrue);
    });

    test('fotoğraf ve imza zorunlulukları; imza alınamadı = foto + konum', () {
      final m = model(_detail(photo: false, signature: true));
      expect(m.photoRequired, isFalse);
      expect(m.photosError, isNull);
      expect(m.signatureError, DriverCopy.signatureRequired);
      expect(m.gpsRequired, isFalse);

      m.goTo(DeliverStep.signature);
      m.setWaiver(const SignatureWaiver(SignatureWaiverReason.refused));
      expect(m.signatureError, isNull);
      expect(m.photoRequired, isTrue, reason: 'imza yoksa fotoğraf şart');
      expect(m.gpsRequired, isTrue, reason: 'imza yoksa konum şart');
      // İleri: fotoğraf yoksa fotoğraf adımına döner.
      expect(m.next(), DriverCopy.waiverNeedsPhoto);
      expect(m.step, DeliverStep.photos);

      m.addPhotos(['/tmp/a.jpg']);
      expect(m.photosError, isNull);
      m.clearWaiver();
      expect(m.signatureError, DriverCopy.signatureRequired);
      m.setSignature('/tmp/s.png');
      expect(m.signatureError, isNull);
      expect(m.draft.waiver, isNull);
    });

    test('Diğer nedeni açıklamasız geçmez', () {
      final m = model(_detail());
      m.setWaiver(const SignatureWaiver(SignatureWaiverReason.other, 'a'));
      expect(m.signatureError, DriverCopy.waiverNoteRequired);
    });

    test('özetten geriye ilk eksik adım; tamamlanınca hazır', () {
      final m = model(_detail(signature: false));
      expect(m.firstInvalidStep, DeliverStep.liters);
      m.fillPlanned();
      expect(m.firstInvalidStep, DeliverStep.document);
      m.setDocument('IRS-1');
      expect(m.firstInvalidStep, DeliverStep.photos);
      m.addPhotos(['/tmp/a.jpg']);
      expect(m.firstInvalidStep, isNull);
      expect(m.isComplete, isTrue);
    });

    test('düzeltme: önceki teslim bilgileri ve fotoğraflar önerilir', () {
      final d = _detail(
        status: 4,
        delivered: 5800,
        attachments: [
          {
            'publicId': 'p-1',
            'ownerType': 10,
            'ownerId': 5002,
            'kind': 30,
            'fileName': 'a.jpg',
            'contentType': 'image/jpeg',
            'isActive': true,
          },
        ],
      );
      final m = model(d);
      expect(m.draft.correction, isTrue);
      expect(m.draft.litersText, '5800');
      expect(m.draft.documentNo, 'IRS-1');
      expect(m.draft.recipientName, 'Volkan Ateş');
      expect(m.draft.photos.single.publicId, 'p-1');
      expect(m.draft.photos.single.fromServer, isTrue);
    });

    test(
      'her değişiklik taslağa yazılır; yeniden açınca aynı adımdan sürer',
      () async {
        final m = model(_detail());
        m.fillPlanned();
        m.next();
        m.setDocument('IRS-42');
        m.next();
        await m.flush();
        final saved = store.get('u-sofor', 5002);
        expect(saved, isNotNull);
        expect(saved!.step, DeliverStep.recipient);
        expect(saved.litersText, '8000');
        expect(saved.documentNo, 'IRS-42');

        final again = model(_detail(), initial: saved);
        expect(again.step, DeliverStep.recipient);
        expect(again.draft.documentNo, 'IRS-42');
      },
    );

    test('taslak 24 saat sonra düşer, dosyaları silinir', () async {
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime.utc(2026, 10, 21, 9);
      final s = DeliverDraftStore(PrefsStore(prefs), files, clock: () => now);
      await s.save(
        'u-sofor',
        DeliverDraft(
          shipmentId: 5002,
          code: 'SVK-00005002',
          litersText: '10',
          photos: const [DraftPhoto(path: '/tmp/x.jpg')],
          savedAt: now,
        ),
      );
      expect(s.get('u-sofor', 5002), isNotNull);
      now = now.add(const Duration(hours: 25));
      expect(s.get('u-sofor', 5002), isNull);
      expect(files.deleted, contains('/tmp/x.jpg'));
      final raw = prefs.getString(DeliverDraftStore.keyFor('u-sofor'));
      expect(raw == null || (jsonDecode(raw) as Map).isEmpty, isTrue);
    });

    test('taslak kullanıcıya özeldir (çıkışta silinen önek)', () {
      expect(
        DeliverDraftStore.keyFor('u-sofor'),
        PrefKeys.user('u-sofor', 'driver.deliverDrafts'),
      );
    });

    test('vazgeç: korunan dosyalar dışında silinir', () async {
      final m = model(_detail());
      m.addPhotos(['/tmp/keep.jpg', '/tmp/drop.jpg']);
      await m.flush();
      await m.discard(keep: {'/tmp/keep.jpg'});
      expect(files.deleted, ['/tmp/drop.jpg']);
      expect(store.get('u-sofor', 5002), isNull);
    });
  });
}
