// C.7 erişilebilirlik: Onaylarım ekranları 360×640'ta, yazı ölçeği 1.0 / 2.0, açık / koyu tema;
// taşma yok, dokunma hedefleri, etiketler ve metin kontrastı yönergelere uygun.
import 'package:flutter_test/flutter_test.dart';

import 'a5_test_kit.dart';

void main() {
  group('C.7 Onaylarım', () {
    a11yMatrix('liste (finans)', persona: 'finans', location: '/approvals');
    a11yMatrix(
      'sipariş finansı ayrıntısı (finans)',
      persona: 'finans',
      location: '/approvals/9001',
    );
    a11yMatrix(
      'ek bilgi yanıtı (cari)',
      persona: 'musteri',
      location: '/approvals/9005',
    );
    a11yMatrix(
      'şirket içi talep sonucu (cari onaylayan)',
      persona: 'onay',
      location: '/approvals/9013',
    );
  });
}
