# 5. Practice tasks: beginner (B01-B20)

Work as `ansible` on control-node in `/home/ansible/ansible`. Use FQCNs
(`ansible.builtin.copy`) and `ansible-doc` instead of the internet.

* Check one task: `rhcelab practice B05`. Check all beginner tasks: `rhcelab practice B`.
* Start clean: `rhcelab reset` (nodes) and `rhcelab reset --workspace` (also archives
  and empties your workspace).
* Groups used throughout (task B01): `dev`=managed-node1, `prod`=managed-node2,
  `webservers`=managed-node1, `dbservers`=managed-node2, `managed`=dev+prod.

---

### B01 - Inventory and ansible.cfg

**Objective:** Create `/home/ansible/ansible/inventory` with groups `dev`
(managed-node1), `prod` (managed-node2), `webservers` (managed-node1), `dbservers`
(managed-node2) and `managed` (children `dev` and `prod`). Create
`/home/ansible/ansible/ansible.cfg` that uses this inventory, connects as `ansible`,
escalates to root with sudo, uses `/home/ansible/ansible/roles` and
`/home/ansible/ansible/collections`, and does not prompt for host keys.

**Expected result:** `ansible-inventory --graph` shows the groups; `ansible all -m ping`
succeeds without prompts.

**Validation:**
```bash
rhcelab practice B01
ansible-inventory --graph
ansible-config dump --only-changed
```

**Common mistakes:**
- Writing `[managed]` instead of `[managed:children]` (the members are then treated as host names `dev` and `prod`).
- Relative `inventory = inventory` works only from that directory; use the absolute path.
- Putting `become` under `[defaults]` instead of `[privilege_escalation]`.
- Forgetting `ansible.cfg` is ignored in a world-writable directory.

---

### B02 - Ad-hoc ping script

**Objective:** Create executable `adhoc-ping.sh` that runs the `ping` module
ad-hoc against all managed nodes.

**Expected result:** `./adhoc-ping.sh` prints `pong` for both nodes and exits 0.

**Validation:**
```bash
rhcelab practice B02
./adhoc-ping.sh; echo "exit=$?"
```

**Common mistakes:**
- Forgetting `chmod +x` or the `#!/bin/bash` line.
- Using `ping` the ICMP tool idea: the Ansible ping module tests SSH + Python, not ICMP.

---

### B03 - Ad-hoc command module

**Objective:** Create executable `adhoc-uptime.sh` that runs `uptime` on all managed
nodes using the `command` module explicitly (`-m ansible.builtin.command`).

**Expected result:** Output contains `load average` for each node.

**Validation:**
```bash
rhcelab practice B03
./adhoc-uptime.sh
```

**Common mistakes:**
- Relying on the default module without `-m` (the task asks for it explicitly).
- Using `command` for pipes or redirects; those need `shell`.

---

### B04 - Ad-hoc copy

**Objective:** With one ad-hoc command, make `/etc/motd` on all managed nodes contain
exactly `Managed by Ansible` (one line).

**Expected result:** `cat /etc/motd` prints `Managed by Ansible` on both nodes.

**Validation:**
```bash
rhcelab practice B04
ansible managed -a 'cat /etc/motd'
```

**Common mistakes:**
- Forgetting `become` (needed unless it is in `ansible.cfg`).
- Quoting: `-a "content='Managed by Ansible\n' dest=/etc/motd"`; the outer and inner quotes must differ.

---

### B05 - Ad-hoc package install

**Objective:** Install the package `tree` on the `dev` group only, ad-hoc, with the
`dnf` module.

**Expected result:** `tree` installed on managed-node1, not on managed-node2.

**Validation:**
```bash
rhcelab practice B05
ansible managed -a 'rpm -q tree'
```

**Common mistakes:**
- Targeting `all`.
- `state=installed` works but `present` is the documented value.

---

### B06 - First playbook: files and directories

**Objective:** Write `b06-file.yml` that creates directory `/srv/ansible-lab` (owner
root, mode 0755) on all managed nodes and a file `/srv/ansible-lab/README` containing
the line `Practice lab file`.

