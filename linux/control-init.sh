#!/usr/bin/env bash
# control-init.sh - install Ansible and the lab tooling on control-node.
#
# Run as root from the repository root, after node-init.sh and a restart:
#     wsl -d control-node -u root --cd <repo> --exec bash linux/control-init.sh [--with-navigator] [--with-lint]
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
LAB_HOME=/opt/rhcelab
VENV=/opt/ansible
WEBROOT=/var/www/html/materials
LAB_USER=ansible
WORKSPACE=/home/$LAB_USER/ansible
# ansible-core 2.18 is the newest release that still supports Python 3.9 targets
# (Rocky 9's platform python) and runs on Rocky 9's python3.12.
ANSIBLE_CORE_SPEC=${ANSIBLE_CORE_SPEC:-ansible-core>=2.16,<2.19}
EXTRA_PIP=()

for arg in "$@"; do
    case $arg in
        --with-navigator) EXTRA_PIP+=(ansible-navigator) ;;
        --with-lint) EXTRA_PIP+=(ansible-lint) ;;
        *) echo "unknown option $arg" >&2; exit 2 ;;
    esac
done

log() { printf '\n==> [control-node] %s\n' "$*"; }
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }

log "Installing packages (Python 3.12, httpd for the materials server, RHEL system roles)"
dnf -y install python3.12 python3.12-pip httpd git jq tmux rhel-system-roles

log "Installing $ANSIBLE_CORE_SPEC into $VENV"
[[ -x $VENV/bin/python ]] || python3.12 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q "$ANSIBLE_CORE_SPEC" "${EXTRA_PIP[@]}"
for tool in "$VENV"/bin/ansible "$VENV"/bin/ansible-* ; do
    ln -sfn "$tool" "/usr/local/bin/$(basename "$tool")"
done
# /usr/local/bin precedes /usr/bin, so the venv wins over the AppStream
# ansible-core 2.14 that rhel-system-roles may pull in.
/usr/local/bin/ansible --version | head -n1

log "Installing lab tooling into $LAB_HOME"
mkdir -p "$LAB_HOME"
# No -a: the stage lives on drvfs where every file looks like 0777/uid 1000.
rsync -r --delete --exclude .git --exclude windows "$REPO/" "$LAB_HOME/"
chown -R root:root "$LAB_HOME"
find "$LAB_HOME" -type d -exec chmod 0755 {} +
find "$LAB_HOME" -type f -exec chmod 0644 {} +
find "$LAB_HOME" -name '*.sh' -exec sed -i 's/\r$//' {} + -exec chmod 0755 {} +

log "SSH key for $LAB_USER"
sudo -u "$LAB_USER" bash -c '
    install -d -m 0700 ~/.ssh
    [[ -f ~/.ssh/id_ed25519 ]] || ssh-keygen -q -t ed25519 -N "" -C "ansible@control-node" -f ~/.ssh/id_ed25519
'

log "Candidate workspace $WORKSPACE and editor settings"
install -d -o "$LAB_USER" -g "$LAB_USER" -m 0755 "$WORKSPACE"
cat >/home/$LAB_USER/.vimrc <<'EOF'
" YAML-friendly defaults (worth typing from memory on exam day)
autocmd FileType yaml setlocal ai et ts=2 sw=2 sts=2 cuc
syntax on
EOF
chown "$LAB_USER:$LAB_USER" /home/$LAB_USER/.vimrc

log "Materials server: http://materials.lab.example.com/materials/"
mkdir -p "$WEBROOT"/{roles,collections}
cp -r --no-preserve=mode,ownership "$REPO"/materials/. "$WEBROOT/"
# Normalize owner and modes inside the archives (the sources sit on drvfs).
TAR_OPTS=(--owner=0 --group=0 --mode=u=rwX,go=rX --sort=name)
for role in "$REPO"/materials-src/roles/*/; do
    tar "${TAR_OPTS[@]}" -C "$REPO/materials-src/roles" -czf "$WEBROOT/roles/$(basename "$role").tar.gz" "$(basename "$role")"
done
tar "${TAR_OPTS[@]}" -C "$REPO/materials-src" -czf "$WEBROOT/app.tar.gz" app
(cd "$WEBROOT" && sha256sum app.tar.gz >app.tar.gz.sha256)
passfile=$(mktemp)
echo 'insecure8sure' >"$passfile"
"$VENV/bin/ansible-vault" encrypt --vault-password-file "$passfile" \
    --output "$WEBROOT/salaries.yml" "$REPO/materials-src/salaries.yml"
rm -f "$passfile"
tmpdl=$(mktemp -d)
# Pinned to the majors that support ansible-core 2.18.
if "$VENV/bin/ansible-galaxy" collection download -p "$tmpdl" \
    'ansible.posix:>=1.6.0,<3.0.0' 'community.general:>=10.0.0,<13.0.0' >/dev/null; then
    cp "$tmpdl"/ansible-posix-*.tar.gz "$WEBROOT/collections/ansible-posix.tar.gz"
    cp "$tmpdl"/community-general-*.tar.gz "$WEBROOT/collections/community-general.tar.gz"
else
    echo "WARNING: could not download collections from Galaxy; collection tasks will not work" >&2
fi
rm -rf "$tmpdl"
find "$WEBROOT" -type d -exec chmod 0755 {} +
find "$WEBROOT" -type f -exec chmod 0644 {} +

# httpd binds only the control node's lab address: the shared WSL namespace may
# already have something on *:80 (another distro, Docker).
sed -i 's/^Listen .*/Listen 10.10.10.10:80/' /etc/httpd/conf/httpd.conf
cat >/etc/httpd/conf.d/rhcelab-materials.conf <<'EOF'
ServerName control-node.lab.example.com
<Directory "/var/www/html/materials">
    Options +Indexes +FollowSymLinks
    IndexOptions FancyIndexing NameWidth=*
</Directory>
EOF
mkdir -p /etc/systemd/system/httpd.service.d
cat >/etc/systemd/system/httpd.service.d/10-rhcelab.conf <<'EOF'
# rhcelab: 10.10.10.10 must exist before httpd binds it.
[Unit]
Requires=rhcelab-net.service
After=rhcelab-net.service
EOF
systemctl daemon-reload
systemctl enable --now httpd
systemctl restart httpd

log "Control node ready"
echo "Next: authorize the key on the managed nodes (New-RhceLab.ps1 does it), then:"
echo "    rhcelab known-hosts && rhcelab validate"
