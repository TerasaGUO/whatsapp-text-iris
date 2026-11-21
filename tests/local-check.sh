#!/bin/sh
# Run all services and tests in a disposable, network-isolated IRIS container using synthetic webhook secrets.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_image=${IRIS_IMAGE:-containers.intersystems.com/intersystems/irishealth-community:2026.2}
test_container=$(docker run --detach --rm --network none -e WA_APP_SECRET=local-app-secret -e WA_VERIFY_TOKEN=local-verify -e WA_PHONE_ID=7123 -v "$project_dir:/app:ro" "$test_image" --check-caps false)
trap 'docker stop -t 20 "$test_container" >/dev/null 2>&1 || true' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
attempt=0
until docker exec "$test_container" iris session IRIS -U USER '##class(%SYSTEM.Version).GetVersion' >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 60 ]; then
        docker logs --tail 20 "$test_container" >&2
        exit 1
    fi
    sleep 1
done
docker exec "$test_container" sh -ec '
    iris session IRIS -U USER < /app/tests/load.script
    iris session IRIS -U %SYS < /app/tests/webapp.script
    export PYTHONDONTWRITEBYTECODE=1
    cd /app
    python3 -m unittest discover -s tests
    python3 tests/loopback.py
'
