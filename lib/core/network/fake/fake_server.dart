import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../models/json.dart';
import '../../utils/log.dart';
import '../../utils/turkish_text.dart';
import 'fake_auth.dart';
import 'fake_personas.dart';
import 'fake_world.dart';
import 'multipart.dart';

/// Sahte uç nokta işleyicisi. Dönüş:
/// - JSON'a çevrilebilen değer (Map, List, sayı, metin) → 200 + gövde,
/// - [FakeResponse] → olduğu gibi (ör. `FakeResponse.noContent()`, `FakeResponse.created(...)`),
/// - [FakeBinary] → ikili içerik (PDF, görsel),
/// - `null` → 204.
/// Hata için [FakeResponse] fırlatılabilir (`throw FakeResponse.business('…')`).
typedef FakeHandler = FutureOr<Object?> Function(FakeRequest req);

/// Sahte yanıt. İşleyiciden döndürülür ya da fırlatılır.
class FakeResponse implements Exception {
  const FakeResponse(this.status, [this.body, this.headers = const {}]);

  factory FakeResponse.ok(Object? body) => FakeResponse(200, body);
  factory FakeResponse.created(Object? body) => FakeResponse(201, body);
  factory FakeResponse.accepted(Object? body) => FakeResponse(202, body);
  factory FakeResponse.noContent() => const FakeResponse(204);

  /// RFC 7807 + `code` (spec B.2).
  factory FakeResponse.problem(
    int status,
    String code,
    String detail, {
    Map<String, List<String>>? errors,
    Map<String, String> headers = const {},
  }) => FakeResponse(status, {
    'type': 'about:blank',
    'title': detail,
    'status': status,
    'detail': detail,
    'code': code,
    'traceId':
        'fake-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
    'errors': ?errors,
  }, headers);

  /// 400 `validation`.
  factory FakeResponse.validation(
    Map<String, List<String>> errors, [
    String detail = 'İşaretli alanları kontrol edin.',
  ]) => FakeResponse.problem(400, 'validation', detail, errors: errors);

  /// 400 `business_rule` (ServiceException).
  factory FakeResponse.business(String detail) =>
      FakeResponse.problem(400, 'business_rule', detail);

  factory FakeResponse.unauthorized([
    String code = 'unauthorized',
    String detail = 'Oturum açmanız gerekiyor.',
  ]) => FakeResponse.problem(401, code, detail);

  factory FakeResponse.forbidden([
    String detail = 'Bu işlem için yetkiniz yok.',
  ]) => FakeResponse.problem(403, 'forbidden', detail);

  factory FakeResponse.notFound([String detail = 'Kayıt bulunamadı.']) =>
      FakeResponse.problem(404, 'not_found', detail);

  factory FakeResponse.conflict(String code, String detail) =>
      FakeResponse.problem(409, code, detail);

  factory FakeResponse.server([
    String detail =
        'Sunucu isteği tamamlayamadı. Birkaç dakika sonra tekrar deneyin.',
  ]) => FakeResponse.problem(500, 'server_error', detail);

  final int status;
  final Object? body;
  final Map<String, String> headers;

  @override
  String toString() => 'FakeResponse($status)';
}

/// İkili yanıt gövdesi.
class FakeBinary {
  const FakeBinary(
    this.bytes, {
    this.contentType = 'application/octet-stream',
    this.fileName,
  });
  final Uint8List bytes;
  final String contentType;
  final String? fileName;
}

/// Sahte isteğin okunmuş hâli.
class FakeRequest {
  FakeRequest({
    required this.server,
    required this.method,
    required this.path,
    required this.uri,
    this.params = const {},
    this.body,
    this.multipart,
    this.headers = const {},
    this.user,
  });

  final FakeServer server;
  final String method;

  /// `api/v1/` köküne göre yol (baştaki `/` yok): `orders/12`.
  final String path;
  final Uri uri;

  /// Yol parametreleri (`orders/{id}` → `{'id': '12'}`).
  final Map<String, String> params;

  /// Çözülmüş JSON gövdesi (Map/List) ya da null.
  final Object? body;

  /// Çok parçalı form (yükleme).
  final FakeMultipart? multipart;

  /// Küçük harfli başlık adları.
  final Map<String, String> headers;

  /// Belirteçten çözülen kullanıcı (anonim uçlarda null olabilir).
  final FakePersona? user;

  FakeWorld get world => server.world;

  /// JSON gövdesi okuyucu.
  JsonReader get json => JsonReader.of(body);

  String? header(String name) => headers[name.asciiLower];

  String? get idempotencyKey => header('idempotency-key');

  String? query(String key) {
    final v = uri.queryParametersAll[key];
    return v == null || v.isEmpty ? null : v.first;
  }

  List<String> queryAll(String key) => uri.queryParametersAll[key] ?? const [];

  int? queryInt(String key) => int.tryParse(query(key) ?? '');

  bool? queryBool(String key) => switch (query(key)?.asciiLower) {
    'true' || '1' => true,
    'false' || '0' => false,
    _ => null,
  };

