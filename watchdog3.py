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

TRISQUELRELEASES = {
    'etiona': {'version': '9.0', 'codename': 'etiona', 'upstream': 'bionic'},
    'nabia': {'version': '10.0', 'codename': 'nabia', 'upstream': 'focal'}
    }

TRISQUEL_REPO_KEY = "B138CA450C05112F"
BUILDS_REPO_KEY = "CFB708E203134F62"
UBUNTU_REPO_KEY = "3B4FE6ACC0B21F32"

parser = argparse.ArgumentParser(description=("Identify packages out-of-sync between "
                                              "upstream and Trisquel"))
parser.add_argument('release',
                    help=("Trisquel release to check. Releases known by this script: %s"
                          % ', '.join(TRISQUELRELEASES.keys())),
                    nargs='*', default="")
parser.add_argument('--working_directory',
                    help=("Directory to clone package helpers and create apt configuration"),
                    nargs='?', default=os.getcwd())
parser.add_argument('--debug', help="Enable degugging printing",
                    default=False, action='store_true')
parser.add_argument('--check_gpg', help="Retrieve and check gpg keys for each repository",
                    default=False, action='store_true')
args = parser.parse_args()


def debug(string):
    if args.debug:
        print(string)


def git_command(params):
    """
    Executes git commands on a local clone of package-helpers.git
    """
    if not os.path.exists("%s/package-helpers" % args.working_directory):
        os.system("/usr/bin/git clone https://gitlab.trisquel.org/trisquel/package-helpers.git \
                  %s/package-helpers" % args.working_directory)
    command = "/usr/bin/git --git-dir=%s/package-helpers/.git --work-tree=%s/package-helpers/ %s" \
              % (args.working_directory, args.working_directory, params)
    result = subprocess.run(command.split(), capture_output=True)
    if result.returncode == 0:
        return result.stdout.decode("utf-8")
    else:
        print("E: command git %s failed" % params)
        return None


def get_gpg_key(keyid, keyring):
    """
    Retrieve a gpg key by id or full fingerprint, store it in keyring file
    """
    if not args.check_gpg:
        return True
    debug("Retrieving gpg key %s to %s" % (keyid, keyring))
    result = subprocess.run("apt-key --keyring %s adv "
                            "--keyserver keyserver.ubuntu.com --recv-keys %s"
                            % (keyring, keyid), shell=True, capture_output=True)
    if result.returncode != 0:
        print("E: failed to fetch gpg key %s" % keyid)
        return False
    return True


def list_helper_packages(release):
    """
    Given a Trisquel release, list all packages that have a helper script.
    """
    git_command("fetch --all")
    paths = git_command("ls-tree  --name-only origin/%s:helpers " % release).split()
    packages = []

    for i, path in enumerate(paths):
        if path == "DATA" or path == "config":
            continue
        packages.append(path.replace("make-", ""))

    return packages


def get_helper_info(release, package):
    """
    Returns a dictionary with information about a package helper script for a Trisquel release
    listing version, external repositories, backports and dependencies
    """
    external = False
    backport = False
    depends = []
    repokey = ""

    helper = git_command("show origin/%s:helpers/make-%s" % (release, package))
    for line in helper.splitlines():
        if line.startswith("VERSION="):
            version = line.replace("VERSION=", "").replace("\n", "")
            version = "+%strisquel%s" % (TRISQUELRELEASES[release]['version'], version)
        if line.startswith("EXTERNAL="):
            external = line.replace("EXTERNAL=", "")\
                .replace("\n", "").replace('\'', '').replace('\"', '')
        if line.startswith("BACKPORT"):
            backport = True
        if line.startswith("DEPENDS="):
            depends = line.replace("DEPENDS=", "").replace(" ", "").split(",")
        if line.startswith("REPOKEY="):
            repokey = line.replace("REPOKEY=", "").replace(" ", "")

    return {'version': version,
            'external': external,
            'backport': backport,
            'depends': depends,
            "repokey": repokey}


