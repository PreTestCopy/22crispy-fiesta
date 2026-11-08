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
cv_step Given "a product exists in the catalog (added by a registered user)" $LINENO
register_user $LINENO
N="CV Item ${SUFFIX}"; DS="Item desc ${SUFFIX}"; PR=42.75; CODE="CVI-${SUFFIX}"
create_product "$N" "$DS" "$PR" "$CODE" $LINENO; ID="$PID"

# When
cv_step When "an anonymous client opens the product by its identifier" $LINENO
cv_http GET "/products/$ID"
STATUS="$CV_HTTP_STATUS"; BODY="$CV_HTTP_BODY"

# Then
cv_step Then "the product details are returned and match the catalog entry" $LINENO
[ "$STATUS" = "200" ] || cv_fail "expected 200 for anonymous product view got $STATUS: $BODY" $LINENO
P=$(echo "$BODY" | jq -c '.product // .')
[ "$(echo "$P" | jq -r '.id')" = "$ID" ] || cv_fail "expected id $ID got $(echo "$P" | jq -r '.id')" $LINENO
[ "$(echo "$P" | jq -r '.name')" = "$N" ] || cv_fail "expected name $N got $(echo "$P" | jq -r '.name')" $LINENO
[ "$(echo "$P" | jq -r '.description')" = "$DS" ] || cv_fail "expected description $DS got $(echo "$P" | jq -r '.description')" $LINENO
echo "$P" | jq -e --argjson p "$PR" '.price == $p' >/dev/null || cv_fail "expected price $PR got $(echo "$P" | jq -r '.price')" $LINENO
GOT=$(echo "$P" | jq -r '.code // .productCode // empty')
[ "$GOT" = "$CODE" ] || cv_fail "expected product code $CODE in product details got '${GOT}': $P" $LINENO
cv_http GET /products
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 for catalog got $CV_HTTP_STATUS" $LINENO
CAT=$(echo "$CV_HTTP_BODY" | jq -c --arg id "$ID" '(.products // .) | map(select(.id==$id)) | .[0] // empty')
[ -n "$CAT" ] || cv_fail "expected product $ID in catalog got none" $LINENO
[ "$(echo "$CAT" | jq -S -c .)" = "$(echo "$P" | jq -S -c .)" ] || cv_fail "expected product details to match catalog entry got detail=$P catalog=$CAT" $LINENO

# Cleanup
cv_step Cleanup "in-memory store; no delete endpoint exists, data is unique per run" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_54405473_2"
