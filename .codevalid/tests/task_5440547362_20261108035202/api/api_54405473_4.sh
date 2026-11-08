#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"

# Given
cv_step Given "an identifier that matches no product in the catalog" $LINENO
UNKNOWN_ID="00000000-0000-4000-8000-${SUFFIX: -12}"
cv_http GET /products
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 for catalog got $CV_HTTP_STATUS" $LINENO
echo "$CV_HTTP_BODY" | jq -e --arg id "$UNKNOWN_ID" '(.products // .) | map(select(.id==$id)) | length == 0' >/dev/null \
  || cv_fail "expected identifier $UNKNOWN_ID to be unused but it exists" $LINENO

# When
cv_step When "a client opens a product with the unknown identifier" $LINENO
cv_http GET "/products/$UNKNOWN_ID"
STATUS="$CV_HTTP_STATUS"; BODY="$CV_HTTP_BODY"

# Then
cv_step Then "the client is told the product was not found and no details are returned" $LINENO
[ "$STATUS" = "404" ] || cv_fail "expected 404 not found got $STATUS: $BODY" $LINENO
echo "$BODY" | jq -e '(.product // null) == null and (has("name") | not) and (has("price") | not)' >/dev/null 2>&1 \
  || cv_fail "expected no product details in body got $BODY" $LINENO

# Cleanup
cv_step Cleanup "nothing was created" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_54405473_4"
