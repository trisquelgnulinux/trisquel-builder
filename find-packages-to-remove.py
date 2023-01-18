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
from watchdog3 import build_cache, list_helper_packages, list_src
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
                                "main", release, TRISQUEL_REPO_KEY)
cache["ubuntu"] = build_cache("ubuntu",
                              "http://archive.ubuntu.com/ubuntu",
                              [upstream, "%s-updates" % upstream,
                               "%s-security" % upstream],
                              "main universe", release, UBUNTU_REPO_KEY)

helpers = list_helper_packages(release)

tpackages = list_src(cache["trisquel"]["source_records"])
upackages = list_src(cache["ubuntu"]["source_records"])

for pkg in tpackages:
    if pkg not in helpers and pkg not in upackages \
      and "trisquel" not in pkg \
      and "sugar-activity" not in pkg \
      and "app-install-data" not in pkg \
      and "atheros-firmware" not in pkg \
      and "openfwwf" not in pkg:
        print(pkg)
