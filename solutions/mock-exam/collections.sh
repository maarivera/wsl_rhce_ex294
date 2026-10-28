#!/bin/bash
# T03 - collections from the materials server into mycollections.
ansible-galaxy collection install -p /home/ansible/ansible/mycollections \
  http://materials.lab.example.com/materials/collections/ansible-posix.tar.gz \
  http://materials.lab.example.com/materials/collections/community-general.tar.gz
