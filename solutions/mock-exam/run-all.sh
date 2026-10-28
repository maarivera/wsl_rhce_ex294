#!/usr/bin/env bash
# run-all.sh - apply the reference solution of the mock exam, then grade it.
# Use it to prove the lab and the grader work end to end (expected: 300/300).
#
#   rhcelab exam-start                 # clean nodes, repos removed, workspace archived
#   /opt/rhcelab/solutions/mock-exam/run-all.sh
#
# SPOILERS: every answer is in this directory.
set -euo pipefail

SOL=$(cd "$(dirname "$0")" && pwd)
WS=/home/ansible/ansible
MAT=http://materials.lab.example.com/materials

if [[ -n $(ls -A "$WS" 2>/dev/null) && ${1:-} != --force ]]; then
    echo "$WS is not empty. Run 'rhcelab exam-start' first, or pass --force." >&2
    exit 1
fi
mkdir -p "$WS"
cd "$WS"
unset ANSIBLE_CONFIG

step() { printf '\n=== %s\n' "$*"; }

step "T01 ansible.cfg and inventory"
cp "$SOL"/ansible.cfg "$SOL"/inventory .
ansible all -m ansible.builtin.ping -o

step "T02 repositories (ad-hoc)"
install -m 0755 "$SOL/adhoc.sh" adhoc.sh
./adhoc.sh

step "T03 collections"
bash "$SOL/collections.sh"

step "T04 packages"
cp "$SOL/packages.yml" . && ansible-playbook packages.yml

step "T05 timesync system role"
cp "$SOL/timesync.yml" . && ansible-playbook timesync.yml

step "T06 roles from requirements"
mkdir -p roles && cp "$SOL/roles/requirements.yml" roles/
ansible-galaxy role install -r roles/requirements.yml -p roles

step "T07 use the roles"
cp "$SOL/roles.yml" . && ansible-playbook roles.yml

step "T08 apache role"
cp -r "$SOL/roles/apache" roles/ && cp "$SOL/apache.yml" . && ansible-playbook apache.yml

step "T09 logical volume"
cp "$SOL/lv.yml" . && ansible-playbook lv.yml

step "T10 hosts template"
cp "$SOL/hosts.j2" "$SOL/hosts.yml" . && ansible-playbook hosts.yml

step "T11 issue"
cp "$SOL/issue.yml" . && ansible-playbook issue.yml

step "T12 web content"
cp "$SOL/webcontent.yml" . && ansible-playbook webcontent.yml

step "T13 hardware report"
cp "$SOL/hwreport.yml" . && ansible-playbook hwreport.yml

step "T14 vault"
echo whenyouwishuponastar >secret.txt && chmod 0600 secret.txt
cp "$SOL/locker.yml.plain" locker.yml
ansible-vault encrypt --vault-password-file secret.txt locker.yml

step "T15 users"
curl -fsSO "$MAT/user_list.yml"
cp "$SOL/users.yml" . && ansible-playbook users.yml --vault-password-file secret.txt

step "T16 rekey"
curl -fsSO "$MAT/salaries.yml"
old=$(mktemp) new=$(mktemp)
echo insecure8sure >"$old"; echo bbs2you9527 >"$new"
ansible-vault rekey --vault-password-file "$old" --new-vault-password-file "$new" salaries.yml
rm -f "$old" "$new"

step "T17 cron"
cp "$SOL/cron.yml" . && ansible-playbook cron.yml

step "T18 report"
cp "$SOL/report.yml" . && ansible-playbook report.yml

step "Grading"
/opt/rhcelab/validate/validate-exam.sh
