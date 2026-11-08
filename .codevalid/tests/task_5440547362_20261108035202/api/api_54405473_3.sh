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
cv_step Given "a signed-in user, a product in the catalog, and the anonymous view of catalog and product" $LINENO
register_user $LINENO
create_product "CV Same ${SUFFIX}" "Same desc ${SUFFIX}" 3.3 "CVS-${SUFFIX}" $LINENO; ID="$PID"
cv_prereq "anonymous view of catalog and product" $LINENO
cv_http GET /products
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 for anonymous catalog got $CV_HTTP_STATUS" $LINENO
ANON_CAT=$(echo "$CV_HTTP_BODY" | jq -S -c '(.products // .) | sort_by(.id)')
cv_http GET "/products/$ID"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 for anonymous product got $CV_HTTP_STATUS" $LINENO
ANON_P=$(echo "$CV_HTTP_BODY" | jq -S -c '.product // .')

# When
cv_step When "the signed-in user views the catalog and opens the product" $LINENO
cv_http GET /products -H "Authorization: Bearer $TOKEN"
CAT_STATUS="$CV_HTTP_STATUS"; CAT_BODY="$CV_HTTP_BODY"
cv_http GET "/products/$ID" -H "Authorization: Bearer $TOKEN"
P_STATUS="$CV_HTTP_STATUS"; P_BODY="$CV_HTTP_BODY"

# Then
cv_step Then "signed-in responses equal the anonymous ones" $LINENO
[ "$CAT_STATUS" = "200" ] || cv_fail "expected 200 for signed-in catalog got $CAT_STATUS" $LINENO
[ "$P_STATUS" = "200" ] || cv_fail "expected 200 for signed-in product got $P_STATUS" $LINENO
AUTH_CAT=$(echo "$CAT_BODY" | jq -S -c '(.products // .) | sort_by(.id)')
AUTH_P=$(echo "$P_BODY" | jq -S -c '.product // .')
[ "$AUTH_CAT" = "$ANON_CAT" ] || cv_fail "expected signed-in catalog to equal anonymous catalog got differing results" $LINENO
[ "$AUTH_P" = "$ANON_P" ] || cv_fail "expected signed-in product $AUTH_P to equal anonymous $ANON_P" $LINENO

# Cleanup
cv_step Cleanup "in-memory store; no delete endpoint exists, data is unique per run" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_54405473_3"
