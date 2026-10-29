// Tasarım v4 tur 2 (B13): finansın bilgi istediği ön kayıt bir onay talebidir — saha ana sayfasının
// "Sıra sizde" işi ile Diğer'in Onaylar noktası aynı sayfayı (talebin yanıt alanı) açar: bir iş, bir
// sayı, bir sayfa. Talep Bende'de bulunamazsa ön kayıt açılır.
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/approvals/api.dart';
import 'package:akaryakitnet/features/approvals/approvals_fake.dart';
import 'package:flutter_test/flutter_test.dart';

import 'field_test_kit.dart';

void main() {
  testWidgets(
    'saha: "Bilgi gönder" talebin yanıt alanını açar (/approvals/:id?reply=1)',
    (tester) async {
      final app = await pumpField(
        tester,
        persona: 'saha',
        location: '/home',
        setup: (h) => registerApprovalsFakes(h.server),
      );
      final card = tester.widget<AknTaskCard>(find.byType(AknTaskCard));
      final info = card.tasks.where((t) => t.id == 'field-lead-info');
      expect(info, hasLength(1), reason: 'ek bilgi bekleyen ön kayıt işi');
      // Talep: ön kayıt 8001'in finans onayı (Bende'de; temsilci yanıtlayacak).
      final request = app.harness.server.world.approvals.firstWhere(
        (a) => a['type'] == 7 && a['subjectId'] == 8001,
      );
      // Ön kayıt işi bir satırdır (gecikmiş saha formu öndedir): satıra dokunmak yanıt alanını açar.
      await tapText(tester, 'Ön kayıt için bilgi gönderin');
      expect(
        find.text('stub:/approvals/${request['id']}?reply=1'),
        findsOneWidget,
      );
      await finish(tester);
    },
  );

  testWidgets(
    'saha (v4 tur 2): Bende\'nin gecikmiş saha formu "Sıra sizde"nin başında; sayı Bende ile aynı',
    (tester) async {
      final app = await pumpField(
        tester,
        persona: 'saha',
        location: '/home',
        setup: (h) => registerApprovalsFakes(h.server),
      );
      final card = tester.widget<AknTaskCard>(find.byType(AknTaskCard));
      final bende = app.container.read(
        approvalsListProvider(const ApprovalsQuery()),
      );
      expect(bende.hasData, isTrue);
      expect(bende.items, isNotEmpty);
      // Kartın sayısı Onaylar › Bende'nin sayısı (gönderilecek form yok).
      expect(AknTaskCard.countOf(card.tasks, card.total), bende.totalCount);
      // Gecikmiş talep öndedir, tehlike tonunda; "Bilgi gönder" yanıt alanını açar.
      final lead = card.tasks.first;
      expect(lead.id, startsWith('approval-'));
      expect(lead.tone, AknTaskTone.danger);
      expect(lead.title, 'Saha formu için bilgi gönderin');
      expect(lead.time, endsWith('gecikti'));
      final id = (lead.id as String).substring('approval-'.length);
      await tapText(tester, 'Bilgi gönder');
      expect(find.text('stub:/approvals/$id?reply=1'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    'Onaylar okunamazsa (sahte uç yok) iş yine ön kaydı açar: çıkmaz sokak yok',
    (tester) async {
      await pumpField(tester, persona: 'saha', location: '/home');
      await tapText(tester, 'Bilgi gönder');
      expect(find.textContaining('stub:/approvals/'), findsNothing);
      expect(find.text('Bilgi gönder'), findsNothing, reason: 'sayfa açıldı');
      await finish(tester);
    },
  );
}
