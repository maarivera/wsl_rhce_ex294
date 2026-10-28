# 8. Mock RHCE exam (EX294 style)

**Duration:** 4 hours · **Tasks:** 18 · **Points:** 300 · **Pass mark:** 210 (70%)

## 8.1 Before you start (not part of the exam time)

```bash
rhcelab exam-start      # archives ~/ansible, resets both nodes, REMOVES repo files
rhcelab status          # both nodes reachable
```

Then set a 4-hour timer. Do not open the `solutions/` directory, the internet or
these docs (except this page). `ansible-doc`, `man`, and
`/usr/share/doc/rhel-system-roles/` are allowed, as on the real exam.

## 8.2 Candidate instructions

* Work as user `ansible` on `control-node`. All files you create must be in
  `/home/ansible/ansible` unless a task says otherwise.
* Playbooks are graded by their **result on the managed nodes**, and by the files
  in your workspace. Your work must survive a re-run (be idempotent where possible).
* All playbooks must run with `ansible-playbook <file>` from `/home/ansible/ansible`
  (vault tasks: with `--vault-password-file secret.txt`).
* Use the inventory and configuration you create in task 1, not `/opt/rhcelab`.
* The managed nodes have **no repositories** until you complete task 2.
* Read every task completely before you start it. Tasks are not ordered by difficulty.
* WSL note: SELinux is disabled by the WSL kernel. Where a task asks for SELinux file
  contexts, use `ignore_selinux_state: true` (and `reload: false`) on
  `community.general.sefcontext`. The persistent rule is what is graded.

## 8.3 Environment

| Item | Value |
|---|---|
| Control node | `control-node.lab.example.com` (10.10.10.10) |
| Managed nodes | `managed-node1.lab.example.com` (10.10.10.11), `managed-node2.lab.example.com` (10.10.10.12) |
| User | `ansible`, SSH keys installed, passwordless sudo on the managed nodes |
| Materials | `http://materials.lab.example.com/materials/` |
| Repositories | BaseOS `http://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/`, AppStream `http://dl.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/` |
| GPG key | `https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9` |
| RHEL system roles | installed on control-node (`/usr/share/ansible/`) |
| Spare storage | managed-node1 has volume group `research` (about 1 GiB) |

## 8.4 Tasks

### Task 1 - Install and configure Ansible (20 points)

Ansible is installed on control-node. Configure it:

* Create the static inventory `/home/ansible/ansible/inventory`:
  * `managed-node1` is a member of group `dev`
  * `managed-node2` is a member of group `prod`
  * group `prod` is a member of group `webservers`
* Create `/home/ansible/ansible/ansible.cfg`:
  * the default inventory is `/home/ansible/ansible/inventory`
  * the remote user is `ansible`, privilege escalation is enabled by default
  * the default roles directory is `/home/ansible/ansible/roles` (keep
    `/usr/share/ansible/roles` available as well)
  * the default collections directory is `/home/ansible/ansible/mycollections`
    (keep `/usr/share/ansible/collections` available as well)

### Task 2 - Yum repositories with ad-hoc commands (15 points)

Create the executable script `/home/ansible/ansible/adhoc.sh` that uses **Ansible
ad-hoc commands** to configure two repositories on every managed node:

| | Repository 1 | Repository 2 |
|---|---|---|
| name | `EX294_BASE` | `EX294_STREAM` |
| description | `EX294 base software` | `EX294 stream software` |
| baseurl | BaseOS URL from 8.3 | AppStream URL from 8.3 |
| GPG check | enabled | enabled |
| GPG key | key URL from 8.3 | key URL from 8.3 |
| enabled | yes | yes |

Run the script.

### Task 3 - Install collections (10 points)

Install these collections into `/home/ansible/ansible/mycollections`:

* `http://materials.lab.example.com/materials/collections/ansible-posix.tar.gz`
* `http://materials.lab.example.com/materials/collections/community-general.tar.gz`

### Task 4 - Install packages (20 points)

Create `/home/ansible/ansible/packages.yml` that:

* installs `php` and `mariadb` on the hosts in `dev` and `prod`
* installs the package group `RPM Development Tools` on the hosts in `dev`
* updates all packages to the latest version on the hosts in `dev`

### Task 5 - Use a RHEL system role (15 points)

Create `/home/ansible/ansible/timesync.yml` that uses the RHEL `timesync` system role
on all managed nodes to synchronize time with `pool.ntp.org` with `iburst` enabled.

### Task 6 - Install roles with a requirements file (15 points)

Create `/home/ansible/ansible/roles/requirements.yml` and use it to install into
`/home/ansible/ansible/roles`:

