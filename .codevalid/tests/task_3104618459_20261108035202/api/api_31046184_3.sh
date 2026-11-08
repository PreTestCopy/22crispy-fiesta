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
cv_step Given "a signed-in user has added a product with code X" $LINENO
register_user $LINENO
CODE="CV-DUP-${SUFFIX}"
NAME1="CV First ${SUFFIX}"
NAME2="CV Second ${SUFFIX}"
P1=$(jq -nc --arg n "$NAME1" --arg c "$CODE" '{name:$n,description:"first",price:10,code:$c}')
cv_http POST /products "$P1" -H "Authorization: Bearer $TOKEN"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 creating first product got $CV_HTTP_STATUS" $LINENO
ID1=$(echo "$CV_HTTP_BODY" | jq -r '.product.id // .id // empty')
[ -n "$ID1" ] || cv_fail "expected first product id got none" $LINENO
P2=$(jq -nc --arg n "$NAME2" --arg c "$CODE" '{name:$n,description:"second",price:20,code:$c}')

# When
cv_step When "the user adds another product with the same code X" $LINENO
cv_http POST /products "$P2" -H "Authorization: Bearer $TOKEN"
DUP_STATUS="$CV_HTTP_STATUS"; DUP_BODY="$CV_HTTP_BODY"

# Then
cv_step Then "the second product is refused and only the first, unchanged, holds code X" $LINENO
case "$DUP_STATUS" in 2*) cv_fail "expected duplicate code refused (4xx) got $DUP_STATUS: $DUP_BODY" $LINENO ;; esac
cv_http GET /products
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 listing catalog got $CV_HTTP_STATUS" $LINENO
N2=$(echo "$CV_HTTP_BODY" | jq --arg n "$NAME2" '[(.products // .)[] | select(.name == $n)] | length')
[ "$N2" = "0" ] || cv_fail "expected second product absent from catalog got $N2 entries" $LINENO
F=$(echo "$CV_HTTP_BODY" | jq -c --arg id "$ID1" '[(.products // .)[] | select(.id == $id)][0] // empty')
[ -n "$F" ] || cv_fail "expected first product $ID1 still in catalog got none" $LINENO
echo "$F" | jq -e --arg n "$NAME1" '.name == $n and .description == "first" and .price == 10' >/dev/null \
  || cv_fail "expected first product unchanged got $F" $LINENO

# Cleanup
cv_step Cleanup "in-memory store; no delete endpoint exists, data is unique per run" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_31046184_3"
