# 2. Deployment guide

Two ways to build the lab:

* **A. Automated:** one PowerShell script, ~15-25 minutes.
* **B. Manual:** the same steps as individual commands, so you can see (and
  explain) every step.

## 2.0 Requirements

| Item | Requirement |
|---|---|
| Windows | Windows 11 (build 22000+), virtualization enabled in firmware |
| WSL | Microsoft Store WSL 2.x (`wsl --version` works) |
| RAM | 16 GB host recommended; the WSL VM gets 6 GB |
| Disk | ~12 GB free on the lab drive |
| Network | Internet access to `dl.rockylinux.org`, `pypi.org`, `galaxy.ansible.com` |

Install or update WSL from an **elevated** PowerShell (once):

```powershell
wsl --install --no-distribution
wsl --update
wsl --version
```

Reboot if `wsl --install` asks you to.

Recommended VM settings: copy [`windows/wslconfig.example`](../windows/wslconfig.example)
into `%USERPROFILE%\.wslconfig` (merge with existing content), then:

```powershell
wsl --shutdown
```

## 2.A Automated deployment

Run as your normal user (not elevated):

```powershell
mkdir C:\RHCE -Force; cd C:\RHCE
git clone https://github.com/maarivera/wsl_rhce_ex294.git
cd wsl_rhce_ex294
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\windows\New-RhceLab.ps1
```

Options:

| Parameter | Purpose |
|---|---|
| `-LabRoot D:\WSL\rhcelab` | Store distributions elsewhere (default `%USERPROFILE%\WSL\rhcelab`) |
| `-ImagePath C:\Downloads\Rocky-9-WSL-Base.latest.x86_64.wsl` | Use a pre-downloaded image |
| `-ReuseGolden` | Re-clone the nodes from the existing golden VHDX (fast rebuild) |
| `-Force` | Replace existing lab distributions |
| `-WithNavigator` | Also install `ansible-navigator` |

What it does, in order:

1. Checks Windows build, WSL version and free disk space.
2. Copies the repository to `<LabRoot>\stage` with LF line endings.
3. Downloads the Rocky Linux 9 WSL image and verifies its SHA256 checksum.
4. Imports `rocky9-golden` and runs `linux/golden-build.sh`.
5. Exports the golden image as a VHDX and clones the three nodes from it.
6. Runs `linux/node-init.sh` in each clone, then restarts it.
7. Starts the nodes and runs `linux/control-init.sh` on control-node.
8. Installs control-node's SSH public key on the managed nodes.
9. Captures the reset baseline and runs the lab validation.

After a Windows reboot or `wsl --shutdown`:

```powershell
.\windows\Start-RhceLab.ps1
```

## 2.B Manual deployment (copy-paste)

Every command below is what the scripts run. Use the same PowerShell window
throughout; the variables carry over.

### Step 1 - Variables and folders (PowerShell)

```powershell
$LabRoot = "$env:USERPROFILE\WSL\rhcelab"
$Repo    = "C:\RHCE\wsl_rhce_ex294"
$Image   = "$LabRoot\images\Rocky-9-WSL-Base.latest.x86_64.wsl"
$Url     = "https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-WSL-Base.latest.x86_64.wsl"
New-Item -ItemType Directory -Force "$LabRoot\images", "$LabRoot\golden", "$LabRoot\nodes" | Out-Null
```

### Step 2 - Download and verify the image (PowerShell)

```powershell
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest $Url -OutFile $Image -UseBasicParsing
Invoke-WebRequest "$Url.CHECKSUM" -OutFile "$Image.CHECKSUM" -UseBasicParsing
Get-Content "$Image.CHECKSUM"
(Get-FileHash -Algorithm SHA256 $Image).Hash
```

The two hashes must match (case does not matter).

### Step 3 - Build the golden image (PowerShell + WSL)

```powershell
wsl --import rocky9-golden "$LabRoot\golden\distro" $Image --version 2
wsl -d rocky9-golden -u root --cd $Repo --exec bash linux/golden-build.sh
wsl --terminate rocky9-golden
wsl --export rocky9-golden "$LabRoot\golden\rocky9-golden.vhdx" --vhd
wsl --unregister rocky9-golden
```

> If you cloned the repository with `core.autocrlf=true` before `.gitattributes`
> existed, the scripts have CRLF line endings and bash fails with `$'\r': command not
> found`. Re-clone, or run `git config core.autocrlf input` and
> `git checkout -- .` in the repository.

`golden-build.sh` (read it, it is short) performs:

