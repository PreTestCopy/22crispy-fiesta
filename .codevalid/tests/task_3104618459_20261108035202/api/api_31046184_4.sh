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
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 from register got $CV_HTTP_STATUS" "$1"
  TOKEN=$(echo "$CV_HTTP_BODY" | jq -r '.token // empty')
  [ -n "$TOKEN" ] || cv_fail "expected token from register got none" "$1"
}

# Given
cv_step Given "a signed-in user has added a product" $LINENO
register_user $LINENO
CODE="CV-${SUFFIX}"
NAME="CV Catalog ${SUFFIX}"
DESC="Catalog description ${SUFFIX}"
PRICE=42.5
PAYLOAD=$(jq -nc --arg n "$NAME" --arg d "$DESC" --argjson p "$PRICE" --arg c "$CODE" '{name:$n,description:$d,price:$p,code:$c}')
cv_http POST /products "$PAYLOAD" -H "Authorization: Bearer $TOKEN"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 creating product got $CV_HTTP_STATUS" $LINENO
ID=$(echo "$CV_HTTP_BODY" | jq -r '.product.id // .id // empty')
[ -n "$ID" ] || cv_fail "expected product id got none" $LINENO

# When
cv_step When "a visitor who is not signed in requests the full catalog" $LINENO
cv_http GET /products
LIST_STATUS="$CV_HTTP_STATUS"; LIST_BODY="$CV_HTTP_BODY"

# Then
cv_step Then "the catalog includes the new product with name, description, price and code" $LINENO
[ "$LIST_STATUS" = "200" ] || cv_fail "expected 200 got $LIST_STATUS" $LINENO
P=$(echo "$LIST_BODY" | jq -c --arg id "$ID" '(.products // .) | map(select(.id == $id)) | .[0] // empty')
[ -n "$P" ] || cv_fail "expected product $ID in catalog got none" $LINENO
[ "$(echo "$P" | jq -r '.name')" = "$NAME" ] || cv_fail "expected name $NAME got $(echo "$P" | jq -r '.name')" $LINENO
[ "$(echo "$P" | jq -r '.description')" = "$DESC" ] || cv_fail "expected description $DESC got $(echo "$P" | jq -r '.description')" $LINENO
echo "$P" | jq -e --argjson p "$PRICE" '.price == $p' >/dev/null || cv_fail "expected price $PRICE got $(echo "$P" | jq -r '.price')" $LINENO
GOT_CODE=$(echo "$P" | jq -r '.code // .productCode // empty')
[ "$GOT_CODE" = "$CODE" ] || cv_fail "expected product code $CODE in catalog entry got '${GOT_CODE}'" $LINENO

# Cleanup
cv_step Cleanup "in-memory store; no delete endpoint exists, data is unique per run" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_31046184_4"
