# RHCE EX294 practice lab on WSL2 + Rocky Linux 9

A three-node Ansible lab that runs entirely inside WSL2 on Windows 11. It mirrors the
RHCE (EX294) exam environment: a control node, two managed nodes, key-only SSH as a
dedicated `ansible` user, a "materials" web server, 60 practice tasks, a timed
300-point mock exam with an automatic grader, and one-command resets.

| | |
|---|---|
| Nodes | `control-node` 10.10.10.10, `managed-node1` 10.10.10.11, `managed-node2` 10.10.10.12 |
| OS | Rocky Linux 9 (official WSL image), systemd enabled |
| Ansible | ansible-core 2.18 (Python 3.12 venv) + RHEL system roles |
| Automation user | `ansible`, SSH keys only, passwordless sudo |
| Name resolution | `/etc/hosts` on every node (`*.lab.example.com`), no external DNS |

## Architecture

```
 Windows 11 host
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │  WSL2 utility VM (one Linux kernel shared by every distribution)             │
 │                                                                              │
 │  Shared ("root") network namespace: eth0 = WSL NAT to Windows/Internet       │
 │  ┌────────────────────────────────────────────────────────────────────────┐  │
 │  │ rhcebr0  Linux bridge  10.10.10.1/24 (gateway)   nft: ip rhcelab NAT    │  │
 │  │   │                                                                    │  │
 │  │   ├── 10.10.10.10  control-node (distro, stays in the shared namespace) │  │
 │  │   │                ansible-core 2.18, /home/ansible/ansible (workspace) │  │
 │  │   │                httpd → http://materials.lab.example.com/materials/  │  │
 │  │   │                                                                    │  │
 │  │   ├── veth rlv11 ─┐                                                    │  │
 │  │   └── veth rlv12 ─┼─────────────┐                                      │  │
 │  └───────────────────┼─────────────┼──────────────────────────────────────┘  │
 │   ┌──────────────────┴───────┐ ┌───┴──────────────────────┐                  │
 │   │ managed-node1 (distro)   │ │ managed-node2 (distro)   │                  │
 │   │ netns "rhcelab"          │ │ netns "rhcelab"          │                  │
 │   │ eth0 10.10.10.11/24      │ │ eth0 10.10.10.12/24      │                  │
 │   │ sshd firewalld httpd ... │ │ sshd firewalld httpd ... │                  │
 │   │ disk: loop (1 GiB)       │ │ disk: loop (2 GiB)       │                  │
 │   │ VG research (seeded)     │ │ (blank)                  │                  │
 │   └──────────────────────────┘ └──────────────────────────┘                  │
 └──────────────────────────────────────────────────────────────────────────────┘
        control-node ──SSH (key: ~ansible/.ssh/id_ed25519)──▶ managed nodes
```

**Why the network namespaces?** All WSL2 distributions share one kernel *and one
network stack*: same IP address, same ports, same firewall tables. Without
namespaces, two "nodes" cannot both run sshd on port 22, and firewalld on one node
would rewrite the firewall of every distribution, including your daily Ubuntu and
Docker. Each managed node therefore runs its network services in a private network
namespace wired to a lab bridge. That gives each node its own IP, port space and real,
isolated firewalld. See [docs/01-architecture.md](docs/01-architecture.md).

## Quick start

From PowerShell (not as Administrator), in a clone of this repository on a local
drive (e.g. `C:\RHCE\wsl_rhce_ex294`):

```powershell
wsl --update
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\windows\New-RhceLab.ps1            # ~15-25 minutes, ~12 GB disk
wsl -d control-node                  # you are now ansible@control-node
```

Then, inside control-node:

```bash
rhcelab status          # bridge + SSH reachability
rhcelab validate        # 34 environment checks
cd ~/ansible            # your workspace - start with docs/05-practice-beginner.md
```

## Documentation

