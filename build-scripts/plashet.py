#!/usr/bin/python2

from __future__ import print_function
import optparse
import xmlrpclib
import os
import errno
from kobo.rpmlib import parse_nvr

BREW_URL = "https://brewhub.engineering.redhat.com/brewhub"
ERRATA_URL = "http://errata-xmlrpc.devel.redhat.com/errata/errata_service"
ERRATA_API_URL = "https://errata.engineering.redhat.com/api/v1/"

def mkdirs(path, mode=0755):
    """
    Make sure a directory exists. Similar to shell command `mkdir -p`.
    :param path: Str path
    :param mode: create directories with mode
    """
    try:
        os.makedirs(str(path), mode=mode)
    except OSError as e:
        if e.errno != errno.EEXIST:  # ignore if dest_dir exists
            raise

def run():

    parser = optparse.OptionParser(description='''
Creates a puddle-like repository using only symlinks to RPMs in a local
brewroot filesystem. This avoids copying all the files again.

The repository is filled with RPMs derived from the list of files 
attached to a specified errata. 

By default, all CPU architectures are included in the repository. If
you want to limit the new repository to include only specific architectures,
specify --arch.
''')

    parser.add_option(
        "--base-dir",
        metavar="DIR",
        default=os.getcwd(),
        dest='base_dir',
        help="Required. Base directory for all plashets. Defaults to current working directory.",
    )
    parser.add_option(
        "--name",
        metavar="NAME",
        dest='name',
        help="Required. Directory name to create relative to base directory.",
    )
    parser.add_option(
        "--symlink",
        metavar="NAME",
        dest='symlink',
        help="Symlink to create in base directory to successful plashet directory.",
    )
    parser.add_option(
        "--advisory-id",
        metavar="NUM",
        dest='advisory_id',
        help="Required. The advisory id from which to extract RPMs.",
    )
    parser.add_option(
        "--errata-xmlrpc-url",
        dest="errata_xmlrpc_url",
        default=ERRATA_URL,
        metavar="URL",
        help="Change the default errata xmlrpc URL.",
    )
    parser.add_option(
        "--brew-root",
        metavar="DIR",
        default='/mnt/redhat/brewroot',
        help="File system location of brew root.",
    )
    parser.add_option(
        "--arch",
        metavar="DIR",
        action="append",
        dest='arches',
        default=[],
        help="Refine plashet to only noarch and these arches.",
    )
    parser.add_option(
        "--signing-key-id",
        metavar="HEX",
        default='fd431d51',
        dest='signing_key_id',
        help="Override default signing requirement.",
    )

    opts, _ = parser.parse_args()

    if not opts.name:
        print('--name is required')
        exit(1)

    if not opts.advisory_id:
        print('--advisory-id is required')
        exit(1)

    errata_proxy = xmlrpclib.ServerProxy(opts.errata_xmlrpc_url)
    module_builds = False  # ???

    brew_root_path = os.path.abspath(opts.brew_root)
    packages_path = os.path.join(brew_root_path, 'packages')
    if not os.path.isdir(packages_path):
        print('{} does not exist; unable to start'.format(packages_path))
        exit(1)

    base_dir_path = os.path.abspath(opts.base_dir)
    if not os.path.isdir(base_dir_path):
        print('{} does not exist; unable to start'.format(base_dir_path))
        exit(1)

    dest_dir = os.path.join(base_dir_path, opts.name)
    if os.path.exists(dest_dir):
        print('Destination {} already exists; name must be unique'.format(dest_dir))
        exit(1)

    mkdirs(dest_dir)
    links_dir = os.path.join(dest_dir, 'links')
    mkdirs(links_dir)

    rpm_list_path = os.path.join(dest_dir, 'rpm_list')

    with open(rpm_list_path, mode='w+') as rl:
        for build in errata_proxy.getErrataBrewBuilds(opts.advisory_id):
            nvr = build["brew_build_nvr"]
            is_module = build["is_module"]
            if module_builds and not is_module:
                continue
            if not module_builds and is_module:
                continue
            parsed_nvr = parse_nvr(nvr)
            package_name = parsed_nvr["name"]
            package_version = parsed_nvr["version"]
            package_release = parsed_nvr["release"]

            found = 0

            br_signed_path = '{brew_packages}/{package_name}/{package_version}/{package_release}/data/signed/{signing_key_id}'.format(
                brew_packages=packages_path,
                package_name=package_name,
                package_version=package_version,
                package_release=package_release,
                signing_key_id=opts.signing_key_id,
            )

            if not os.path.isdir(br_signed_path):
                raise IOError('Package {nvr} has not been signed; {signed_path} does not exist'.format(
                    nvr=nvr,
                    signed_path=br_signed_path,
                ))

            arches = list(opts.arches)
            if not arches:
                arches = os.listdir(br_signed_path)
                arches.remove('src')
            else:
                arches.append('noarch')

            for a in arches:
                br_arch_path = os.path.join(br_signed_path, a)

                if not os.path.isdir(br_arch_path):
                    continue

                link_name = '{package_name}_{package_version}_{package_release}_{arch}'.format(
                    package_name=package_name,
                    package_version=package_version,
                    package_release=package_release,
                    arch=a,
                )
                package_link_path = os.path.join(links_dir, link_name)
                os.symlink(br_arch_path, package_link_path)

                rpms = os.listdir(package_link_path)
                if not rpms:
                    raise IOError('Did not find rpms in {}'.format(br_arch_path))

                for r in rpms:
                    rpm_path = os.path.join('links', link_name, r)
                    rl.write(rpm_path + '\n')
                    found += 1

            if not found:
                raise IOError('Unable to find any rpms for {nvr} in {p}'.format(nvr=nvr, p=br_signed_path))

        if os.system('cd {dest_dir} && createrepo -i rpm_list .'.format(dest_dir=dest_dir)) != 0:
            print('Error creating repo at: {dest_dir}'.format(dest_dir=dest_dir))
            exit(1)

        print('Successfully created repo at: {dest_dir}'.format(dest_dir=dest_dir))

        if opts.symlink:
            if os.system('cd {base_dir_path} && ln -sfn {dest} {link}'.format(dest=dest_dir, link=opts.symlink)) != 0:
                print('Error creating symlink: {link}'.format(link=opts.symlink))
                exit(1)
            print('Successfully created symlink at: {link}'.format(dest_dir=dest_dir, link=opts.symlink))

if __name__ == '__main__':
    run()
