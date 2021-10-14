#!/usr/bin/python3

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

import argparse
import os
import sys
import subprocess
import apt_pkg
import apt

parser = argparse.ArgumentParser(description=("Identify packages out-of-sync between "
                                              "upstream and Trisquel"))
parser.add_argument('working_directory',
                    help=("Directory to clone package helpers and create apt configuration"),
                    nargs='?', default=os.getcwd())
parser.add_argument('--debug', help="Enable degugging printing",
                    default=False, action='store_true')
args = parser.parse_args()

wd = args.working_directory

trisquelversions = {
    'etiona': {'version': '9.0', 'codename': 'etiona', 'upstream': 'bionic'},
    'nabia': {'version': '10.0', 'codename': 'nabia', 'upstream': 'focal'}
    }


def debug(string):
    if args.debug:
        print(string)


def gitcommand(params):
    if not os.path.exists(wd+"/package-helpers"):
        os.system('/usr/bin/git clone \
                  https://gitlab.trisquel.org/trisquel/package-helpers.git '
                  + wd + "/package-helpers")
    command = '/usr/bin/git --git-dir=' \
        + wd + '/package-helpers/.git --work-tree=' \
        + wd + '/package-helpers/ ' + params
    result = subprocess.run(command.split(), capture_output=True)
    if result.returncode == 0:
        return result.stdout.decode("utf-8")
    else:
        print("E: command git %s failed" % params)
        return None


def listhelpers(dist):
    gitcommand("fetch --all")
    paths = gitcommand("ls-tree  --name-only origin/%s:helpers " % dist).split()
    helpers = []
    for i, path in enumerate(paths):
        if path == "DATA" or path == "config":
            continue
        helpers.append(path.replace("make-", ""))

    return helpers


def helperversion(dist, package):
    external = False
    backport = False
    depends = []

    helper = gitcommand("show origin/%s:helpers/make-%s" % (dist, package))
    for line in helper.splitlines():
        if line.startswith("VERSION="):
            version = line.replace("VERSION=", "").replace("\n", "")
            version = "+%strisquel%s" % (trisquelversions[dist]['version'], version)
        if line.startswith("EXTERNAL="):
            external = line.replace("EXTERNAL=", "")\
                .replace("\n", "").replace('\'', '').replace('\"', '')
        if line.startswith("BACKPORT"):
            backport = True
        if line.startswith("DEPENDS="):
            depends = line.replace("DEPENDS=", "").replace(" ", "").split(",")

    return {'version': version, 'external': external, 'backport': backport, 'depends': depends}


def makesourceslist(name, uri, suites, components):
    lines = []
    for suite in suites:
        lines.append("%s %s %s %s\n" % ("deb-src", uri, suite, components))
    if name == 'trisquel':
        lines.append("%s %s %s %s\n" %
                     ("deb-src", "http://builds.trisquel.org/repos/%s" %
                      dist, dist, components))
        lines.append("%s %s %s %s\n" %
                     ("deb-src", "http://builds.trisquel.org/repos/%s" %
                      dist, "%s-security" % dist, components))
    if name == 'trisquel-backports':
        lines.append("%s %s %s %s\n" %
                     ("deb-src", "http://builds.trisquel.org/repos/%s" %
                      dist, "%s-backports" % dist, components))
    f = open("./apt/%s/etc/apt/sources.list" % name, "w")
    f.writelines(lines)
    f.close()


def makerepo(name, uri, suites, components):
    debug("Building cache for %s repository... " % name)
    if not os.path.exists("./apt/%s" % name):
        os.makedirs("./apt/%s/var/lib/apt/lists" % name)
        os.makedirs("./apt/%s/etc/apt/sources.list.d" % name)
    apt_pkg.config.set("Dir::Cache::pkgcache", "")
    apt_pkg.config.set("Dir::Cache::archives", "")
    # TODO gpg key handling
    apt_pkg.config.set("Acquire::Check-Valid-Until",  "false")
    apt_pkg.config.set("Acquire::AllowInsecureRepositories",  "true")
    apt_pkg.config.set("Acquire::AllowDowngradeToInsecureRepositories",  "true")
    apt_pkg.config.set("Dir",  "./apt/%s/" % name)
    apt_pkg.config.set("Dir::State::lists",  "./apt/%s/var/lib/apt/lists" % name)
    apt_pkg.config.set("Dir::Etc::sourcelist", "./apt/%s/etc/apt/sources.list" % name)
    apt_pkg.config.set("Dir::Etc::sourceparts", "./apt/%s/etc/apt/sources.list.d" % name)
    apt_pkg.config.set("Dir::State::status", "/dev/null")
    makesourceslist(name, uri, suites, components)
    apt_pkg.init()
    cache = apt.Cache()
    try:
        cache.update(raise_on_error=True)
    except apt_pkg.Error:
        try:
            debug("Cache for %s failed to build, trying again" % name)
            cache.update(raise_on_error=True)
        except apt_pkg.Error:
            debug("Cache for %s failed to build again, giving up")
            return None
    cache.open()
    cache.close()
    try:
        src = apt_pkg.SourceRecords()
    except apt_pkg.Error:
        debug("E: could not set up repo cache for %s" % name)
        return None
    return src


