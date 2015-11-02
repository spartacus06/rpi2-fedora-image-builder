#!/bin/bash

if [[ $HEADLESS -ne 0 ]]; then
    echo "Adding pi user with password raspberry..."
    echo "pi:x:1000:" >> "$MNTDIR/etc/group"
    echo "pi:x:1000:1000:Raspberry Pi User:/home/pi:/bin/bash" >> "$MNTDIR/etc/passwd"
    echo 'pi:$6$vvgvIimr$NgklQX6s2GEq4/aQM2ZaFzh6otIEHNFC7m2eUamen9nI2QwHUlgazqif4ZB5P2yVjKGNvUoNHzJ0vdrtFs2hY1:16574:0:99999:7:::' >> "$MNTDIR/etc/shadow"
    echo "pi:!::" >> "$MNTDIR/etc/gshadow"
    sed -i "s/^wheel:x:10:/wheel:x:10:pi/" "$MNTDIR/etc/group"
    mkdir -p "$MNTDIR/home/pi"
    chmod 0750 "$MNTDIR/home/pi"
    chcon -t user_home_dir_t "$MNTDIR/home/pi"
    cp -p "$MNTDIR/etc/skel/.bashrc" "$MNTDIR/home/pi"
    chcon -t user_home_t "$MNTDIR/home/pi/.bashrc"
    cp -p "$MNTDIR/etc/skel/.bash_profile" "$MNTDIR/home/pi"
    chcon -t user_home_t "$MNTDIR/home/pi/.bash_profile"
    cp -p "$MNTDIR/etc/skel/.bash_logout" "$MNTDIR/home/pi"
    chcon -t user_home_t  "$MNTDIR/home/pi/.bash_logout"
    chown -R 1000:1000 "$MNTDIR/home/pi"
fi
