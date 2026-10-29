import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/models/enums.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/routing/route_access.dart';
import '../../approvals/api.dart';

/// Onay talebinin konu türleri (`FinanceSubjectTypes`; satırın `subjectType` alanı).
abstract final class ApprovalSubjects {
  /// Sipariş finans onayı (`subjectId` = sipariş).
  static const order = 'Order';

  /// Yeni cari finans onayı (`subjectId` = StationCustomer, finans kartının kimliği).
  static const stationCustomer = 'StationCustomer';

  /// Ön kayıt finans onayı (`subjectId` = ön kayıt).
  static const customerLead = 'CustomerLead';
}

/// Bende'deki bir türün talepleri, konu kimliğine göre ([myApprovalsBySubjectProvider]).
@immutable
class MyApprovals {
  const MyApprovals(this.bySubject, {this.total = 0, this.complete = true});

  /// Onaylar'ı açamayan ya da listesi yüklenemeyen izleyen: hiçbiri onun sırası değil.
  static const none = MyApprovals({});

  /// Konu kimliği → talep (Bende'nin okunan sayfası).
  final Map<int, ApprovalRow> bySubject;

  /// Bu türde Bende'deki talep sayısı (sunucunun toplamı; bant durumu bununla konuşur).
  final int total;

  /// Bende'nin bu türdeki tamamı okundu: burada olmayan konu izleyenin sırası değil.
  final bool complete;

  ApprovalRow? operator [](int subjectId) => bySubject[subjectId];
}

/// Onaylar › Bende'deki açık talepler, konusuna göre (v4 P3: "sıra sizde" diyen satır kararın
/// verildiği sayfayı doğrudan açar). Anahtar: talep türü ve konu türü ([ApprovalSubjects]). Bende =
/// izleyenin karar vereceği ya da yanıtlayacağı talepler (Onaylar rozetiyle aynı sayım); yalnızca bu
/// satırlar izleyenin sırasıdır.
///
/// * İzleyen Onaylar'ı açamıyorsa [MyApprovals.none] (sıra onda değil; istek atılmaz).
/// * Liste yüklenirken null (çağıran beklerken iyimser davranabilir); yüklenemezse
///   [MyApprovals.none].
/// * Bende'nin ilk sayfası (25 satır) okunur; devamı varsa [MyApprovals.complete] false olur ve
///   çağıran bulamadığı talep için Onaylar'ı ([approvalsOfType]) açar.
final myApprovalsBySubjectProvider = Provider.autoDispose
    .family<MyApprovals?, ({ApprovalType type, String subject})>((ref, key) {
      final policy = ref.watch(accessPolicyProvider);
      final features = ref.watch(appConfigProvider.select((c) => c.features));
      if (!policy.isSignedIn ||
          !RouteAccess.isAllowed(AppRoutes.approvals, policy, features)) {
        return MyApprovals.none;
      }
      final s = ref.watch(
        approvalsListProvider(
          ApprovalsQuery(scope: ApprovalScope.toMe, type: key.type),
        ),
      );
      if (!s.hasData) return s.error == null ? null : MyApprovals.none;
      return MyApprovals(
        {
          for (final a in s.items)
            if (a.type == key.type &&
                a.subjectType == key.subject &&
                a.status.isOpen)
              a.subjectId: a,
        },
        total: s.totalCount,
        complete: !s.hasMore,
      );
    });

/// Yeni cari finans onayları (finans kartı ve listesi): konu StationCustomer = kartın kimliği.
const onboardingApprovals = (
  type: ApprovalType.customerOnboarding,
  subject: ApprovalSubjects.stationCustomer,
);

/// Sipariş finans onayları (bayi sipariş listesi ve ayrıntısı): konu sipariştir.
const orderFinanceApprovals = (
  type: ApprovalType.orderFinance,
  subject: ApprovalSubjects.order,
);

/// Ön kayıt finans onayları (saha ana sayfası: temsilciden bilgi istenen talep).
const leadFinanceApprovals = (
  type: ApprovalType.leadFinance,
  subject: ApprovalSubjects.customerLead,
);

/// Onaylar'ın bir türe süzülmüş hâli (`/approvals?type=6`): talep Bende'nin okunan sayfasında
/// bulunamadığında "Karar ver"in gittiği yer.
String approvalsOfType(ApprovalType type) =>
    '${AppRoutes.approvals}?type=${type.code}';
