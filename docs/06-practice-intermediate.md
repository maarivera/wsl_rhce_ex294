# 6. Practice tasks: intermediate (I01-I20)

Prerequisite: B01 (inventory/ansible.cfg) and B17 (collections in
`/home/ansible/ansible/collections`). Check with `rhcelab practice I07` or
`rhcelab practice I`.

---

### I01 - Loops

**Objective:** `i01-users.yml` creates users `carol`, `dave` and `erin` with UIDs
2101, 2102 and 2103 on all managed nodes, using **one** task with `loop`.

**Expected result:** `id -u carol` = 2101, and so on.

**Validation:**
```bash
rhcelab practice I01
ansible managed -a 'id carol'
```

**Common mistakes:**
- Looping over a list of names and computing UIDs: loop over a list of dicts
  (`{name: carol, uid: 2101}`) and use `item.name` / `item.uid`.

---

### I02 - Loop over dictionaries

**Objective:** `i02-dirs.yml` creates group `share`, then (one looped task) the
directories `/srv/data` (root:root, 0750) and `/srv/share` (root:share, 2775) on all
managed nodes.

**Expected result:** `stat -c '%U:%G %a'` gives `root:root 750` and `root:share 2775`.

**Validation:**
```bash
rhcelab practice I02
ansible managed -a 'stat -c "%n %U:%G %a" /srv/data /srv/share'
```

**Common mistakes:**
- `mode: 2775` unquoted; use `"2775"` (or `"u=rwx,g=rwxs,o=rx"`).
- Creating the directory before the group exists.

---

### I03 - Conditionals with groups and facts

**Objective:** `i03-db.yml` runs on `managed` and installs `mariadb-server` only on
hosts that are in `dbservers` **and** have more than 512 MB of RAM.

**Expected result:** installed on managed-node2 only.

**Validation:**
```bash
rhcelab practice I03
ansible managed -a 'rpm -q mariadb-server'
```

**Common mistakes:**
- `when: dbservers in group_names` (unquoted group name is a variable): use `"'dbservers' in group_names"`.
- Wrapping `when` in `{{ }}`.

---

### I04 - Registered variables

**Objective:** `i04-register.yml` runs `rpm -q httpd` on all managed nodes, registers
the result without failing, and writes `installed` or `missing` to
`/root/httpd-status.txt` accordingly.

**Expected result:** managed-node1 `installed` (after B08), managed-node2 `missing`.

**Validation:**
```bash
rhcelab practice I04
ansible managed -a 'cat /root/httpd-status.txt'
```

**Common mistakes:**
- The task fails on managed-node2 (rc=1): add `failed_when: false` (or `ignore_errors`).
- Reporting `changed` for a read-only command: add `changed_when: false`.

---

### I05 - Handlers

**Objective:** `i05-handlers.yml` for `webservers` deploys
`/etc/httpd/conf.d/security.conf` with the two lines `ServerTokens Prod` and
`ServerSignature Off`, and notifies a handler that restarts httpd.

**Expected result:** file present; httpd running; a second run triggers no handler.

**Validation:**
```bash
rhcelab practice I05
ansible-playbook i05-handlers.yml   # 2nd run: changed=0, no RUNNING HANDLER
```

**Common mistakes:**
- Handlers run at the end of the play; if a later task fails, they do not run
  (use `--force-handlers` or `meta: flush_handlers` when needed).

---

### I06 - Templates and facts

**Objective:** `templates/motd.j2` + `i06-motd.yml` produce on every managed node an
`/etc/motd` with these lines:
```
Welcome to <FQDN>
IP: <default IPv4 address>
Groups: <group_names joined with ", ">
```

**Expected result:** e.g. `Welcome to managed-node1.lab.example.com`, `IP: 10.10.10.11`.

**Validation:**
```bash
rhcelab practice I06
ssh managed-node2 cat /etc/motd
```

**Common mistakes:**
- `ansible_default_ipv4.address` vs `ansible_facts['default_ipv4']['address']`: both
  work; mixing styles is confusing.
- `join` without quotes: `{{ group_names | join(', ') }}`.

---

### I07 - Jinja2 loop over hostvars

**Objective:** `i07-hosts.yml` + `templates/lab-hosts.j2` create `/etc/lab-hosts` on
`dev` only, one line per host in group `managed`:
`<IPv4> <FQDN> <short hostname>`.

