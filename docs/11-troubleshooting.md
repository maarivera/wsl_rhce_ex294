# 11. Troubleshooting guide

Start every investigation with:

```bash
rhcelab status           # on control-node
rhcelab validate         # which layer is broken?
```

```powershell
wsl --list --verbose     # on Windows: which distributions are running?
```

## 11.1 Deployment

| Symptom | Cause | Fix |
|---|---|---|
| `running scripts is disabled on this system` | PowerShell execution policy | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` (current window only) |
| `$'\r': command not found` / `bad interpreter` | Scripts checked out with CRLF | `git config core.autocrlf input`, re-clone; `New-RhceLab.ps1` normalizes its stage copy anyway |
| `wsl: Unknown option --vhd` | Old inbox WSL | `wsl --update` (Store WSL 2.x) |
| `Lab files must live on a local drive` | Repo on a network share | Clone to `C:\...` |
| dnf fails during golden build | No Internet / proxy | Test `curl -I https://dl.rockylinux.org` inside `wsl -d rocky9-golden -u root`; configure `proxy=` in `/etc/dnf/dnf.conf` |
| `pip install` fails in control-init | PyPI blocked | Set `PIP_INDEX_URL` to a mirror, or re-run `control-init.sh` |
| Collections tarballs missing (L08 fails) | Galaxy unreachable during build | `wsl -d control-node -u root --cd <repo> --exec bash linux/control-init.sh` again |
| Asked to create a UNIX user on first start | Image OOBE ran | Press Ctrl+C; `golden-build.sh` disables OOBE. Rebuild with `-Force` |

## 11.2 Nodes stop by themselves

WSL terminates idle distributions. Keep them running with
`.\windows\Start-RhceLab.ps1` or `rhcelab up`. Check:

```powershell
wsl --list --running
Get-Process wsl | Select-Object Id, StartTime    # hidden keep-alive processes
```

## 11.3 Networking

| Symptom | Diagnosis | Fix |
|---|---|---|
| `ssh: connect to host managed-node1 port 22: No route to host` | Node not running, or bridge missing | `wsl -l --running`; `ip link show rhcebr0` on control-node; `rhcelab up` |
| `Connection refused` on port 22 | sshd not running in the namespace | `wsl -d managed-node1 -u root -- systemctl status rhcelab-net sshd` |
| Node reachable but `dnf` times out | NAT or forwarding broken | on control-node: `sudo nft list table ip rhcelab`, `sysctl net.ipv4.ip_forward`; on node: `ssh managed-node1 curl -I https://dl.rockylinux.org` |
| Docker installed and nodes cannot reach each other or the Internet | Docker set the iptables FORWARD policy to DROP | `sudo iptables -L DOCKER-USER -n` on control-node should show two `rhcelab` ACCEPT rules. If Docker uses **iptables-legacy**, Rocky's nft-based iptables cannot see that table: in the Docker distro run `iptables -I DOCKER-USER -i rhcebr0 -j ACCEPT; iptables -I DOCKER-USER -o rhcebr0 -j ACCEPT` |
| External names do not resolve on managed nodes | DNS server not reachable from the namespace | `ssh managed-node1 cat /etc/resolv.conf`. If it shows an address that only works locally, set `generateResolvConf = false` in the node's `/etc/wsl.conf` and write `nameserver 1.1.1.1` (or your corporate DNS) to `/etc/resolv.conf` |
| `ansible_default_ipv4` shows a 172.x address | You ran the module in the shared namespace (e.g. `wsl -d managed-node1` shell, not SSH) | Always go through SSH/Ansible; `sudo ip netns exec rhcelab bash` for a namespace shell |
| After `wsl --shutdown` nothing works | Bridge is rebuilt by the first node that boots | `.\windows\Start-RhceLab.ps1` |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | Node was re-cloned (new host keys) | `rhcelab known-hosts` |

Repair a node's network by hand (out-of-band):

