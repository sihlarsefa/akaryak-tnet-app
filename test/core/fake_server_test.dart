import 'dart:convert';
import 'dart:typed_data';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/media/attachment_api.dart';
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/fake/fake_api_adapter.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

void main() {
  group('FakeServer yönlendirme', () {
    test(
      'sabit parça değişkenden önce gelir; sonra kaydedilen kazanır',
      () async {
        final s = FakeServer.forTests(world: FakeWorld.seeded())
          ..get(
            'approvals/{id}',
            (r) => {'kind': 'detail', 'id': r.params['id']},
            anonymous: true,
          )
          ..get('approvals/badge', (r) => {'kind': 'badge'}, anonymous: true)
          ..get('items/{id:int}', (r) => {'v': 1}, anonymous: true)
          ..get('items/{id:int}', (r) => {'v': 2}, anonymous: true);
        Future<FakeResponse> get(String path) => s.handle(
          method: 'GET',
          path: path,
          uri: Uri.parse('http://x/api/v1/$path'),
        );
        expect((await get('approvals/badge')).body, {'kind': 'badge'});
        expect((await get('approvals/42')).body, {
          'kind': 'detail',
          'id': '42',
        });
        expect((await get('items/7')).body, {'v': 2});
        final missing = await get('items/abc');
        expect(missing.status, 404);
        expect(jsonEncode(missing.body), contains('Sahte API'));
      },
    );

    test('yol göreli hâle gelir', () {
      expect(
        FakeApiAdapter.relativePath(
          Uri.parse('http://x:3108/api/v1/orders/12/'),
        ),
        'orders/12',
      );
      expect(
        FakeApiAdapter.relativePath(Uri.parse('http://x/api/Auth/login')),
        'api/Auth/login',
      );
    });

    test('dünya tohumu tutarlı', () {
      // Roller v5 öncesi akış: Onaylayan'ın bekleyen şirket içi talebi (9003) tohumlanır.
      final w = FakeWorld.seeded(companyApprovals: true);
      for (final s in w.shipments) {
        expect(
          w.order(s['orderId'] as int),
          isNotNull,
          reason: 'sevkiyat ${s['id']}',
        );
      }
      expect(w.shipmentsOfDriver('u-sofor'), isNotEmpty);
      expect(
        w.ordersOfCustomer(101).map((o) => o['status']),
        containsAll([1, 2, 3, 7]),
      );
      expect(w.approvalsWaitingFor(findFakePersona('finans')!), 1);
      expect(w.approvalsWaitingFor(findFakePersona('onay')!), 1);
      expect(w.approvalsWaitingFor(findFakePersona('sofor')!), 0);
      expect(w.unreadNotifications('u-musteri'), greaterThan(0));
      final detail = OrderDetail.fromJson(
        w.orders.firstWhere((o) => o['status'] == 2),
      );
      expect(detail.currentQuote?.unitPriceTry, 42.35);
      expect(detail.expiresAt!.isAfter(DateTime.now().toUtc()), isTrue);
    });
  });

  group('Sahte API uçtan uca (Dio üzerinden)', () {
    late TestHarness h;
    late ProviderContainer c;

    setUp(() async {
      h = await TestHarness.create(prefs: {'akn.onboardingDone': true});
      c = h.container();
      addTearDown(c.dispose);
    });

    test('oturumsuz istek 401; app/config anonim', () async {
      await expectLater(
        c.read(apiClientProvider).get('me/access', parse: (j) => j),
        throwsA(isA<UnauthorizedFailure>()),
      );
      final config = await c
          .read(apiClientProvider)
          .get('app/config', anonymous: true, parse: AppConfig.fromJson);
      expect(config.features.otpLogin, isTrue);
      expect(config.features.assistant, isTrue);
    });

    test('Idempotency: aynı anahtar aynı yanıt, farklı gövde 400', () async {
      await c
          .read(sessionControllerProvider.notifier)
          .loginWithPassword('musteri', 'demo');
      var n = 0;
      h.server.post('test/echo', (r) => {'n': ++n, 'body': r.body});
      final api = c.read(apiClientProvider);
      final a = await api.post(
        'test/echo',
        body: {'x': 1},
        idempotencyKey: 'k-1',
        parse: (j) => j,
      );
      final b = await api.post(
        'test/echo',
        body: {'x': 1},
        idempotencyKey: 'k-1',
        parse: (j) => j,
      );
      expect(a, b);
      expect(n, 1, reason: 'ikinci istek işlenmez, tekrar edilir');
      await expectLater(
        api.post(
          'test/echo',
          body: {'x': 2},
          idempotencyKey: 'k-1',
          parse: (j) => j,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('belge yükleme (çok parçalı) → listeleme → içerik', () async {
      await c
          .read(sessionControllerProvider.notifier)
          .loginWithPassword('musteri', 'demo');
      final api = c.read(attachmentApiProvider);
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4, 5]);
      double? lastProgress;
      final result = await api.uploadBytes(
        ownerType: AttachmentOwnerType.order,
        ownerId: 12002,
        kind: AttachmentKind.chequeImage,
        bytes: png,
        fileName: 'cek.png',
        contentType: 'image/png',
        note: 'Ön yüz',
        onProgress: (p) => lastProgress = p,
      );
      expect(result.attachment.kind, AttachmentKind.chequeImage);
      expect(result.attachment.kindLabel, 'Çek görseli');
      expect(result.attachment.isImage, isTrue);
      expect(result.attachment.note, 'Ön yüz');
      expect(lastProgress, 1.0);

      final list = await api.list(AttachmentOwnerType.order, 12002);
      expect(list.single.publicId, result.attachment.publicId);
      final bytes = await api.content(result.attachment.publicId);
      expect(bytes, png);

      await expectLater(
        api.uploadBytes(
          ownerType: AttachmentOwnerType.order,
          ownerId: 1,
          kind: AttachmentKind.other,
          bytes: Uint8List.fromList([1, 2]),
          fileName: 'x.gif',
          contentType: 'image/gif',
        ),
        throwsA(isA<BusinessFailure>()),
      );
    });

    test('hata enjeksiyonu: bağlantı yok', () async {
      h.server.failureMode = FakeFailureMode.offline;
      await expectLater(
        c
            .read(sessionControllerProvider.notifier)
            .loginWithPassword('musteri', 'demo'),
        throwsA(isA<OfflineFailure>()),
      );
    });

    test('her persona me/access ile kendi kapsamını alır', () async {
      for (final p in fakePersonas) {
        final session = c.read(sessionControllerProvider.notifier);
        final outcome = await session.loginWithPassword(p.key, 'demo');
        if (p.requiresTwoFactor) {
          final ch = (outcome as LoginNeedsCode).challenge;
          await session.verifyCode(ch.challengeId, '123456');
        }
        final access = c.read(sessionControllerProvider).access!;
        expect(access.userName, p.key);
        expect(access.persona, p.persona);
        if (p.persona == Persona.bayi) {
          expect(access.stationTitle, 'Demir Petrol Akaryakıt Ltd. Şti.');
        }
        if (p.persona == Persona.customer) expect(access.customerId, 101);
        await session.signOut();
      }
    });
  });
}
