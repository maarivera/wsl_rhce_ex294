# 9. Reset scripts

Three layers, from fastest to most thorough:

| Layer | Command | Needs SSH? | Time | Restores |
|---|---|---|---|---|
| Ansible (control-node) | `rhcelab reset` | yes | 1-3 min | baseline config, packages, users, storage ... |
| Out-of-band (Windows) | `.\windows\Reset-RhceLab.ps1` | no | 1-3 min | same, via `wsl.exe -u root` |
| Hard (Windows) | `.\windows\Reset-RhceLab.ps1 -Hard` | no | ~1 min/node | everything: re-clone from golden VHDX |

All soft resets run the same script, `/usr/local/sbin/rhcelab-reset`, on the node.
It compares the node with the **baseline captured right after the build**
(`/var/lib/rhcelab/baseline/`), so it removes whatever an exercise added without a
hard-coded list of packages or users.

## 9.1 From control-node

```bash
rhcelab reset                               # both nodes, everything
rhcelab reset --only users,firewall         # selected components
rhcelab reset --node managed-node2          # one node
rhcelab reset --exam                        # everything, then remove repo files
rhcelab reset --workspace                   # also archive + empty ~/ansible
rhcelab exam-start                          # = --workspace --exam
```

Or directly with Ansible:

```bash
cd /opt/rhcelab
ANSIBLE_CONFIG=lab/ansible.cfg ansible-playbook reset/reset-lab.yml
ANSIBLE_CONFIG=lab/ansible.cfg ansible-playbook reset/reset-lab.yml --tags packages,services
ANSIBLE_CONFIG=lab/ansible.cfg ansible-playbook reset/reset-lab.yml -e exam_mode=true
```

Workspace archives go to `~/workspace-backups/ansible-<timestamp>.tar.gz`.

## 9.2 From Windows (when SSH is broken)

Typical cases: an exercise broke `sshd_config`, removed the `ansible` user's key,
blocked SSH in firewalld, or uninstalled `sudo`.

```powershell
.\windows\Reset-RhceLab.ps1                                  # soft, both nodes
.\windows\Reset-RhceLab.ps1 -Node managed-node1 -Components files,firewall
.\windows\Reset-RhceLab.ps1 -Exam                            # soft + remove repos
.\windows\Reset-RhceLab.ps1 -Hard -Node managed-node2        # re-clone
```

Single command without the script:

```powershell
wsl -d managed-node1 -u root -- rhcelab-reset all
```

## 9.3 Components

| Component | What it rebuilds |
|---|---|
| `repos` | Restores `/etc/yum.repos.d` and `dnf.conf` from the baseline, `dnf clean all` |
| `services` | Disables and stops every service/socket/timer that was not enabled in the baseline; re-enables baseline units |
| `storage` | Unmounts and swaps off anything on the node's lab disks, removes VGs/PVs/partitions, wipes and re-creates the loop disks, re-seeds VG `research` on managed-node1, restores `/etc/fstab` and LVM config |
| `packages` | Removes extra package groups, removes extra *user-installed* packages and their now-unused dependencies, reinstalls missing baseline packages |
| `users` | Deletes users, groups and home directories that are not in the baseline |
| `cron` | Restores crontabs, `/etc/cron.d`, `cron.allow/deny`, removes `at` jobs |
| `files` | Restores tracked configuration (hosts, motd, issue, sudoers, sysctl, profile.d, limits, systemd units, sshd config, chrony, login.defs, the ansible user's `~/.ssh`), removes custom facts and the paths in `/etc/rhcelab/reset-paths.conf` |
| `firewall` | Restores `/etc/firewalld`, ensures firewalld is installed, enabled and reloaded |
| `selinux` | Restores `/etc/selinux/config`, removes local fcontext/boolean/port customizations |
| `--exam` | Moves all `*.repo` files to `/var/lib/rhcelab/stashed-repos` (the next reset brings them back) |

`all` runs them in a safe order: repos → services → storage → packages → users → cron
→ files → firewall → selinux → re-enable baseline units.

Log: `/var/log/rhcelab-reset.log` on each node.

## 9.4 Adding your own artifacts

Exercises you invent may create files outside the tracked paths. Add them (globs
allowed) to `/etc/rhcelab/reset-paths.conf` on the managed nodes:

```bash
ansible managed -b -m ansible.builtin.lineinfile -a "path=/etc/rhcelab/reset-paths.conf line=/opt/myapp"
```

To make the change permanent across hard resets, add the path to
`linux/files/etc/rhcelab/reset-paths.conf` in the repository and rebuild the golden
image (`New-RhceLab.ps1 -Force`).

## 9.5 Re-capturing the baseline

If you deliberately change the baseline (for example to pre-install a package for
every exercise), re-capture it on the node:

```bash
ssh managed-node1 sudo rhcelab-baseline capture
```

## 9.6 Rebuilding the whole lab

```powershell
.\windows\New-RhceLab.ps1 -Force -ReuseGolden   # re-clone all nodes (keeps golden image)
.\windows\New-RhceLab.ps1 -Force                # also rebuild the golden image (latest updates)
```
