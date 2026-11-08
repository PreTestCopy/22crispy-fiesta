#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"

# Given
cv_step Given "an identifier that belongs to no product" $LINENO
UNKNOWN_ID="00000000-0000-4000-8000-$(printf '%012d' "$(( $(date +%s) % 1000000000000 ))")"
cv_http GET /products
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 listing catalog got $CV_HTTP_STATUS" $LINENO
N=$(echo "$CV_HTTP_BODY" | jq --arg id "$UNKNOWN_ID" '[(.products // .)[] | select(.id == $id)] | length')
[ "$N" = "0" ] || cv_fail "expected unknown id absent from catalog got $N" $LINENO

# When
cv_step When "a visitor opens the product by the unknown id" $LINENO
cv_http GET "/products/$UNKNOWN_ID"
GET_STATUS="$CV_HTTP_STATUS"; GET_BODY="$CV_HTTP_BODY"

# Then
cv_step Then "no product details are returned" $LINENO
case "$GET_STATUS" in 2*) cv_fail "expected not-found for unknown id got $GET_STATUS: $GET_BODY" $LINENO ;; esac
HAS=$(echo "$GET_BODY" | jq -r 'if type == "object" and (.product // null) != null then "yes" else "no" end' 2>/dev/null || echo no)
[ "$HAS" = "no" ] || cv_fail "expected no product details got $GET_BODY" $LINENO

# Cleanup
cv_step Cleanup "nothing was created" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_31046184_6"