  /// `?page=&pageSize=` (varsayılan 1 / 25, en fazla 100).
  ({int page, int pageSize}) get paging {
    final page = max(1, queryInt('page') ?? 1);
    final size = (queryInt('pageSize') ?? 25).clamp(1, 100);
    return (page: page, pageSize: size);
  }

  /// Tamsayı yol parametresi.
  int intParam(String name) =>
      int.tryParse(params[name] ?? '') ?? (throw FakeResponse.notFound());

  /// Oturum açmış kullanıcı (yoksa 401).
  FakePersona requireUser() => user ?? (throw FakeResponse.unauthorized());

  /// Sayfa yetkisi yoksa 403.
  void requirePage(String page, [String perm = 'Gorur']) {
    if (!requireUser().can(page, perm)) throw FakeResponse.forbidden();
  }

  /// Listeyi sayfalar ve `PagedResult` JSON'u döndürür.
  JsonMap paged(List<Object?> all) {
    final p = paging;
    final start = (p.page - 1) * p.pageSize;
    final items = start >= all.length
        ? const <Object?>[]
        : all.sublist(start, min(all.length, start + p.pageSize));
    return {
      'items': items,
      'totalCount': all.length,
      'pageNumber': p.page,
      'pageSize': p.pageSize,
      'totalPages': (all.length / p.pageSize).ceil(),
    };
  }
}

/// Kayıtlı sahte uç nokta.
class FakeRoute {
  FakeRoute(
    this.method,
    this.pattern,
    this.handler, {
    this.anonymous = false,
    required this.order,
  }) : _segments = pattern.split('/').where((s) => s.isNotEmpty).toList();

  final String method;

  /// `orders/{id}`, `payments/{orderId:int}`, `stations/me/quote-desk`.
  final String pattern;
  final FakeHandler handler;

  /// Oturum gerektirmez (giriş, app/config).
  final bool anonymous;

  /// Kayıt sırası (sonra kaydedilen kazanır).
  final int order;
  final List<String> _segments;

  int get literalCount => _segments.where((s) => !s.startsWith('{')).length;

  Map<String, String>? match(String method, String path) {
    if (method.asciiUpper != this.method) return null;
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length != _segments.length) return null;
    final params = <String, String>{};
    for (var i = 0; i < parts.length; i++) {
      final seg = _segments[i];
      final part = Uri.decodeComponent(parts[i]);
      if (seg.startsWith('{') && seg.endsWith('}')) {
        final spec = seg.substring(1, seg.length - 1).split(':');
        if (spec.length > 1 && spec[1] == 'int' && int.tryParse(part) == null) {
          return null;
        }
        params[spec[0]] = part;
      } else if (seg.asciiLower != part.asciiLower) {
        return null;
      }
    }
    return params;
  }
}

/// Dev menüsünden açılan hata enjeksiyonu.
enum FakeFailureMode {
  none('Kapalı'),
  offline('Bağlantı yok'),
  timeout('Zaman aşımı'),
  serverError('Sunucu hatası (500)'),
  flaky('Ara sıra hata (%20)');

  const FakeFailureMode(this.label);
  final String label;
}

/// Uygulama içi sahte API sunucusu (spec C.4 / D.4). `API_MODE=fake` iken Dio'nun adaptörü
/// [FakeApiAdapter] bu sunucuya yönlendirir. Durum bellektedir ([world]); 300–800 ms gecikme ve dev
/// menüsünden hata enjeksiyonu vardır.
///
/// Özellikler kendi uçlarını `features/<f>/<f>_fake.dart` içindeki `register<F>Fakes(FakeServer s)` ile
/// kaydeder. Aynı yöntem + yol için **sonra kaydedilen kazanır** (özellik, çekirdek sahtesini ezebilir).
class FakeServer {
  FakeServer({
    FakeWorld? world,
    Random? random,
    this.minLatency = const Duration(milliseconds: 300),
    this.maxLatency = const Duration(milliseconds: 800),
  }) : world = world ?? FakeWorld.seeded(),
       random = random ?? Random();

  final FakeWorld world;
  final Random random;
  late final FakeAuth auth = FakeAuth(this);

  Duration minLatency;
  Duration maxLatency;

  /// Gecikme açık mı (testlerde kapalı).
  bool latencyEnabled = true;
  FakeFailureMode failureMode = FakeFailureMode.none;

  final List<FakeRoute> _routes = [];
  int _order = 0;

  /// Idempotency tekrarları: `userId|key` → yanıt.
  final Map<String, ({String hash, FakeResponse response})> _idempotency = {};

  /// Testler için: gecikmesiz, hatasız sunucu.
  factory FakeServer.forTests({FakeWorld? world}) =>
      FakeServer(world: world, random: Random(7))..latencyEnabled = false;

