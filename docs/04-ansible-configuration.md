# 4. Ansible configuration

## 4.1 Installation (done by `control-init.sh`)

Rocky Linux 9 AppStream ships ansible-core **2.14**. To get 2.15+ the lab installs
ansible-core from PyPI into a Python 3.12 virtual environment:

```bash
sudo dnf -y install python3.12 python3.12-pip rhel-system-roles
sudo python3.12 -m venv /opt/ansible
sudo /opt/ansible/bin/pip install --upgrade pip
sudo /opt/ansible/bin/pip install 'ansible-core>=2.16,<2.19'
for t in /opt/ansible/bin/ansible /opt/ansible/bin/ansible-*; do sudo ln -sfn "$t" /usr/local/bin/; done
ansible --version
```

Why `<2.19`: ansible-core 2.18 is the newest release that supports **Python 3.9 on the
managed nodes** (Rocky 9's platform Python). Later releases drop it, and 2.19 also
changed templating behaviour in ways that break many exam-style playbooks.

`rhel-system-roles` (AppStream) installs the `redhat.rhel_system_roles` collection
under `/usr/share/ansible/collections` and the legacy `rhel-system-roles.*` roles
under `/usr/share/ansible/roles`. It may also pull in the AppStream ansible-core 2.14
in `/usr/bin`. That copy is harmless because `/usr/local/bin` comes first in `$PATH`.
Do not run `sudo ansible-playbook`: sudo's `secure_path` would pick 2.14.

Optional extras:

```bash
sudo /opt/ansible/bin/pip install ansible-navigator ansible-lint
sudo ln -sfn /opt/ansible/bin/ansible-navigator /usr/local/bin/
sudo ln -sfn /opt/ansible/bin/ansible-lint /usr/local/bin/
ansible-navigator run site.yml -m stdout --ee false   # no container engine needed
```

## 4.2 Workspace layout

```
/home/ansible/ansible/        <- your exam workspace (empty after `rhcelab exam-start`)
├── ansible.cfg
├── inventory
├── roles/
├── collections/  (practice)  or  mycollections/ (mock exam)
├── group_vars/  host_vars/
└── *.yml
/opt/rhcelab/                 <- lab tooling (read-only for you)
├── lab/ansible.cfg, lab/inventory   (graders and reset; independent of your files)
├── reset/  validate/  solutions/  docs/
```

## 4.3 Inventory

Reference: [`ansible-reference/inventory`](../ansible-reference/inventory) (practice
groups). Type it yourself; that is task B01.

```ini
[dev]
managed-node1

[prod]
managed-node2

[webservers]
managed-node1

[dbservers]
managed-node2

[managed:children]
dev
prod
```

Verify:

```bash
cd ~/ansible
ansible-inventory --graph
ansible-inventory --host managed-node1
ansible managed --list-hosts
```

YAML equivalent (both formats appear on the exam):

```yaml
all:
  children:
    managed:
      children:
        dev:
          hosts:
            managed-node1:
        prod:
          hosts:
            managed-node2:
    webservers:
      hosts:
        managed-node1:
    dbservers:
      hosts:
        managed-node2:
```

## 4.4 ansible.cfg

Reference: [`ansible-reference/ansible.cfg`](../ansible-reference/ansible.cfg).

```ini
[defaults]
inventory = /home/ansible/ansible/inventory
remote_user = ansible
roles_path = /home/ansible/ansible/roles:/usr/share/ansible/roles
collections_path = /home/ansible/ansible/collections:/usr/share/ansible/collections
host_key_checking = False
forks = 5

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False
```

| Setting | Why |
|---|---|
| `inventory` | absolute path, so commands work from any directory that uses this config |
| `remote_user` | the automation user on the managed nodes |
| `roles_path` | your roles first, then the RHEL system roles |
| `collections_path` | Galaxy collections you install, then `redhat.rhel_system_roles` |
| `host_key_checking` | known_hosts is pre-populated; disabling avoids prompts after node rebuilds |
| `become*` | most exam tasks need root on the managed nodes |

Configuration precedence (highest first): `ANSIBLE_CONFIG` env var →
`./ansible.cfg` → `~/.ansible.cfg` → `/etc/ansible/ansible.cfg`. Check which file is
in effect and what you changed:

```bash
ansible --version | grep 'config file'
ansible-config dump --only-changed
```

> Never export `ANSIBLE_CONFIG` in your shell profile; the lab tooling sets it only
> for its own commands.

## 4.5 SSH trust

The trust is created at build time (public key installed out-of-band). To inspect or
redo it:

```bash
ls -l ~/.ssh/                       # id_ed25519, id_ed25519.pub, known_hosts
ssh managed-node1 hostname          # no password prompt
ssh managed-node1 sudo -n true && echo "passwordless sudo OK"
rhcelab known-hosts                 # after a node is re-cloned (new host keys)
```

Password logins are disabled on purpose:

```bash
ssh -o PubkeyAuthentication=no managed-node1     # -> Permission denied (publickey)
ssh managed-node1 sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin'
```

If you ever need to re-authorize a key from Windows:

```powershell
$pub = wsl -d control-node -u ansible --exec cat /home/ansible/.ssh/id_ed25519.pub
wsl -d managed-node1 -u root --exec /usr/local/sbin/rhcelab-authorize-key "$pub" ansible
```

## 4.6 Connectivity verification

```bash
cd ~/ansible
ansible all -m ansible.builtin.ping
ansible all -m ansible.builtin.command -a 'id'                  # uid=0(root) with become
ansible all -m ansible.builtin.setup -a 'filter=ansible_default_ipv4'
ansible all -m ansible.builtin.setup -a 'filter=ansible_local'  # lab disk fact
rhcelab validate                                                # whole lab
```

Expected:

```
managed-node1 | SUCCESS => { "changed": false, "ping": "pong" }
managed-node2 | SUCCESS => { "changed": false, "ping": "pong" }
```

## 4.7 Documentation offline (as on the exam)

```bash
ansible-doc -l | grep -i firewall
ansible-doc ansible.posix.firewalld        # full doc
ansible-doc -s community.general.lvol      # snippet only
ansible-doc -t keyword -l                  # play/task keywords
ansible-config list | less
ls /usr/share/doc/rhel-system-roles/       # system role READMEs and examples
```
