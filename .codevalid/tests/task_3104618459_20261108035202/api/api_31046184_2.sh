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
cv_step Given "a signed-in user and a product payload missing the product code" $LINENO
register_user $LINENO
NAME="CV NoCode ${SUFFIX}"
PAYLOAD=$(jq -nc --arg n "$NAME" --arg d "Missing code ${SUFFIX}" '{name:$n,description:$d,price:5}')

# When
cv_step When "the user tries to add the product without a product code" $LINENO
cv_http POST /products "$PAYLOAD" -H "Authorization: Bearer $TOKEN"
CREATE_STATUS="$CV_HTTP_STATUS"; CREATE_BODY="$CV_HTTP_BODY"

# Then
cv_step Then "the product is refused and not in the catalog" $LINENO
case "$CREATE_STATUS" in 2*) cv_fail "expected refusal (4xx) for product without code got $CREATE_STATUS: $CREATE_BODY" $LINENO ;; esac
cv_http GET /products
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 listing catalog got $CV_HTTP_STATUS" $LINENO
N=$(echo "$CV_HTTP_BODY" | jq --arg n "$NAME" '[(.products // .)[] | select(.name == $n)] | length')
[ "$N" = "0" ] || cv_fail "expected product without code absent from catalog got $N entries" $LINENO

# Cleanup
cv_step Cleanup "in-memory store; no delete endpoint exists, data is unique per run" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_31046184_2"
