#!/usr/bin/env bash
set -e
cp -a /seed_home/. /home/devuser/
chmod 700 /home/devuser/.ssh
chmod 600 /home/devuser/.ssh/authorized_keys
chown -R devuser:devuser /home/devuser
tail -f /dev/null
