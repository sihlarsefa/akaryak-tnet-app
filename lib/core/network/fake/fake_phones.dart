import '../../models/json.dart';
import '../../models/me_access.dart';
import '../../utils/validators.dart';
import 'fake_personas.dart';
import 'fake_world.dart';

/// Sahte dünyada hesapların cep telefonları ve telefonla girişe uygunluk (sunucu
/// `MobileAuthService.ResolveOtpTargetAsync` / `IsOtpEligibleAsync` aynası). 2026-11: ayrı telefon
/// doğrulaması yok; hesapta kayıtlı numara (yönetici ya da Profil girer) telefonla giriş için yeter.
///
/// - Uygun hesap: merkez değil, demo / tohum hesabı değil, pasif değil.
/// - Numara tek bir uygun hesaptaysa kod o hesaba gider; hiçbirinde ya da birden çoğunda ise SMS
///   gitmez (yanıt yine aynı: "kod gönderildi").
abstract final class FakePhones {
  /// Profil düzenlemeleri (`PUT me/profile`; profil sahtesi yazar, kimlik sahtesi okur): persona
  /// anahtarı → `{displayName, phoneNumber}`.
  static const editsBag = 'profile.edits';

  static const _seedBag = 'auth.seedAccounts';

  /// Numara başka bir uygun hesapta da kayıtlı (sunucu iletisi): `PUT me/profile` uyarısı, şirket
  /// kullanıcısı / personel kaydında `phoneNumber` doğrulama hatası.
  static const sharedMessage =
      'Bu cep numarası başka bir hesapta kayıtlı; telefonla giriş için her hesapta farklı numara olmalı.';

  static Map<String, JsonMap> edits(FakeWorld w) =>
      w.bag<Map<String, JsonMap>>(editsBag, () => {});

  /// Demo / tohum hesabı sayılan personalar (sunucuda e-postası `@akaryakitnet.local` ile biten hesaplar,
  /// `MobileAccountRules.IsSeedAccount`; sahte personaların e-postası `@demo.akaryakitnet.local` olduğundan
  /// hiçbiri kendiliğinden sayılmaz). Testler ekler; dünya sıfırlanınca boşalır.
  static Set<String> seedAccounts(FakeWorld w) =>
      w.bag<Set<String>>(_seedBag, () => {});

  /// Personanın hesabındaki numara (`90` + 10 hane); boşaltıldıysa ya da geçersizse null.
  static String? of(FakeWorld w, FakePersona p) {
    final e = edits(w)[p.key];
    final raw = e != null && e.containsKey('phoneNumber')
        ? e['phoneNumber'] as String?
        : p.phone;
    return Validators.normalizePhone(raw);
  }

  /// `0532 *** ** 01` biçimi (`90` + 10 hane girdi).
  static String mask(String phone) {
    final ten = phone.substring(phone.length - 10);
    return '0${ten.substring(0, 3)} *** ** ${ten.substring(8)}';
  }

  /// Telefonla girişe uygun hesap mı (merkez, demo / tohum ve pasif hariç).
  static bool eligible(FakeWorld w, FakePersona p) =>
      p.persona != Persona.platform &&
      !p.passive &&
      !seedAccounts(w).contains(p.key);

  /// [phone] (`90` + 10 hane) numarasını taşıyan uygun hesaplar ([exceptKey] hariç).
  static List<FakePersona> owners(
    FakeWorld w,
    String phone, {
    String? exceptKey,
  }) => [
    for (final p in fakePersonas)
      if (p.key != exceptKey && of(w, p) == phone && eligible(w, p)) p,
  ];

  /// Kodun gideceği hesap: numara tam bir uygun hesaptaysa o, yoksa null (SMS gitmez).
  static FakePersona? otpTarget(FakeWorld w, String phone) {
    final list = owners(w, phone);
    return list.length == 1 ? list.single : null;
  }

  /// [raw] numarası [exceptKey] dışında bir uygun hesapta da kayıtlı mı.
  static bool sharedWithOther(FakeWorld w, String? raw, {String? exceptKey}) {
    final phone = Validators.normalizePhone(raw);
    return phone != null && owners(w, phone, exceptKey: exceptKey).isNotEmpty;
  }
}
