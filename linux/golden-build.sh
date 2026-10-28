#!/usr/bin/env bash
# golden-build.sh - turn a freshly imported Rocky Linux 9 WSL image into the lab's
# "golden" image. Every lab node is cloned from it.
#
# Run as root from the repository root (New-RhceLab.ps1 does this for you):
#     wsl -d rocky9-golden -u root --cd <repo> --exec bash linux/golden-build.sh
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
LAB_USER=ansible
LAB_UID=1000

# Packages a freshly installed RHEL 9 server has, plus the tools the lab itself needs
# (iproute/nftables/iptables-nft for networking, lvm2/xfsprogs/parted for storage
# exercises, policycoreutils-python-utils for semanage, python3 for Ansible modules).
BASE_PACKAGES=(
    systemd openssh-server openssh-clients sudo passwd shadow-utils
    iproute iputils nftables iptables-nft kmod procps-ng psmisc hostname which
    findutils less vim-enhanced bash-completion man-db man-pages tar gzip bzip2 unzip
    rsync curl wget lsof util-linux
    lvm2 xfsprogs e2fsprogs parted
    cronie at firewalld
    selinux-policy-targeted policycoreutils policycoreutils-python-utils
    python3 python3-libselinux python3-libsemanage python3-policycoreutils
    dnf-plugins-core glibc-langpack-en
)

log() { printf '\n==> %s\n' "$*"; }

[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }
grep -q 'Rocky Linux.* 9' /etc/redhat-release || { echo "expected Rocky Linux 9" >&2; exit 1; }

log "Updating the image and installing base packages"
dnf -y update
dnf -y install "${BASE_PACKAGES[@]}"

log "Creating automation user '$LAB_USER' (uid $LAB_UID, key-based SSH only)"
if ! id "$LAB_USER" &>/dev/null; then
    # The image's OOBE would create 'rocky' with uid 1000; we never run it.
    useradd -m -u "$LAB_UID" -c "Ansible automation user" "$LAB_USER"
fi
# '*' = no valid password: no password logins, but key logins and `wsl -u` work.
usermod -p '*' "$LAB_USER"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$LAB_USER" >/etc/sudoers.d/"$LAB_USER"
chmod 0440 /etc/sudoers.d/"$LAB_USER"
visudo -cqf /etc/sudoers.d/"$LAB_USER"

log "Installing lab scripts and units"
# Explicit install(1) with fixed modes: the staging copy lives on drvfs (/mnt/c), where
# every file appears as 0777 owned by uid 1000. `cp -a` would carry that over, onto
# /etc and /usr too.
F=$REPO/linux/files
install -d -m 0755 /etc/rhcelab /etc/ansible/facts.d /var/lib/rhcelab
install -m 0755 "$F"/usr/local/sbin/rhcelab-* /usr/local/sbin/
install -m 0755 "$F"/usr/local/bin/rhcelab /usr/local/bin/
install -m 0644 "$F"/etc/systemd/system/rhcelab-*.service /etc/systemd/system/
install -m 0600 "$F"/etc/ssh/sshd_config.d/10-rhcelab.conf /etc/ssh/sshd_config.d/
install -m 0644 "$F"/etc/rhcelab/reset-paths.conf /etc/rhcelab/

log "Configuring WSL (systemd, default user, lab-managed /etc/hosts)"
cat >/etc/wsl.conf <<EOF
# Managed by the RHCE lab. node-init.sh sets the hostname.
[boot]
systemd = true

[user]
default = $LAB_USER

[network]
generateHosts = false
generateResolvConf = true

[interop]
enabled = true
appendWindowsPath = false
EOF
# Disable the first-run user-creation wizard shipped in the WSL image.
if [[ -f /etc/wsl-distribution.conf ]]; then
    sed -i '/^\[oobe\]/,/^\[/{/^command/d;/^defaultName/d}' /etc/wsl-distribution.conf
fi

log "LVM: restrict every node to its own disks (devices file)"
if ! grep -q 'rhcelab' /etc/lvm/lvmlocal.conf 2>/dev/null; then
    cat >>/etc/lvm/lvmlocal.conf <<'EOF'

# rhcelab: /dev is shared by all WSL distributions. Only devices listed in
# /etc/lvm/devices/system.devices are used, so nodes never see each other's PVs.
devices {
    use_devicesfile = 1
}
EOF
fi

log "SELinux: userspace configured; the WSL2 kernel does not enable SELinux"
# The baseline is 'permissive' on purpose so the SELinux exercises have work to do.
sed -i 's/^SELINUX=.*/SELINUX=permissive/; s/^SELINUXTYPE=.*/SELINUXTYPE=targeted/' /etc/selinux/config

log "Enabling services"
systemctl enable sshd firewalld crond atd rhcelab-net.service rhcelab-storage.service

log "Generalizing the image (machine-id, SSH host keys, caches)"
: >/etc/machine-id
rm -f /etc/ssh/ssh_host_*
dnf clean all
rm -rf /var/cache/dnf/* /tmp/* /var/tmp/* /root/.bash_history /home/"$LAB_USER"/.bash_history
log "Golden image ready"
