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
cv_step Given "a registered, signed-in user and a fresh product code" $LINENO
register_user $LINENO
CODE="CV-${SUFFIX}"
NAME="CV Product ${SUFFIX}"
DESC="Description ${SUFFIX}"
PRICE=19.99
PAYLOAD=$(jq -nc --arg n "$NAME" --arg d "$DESC" --argjson p "$PRICE" --arg c "$CODE" '{name:$n,description:$d,price:$p,code:$c}')

# When
cv_step When "the signed-in user adds the product" $LINENO
cv_http POST /products "$PAYLOAD" -H "Authorization: Bearer $TOKEN"
CREATE_STATUS="$CV_HTTP_STATUS"; CREATE_BODY="$CV_HTTP_BODY"

# Then
cv_step Then "the product is stored with an id and returned details match the submitted fields" $LINENO
[ "$CREATE_STATUS" = "201" ] || cv_fail "expected 201 got $CREATE_STATUS: $CREATE_BODY" $LINENO
P=$(echo "$CREATE_BODY" | jq -c '.product // .')
ID=$(echo "$P" | jq -r '.id // empty')
[ -n "$ID" ] || cv_fail "expected product id got none: $CREATE_BODY" $LINENO
[ "$(echo "$P" | jq -r '.name')" = "$NAME" ] || cv_fail "expected name $NAME got $(echo "$P" | jq -r '.name')" $LINENO
[ "$(echo "$P" | jq -r '.description')" = "$DESC" ] || cv_fail "expected description $DESC got $(echo "$P" | jq -r '.description')" $LINENO
echo "$P" | jq -e --argjson p "$PRICE" '.price == $p' >/dev/null || cv_fail "expected price $PRICE got $(echo "$P" | jq -r '.price')" $LINENO
GOT_CODE=$(echo "$P" | jq -r '.code // .productCode // empty')
[ "$GOT_CODE" = "$CODE" ] || cv_fail "expected product code $CODE in returned product got '${GOT_CODE}'" $LINENO
cv_http GET "/products/$ID"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected stored product readable (200) got $CV_HTTP_STATUS" $LINENO
STORED_CODE=$(echo "$CV_HTTP_BODY" | jq -r '.product.code // .product.productCode // empty')
[ "$STORED_CODE" = "$CODE" ] || cv_fail "expected stored product code $CODE got '${STORED_CODE}'" $LINENO

# Cleanup
cv_step Cleanup "in-memory store; no delete endpoint exists, data is unique per run" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_31046184_1"
