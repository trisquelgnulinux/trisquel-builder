#!/usr/bin/python3
#
#    Copyright (C) 2023  Ruben Rodriguez <ruben@trisquel.info>
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

import argparse

import watchdog3
from watchdog3 import build_cache, list_helper_packages, list_src, list_binaries, source_binary
from watchdog3 import TRISQUELRELEASES, TRISQUEL_REPO_KEY, UBUNTU_REPO_KEY

watchdog3.args = watchdog3.setup("Find packages that were removed from the Ubuntu \
        repositories at release time, but were left over in the Trisquel repository")

release = watchdog3.args.release[0]
upstream = TRISQUELRELEASES[release]['upstream']

cache = {}
cache["trisquel"] = build_cache("trisquel",
                                "http://archive.trisquel.org/trisquel",
                                [release, "%s-updates" % release,
                                 "%s-security" % release],
                                "main", release, TRISQUEL_REPO_KEY, True)
cache["ubuntu"] = build_cache("ubuntu",
                              "http://archive.ubuntu.com/ubuntu",
                              [upstream, "%s-updates" % upstream,
                               "%s-security" % upstream],
                              "main universe", release, UBUNTU_REPO_KEY, True)

helpers = list_helper_packages(release)

tsrc = list_src(cache["trisquel"]["source_records"])
usrc = list_src(cache["ubuntu"]["source_records"])
tbin = list_binaries(cache["trisquel"]["cache"])
ubin = list_binaries(cache["ubuntu"]["cache"])

srclist = []

for src in tsrc:
    if src not in helpers \
       and src not in usrc \
       and "trisquel" not in src \
       and "sugar-activity" not in src \
       and "app-install-data" not in src \
       and "atheros-firmware" not in src \
       and "openfwwf" not in src:
        if src not in srclist:
            srclist.append(src)

for src in srclist:
    print("src: %s" % src)

pkglist = []

for pkg in tbin:
    if pkg not in ubin:
        src = source_binary(pkg, cache["trisquel"]['cache'])
        if src not in srclist \
           and src not in helpers \
           and "trisquel" not in src \
           and "sugar-activity" not in src \
           and "app-install-data" not in src \
           and "atheros-firmware" not in src \
           and "openfwwf" not in src:
            if pkg not in pkglist:
                pkglist.append(pkg)

for pkg in pkglist:
    print("pkg: %s" % pkg)
