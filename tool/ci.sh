#!/bin/bash
# AkaryakıtNet CI (spec C.9, D.7): bağımlılık → Türkçe harf kuralı → gizli değer → biçim → analiz → test →
# Android debug APK → iOS simülatör.
# Kullanım: bash tool/ci.sh [--no-build]
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== flutter pub get"
flutter pub get

echo "== Türkçe büyük/küçük harf kuralı (lib/ içinde toUpperCase/toLowerCase yalnızca turkish_text.dart)"
# Türkçe metinde I/İ ve ı/i yanlış dönüşür: TurkishText.upper/lower ya da asciiUpper/asciiLower kullanın.
if grep -rnE '\.to(Upper|Lower)Case\(\)' lib --include='*.dart' \
  | grep -v 'lib/core/utils/turkish_text.dart' | grep -vE ':\s*//'; then
  echo "HATA: lib/ içinde toUpperCase()/toLowerCase() bulundu (yukarıda)." >&2
  exit 1
fi

echo "== Gizli değer denetimi (env/*.json yalnızca bilinen anahtarlar)"
for f in env/*.json; do
  if grep -qiE '"[a-z_]*(api_?key|secret|password|token)[a-z_]*"' "$f"; then
    echo "HATA: $f gizli değer anahtarı içeriyor." >&2
    exit 1
  fi
done

echo "== dart format (değişiklik varsa başarısız)"
dart format --output=none --set-exit-if-changed lib test integration_test

echo "== flutter analyze"
flutter analyze

echo "== flutter test"
flutter test

if [ "${1:-}" = "--no-build" ]; then
  echo "== derleme atlandı (--no-build)"
  exit 0
fi

echo "== Android debug APK (test ortamı)"
flutter build apk --debug --dart-define-from-file=env/test.json

echo "== iOS simülatör (test ortamı)"
flutter build ios --simulator --debug --dart-define-from-file=env/test.json

echo "CI tamam."
