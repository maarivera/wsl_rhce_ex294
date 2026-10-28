# 3. WSL configuration

## 3.1 `%USERPROFILE%\.wslconfig` (Windows, VM-wide)

```ini
[wsl2]
memory=6GB
processors=4
swap=4GB
networkingMode=nat
```

* `memory`: three systemd-based nodes plus dnf transactions need about 4-6 GB.
* `networkingMode=nat` is the default; the lab bridge and NAT are designed for it.
  Mirrored mode may work but is not supported by the lab scripts.
* Apply changes with `wsl --shutdown`. This also stops the lab; start it again with
  `.\windows\Start-RhceLab.ps1`.

## 3.2 `/etc/wsl.conf` (per distribution)

Written by `golden-build.sh` and personalized by `node-init.sh`:

```ini
[boot]
systemd = true            # real systemd: services, timers, cron, firewalld

[user]
default = ansible         # `wsl -d <node>` logs in as the automation user

[network]
hostname = managed-node1  # node-init.sh sets this per node
generateHosts = false     # /etc/hosts is managed by the lab
generateResolvConf = true # WSL keeps DNS working (incl. DNS tunneling)

[interop]
enabled = true            # control-node uses wsl.exe for `rhcelab up`
appendWindowsPath = false # keep Windows paths out of $PATH
```

`wsl.conf` changes take effect after `wsl --terminate <node>`.

## 3.3 Efficient cloning

| Method | Command | Speed | Notes |
|---|---|---|---|
| tar export/import | `wsl --export golden g.tar` / `wsl --import n dir g.tar` | slow (extracts every file) | portable |
| **VHD export/import** (used) | `wsl --export golden g.vhdx --vhd` / `wsl --import n dir g.vhdx --vhd` | fast (block copy) | keeps the golden VHDX for hard resets |
| In-place import | `Copy-Item g.vhdx dir\ext4.vhdx` / `wsl --import-in-place n dir\ext4.vhdx` | fastest | you manage the copies yourself |

Every clone is generalized by `node-init.sh`:

```bash
rm -f /etc/machine-id && systemd-machine-id-setup   # unique machine-id
rm -f /etc/ssh/ssh_host_* && ssh-keygen -A          # unique SSH host keys
```

Without this, all nodes would share SSH host keys (known_hosts confusion) and the
same machine-id (journald, DHCP-style identifiers).

## 3.4 Networking

### Why not just use the WSL IP?

`ip addr` shows the same `eth0` address in every distribution: they share one network
namespace. WSL2 offers no per-distribution IP and the NAT address changes on every
WSL restart. The lab therefore builds its own static network:

| Component | Where | Created by |
|---|---|---|
| Bridge `rhcebr0`, 10.10.10.1/24 | shared namespace | first lab node to boot |
| nft table `ip rhcelab` (masquerade + forward accept) | shared namespace | every lab node at boot (idempotent) |
| `net.ipv4.ip_forward=1` | shared namespace | every lab node at boot |
| netns `rhcelab`, `eth0` 10.10.10.1x/24, default via 10.10.10.1 | managed node | `rhcelab-net` |
| 10.10.10.10/24 on `rhcebr0` | shared namespace | control-node's `rhcelab-net` |
| DOCKER-USER accept rules for `rhcebr0` | shared namespace | only if Docker's chain exists |

Inspect it:

```bash
# on control-node (shared namespace)
ip -br addr show rhcebr0
bridge link
sudo nft list table ip rhcelab

# on a managed node, as Ansible sees it
ssh managed-node1 ip -br addr
ssh managed-node1 ip route
ssh managed-node1 sudo firewall-cmd --list-all
```

### DNS

Lab names come from `/etc/hosts`. External names use WSL's generated
`/etc/resolv.conf`. With DNS tunneling (`nameserver 10.255.255.254`) that address
lives in the shared namespace, and the managed nodes reach it through the bridge.

### Static vs. dynamic

All lab addresses are static and independent of the WSL NAT address, so nothing
needs to be updated when Windows or WSL restarts.

## 3.5 Keeping nodes running

WSL terminates a distribution a few seconds after its last client process exits,
even with systemd enabled. A stopped managed node is simply unreachable (like a
powered-off server). Ways to keep nodes up:

```powershell
.\windows\Start-RhceLab.ps1          # hidden "sleep infinity" per node
```

```bash
rhcelab up                           # same, from inside control-node (WSL interop)
```

Check from Windows:

```powershell
wsl --list --running
```

Restarting a node (the WSL equivalent of a reboot):

```powershell
wsl --terminate managed-node1
.\windows\Start-RhceLab.ps1 -NoShell
```

## 3.6 Useful WSL commands

| Task | Command |
|---|---|
| List lab distributions | `wsl -l -v` |
| Shell on a node as ansible | `wsl -d managed-node1` |
| Root shell on a node (out-of-band) | `wsl -d managed-node1 -u root` |
| Run one command | `wsl -d managed-node1 -u root -- systemctl status sshd` |
| Stop one node | `wsl --terminate managed-node1` |
| Stop all of WSL | `wsl --shutdown` |
| Disk usage of a node | `Get-Item $env:USERPROFILE\WSL\rhcelab\nodes\managed-node1\ext4.vhdx` |
| Compact a VHDX (after `wsl --shutdown`, elevated) | `Optimize-VHD -Path <ext4.vhdx> -Mode Full` (needs Hyper-V tools) |
