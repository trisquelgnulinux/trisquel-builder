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


import urllib2
import itertools
import subprocess
import zlib
import lzma
import apt_pkg
import os
import copy
import re

def calculatenewversion(package,dist):
    distversion=""
    if dist == "flidas": distversion="8.0"
    if dist == "etiona": distversion="9.0"
    if dist == "nabia": distversion="10.0"
    file=wd+'/package-helpers/helpers/make-'+package
    if os.path.exists(file):
        with open(file) as helper:
            for line in helper:
                if line.startswith("VERSION="):
                    version=line.replace("VERSION=","").replace("\n","")
                    return "+"+distversion+"trisquel"+version
    return ""

def warn(text):
    print "             WARNING: " + text

def listmirror(dic, mirror, dist, component):
    urlbuilder = mirror + "/dists/" + dist + "/" + component + "/source/Sources.{}"
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
                warn("Could not fetch sources for: \'{}/{} {}\'".format(mirror, dist, component))
                return

    if url.split(".")[-1] == "gz":
        try:
            pkglist = zlib.decompress(urldata[url], 16+zlib.MAX_WBITS)
        except Exception as e:
            warn(url + ": " + str(e))
            return
    elif url.split(".")[-1] == "xz":
        try:
            pkglist = lzma.decompress(urldata[url])
        except Exception as e:
            warn(url + ": " + str(e))
            return
    else:
        warn("Unknown compression extension: " + url.split(".")[-1])
        return

    pkgmap = map(str.strip, pkglist.splitlines())
    for key,group in itertools.groupby(pkgmap, lambda x: x == ''):
        if not key:
            data={}
            for item in group:
                if 'Package: ' in item or  'Version: ' in item:
                    field,value=item.split(': ')
                    value=value.strip()
                    data[field]=value
            if dic.has_key(data['Package']):
                if apt_pkg.version_compare(data['Version'],dic[data['Package']]) > 0:
                    dic[data['Package']]=data['Version']
            else:
                dic[data['Package']]=data['Version']

def listdistro(dic, url, dist, component):
    for dist in dist, dist+"-updates",dist+"-security":
        listmirror(dic, url, dist, component)

def compare(udic, tdic,trisqueldist):
    linuxmeta=False
    for item in tdic:
        if udic.has_key(item):
            if 'trisquel' in tdic[item]:
                newversion=calculatenewversion(item,trisqueldist)
                #print item
                #print tdic[item]+" "+udic[item]+newversion
                #print re.split(':',tdic[item])[-1],udic[item]+newversion
                #print apt_pkg.version_compare(re.split(':',tdic[item])[-1],udic[item]+newversion)
                #if apt_pkg.version_compare(tdic[item],udic[item]) < 0:
                if (apt_pkg.version_compare(re.split(':',tdic[item])[-1], re.split(":",udic[item]+newversion)[-1]) < 0):
                    # TODO: if item == "grub"
                    if "linux-meta" in item:
                        metaver=udic[item].split('.')
                        metaver='.'.join(metaver[:4])
                        try:
                            linuxver=tdic[item.replace('-meta','')].replace('-','.').split('.')
                        except KeyError:
                            print item
                            linuxver="0"
                        linuxver='.'.join(linuxver[:4])
                        if apt_pkg.version_compare(metaver, linuxver) >0:
                            warn ("Skipping compilation of " + item + " "  +  metaver + " because " + item.replace('-meta','') + " package in Trisquel is " + linuxver)
                            continue
                    if os.path.exists(wd+'/package-helpers/helpers/make-'+item):
                        print "Package " + item + " can be upgraded to version " + udic[item] + gettrisquelversion(item) + " current "+ trisqueldist +" version is " + tdic[item]
                    else:
                        warn(item + ' helper not found')
