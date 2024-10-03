#!/bin/bash
#
#    Copyright (C) 2018-2021  Ruben Rodriguez <ruben@trisquel.info>
#    Copyright (C) 2024  Luis Guzman <ark@switnet.org>
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

# https://wiki.debian.org/sbuild

# True if $1 is greater than $2
version_gt() { dpkg --compare-versions "$1" gt "$2"; }

if [ "$EUID" -ne 0 ]; then
   echo "This script must be run as root"
   exit 1
fi

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
   echo Usage: "$0" CODENAME ARCH UPSTREAM \(optional\)
   echo Example 1: "$0" aramo amd64
   echo Example 2: "$0" bullseye amd64
   echo Example 3: "$0" ecne amd64 upstream
   exit 1
fi

set -e

#------------------------------------------------
# Set initial variables.
#------------------------------------------------
CODENAME="$1"
ARCH="$2"
UPSTREAM="$3"
HOST_OS="$(lsb_release -si)"
DBSTRAP_VER="$(dpkg-query -s debootstrap 2>/dev/null|awk '/Version/{print$2}')"
PORTS=false
EATMYDATA=eatmydata
UBUSRC=http://archive.ubuntu.com/ubuntu
## debootstrap and keyring files setup using git submodules.
DBSTRAP_SCRIPTS="debootstrap/scripts"
SYSTEM_DBSTRAP_SCRIPTS="/usr/share/debootstrap/scripts/"
DEBIAN_KEYRING_FOLDER="debian-archive-keyring"
KEYRING_FILE="ubuntu-keyring/keyrings/ubuntu-archive-keyring.gpg"
TRISQUEL_KEYRING_FILE="trisquel-packages/extra/trisquel-keyring/keyrings/trisquel-archive-keyring.gpg"
EXTRACTOR="dpkg-deb"
REPO="http://archive.trisquel.org/trisquel"

#------------------------------------------------
# Check for minimal required dependencies to use script.
#------------------------------------------------
[ ! -d "$DEBIAN_KEYRING_FOLDER/apt-trusted-asc" ] &&
echo "Don't forget to init git submodules of the repo." && exit
for i in debootstrap sbuild schroot ; do
    [ -z "$(dpkg-query -l|grep "$i")" ] && \
    printf "> Minimal dependecies required: debootstrap sbuild schroot\n" && \
    exit
done


#------------------------------------------------
# Setup variables logic from input.
#------------------------------------------------
[ "$ARCH" = "i386"  ] || [ "$ARCH" = "armhf" ] && BITS=32
[ "$ARCH" = "amd64" ] || [ "$ARCH" = "arm64" ] || [ "$ARCH" = "ppc64el" ] && BITS=64
[ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ] || [ "$ARCH" = "ppc64el" ] && PORTS=true
[ "$BITS" == "32" ] && EATMYDATA=""
[ "$ARCH" = "ppc64el" ] && EXTRACTOR="ar"
[ "$CODENAME" == "buster"   ] && UPSTREAM="debian" && VALID=1
[ "$CODENAME" == "bullseye" ] && UPSTREAM="debian" && VALID=1
[ "$CODENAME" == "bookworm" ] && UPSTREAM="debian" && VALID=1
[ "$CODENAME" == "trixie"   ] && UPSTREAM="debian" && VALID=1
[ "$CODENAME" == "sid"      ] && UPSTREAM="debian" && VALID=1
[ "$CODENAME" == "ecne"   ] && UBURELEASE="noble" &&  VALID=1
[ "$CODENAME" == "aramo"  ] && UBURELEASE="jammy"  && VALID=1
[ "$CODENAME" == "nabia"  ] && UBURELEASE="focal"  && VALID=1
[ "$CODENAME" == "etiona" ] && UBURELEASE="bionic" && VALID=1
"$PORTS" && UBUSRC=http://ports.ubuntu.com/

if [ "$VALID" != 1 ]; then
    echo "Not valid codename"
    exit 1
fi