def lookup(record, package):
    if record is None:
        return None
    record.restart()
    version = 0
    newversion = 0
    while record.lookup(package):
        newversion = record.version
        if version == 0 or apt_pkg.version_compare(version, newversion) < 0:
            version = newversion
    return version


def compare(tversion, tresult, uresult, package, dist, cache):
    if apt_pkg.version_compare(tresult, uresult + tversion['version']) < 0:
        # Never build linux metapackages before the binary packages
        if "-meta" in package and package.startswith('linux'):
            debug("Metapackage: %s | trisquel version: %s | upstream version: %s | helper: %s"
                  % (package, tresult, uresult, tversion['version']))
            basepackage = package.replace("-meta", "")
            result = lookup(cache, basepackage)
            if result:
                if "trisquel" not in result:
                    print(("E: Skipping building %s, "
                           "binary package exists but has no trisquel version") % package)
                    return
                debug("Upstream version of %s: %s" % (basepackage, result))
                abi = tresult.split(".")
                abi = '.'.join(abi[0:4])
                if abi not in result.replace("-", '.'):
                    print("W: Skipping building %s, binary package is out of date" % package)
                    return
            else:
                print("W: Skipping building %s, binary package is missing" % package)
                return
        # If dependencies are defined in helper, check that they are built in order
        if tversion['depends']:
            for dependency in tversion['depends']:
                result = lookup(cache, dependency)
                # Also look in trisquel $dist main
                if not result:
                    result = lookup(T, dependency)
                if not result or "trisquel" not in result:
                    print(("W: Skipping build, "
                           "dependency %s missing for helper make-%s on %s ")
                          % (dependency, package, dist))
        print(("Package %s can be upgraded to version %s "
               "current %s version is %s")
              % (package, uresult+tversion['version'], dist, tresult))
    else:
        debug("%s: Trisquel repo has %s and upstream has %s helper:%s"
              % (package, tresult, uresult, tversion['version']))


def check_versions(trepo, urepo, tversion, package, dist):
    tresult=lookup(trepo, package)
    uresult=lookup(urepo, package)
    if tresult and not uresult:
        if tversion['external']:
            repo_str = "external repository"
        elif tversion['backport']:
            repo_str = "Ubuntu backports"
        else:
            repo_str = "Ubuntu"

        print("%s missing on %s! Trisquel has version %s"
              % (package, repo_str, tresult))
    if uresult and not tresult:
        print("Package %s can be upgraded to version %s current %s version is missing"
              % (package, uresult + tversion['version'], dist))
    if tresult and uresult:
        compare(tversion, tresult, uresult, package, dist, trepo)


for dist in ["nabia", "etiona"]:
    print("== Checking %s ==========================================================" % dist)
    upstream = trisquelversions[dist]['upstream']

    T = makerepo("trisquel",
                 "http://archive.trisquel.org/trisquel",
                 [dist, "%s-updates" % dist, "%s-security" % dist], "main")
    U = makerepo("ubuntu",
                 "http://archive.ubuntu.com/ubuntu",
                 [upstream, "%s-updates" % upstream, "%s-security" % upstream], "main universe")
    Ub = makerepo("ubuntu-backports",
                  "http://archive.ubuntu.com/ubuntu",
                  ["%s-backports" % upstream], "main universe")
    Tb = makerepo("trisquel-backports",
                  "http://archive.trisquel.org/trisquel",
                  ["%s-backports" % dist], "main")

    for package in listhelpers(dist):
        debug("")
        debug(package)
        tversion = helperversion(dist, package)

        if not tversion['external']:
            if not tversion['backport']:
                check_versions(T, U, tversion, package, dist)
            else:
                check_versions(Tb, Ub, tversion, package, dist)
        else:
            # External
            suite = tversion['external'].split()[2]\
                    .replace("$UPSTREAM", trisquelversions[dist]['upstream'])
            components = ' '.join(tversion['external'].split()[3:])
            E = makerepo(package, tversion['external'].split()[1], [suite], components)

            if tversion['backport']:
                check_versions(Tb, E, tversion, package, dist)
            else:
                check_versions(T, E, tversion, package, dist)
