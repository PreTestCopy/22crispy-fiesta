#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
EMAIL="cv_${SUFFIX}@example.com"
PASSWORD="CvPassw0rd!${SUFFIX}"

register_user() {
  local body
  body=$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" --arg n "CV User $SUFFIX" '{email:$e,password:$p,name:$n}')
  cv_http POST /auth/register "$body"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 from register got $CV_HTTP_STATUS: $CV_HTTP_BODY" "$1"
  TOKEN=$(echo "$CV_HTTP_BODY" | jq -r '.token // empty')
  [ -n "$TOKEN" ] || cv_fail "expected token from register got none" "$1"
}

# create_product <name> <description> <price> <code> <line>; sets PID
create_product() {
  local body
  body=$(jq -nc --arg n "$1" --arg d "$2" --argjson p "$3" --arg c "$4" '{name:$n,description:$d,price:$p,code:$c}')
  cv_http POST /products "$body" -H "Authorization: Bearer $TOKEN"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 creating product got $CV_HTTP_STATUS: $CV_HTTP_BODY" "$5"
  PID=$(echo "$CV_HTTP_BODY" | jq -r '.product.id // .id // empty')
  [ -n "$PID" ] || cv_fail "expected product id from create got none: $CV_HTTP_BODY" "$5"
}

# Given
cv_step Given "several products with different product codes exist in the catalog" $LINENO
register_user $LINENO
create_product "CV U1 ${SUFFIX}" "u1" 1 "CVU1-${SUFFIX}" $LINENO
create_product "CV U2 ${SUFFIX}" "u2" 2 "CVU2-${SUFFIX}" $LINENO
create_product "CV U3 ${SUFFIX}" "u3" 3 "CVU3-${SUFFIX}" $LINENO

# When
cv_step When "a client views the full catalog" $LINENO
cv_http GET /products
STATUS="$CV_HTTP_STATUS"; BODY="$CV_HTTP_BODY"

# Then
cv_step Then "every product has a product code and no two share one" $LINENO
[ "$STATUS" = "200" ] || cv_fail "expected 200 for catalog got $STATUS" $LINENO
LIST=$(echo "$BODY" | jq -c '.products // .')
MISSING=$(echo "$LIST" | jq '[.[] | select(((.code // .productCode) // "") == "")] | length')
[ "$MISSING" = "0" ] || cv_fail "expected every catalog product to have a product code got $MISSING without one" $LINENO
DUPS=$(echo "$LIST" | jq -c '[.[] | (.code // .productCode)] | group_by(.) | map(select(length>1) | .[0])')
[ "$DUPS" = "[]" ] || cv_fail "expected distinct product codes got duplicates $DUPS" $LINENO

# Cleanup
cv_step Cleanup "in-memory store; no delete endpoint exists, data is unique per run" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_54405473_5"
