#!/bin/bash
# Start the observability stack WITHOUT the Tempo container — the fallback
# for when `grafana/tempo` cannot be pulled from any mirror (2026-11-15).
# Runs the official darwin/arm64 Tempo binary on the host and a collector
# container that forwards OTLP to it via host.docker.internal:4327.
#
# Requires: tempo/bin/tempo (fetched once from GitHub release), the
# otel/opentelemetry-collector-contrib image, and the tier0-net network.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -x tempo/bin/tempo ]; then
  echo "FAIL: tempo/bin/tempo missing. Fetch tempo_2.6.1_darwin_arm64.tar.gz and" >&2
  echo "      extract its tempo binary to tempo/bin/tempo." >&2
  exit 1
fi

# 1. host tempo (skip if already listening)
if lsof -nP -iTCP:3200 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "host tempo already listening on :3200"
else
  echo "starting host tempo ..."
  mkdir -p tempo/data/blocks tempo/data/wal
  nohup ./tempo/bin/tempo -config.file=tempo/tempo.local-binary.yaml > tempo/tempo.log 2>&1 &
  sleep 3
fi

# 2. collector container (recreate to pick up config)
echo "starting collector container ..."
docker rm -f otel-collector-local >/dev/null 2>&1 || true
docker run -d --name otel-collector-local \
  --network tier0-net \
  -p 127.0.0.1:4318:4318 \
  -v "$PWD/otel/collector-config.local-binary.yaml:/etc/otel/config.yaml:ro" \
  --add-host host.docker.internal:host-gateway \
  otel/opentelemetry-collector-contrib:0.115.1 \
  --config=/etc/otel/config.yaml >/dev/null
sleep 3

echo "stack up (fallback mode). verify with: ./smoke-test.sh"