**Expected result:** Directory and file exist with the right mode and content.

**Validation:**
```bash
rhcelab practice B06
ansible-playbook b06-file.yml --syntax-check
ansible managed -a 'ls -ld /srv/ansible-lab'
```

**Common mistakes:**
- `mode: 755` (an integer, read as octal 01363 by YAML 1.1): always quote, `mode: "0755"`.
- Indentation errors: run `--syntax-check` first.

---

### B07 - Install a list of packages

**Objective:** Write `b07-packages.yml` that installs `git` and `tmux` on all managed
nodes in a single task.

**Expected result:** both packages installed.

**Validation:**
```bash
rhcelab practice B07
ansible managed -a 'rpm -q git tmux'
```

**Common mistakes:**
- Looping over packages with `loop:`; pass the list to `name:` (one transaction, faster).

---

### B08 - Services

**Objective:** Write `b08-httpd.yml` that installs `httpd` on `webservers`, starts it
and enables it at boot.

**Expected result:** httpd active and enabled on managed-node1.

**Validation:**
```bash
rhcelab practice B08
ssh managed-node1 systemctl is-active httpd
curl -s http://managed-node1 | head -3   # firewall blocks this until B15 is done
```

**Common mistakes:**
- `state: started` without `enabled: true` (not persistent).
- Confusing `service` and `systemd` modules: both work here.

---

### B09 - Users

**Objective:** Write `b09-user.yml` that creates user `alice` with UID 2001, comment
`Alice Lab` and shell `/bin/bash` on all managed nodes.

**Expected result:** `getent passwd alice` shows `2001`, `Alice Lab`, `/bin/bash`.

**Validation:**
```bash
rhcelab practice B09
ansible managed -a 'getent passwd alice'
```

**Common mistakes:**
- Quoting `uid: "2001"` is fine; `uid: 02001` is not.

---

### B10 - Groups and membership

**Objective:** Write `b10-groups.yml`: group `developers` with GID 3000 and user `bob`
as a member (supplementary group) on all managed nodes.

**Expected result:** `id bob` lists `developers`.

**Validation:**
```bash
rhcelab practice B10
ansible managed -a 'id bob'
```

**Common mistakes:**
- `group:` sets the primary group; supplementary groups need `groups:`.
- Omitting `append: true` when the user already has other supplementary groups.

---

### B11 - Play variables

**Objective:** Write `b11-vars.yml` that defines the play variable `lab_owner: rhce`
and writes its value (only) into `/etc/lab-owner` on all managed nodes.

**Expected result:** `/etc/lab-owner` contains `rhce`.

**Validation:**
```bash
rhcelab practice B11
ansible managed -a 'cat /etc/lab-owner'
```

**Common mistakes:**
- A value starting with `{{` must be quoted: `content: "{{ lab_owner }}\n"`.

---

### B12 - Facts

**Objective:** Write `b12-facts.yml` that creates `/etc/node-facts.txt` on all managed
nodes with exactly these three lines, from facts:
```
hostname=<short hostname>
distribution=<distribution name>
version=<distribution version>
```

**Expected result:** e.g. `hostname=managed-node1`, `distribution=Rocky`, `version=9.8`.

**Validation:**
```bash
rhcelab practice B12
ansible managed -m setup -a 'filter=ansible_distribution*'
ansible managed -a 'cat /etc/node-facts.txt'
```

**Common mistakes:**
- `gather_facts: false` and then using facts.
- Using `ansible_fqdn` instead of `ansible_hostname`.

---

### B13 - lineinfile

**Objective:** Write `b13-line.yml` that ensures `/etc/profile.d/lab.sh` exists and
contains the line `export LAB_ENV=practice`. Running it twice must not add a second
line.

**Expected result:** exactly one such line.

**Validation:**
```bash
rhcelab practice B13
ansible-playbook b13-line.yml   # second run: changed=0
```

**Common mistakes:**
- Forgetting `create: true` when the file does not exist.

---

### B14 - Copy a file from the control node

