#!/bin/bash

#set -x

SCRIPTDIR=$(dirname $(readlink -f $0))
export RESOURCEDIR="$SCRIPTDIR/resources"
export MNTDIR="$SCRIPTDIR/mnt"

[[ -d "$RESOURCEDIR" ]] || mkdir "$RESOURCEDIR" || exit 1
[[ -d "$MNTDIR" ]] || mkdir "$MNTDIR" || exit 1

IMAGEURL="http://mirror.pnl.gov/fedora/linux/releases/21/Images/armhfp/Fedora-Minimal-armhfp-21-5-sda.raw.xz"
# size in MB
BOOTSIZE=50
ROOTSIZE=900
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

ROOTOFFSET=$(partx $IMAGEFILE | tail -n 1 | awk '{print $2}')
echo "Extracting rootfs..."
dd if=$IMAGEFILE bs=512 skip=$ROOTOFFSET of=root.img &> /dev/null || exit 1

IMAGESIZE=$((BOOTSIZE + ROOTSIZE + 1))
BOOTSIZE_MB="$BOOTSIZE"M
ROOTSIZE_MB="$ROOTSIZE"M
IMAGESIZE_MB="$IMAGESIZE"M

# create boot partition
echo "Creating boot partition..."
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
sudo umount $MNTDIR || exit 1

# prepare root partition
echo "Preparing root partition..."
e2fsck -fp root.img >/dev/null || exit 1
resize2fs root.img $ROOTSIZE_MB >/dev/null || exit 1
truncate -s $ROOTSIZE_MB root.img || exit 1
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
sudo umount $MNTDIR || exit 1

# create image
echo "Creating image..."
truncate -s $IMAGESIZE_MB $IMAGEFILE.img || exit 1
parted $IMAGEFILE.img mklabel msdos 2>/dev/null || exit 1
parted $IMAGEFILE.img mkpart primary fat16 1MiB $((BOOTSIZE + 1))MiB 2>/dev/null || exit 1
parted $IMAGEFILE.img mkpart primary $((BOOTSIZE + 1))MiB 100% 2>/dev/null || exit 1
dd if=boot.img of=$IMAGEFILE.img obs=1M seek=1 &> /dev/null || exit 1
dd if=root.img of=$IMAGEFILE.img obs=1M seek=$((BOOTSIZE + 1)) &> /dev/null || exit 1

if [[ $COMPRESS -ne 0 ]]; then
	echo "Compressing final image (might take a while)..."
	xz $IMAGEFILE.img || exit 1
fi

echo "$IMAGEFILE.img created successfully."

