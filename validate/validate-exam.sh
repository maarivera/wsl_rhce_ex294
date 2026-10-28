#!/usr/bin/env bash
# Grade the mock exam: 300 points, pass mark 210 (run as ansible on control-node).
#   validate-exam.sh            grade every task
#   validate-exam.sh T08,T09    grade selected tasks
exec "$(dirname "$0")/run-checks.sh" exam "${1:-all}" --threshold 210