```powershell
wsl -d managed-node1 -u root -- rhcelab-net status
wsl -d managed-node1 -u root -- systemctl restart rhcelab-net
wsl -d managed-node1 -u root -- systemctl restart sshd firewalld
```

> Restarting `rhcelab-net` is safe: it is idempotent and keeps the namespace that
> sshd and firewalld already use.

## 11.4 SSH and privilege escalation

| Symptom | Fix |
|---|---|
| `Permission denied (publickey)` | Key missing on the node. From Windows: see [04 §4.5](04-ansible-configuration.md#45-ssh-trust), or `.\windows\Reset-RhceLab.ps1 -Components files` |
| `Missing sudo password` | An exercise broke `/etc/sudoers.d/ansible` → `Reset-RhceLab.ps1 -Components files` |
| Locked out by firewalld (`--remove-service ssh`) | `Reset-RhceLab.ps1 -Components firewall` |
| Broken `sshd_config` | `wsl -d managed-node1 -u root -- sshd -t` shows the error; `Reset-RhceLab.ps1 -Components files` |

## 11.5 Ansible

| Symptom | Fix |
|---|---|
| `ansible --version` shows 2.14 | You ran it via `sudo` or `/usr/bin/ansible`. Use `/usr/local/bin/ansible` (default `$PATH`) |
| `config file = None` | You are not in `/home/ansible/ansible`, or the directory is world-writable (`chmod 755`) |
| `couldn't resolve module/action 'ansible.posix.firewalld'` | Install collections (B17/T3) and check `collections_path` |
| `the role 'redhat.rhel_system_roles.timesync' was not found` | `collections_path` must include `/usr/share/ansible/collections` |
| Vault: `Attempting to decrypt but no vault secrets found` | Add `--vault-password-file secret.txt` or `--ask-vault-pass` |
| `sefcontext`: `SELinux is disabled on this host` | WSL kernel: add `ignore_selinux_state: true` and `reload: false` |
| `seboolean` / `seport` fail | Not possible on the WSL kernel; practise on a real VM |
| `reboot` module hangs | Not possible in WSL; use `wsl --terminate <node>` + `rhcelab up` |

## 11.6 systemd

```powershell
wsl -d managed-node1 -u root -- systemctl --failed
wsl -d managed-node1 -u root -- journalctl -b -u rhcelab-net -u rhcelab-storage -u sshd
```

`systemctl is-system-running` reporting `degraded` is normal in WSL when a unit that
expects real hardware fails. It only matters if a lab unit is in the list.

## 11.7 Storage

| Symptom | Fix |
|---|---|
| `Device /dev/loopN excluded by a filter` | The disk is not in the LVM devices file: `sudo lvmdevices --adddev $(...)`; or reset storage |
| VG `research` missing on managed-node1 | `rhcelab reset --only storage` |
| Mount from fstab fails after a WSL restart | Loop numbers may change. Use `/dev/<vg>/<lv>` or `UUID=` in fstab, never `/dev/loopNpM` |
| `vgcreate`: name already in use | device-mapper is shared by all nodes: choose a VG name no other node uses |
| Partition `/dev/loopN1` not found | Loop partitions are named `/dev/loopNp1` |

## 11.8 Disk space and memory

```powershell
Get-ChildItem $env:USERPROFILE\WSL\rhcelab -Recurse -Filter *.vhdx | Select-Object FullName, @{n='GB';e={[math]::Round($_.Length/1GB,1)}}
```

Inside a node, `dnf clean all` frees cache. The VHDX files do not shrink
automatically. After `wsl --shutdown`, compact them with `Optimize-VHD` (Hyper-V
tools) or `diskpart` → `select vdisk file=<path>` → `compact vdisk`.

If dnf transactions get killed, raise `memory=` in `.wslconfig` (see
[03](03-wsl-configuration.md)).

## 11.9 Last resort

```powershell
.\windows\Reset-RhceLab.ps1 -Hard                 # re-clone managed nodes
.\windows\New-RhceLab.ps1 -Force -ReuseGolden     # re-clone everything
```
