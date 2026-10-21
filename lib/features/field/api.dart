/// Saha özelliği (sahibi A6). Diğer özellikler yalnızca bu dosyayı içe aktarır.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/offline/outbox_runner.dart';
import 'data/field_outbox.dart';

export 'field_routes.dart' show fieldRoutes;
export 'presentation/field_home.dart' show FieldHome;

/// Saha bekleyen işlem işleyicileri: `field.saveDraft`, `lead.saveDraft`, `lead.upload` (spec C.4).
/// Uygulama katmanı bunları `outboxHandlersProvider` içine ekler.
Map<String, OutboxHandler> fieldOutboxHandlers(Ref ref) =>
    buildFieldOutboxHandlers();
