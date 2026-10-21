#!/usr/bin/env bash
# Sunucunun ürettiği sözleşme örneklerini (arka uç `MobileContractSamplesTests`, B-INT) uygulamaya kopyalar.
#
#   tool/sync_contract_samples.sh [kaynak-klasör]
#
# Varsayılan kaynak: ../AkaryakıtNet/artifacts/contract-samples. Arka uçta örnekleri yazmak için:
#   AKN_WRITE_CONTRACT_SAMPLES=1 dotnet test --filter MobileContractSamplesTests
# Sonra `flutter test test/contract/`: index.json'daki her dosyanın bir okuyucusu olmalı
# (test/contract/contract_samples_test.dart → _serverParsers); değerler değiştiyse denetimleri güncelleyin.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
src="${1:-$here/../AkaryakıtNet/artifacts/contract-samples}"
dst="$here/test/contract/server"
if [ ! -f "$src/index.json" ]; then
  echo "index.json bulunamadı: $src" >&2
  exit 1
fi
mkdir -p "$dst"
rm -f "$dst"/*.json
cp "$src"/*.json "$dst"/
echo "$(find "$dst" -name '*.json' | wc -l | tr -d ' ') dosya kopyalandı: $dst"
