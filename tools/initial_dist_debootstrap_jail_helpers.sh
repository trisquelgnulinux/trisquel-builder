#!/bin/bash

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

##
# This script is heavily based on the sbuild-create.sh one, it even uses the same
# submodules to pull a debootstrap dir so we can automatically gather and match
# packages helpers used on a schroot jail, so they are the first helpers to be
# reviewed and build for the new release, so we can get a working trisquel jail
# right away.
##

if [ $# -lt 2 ] || [ $# -gt 2 ]; then
   echo "Usage: $0 CODENAME upstream"
   echo " > Example: $0 ecne upstream"
   exit 1
fi

CODENAME="$1"
UPSTREAM="$2"
DBSTRAP_SCRIPTS="../debootstrap/scripts"
KEYRING_FILE="../ubuntu-keyring/keyrings/ubuntu-archive-keyring.gpg"
PACKAGE_HELPERS_REPO="https://gitlab.trisquel.org/trisquel/package-helpers.git"
EXTRACTOR="dpkg-deb"
REPO="http://archive.ubuntu.com/ubuntu"
PH_HELPERS_DIR="debootstrap-helpers"

#------------------------------------------------
# Check for minimal required dependencies to use script.
#------------------------------------------------
[ ! -d $DBSTRAP_SCRIPTS ] &&
echo "Don't forget to init git submodules of the repo." && exit 1
[ ! -d $PH_HELPERS_DIR/helpers ] && \
git clone $PACKAGE_HELPERS_REPO $PH_HELPERS_DIR
for i in debootstrap git ; do
    [ -z "$(dpkg-query -l|grep "$i")" ] && \
    printf " > Minimal dependecies required: debootstrap\n" && \
    exit 1
done
echo "Check for sources enabled repos."
[ -n "$(apt-cache madison debootstrap|grep Sources)" ] && \
    echo " > Ok, seems sources are enabled"
[ -z "$(apt-cache madison debootstrap|grep Sources)" ] &&
    echo " > No sources repos seem available" && exit 1

#------------------------------------------------
# Setup variables logic from input.
#------------------------------------------------
[ "$CODENAME" == "ecne"   ] && UBURELEASE="noble" &&  VALID=1 && DEVELOPMENT=1
[ "$CODENAME" == "aramo"  ] && UBURELEASE="jammy"  && VALID=1
[ "$CODENAME" == "nabia"  ] && UBURELEASE="focal"  && VALID=1
[ "$CODENAME" == "etiona" ] && UBURELEASE="bionic" && VALID=1

if [ "$VALID" != 1 ]; then
    echo "> Not valid codename"
    exit 1
fi

echo -e "\n> Set package helpers $CODENAME branch."
cd $PH_HELPERS_DIR
git checkout $CODENAME
cd ..

CODENAME="$UBURELEASE"
PRE_BUILD_KEYRING="--keyring=$KEYRING_FILE"
TMP_DBSTRAP_DIR=/tmp/${CODENAME}_dbstrap_dir

[ ! -d "$TMP_DBSTRAP_DIR" ] && mkdir $TMP_DBSTRAP_DIR

sudo -v
echo -e "\n > Fetching debootrap base requires sudo, this will take time please wait...\n"
echo "Initial helper review list for $CODENAME debootstrap jail build:"
echo "------"
for a in $(\
    for b in \
    $(sudo debootstrap \
        --extractor=$EXTRACTOR \
        --variant=minbase \
        --components=main \
        "$PRE_BUILD_KEYRING" \
        --include=apt \
        "$CODENAME" \
        "$TMP_DBSTRAP_DIR" \
        "$REPO" \
        "$DBSTRAP_SCRIPTS/$CODENAME"  | \
      grep Validating | \
      sed '/Packages/d' | \
      awk '{print$3}')
    do
        apt-cache madison "$b" |  grep Sources | awk '{print$1}'
    done | awk '!a[$0]++')
do
    [ -f $PH_HELPERS_DIR/helpers/make-"$a" ] && \
    wc -c $PH_HELPERS_DIR/helpers/make-"$a" | sed "s|$PH_HELPERS_DIR/helpers/||"
    for i in $( \
                grep "install" ../sbuild-create.sh | \
                grep -v '#' | \
                grep -v ' true' | \
                grep -v "REPO_DIST"| \
                sed 's|$.*||' | \
                sed 's| --no-install-recommends||' | \
                awk -F 'install' '{print$2}' | \
                xargs )
    do
        [ -f $PH_HELPERS_DIR/helpers/make-"$i" ] && \
        wc -c $PH_HELPERS_DIR/helpers/make-"$i" | sed "s|$PH_HELPERS_DIR/helpers/||"
    done
done | awk '!a[$0]++' | sort -rn
echo "------"
echo "Done"

sudo rm -rf $PH_HELPERS_DIR $TMP_DBSTRAP_DIR wget-log*

