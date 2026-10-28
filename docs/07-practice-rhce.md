# 7. Practice tasks: RHCE level (R01-R20)

These match the depth of real exam tasks: several modules, facts, error handling and
idempotency in one deliverable. Run `rhcelab reset` before a full R-series pass.
Check with `rhcelab practice R11` or `rhcelab practice R`.

---

### R01 - Role apache

**Objective:** Role `apache`: install httpd and firewalld, start and enable both,
allow http permanently and immediately, deploy `/var/www/html/index.html` from a
template containing exactly
`Welcome to <FQDN> on <default IPv4>`, and restart httpd via a handler when the
configuration changes. Apply it to `webservers` with `r01-apache.yml`.

**Expected result:** `curl http://managed-node1` →
`Welcome to managed-node1.lab.example.com on 10.10.10.11`.

**Validation:**
```bash
rhcelab practice R01
curl http://managed-node1
```

**Common mistakes:**
- Notifying a handler for the index page (content changes need no restart).
- Forgetting the firewall: the page works on the node but not from control-node.

---

### R02 - RHEL system role: timesync

**Objective:** `r02-time.yml` uses `redhat.rhel_system_roles.timesync` on all managed
nodes with NTP server `time.cloudflare.com`, `iburst` enabled.

**Expected result:** `/etc/chrony.conf` contains `server time.cloudflare.com iburst`;
chronyd enabled.

**Validation:**
```bash
rhcelab practice R02
less /usr/share/doc/rhel-system-roles/timesync/README.md
```

**Common mistakes:**
- `timesync_ntp_servers` is a list of dicts (`hostname`, `iburst`), not a list of strings.
- Copying the example playbook and forgetting to change `hosts:`.

---

### R03 - SELinux mode

**Objective:** `r03-selinux.yml` makes SELinux `enforcing` with policy `targeted`
persistently on all managed nodes (`ansible.posix.selinux`).

**Expected result:** `/etc/selinux/config` has `SELINUX=enforcing` and `SELINUXTYPE=targeted`.

**Validation:**
```bash
rhcelab practice R03
```

**Common mistakes:**
- WSL lab: the module reports "reboot required"; there is no reboot in WSL and the kernel
  keeps SELinux disabled. On the exam, a reboot handler/task may be required.

---

### R04 - LVM with fallback and mount

**Objective:** `r04-backup.yml` on all managed nodes:
- if VG `research` does not exist, print `VG research does not exist`;
- otherwise create LV `backup` of 1200 MiB; if that fails, print
  `Insufficient space, creating 600 MiB` and create 600 MiB instead;
- format XFS and mount persistently on `/mnt/backup`.

**Expected result:** managed-node1 (1 GiB VG): `research/backup` = 600 MiB, mounted.
managed-node2: message only.

**Validation:**
```bash
rhcelab practice R04
ansible managed -m setup -a 'filter=ansible_lvm'
```

**Common mistakes:**
- `when: ansible_lvm.vgs.research is defined` placed on the `block`
  (correct) vs. on each task (verbose but fine).
- Facts gathered before the LV exists: use `/dev/research/backup`, not facts, for the
  filesystem task.

---

### R05 - Inventory report from facts

**Objective:** `r05-report.yml` writes `/root/inventory.txt` on all managed nodes from
a template, with lines:
```
hostname=<short hostname>
fqdn=<fqdn>
cpus=<vcpus>
memory_mb=<total memory>
lab_disk=<ansible_local.rhcelab.disk>
disk_vdb=<size of vdb or NONE>
```

**Expected result:** values match the node; `disk_vdb=NONE` (WSL has no vdb).

**Validation:**
```bash
rhcelab practice R05
```

**Common mistakes:**
- `ansible_devices.vdb.size` without `| default('NONE')` → undefined variable error.

---

### R06 - Users from a vaulted list

**Objective:** Create `vars/r06-users.yml`:
```yaml
r06_users:
  - { name: dev1, role: developer }
  - { name: dev2, role: developer }
  - { name: ops1, role: operator }
```
and an encrypted `vault/r06-passwords.yml` with `pw_dev: DevPass123`,
`pw_ops: OpsPass123`. `r06-users.yml` creates developers on `dev` (group `devteam`,
password `pw_dev`) and operators on `prod` (group `opsteam`, password `pw_ops`),
SHA-512 hashed.

