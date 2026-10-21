import 'package:go_router/go_router.dart';

import 'design_gallery.dart';

export 'design_gallery.dart' show DesignGalleryPage;

/// Path of the design gallery (dev environment only).
const String kDesignGalleryPath = '/dev/gallery';

/// The `/dev/gallery` route. Register it only in the dev environment:
///
/// ```dart
/// routes: [
///   ...,
///   if (env.env == AknEnv.dev) designGalleryRoute(),
/// ],
/// ```
GoRoute designGalleryRoute() => GoRoute(
  path: kDesignGalleryPath,
  builder: (context, state) => const DesignGalleryPage(),
);
