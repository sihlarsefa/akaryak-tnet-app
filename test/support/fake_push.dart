// Push için test sahteleri: bildirim izninin platform çağrıları ve Firebase'siz bir PushService
// (dinleyici bağlamaz, belirteç sabit). Ağ ve eklenti yok.
import 'package:akaryakitnet/core/push/push_service.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// İzin durumu ve sistem penceresi. Varsayılan iOS gibidir: sorulmadan önce `notDetermined`,
/// sorulunca [answer]. [sdk] verilirse Android API düzeyi.
class FakePushPlatform implements PushPermissionPlatform {
  FakePushPlatform({
    this.current = AuthorizationStatus.notDetermined,
    this.answer = AuthorizationStatus.authorized,
    this.sdk,
  });

  AuthorizationStatus current;
  AuthorizationStatus answer;
  final int? sdk;

  /// Açılan sistem pencereleri.
  int requests = 0;

  @override
  Future<int?> androidSdkInt() async => sdk;

  @override
  Future<AuthorizationStatus> status() async => current;

  @override
  Future<AuthorizationStatus> request() async {
    requests++;
    current = answer;
    return answer;
  }
}

/// Firebase yapılandırılmış gibi davranan PushService: izin [FakePushPlatform]'dan, belirteç sabit.
class FakePushService extends PushService {
  FakePushService({
    required PrefsStore super.prefs,
    required FakePushPlatform super.permissions,
    this.fakeToken = 'tok-1',
  }) : super(available: true);

  final String? fakeToken;

  /// Çıkışta silinen belirteçler.
  int deletes = 0;

  @override
  Future<void> start() async {}

  @override
  Future<String?> token() async => fakeToken;

  @override
  Future<void> deleteToken() async {
    deletes++;
  }
}
