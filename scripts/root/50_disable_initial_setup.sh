#!/bin/bash

if [[ $HEADLESS -ne 0 ]]; then
    echo "Disabling initial-setup..."
    rm "$MNTDIR/etc/systemd/system/multi-user.target.wants/initial-setup-text.service"
fi
