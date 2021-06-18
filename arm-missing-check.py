#    Copyright (C) 2015-2021  Ruben Rodriguez <ruben@trisquel.info>
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


# This sript checks for missing arm packages that are available for amd64

import urllib2
import itertools
import subprocess
import zlib
#import lzma
import apt_pkg
import os
import copy
import re

urldata={}

def listmirror(mirror, dist, component, arch):
    dic={}
    urlbuilder = mirror + "/dists/" + dist + "/" + component + "/binary-" + arch + "/Packages.gz"
    compressionexts = ["gz", "xz"]
    url = None
    for comp in compressionexts:
        if urlbuilder.format(comp) in urldata:
            url = urlbuilder.format(comp)
            break
    if url is None:
        for i, comp in enumerate(compressionexts):
            url = urlbuilder.format(comp)
            try:
                urldata[url] = urllib2.urlopen(url).read()
                break
            except urllib2.URLError as e:
                pass
            # If we reached the end, we did not find a Sources file
            if i == len(compressionexts) - 1:
                print("Could not fetch sources for: \'{}/{} {}\'".format(mirror, dist, component))
                return

    if url.split(".")[-1] == "gz":
        try:
            pkglist = zlib.decompress(urldata[url], 16+zlib.MAX_WBITS)
        except Exception as e:
            print(url + ": " + str(e))
            return
    elif url.split(".")[-1] == "xz":
        try:
            pkglist = lzma.decompress(urldata[url])
        except Exception as e:
            print(url + ": " + str(e))
            return
    else:
        print("Unknown compression extension: " + url.split(".")[-1])
        return

    pkgmap = map(str.strip, pkglist.splitlines())
    for key,group in itertools.groupby(pkgmap, lambda x: x == ''):
        if not key:
            data={}
            for item in group:
                if 'Package: ' in item or  'Version: ' in item or 'Architecture: ' in item:
                    field,value=item.split(': ')
                    value=value.strip()
                    data[field]=value
                if 'Source: ' in item:
                    data['Package']=item.split(': ')[1]
            if data['Architecture'] != arch: continue
            if dic.has_key(data['Package']):
                if apt_pkg.version_compare(data['Version'],dic[data['Package']]) > 0:
                    dic[data['Package']]=data['Version']
            else:
                dic[data['Package']]=data['Version']
            if data.has_key('Source'):
                dic[data['Package']]=data['Source']
    return dic

apt_pkg.init_system()

mirror="https://builds.trisquel.org/repos/nabia"

for dist in ["nabia","nabia-security", "nabia-backports"]:
    dicarm=listmirror(mirror, dist, "main", "armhf")
    dicamd=listmirror(mirror, dist, "main", "amd64")
    for package in dicamd:
        if package not in dicarm or dicamd[package] != dicarm[package]:
            print "Missing arm package: %s - amd64 version: %s" % (package, dicamd[package])