**Expected result:** dev1/dev2 only on managed-node1, ops1 only on managed-node2,
passwords correct.

**Validation:**
```bash
rhcelab practice R06
```

**Common mistakes:**
- `selectattr('role', 'equalto', 'developer')` without `| list` in older versions.
- Groups must exist before users reference them.

---

### R07 - Vault IDs and rekey

**Objective:** Encrypt `vault/api.yml` (`api_token: abc123`) with vault ID `api`
(password file `.vault_api`), then rekey it to a new password stored in
`.vault_api_new`, keeping the vault ID.

**Expected result:** first line `$ANSIBLE_VAULT;1.2;AES256;api`; opens with
`--vault-id api@.vault_api_new`.

**Validation:**
```bash
rhcelab practice R07
```

**Common mistakes:**
- `ansible-vault rekey --new-vault-id api@.vault_api_new` (keeps the label) vs.
  `--new-vault-password-file` (drops it, giving format 1.1).

---

### R08 - Requirements files

**Objective:** Write `collections/requirements.yml` (installing
`community.general` and `ansible.posix` from the materials tarballs) and
`roles/requirements.yml` (role `motd` from
`http://materials.lab.example.com/materials/roles/motd.tar.gz`). Install both into
the workspace.

**Expected result:** collections in `collections/`, role in `roles/motd`.

**Validation:**
```bash
rhcelab practice R08
ansible-galaxy collection install -r collections/requirements.yml -p collections
ansible-galaxy role install -r roles/requirements.yml -p roles
```

**Common mistakes:**
- `ansible-galaxy install -r` installs roles and collections, but only to the default
  paths unless `-p`/config says otherwise.

---

### R09 - Use a Galaxy role with variables

**Objective:** `r09-motd.yml` applies role `motd` to all managed nodes with
`motd_message: "RHCE practice node"`.

**Expected result:** `/etc/motd` begins with `RHCE practice node`.

**Validation:**
```bash
rhcelab practice R09
```

**Common mistakes:**
- Setting the variable in `vars:` of another play.
- Reading the role's `defaults/main.yml` is the fastest way to learn its variables.

---

### R10 - Conditionals inside templates

**Objective:** `r10-role.yml` + template: `/etc/node-role.conf` contains `role=web`
on `webservers`, `role=db` on `dbservers`, `role=generic` elsewhere (Jinja2
`if/elif/else`).

**Expected result:** managed-node1 `role=web`, managed-node2 `role=db`.

**Validation:**
```bash
rhcelab practice R10
```

**Common mistakes:**
- Testing `inventory_hostname in groups['webservers']` vs `'webservers' in group_names`: both work.

---

### R11 - Custom port end-to-end

**Objective:** On `webservers`, make httpd additionally listen on 8080
(`/etc/httpd/conf.d/port8080.conf` with `Listen 8080`), open 8080/tcp permanently and
immediately, restart httpd through a handler, and verify from control-node with the
`uri` module (`delegate_to: localhost`).

**Expected result:** `curl http://managed-node1:8080/` answers.

**Validation:**
```bash
rhcelab practice R11
```

**Common mistakes:**
- Replacing `Listen 80` (breaks R01).
- Real exam: also label the port with `community.general.seport`
  (`http_port_t`). The WSL kernel has no SELinux, so seport cannot run here.

---

### R12 - sysctl with dict loops

**Objective:** From a dict variable, set persistently in `/etc/sysctl.d/90-lab.conf`
and at runtime on all managed nodes:
`net.ipv4.conf.all.log_martians=1`, `net.ipv4.tcp_syncookies=1`,
`net.ipv4.icmp_echo_ignore_broadcasts=1`. Use `dict2items`.

**Expected result:** file contains the three keys; `sysctl -n` shows 1.

**Validation:**
```bash
rhcelab practice R12
```

**Common mistakes:**
- Lab note: only use `net.*` keys here; they are per network namespace. Kernel-wide
  keys such as `vm.swappiness` would change the whole WSL VM.

---

### R13 - Assertions

**Objective:** `r13-preflight.yml` asserts that every managed node runs Rocky Linux 9
and has at least 1024 MB of RAM, then writes `PASS` to `/root/preflight.txt`. If an
assertion fails the play must stop for that host with a clear message.

**Expected result:** `/root/preflight.txt` = `PASS` on both nodes.

**Validation:**
```bash
rhcelab practice R13
```

