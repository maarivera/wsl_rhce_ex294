#!/usr/bin/env bash
# run-checks.sh - run a TSV check suite against the lab (bash engine).
#
# Usage: run-checks.sh SUITE [FILTER] [--threshold N]
#   SUITE   lab | exam | practice   (reads validate/SUITE-checks.tsv)
#   FILTER  comma-separated IDs or prefixes: T09, B05, R, all (default: all)
#
# TSV columns: ID  POINTS  TARGET  DESCRIPTION  COMMAND
#   TARGET control         -> run as ansible in the workspace (/home/ansible/ansible)
#   TARGET managed-nodeN   -> run as root on that node over SSH
#   COMMAND passes when it exits 0.
# validate/run-checks.yml runs the same files with Ansible.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
WORKSPACE=${WORKSPACE:-/home/ansible/ansible}
SUITE=${1:?usage: run-checks.sh lab|exam|practice [FILTER] [--threshold N]}
shift
FILTER=all THRESHOLD=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --threshold) THRESHOLD=$2; shift 2 ;;
        *) FILTER=$1; shift ;;
    esac
done
TSV=$HERE/$SUITE-checks.tsv
[[ -r $TSV ]] || { echo "no such suite: $TSV" >&2; exit 2; }

if [[ -t 1 ]]; then G=$'\e[32m' R=$'\e[31m' B=$'\e[1m' N=$'\e[0m'; else G="" R="" B="" N=""; fi
SSH_OPTS=(-n -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR)

matches() {
    local id=$1 f
    [[ ${FILTER,,} == all ]] && return 0
    IFS=, read -ra fs <<<"$FILTER"
    for f in "${fs[@]}"; do [[ $id == "$f"* ]] && return 0; done
    return 1
}

run_check() {
    local target=$1 cmd=$2
    if [[ $target == control ]]; then
        (cd "$WORKSPACE" 2>/dev/null || cd ~; env -u ANSIBLE_CONFIG timeout 120 bash -c "$cmd") </dev/null &>/dev/null
    else
        timeout 120 ssh "${SSH_OPTS[@]}" "ansible@$target" "sudo -n bash -c $(printf '%q' "$cmd")" &>/dev/null
    fi
}

mkdir -p ~/rhcelab-reports
REPORT=~/rhcelab-reports/$SUITE-$(date +%Y%m%d-%H%M%S).txt
declare -A task_total task_got
order=()
total=0 got=0 passed=0 failed=0

main() {
printf '%sRHCE lab check suite: %s (filter: %s) - %s%s\n\n' "$B" "$SUITE" "$FILTER" "$(date '+%F %T')" "$N"
while IFS=$'\t' read -r id pts target desc cmd; do
    [[ -z ${id// /} || $id == \#* ]] && continue
    matches "$id" || continue
    [[ -n ${task_total[$id]+x} ]] || { order+=("$id"); task_total[$id]=0; task_got[$id]=0; }
    task_total[$id]=$((task_total[$id] + pts)); total=$((total + pts))
    if run_check "$target" "$cmd"; then
        printf '  %sPASS%s  %-5s %-14s %s\n' "$G" "$N" "$id" "$target" "$desc"
        task_got[$id]=$((task_got[$id] + pts)); got=$((got + pts)); passed=$((passed + 1))
    else
        printf '  %sFAIL%s  %-5s %-14s %s\n' "$R" "$N" "$id" "$target" "$desc"
        failed=$((failed + 1))
    fi
done <"$TSV"

if [[ $SUITE == exam ]]; then
    printf '\n%sScore by task%s\n' "$B" "$N"
    for id in "${order[@]}"; do printf '  %-5s %3d / %3d\n' "$id" "${task_got[$id]}" "${task_total[$id]}"; done
    printf '\n%sTOTAL: %d / %d%s' "$B" "$got" "$total" "$N"
    if [[ -n $THRESHOLD ]]; then
        if (( got >= THRESHOLD )); then printf '  %sPASS%s (need %d)\n' "$G" "$N" "$THRESHOLD"; else printf '  %sFAIL%s (need %d)\n' "$R" "$N" "$THRESHOLD"; fi
    else
        echo
    fi
else
    printf '\n%s%d passed, %d failed%s\n' "$B" "$passed" "$failed" "$N"
fi
}

tmp=$(mktemp)
main | tee "$tmp"
sed 's/\x1b\[[0-9;]*m//g' "$tmp" >"$REPORT"
rm -f "$tmp"
echo "report: $REPORT"

# Exit 0 only when everything selected passed (exam: when the threshold was met).
if [[ $SUITE == exam && -n $THRESHOLD ]]; then
    grep -q 'TOTAL:.*PASS' "$REPORT"
else
    ! grep -q '^  FAIL' "$REPORT"
fi