* `http://materials.lab.example.com/materials/roles/phpinfo.tar.gz` as role `phpinfo`
* `http://materials.lab.example.com/materials/roles/motd.tar.gz` as role `motd`

### Task 7 - Use the installed roles (15 points)

Create `/home/ansible/ansible/roles.yml` that:

* applies role `phpinfo` to the hosts in `webservers`. Afterwards
  `http://managed-node2/info.php` must show
  `Hello PHP World from managed-node2.lab.example.com` (rendered by PHP).
* applies role `motd` to all managed nodes with the message
  `Managed by Ansible - EX294 lab` (read the role's defaults for the variable name).

### Task 8 - Create a role (25 points)

Create role `apache` in `/home/ansible/ansible/roles` that:

* installs `httpd` and `firewalld`; starts and enables both
* allows the `http` service in the firewall, permanently and immediately
* deploys `/etc/httpd/conf.d/servername.conf` from a template containing
  `ServerName <FQDN>`; when this file changes, httpd is restarted **by a handler**
* deploys `/var/www/html/index.html` from a template whose content is exactly:
  `Welcome to HOSTNAME on IPADDRESS`, where HOSTNAME is the node's fully qualified
  domain name and IPADDRESS its default IPv4 address

Create `/home/ansible/ansible/apache.yml` that applies the role to `webservers`.

### Task 9 - Logical volumes (20 points)

Create `/home/ansible/ansible/lv.yml` that runs on all managed nodes and:

* creates logical volume `data` of 1500 MiB in volume group `research`
* if the volume group lacks space, prints the message
  `Could not create logical volume of that size` and creates the LV with 800 MiB instead
* if volume group `research` does not exist, prints the message
  `Volume group does not exist`
* formats the logical volume with `ext4`
* does **not** mount the logical volume

### Task 10 - Generate a hosts file (15 points)

* Download `http://materials.lab.example.com/materials/hosts.j2` to
  `/home/ansible/ansible/hosts.j2` and complete it so that it produces one line per
  managed node in the inventory, in the format
  `IPADDRESS FQDN SHORTHOSTNAME` (default IPv4 address, separated by single spaces).
* Create `/home/ansible/ansible/hosts.yml` that deploys the result to `/etc/myhosts` on
  the hosts in `dev` only.

### Task 11 - Modify file content (10 points)

Create `/home/ansible/ansible/issue.yml` that sets the content of `/etc/issue` to:

* `Development` on the hosts in `dev`
* `Production` on the hosts in `prod`

### Task 12 - Web content directory (20 points)

Create `/home/ansible/ansible/webcontent.yml` that runs on the hosts in `dev` and:

* creates directory `/webdev` owned by group `webdev` (create the group), with
  permissions `rwxrwsr-x`
* gives `/webdev` and everything below it the SELinux type `httpd_sys_content_t`,
  persistently
* creates `/webdev/index.html` containing `Development`
* creates the symbolic link `/var/www/html/webdev` → `/webdev`
* makes `http://managed-node1/webdev/` show `Development` when requested from
  control-node (httpd running and enabled, firewall open)

### Task 13 - Hardware report (20 points)

Create `/home/ansible/ansible/hwreport.yml` that on all managed nodes:

* downloads `http://materials.lab.example.com/materials/hwreport.empty` to
  `/root/hwreport.txt`
* fills in: inventory host name, total memory in MiB, BIOS version, size of disk
  `vda`, size of disk `vdb`
* every line keeps its `KEY=` prefix; a value that cannot be determined (for example
  a missing disk) is written as `NONE`

### Task 14 - Create an encrypted variable file (20 points)

* Create `/home/ansible/ansible/locker.yml` encrypted with Ansible Vault, containing:
  * `pw_developer` with value `Imadev`
  * `pw_manager` with value `Imamgr`
* The vault password is `whenyouwishuponastar`, stored in
  `/home/ansible/ansible/secret.txt`.

### Task 15 - Create user accounts (25 points)

Download `http://materials.lab.example.com/materials/user_list.yml` to
`/home/ansible/ansible/`. Create `/home/ansible/ansible/users.yml` that uses
`locker.yml` (task 14) and `user_list.yml` to:

* create every user whose job is `developer` on the hosts in `dev`, with the UID from
  the list, supplementary group `devops`, and the password `pw_developer`
* create every user whose job is `manager` on the hosts in `prod`, with the UID from
  the list, supplementary group `opsmgr`, and the password `pw_manager`
* hash passwords with SHA-512; passwords must expire after at most 30 days

### Task 16 - Rekey a vault file (10 points)

Download `http://materials.lab.example.com/materials/salaries.yml` to
`/home/ansible/ansible/salaries.yml`. Its current vault password is `insecure8sure`.
Change it to `bbs2you9527`.

### Task 17 - Scheduled job (15 points)

Create `/home/ansible/ansible/cron.yml` that on all managed nodes creates a cron job
for user `natasha` (create the user if needed) that runs
`logger "EX294 in progress"` every 2 minutes.

### Task 18 - Report with error handling and delegation (10 points)

Create `/home/ansible/ansible/report.yml` that on all managed nodes:

1. runs `systemctl is-active httpd` and registers the result. The task must never
   fail and never report `changed`. Tag: `status`.
2. using delegation, writes a line `<inventory_hostname>: <result>` for every node into
   `/home/ansible/ansible/httpd_status.txt` on control-node (`unknown` if there is no
   output). Tag: `status`.
3. in a block, stops the service `rhce-nonexistent`; when that fails, a rescue section
   writes `rescued` to `/root/rescue.txt`. Tag: `recovery`.

Run it last.

## 8.5 Scoring criteria

| Task | Points | Graded on |
|---|---|---|
| 1 | 20 | files exist (2), dev/prod membership (3), webservers children (3), remote_user (2), roles_path (3), collections_path (2), become (2), `ansible all -m ping` (3) |
| 2 | 15 | script uses `yum_repository` (3), repo files on each node (8), both repos enabled (4) |
| 3 | 10 | each collection present in `mycollections` (5+5) |
| 4 | 20 | file (2), php+mariadb on both nodes (6), group on dev (4), not on prod (3), dev fully updated (5) |
| 5 | 15 | uses the system role (3), chrony server line on both (8), chronyd enabled on both (4) |
| 6 | 15 | requirements file (3), each role installed (6+6) |
| 7 | 15 | file (2), PHP page rendered (7), motd on both (6) |
| 8 | 25 | role structure (4), handler notified (2), playbook (2), httpd (3), firewall (3), ServerName (3), index page via HTTP (8) |
| 9 | 20 | file (2), LV size 800 MiB (6), ext4 (6), not mounted (3), both messages present (3) |
| 10 | 15 | files (2), node1 line (5), node2 line (5), not on prod (3) |
| 11 | 10 | file (2), each node content (4+4) |
| 12 | 20 | dir/group/mode (4), index (3), link (3), SELinux rule (3), httpd (2), HTTP from control (5) |
| 13 | 20 | per node: file, HOST, MEMORY, BIOS, NONE disks (2 each) |
| 14 | 20 | secret.txt (4), encrypted (4), each variable (6+6) |
| 15 | 25 | uses locker (1); per node: right users/UIDs/group (4), wrong users absent (3), password (4), max age (1) |
| 16 | 10 | opens with the new password (7), old password rejected (3) |
| 17 | 15 | file (1), job on each node (7+7) |
| 18 | 10 | tags + delegation (2), status lines (4), rescue on each node (2+2) |
| **Total** | **300** | **Pass: 210** |

Grade at any time (it does not change anything):

```bash
rhcelab grade                 # bash grader
rhcelab grade-ansible         # the same checks via Ansible
rhcelab grade T08,T09         # selected tasks
```

The real exam reveals only your total per objective, after the exam. Resist grading
until the 4 hours are over.

## 8.6 Verification checklist (last 20 minutes)

- [ ] `ansible-inventory --graph` shows dev, prod, webservers→prod
- [ ] `ansible all -m ping` from `/home/ansible/ansible` works without prompts
- [ ] Every playbook passes `ansible-playbook --syntax-check <file>`
- [ ] Every playbook re-runs without failures (`changed` may be > 0 for `password_hash`)
- [ ] `dnf repolist` on both nodes shows EX294_BASE and EX294_STREAM
- [ ] `curl http://managed-node2/`, `curl http://managed-node2/info.php`,
      `curl http://managed-node1/webdev/` from control-node
- [ ] `ansible-vault view --vault-password-file secret.txt locker.yml`
- [ ] `ansible-vault view salaries.yml` asks for and accepts `bbs2you9527`
- [ ] `ssh managed-node1 sudo lvs research` shows `data`, not mounted
- [ ] `ssh managed-node1 sudo crontab -l -u natasha`
- [ ] `cat httpd_status.txt` has two lines
- [ ] No file names misspelled (`users.yml`, `lv.yml`, `hwreport.yml` ...)

## 8.7 After the exam

```bash
rhcelab grade                                    # score + per-task breakdown
less ~/rhcelab-reports/exam-*.txt                # saved reports
less /opt/rhcelab/solutions/mock-exam/*.yml      # reference solution
```

Self-test of the lab: `rhcelab exam-start && /opt/rhcelab/solutions/mock-exam/run-all.sh`
should end with `TOTAL: 300 / 300  PASS`.
