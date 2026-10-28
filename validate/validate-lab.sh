#!/usr/bin/env bash
# Check that the lab environment itself is healthy (run as ansible on control-node).
exec "$(dirname "$0")/run-checks.sh" lab "$@"
