#!/usr/bin/env bash
set -euo pipefail
source "${CODEVALID_ROOT:-.}/.codevalid/lib/cv.sh"

BASE_URL="${BASE_URL:-http://app:6713}"
SUFFIX="$(date +%s%N)"
PASSWORD="CvPassw0rd!${SUFFIX}"

register_user() {
  local email="$1"
  local body
  body=$(jq -nc --arg e "$email" --arg p "$PASSWORD" '{email:$e,password:$p,name:"CV User"}')
  cv_http POST /auth/register "$body"
  [ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 registering $email got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
  REG_TOKEN=$(echo "$CV_HTTP_BODY" | jq -r '.token // empty')
  [ -n "$REG_TOKEN" ] || cv_fail "expected token on register got none: $CV_HTTP_BODY" $LINENO
}

# Given
cv_step Given "an owner has added a product and a second signed-in user exists" $LINENO
cv_prereq "register owner" $LINENO
register_user "cv-owner-${SUFFIX}@example.com"
OWNER_TOKEN="$REG_TOKEN"
cv_prereq "register attacker" $LINENO
register_user "cv-attacker-${SUFFIX}@example.com"
ATTACKER_TOKEN="$REG_TOKEN"

ORIG_NAME="CV Original ${SUFFIX}"
ORIG_PAYLOAD=$(jq -nc --arg n "$ORIG_NAME" --arg c "CV-ORIG-${SUFFIX}" '{name:$n,description:"original description",price:19.99,code:$c}')
cv_prereq "owner adds the original product" $LINENO
cv_http POST /products "$ORIG_PAYLOAD" -H "Authorization: Bearer $OWNER_TOKEN"
[ "$CV_HTTP_STATUS" = "201" ] || cv_fail "expected 201 creating original product got $CV_HTTP_STATUS: $CV_HTTP_BODY" $LINENO
ORIG_ID=$(echo "$CV_HTTP_BODY" | jq -r '.product.id // empty')
[ -n "$ORIG_ID" ] || cv_fail "expected product id in create response got none: $CV_HTTP_BODY" $LINENO
cv_http GET "/products/${ORIG_ID}"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 reading original product got $CV_HTTP_STATUS" $LINENO
ORIG_SNAPSHOT=$(echo "$CV_HTTP_BODY" | jq -cS '.product')

ATTACK_NAME="CV Hijack ${SUFFIX}"
ATTACK_PAYLOAD=$(jq -nc --arg id "$ORIG_ID" --arg n "$ATTACK_NAME" --arg c "CV-HIJACK-${SUFFIX}" \
  '{id:$id,name:$n,description:"hijacked description",price:0.01,code:$c}')

# When
cv_step When "the second user adds a product supplying the existing product's identifier" $LINENO
cv_http POST /products "$ATTACK_PAYLOAD" -H "Authorization: Bearer $ATTACKER_TOKEN"
ATTACK_STATUS="$CV_HTTP_STATUS"; ATTACK_BODY="$CV_HTTP_BODY"

# Then
cv_step Then "the existing product is unchanged and the new product did not take its identifier" $LINENO
case "$ATTACK_STATUS" in
  2*)
    NEW_ID=$(echo "$ATTACK_BODY" | jq -r '.product.id // empty')
    [ "$NEW_ID" != "$ORIG_ID" ] || cv_fail "expected new product to get a server-assigned id got the supplied existing id $ORIG_ID" $LINENO
    ;;
esac
cv_http GET "/products/${ORIG_ID}"
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 reading original product after attempt got $CV_HTTP_STATUS" $LINENO
AFTER_SNAPSHOT=$(echo "$CV_HTTP_BODY" | jq -cS '.product')
[ "$AFTER_SNAPSHOT" = "$ORIG_SNAPSHOT" ] || cv_fail "expected original product unchanged ($ORIG_SNAPSHOT) got $AFTER_SNAPSHOT" $LINENO
cv_http GET /products
[ "$CV_HTTP_STATUS" = "200" ] || cv_fail "expected 200 listing catalog got $CV_HTTP_STATUS" $LINENO
SAME_ID=$(echo "$CV_HTTP_BODY" | jq --arg id "$ORIG_ID" '[(.products // .)[] | select(.id == $id)] | length')
[ "$SAME_ID" = "1" ] || cv_fail "expected exactly one catalog entry with id $ORIG_ID got $SAME_ID" $LINENO
HIJACK_AT_ID=$(echo "$CV_HTTP_BODY" | jq --arg id "$ORIG_ID" --arg n "$ATTACK_NAME" '[(.products // .)[] | select(.id == $id and .name == $n)] | length')
[ "$HIJACK_AT_ID" = "0" ] || cv_fail "expected attacker product not stored under id $ORIG_ID got $HIJACK_AT_ID" $LINENO

# Cleanup
cv_step Cleanup "products are kept in memory only and the app has no delete route; nothing to remove" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_31046184_9"
