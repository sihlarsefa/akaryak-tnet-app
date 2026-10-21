#!/bin/bash
# Canlı test sunucusu salt-okunur duman testi (spec D.3 A-INT). Yazan istek yok: sipariş, teslim, karar
# GÖNDERMEZ. Yalnızca demo/inceleme kiracısıyla kullanın (test sunucusu canlı veritabanıdır).
#
#   bash tool/live_smoke.sh [API_KÖKÜ]                     # varsayılan env/test.json API_BASE_URL
#   AKN_SMOKE_USER=inceleme.musteri AKN_SMOKE_PASSWORD=... bash tool/live_smoke.sh   # + giriş ve listeler
#
# Şifre yalnızca ortam değişkeninden okunur; dosyaya ve çıktıya yazılmaz. Yeni uçlar (mobil v1) henüz
# dağıtılmadıysa 404 "beklenen" sayılır (eski sürüm), betik yine 0 döner; `--strict` ile 404 hatadır.
set -uo pipefail
cd "$(dirname "$0")/.."

STRICT=0
API=""
for a in "$@"; do
  case "$a" in
    --strict) STRICT=1 ;;
    *) API="$a" ;;
  esac
done
if [ -z "$API" ]; then
  API=$(python3 -c "import json;print(json.load(open('env/test.json'))['API_BASE_URL'])")
fi
API="${API%/}"
FAIL=0
pass() { printf '  ✓ %s\n' "$1"; }
warn() { printf '  ~ %s\n' "$1"; [ "$STRICT" = 1 ] && FAIL=1; }
fail() { printf '  ✗ %s\n' "$1"; FAIL=1; }

code() { curl -s -o /tmp/akn_smoke_body.$$ -w '%{http_code}' --max-time 20 "$@"; }
body() { cat /tmp/akn_smoke_body.$$; }
trap 'rm -f /tmp/akn_smoke_body.$$' EXIT

echo "== $API"
c=$(code "$API/swagger/index.html"); [ "$c" = 200 ] && pass "swagger 200" || warn "swagger $c (Swagger:Enabled kapalı olabilir)"

c=$(code "$API/health/live")
if [ "$c" = 200 ]; then pass "health/live 200"; else warn "health/live $c (eski sürüm: mobil API dağıtılmamış)"; fi

c=$(code "$API/health/ready")
if [ "$c" = 200 ] || [ "$c" = 503 ]; then
  body | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  · build', d.get('build'), '· contract', d.get('contract'), '· status', d.get('status'))
print('  · flags', {k: v for k, v in (d.get('flags') or {}).items()})
sys.exit(0 if d.get('contract') == 'mobile-v1' else 3)
" && pass "health/ready sözleşme mobile-v1" || fail "health/ready sözleşme farklı"
else
  warn "health/ready $c"
fi

for p in ios android; do
  c=$(code "$API/api/v1/app/config?platform=$p")
  if [ "$c" = 200 ]; then
    body | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('contractVersion') in (None, 'mobile-v1'), d.get('contractVersion')
m=d.get('maintenance') or {}
print('  · minBuild', d.get('minBuild'), 'latestBuild', d.get('latestBuild'), 'bakım', m.get('active'), 'özellikler', d.get('features'))
" && pass "app/config ($p)" || fail "app/config ($p) sözleşme uyumsuz"
  else
    warn "app/config ($p) $c → uygulama 'Sunucu güncel değil' gösterir"
  fi
done

for doc in privacy kvkk terms support account-deletion ai; do
  c=$(code "$API/legal/$doc")
  [ "$c" = 200 ] && pass "legal/$doc" || warn "legal/$doc $c"
done

if [ -n "${AKN_SMOKE_USER:-}" ] && [ -n "${AKN_SMOKE_PASSWORD:-}" ]; then
  echo "== giriş: $AKN_SMOKE_USER"
  DEV=$(python3 -c "import uuid;print(uuid.uuid4())")
  payload=$(python3 -c "
import json,os
print(json.dumps({'userNameOrEmail': os.environ['AKN_SMOKE_USER'], 'password': os.environ['AKN_SMOKE_PASSWORD'],
  'device': {'deviceId': '$DEV', 'platform': 'ios', 'model': 'smoke', 'osVersion': 'smoke', 'appVersion': '1.0.0', 'appBuild': 1}}))")
  c=$(code -X POST -H 'Content-Type: application/json' -H "X-Device-Id: $DEV" -H 'X-App-Platform: ios' -H 'X-App-Build: 1' \
    --data "$payload" "$API/api/v1/auth/login")
  if [ "$c" = 200 ]; then
    TOKEN=$(body | python3 -c "import json,sys;d=json.load(sys.stdin);t=d.get('tokens') or {};print(t.get('accessToken',''))")
    if [ -z "$TOKEN" ]; then warn "giriş 2FA istedi (kod gerektirir; atlandı)"; else
      pass "auth/login"
      H=(-H "Authorization: Bearer $TOKEN" -H "X-Device-Id: $DEV" -H 'X-App-Platform: ios' -H 'X-App-Build: 1')
      c=$(code "${H[@]}" "$API/api/v1/me/access"); [ "$c" = 200 ] && pass "me/access" || fail "me/access $c"
      persona=$(body | python3 -c "import json,sys;print(json.load(sys.stdin).get('persona',''))" 2>/dev/null)
      echo "  · persona: $persona"
      if [ "$persona" = customer ]; then
        list="home/customer customers/me/orders?segment=active notifications approvals/badge"
      else
        list="home/bayi bayi/orders?page=1 bayi/quote-desk notifications driver/shipments"
      fi
      for p in $list; do
        c=$(code "${H[@]}" "$API/api/v1/$p"); { [ "$c" = 200 ] || [ "$c" = 403 ]; } && pass "$p $c" || fail "$p $c"
      done
      # Oturumu kapat (yenileme belirtecini iptal eder).
      code -X POST "${H[@]}" -H 'Content-Type: application/json' --data '{"allDevices":false}' "$API/api/v1/auth/logout" >/dev/null
    fi
  else
    warn "auth/login $c"
  fi
else
  echo "== giriş atlandı (AKN_SMOKE_USER / AKN_SMOKE_PASSWORD yok)"
fi

[ "$FAIL" = 0 ] && echo "SONUÇ: tamam" || echo "SONUÇ: hata var"
exit $FAIL
