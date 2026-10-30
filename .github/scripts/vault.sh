#!/usr/bin/env bash
# خزنة أسرار Tomo داخل قاعدة بياناته (جدول private_settings — لا يقرؤه إلا مفتاح الخدمة)
# يحتاج: SUPABASE_ACCESS_TOKEN · REF
#   vault.sh get <key>            ⇐ يطبع القيمة (JSON)
#   vault.sh put <key> <json>     ⇐ يحفظ
set -euo pipefail
: "${SUPABASE_ACCESS_TOKEN:?}" "${REF:?}"
URL="https://$REF.supabase.co"
SRK=$(curl -sf "https://api.supabase.com/v1/projects/$REF/api-keys?reveal=true" -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  | jq -r '[.[] | select(.name=="service_role" or .type=="secret")][0].api_key')
[ -n "$SRK" ] && [ "$SRK" != "null" ] || { echo "::error::تعذّر جلب مفتاح الخدمة" >&2; exit 1; }
echo "::add-mask::$SRK" >&2
H=(-H "apikey: $SRK" -H "Authorization: Bearer $SRK" -H "Content-Type: application/json")
case "$1" in
  get) curl -sf "$URL/rest/v1/private_settings?select=value&key=eq.$2" "${H[@]}" | jq -c '.[0].value // empty' ;;
  put) jq -n --arg k "$2" --argjson v "$3" '{key:$k, value:$v}' \
         | curl -sf -X POST "$URL/rest/v1/private_settings?on_conflict=key" "${H[@]}" -H "Prefer: resolution=merge-duplicates,return=minimal" -d @- ;;
esac
