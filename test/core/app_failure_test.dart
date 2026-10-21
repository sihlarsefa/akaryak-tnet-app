import 'dart:io';

import 'package:akaryakitnet/core/network/api_client.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/idempotency.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_adapter.dart';

void main() {
  group('AppFailure.fromResponse (ProblemDetails code)', () {
    Map<String, Object?> problem(
      int status,
      String code, [
      String detail = 'Mesaj',
    ]) => {'status': status, 'code': code, 'detail': detail, 'traceId': 'abc'};

    test('400 validation → alan hataları', () {
      final f = AppFailure.fromResponse(400, {
        ...problem(400, 'validation', 'Lütfen alanları kontrol edin.'),
        'errors': {
          'QuantityLiters': ['Litre sıfırdan büyük olmalı.'],
        },
      });
      expect(f, isA<ValidationFailure>());
      final v = f as ValidationFailure;
      expect(v.errorFor('quantityliters'), 'Litre sıfırdan büyük olmalı.');
      expect(v.message, 'Lütfen alanları kontrol edin.');
      expect(v.traceId, 'abc');
    });

    test('400 business_rule → sunucunun Türkçe mesajı', () {
      final f = AppFailure.fromResponse(
        400,
        problem(400, 'business_rule', 'Bu siparişe teklif verilemez.'),
      );
      expect(f, isA<BusinessFailure>());
      expect(f.message, 'Bu siparişe teklif verilemez.');
      expect(f.isUncertain, isFalse);
    });

    test('401 kodları', () {
      final expired = AppFailure.fromResponse(
        401,
        problem(401, 'token_expired'),
      );
      expect((expired as UnauthorizedFailure).isTokenExpired, isTrue);
      final revoked = AppFailure.fromResponse(
        401,
        problem(401, 'session_revoked'),
      );
      expect((revoked as UnauthorizedFailure).isSessionRevoked, isTrue);
      final bare = AppFailure.fromResponse(401, null);
      expect((bare as UnauthorizedFailure).reason, 'unauthorized');
      expect(bare.message, contains('Oturumunuz sona erdi'));
    });

    test('403, 404, 426', () {
      expect(
        AppFailure.fromResponse(403, null).message,
        'Bu işlem için yetkiniz yok.',
      );
      expect(AppFailure.fromResponse(404, null), isA<NotFoundFailure>());
      expect(
        AppFailure.fromResponse(426, problem(426, 'app_update_required')),
        isA<UpdateRequiredFailure>(),
      );
    });

    test('409 çakışma kodları', () {
      final c =
          AppFailure.fromResponse(
                409,
                problem(409, 'concurrency_conflict', 'Kayıt değişti.'),
              )
              as ConflictFailure;
      expect(c.isConcurrency, isTrue);
      expect(c.isUncertain, isFalse);
      final p =
          AppFailure.fromResponse(409, {'code': 'idempotency_in_progress'})
              as ConflictFailure;
      expect(p.isInProgress, isTrue);
      expect(p.isUncertain, isTrue, reason: 'aynı anahtarla tekrar denenmeli');
      expect(p.isTransient, isTrue);
      expect(
        AppFailure.fromResponse(409, problem(409, 'already_reported')),
        isA<ConflictFailure>(),
      );
    });

    test('429 Retry-After', () {
      final f =
          AppFailure.fromResponse(
                429,
                problem(429, 'rate_limited'),
                retryAfterHeader: '30',
              )
              as RateLimitedFailure;
      expect(f.retryAfter, const Duration(seconds: 30));
      expect(f.isTransient, isTrue);
    });

    test('5xx → ServerFailure, istisna metni sızmaz', () {
      final f = AppFailure.fromResponse(
        500,
        'System.NullReferenceException at …',
      );
      expect(f, isA<ServerFailure>());
      expect(f.message, isNot(contains('Exception')));
      expect(f.isUncertain, isTrue);
      final disabled = AppFailure.fromResponse(
        503,
        problem(503, 'assistant_disabled', 'Asistan kapalı.'),
      );
      expect(disabled.message, 'Asistan kapalı.');
      expect(disabled.isTransient, isFalse);
    });
  });

  group('AppFailure.from (Dio istisnaları)', () {
    final options = RequestOptions(path: '/x');

    test('bağlantı, zaman aşımı, iptal', () {
      expect(
        AppFailure.from(
          DioException.connectionError(requestOptions: options, reason: 'x'),
        ),
        isA<OfflineFailure>(),
      );
      expect(
        AppFailure.from(
          DioException.receiveTimeout(
            timeout: Duration.zero,
            requestOptions: options,
          ),
        ),
        isA<TimeoutFailure>(),
      );
      final cancel = AppFailure.from(
        DioException.requestCancelled(requestOptions: options, reason: 'x'),
      );
      expect((cancel as UnknownFailure).cancelled, isTrue);
      expect(
        AppFailure.from(const SocketException('x')),
        isA<OfflineFailure>(),
      );
      expect(
        AppFailure.from(const FormatException('x')),
        isA<UnknownFailure>(),
      );
      expect(AppFailure.from(StateError('x')), isA<UnknownFailure>());
    });

    test('ApiClient yalnızca AppFailure fırlatır', () async {
      final adapter = QueueAdapter()
        ..problem(400, 'business_rule', 'Sipariş kapalı.')
        ..connectionError()
        ..json(200, {'unexpected': true});
      final api = ApiClient(
        Dio(BaseOptions(baseUrl: 'http://x/api/v1/'))
          ..httpClientAdapter = adapter,
      );
      await expectLater(
        api.get('orders/1', parse: (j) => j),
        throwsA(
          isA<BusinessFailure>().having(
            (f) => f.message,
            'message',
            'Sipariş kapalı.',
          ),
        ),
      );
      await expectLater(
        api.get('orders/1', parse: (j) => j),
        throwsA(isA<OfflineFailure>()),
      );
      await expectLater(
        api.get<int>('orders/1', parse: (j) => (j! as List).length),
        throwsA(isA<UnknownFailure>()),
        reason: 'ayrıştırma hatası da AppFailure olur',
      );
    });
  });

  group('IdempotencyLedger', () {
    test('belirsiz sonuçta anahtar korunur, kesin sonuçta bırakılır', () {
      var n = 0;
      final ledger = IdempotencyLedger(generator: () => 'k${++n}');
      final k1 = ledger.keyFor('orders/place');
      expect(ledger.keyFor('orders/place'), k1);
      ledger.settle('orders/place', error: const TimeoutFailure());
      expect(
        ledger.keyFor('orders/place'),
        k1,
        reason: 'zaman aşımında aynı anahtarla tekrar',
      );
      ledger.settle('orders/place', error: const BusinessFailure('Hayır'));
      expect(
        ledger.keyFor('orders/place'),
        isNot(k1),
        reason: 'kesin yanıt sonrası yeni niyet',
      );
    });

    test('UUID v4 biçimi', () {
      for (var i = 0; i < 50; i++) {
        expect(isValidIdempotencyKey(newIdempotencyKey()), isTrue);
      }
    });
  });
}
