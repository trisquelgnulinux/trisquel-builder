#    Copyright (C) 2015-2019  Ruben Rodriguez <ruben@trisquel.info>
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
import apt_pkg
import os

apt_pkg.init_system()

blacklist={}
blacklist={
  "belenos":["electrum","fop","qelectrotech","qtox","toxic","utox","zam-plugins"],
  "flidas":[],
  "etiona":[]
}


class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'

def calculatenewversion(package,dist):
    distversion=""
    if dist == "belenos": distversion="7.0"
    if dist == "flidas": distversion="8.0"
    if dist == "etiona": distversion="9.0"
    file=wd+'/package-helpers/helpers/make-'+package
    if os.path.exists(file):
        with open(file) as helper:
            for line in helper:
                if line.startswith("VERSION="):
                    version=line.replace("VERSION=","")
                    return "+"+distversion+"trisquel"+version
    return ""

def warn(text):
    print bcolors.WARNING + "WARNING: " + text + bcolors.ENDC

def listmirror(dic, url, dist, component):
    url = url + "/dists/" + dist + "/" + component + "/source/Sources.gz"
    if url not in urldata:
      try:
          #print "Downloading: " + url
          urldata[url] = urllib2.urlopen(url).read()
      except:
          warn( url + " 404")
          return
    pkglist = zlib.decompress(urldata[url], 16+zlib.MAX_WBITS)
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
                #newversion=calculatenewversion(item,trisqueldist)
                #print "item"
                #print item
                #print "tdic[item]++udic[item]+newversion"
                #print tdic[item]+" - "+udic[item]+newversion
                #print "apt_pkg.version_compare(tdic[item],udic[item]+newversion)"
                #print apt_pkg.version_compare(tdic[item],udic[item]+newversion)
                #print "endprint"
                #if (apt_pkg.version_compare(tdic[item],udic[item]+newversion) < 0) or (apt_pkg.version_compare(tdic[item],udic[item]) < 0):
                if apt_pkg.version_compare(tdic[item],udic[item]) < 0:
                    # TODO: if item == "grub"
                    #if item == "linux-meta":
                    if "linux-meta" in item:
                        metaver=udic[item].split('.')
                        metaver='.'.join(metaver[:4])
                        print metaver
                        try:
                            linuxver=tdic[item.replace('-meta','')].replace('-','.').split('.')
                        except KeyError:
                            print item
                            linuxver="0"
                        linuxver='.'.join(linuxver[:4])
                        if apt_pkg.version_compare(metaver, linuxver) >0:
                            warn ("Skipping compilation of " + item + " "  +  metaver + " because " + item.replace('-meta','') + " package in Trisquel is " + linuxver + bcolors.ENDC)
                            continue
                    if os.path.exists(wd+'/package-helpers/helpers/make-'+item):
                        if item not in blacklist[trisqueldist]:
                            print "Package " + item + " can be upgraded to version " + udic[item] + gettrisquelversion(item) + " current "+ trisqueldist +" version is " + tdic[item]
                    else:
                        warn(item + ' helper not found')
                    #print "sh makepackage " + item
def comparepackage(udic, tdic, package,trisqueldist):
    if not udic.has_key(package):
        warn('package '+package+' not found upstream')
        return
    if not tdic.has_key(package):
        warn('package '+package+' not found in Trisquel')
        print "Package " + package + " can be upgraded to version " + udic[package] + gettrisquelversion(package) + " current " + trisqueldist +" version is missing"
        return
    if apt_pkg.version_compare(tdic[package],udic[package]) < 0:
       if package not in blacklist[trisqueldist]:
           print "Package " + package + " can be upgraded to version " + udic[package] + gettrisquelversion(package) + " current " + trisqueldist +" version is " + tdic[package]

def gettrisquelversion(package):
    #if not os.path.exists(wd+'/package-helpers/helpers/make-'+package):
    #    return "helper not found"
    revision=subprocess.check_output('/bin/grep "export REVISION=" '+wd+'/package-helpers/helpers/config |sed "s/.*=//"', shell=True).splitlines()[0]
    version=subprocess.check_output('/bin/grep ^VERSION= '+wd+'/package-helpers/helpers/make-'+package+'|sed "s/.*=//" ', shell=True).splitlines()[0]
    return '+'+revision+'trisquel'+version

def checkversions(ubuntudist,trisqueldist):
    listdistro(udic, "http://archive.ubuntu.com/ubuntu", ubuntudist, "main")
    listdistro(udic, "http://archive.ubuntu.com/ubuntu", ubuntudist, "universe")
    listdistro(tdic, "http://archive.trisquel.info/trisquel", trisqueldist, "main")
    listmirror(tdic, "http://devel.trisquel.info/repos/trisquel/"+trisqueldist, trisqueldist, "main")
    listmirror(tdic, "http://devel.trisquel.info/repos/trisquel/"+trisqueldist, trisqueldist+"-security", "main")
    listmirror(tdic, "http://devel.trisquel.info/repos/trisquel/"+trisqueldist, trisqueldist+"-backports", "main")
    compare(udic, tdic,trisqueldist)

def externals(upstream, branch):
    packages = subprocess.check_output(gitcommand +'ls-tree -r --name-only '+branch+' |grep helpers/make- |sed "s/.*make-//"', shell=True).splitlines()
    tdic={}
    listdistro(tdic, "http://archive.trisquel.info/trisquel", branch, "main")
    listmirror(tdic, "http://devel.trisquel.info/repos/trisquel/"+branch, branch, "main")
    listmirror(tdic, "http://devel.trisquel.info/repos/trisquel/"+branch, branch+"-security", "main")
    listmirror(tdic, "http://devel.trisquel.info/repos/trisquel/"+branch, branch+"-backports", "main")
    for package in packages:
        external=''
        try:
            external=subprocess.check_output(gitcommand +'show '+branch+':helpers/make-'+package+' |grep EXTERNAL ', shell=True).splitlines()
        except:
            pass
        if external != '':
            #print external
            external[0]=external[0].replace("\'","")
            external[0]=external[0].replace("\"","")
            external=external[0].replace("EXTERNAL=","")
            external=external.replace("$UPSTREAM",upstream)
            external=external.replace("deb-src ","")
            udic={}
            external.split()[0]
            #print external
            listmirror(udic, external.split()[0], external.split()[1], external.split()[2])
            comparepackage(udic, tdic, package, branch)

#print "Checking pair: lucid - taranis"
#checkversions("lucid","taranis")
#print "externals"
#externals("lucid", "taranis", "taranis")


#wd=os.getcwd()
wd='/home/jenkins/scripts'
gitcommand='/usr/bin/git --git-dir='+wd+'/package-helpers/.git --work-tree='+wd+'/package-helpers/ '

if not os.path.exists(wd+"/package-helpers"):
    os.system('/usr/bin/git clone https://devel.trisquel.info/trisquel/package-helpers.git '+ wd +"/package-helpers")

for pair in ['xenial','flidas'],['trusty','belenos'],['bionic','etiona']:
    urldata={}
    tdic={}
    udic={}
    print "========================================================================="
    print "Checking pair: " + str(pair)
    os.system(gitcommand +'checkout ' + pair[1])
    os.system(gitcommand + 'pull')
    checkversions(pair[0], pair[1])
    externals(pair[0], pair[1])
