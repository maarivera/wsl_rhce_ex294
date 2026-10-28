# 10. Validation scripts

## 10.1 Overview

All checks live in three TSV files and are executed by two interchangeable engines:

| Suite | File | Checks | Purpose |
|---|---|---|---|
| `lab` | `validate/lab-checks.tsv` | 34 | the environment itself (network, SSH, DNS, storage, tooling) |
| `exam` | `validate/exam-checks.tsv` | 92 (300 points) | the mock exam |
| `practice` | `validate/practice-checks.tsv` | 101 (60 tasks) | B01-B20, I01-I20, R01-R20 |

| Engine | Command |
|---|---|
| Bash | `validate/run-checks.sh SUITE [FILTER] [--threshold N]` |
| Ansible | `ansible-playbook validate/run-checks.yml -e suite=SUITE [-e filter=...]` |

Shortcuts on control-node:

```bash
rhcelab validate                # bash, lab suite
rhcelab practice B05            # bash, practice suite, one task
rhcelab practice R              # all RHCE-level tasks
rhcelab grade                   # bash, exam suite, threshold 210
rhcelab grade-ansible           # Ansible, exam suite
```

Plus a native Ansible environment check that uses facts and `assert`:

```bash
cd /opt/rhcelab
ANSIBLE_CONFIG=lab/ansible.cfg ansible-playbook validate/validate-lab.yml
```

Reports are saved to `~/rhcelab-reports/<suite>-<timestamp>.txt`.

## 10.2 Check format

One check per line, TAB-separated:

```
ID    POINTS  TARGET         DESCRIPTION                     COMMAND
T11   4       managed-node1  /etc/issue is Development       test "$(cat /etc/issue)" = Development
T01   3       control        ansible all -m ping succeeds    ansible all -m ansible.builtin.ping -o
```

* `TARGET control`: runs as `ansible` in `/home/ansible/ansible` with
  `ANSIBLE_CONFIG` unset, so **your** `ansible.cfg` is used.
* `TARGET managed-nodeN`: runs as root on that node over SSH, so it runs inside the
  node's network namespace, exactly where Ansible runs.
* A check passes when the command exits 0. Commands must not contain `{{`, `{%` or
  `{#` (the Ansible engine would template them).

The grader never uses your inventory to reach the nodes. It connects directly with the
`ansible` user's key, so a broken inventory costs only the inventory points.

## 10.3 Sample output

```
RHCE lab check suite: exam (filter: all) - 2026-10-28 14:02:11

  PASS  T01   control        ansible.cfg and inventory exist in /home/ansible/ansible
  PASS  T01   control        groups dev=managed-node1, prod=managed-node2
  FAIL  T09   managed-node1  research/data created with the fallback size 800 MiB
  ...
Score by task
  T01    20 /  20
  T09    14 /  20
  ...
TOTAL: 262 / 300  PASS (need 210)
```

## 10.4 Manual verification commands by objective

| Objective | Command (from control-node) |
|---|---|
| Inventory | `ansible-inventory --graph`, `ansible-inventory --host managed-node1` |
| Config | `ansible-config dump --only-changed`, `ansible --version` |
| Connectivity | `ansible all -m ping`, `ssh managed-node1 hostname` |
| Facts | `ansible managed-node1 -m setup -a 'filter=ansible_default_ipv4'` |
| Packages | `ansible managed -a 'rpm -q httpd'`, `ansible managed -a 'dnf -q group list --installed'` |
| Repositories | `ansible managed -a 'dnf -q repolist'`, `ansible managed -a 'cat /etc/yum.repos.d/EX294_BASE.repo'` |
| Services | `ansible managed -a 'systemctl is-enabled httpd'`, `... is-active httpd` |
| Firewall | `ansible managed -a 'firewall-cmd --list-all'`, `... --permanent --list-all` |
| Users | `ansible managed -a 'id bob'`, `ansible managed -a 'chage -l bob'` |
| Cron | `ansible managed -a 'crontab -l -u natasha'`, `ansible managed -a 'ls /etc/cron.d'` |
| Storage | `ansible managed -a 'lsblk -f'`, `ansible managed -a 'lvs'`, `ansible managed -a 'findmnt --fstab'` |
| SELinux | `ansible managed -a 'cat /etc/selinux/config'`, `ansible managed -a 'semanage fcontext -l -C'` |
| Web | `curl http://managed-node1/`, `curl -I http://managed-node2/info.php` |
| Vault | `ansible-vault view --vault-password-file secret.txt locker.yml` |
| Templates | `ansible managed -a 'cat /etc/myhosts'` |
| Idempotency | run the playbook twice; the second `PLAY RECAP` should show `changed=0` |

## 10.5 Writing your own checks

Add a line to `practice-checks.tsv` (on control-node: copy `/opt/rhcelab/validate` to
your home first, since `/opt/rhcelab` is root-owned):

```bash
cp -r /opt/rhcelab/validate ~/my-validate
printf 'X01\t1\tmanaged-node1\tchrony points to my server\tgrep -q "^server ntp.example.com" /etc/chrony.conf\n' >> ~/my-validate/practice-checks.tsv
~/my-validate/run-checks.sh practice X01
```
