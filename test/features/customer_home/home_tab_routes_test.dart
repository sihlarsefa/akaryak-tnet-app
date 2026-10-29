// v4 B14 (QA SC-01): ana sayfadan bir alt menü sekmesine giden bağlantılar `push` değil
// `openAppLocation` kullanır. Talep edende "Teslimatlar" bir sekmedir ("Teslimat"): "Yolda › Tümü"
// sekmeye geçer (yığın kökte kalır, geri tuşu Ana sayfa'ya döner); yöneticide sekme değildir,
// sayfa ana sayfanın üstüne açılır. Gerçek uygulama: kabuk, gerçek yönlendirici, tüm sahteler.
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_home/copy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../qa/shell-common/qa_support.dart';

/// "Yolda" (ya da "Bugün gelecek") başlığındaki "Tümü".
Finder _onTheWayAll() => find.descendant(
  of: find.byWidgetPredicate(
    (w) =>
        w is SectionHeader &&
        (w.title == HomeCopy.onTheWay || w.title == HomeCopy.arrivingToday),
  ),
  matching: find.textContaining(HomeCopy.all),
);

Future<void> _openShipmentsFromHome(
  WidgetTester tester,
  String persona, {
  required bool tab,
}) async {
  final qa = QaProblems('b14_home_shipments_$persona');
  try {
    final app = await launchQa(tester);
    await qaSignIn(tester, app, persona);
    final router = app.container.read(routerProvider);
    router.go('/home');
    await pumpSteps(tester, const Duration(milliseconds: 1200));
    await settleIo(tester);
    qa.check(tester, 'ana sayfa');
    final all = _onTheWayAll();
    await qaScrollTo(tester, all);
    expect(all, findsOneWidget);
    qa.where = 'Yolda › Tümü';
    await qaTap(tester, all);
    await pumpSteps(tester, const Duration(milliseconds: 1500));
    await settleIo(tester);
    qa.check(tester, 'Yolda › Tümü');
    expect(app.location, '/shipments');
    // Sekmeye `go` ile geçildi: üstte açılmış bir sayfa yok. Sekme değilse sayfa yığına eklenir.
    expect(router.canPop(), tab ? isFalse : isTrue);
    await tester.pumpWidget(const SizedBox());
  } catch (e, st) {
    qa.add(
      'beklenmeyen: ${e.toString().split('\n').take(8).join(' ')} @ '
      '${st.toString().split('\n').where((l) => l.contains('customer_home')).take(3).join(' | ')}',
    );
  } finally {
    qa.finish();
  }
}

void main() {
  testWidgets(
    'talep eden: "Yolda › Tümü" Teslimat sekmesine geçer (kabuk ikinci kez kurulmaz)',
    (tester) => _openShipmentsFromHome(tester, 'talep', tab: true),
  );

  testWidgets(
    'şirket yöneticisi: "Yolda › Tümü" Teslimatlar sayfasını ana sayfanın üstüne açar',
    (tester) => _openShipmentsFromHome(tester, 'musteri', tab: false),
  );
}
