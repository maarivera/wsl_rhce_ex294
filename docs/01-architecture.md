# 1. Architecture

## 1.1 Topology

```
                         Internet (dl.rockylinux.org, galaxy.ansible.com)
                                        ▲
                                        │ Windows NAT
 ┌──────────────────────────────────────┼───────────────────────────────────────┐
 │ WSL2 utility VM  (kernel 6.x-microsoft-standard-WSL2, shared by all distros)  │
 │                                      │                                        │
 │  shared network namespace      eth0 172.x.x.x (WSL NAT)                       │
 │   ├─ nft table "ip rhcelab": masquerade 10.10.10.0/24 → eth0                  │
 │   └─ rhcebr0 (Linux bridge) 10.10.10.1/24 ── the lab "switch"                 │
 │        │                                                                      │
 │        ├─ 10.10.10.10/24 (address on the bridge)                              │
 │        │    control-node   processes run in the shared namespace              │
 │        │                   httpd listens on 10.10.10.10:80 only               │
 │        │                                                                      │
 │        ├─ rlv11 ══ veth ══ eth0 10.10.10.11/24 ┐ managed-node1                 │
 │        │                     netns "rhcelab"   │  sshd, firewalld, httpd,      │
 │        │                                       ┘  crond, chronyd, mariadb ...  │
 │        └─ rlv12 ══ veth ══ eth0 10.10.10.12/24 ┐ managed-node2                 │
 │                              netns "rhcelab"   ┘  (same list)                  │
 │                                                                               │
 │  /dev (devtmpfs) is shared too:                                               │
 │     /var/lib/rhcelab/disks/managed-node1-disk1.img → /dev/loopN → PV → VG research
 │     /var/lib/rhcelab/disks/managed-node2-disk1.img → /dev/loopM (blank)        │
 └───────────────────────────────────────────────────────────────────────────────┘
```

| Node | Role | IP | Services | Spare disk |
|---|---|---|---|---|
| control-node | Ansible control node, materials server | 10.10.10.10 | httpd (materials) | - |
| managed-node1 | Managed node, group `dev` | 10.10.10.11 | sshd, firewalld, crond, atd | 1 GiB, VG `research` |
| managed-node2 | Managed node, group `prod` | 10.10.10.12 | sshd, firewalld, crond, atd | 2 GiB, blank |

Names resolve from `/etc/hosts` on every node (`generateHosts = false` in
`/etc/wsl.conf`):

```
10.10.10.1  lab-gateway.lab.example.com lab-gateway
10.10.10.10 control-node.lab.example.com control-node materials.lab.example.com
10.10.10.11 managed-node1.lab.example.com managed-node1
10.10.10.12 managed-node2.lab.example.com managed-node2
```

## 1.2 The core problem: WSL2 distributions are not VMs

Every WSL2 distribution is a set of Linux namespaces (mount, PID, UTS) inside the
**same** lightweight VM. They do **not** get their own network namespace. Verified
on this lab's target kernel:

| Shared resource | Consequence for a naive 3-distro lab | How the lab solves it |
|---|---|---|
| Network namespace (IP, ports, routes) | All "nodes" have the same IP; only one sshd can bind :22; `ansible_default_ipv4` is identical everywhere | Per-node network namespace + veth + bridge (`rhcelab-net`) |
| netfilter/nftables | firewalld on node A rewrites the firewall of node B, your Ubuntu distro and Docker | firewalld runs *inside* each node's namespace, so its rules are isolated and real |
| `/dev` (one devtmpfs) | Every node sees every block device | Loop-backed disks + LVM devices file per node (`rhcelab-storage`) |
| Kernel LSM | SELinux compiled in but not enabled at boot | Userspace configured; graded via config files (see 1.5) |
| Swap | One VM-wide swap | Swap exercises avoided |

### How a managed node gets its own network stack

1. `rhcelab-net.service` (early boot) creates the bridge if it does not exist yet,
   loads the NAT table, creates network namespace `rhcelab` and moves one end of a
   veth pair into it as `eth0` with the node's IP and default route `10.10.10.1`.