  void on(
    String method,
    String pattern,
    FakeHandler handler, {
    bool anonymous = false,
  }) => _routes.add(
    FakeRoute(
      method.asciiUpper,
      pattern,
      handler,
      anonymous: anonymous,
      order: _order++,
    ),
  );

  void get(String pattern, FakeHandler handler, {bool anonymous = false}) =>
      on('GET', pattern, handler, anonymous: anonymous);
  void post(String pattern, FakeHandler handler, {bool anonymous = false}) =>
      on('POST', pattern, handler, anonymous: anonymous);
  void put(String pattern, FakeHandler handler, {bool anonymous = false}) =>
      on('PUT', pattern, handler, anonymous: anonymous);
  void delete(String pattern, FakeHandler handler, {bool anonymous = false}) =>
      on('DELETE', pattern, handler, anonymous: anonymous);

  /// Kayıtlı uç sayısı (tanılama).
  int get routeCount => _routes.length;

  /// Rastgele gecikme (300–800 ms).
  Duration nextLatency() {
    if (!latencyEnabled) return Duration.zero;
    final span = maxLatency.inMilliseconds - minLatency.inMilliseconds;
    return minLatency +
        Duration(milliseconds: span <= 0 ? 0 : random.nextInt(span));
  }

  /// İsteği işler. Hata enjeksiyonu [FakeApiAdapter] içindedir.
  Future<FakeResponse> handle({
    required String method,
    required String path,
    required Uri uri,
    Object? body,
    FakeMultipart? multipart,
    Map<String, String> headers = const {},
  }) async {
    FakeRoute? best;
    Map<String, String>? bestParams;
    for (final r in _routes) {
      final p = r.match(method, path);
      if (p == null) continue;
      if (best == null ||
          r.literalCount > best.literalCount ||
          (r.literalCount == best.literalCount && r.order > best.order)) {
        best = r;
        bestParams = p;
      }
    }
    if (best == null) {
      return FakeResponse.problem(
        404,
        'not_found',
        'Sahte API\'de tanımlı değil: $method $path',
      );
    }

    final bearer = headers['authorization'];
    final token = bearer != null && bearer.startsWith('Bearer ')
        ? bearer.substring(7)
        : null;
    final access = token == null ? null : auth.resolveAccess(token);
    if (!best.anonymous) {
      if (token == null) return FakeResponse.unauthorized();
      if (access == null) {
        return FakeResponse.unauthorized('unauthorized', 'Oturum geçersiz.');
      }
      if (access.expired) {
        return FakeResponse.unauthorized(
          'token_expired',
          'Oturum süresi doldu.',
        );
      }
      if (access.revoked) {
        return FakeResponse.unauthorized(
          'session_revoked',
          'Oturum sonlandırıldı.',
        );
      }
    }
    final user = access != null && !access.expired && !access.revoked
        ? world.persona(access.personaKey)
        : null;

    final req = FakeRequest(
      server: this,
      method: method,
      path: path,
      uri: uri,
      params: bestParams ?? const {},
      body: body,
      multipart: multipart,
      headers: headers,
      user: user,
    );

    // Idempotency (spec B.2): aynı anahtar + aynı gövde → aynı yanıt; farklı gövde → 400.
    final key = req.idempotencyKey;
    final idemKey = key != null && method != 'GET'
        ? '${user?.userId ?? '-'}|$key'
        : null;
    final bodyHash = idemKey == null ? '' : _hash(path, body, multipart);
    if (idemKey != null) {
      final prior = _idempotency[idemKey];
      if (prior != null) {
        if (prior.hash != bodyHash) {
          return FakeResponse.validation(
            const {},
            'Aynı Idempotency-Key farklı bir istekle kullanıldı.',
          );
        }
        return FakeResponse(prior.response.status, prior.response.body, {
          ...prior.response.headers,
          'idempotent-replay': 'true',
        });
      }
    }

    FakeResponse response;
    try {
      final result = await best.handler(req);
      response = switch (result) {
        null => FakeResponse.noContent(),
        final FakeResponse r => r,
        final FakeBinary b => FakeResponse(200, b),
        _ => FakeResponse(200, result),
      };
    } on FakeResponse catch (r) {
      response = r;
    } catch (e, st) {
      AppLog.error('Sahte işleyici hatası: $method $path', e, st);
      response = FakeResponse.server();
    }

    if (idemKey != null && response.status < 500) {
      _idempotency[idemKey] = (hash: bodyHash, response: response);
    }
    return response;
  }

  static String _hash(String path, Object? body, FakeMultipart? multipart) {
    if (multipart != null) {
      final files = multipart.files
          .map((f) => '${f.field}:${f.fileName}:${f.bytes.length}')
          .join(',');
      return '$path|${jsonEncode(multipart.fields)}|$files';
    }
    try {
      return '$path|${jsonEncode(body)}';
    } catch (_) {
      return '$path|$body';
    }
  }

  /// Dev menüsü: sahte verileri baştan yükler (oturumlar korunur).
  void resetWorld() {
    world.reset();
    _idempotency.clear();
  }
}