**Objective:** Create `files/banner.txt` in the workspace containing
`Authorized access only`, and write `b14-banner.yml` that copies it to
`/etc/issue.net` (mode 0644, owner root) on all managed nodes.

**Expected result:** `/etc/issue.net` has the text, mode 644.

**Validation:**
```bash
rhcelab practice B14
ansible managed -a 'ls -l /etc/issue.net'
```

**Common mistakes:**
- `src: banner.txt` without the `files/` directory next to the playbook (relative
  `src` is searched in `files/` of the playbook or role).

---

### B15 - firewalld

**Objective:** Write `b15-firewall.yml` that permanently and immediately allows the
`http` service in firewalld on `webservers`.

**Expected result:** `firewall-cmd --list-services` and
`firewall-cmd --permanent --list-services` both include `http`;
`curl http://managed-node1` works from control-node.

**Validation:**
```bash
rhcelab practice B15
ssh managed-node1 sudo firewall-cmd --list-services
curl -sI http://managed-node1 | head -1
```

**Common mistakes:**
- `permanent: true` without `immediate: true` (only active after a reload).
- The module is `ansible.posix.firewalld`; install the `ansible.posix` collection
  first (task B17), otherwise the module is not found.

---

### B16 - Cron

**Objective:** Write `b16-cron.yml` that creates a root cron job named
`cleanup tmp` on all managed nodes, running `find /tmp -mtime +7 -delete` daily at 02:30.

**Expected result:** `crontab -l` for root shows `#Ansible: cleanup tmp` and
`30 2 * * * find /tmp -mtime +7 -delete`.

**Validation:**
```bash
rhcelab practice B16
ansible managed -a 'crontab -l -u root'
```

**Common mistakes:**
- Omitting `name:` (the module then cannot find the job again, so each run adds a duplicate).
- Swapping `minute` and `hour`.

---

### B17 - Collections

**Objective:** Install the collections `ansible.posix` and `community.general` from
`http://materials.lab.example.com/materials/collections/` into
`/home/ansible/ansible/collections`, and make sure `ansible.cfg` uses that path.

**Expected result:** `ansible-galaxy collection list` shows both under your
workspace path.

**Validation:**
```bash
rhcelab practice B17
ansible-galaxy collection list
```

**Common mistakes:**
- Installing into `~/.ansible/collections` (default) instead of the requested path: use `-p`.
- `collections_paths` (old spelling) vs `collections_path`: both are accepted, but use one consistently.

---

### B18 - Handler basics

**Objective:** Write `b18-handler.yml` for `webservers` that deploys
`/etc/httpd/conf.d/servername.conf` containing
`ServerName {{ ansible_fqdn }}` (rendered) and restarts httpd through a handler only
when the file changes.

**Expected result:** `ServerName managed-node1.lab.example.com`; httpd running;
second run reports no handler.

**Validation:**
```bash
rhcelab practice B18
ssh managed-node1 sudo httpd -t
```

**Common mistakes:**
- `copy` with `content: "ServerName {{ ansible_fqdn }}"` works; a `template` needs a `.j2` file.
- Handler name in `notify` must match exactly (case-sensitive).

---

### B19 - Ad-hoc facts with a filter

**Objective:** Create executable `adhoc-facts.sh` that shows only the
`ansible_distribution*` facts of all managed nodes using the `setup` module.

**Expected result:** output contains `"ansible_distribution": "Rocky"`.

**Validation:**
```bash
rhcelab practice B19
```

**Common mistakes:**
- `filter=distribution` (filters match the fact name including the `ansible_` prefix; use wildcards).

---

### B20 - Debug and magic variables

**Objective:** Write `b20-debug.yml` that prints, for every managed node,
`inventory_hostname` and the list `group_names`.

**Expected result:** output shows `managed-node1` with `['dev', 'managed', 'webservers']` (order may vary).

**Validation:**
```bash
rhcelab practice B20
ansible-playbook b20-debug.yml
```

**Common mistakes:**
- Using `msg:` and `var:` together in one `debug` task (mutually exclusive).
