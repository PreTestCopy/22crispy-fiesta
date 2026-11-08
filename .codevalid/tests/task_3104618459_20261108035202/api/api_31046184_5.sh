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
NAME="CV Single ${SUFFIX}"
DESC="Single description ${SUFFIX}"
PAYLOAD=$(jq -nc --arg n "$NAME" --arg d "$DESC" --arg c "CV-${SUFFIX}" '{name:$n,description:$d,price:7.25,code:$c}')
cv_http POST /products "$PAYLOAD" -H "Authorization: Bearer $TOKEN"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 creating product got $CV_HTTP_STATUS" $LINENO
ID=$(echo "$CV_HTTP_BODY" | jq -r '.product.id // .id // empty')
[ -n "$ID" ] || cv_fail "expected product id got none" $LINENO

# When
cv_step When "a visitor who is not signed in opens the product by id" $LINENO
cv_http GET "/products/$ID"
GET_STATUS="$CV_HTTP_STATUS"; GET_BODY="$CV_HTTP_BODY"

# Then
cv_step Then "the product details are returned" $LINENO
[ "$GET_STATUS" = "200" ] || cv_fail "expected 200 got $GET_STATUS" $LINENO
P=$(echo "$GET_BODY" | jq -c '.product // .')
[ "$(echo "$P" | jq -r '.id')" = "$ID" ] || cv_fail "expected id $ID got $(echo "$P" | jq -r '.id')" $LINENO
[ "$(echo "$P" | jq -r '.name')" = "$NAME" ] || cv_fail "expected name $NAME got $(echo "$P" | jq -r '.name')" $LINENO
[ "$(echo "$P" | jq -r '.description')" = "$DESC" ] || cv_fail "expected description $DESC got $(echo "$P" | jq -r '.description')" $LINENO
echo "$P" | jq -e '.price == 7.25' >/dev/null || cv_fail "expected price 7.25 got $(echo "$P" | jq -r '.price')" $LINENO

# Cleanup
cv_step Cleanup "in-memory store; no delete endpoint exists, data is unique per run" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_31046184_5"
