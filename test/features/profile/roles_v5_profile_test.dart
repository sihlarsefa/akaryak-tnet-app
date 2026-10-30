// Roller v5 Profil (spec akn-roles-v5 §7): rol adı sunucudan (panelle aynı), birim onaycısında
// "Finans birimi · onaycı", müşteride sunucunun etiketi (`customerUserRoleLabel`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'a8_kit.dart';

const _tall = Size(390, 2600);

void main() {
  testWidgets('finans birimi onaycısı: "Finans birimi · onaycı"', (
    tester,
  ) async {
    setPhoneSize(tester, _tall);
    await pumpA8(tester, '/profile', persona: 'finans');
    expect(find.textContaining('Finans birimi · onaycı'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('onaycı olmayan İkmal birimi: yalnızca rol adı', (tester) async {
    setPhoneSize(tester, _tall);
    await pumpA8(tester, '/profile', persona: 'ikmal');
    expect(find.textContaining('İkmal birimi'), findsOneWidget);
    expect(find.textContaining('onaycı'), findsNothing);
    await finish(tester);
  });

  testWidgets('pasif rol: "(pasif)" ekiyle', (tester) async {
    setPhoneSize(tester, _tall);
    await pumpA8(tester, '/profile', persona: 'izleyici');
    expect(find.textContaining('Görüntüleyici (pasif)'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('müşteri: rol sunucunun etiketi ("Yönetici")', (tester) async {
    setPhoneSize(tester, _tall);
    await pumpA8(tester, '/profile');
    expect(find.textContaining('Yönetici'), findsOneWidget);
    await finish(tester);
  });
}
