#!/bin/bash

echo "Disabling initial-setup..."
rm "$MNTDIR/etc/systemd/system/multi-user.target.wants/initial-setup-text.service"