**Expected result:** two lines on managed-node1, no file on managed-node2.

**Validation:**
```bash
rhcelab practice I07
ssh managed-node1 cat /etc/lab-hosts
```

**Common mistakes:**
- Running the play only on `dev`: then managed-node2's facts are never gathered and
  `hostvars['managed-node2']['ansible_facts']` is empty. Run on `managed` and
  restrict the template task with `when: "'dev' in group_names"`.

---

### I08 - Ansible Vault

**Objective:** Create `.vault_pass` (mode 0600) containing a password of your choice
and an encrypted `vault/secrets.yml` with `db_password: Sup3rS3cret`.

**Expected result:** the file starts with `$ANSIBLE_VAULT`;
`ansible-vault view --vault-password-file .vault_pass vault/secrets.yml` shows it.

**Validation:**
```bash
rhcelab practice I08
```

**Common mistakes:**
- A trailing newline in the password file is fine; a password typed
  differently at `ansible-vault create` is not.
- Committing `.vault_pass` to Git (this repository's `.gitignore` excludes it).

---

### I09 - Vault in a playbook

**Objective:** `i09-dbadmin.yml` creates user `dbadmin` on `dbservers` with the
password `db_password` from `vault/secrets.yml`, hashed with SHA-512.

**Expected result:** `dbadmin` exists only on managed-node2; its password is
`Sup3rS3cret`.

**Validation:**
```bash
rhcelab practice I09
ansible-playbook i09-dbadmin.yml --vault-password-file .vault_pass
```

**Common mistakes:**
- Passing the clear text to `password:` (it expects a hash): use
  `"{{ db_password | password_hash('sha512') }}"`.
- Forgetting `--vault-password-file` (or `vault_password_file` in ansible.cfg).

---

### I10 - group_vars

**Objective:** Create `group_vars/dev.yml` (`env_name: development`) and
`group_vars/prod.yml` (`env_name: production`); `i10-env.yml` writes `env_name` to
`/etc/environment-name` on all managed nodes.

**Expected result:** managed-node1 `development`, managed-node2 `production`.

**Validation:**
```bash
rhcelab practice I10
ansible-inventory --host managed-node1
```

**Common mistakes:**
- `group_vars/` must sit next to the inventory or the playbook.
- Naming the file `dev.yaml.j2` or `dev` without extension in the wrong place.

---

### I11 - Tags

**Objective:** `i11-tags.yml` has a task tagged `packages` (installs `zsh`) and a task
tagged `config` (creates an empty `/etc/lab-tags.conf`). Run it **with only the
`config` tag**.

**Expected result:** `/etc/lab-tags.conf` exists, `zsh` is **not** installed.

**Validation:**
```bash
rhcelab practice I11
ansible-playbook i11-tags.yml --list-tags
```

**Common mistakes:**
- Running without `--tags config` (installs zsh too).
- `--skip-tags` vs `--tags`; `always`/`never` special tags.

---

### I12 - changed_when / failed_when

**Objective:** `i12-ghost.yml` checks whether user `ghost` exists with `id ghost`
without failing, reports `ok` (not `changed`), and writes `absent` or `present` to
`/root/ghost.txt`.

**Expected result:** `/root/ghost.txt` = `absent`; the check task shows `ok`.

**Validation:**
```bash
rhcelab practice I12
```

**Common mistakes:**
- Using the `getent` module and forgetting `fail_key: false` (a valid alternative).

---

### I13 - block / rescue / always

**Objective:** `i13-block.yml`: in a `block`, install the non-existent package
`rhce-nonexistent-pkg`; in `rescue`, write `install failed` to `/root/rescue.log`; in
`always`, create `/root/always.log`.

**Expected result:** both files exist on all managed nodes; the play ends without
failure (`rescued=1`).

**Validation:**
```bash
rhcelab practice I13
```

**Common mistakes:**
- `ignore_errors: true` inside the block prevents the rescue from running.

---

### I14 - Partitions and file systems

**Objective:** On managed-node2, using the spare disk from the custom fact
`ansible_local.rhcelab.disk`, create partition 1 (500 MiB), format it XFS and mount
it persistently on `/mnt/part1`.

**Expected result:** `findmnt /mnt/part1` shows `xfs`; `/etc/fstab` has the entry.

**Validation:**
```bash
rhcelab practice I14
ansible managed-node2 -m setup -a 'filter=ansible_local'   # which loop device is yours
ssh managed-node2 findmnt /mnt/part1
```

**Common mistakes:**
- On loop disks the first partition is `<disk>p1` (e.g. `/dev/loop3p1`), not `<disk>1`.
- Using `ansible.posix.mount` with `state: present` (only fstab) instead of `mounted`.
- Lab note: never touch disks that are not in `ansible_local.rhcelab.disks`; `/dev` is shared by all nodes.

---

### I15 - LVM

**Objective:** On managed-node2, create partition 2 from 500 MiB to the end of the
spare disk, VG `vg_lab` on it, LV `lv_data` of 600 MiB, format ext4, mount persistently
on `/mnt/data`.

**Expected result:** `lvs vg_lab` shows `lv_data 600.00m`; `/mnt/data` mounted.

**Validation:**
```bash
rhcelab practice I15
ssh managed-node2 sudo lvs
```

**Common mistakes:**
- `size: 600` (MiB is the default unit for `lvol`, but be explicit: `600m`).
- `community.general.lvg` needs `pvs:` as a list or comma string of devices.
- Lab note: VG names must be unique across the lab (device-mapper is shared).

---

### I16 - Repositories

**Objective:** `i16-repos.yml` creates repositories on all managed nodes:
`lab-baseos` (baseurl `http://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/`) and
`lab-appstream` (baseurl `http://dl.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/`),
both with `gpgcheck` enabled and gpgkey
`https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9`.

**Expected result:** `dnf repolist` lists both.

**Validation:**
```bash
rhcelab practice I16
ansible managed -a 'dnf -q repolist'
```

**Common mistakes:**
- Forgetting `description` (it becomes the `name =` line; required in practice).
- Wrong key URL makes every later install fail with a GPG error.

---

### I17 - SELinux file contexts

**Objective:** On `webservers`, create `/srv/web/index.html` and add a persistent
SELinux file context `httpd_sys_content_t` for `/srv/web(/.*)?`, then apply it.

**Expected result:** the rule is in
`/etc/selinux/targeted/contexts/files/file_contexts.local`.

**Validation:**
```bash
rhcelab practice I17
ssh managed-node1 sudo semanage fcontext -l -C
```

**Common mistakes:**
- `chcon` / `file: setype=` are not persistent across a relabel.
- **WSL lab:** SELinux is disabled in the kernel; add `ignore_selinux_state: true`
  and `reload: false` to `community.general.sefcontext`. On the real exam leave them
  out and run `restorecon -Rv /srv/web`.

---

### I18 - Cron files

**Objective:** `i18-cronfile.yml` creates `/etc/cron.d/lab-backup` on all managed
nodes running `tar czf /root/etc-backup.tgz /etc` as root at 23:00 Monday-Friday.

**Expected result:** the file contains `0 23 * * 1-5 root tar czf /root/etc-backup.tgz /etc`.

**Validation:**
```bash
rhcelab practice I18
```

**Common mistakes:**
- With `cron_file:` you must also set `user:` (the user column).

---

### I19 - Delegation

**Objective:** `i19-report.yml` gathers facts on the managed nodes and writes one line
per node, `<inventory_hostname> <IPv4>`, into
`/home/ansible/ansible/inventory-report.txt` on control-node, using `delegate_to`.

**Expected result:** `managed-node1 10.10.10.11` and `managed-node2 10.10.10.12`.

**Validation:**
```bash
rhcelab practice I19
cat ~/ansible/inventory-report.txt
```

**Common mistakes:**
- Both hosts writing the same file in parallel: use `lineinfile` with `throttle: 1`
  (or `run_once` + a loop over `ansible_play_hosts`).
- `become: true` makes the local file root-owned; set `become: false` on the delegated task.

---

### I20 - Your first role

**Objective:** Create role `issue` (`ansible-galaxy role init roles/issue`) with a
default `issue_text: "Authorized users only"` that templates `/etc/issue`. Apply it to
all managed nodes, overriding `issue_text` to `Production system` for `prod`.

**Expected result:** managed-node1 `/etc/issue` = `Authorized users only`,
managed-node2 = `Production system`.

**Validation:**
```bash
rhcelab practice I20
```

**Common mistakes:**
- Putting the override in `defaults/` of the role (lowest precedence is correct for
  the default, but the override belongs in `group_vars/prod.yml` or the play).
