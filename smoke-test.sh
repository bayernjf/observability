#!/bin/bash
# OTel phase-1 smoke test (OTel plan 2026-11-14).
#
# Sends one minimal OTLP/HTTP JSON trace to the local collector and then
# queries Tempo to prove the full path: SDK -> collector -> storage.
# Requires the stack up (`docker compose up -d`). Fail-loud: any missing
# piece exits non-zero so this doubles as the phase-1 acceptance check.
set -euo pipefail

COLLECTOR="http://127.0.0.1:4318/v1/traces"
TEMPO="http://127.0.0.1:3200"
TRACE_ID="$(openssl rand -hex 16)"
SPAN_ID="$(openssl rand -hex 8)"
NOW_MS="$(python3 -c 'import time; print(int(time.time()*1000))')"
START_NS="$((NOW_MS * 1000000))"
END_NS="$(( (NOW_MS + 50) * 1000000 ))"

payload=$(cat <<JSON
{
  "resourceSpans": [{
    "resource": {"attributes": [
      {"key": "service.name", "value": {"stringValue": "otel-smoke"}},
      {"key": "deployment.environment", "value": {"stringValue": "local"}}
    ]},
    "scopeSpans": [{"scope": {"name": "smoke"}, "spans": [{
      "traceId": "$TRACE_ID",
      "spanId": "$SPAN_ID",
      "name": "phase1.smoke",
      "kind": 1,
      "startTimeUnixNano": "$START_NS",
      "endTimeUnixNano": "$END_NS",
      "attributes": [{"key": "tier0.smoke", "value": {"boolValue": true}}]
    }]}]
  }]
}
JSON
)

echo "1/2 posting OTLP trace to collector"
code="$(curl -s -o /tmp/otel-smoke.out -w '%{http_code}' -X POST "$COLLECTOR" \
  -H 'content-type: application/json' -d "$payload")"
if [ "$code" != "200" ]; then
  echo "FAIL: collector returned HTTP $code" >&2; cat /tmp/otel-smoke.out >&2; exit 1
fi
echo "    accepted (HTTP 200)"

echo "2/2 reading it back from Tempo"
# Tempo needs a moment to flush the batch; poll briefly instead of sleeping.
found=""
for _ in $(seq 1 10); do
  body="$(curl -s "$TEMPO/api/traces/$TRACE_ID" || true)"
  if echo "$body" | grep -q "phase1.smoke"; then found=1; break; fi
  sleep 1
done
if [ -z "$found" ]; then
  echo "FAIL: trace $TRACE_ID not retrievable from Tempo" >&2; exit 1
fi
echo "    trace stored and queryable"
echo "PASS: OTel phase-1 path verified (trace $TRACE_ID)"