def comparepackage(udic, tdic, package,trisqueldist):
    if not udic.has_key(package):
        warn('package '+package+' not found upstream')
        return
    if not tdic.has_key(package):
        warn('package '+package+' not found in Trisquel')
        print "Package " + package + " can be upgraded to version " + udic[package] + gettrisquelversion(package) + " current " + trisqueldist +" version is missing"
        return
    if apt_pkg.version_compare(tdic[package],udic[package]) < 0:
        print "Package " + package + " can be upgraded to version " + udic[package] + gettrisquelversion(package) + " current " + trisqueldist +" version is " + tdic[package]

def gettrisquelversion(package):
    revision=subprocess.check_output('/bin/grep "export REVISION=" '+wd+'/package-helpers/helpers/config |sed "s/.*=//"', shell=True).splitlines()[0]
    version=subprocess.check_output('/bin/grep ^VERSION= '+wd+'/package-helpers/helpers/make-'+package+'|sed "s/.*=//" ', shell=True).splitlines()[0]
    return '+'+revision+'trisquel'+version

def checkversions(ubuntudist,trisqueldist):
    global basetdic,baseudic
    listdistro(udic, "http://archive.ubuntu.com/ubuntu", ubuntudist, "main")
    listdistro(udic, "http://archive.ubuntu.com/ubuntu", ubuntudist, "universe")
    listdistro(tdic, "http://archive.trisquel.org/trisquel", trisqueldist, "main")
    listmirror(tdic, "http://builds.trisquel.org/repos/"+trisqueldist, trisqueldist, "main")
    listmirror(tdic, "http://builds.trisquel.org/repos/"+trisqueldist, trisqueldist+"-security", "main")
    basetdic=copy.deepcopy(tdic)
    baseudic=copy.deepcopy(udic)
    compare(udic, tdic,trisqueldist)

def externals(upstream, branch):
    packages = subprocess.check_output(gitcommand +'ls-tree -r --name-only '+branch+' |grep helpers/make- |sed "s/.*make-//"', shell=True).splitlines()
    for package in packages:
        external=''
        backport=''
        try:
            external=subprocess.check_output(gitcommand +'show '+branch+':helpers/make-'+package+' |grep EXTERNAL ', shell=True).splitlines()
            backport=subprocess.check_output(gitcommand +'show '+branch+':helpers/make-'+package+' |grep BACKPORT ', shell=True).splitlines()
        except:
            pass
        if external != '':
            external[0]=external[0].replace("\'","")
            external[0]=external[0].replace("\"","")
            external=external[0].replace("EXTERNAL=","")
            external=external.replace("$UPSTREAM",upstream)
            external=external.replace("deb-src ","")
            if backport != '':
                tdic={}
                udic={}
                listmirror(tdic, "http://archive.trisquel.org/trisquel", branch+"-backports", "main")
                listmirror(tdic, "http://builds.trisquel.org/repos/"+branch, branch+"-backports", "main")
                for component in external.split()[2:]:
                    listmirror(udic, external.split()[0], external.split()[1], component)
                comparepackage(udic, tdic, package, branch)
            if backport == '':
                udic=copy.deepcopy(baseudic)
                tdic=copy.deepcopy(basetdic)
                for component in external.split()[2:]:
                    listmirror(udic, external.split()[0], external.split()[1], component)
                comparepackage(udic, tdic, package, branch)

apt_pkg.init_system()

wd='/dev/shm'

if not os.path.exists(wd+"/package-helpers"):
    os.system('/usr/bin/git clone https://gitlab.trisquel.org/trisquel/package-helpers.git '+ wd +"/package-helpers")

gitcommand='/usr/bin/git --git-dir='+wd+'/package-helpers/.git --work-tree='+wd+'/package-helpers/ '

for pair in ['focal','nabia'],['bionic','etiona'],['xenial','flidas']:
    urldata={}
    tdic={}
    basetdic={}
    udic={}
    baseudic={}
    print "========================================================================="
    print "Checking pair: " + str(pair)
    os.system(gitcommand +'checkout ' + pair[1])
    os.system(gitcommand + 'pull')
    checkversions(pair[0], pair[1])
    externals(pair[0], pair[1])
