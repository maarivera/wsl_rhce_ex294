#!/bin/bash
# T02 - repositories on every managed node with ad-hoc commands.
ansible all -m ansible.builtin.yum_repository -a "name=EX294_BASE description='EX294 base software' \
  baseurl=http://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/ \
  gpgcheck=yes gpgkey=https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9 enabled=yes"

ansible all -m ansible.builtin.yum_repository -a "name=EX294_STREAM description='EX294 stream software' \
  baseurl=http://dl.rockylinux.org/pub/rocky/9/AppStream/x86_64/os/ \
  gpgcheck=yes gpgkey=https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-Rocky-9 enabled=yes"
