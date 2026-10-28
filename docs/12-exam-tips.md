# 12. RHCE exam tips

## 12.1 Exam-day strategy

1. **First 15 minutes:** read *all* tasks. Note dependencies (inventory → repos →
   collections → everything else; vault file → users). Mark the quick wins.
2. **Foundation first:** `ansible.cfg` + inventory, then repositories. Without them
   nothing else can score.
3. **One playbook per task, named exactly as requested**, in the requested directory.
   The grader looks for the file name and the result.
4. **Run every playbook immediately** and verify the result on the node. A correct
   playbook that was never run scores nothing.
5. **Time box:** ~10 minutes per task on the first pass. Stuck for 5 minutes? Skip,
   note it, come back.
6. **Last 30 minutes:** run every playbook again in order (idempotency, nothing
   broken by later tasks), then the [checklist](08-mock-exam.md#86-verification-checklist-last-20-minutes).
7. **Reboot test:** on the real exam, the nodes may be rebooted before grading. Every
   service must be `enabled`, every mount in fstab, every firewall rule `permanent`.

## 12.2 Setup in the first five minutes

```bash
cat > ~/.vimrc <<'EOF'
autocmd FileType yaml setlocal ai et ts=2 sw=2 sts=2 cuc
EOF
cd ~/ansible
ansible --version          # config file = /home/.../ansible/ansible.cfg ?
```

## 12.3 `ansible-doc` is your internet

```bash
ansible-doc -l | grep -i lvol               # find a module
ansible-doc -s community.general.lvol       # parameters as a ready-to-edit snippet
ansible-doc ansible.builtin.user | sed -n '/^EXAMPLES/,$p'   # just the examples
ansible-doc -t filter ansible.builtin.password_hash
ansible-doc -t lookup ansible.builtin.file
ansible-doc -t keyword -l | grep -i delegate
ls /usr/share/doc/rhel-system-roles/        # README.md + example playbooks per role
```

## 12.4 Patterns that come up again and again

| Need | Pattern |
|---|---|
| Only some hosts | `when: "'dev' in group_names"` or `when: inventory_hostname in groups['dev']` |
| Facts of other hosts | play on all hosts, then `hostvars[h]['ansible_facts'][...]` |
| Missing value | `{{ ansible_facts['devices']['vdb']['size'] \| default('NONE') }}` |
| Try / fallback | `block:` / `rescue:` / `always:` |
| Never fail a probe | `register: r`, `failed_when: false`, `changed_when: false` |
| Hash a password | `"{{ pw \| password_hash('sha512') }}"` |
| Filter a list of dicts | `users \| selectattr('job', 'equalto', 'developer') \| list` |
| Run on control node | `delegate_to: localhost`, `become: false`, `run_once: true` |
| Restart on change | `notify: Restart httpd` + `handlers:` |
| Firewall | `permanent: true` **and** `immediate: true` |
| SELinux context | `sefcontext` + `restorecon -Rv` (lab: `ignore_selinux_state: true`) |
| Persistent mount | `ansible.posix.mount` with `state: mounted` |
| Quote octal modes | `mode: "0644"`, `mode: "2775"` |

## 12.5 Common point losers

- File in the wrong directory or misspelled (`hwreport.yaml` instead of `.yml`).
- Hard-coded host names or IPs where facts were required (`Welcome to {{ ansible_fqdn }}`).
- Group used in a task does not exist in the inventory.
- Variables file and vault password file not wired up (`vars_files`, `--vault-password-file`).
- Services started but not enabled; firewall rule not permanent.
- `ansible.cfg` with `inventory = ./inventory` while running from another directory.
- A later playbook silently overrides an earlier result (e.g. two tasks writing `/etc/motd`).
- Editing a role's `defaults/main.yml` of an installed Galaxy role instead of passing variables.

## 12.6 Debugging fast

```bash
ansible-playbook site.yml --syntax-check
ansible-playbook site.yml --check --diff          # dry run (not all modules support it)
ansible-playbook site.yml --start-at-task "Create users"
ansible-playbook site.yml --step
ansible-playbook site.yml -v                      # -vvv for connection problems
ansible-playbook site.yml --list-tasks --list-tags --list-hosts
ansible managed-node1 -m debug -a "var=hostvars['managed-node2']['ansible_facts']['default_ipv4']"
```

## 12.7 Mindset

* The exam is performance-based: **results count, elegance does not.** A working
  `shell` task beats a broken perfect module. But prefer modules: they are idempotent
  and easier to verify.
* Do not fight a task you cannot finish. Partial credit exists per objective.
* Leave the environment working. Never break SSH or sudo on a managed node.
