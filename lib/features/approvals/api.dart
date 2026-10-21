/// Approvals özelliğinin dışa açık yüzü (sahibi A5). Diğer özellikler yalnızca bu dosyayı içe aktarır;
/// özellikler arası gezinme rota yollarıyla yapılır (`AppRoutes`).
///
/// Finans ve Tahsilat (yine A5) ortak parçaları buradan alır: sayfalı liste durumu ve görünümü,
/// hata ekranları, belge ızgarası, yükleme, belirsiz sonuç kuralları ve sahte depo.
library;

export 'approvals_routes.dart' show approvalsRoutes;
export 'fake/a5_fake_store.dart' show A5FakeStore;
export 'shared/action_outcome.dart';
export 'shared/attachment_grid.dart';
export 'shared/failure_view.dart';
export 'shared/layout.dart';
export 'shared/paged_list.dart';
export 'shared/paged_list_view.dart';
export 'shared/submit_retry.dart';
export 'shared/uploads.dart';
