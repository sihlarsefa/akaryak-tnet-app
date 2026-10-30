import '../../utils/turkish_text.dart';
import '../../utils/validators.dart';
import 'fake_personas.dart';

/// Sunucunun şifre kuralları (Identity: en az 8 karakter, rakam, küçük ve büyük harf; iletiler
/// `AccountSelfService.Translate` ile aynı). Boş liste: geçerli.
List<String> fakePasswordErrors(String value) => [
  if (value.length < 8) 'Şifre en az 8 karakter olmalıdır.',
  if (!RegExp(r'\d').hasMatch(value)) 'Şifre en az bir rakam içermelidir.',
  if (!RegExp(r'[a-zçğıöşü]').hasMatch(value))
    'Şifre en az bir küçük harf içermelidir.',
  if (!RegExp(r'[A-ZÇĞİÖŞÜ]').hasMatch(value))
    'Şifre en az bir büyük harf içermelidir.',
];

/// Kullanıcı adı kuralı (sunucu: kırpılır; 3–50 karakter; İngilizce harf, rakam, `.`, `_`, `-`; iletiler
/// uygulamanınkiyle aynı, [Validators.userName]).
String? fakeUserNameError(String value) => Validators.userName(value);

/// Kullanıcı adı bir demo personasında ya da [taken] içinde var mı (büyük / küçük harf duyarsız).
bool fakeUserNameTaken(String value, Iterable<String?> taken) {
  final v = TurkishText.lower(value);
  if (fakePersonas.any((p) => p.userName == v)) return true;
  return taken.any((t) => t != null && TurkishText.lower(t) == v);
}
