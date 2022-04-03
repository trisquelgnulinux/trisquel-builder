#!/bin/bash

#    Copyright (C) 2018-2021  Ruben Rodriguez <ruben@trisquel.info>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

#https://wiki.debian.org/sbuild

if [ $EUID -ne 0 ]; then
   echo "This script must be run as root"
   exit 1
fi

if [ $# -lt 2 ] && [ $# -gt 3 ]; then
   echo Usage: $0 CODENAME ARCH UPSTREAM\(optional\)
   echo Example: $0 nabia amd64 upstream
   exit 1
fi

set -e

CODENAME=$1
ARCH=$2
UPSTREAM=$3

[ "$ARCH" = "i386" ] || [ "$ARCH" = "armhf" ] && BITS=32
[ "$ARCH" = "amd64" ] || [ "$ARCH" = "arm64" ] && BITS=64
PORTS=false
[ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ] && PORTS=true
if [ "$UPSTREAM" = "upstream" ];then
REPO=http://archive.ubuntu.com/ubuntu
else
REPO=http://archive.trisquel.org/trisquel
fi

[ "$CODENAME" == "aramo" ] && UBURELEASE=jammy
[ "$CODENAME" == "nabia" ] && UBURELEASE=focal
[ "$CODENAME" == "etiona" ] && UBURELEASE=bionic
[ "$CODENAME" == "flidas" ] && UBURELEASE=xenial
[ "$CODENAME" == "belenos" ] && UBURELEASE=trusty

if [ "$UPSTREAM" = "upstream" ];then
CODENAME=$UBURELEASE
UNIVERSE="universe"
fi

SBUILD_CREATE_DIR="/tmp/sbuild-create/$CODENAME-$ARCH"
umount $SBUILD_CREATE_DIR/proc || true
umount $SBUILD_CREATE_DIR/ || true
rm -rf $SBUILD_CREATE_DIR
mkdir -p $SBUILD_CREATE_DIR
mount -t tmpfs none $SBUILD_CREATE_DIR

if [ "$UPSTREAM" = "upstream" ];then
    TMP_KEY=`mktemp -d`
    LATEST_LTS_KEYRING="http://archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-keyring/ubuntu-keyring_2021.03.26.tar.gz"
    KEYRING_PATH="ubuntu-keyring-2021.03.26/keyrings"
    KEYRING_FILE="ubuntu-archive-keyring.gpg"
    curl -s -4  $LATEST_LTS_KEYRING | tar xvfz  - $KEYRING_PATH/$KEYRING_FILE
    mv $KEYRING_PATH/$KEYRING_FILE $TMP_KEY/$KEYRING_FILE
    rm -r $(dirname $KEYRING_PATH)
    PRE_BUILD_KEYRING="--keyring=$TMP_KEY/$KEYRING_FILE"
    [ -f /usr/share/debootstrap/scripts/$CODENAME ] && rm /usr/share/debootstrap/scripts/$CODENAME
    ln -s /usr/share/debootstrap/scripts/trisquel /usr/share/debootstrap/scripts/$CODENAME
fi

debootstrap --arch=$ARCH --variant=minbase --components=main $PRE_BUILD_KEYRING --include=apt $CODENAME $SBUILD_CREATE_DIR $REPO

if [ "$UPSTREAM" != "upstream" ];then
wget http://builds.trisquel.org/repos/signkey.asc  -O $SBUILD_CREATE_DIR/tmp/key.asc
fi

cat << MAINEOF > $SBUILD_CREATE_DIR/finish.sh
#!/bin/bash
set -x
set -e
if [ -n "" ]; then
   mkdir -p /etc/apt/apt.conf.d/
   cat > /etc/apt/apt.conf.d/99mk-sbuild-proxy <<EOF
// proxy settings copied from mk-sbuild
Acquire { HTTP { Proxy ""; }; };
EOF
fi

add_sbuild_keys() {
# Reload package lists
# Install ubuntu build keys
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 40976EAF437D05B5
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 3B4FE6ACC0B21F32
# Trisquel keys
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 33C66596
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0C05112F
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com FED8FD3E
}

echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/force-unsafe-io

mkdir -p /home/jenkins/.gnupg
echo "no-use-agent" > /home/jenkins/.gnupg/gpg.conf
chown 1007.1008 -R /home/jenkins

#Add keys to trisquel schroot
if [ "$UPSTREAM" != "upstream" ]; then
add_sbuild_keys
cat /tmp/key.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/builds-repo-key.gpg  >/dev/null
fi

apt-get update
# Disable debconf questions so that automated builds won't prompt
echo set debconf/frontend Noninteractive | debconf-communicate
echo set debconf/priority critical | debconf-communicate
# Install basic build tool set, trying to match buildd
apt-get -y --force-yes install build-essential
apt-get -y --force-yes install --no-install-recommends fakeroot apt-utils aptitude pkgbinarymangler apt devscripts zip unzip quilt wget lsb-release gnupg

#Add keys to upstream schroot (first get universe requirements).
if [ "$UPSTREAM" = "upstream" ]; then
add_sbuild_keys
fi

# Set up expected /dev entries
if [ ! -r /dev/stdin ];  then ln -sf /proc/self/fd/0 /dev/stdin;  fi
if [ ! -r /dev/stdout ]; then ln -sf /proc/self/fd/1 /dev/stdout; fi
if [ ! -r /dev/stderr ]; then ln -sf /proc/self/fd/2 /dev/stderr; fi

apt-get -y --force-yes dist-upgrade
apt-get clean
echo "dash dash/sh boolean false" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dash

# Clean up
rm /finish.sh
echo Finished self-setup
MAINEOF

UBUSRC=archive.ubuntu.com/ubuntu
$PORTS && UBUSRC=ports.ubuntu.com/

cat << EOF > $SBUILD_CREATE_DIR/etc/apt/sources.list
deb $REPO $CODENAME main $UNIVERSE
deb $REPO $CODENAME-updates main $UNIVERSE
deb $REPO $CODENAME-security main $UNIVERSE

deb-src $REPO $CODENAME main $UNIVERSE
deb-src $REPO $CODENAME-updates main $UNIVERSE
deb-src $REPO $CODENAME-security main $UNIVERSE

EOF
if [ "$UPSTREAM" != "upstream" ];then
cat << EOF >> $SBUILD_CREATE_DIR/etc/apt/sources.list
#Trisquel builds repositories
deb http://builds.trisquel.org/repos/$CODENAME/ $CODENAME main
deb http://builds.trisquel.org/repos/$CODENAME/ $CODENAME-security main

#Ubuntu sources (only source packages)
deb-src http://$UBUSRC $UBURELEASE main universe
deb-src http://$UBUSRC $UBURELEASE-updates main universe
deb-src http://$UBUSRC $UBURELEASE-security main universe

EOF
fi

mount -o bind /proc $SBUILD_CREATE_DIR/proc
chroot $SBUILD_CREATE_DIR bash -x /finish.sh
umount $SBUILD_CREATE_DIR/proc

rm -rf /var/lib/schroot/chroots/$CODENAME-$ARCH
[ -d /var/lib/schroot/chroots ] || mkdir /var/lib/schroot/chroots
cp -a $SBUILD_CREATE_DIR /var/lib/schroot/chroots/$CODENAME-$ARCH
umount $SBUILD_CREATE_DIR
rm -r $SBUILD_CREATE_DIR

cat << EOF > /etc/schroot/chroot.d/sbuild-$CODENAME-$ARCH
[$CODENAME-$ARCH]
description=$CODENAME-$ARCH
groups=sbuild,root
root-groups=sbuild,root
source-root-groups=sbuild,root
type=directory
profile=sbuild
union-type=overlay
directory=/var/lib/schroot/chroots/$CODENAME-$ARCH
command-prefix=linux$BITS
EOF

if ! [ -e /etc/schroot/setup.d/04tmpfs ]; then
cat >/etc/schroot/setup.d/04tmpfs <<"END"
#!/bin/sh

set -e

. "$SETUP_DATA_DIR/common-data"
. "$SETUP_DATA_DIR/common-functions"
. "$SETUP_DATA_DIR/common-config"

MEM=$(free --giga |grep Mem: |awk '{print $2}')
[ $MEM -lt 30 ] || exit 0
SIZE=$(expr ${MEM}00 / 110)

if [ "$STAGE" = "setup-start" ]; then
  mount -t tmpfs overlay /var/lib/schroot/union/overlay -o size=${SIZE}G
elif [ "$STAGE" = "setup-recover" ]; then
  mount -t tmpfs overlay /var/lib/schroot/union/overlay -o size=${SIZE}G
elif [ "$STAGE" = "setup-stop" ]; then
  umount -f /var/lib/schroot/union/overlay
fi
END
chmod a+rx /etc/schroot/setup.d/04tmpfs

fi

if [ "$UPSTREAM" = "upstream" ];then
    [ -f /usr/share/debootstrap/scripts/$CODENAME ] && rm /usr/share/debootstrap/scripts/$CODENAME
fi

sbuild-update -udcar $CODENAME-$ARCH

echo "Setup of schroot $CODENAME-$ARCH finished successfully"