| # | Document | Contents |
|---|---|---|
| 1 | [Architecture](docs/01-architecture.md) | Diagram, design decisions, what is real vs. simulated on WSL2 |
| 2 | [Deployment guide](docs/02-deployment-guide.md) | Automated and fully manual (copy-paste) PowerShell/WSL setup |
| 3 | [WSL configuration](docs/03-wsl-configuration.md) | `.wslconfig`, `wsl.conf`, cloning, networking, keeping nodes running |
| 4 | [Ansible configuration](docs/04-ansible-configuration.md) | Install, `ansible.cfg`, inventory, SSH trust, connectivity tests |
| 5 | [Practice: beginner](docs/05-practice-beginner.md) | B01-B20 |
| 6 | [Practice: intermediate](docs/06-practice-intermediate.md) | I01-I20 |
| 7 | [Practice: RHCE level](docs/07-practice-rhce.md) | R01-R20 |
| 8 | [Mock exam](docs/08-mock-exam.md) | 4-hour, 18-task, 300-point exam with scoring and checklist |
| 9 | [Reset scripts](docs/09-reset.md) | Soft/hard resets, per-component rebuilds |
| 10 | [Validation scripts](docs/10-validation.md) | Bash and Ansible graders, writing your own checks |
| 11 | [Troubleshooting](docs/11-troubleshooting.md) | Networking, SSH, systemd, storage, Docker side effects |
| 12 | [RHCE exam tips](docs/12-exam-tips.md) | Exam-day strategy, time management, `ansible-doc` drills |
| 13 | [2-week roadmap](docs/13-roadmap.md) | Daily plan, repetitions, readiness criteria |

## Repository layout

```
windows/            PowerShell: New-, Start-, Stop-, Reset-, Remove-RhceLab.ps1
linux/              golden-build.sh, node-init.sh, control-init.sh
linux/files/        files installed on every node (rhcelab-net, -storage, -reset, ...)
lab/                the lab's own ansible.cfg + inventory (graders, reset)
ansible-reference/  reference ansible.cfg + inventory for your workspace
reset/              reset-lab.yml (Ansible) and reset-lab.sh (wrapper)
validate/           check suites (*.tsv), bash + Ansible engines, validate-lab.yml
materials/          files served at http://materials.lab.example.com/materials/
materials-src/      sources for role tarballs, vault file, app archive
solutions/          mock exam reference solution (spoilers) + run-all.sh
docs/               the guides listed above
```

## Daily commands (inside control-node)

| Command | What it does |
|---|---|
| `rhcelab status` | Bridge and SSH reachability |
| `rhcelab up` | Start the managed nodes from inside control-node |
| `rhcelab practice B05` / `I` / `all` | Check practice tasks |
| `rhcelab exam-start` | Archive workspace, reset nodes, remove repos |
| `rhcelab grade` | Grade the mock exam (pass mark 210/300) |
| `rhcelab reset` / `rhcelab reset --only users,firewall` | Reset managed nodes |

## WSL2 limitations you should know

| Exam topic | In this lab |
|---|---|
| SELinux | The WSL2 kernel boots with SELinux **disabled**. `/etc/selinux/config` and persistent file contexts (`sefcontext` with `ignore_selinux_state: true`) work and are graded; booleans and port labels cannot be set. Practise those on a real VM. |
| Reboots | `ansible.builtin.reboot` does not work; restart a node with `wsl --terminate managed-node1` and `rhcelab up`. |
| Disks | Spare disks are loop devices (`ansible_local.rhcelab.disk`), not `/dev/vdb`. VG names must be unique lab-wide (device-mapper is shared). |
| Swap | Swap is VM-wide; avoid swap exercises or remove the swap afterwards. |
| Kernel/bootloader | No kernel, GRUB or `tuned` exercises. |

Everything else (inventories, ad-hoc commands, playbooks, variables, facts,
conditionals, loops, handlers, templates, roles, collections, system roles, vault,
packages, repositories, services, users, cron, LVM, file systems, firewalld,
delegation, tags, error handling) behaves as it does on RHEL.