#------------------------------------------------
# Set debootstrap repo according to the script input.
#------------------------------------------------
[ "$UPSTREAM" = "upstream" ] && \
REPO="http://archive.ubuntu.com/ubuntu" && \
TRISQUELREPO="http://archive.trisquel.org/trisquel" && \
"$PORTS" && REPO="$UBUSRC"
#
[ "$UPSTREAM" = "debian" ] && \
REPO="http://deb.debian.org/debian"

echo -e "\\nOS: $HOST_OS \\ndebootstrap: $DBSTRAP_VER\\n"

#------------------------------------------------
# Upgrade (if required) and setup debootstrap package.
#------------------------------------------------
## - Debian host | aramo schroot
if [ "$HOST_OS" = "Debian" ] && version_gt 1.0.124 "$DBSTRAP_VER" && \
   [ "$CODENAME" = "aramo" ]; then
    echo "It is required to upgrade debootstrap to create a $CODENAME jail, upgrading..."
    {
    echo "#Pinned repo (see /etc/apt/preferences.d/debootstrap)."
    echo "deb http://deb.debian.org/debian bookworm main"
    } > /etc/apt/sources.list.d/debootstrap.list
    {
    echo "Package: *"
    echo "Pin: release n=bookworm"
    echo "Pin-Priority: 1"
    } > /etc/apt/preferences.d/debootstrap

    apt-get update -q2
    apt-get -t bookworm -y install debootstrap
fi
## - Trisquel / Ubuntu host | aramo schroot
if [ "$HOST_OS" != "Debian" ] && version_gt 1.0.124 "$DBSTRAP_VER" && \
   [ "$CODENAME" = "aramo" ]; then
    echo "It is required to upgrade debootstrap to create the $CODENAME jail, upgrading..."
    ### Add variables to meet either OS.
    [ "$HOST_OS" = "Trisquel" ] && REPO_ARCHIVE="$REPO" && REPO_DIST="$CODENAME"
    [ "$HOST_OS" = "Ubuntu" ] && REPO_ARCHIVE="$UBUSRC" && REPO_DIST="$UBURELEASE"
    "$PORTS" && BIN_URL="ubuntu-ports"
    ### Set custom OS backport repository.
    {
    echo "#Pinned repo (see /etc/apt/preferences.d/debootstrap)."
    echo "deb $REPO_ARCHIVE$BIN_URL $REPO_DIST main"
    } > /etc/apt/sources.list.d/debootstrap.list
    {
    echo "Package: *"
    echo "Pin: release n=$REPO_DIST"
    echo "Pin-Priority: 1"
    } > /etc/apt/preferences.d/debootstrap

    apt-get update -q2
    apt-get -t "$REPO_DIST" -y install --reinstall debootstrap
fi
# Delete tmp deboostrap pinned repo.
rm -f /etc/apt/sources.list.d/debootstrap.list \
      /etc/apt/preferences.d/debootstrap

#------------------------------------------------
# Prepare debootstrap and chroot
#------------------------------------------------
CA_BASE="$CODENAME-$ARCH"
TBR_CODENAME="$CODENAME" # not used (overwritten) on debian chroots.
SBUILD_CREATE_DIR="/tmp/sbuild-create/$CA_BASE"

## Fix variables to use trisquel codename as upstream value on schroot.
[ "$UPSTREAM" = "upstream" ] && \
TRISQUELNAME="$CODENAME" && \
CODENAME="$UBURELEASE" && \
UNIVERSE="universe"

[ -z "$UPSTREAM" ] && \
if [ -f "$DBSTRAP_SCRIPTS/$CODENAME" ]; then
  DBSTRAP_SCRIPTS="$DBSTRAP_SCRIPTS"
elif [ -f "$SYSTEM_DBSTRAP_SCRIPTS/$CODENAME" ] ;then
  DBSTRAP_SCRIPTS="$SYSTEM_DBSTRAP_SCRIPTS"
else
  echo "No available \"$CODENAME\" debootstrap script at:"
  echo "  - $DBSTRAP_SCRIPTS"
  echo "  - $SYSTEM_DBSTRAP_SCRIPTS"
  exit
fi

