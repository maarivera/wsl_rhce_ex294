#!/usr/bin/env bash
# Check practice tasks: check-practice.sh B05 | B | I | R | B01,I07 | all
[[ $# -ge 1 ]] || { echo "usage: $0 TASK-ID|B|I|R|all" >&2; exit 2; }
exec "$(dirname "$0")/run-checks.sh" practice "$1"