def make_sourceslist(name, uri, suites, components, release):
    """
    Builds a sources.list file given its description as parameters
    """
    lines = []
    for suite in suites:
        lines.append("%s %s %s %s\n" % ("deb-src", uri, suite, components))
    if name == 'trisquel':
        lines.append("%s %s %s %s\n" %
                     ("deb-src", "http://builds.trisquel.org/repos/%s" %
                      release, release, components))
        get_gpg_key(BUILDS_REPO_KEY, "%s/apt/%s/%s/etc/apt/trusted.gpg"
                    % (args.working_directory, release, name))
        lines.append("%s %s %s %s\n" %
                     ("deb-src", "http://builds.trisquel.org/repos/%s" %
                      release, "%s-security" % release, components))
    if name == 'trisquel-backports':
        get_gpg_key(BUILDS_REPO_KEY, "%s/apt/%s/%s/etc/apt/trusted.gpg"
                    % (args.working_directory, release, name))
        lines.append("%s %s %s %s\n" %
                     ("deb-src", "http://builds.trisquel.org/repos/%s" %
                      release, "%s-backports" % release, components))
    f = open("%s/apt/%s/%s/etc/apt/sources.list" % (args.working_directory, release, name), "w")
    f.writelines(lines)
    f.close()


def build_cache(name, uri, suites, components, release, keyid):
    """
    Builds an apt repository based on parameters
    Returns an apt.Cache object and a apt_pkg.SourceRecords object
    """
    debug("Building cache for %s repository... " % name)
    if not os.path.exists("%s/apt/%s/%s"
                          % (args.working_directory, release, name)):
        os.makedirs("%s/apt/%s/%s/var/lib/apt/lists"
                    % (args.working_directory, release, name))
        os.makedirs("%s/apt/%s/%s/etc/apt/sources.list.d"
                    % (args.working_directory, release, name))
    apt_pkg.config.set("Dir::Cache::pkgcache", "")
    apt_pkg.config.set("Dir::Cache::archives", "")
    if not args.check_gpg or not get_gpg_key(keyid, "%s/apt/%s/%s/etc/apt/trusted.gpg"
                                             % (args.working_directory, release, name)):
        if args.check_gpg:
            print("E: gpg key missing for %s, disabling check" % name)
        apt_pkg.config.set("Acquire::Check-Valid-Until",  "false")
        apt_pkg.config.set("Acquire::AllowInsecureRepositories",  "true")
        apt_pkg.config.set("Acquire::AllowDowngradeToInsecureRepositories",  "true")
    apt_pkg.config.set("Dir",  "%s/apt/%s/%s/" % (args.working_directory, release, name))
    apt_pkg.config.set("Dir::State::lists",  "%s/apt/%s/%s/var/lib/apt/lists"
                       % (args.working_directory, release, name))
    apt_pkg.config.set("Dir::Etc::sourcelist", "%s/apt/%s/%s/etc/apt/sources.list"
                       % (args.working_directory, release, name))
    apt_pkg.config.set("Dir::Etc::sourceparts", "%s/apt/%s/%s/etc/apt/sources.list.d"
                       % (args.working_directory, release, name))
    apt_pkg.config.set("Dir::State::status", "/dev/null")
    make_sourceslist(name, uri, suites, components, release)
    apt_pkg.init()
    cache = apt.Cache()
    try:
        cache.update(raise_on_error=True)
    except apt.cache.FetchFailedException:
        debug("E: apt.Cache for %s failed to build" % name)
        #raise
        return None
    try:
        src = apt_pkg.SourceRecords()
    except apt_pkg.Error:
        debug("E: could not get apt_pkg.SourceRecords for %s" % name)
        return None
    return {"cache": cache, "source_records": src}


def lookup_src(cache, package):
    """
    Search for a package in apt.SourceRecords and return the version string
    """
    if cache is None:
        return None
    record = cache["source_records"]
    record.restart()
    version = 0
    newversion = 0
    while record.lookup(package):
        newversion = record.version
        if version == 0 or apt_pkg.version_compare(version, newversion) < 0:
            version = newversion
    return version