2. `node-init.sh` installs a systemd drop-in for every network-facing service:

   ```ini
   # /etc/systemd/system/sshd.service.d/10-rhcelab-netns.conf
   [Unit]
   Requires=rhcelab-net.service
   After=rhcelab-net.service

   [Service]
   NetworkNamespacePath=/run/netns/rhcelab
   ```

   Covered services: sshd, firewalld, httpd, nginx, php-fpm, mariadb, mysqld,
   postgresql, vsftpd, postfix, crond, atd, chronyd, named, smb, nmb, nfs-server and
   rsyslog. Drop-ins for packages that are not installed yet are harmless; they apply
   as soon as an exercise installs the package.
3. Ansible connects through sshd, so **every module runs in the node's namespace**:
   facts show `eth0 10.10.10.11`, `firewall-cmd` manages that node's own firewall,
   and `httpd` on managed-node1 does not collide with `httpd` on managed-node2.

> `wsl -d managed-node1` opens a shell in the *shared* namespace (WSL starts it,
> not systemd). Use it for out-of-band repair. To look at the node the way Ansible
> does, use `ssh managed-node1` from control-node, or
> `sudo ip netns exec rhcelab bash` inside the node.

### Why the control node stays in the shared namespace

Your interactive shell (`wsl -d control-node`) is started by WSL, not by systemd, so
it would always land in the shared namespace anyway. The control node therefore
simply owns 10.10.10.10 on the bridge. For the same reason **firewalld is masked and
sshd disabled on control-node**: they would act on the namespace that every other
WSL distribution uses.

## 1.3 Golden image and cloning

```
Rocky-9-WSL-Base.latest.x86_64.wsl (official, SHA256-verified)
        │ wsl --import rocky9-golden
        ▼
rocky9-golden ── golden-build.sh: dnf update, base packages, ansible user,
        │        sshd key-only, lab scripts/units, generalize (machine-id, host keys)
        │ wsl --export --vhd  →  golden\rocky9-golden.vhdx
        ▼
wsl --import <node> <dir> rocky9-golden.vhdx --vhd      (x3, no tar extraction)
        │ node-init.sh: hostname, /etc/hosts, lab.conf, netns drop-ins,
        │               new machine-id + SSH host keys
        ▼
control-init.sh (control-node): ansible-core venv, rhel-system-roles, materials server
Grant-LabTrust: control's public key → managed nodes (out-of-band via wsl.exe)
rhcelab-baseline capture: reset reference for every managed node
```

The golden VHDX is kept, so a broken node is re-cloned in about a minute
(`Reset-RhceLab.ps1 -Hard`).

## 1.4 Exam fidelity

| Exam environment | This lab |
|---|---|
| `control.lab.example.com` + 4-5 managed nodes | `control-node` + 2 managed nodes (groups map onto them) |
| User `student`/`greg` with key-based SSH | User `ansible`, key-only SSH, NOPASSWD sudo |
| Materials on `http://classroom/materials` | `http://materials.lab.example.com/materials/` |
| Repositories provided by the classroom | Rocky mirrors (`dl.rockylinux.org`); `--exam` reset removes repo files |
| ansible-core 2.14 + ansible-navigator | ansible-core 2.18 (2.14 RPM also present via rhel-system-roles); navigator optional |
| `/dev/vdb`, `/dev/vdc` spare disks | Loop devices, path in `ansible_local.rhcelab.disk` |
| SELinux enforcing | SELinux disabled by the WSL kernel (see 1.5) |

## 1.5 What is real and what is simulated

**Real:** SSH, sudo, facts, dnf and repositories, systemd services, users, groups,
passwords, cron, at, firewalld (isolated, actually filtering traffic between nodes),
httpd/php-fpm/MariaDB, LVM, partitions, XFS/ext4, mounts and fstab, templates, roles,
collections, system roles (timesync), vault, delegation.

**Simulated:**

* **SELinux** is configured but not enforced. `ansible.posix.selinux` writes
  `/etc/selinux/config` (it reports "reboot required"). `community.general.sefcontext`
  needs `ignore_selinux_state: true` and writes the persistent rule into
  `file_contexts.local`. `restorecon` is a no-op. Booleans (`seboolean`) and port
  labels (`seport`) fail on a kernel without SELinux, so practise those on a real
  RHEL/Rocky VM.
* **Reboots**: `ansible.builtin.reboot` cannot reboot a WSL distribution.
* **Disks** are loop devices; `/dev` is shared, so `lsblk` shows every node's
  devices. Never touch a device that is not in `ansible_local.rhcelab.disks`.
