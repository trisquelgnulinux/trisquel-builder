#!/bin/bash

#    Copyright (C) 2018-2021  Ruben Rodriguez <ruben@trisquel.info>
#    Copyright (C) 2022  Luis Guzman <ark@switnet.org>
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

# True if $1 is greater than $2
version_gt() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"; }

if [ "$EUID" -ne 0 ]; then
   echo "This script must be run as root"
   exit 1
fi

if [ $# -lt 2 ] && [ $# -gt 3 ]; then
   echo Usage: "$0" CODENAME ARCH UPSTREAM \(optional\)
   echo Example 1: "$0" nabia amd64
   echo Example 2: "$0" bullseye amd64
   echo Example 3: "$0" aramo amd64 upstream
   exit 1
fi

set -e
#Clean previous setup.
[ -f /etc/apt/sources.list.d/debootstrap.list ] && \
rm /etc/apt/sources.list.d/debootstrap.list
[ -f /etc/apt/preferences.d/debootstrap ] && \
rm /etc/apt/preferences.d/debootstrap

CODENAME="$1"
ARCH="$2"
UPSTREAM="$3"

[ "$ARCH" = "i386"  ] || [ "$ARCH" = "armhf" ] && BITS=32
[ "$ARCH" = "amd64" ] || [ "$ARCH" = "arm64" ] || [ "$ARCH" = "ppc64el" ] && BITS=64
PORTS=false
[ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ] || [ "$ARCH" = "ppc64el" ] && PORTS=true

[ "$CODENAME" == "buster"   ] && UPSTREAM="debian" && VALID=1
[ "$CODENAME" == "bullseye" ] && UPSTREAM="debian" && VALID=1
[ "$CODENAME" == "bookworm" ] && UPSTREAM="debian" && VALID=1
[ "$CODENAME" == "sid"      ] && UPSTREAM="debian" && VALID=1

EATMYDATA=eatmydata
[ "$BITS" == "32" ] && EATMYDATA=""

UBUSRC=http://archive.ubuntu.com/ubuntu
"$PORTS" && UBUSRC=http://ports.ubuntu.com/

if [ "$UPSTREAM" = "upstream" ];then
REPO=http://archive.ubuntu.com/ubuntu
"$PORTS" && REPO="$UBUSRC"
elif [ "$UPSTREAM" = "debian" ]; then
REPO=http://deb.debian.org/debian
else
REPO=http://archive.trisquel.org/trisquel
fi

[ "$CODENAME" == "aramo"  ] && UBURELEASE=jammy  && VALID=1
[ "$CODENAME" == "nabia"  ] && UBURELEASE=focal  && VALID=1
[ "$CODENAME" == "etiona" ] && UBURELEASE=bionic && VALID=1

if [ "$VALID" != 1 ];then
    echo "Not valid codename"
    exit 1
fi

HOST_OS="$(lsb_release -si)"
DBSTRAP_VER="$(dpkg-query -s debootstrap 2>/dev/null|awk '/Version/{print$2}')"
echo -e "\\nOS: $HOST_OS \\ndebootstrap: $DBSTRAP_VER\\n"

#Upgrade debian debootstrap package if required.
if [ "$HOST_OS" = Debian ] && \
   version_gt 1.0.124 "$DBSTRAP_VER" && \
   [ "$CODENAME" = aramo ];then
    echo "It is required to upgrade debootstrap to create a $CODENAME jail, upgrading..."
cat << DBST_REPO >> /etc/apt/sources.list.d/debootstrap.list
#Pinned repo (see /etc/apt/preferences.d/debootstrap).
deb http://deb.debian.org/debian bullseye-backports main
DBST_REPO
    apt update -q2
cat << DBST > /etc/apt/preferences.d/debootstrap
Package: *
Pin: release n=bullseye-backports
Pin-Priority: 1
DBST
    apt-get -t bullseye-backports install debootstrap
fi

if [ "$HOST_OS" != Debian ] && \
   version_gt 1.0.124 "$DBSTRAP_VER" && \
   [ "$CODENAME" = aramo ];then
    echo "It is required to upgrade debootstrap to create the $CODENAME jail, upgrading..."
#Add variables to meet OS.
[ "$HOST_OS" = "Trisquel" ] && REPO_ARCHIVE="$REPO" && REPO_DIST="$CODENAME"
[ "$HOST_OS" = "Ubuntu" ] && REPO_ARCHIVE="$UBUSRC" && REPO_DIST="$UBURELEASE"
"$PORTS" && BIN_URL="ubuntu-ports"
#Set custom OS backport repository.
cat << DBST_REPO > /etc/apt/sources.list.d/debootstrap.list
#Pinned repo (see /etc/apt/preferences.d/debootstrap).
deb $REPO_ARCHIVE$BIN_URL $REPO_DIST main
DBST_REPO
cat << DBST > /etc/apt/preferences.d/debootstrap
Package: *
Pin: release n=$REPO_DIST
Pin-Priority: 1
DBST
    apt update -q2
    apt-get -t "$REPO_DIST" install --reinstall debootstrap
fi

CA_BASE="$CODENAME-$ARCH"
SBUILD_CREATE_DIR="/tmp/sbuild-create/$CA_BASE"

if [ "$UPSTREAM" = "upstream" ];then
CODENAME="$UBURELEASE"
UNIVERSE="universe"
fi

umount "$SBUILD_CREATE_DIR"/proc || true
umount "$SBUILD_CREATE_DIR"/ || true
rm -rf "$SBUILD_CREATE_DIR"
mkdir -p "$SBUILD_CREATE_DIR"
mount -t tmpfs none "$SBUILD_CREATE_DIR"
DBSTRAP_SCRIPTS="/usr/share/debootstrap/scripts"

if [ "$HOST_OS" = "Trisquel" ];then
    if [ "$UPSTREAM" = "upstream" ];then
        TMP_KEY="$(mktemp -d)"
        LATEST_LTS_KEYRING="http://archive.ubuntu.com/ubuntu/pool/main/u/ubuntu-keyring/ubuntu-keyring_2021.03.26.tar.gz"
        KEYRING_PATH="ubuntu-keyring-2021.03.26/keyrings"
        KEYRING_FILE="ubuntu-archive-keyring.gpg"
        curl -s -4  "$LATEST_LTS_KEYRING" | tar xvfz  - "$KEYRING_PATH"/"$KEYRING_FILE"
        mv "$KEYRING_PATH"/"$KEYRING_FILE" "$TMP_KEY"/"$KEYRING_FILE"
        rm -r "$(dirname $KEYRING_PATH)"
        PRE_BUILD_KEYRING="--keyring=$TMP_KEY/$KEYRING_FILE"
        if [ ! -f "$DBSTRAP_SCRIPTS"/"$CODENAME" ];then
            if [ -f  "$DBSTRAP_SCRIPTS"/trisquel ]; then
                ln -s "$DBSTRAP_SCRIPTS"/trisquel "$DBSTRAP_SCRIPTS"/"$CODENAME"
            elif [ -f "$DBSTRAP_SCRIPTS"/gutsy ]; then
                ln -s "$DBSTRAP_SCRIPTS"/gutsy "$DBSTRAP_SCRIPTS"/"$CODENAME"
            else
               echo "No option available"
               exit
            fi
        fi
    fi
fi
if [ "$HOST_OS" != "Trisquel" ];then
    if [ -z "$UPSTREAM" ];then
        TMP_TKEY="$(mktemp -d)"
        TRISQUEL_ARCHIVE_KEYRING="http://archive.trisquel.org/trisquel/trisquel-archive-signkey.gpg"
        curl -s -4 "$TRISQUEL_ARCHIVE_KEYRING" > "$TMP_TKEY"/trisquel-archive-signkey
        gpg --dearmor "$TMP_TKEY"/trisquel-archive-signkey
        PRE_BUILD_KEYRING="--keyring=$TMP_TKEY/trisquel-archive-signkey.gpg"
        DBSTAP_TRISQUEL="https://gitlab.trisquel.org/trisquel/package-helpers/-/raw/nabia/helpers/DATA/debootstrap/trisquel"
        DBSTRAP_TRIS_COM="https://gitlab.trisquel.org/trisquel/package-helpers/-/raw/nabia/helpers/DATA/debootstrap/trisquel-common"
        [ ! -f "$DBSTRAP_SCRIPTS"/"$CODENAME"     ] && curl -s -4 "$DBSTAP_TRISQUEL" > "$DBSTRAP_SCRIPTS"/"$CODENAME"
        [ ! -f "$DBSTRAP_SCRIPTS"/trisquel-common ] && curl -s -4 "$DBSTRAP_TRIS_COM" > "$DBSTRAP_SCRIPTS"/trisquel-common
    elif [ "$UPSTREAM" = upstream ];then
        apt install -y ubuntu-keyring
        PRE_BUILD_KEYRING="--keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg"
        [ ! -f "$DBSTRAP_SCRIPTS"/"$CODENAME" ] && ln -s "$DBSTRAP_SCRIPTS"/gutsy "$DBSTRAP_SCRIPTS"/"$CODENAME"
    fi
fi
if [ "$UPSTREAM" = "debian" ];then
    apt install -y debian-archive-keyring
    PRE_BUILD_KEYRING="--keyring=/usr/share/keyrings/debian-archive-keyring.gpg"
    DBSTAP_SID="https://salsa.debian.org/installer-team/debootstrap/-/raw/master/scripts/sid"
    DBSTRAP_DEB_COM="https://salsa.debian.org/installer-team/debootstrap/-/raw/master/scripts/debian-common"
    [ ! -f "$DBSTRAP_SCRIPTS"/"$CODENAME"   ] && curl -s -4 "$DBSTAP_SID" > "$DBSTRAP_SCRIPTS"/"$CODENAME"
    [ ! -f "$DBSTRAP_SCRIPTS"/debian-common ] && curl -s -4 "$DBSTRAP_DEB_COM" > "$DBSTRAP_SCRIPTS"/debian-common
fi

EXTRACTOR="dpkg-deb"
[ "$ARCH" = "ppc64el" ] && EXTRACTOR=ar

[ -z "$PRE_BUILD_KEYRING" ] && PRE_BUILD_KEYRING="--verbose"
debootstrap --arch="$ARCH" \
	    --extractor=$EXTRACTOR \
            --variant=minbase \
            --components=main \
            "$PRE_BUILD_KEYRING" \
            --include=apt \
            "$CODENAME" \
            "$SBUILD_CREATE_DIR" "$REPO"

wget http://builds.trisquel.org/repos/signkey.asc  -O "$SBUILD_CREATE_DIR"/tmp/key.asc

cat << MAINEOF > "$SBUILD_CREATE_DIR"/finish.sh
#!/bin/bash
set -x
set -e
TMP_GPG_REPO="$(mktemp)"
if [ -n "" ]; then
   mkdir -p /etc/apt/apt.conf.d/
   cat > /etc/apt/apt.conf.d/99mk-sbuild-proxy <<EOF
// proxy settings copied from mk-sbuild
Acquire { HTTP { Proxy ""; }; };
EOF
fi

#Add gpg key via gpg server to keyring storage.
add_gpg_keyring() {
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com \$1
apt-key export \$1 | gpg --dearmour | tee $TMP_GPG_REPO/\$1.gpg >/dev/null
apt-key del \$1
mv $TMP_GPG_REPO/\$1.gpg /etc/apt/trusted.gpg.d/
}
add_sbuild_keys() {
# Reload package lists
# Install Ubuntu build keys
add_gpg_keyring 40976EAF437D05B5
add_gpg_keyring 3B4FE6ACC0B21F32
add_gpg_keyring 871920D1991BC93C
# Trisquel keys
add_gpg_keyring 92D284CF33C66596
add_gpg_keyring B138CA450C05112F
add_gpg_keyring FED8FD3E
# Debian
add_gpg_keyring 9D6D8F6BC857C906
add_gpg_keyring 8B48AD6246925553
add_gpg_keyring DCC9EFBF77E11517
add_gpg_keyring 648ACFD622F3D138
add_gpg_keyring 54404762BBB6E853
add_gpg_keyring 605C66F00D6C9793
add_gpg_keyring 0E98404D386FA1D9
}

echo "force-unsafe-io" > /etc/dpkg/dpkg.cfg.d/force-unsafe-io

mkdir -p /home/jenkins/.gnupg
echo "no-use-agent" > /home/jenkins/.gnupg/gpg.conf
chown 1007.1008 -R /home/jenkins

#Add keys to trisquel schroot
if [ -z "$UPSTREAM" ]; then
add_sbuild_keys
cat /tmp/key.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/builds-repo-key.gpg  >/dev/null
fi

apt-get update
# Disable debconf questions so that automated builds won't prompt
echo set debconf/frontend Noninteractive | debconf-communicate
echo set debconf/priority critical | debconf-communicate
# Install basic build tool set, trying to match build
apt-get -y  --allow-downgrades \
            --allow-remove-essential \
            --allow-change-held-packages \
            install build-essential
apt-get -y  --allow-downgrades \
            --allow-remove-essential \
            --allow-change-held-packages \
            install --no-install-recommends fakeroot apt-utils apt zip unzip quilt wget lsb-release gnupg $EATMYDATA
apt-get -y  --allow-downgrades \
            --allow-remove-essential \
            --allow-change-held-packages \
            install --no-install-recommends aptitude pkgbinarymangler || true

#Add keys to upstream schroot (first get universe requirements).
if [ "$UPSTREAM" = "upstream" ] || [ "$UPSTREAM" = "debian" ]; then
add_sbuild_keys
cat /tmp/key.asc | gpg --dearmor | tee /etc/apt/trusted.gpg.d/builds-repo-key.gpg  >/dev/null
fi

# Set up expected /dev entries
if [ ! -r /dev/stdin ];  then ln -sf /proc/self/fd/0 /dev/stdin;  fi
if [ ! -r /dev/stdout ]; then ln -sf /proc/self/fd/1 /dev/stdout; fi
if [ ! -r /dev/stderr ]; then ln -sf /proc/self/fd/2 /dev/stderr; fi

apt-get -y  --allow-downgrades \
            --allow-remove-essential \
            --allow-change-held-packages \
            dist-upgrade
apt-get clean
echo "dash dash/sh boolean false" | debconf-set-selections
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dash

# Ensure resolf.conf is not a symlink
sed '' -i /etc/resolv.conf

# Clean up
rm /finish.sh
echo Finished self-setup
MAINEOF

cat << EOF > "$SBUILD_CREATE_DIR"/etc/apt/sources.list
deb $REPO $CODENAME main $UNIVERSE
deb $REPO $CODENAME-updates main $UNIVERSE
deb $REPO $CODENAME-security main $UNIVERSE

deb-src $REPO $CODENAME main $UNIVERSE
deb-src $REPO $CODENAME-updates main $UNIVERSE
deb-src $REPO $CODENAME-security main $UNIVERSE

#Trisquel builds repositories
#deb http://builds.trisquel.org/repos/$(cut -d '-' -f1 <<< "$CA_BASE")/ $(cut -d '-' -f1 <<< "$CA_BASE") main
#deb http://builds.trisquel.org/repos/$(cut -d '-' -f1 <<< "$CA_BASE")/ $(cut -d '-' -f1 <<< "$CA_BASE")-security main
EOF
if [ "$UPSTREAM" != "upstream" ];then
cat << EOF >> "$SBUILD_CREATE_DIR"/etc/apt/sources.list

#Ubuntu sources (only source packages)
deb-src $UBUSRC $UBURELEASE main universe
deb-src $UBUSRC $UBURELEASE-updates main universe
deb-src $UBUSRC $UBURELEASE-security main universe

EOF
fi
if [ "$UPSTREAM" = "debian" ];then
    if [ "$CODENAME" = "sid"      ]; then
cat << EOF > "$SBUILD_CREATE_DIR"/etc/apt/sources.list
deb $REPO $CODENAME main
deb-src $REPO $CODENAME main

EOF
    fi
    if [ "$CODENAME" = "bullseye" ] || \
       [ "$CODENAME" = "bookworm" ]; then
cat << EOF > "$SBUILD_CREATE_DIR"/etc/apt/sources.list
deb $REPO $CODENAME main
deb $REPO $CODENAME-updates main
deb $REPO-security $CODENAME-security main

deb-src $REPO $CODENAME main
deb-src $REPO $CODENAME-updates main
deb-src $REPO-security $CODENAME-security main

EOF
    fi
    if [ "$CODENAME" = "buster" ]; then
cat << EOF > "$SBUILD_CREATE_DIR"/etc/apt/sources.list
deb $REPO $CODENAME main
deb $REPO $CODENAME-updates main
deb http://security.debian.org/debian-security $CODENAME/updates main

deb-src $REPO $CODENAME main
deb-src $REPO $CODENAME-updates main
deb-src http://security.debian.org/debian-security $CODENAME/updates main

EOF
    fi
fi
mount -o bind /proc "$SBUILD_CREATE_DIR"/proc
chroot "$SBUILD_CREATE_DIR" bash -x /finish.sh
#Enable builds.trisquel.org repo
chroot "$SBUILD_CREATE_DIR" sed -i '/builds.trisquel.org/s|^#||g' /etc/apt/sources.list
umount "$SBUILD_CREATE_DIR"/proc

rm -rf /var/lib/schroot/chroots/"$CA_BASE"
[ -d /var/lib/schroot/chroots ] || mkdir /var/lib/schroot/chroots
cp -a "$SBUILD_CREATE_DIR" /var/lib/schroot/chroots/"$CA_BASE"
umount "$SBUILD_CREATE_DIR"
rm -r "$SBUILD_CREATE_DIR"

cat << EOF > /etc/schroot/chroot.d/sbuild-"$CA_BASE"
[$CA_BASE]
description=$CODENAME-$ARCH $UPSTREAM build.
groups=sbuild,root
root-groups=sbuild,root
source-root-groups=root,sbuild
type=directory
profile=sbuild
union-type=overlay
directory=/var/lib/schroot/chroots/$CA_BASE
command-prefix=linux$BITS,$EATMYDATA
EOF

rm -f /etc/schroot/setup.d/04tmpfs

if [ "$UPSTREAM" = "upstream" ] || [ "$UPSTREAM" = "debian" ];then
    [ -f /usr/share/debootstrap/scripts/$CODENAME ] && rm /usr/share/debootstrap/scripts/$CODENAME
    [ -f /usr/share/debootstrap/scripts/debian-common ] && rm /usr/share/debootstrap/scripts/debian-common
fi

sbuild-update -udcar "$CA_BASE"

echo "Setup of schroot $CA_BASE finished successfully"