```bash
dnf -y update
dnf -y install openssh-server sudo iproute nftables iptables-nft lvm2 xfsprogs parted \
    cronie at firewalld policycoreutils-python-utils python3 ...   # full list in the script
useradd -m -u 1000 -c "Ansible automation user" ansible
usermod -p '*' ansible                                  # no password; keys only
echo 'ansible ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/ansible
cp -a linux/files/. /                                   # rhcelab-* scripts and units
# /etc/wsl.conf: systemd=true, default user ansible, generateHosts=false
systemctl enable sshd firewalld crond atd rhcelab-net rhcelab-storage
: > /etc/machine-id; rm -f /etc/ssh/ssh_host_*          # generalize
```

### Step 4 - Clone the three nodes (PowerShell)

Importing a VHDX copies the disk as-is (no tar extraction), so cloning takes seconds.

```powershell
foreach ($n in 'control-node','managed-node1','managed-node2') {
    wsl --import $n "$LabRoot\nodes\$n" "$LabRoot\golden\rocky9-golden.vhdx" --vhd --version 2
}
wsl --list --verbose
```

### Step 5 - Personalize each node (PowerShell + WSL)

```powershell
wsl -d control-node  -u root --cd $Repo --exec bash linux/node-init.sh --role control --name control-node  --ip 10.10.10.10
wsl -d managed-node1 -u root --cd $Repo --exec bash linux/node-init.sh --role managed --name managed-node1 --ip 10.10.10.11 --disks disk1:1024 --seed-vg research:disk1
wsl -d managed-node2 -u root --cd $Repo --exec bash linux/node-init.sh --role managed --name managed-node2 --ip 10.10.10.12 --disks disk1:2048
wsl --terminate control-node; wsl --terminate managed-node1; wsl --terminate managed-node2
```

### Step 6 - Start the nodes (PowerShell)

WSL stops a distribution shortly after its last client process exits. A hidden
`sleep infinity` keeps each node (and its sshd) running:

```powershell
foreach ($n in 'managed-node1','managed-node2','control-node') {
    Start-Process wsl.exe -ArgumentList "-d $n -u root --exec /bin/sleep infinity" -WindowStyle Hidden
}
Start-Sleep 5
foreach ($n in 'managed-node1','managed-node2','control-node') {
    wsl -d $n -u root --exec systemctl is-system-running --wait
}
wsl --list --running
```

`degraded` is acceptable (some units that make no sense in WSL fail); check with
`wsl -d managed-node1 -u root --exec systemctl --failed`.

### Step 7 - Install Ansible on control-node (PowerShell + WSL)

```powershell
wsl -d control-node -u root --cd $Repo --exec bash linux/control-init.sh
```

This installs Python 3.12, creates `/opt/ansible` (venv with
`ansible-core>=2.16,<2.19`), links the tools into `/usr/local/bin`, installs
`rhel-system-roles`, generates `~ansible/.ssh/id_ed25519`, copies the lab tooling to
`/opt/rhcelab` and publishes the materials server. Details in
[04-ansible-configuration.md](04-ansible-configuration.md).

### Step 8 - SSH trust (PowerShell + WSL)

Password authentication is disabled on the managed nodes, so the public key is
installed out-of-band, the way a console or kickstart would do it:

```powershell
$pub = wsl -d control-node -u ansible --exec cat /home/ansible/.ssh/id_ed25519.pub
foreach ($n in 'managed-node1','managed-node2') {
    wsl -d $n -u root --exec /usr/local/sbin/rhcelab-authorize-key "$pub" ansible
}
wsl -d control-node -u ansible --exec /usr/local/bin/rhcelab known-hosts
```

### Step 9 - Baseline and validation (PowerShell + WSL)

```powershell
wsl -d managed-node1 -u root --exec /usr/local/sbin/rhcelab-baseline capture
wsl -d managed-node2 -u root --exec /usr/local/sbin/rhcelab-baseline capture
wsl -d control-node -u ansible --cd /home/ansible --exec /opt/rhcelab/validate/validate-lab.sh
```

All 34 checks should pass.

### Step 10 - Work

```powershell
wsl -d control-node
```

```bash
cd ~/ansible
ansible --version
```

## 2.C Removing the lab

```powershell
.\windows\Remove-RhceLab.ps1               # unregister the distributions (asks first)
.\windows\Remove-RhceLab.ps1 -DeleteFiles  # also delete images and the golden VHDX
```

The nodes' namespaces and veths disappear with them. The bridge `rhcebr0` and the
`ip rhcelab` nft table remain until the next `wsl --shutdown`.