## Create chroot on tmpfs
umount /tmp/sbuild-create/*/proc || true
umount /tmp/sbuild-create/*"$ARCH"/ || true
rm -rf /tmp/sbuild-create/*
mkdir -p "$SBUILD_CREATE_DIR"
mount -t tmpfs none "$SBUILD_CREATE_DIR"

## Standalone setup keyring and debootstrap script file for supported OSes.
[ "$HOST_OS" = "Trisquel" ] && [ "$UPSTREAM" = "upstream" ] && \
PRE_BUILD_KEYRING="--keyring=$KEYRING_FILE"
[ "$HOST_OS" != "Trisquel" ] && [ -z "$UPSTREAM" ] && \
PRE_BUILD_KEYRING="--keyring=$TRISQUEL_KEYRING_FILE"
[ "$UPSTREAM" = upstream ] && \
PRE_BUILD_KEYRING="--keyring=$KEYRING_FILE"
[ "$UPSTREAM" = "debian" ] && \
cat "$DEBIAN_KEYRING_FOLDER"/apt-trusted-asc/*automatic.asc > \
    "$DEBIAN_KEYRING_FOLDER"/debian-apt-keyring.asc && \
cat "$DEBIAN_KEYRING_FOLDER"/debian-apt-keyring.asc | gpg --dearmour | \
    tee "$DEBIAN_KEYRING_FOLDER"/debian-apt-keyring.gpg > /dev/null && \
PRE_BUILD_KEYRING="--keyring=$DEBIAN_KEYRING_FOLDER/debian-apt-keyring.gpg"

[ -z "$PRE_BUILD_KEYRING" ] && PRE_BUILD_KEYRING="--verbose"
debootstrap --arch="$ARCH" \
            --extractor=$EXTRACTOR \
            --variant=minbase \
            --components=main \
            "$PRE_BUILD_KEYRING" \
            --include=apt \
            "$CODENAME" \
            "$SBUILD_CREATE_DIR" \
            "$REPO" \
            "$DBSTRAP_SCRIPTS/$CODENAME"

#------------------------------------------------
# Prepare chroot environment install script.
#------------------------------------------------
wget http://builds.trisquel.org/repos/signkey.asc  -O "$SBUILD_CREATE_DIR"/tmp/key.asc

cat << MAINEOF > "$SBUILD_CREATE_DIR"/finish.sh
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

#Add gpg key via gpg server to keyring storage.
add_gpg_keyring() {
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com \$1
apt-key export \$1 | gpg --dearmour | tee /tmp/\$1.gpg >/dev/null
apt-key del \$1
mv /tmp/\$1.gpg /etc/apt/trusted.gpg.d/
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
# Install packages that might fail separately otherwise all the line will
# not get installed (aptitude).
apt-get -y  --allow-downgrades \
            --allow-remove-essential \
            --allow-change-held-packages \
            install --no-install-recommends pkgbinarymangler
apt-get -y  --allow-downgrades \
            --allow-remove-essential \
            --allow-change-held-packages \
            install --no-install-recommends aptitude || true

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

#------------------------------------------------
# Setup chroot OS repositories.
#------------------------------------------------
## Trisquel / *buntu chroot sources file.
{
echo "deb $REPO $CODENAME main $UNIVERSE"
echo "deb $REPO $CODENAME-updates main $UNIVERSE"
echo "deb $REPO $CODENAME-security main $UNIVERSE"
echo ""
echo "deb-src $REPO $CODENAME main $UNIVERSE"
echo "deb-src $REPO $CODENAME-updates main $UNIVERSE"
echo "deb-src $REPO $CODENAME-security main $UNIVERSE"
echo ""
echo "#Trisquel builds repositories"
echo "#deb http://builds.trisquel.org/repos/$TBR_CODENAME/ $TBR_CODENAME main"
echo "#deb http://builds.trisquel.org/repos/$TBR_CODENAME/ $TBR_CODENAME-security main"
} > "$SBUILD_CREATE_DIR"/etc/apt/sources.list

## Add additional source repositories (used at BUILDONLYARCH).
if [ "$UPSTREAM" != "upstream" ];then
    {
    echo ""
    echo "#Ubuntu sources (only source packages)"
    echo "deb-src $UBUSRC $UBURELEASE main universe"
    echo "deb-src $UBUSRC $UBURELEASE-updates main universe"
    echo "deb-src $UBUSRC $UBURELEASE-security main universe"
    } >> "$SBUILD_CREATE_DIR"/etc/apt/sources.list
else
    {
    echo ""
    echo "#Trisquel sources (only source packages)"
    echo "#SRdeb-src $TRISQUELREPO $TRISQUELNAME main"
    echo "#SRdeb-src $TRISQUELREPO $TRISQUELNAME-updates main"
    echo "#SRdeb-src $TRISQUELREPO $TRISQUELNAME-security main"
    } >> "$SBUILD_CREATE_DIR"/etc/apt/sources.list
fi
## Setup Debian distribution chroot sources file.
if [ "$UPSTREAM" = "debian" ];then
    if [ "$CODENAME" = "sid"      ]; then
        {
        echo "deb $REPO $CODENAME main"
        echo "deb-src $REPO $CODENAME main"
        echo ""
        } > "$SBUILD_CREATE_DIR"/etc/apt/sources.list
    fi
    if [ "$CODENAME" = "bullseye" ] || \
       [ "$CODENAME" = "trixie" ] || \
       [ "$CODENAME" = "bookworm" ]; then
        {
        echo "deb $REPO $CODENAME main"
        echo "deb $REPO $CODENAME-updates main"
        echo "deb $REPO-security $CODENAME-security main"
        echo ""
        echo "deb-src $REPO $CODENAME main"
        echo "deb-src $REPO $CODENAME-updates main"
        echo "deb-src $REPO-security $CODENAME-security main"
        } > "$SBUILD_CREATE_DIR"/etc/apt/sources.list
    fi
    if [ "$CODENAME" = "buster" ]; then
        {
        echo "deb $REPO $CODENAME main"
        echo "deb $REPO $CODENAME-updates main"
        echo "deb http://security.debian.org/debian-security $CODENAME/updates main"
        echo ""
        echo "deb-src $REPO $CODENAME main"
        echo "deb-src $REPO $CODENAME-updates main"
        echo "deb-src http://security.debian.org/debian-security $CODENAME/updates main"
        echo ""
        } > "$SBUILD_CREATE_DIR"/etc/apt/sources.list
    fi
fi

#------------------------------------------------
# Excecute chroot finish.sh and tweak sources file.
#------------------------------------------------
mount -o bind /proc "$SBUILD_CREATE_DIR"/proc
chroot "$SBUILD_CREATE_DIR" bash -x /finish.sh
## Delayed enabled repos as ubuntu doesn't have gpg on main to add keys earlier.
[ -z "$DEVELOPMENT" ] && \
chroot "$SBUILD_CREATE_DIR" sed -i '/builds.trisquel.org/s|^#||g' /etc/apt/sources.list
[ -z "$DEVELOPMENT" ] && \
chroot "$SBUILD_CREATE_DIR" sed -i 's|^#SR||g' /etc/apt/sources.list
umount "$SBUILD_CREATE_DIR"/proc

## Move finished tmpfs chroot to /var/lib/schroot/chroots
rm -rf /var/lib/schroot/chroots/"$CA_BASE"
[ -d /var/lib/schroot/chroots ] || mkdir /var/lib/schroot/chroots
cp -a "$SBUILD_CREATE_DIR" /var/lib/schroot/chroots/"$CA_BASE"
umount "$SBUILD_CREATE_DIR"
rm -rf /tmp/sbuild-create/

{
echo "[$CA_BASE]"
echo "description=$CODENAME-$ARCH $UPSTREAM build."
echo "groups=sbuild,root"
echo "root-groups=sbuild,root"
echo "source-root-groups=root,sbuild"
echo "type=directory"
echo "profile=sbuild"
echo "union-type=overlay"
echo "directory=/var/lib/schroot/chroots/$CA_BASE"
echo "command-prefix=linux$BITS,$EATMYDATA"
}  > /etc/schroot/chroot.d/sbuild-"$CA_BASE"

rm -f /etc/schroot/setup.d/04tmpfs

sbuild-update -udcar "$CA_BASE"

echo "Setup of schroot $CA_BASE finished successfully"
