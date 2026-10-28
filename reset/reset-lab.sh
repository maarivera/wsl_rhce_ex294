#!/usr/bin/env bash
# reset-lab.sh - reset the RHCE lab from control-node (run as ansible).
#
#   reset-lab.sh                      full reset of both managed nodes
#   reset-lab.sh --only users,firewall
#   reset-lab.sh --node managed-node2
#   reset-lab.sh --exam               full reset, then remove repo files (mock exam start)
#   reset-lab.sh --workspace          also archive and empty /home/ansible/ansible
set -euo pipefail

LAB_HOME=${LAB_HOME:-/opt/rhcelab}
WORKSPACE=${WORKSPACE:-/home/ansible/ansible}
export ANSIBLE_CONFIG=$LAB_HOME/lab/ansible.cfg

ONLY="" NODE="managed" EXAM=false RESET_WS=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --only) ONLY=$2; shift 2 ;;
        --node) NODE=$2; shift 2 ;;
        --exam) EXAM=true; shift ;;
        --workspace) RESET_WS=true; shift ;;
        -h | --help) sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done

if $RESET_WS && [[ -d $WORKSPACE ]] && [[ -n $(ls -A "$WORKSPACE") ]]; then
    mkdir -p ~/workspace-backups
    archive=~/workspace-backups/ansible-$(date +%Y%m%d-%H%M%S).tar.gz
    tar -C "$(dirname "$WORKSPACE")" -czf "$archive" "$(basename "$WORKSPACE")"
    find "$WORKSPACE" -mindepth 1 -delete
    rm -rf ~/.ansible/collections ~/.ansible/roles ~/.ansible/tmp
    echo "workspace archived to $archive and emptied"
fi

# Fail early, with the out-of-band fix, if a node cannot be reached.
if ! ansible "$NODE" -m ansible.builtin.ping -o; then
    cat >&2 <<'MSG'

Some nodes are unreachable over SSH. Reset them out-of-band from Windows:
    wsl -d managed-node1 -u root -- rhcelab-reset all
or  .\windows\Reset-RhceLab.ps1            (soft reset)
or  .\windows\Reset-RhceLab.ps1 -Hard      (re-clone from the golden image)
MSG
    exit 1
fi

args=(-l "$NODE" -e "exam_mode=$EXAM")
[[ -n $ONLY ]] && args+=(--tags "$ONLY,verify")
cd "$LAB_HOME"
ansible-playbook reset/reset-lab.yml "${args[@]}"
