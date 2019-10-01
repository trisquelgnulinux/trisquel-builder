#!/bin/bash

#    Copyright (C) 2018-2019  Ruben Rodriguez <ruben@trisquel.info>
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
REPO=http://devel.trisquel.info/trisquel

[ "$CODENAME" == "etiona" ] && UBURELEASE=bionic
[ "$CODENAME" == "flidas" ] && UBURELEASE=xenial
[ "$CODENAME" == "belenos" ] && UBURELEASE=trusty

rm -rf /tmp/sbuild-create/$CODENAME-$ARCH
debootstrap --arch=$ARCH --variant=minbase --components=main --include=apt,eatmydata $CODENAME /tmp/sbuild-create/$CODENAME-$ARCH $REPO

cat << MAINEOF > /tmp/sbuild-create/$CODENAME-$ARCH/finish.sh
#!/bin/bash
#set -x
set -e
if [ -n "" ]; then
   mkdir -p /etc/apt/apt.conf.d/
   cat > /etc/apt/apt.conf.d/99mk-sbuild-proxy <<EOF
// proxy settings copied from mk-sbuild
Acquire { HTTP { Proxy ""; }; };
EOF
fi

echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/force-unsafe-io

mkdir -p /home/jenkins
chown 1007.1008 /home/jenkins

# Install ubuntu build key
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 40976EAF437D05B5
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 3B4FE6ACC0B21F32
# Trisquel key
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 33C66596
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0C05112F
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com FED8FD3E
# Reload package lists
apt-get update
# Disable debconf questions so that automated builds won't prompt
echo set debconf/frontend Noninteractive | debconf-communicate
echo set debconf/priority critical | debconf-communicate
# Install basic build tool set, trying to match buildd
apt-get -y --force-yes install --no-install-recommends build-essential fakeroot apt-utils pkgbinarymangler apt eatmydata devscripts zip unzip quilt default-jdk-headless wget lsb-release git vim ssh-client locales ccache cdbs python3.5 ca-certificates
# Set up expected /dev entries
if [ ! -r /dev/stdin ];  then ln -sf /proc/self/fd/0 /dev/stdin;  fi
if [ ! -r /dev/stdout ]; then ln -sf /proc/self/fd/1 /dev/stdout; fi
if [ ! -r /dev/stderr ]; then ln -sf /proc/self/fd/2 /dev/stderr; fi
# Clean up
rm /finish.sh
apt-get clean
echo "dash dash/sh boolean false" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dash
sed '/backports/s/^#//' -i /etc/apt/sources.list
MAINEOF

cat << EOF > /tmp/sbuild-create/$CODENAME-$ARCH/usr/local/bin/jenkins-slave
#!/bin/bash

wget -O /var/slave.jar http://devel.trisquel.info:8085/jnlpJars/slave.jar 

BUILDDIST=\$(lsb_release -cs)
case "\$BUILDDIST" in
        "flidas")
          export STR=4ff092bbb47a0c7274f43bcf8b83ea7332008f7cc4caf8517312b5c4cabf2970
           ;;
        "belenos")
          export STR=c4cb30c3c8eff2742d62ffb11de3c810c0b48101a403cd078d9b970037414113
           ;;
        "etiona")
          export STR=05e7dcb0125bd85265bf04a57b41fa0e56eb66eab7b5f822a6a15ecf092ef772
           ;;
esac

java -jar /var/slave.jar -jnlpUrl http://devel.trisquel.info:8085/computer/\$BUILDDIST/slave-agent.jnlp -secret "\$STR" 

EOF
chmod 755 /tmp/sbuild-create/$CODENAME-$ARCH/usr/local/bin/jenkins-slave

cat << EOF > /tmp/sbuild-create/$CODENAME-$ARCH/etc/apt/sources.list
deb http://jenkins.trisquel.info/repos/trisquel/$CODENAME/ $CODENAME main
deb http://jenkins.trisquel.info/repos/trisquel/$CODENAME/ $CODENAME-security main
#deb http://jenkins.trisquel.info/repos/trisquel/$CODENAME/ $CODENAME-backports main
deb http://jenkins.trisquel.info/repos/packages/$CODENAME/production $CODENAME main
deb http://devel.trisquel.info/trisquel $CODENAME main
deb http://devel.trisquel.info/trisquel $CODENAME-updates main
deb http://devel.trisquel.info/trisquel $CODENAME-security main
#deb http://devel.trisquel.info/trisquel $CODENAME-backports main
deb-src http://devel.trisquel.info/trisquel $CODENAME main
deb-src http://devel.trisquel.info/trisquel $CODENAME-updates main
deb-src http://devel.trisquel.info/trisquel $CODENAME-security main
#deb-src http://devel.trisquel.info/trisquel $CODENAME-backports main
#Ubuntu sources (only source packages)
deb-src http://archive.ubuntu.com/ubuntu $UBURELEASE main universe
deb-src http://archive.ubuntu.com/ubuntu $UBURELEASE-updates main universe
EOF

mount -o bind /proc /tmp/sbuild-create/$CODENAME-$ARCH/proc
chroot /tmp/sbuild-create/$CODENAME-$ARCH sh -x /finish.sh
umount /tmp/sbuild-create/$CODENAME-$ARCH/proc

rm -rf /var/lib/schroot/chroots/$CODENAME-$ARCH
[ -d /var/lib/schroot/chroots ] || mkdir /var/lib/schroot/chroots
mv /tmp/sbuild-create/$CODENAME-$ARCH /var/lib/schroot/chroots/$CODENAME-$ARCH

cat << EOF > /etc/schroot/chroot.d/sbuild-$CODENAME-$ARCH
[$CODENAME-$ARCH]
description=$CODENAME-$ARCH
groups=sbuild,root
root-groups=sbuild,root
type=directory
profile=sbuild
union-type=overlay
directory=/var/lib/schroot/chroots/$CODENAME-$ARCH
command-prefix=/var/cache/ccache-sbuild/sbuild-setup,eatmydata
EOF

echo "Setup of schroot $CODENAME-$ARCH finished successfully"
