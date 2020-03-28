#!/bin/bash

#    Copyright (C) 2019  Ruben Rodriguez <ruben@trisquel.info>
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

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 https://gitserver/repo.git distcodename [ subdir ] [ branch ]"
    echo "Example: $0 https://gitserver/repo.git flidas [ src ] [ testing ]"
    exit 0
fi

REPO=$1
BUILDDIST=$2
DIR=${3:-/}
BRANCH="${4:-master}"
TMPDIR=$(mktemp -d)
cd $TMPDIR
mkdir git

#trap "rm -rf ${TMPDIR}" 0 HUP INT QUIT ILL ABRT FPE SEGV PIPE TERM

git clone $REPO -b $BRANCH $TMPDIR/git

PKGDIR=$(sed -n 's/ /-/;s/(//;s/).*//;1p' $TMPDIR/git/$DIR/debian/changelog)
mv $TMPDIR/git/$DIR $TMPDIR/$PKGDIR

dpkg-source -b $PKGDIR/

sbuild -v --dist $BUILDDIST --arch amd64 *.dsc --no-arch-all  --resolve-alternatives
sbuild -v --dist $BUILDDIST --arch i386 *.dsc --source --arch-all --resolve-alternatives

echo Package built succesfully at $TMPDIR
