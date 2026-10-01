#!/usr/bin/env bash
# Ned Watch check-in for GitHub Actions. Deadman: POST /v1/checkin/<id>. Overrun: POST /v1/watches/<id>/start|finish.
# The signing secret is masked in logs and only ever sent as an Authorization header over HTTPS.
set -uo pipefail
echo "::add-mask::${NED_SIGNING_SECRET}"

out() { echo "$1=$2" >> "$GITHUB_OUTPUT"; }
problem() {                                   # warn, or fail when fail-on-error is true
  if [ "$(printf %s "$NED_FAIL_ON_ERROR" | tr "[:upper:]" "[:lower:]")" = "true" ]; then echo "::error title=Ned Watch::$1"; out ok false; exit 1; fi
  echo "::warning title=Ned Watch::$1"; out ok false; exit 0
}

[[ "$NED_WATCH_ID" =~ ^w_[0-9a-f]{12}$ ]] || problem "watch-id should look like w_ followed by 12 hex characters"
[ -n "$NED_SIGNING_SECRET" ] || problem "signing-secret is empty (is the secret set in this repo?)"
API="${NED_API%/}"
RUN_ID="${NED_RUN_ID:-gh-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}}"

case "$NED_MODE" in
  checkin) URL="$API/v1/checkin/$NED_WATCH_ID"; BODY='' ;;
  start|finish) URL="$API/v1/watches/$NED_WATCH_ID/$NED_MODE"; BODY="{\"run_id\":\"$RUN_ID\"}" ;;
  *) problem "mode must be checkin, start or finish (got: $NED_MODE)" ;;
esac

RESP=$(mktemp)
CODE=$(curl -sS -o "$RESP" -w '%{http_code}' --max-time 20 --retry 3 --retry-all-errors --retry-delay 2 \
  -X POST "$URL" -H "Authorization: Bearer $NED_SIGNING_SECRET" -H "Content-Type: application/json" \
  -H "User-Agent: ned-watch-deadman-action/1" ${BODY:+--data "$BODY"}) || CODE="000"
TEXT=$(tr -d '\n' < "$RESP" | head -c 2000); rm -f "$RESP"
out response "$TEXT"

if [ "$CODE" = "200" ]; then
  out ok true
  case "$NED_MODE" in
    checkin) echo "Checked in with Ned. $TEXT" ;;
    start)   echo "Run $RUN_ID started; Ned fires if it isn't finished in time. $TEXT" ;;
    finish)  echo "Run $RUN_ID finished. $TEXT" ;;
  esac
  { echo "### Ned Watch: $NED_MODE ok"; echo; echo '```json'; echo "$TEXT"; echo '```'; } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  exit 0
fi
case "$CODE" in
  401) problem "Ned didn't accept the signing secret for $NED_WATCH_ID (HTTP 401)" ;;
  404) problem "Ned has no active watch $NED_WATCH_ID of this kind (HTTP 404). A deadman uses mode checkin; an overrun uses start/finish." ;;
  409) problem "Ned says: $TEXT (HTTP 409)" ;;
  000) problem "couldn't reach $API after 3 tries" ;;
  *)   problem "Ned answered HTTP $CODE: $TEXT" ;;
esac
