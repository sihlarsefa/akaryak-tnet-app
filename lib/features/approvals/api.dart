/// Approvals özelliğinin dışa açık yüzü (sahibi A5). Diğer özellikler yalnızca bu dosyayı içe aktarır;
/// özellikler arası gezinme rota yollarıyla yapılır (`AppRoutes`).
///
/// Finans ve Tahsilat (yine A5) ortak parçaları buradan alır: sayfalı liste durumu ve görünümü,
/// hata ekranları, belge ızgarası, yükleme, belirsiz sonuç kuralları ve sahte depo.
///
/// v4: çekirdek (görev kutusu, kabuk rozetleri) `application/`, `data/` dışa açımlarını ekledi.
library;

export 'application/approvals_providers.dart'
    show approvalsListProvider, approvalBadgeProvider, refreshApprovalCounters;
export 'approvals_routes.dart' show approvalsRoutes;
export 'data/approval_models.dart' show ApprovalRow, ApprovalScope;
export 'data/approvals_repository.dart' show ApprovalsQuery;
export 'fake/a5_fake_store.dart' show A5FakeStore;
export 'shared/action_outcome.dart';
export 'shared/attachment_grid.dart';
export 'shared/failure_view.dart';
export 'shared/layout.dart';
export 'shared/paged_list.dart';
export 'shared/paged_list_view.dart';
export 'shared/submit_retry.dart';
export 'shared/uploads.dart';