def compare_versions(helper_info, tresult, uresult, package, release, cache):
    """
    Compares two package version strings and calculates if new versions need to be built
    """
    if apt_pkg.version_compare(tresult, uresult + helper_info['version']) < 0:
        # Never build linux metapackages before the binary packages
        if "-meta" in package and package.startswith('linux'):
            debug("Metapackage: %s | trisquel version: %s | upstream version: %s | helper: %s"
                  % (package, tresult, uresult, helper_info['version']))
            basepackage = package.replace("-meta", "")
            result = lookup_src(cache, basepackage)
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
        if helper_info['depends']:
            for dependency in helper_info['depends']:
                result = lookup_src(cache, dependency)
                # Also look in trisquel $release main
                if not result:
                    result = lookup_src(cache, dependency)
                if not result or "trisquel" not in result:
                    print(("W: Skipping build, "
                           "dependency %s missing for helper make-%s on %s ")
                          % (dependency, package, release))
        print(("Package %s can be upgraded to version %s "
               "current %s version is %s")
              % (package, uresult+helper_info['version'], release, tresult))
    else:
        debug("%s: Trisquel repo has %s and upstream has %s helper:%s"
              % (package, tresult, uresult, helper_info['version']))


def check_versions(tcache, ucache, helper_info, package, release):
    """
    Checks what type of comparisons to make based on external sources and backports
    """
    tresult = lookup_src(tcache, package)
    uresult = lookup_src(ucache, package)
    if tresult and not uresult:
        if helper_info['external']:
            repo_str = "external repository"
        elif helper_info['backport']:
            repo_str = "Ubuntu backports"
        else:
            repo_str = "Ubuntu"

        print("%s missing on %s! Trisquel has version %s"
              % (package, repo_str, tresult))
    if uresult and not tresult:
        print("Package %s can be upgraded to version %s current %s version is missing"
              % (package, uresult + helper_info['version'], release))
    if tresult and uresult:
        compare_versions(helper_info, tresult, uresult, package, release, tcache)


def check_distro(release):
    """
    Checks all package helpers of a Trisquel release, comparing the latest built version
    with upstream versions and printing if a new version needs to be built
    """
    print("== Checking %s ==========================================================" % release)
    if release in TRISQUELRELEASES:
        upstream = TRISQUELRELEASES[release]['upstream']
    else:
        print("E: release %s not found" % release)
        return
    cache = {}
    cache["trisquel"] = build_cache("trisquel",
                                    "http://archive.trisquel.org/trisquel",
                                    [release, "%s-updates" % release, "%s-security" % release],
                                    "main", release, TRISQUEL_REPO_KEY)
    cache["ubuntu"] = build_cache("ubuntu",
                                  "http://archive.ubuntu.com/ubuntu",
                                  [upstream, "%s-updates" % upstream, "%s-security" % upstream],
                                  "main universe", release, UBUNTU_REPO_KEY)
    cache["ubuntu-backports"] = build_cache("ubuntu-backports",
                                            "http://archive.ubuntu.com/ubuntu",
                                            ["%s-backports" % upstream], "main universe",
                                            release, UBUNTU_REPO_KEY)
    cache["trisquel-backports"] = build_cache("trisquel-backports",
                                              "http://archive.trisquel.org/trisquel",
                                              ["%s-backports" % release], "main",
                                              release, TRISQUEL_REPO_KEY)

    for package in list_helper_packages(release):
        debug("")
        debug(package)
        helper_info = get_helper_info(release, package)

        if not helper_info['external']:
            if not helper_info['backport']:
                check_versions(cache["trisquel"], cache["ubuntu"],
                               helper_info, package, release)
            else:
                check_versions(cache["trisquel-backports"], cache["ubuntu-backports"],
                               helper_info, package, release)
        else:
            # External
            if not helper_info['repokey']:
                debug("W: helper for %s has external repo but is missing REPOKEY"
                      " defaulting to Ubuntu key: %s" % (package, UBUNTU_REPO_KEY))
                helper_info['repokey'] = UBUNTU_REPO_KEY
            suite = helper_info['external'].split()[2]\
                .replace("$UPSTREAM", TRISQUELRELEASES[release]['upstream'])
            components = ' '.join(helper_info['external'].split()[3:])
            cache_external = build_cache(package, helper_info['external'].split()[1],
                                         [suite], components, release, helper_info['repokey'])

            if helper_info['backport']:
                check_versions(cache["trisquel-backports"], cache_external,
                               helper_info, package, release)
            else:
                check_versions(cache["trisquel"], cache_external, helper_info, package, release)


if __name__ == '__main__' and args.release:
    try:
        for release in args.release:
            check_distro(release)
    except KeyboardInterrupt:
        sys.exit(0)
