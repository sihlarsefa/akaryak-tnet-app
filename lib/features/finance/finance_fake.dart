import '../../core/auth/permissions.dart';
import '../../core/models/me_access.dart';
import '../../core/network/fake/fake_server.dart';
import '../../core/utils/tr_time.dart';
import '../../core/utils/turkish_text.dart';
import '../approvals/api.dart';

/// Finans sahte uçları (sahibi A5; spec §B.8).
///
/// - `GET finance/customers?status=pending|approved|closed&risk=1..4&overdue&q&page&pageSize`
///   → `PagedResult<CustomerFinanceListItemDto>`
/// - `GET finance/customers/{stationCustomerId}` → `FinanceCustomerCardDto {profile, reviews, riskReports}`
void registerFinanceFakes(FakeServer server) {
  void require(FakeRequest req) {
    final p = req.requireUser();
    if (p.persona != Persona.bayi || !p.can(Pg.stationFinance)) {
      throw FakeResponse.forbidden();
    }
  }

  List<int>? statuses(String? key) =>
      switch (TurkishText.searchKey(key ?? '')) {
        'pending' || 'bekleyen' => const [0, 3],
        'approved' || 'onayli' => const [1, 2],
        'closed' || 'kapali' || 'red' || 'rejected' => const [4, 5],
        _ => null,
      };

  server.get('finance/customers', (req) {
    require(req);
    final p = req.requireUser();
    final store = A5FakeStore.of(req.world);
    final wanted = statuses(req.query('status'));
    final risk = req.queryInt('risk');
    final overdue = req.queryBool('overdue') ?? false;
    final q = req.query('q');
    final today = TrTime.todayStart();
    final rows =
        [
          for (final id in store.financeLinkIds(p.stationId ?? 0))
            if (store.financeListItem(id) case final item?)
              if ((wanted == null || wanted.contains(item['status'])) &&
                  (risk == null || item['riskClass'] == risk) &&
                  (!overdue ||
                      (TrTime.parseLocal(
                            item['nextReviewDate'] as String?,
                          )?.isBefore(today) ??
                          false)) &&
                  A5FakeStore.matches([
                    item['customerTitle'],
                    item['taxNumber'],
                  ], q))
                item,
        ]..sort(
          (a, b) => '${a['customerTitle']}'.compareTo('${b['customerTitle']}'),
        );
    return req.paged(rows);
  });

  server.get('finance/customers/{id:int}', (req) {
    require(req);
    final p = req.requireUser();
    final store = A5FakeStore.of(req.world);
    final id = req.intParam('id');
    if (!store.financeLinkIds(p.stationId ?? 0).contains(id)) {
      throw FakeResponse.notFound('Cari finans kartı bulunamadı.');
    }
    final card = store.financeCard(id);
    if (card == null) {
      throw FakeResponse.notFound('Cari finans kartı bulunamadı.');
    }
    return card;
  });
}
