#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"

# Given
cv_step Given "a visitor with no token and a complete product payload" $LINENO
NAME="CV Anon ${SUFFIX}"
PAYLOAD=$(jq -nc --arg n "$NAME" --arg c "CV-ANON-${SUFFIX}" '{name:$n,description:"anon attempt",price:3,code:$c}')
cv_http GET /products
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 listing catalog got $CV_HTTP_STATUS" $LINENO

# When
cv_step When "the visitor tries to add the product without signing in" $LINENO
cv_http POST /products "$PAYLOAD"
CREATE_STATUS="$CV_HTTP_STATUS"; CREATE_BODY="$CV_HTTP_BODY"

# Then
cv_step Then "the product is not added and does not appear in the catalog" $LINENO
case "$CREATE_STATUS" in 2*) cv_fail "expected unauthenticated create refused got $CREATE_STATUS: $CREATE_BODY" $LINENO ;; esac
cv_http GET /products
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 listing catalog got $CV_HTTP_STATUS" $LINENO
N=$(echo "$CV_HTTP_BODY" | jq --arg n "$NAME" '[(.products // .)[] | select(.name == $n)] | length')
[ "$N" = "0" ] || cv_fail "expected anonymous product absent from catalog got $N entries" $LINENO

# Cleanup
cv_step Cleanup "nothing was created" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_31046184_8"
