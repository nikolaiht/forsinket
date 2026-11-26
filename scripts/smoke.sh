#!/usr/bin/env bash
#
# Walks two claims through the running app, from the outside, the way the Elm
# app does: one the rules settle on their own, and one that goes to an officer
# and is paid out. Needs curl and jq.
#
#   ./scripts/smoke.sh [base-url]        default: http://localhost:8080

set -euo pipefail

BASE="${1:-http://localhost:8080}"

step() { printf '%s\n' "- $1"; }

get() { curl --fail --silent --show-error "$BASE$1"; }

post() {
  curl --fail --silent --show-error --header 'Content-Type: application/json' --data "$2" "$BASE$1"
}

# The HTTP status of a POST that is expected to be refused.
status_of_post() {
  curl --silent --output /dev/null --write-out '%{http_code}' \
    --header 'Content-Type: application/json' --data "$2" "$BASE$1"
}

days_ago() { date -u -d "$1 days ago" +%F 2>/dev/null || date -u -v "-${1}d" +%F; }

step "the service is up"
get /health | jq --exit-status '.status == "ok"' > /dev/null

step "the web app is served, also for an address deep inside it"
get / | grep --quiet 'Elm.Main.init'
get /krav/nytt | grep --quiet 'Elm.Main.init'

step "the rules and the demo claims are there"
get /api/rules | jq --exit-status '.version == "v1"' > /dev/null
get /api/claims | jq --exit-status 'length >= 6' > /dev/null

step "a departure at least an hour late, some day in the last week"
DEPARTURE=""
for day in 1 2 3 4 5 6 7; do
  DEPARTURE=$(get "/api/departures?date=$(days_ago "$day")" |
    jq --raw-output 'map(select(.outcome.type == "ran" and .outcome.delayMinutes >= 60)) | .[0].id // empty')
  [ -n "$DEPARTURE" ] && break
done
[ -n "$DEPARTURE" ] || { echo "no late departure found" >&2; exit 1; }
echo "  $DEPARTURE"

step "a claim without expenses is approved by the rules"
post /api/claims "{\"departureId\":\"$DEPARTURE\",\"ticket\":{\"type\":\"single\",\"price\":34900},\"expenses\":null}" |
  jq --exit-status '.status.type == "approved" and .status.by.type == "rules" and .version == 2' > /dev/null

step "a claim with expenses waits for an officer"
CLAIM=$(post /api/claims "{\"departureId\":\"$DEPARTURE\",\"ticket\":{\"type\":\"single\",\"price\":34900},\"expenses\":{\"amount\":62000,\"kind\":\"taxi\"}}")
echo "$CLAIM" | jq --exit-status '.status.type == "awaiting_review" and .status.calculation.expenses.type == "pending_review"' > /dev/null
ID=$(echo "$CLAIM" | jq --raw-output '.id')
TICKET_COMPENSATION=$(echo "$CLAIM" | jq '.status.calculation.ticketCompensation')

step "an officer cannot cover more than the rules allow"
[ "$(status_of_post "/api/claims/$ID/decision" '{"expectedVersion":2,"officer":"CI","note":"","decision":{"type":"approve","approvedExpenses":62001}}')" = "422" ]

step "the officer covers 500 kr, and the sum follows"
post "/api/claims/$ID/decision" '{"expectedVersion":2,"officer":"CI","note":"Kvitteringen viser 500 kr.","decision":{"type":"approve","approvedExpenses":50000}}' |
  jq --exit-status --argjson ticket "$TICKET_COMPENSATION" \
    '.status.type == "approved" and .status.calculation.total == $ticket + 50000' > /dev/null

step "a second decision on the version that is no longer current is a conflict"
[ "$(status_of_post "/api/claims/$ID/decision" '{"expectedVersion":2,"officer":"CI","note":"For sent ute.","decision":{"type":"reject","reason":"other"}}')" = "409" ]

step "the claim is paid out, and its history has all four events"
post "/api/claims/$ID/payout" '{"expectedVersion":3}' | jq --exit-status '.status.type == "paid_out"' > /dev/null
get "/api/claims/$ID" |
  jq --exit-status '[.history[].type] == ["submitted", "sent_to_review", "approved_by_officer", "payout_recorded"]' > /dev/null

step "a claim nobody could accept is refused, and a path that does not exist answers in JSON"
[ "$(status_of_post /api/claims '{"departureId":"nope","ticket":{"type":"single","price":0}}')" = "422" ]
[ "$(curl --silent "$BASE/api/nope" | jq --raw-output '.type')" = "not_found" ]

echo "All good."
