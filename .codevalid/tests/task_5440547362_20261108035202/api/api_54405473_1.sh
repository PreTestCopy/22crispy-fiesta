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
cv_step Given "two products exist in the catalog (added by a registered user)" $LINENO
register_user $LINENO
N1="CV Cat A ${SUFFIX}"; D1="Desc A ${SUFFIX}"; P1=12.5; C1="CVA-${SUFFIX}"
N2="CV Cat B ${SUFFIX}"; D2="Desc B ${SUFFIX}"; P2=7; C2="CVB-${SUFFIX}"
create_product "$N1" "$D1" "$P1" "$C1" $LINENO; ID1="$PID"
create_product "$N2" "$D2" "$P2" "$C2" $LINENO; ID2="$PID"

# When
cv_step When "an anonymous client requests the catalog without any token" $LINENO
cv_http GET /products
STATUS="$CV_HTTP_STATUS"; BODY="$CV_HTTP_BODY"

# Then
cv_step Then "the full catalog is returned with name, description, price and product code for each product" $LINENO
[ "$STATUS" = "200" ] || cv_fail "expected 200 for anonymous catalog got $STATUS: $BODY" $LINENO
LIST=$(echo "$BODY" | jq -c '.products // .')
echo "$LIST" | jq -e 'type=="array"' >/dev/null || cv_fail "expected an array of products got $BODY" $LINENO
for spec in "$ID1|$N1|$D1|$P1|$C1" "$ID2|$N2|$D2|$P2|$C2"; do
  IFS='|' read -r id n d p c <<<"$spec"
  P=$(echo "$LIST" | jq -c --arg id "$id" 'map(select(.id==$id)) | .[0] // empty')
  [ -n "$P" ] || cv_fail "expected product $id in anonymous catalog got none" $LINENO
  [ "$(echo "$P" | jq -r '.name')" = "$n" ] || cv_fail "expected name $n got $(echo "$P" | jq -r '.name')" $LINENO
  [ "$(echo "$P" | jq -r '.description')" = "$d" ] || cv_fail "expected description $d got $(echo "$P" | jq -r '.description')" $LINENO
  echo "$P" | jq -e --argjson p "$p" '.price == $p' >/dev/null || cv_fail "expected price $p got $(echo "$P" | jq -r '.price')" $LINENO
  GOT=$(echo "$P" | jq -r '.code // .productCode // empty')
  [ "$GOT" = "$c" ] || cv_fail "expected product code $c in catalog entry got '${GOT}': $P" $LINENO
done
TOTAL=$(echo "$LIST" | jq 'length')
echo "catalog contains $TOTAL products"

# Cleanup
cv_step Cleanup "in-memory store; no delete endpoint exists, data is unique per run" $LINENO
echo "CODEVALID_TEST_ASSERTION_OK:api_54405473_1"
