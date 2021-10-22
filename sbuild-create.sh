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

if [ $# != 2 ]; then
   echo Usage: $0 CODENAME ARCH
   echo Example: $0 flidas i386
   exit 1
fi

set -e

CODENAME=$1
ARCH=$2
[ "$ARCH" = "i386" ] || [ "$ARCH" = "armhf" ] && BITS=32
[ "$ARCH" = "amd64" ] || [ "$ARCH" = "arm64" ] && BITS=64
PORTS=false
[ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ] && PORTS=true
REPO=http://archive.trisquel.org/trisquel

[ "$CODENAME" == "nabia" ] && UBURELEASE=focal
[ "$CODENAME" == "etiona" ] && UBURELEASE=bionic
[ "$CODENAME" == "flidas" ] && UBURELEASE=xenial
[ "$CODENAME" == "belenos" ] && UBURELEASE=trusty

umount /tmp/sbuild-create/$CODENAME-$ARCH/proc || true
umount /tmp/sbuild-create/$CODENAME-$ARCH/ || true
rm -rf /tmp/sbuild-create/$CODENAME-$ARCH
mkdir -p /tmp/sbuild-create/$CODENAME-$ARCH
mount -t tmpfs none /tmp/sbuild-create/$CODENAME-$ARCH
debootstrap --arch=$ARCH --variant=minbase --components=main --include=apt $CODENAME /tmp/sbuild-create/$CODENAME-$ARCH $REPO

wget http://builds.trisquel.org/repos/signkey.asc  -O /tmp/sbuild-create/$CODENAME-$ARCH/tmp/key.asc

cat << MAINEOF > /tmp/sbuild-create/$CODENAME-$ARCH/finish.sh
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

echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/force-unsafe-io

mkdir -p /home/jenkins/.gnupg
echo "no-use-agent" > /home/jenkins/.gnupg/gpg.conf
chown 1007.1008 -R /home/jenkins

# Reload package lists
# Install ubuntu build keys
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 40976EAF437D05B5
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 3B4FE6ACC0B21F32
# Trisquel keys
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 33C66596
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0C05112F
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com FED8FD3E
apt-key add /tmp/key.asc && rm /tmp/key.asc

apt-get update
# Disable debconf questions so that automated builds won't prompt
echo set debconf/frontend Noninteractive | debconf-communicate
echo set debconf/priority critical | debconf-communicate
# Install basic build tool set, trying to match buildd
apt-get -y --force-yes install build-essential
apt-get -y --force-yes install --no-install-recommends fakeroot apt-utils aptitude pkgbinarymangler apt devscripts zip unzip quilt wget lsb-release gnupg



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

cat << EOF > /tmp/sbuild-create/$CODENAME-$ARCH/etc/apt/sources.list

deb http://builds.trisquel.org/repos/$CODENAME/ $CODENAME main
deb http://builds.trisquel.org/repos/$CODENAME/ $CODENAME-security main

deb http://archive.trisquel.org/trisquel $CODENAME main
deb http://archive.trisquel.org/trisquel $CODENAME-updates main
deb http://archive.trisquel.org/trisquel $CODENAME-security main

#deb-src http://archive.trisquel.org/trisquel $CODENAME main
#deb-src http://archive.trisquel.org/trisquel $CODENAME-updates main
#deb-src http://archive.trisquel.org/trisquel $CODENAME-security main

#Ubuntu sources (only source packages)
deb-src http://$UBUSRC $UBURELEASE main universe
deb-src http://$UBUSRC $UBURELEASE-updates main universe
deb-src http://$UBUSRC $UBURELEASE-security main universe

EOF

mount -o bind /proc /tmp/sbuild-create/$CODENAME-$ARCH/proc
chroot /tmp/sbuild-create/$CODENAME-$ARCH bash -x /finish.sh
umount /tmp/sbuild-create/$CODENAME-$ARCH/proc

rm -rf /var/lib/schroot/chroots/$CODENAME-$ARCH
[ -d /var/lib/schroot/chroots ] || mkdir /var/lib/schroot/chroots
cp -a /tmp/sbuild-create/$CODENAME-$ARCH /var/lib/schroot/chroots/$CODENAME-$ARCH
umount /tmp/sbuild-create/$CODENAME-$ARCH
rm -r /tmp/sbuild-create/$CODENAME-$ARCH

cat << EOF > /etc/schroot/chroot.d/sbuild-$CODENAME-$ARCH
[$CODENAME-$ARCH]
description=$CODENAME-$ARCH
groups=sbuild,root
root-groups=sbuild,root
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


sbuild-update -udcar $CODENAME-$ARCH

echo "Setup of schroot $CODENAME-$ARCH finished successfully"