**Common mistakes:**
- Comparing `ansible_distribution_major_version` (a string) to the integer 9:
  use `== '9'` or `| int == 9`.

---

### R14 - fetch and run_once

**Objective:** `r14-backup.yml` fetches `/etc/hosts` from every managed node into
`backups/` on control-node (default fetch layout), then, **once**, writes
`backups/summary.txt` on control-node listing all play hosts.

**Expected result:** `backups/managed-node1/etc/hosts`,
`backups/managed-node2/etc/hosts`, `backups/summary.txt`.

**Validation:**
```bash
rhcelab practice R14
find backups -type f
```

**Common mistakes:**
- `run_once` without `delegate_to: localhost` runs on the first managed node.
- `flat: true` overwrites one host's file with the other's.

---

### R15 - Custom facts

**Objective:** Deploy `/etc/ansible/facts.d/app.fact` (INI: section `[app]` with
`name=lab` and `version=1.0`) to all managed nodes, re-read facts in the same play,
and write `ansible_local.app.app.version` to `/etc/app-version`.

**Expected result:** `/etc/app-version` = `1.0`.

**Validation:**
```bash
rhcelab practice R15
ansible managed -m setup -a 'filter=ansible_local'
```

**Common mistakes:**
- Facts are gathered at play start: add `ansible.builtin.setup:` (filter
  `ansible_local`) after deploying the fact file.
- Making the `.fact` file executable: executable facts must print JSON.

---

### R16 - hostvars across hosts

**Objective:** On `prod` only, write `/etc/peers` containing
`<IPv4 of managed-node1> managed-node1` read from `hostvars`.

**Expected result:** `/etc/peers` = `10.10.10.11 managed-node1` on managed-node2.

**Validation:**
```bash
rhcelab practice R16
```

**Common mistakes:**
- managed-node1's facts are missing when the play targets only prod: run the play on
  `managed` with a `when`, or gather facts with `delegate_facts`.

---

### R17 - Download, verify and extract

**Objective:** On `webservers`, download
`http://materials.lab.example.com/materials/app.tar.gz` verifying it with
`app.tar.gz.sha256`, and extract it into `/opt` so that `/opt/app/VERSION` exists.

**Expected result:** `/opt/app/VERSION` = `1.0.0`.

**Validation:**
```bash
rhcelab practice R17
```

**Common mistakes:**
- `get_url` `checksum: "sha256:http://.../app.tar.gz.sha256"` (URL form) or
  the literal hash; both work.
- `unarchive` with `remote_src: true` when the file is already on the node.

---

### R18 - MariaDB on its own IP

**Objective:** On `dbservers`: install `mariadb-server`, deploy
`/etc/my.cnf.d/lab.cnf` from a template with `[mysqld]` and
`bind-address={{ ansible_default_ipv4.address }}`, start and enable `mariadb`
(restart via handler on change), allow firewalld service `mysql`.

**Expected result:** `ss -ltn` on managed-node2 shows `10.10.10.12:3306`.

**Validation:**
```bash
rhcelab practice R18
ssh managed-node2 ss -ltn
```

**Common mistakes:**
- The service is `mariadb`, the firewalld service is `mysql`.

---

### R19 - Scheduled job for a service account

**Objective:** On all managed nodes create user `backup`, deploy
`/usr/local/bin/backup.sh` (owner backup, mode 0750) and a cron job for `backup`
running it every 15 minutes, 08:00-18:59, Monday-Friday.

**Expected result:** `crontab -l -u backup` shows `*/15 8-18 * * 1-5 /usr/local/bin/backup.sh`.

**Validation:**
```bash
rhcelab practice R19
```

**Common mistakes:**
- `hour: "8-18"` and `weekday: "1-5"` are strings.

---

### R20 - Integration and idempotency

**Objective:** Write `site.yml` that imports playbooks or roles so that one run
applies: role `apache` to `webservers` (R01), the MariaDB setup to `dbservers` (R18),
and role `motd` to all managed nodes (R09). A **second** run must report
`changed=0` on both nodes.

**Expected result:** idempotent `site.yml`.

**Validation:**
```bash
rhcelab practice R20     # runs site.yml once and inspects PLAY RECAP
```

**Common mistakes:**
- `command`/`shell` tasks without `changed_when` or `creates:`.
- `password_hash` without a fixed salt (new hash every run): use
  `update_password: on_create` or a salt.
