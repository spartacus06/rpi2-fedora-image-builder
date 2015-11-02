#!/bin/bash

#set -x
set -u

SCRIPTDIR=$(dirname $(readlink -f $0))
export RESOURCEDIR="$SCRIPTDIR/resources"
export MNTDIR="$SCRIPTDIR/mnt"

[[ -d "$RESOURCEDIR" ]] || mkdir "$RESOURCEDIR" || exit 1
[[ -d "$MNTDIR" ]] || mkdir "$MNTDIR" || exit 1

IMAGEURL="http://mirror.pnl.gov/fedora/linux/releases/22/Images/armhfp/Fedora-Minimal-armhfp-22-3-sda.raw.xz"
# size in MB
BOOTSIZE=100
ROOTSIZE=1800
COMPRESS=0
HEADLESS=0
if [[ ! -f settings.conf ]]; then
	echo "No settings.conf found, using defaults"
else
	echo "Using settings.conf"
	. settings.conf
fi
IMAGEFILE=${IMAGEURL##*/}
IMAGEFILE=${IMAGEFILE%.*}
echo "BOOTSIZE is $BOOTSIZE MB"
echo "ROOTSIZE is $ROOTSIZE MB"
echo "IMAGEFILE is $IMAGEFILE"

rm -f root.img boot.img $IMAGEFILE.img

if [[ ! -f $IMAGEFILE.xz ]]; then
	echo "Downloading image..."
	wget $IMAGEURL || exit 1
fi
if [[ ! -f $IMAGEFILE ]]; then
	echo "Extracting image..."
	xzdec $IMAGEFILE.xz > $IMAGEFILE || exit 1
fi

ROOTOFFSET=$(partx --show $IMAGEFILE | tail -n 1 | awk '{print $2}')
echo "Extracting rootfs..."
dd if=$IMAGEFILE bs=512 skip=$ROOTOFFSET of=root.img &> /dev/null || exit 1

# create boot partition
echo "Creating boot partition..."
BOOTSIZE_MB="$BOOTSIZE"M
truncate -s $BOOTSIZE_MB boot.img || exit 1
mkfs.vfat boot.img > /dev/null || exit 1
echo "Mounting boot filesystem..."
sudo mount boot.img $MNTDIR || exit 1

echo "Calling boot scripts..."
for i in scripts/boot/*.sh
do
	[[ -x "$i" ]] || continue
	echo "$i"
	bash $i
	RET=$?
	if [[ $RET -ne 0 ]]; then
		echo "script $i returned $RET"
		exit 1
	fi
done

if [[ $COMPRESS -ne 0 ]]; then
	# create large zero file for higher image compression
	echo "Zeroing remaining space..."
	dd if=/dev/zero of=$MNTDIR/zeroes &> /dev/null
	rm -f $MNTDIR/zeroes
fi
echo "Unmounting boot filesystem..."
# wait arbitrary, but usually sufficient, time for some file managers to stop using the volume
sleep 3
sudo umount $MNTDIR || exit 1

# prepare root partition
echo "Preparing root partition..."
if file root.img | grep XFS &>/dev/null; then
	echo "Root filesystem is XFS, resize is not supported"
	ROOTSIZE="$(du -m root.img | cut -f1)"
	ROOTSIZE_MB="$ROOTSIZE"M
	echo "ROOTSIZE changed to $ROOTSIZE MB"
else
	e2fsck -fp root.img >/dev/null || exit 1
	ROOTSIZE_MB="$ROOTSIZE"M
	resize2fs root.img $ROOTSIZE_MB >/dev/null || exit 1
	truncate -s $ROOTSIZE_MB root.img || exit 1
fi
echo "Mounting root filesystem..."
sudo mount root.img $MNTDIR || exit 1
blkid -o export root.img > uuid
. uuid
rm -f uuid
export UUID

echo "Calling root scripts..."
for i in scripts/root/*.sh
do
	[[ -x "$i" ]] || continue
	echo "$i"
	bash $i
	RET=$?
	if [[ $RET -ne 0 ]]; then
		echo "script $i returned $RET"
		exit 1
	fi
done

if [[ $COMPRESS -ne 0 ]]; then
	# create large zero file for higher image compression
	echo "Zeroing remaining space..."
	dd if=/dev/zero of=$MNTDIR/zeroes &> /dev/null
	rm -f $MNTDIR/zeroes
fi
echo "Unmounting root filesystem..."
# wait arbitrary, but usually sufficient, time for some file managers to stop using the volume
sleep 3
sudo umount $MNTDIR || exit 1

# create image
echo "Creating image..."
IMAGESIZE_MB="$((BOOTSIZE + ROOTSIZE + 1))M"
truncate -s $IMAGESIZE_MB $IMAGEFILE.img || exit 1
parted $IMAGEFILE.img mklabel msdos 2>/dev/null || exit 1
parted $IMAGEFILE.img mkpart primary fat16 1MiB $((BOOTSIZE + 1))MiB 2>/dev/null || exit 1
parted $IMAGEFILE.img mkpart primary $((BOOTSIZE + 1))MiB 100% 2>/dev/null || exit 1
dd if=boot.img of=$IMAGEFILE.img obs=1M seek=1 &> /dev/null || exit 1
dd if=root.img of=$IMAGEFILE.img obs=1M seek=$((BOOTSIZE + 1)) &> /dev/null || exit 1

if [[ $COMPRESS -ne 0 ]]; then
	echo "Compressing final image (might take a while)..."
	xz -f $IMAGEFILE.img || exit 1
fi

echo "$IMAGEFILE.img created successfully."

