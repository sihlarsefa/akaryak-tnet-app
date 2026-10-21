import 'dart:io';

import 'package:akaryakitnet/features/driver/data/deliver_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory base;

  setUp(() => base = Directory.systemTemp.createTempSync('akn_files_'));
  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  test(
    'dosyalar uygulama klasörüne kopyalanır; temizlik korunanları bırakır',
    () async {
      final store = AppDriverFileStore(baseDir: () async => base);
      final src = File('${base.path}/tmp.jpg')..writeAsBytesSync([1, 2, 3]);
      final photo = await store.persistFile(src.path);
      final sig = await store.persistBytes([4, 5], extension: 'png');
      expect(photo, contains('driver_drafts'));
      expect(photo, endsWith('.jpg'));
      expect(sig, endsWith('.png'));
      expect(store.exists(photo), isTrue);
      expect(File(photo).readAsBytesSync(), [1, 2, 3]);

      await store.sweep({photo}, olderThan: Duration.zero);
      expect(store.exists(photo), isTrue, reason: 'korunan dosya kalır');
      expect(store.exists(sig), isFalse, reason: 'sahipsiz dosya silinir');

      store.deleteAll([photo, '/yok/boyle/bir/dosya.jpg']);
      expect(store.exists(photo), isFalse);
    },
  );
}
