#!/usr/bin/env bash

set -eu
set -o pipefail

devtgz="devs.tar.gz"

# reset umask
umask 0022

# check for device file archive
if [ ! -f "${devtgz}" ] ; then
  printf 'missing the /dev tar archive (run sudo mkdev.sh)\n' 1>&2
  exit 2
fi

sudo () { env "$@"; }
# if we're not root, bring sudo to $sudo
[ $(id -u) != "0" ] && sudo () { command sudo env "$@"; }

# help message
usage () {
  cat << EOM 1>&2
$0 options:
  -h display usage
  -p packagemanager [yum|apt]
  -d distribution
EOM
  exit 0
}

# get options
parse_opts () {
  local opt
  while getopts "hp:d:" opt ; do
    case "${opt}" in
      p) packagemanager=${OPTARG} ;;
      d) distribution=${OPTARG} ;;
      h|*) usage ;;
    esac
  done
}

packagemanager=""
distribution=""

parse_opts "${@}"

# if we didn't get packagemanager, distribution display usage
[ -z "${distribution}" ] && usage
case "${packagemanager}" in
  apt|yum) : ;;
  *) echo "unknown packagemanager" 1>&2 ; usage ;;
esac

# create a scratch directory to use for working files
wkdir=$(mktemp -d)
export TMPDIR="${wkdir}"

__cleanup () {
  sudo rm -rf "${wkdir}"
}

trap __cleanup EXIT ERR

# check that we have a gpg dir for dist.
gpg_keydir="config/${distribution}/gpg-keys"

[ ! -d "${gpg_keydir}" ] && { echo "missing ${gpg_keydir}" 1>&2 ; exit 1 ; } || true

# let's go!
rootdir=$(mktemp -d)
conftar=$(mktemp --tmpdir conf.XXX.tar)

rpm() { sudo rpm --root "${rootdir}" "${@}"; }

# create chroot
case "${packagemanager}" in
  yum)
    # init rpm, add gpg keys and release rpm
    rpm --initdb
    for gpg in "${gpg_keydir}"/* ; do
      rpm --import "${gpg}"
    done
    rpm -iv --nodeps "config/${distribution}/*release*.rpm"
    # install our hack with the same in-chroot path ;)
    mkdir -p --mode=0755 "${rootdir}"/usr/local/lib64
    install -m755 "/tmp/LIBCAP_HACKS/${distribution}/noop_cap_set_file.so" "${rootdir}/usr/local/lib64/noop_cap_set_file.so"
    # let yum do the rest of the lifting
    sudo LD_PRELOAD=/usr/local/lib64/noop_cap_set_file.so yum --installroot "${rootdir}" install -y @Base yum yum-plugin-ovl centos-release
  ;;
esac

sudo tar cp '--exclude=./dev*' -C "${rootdir}" . > "${distribution}.tar"

# create config tar
scratch=$(mktemp -d --tmpdir $(basename $0).XXXXXX)
mkdir -p             "${scratch}"/etc/sysconfig
case "${packagemanager}" in
  yum)
cp       config/yum-common/yum.conf    "${scratch}"/etc/yum.conf
mkdir -p --mode=0755 "${scratch}"/var/cache/yum
  ;;
esac
cp       startup.sh  "${scratch}"/startup
mkdir -p --mode=0755 "${scratch}"/var/cache/ldconfig
printf 'NETWORKING=yes\nHOSTNAME=localhost.localdomain\n' > "${scratch}"/etc/sysconfig/network
printf '127.0.0.1   localhost localhost.localdomain\n'    > "${scratch}"/etc/hosts
tar --numeric-owner --group=0 --owner=0 -c -C "${scratch}" --files-from=- -f "${conftar}" << EOA
./etc/yum.conf
./etc/hosts
./etc/sysconfig/network
./var/cache/yum
./var/cache/ldconfig
./startup
EOA

# uncompress dev tar
devtar=$(mktemp --tmpdir dev.XXX.tar)
zcat "${devtgz}" > "${devtar}"

# use this for rpmdb extraction
rpmdbfiles=$(mktemp --tmpdir $(basename $0).XXXXXX)
cat << EOA > "${rpmdbfiles}"
./var/lib/rpm/Packages
./var/lib/rpm/Name
./var/lib/rpm/Basenames
./var/lib/rpm/Group
./var/lib/rpm/Requirename
./var/lib/rpm/Providename
./var/lib/rpm/Conflictname
./var/lib/rpm/Obsoletename
./var/lib/rpm/Triggername
./var/lib/rpm/Dirnames
./var/lib/rpm/Installtid
./var/lib/rpm/Sigmd5
./var/lib/rpm/Sha1header
EOA

rpmdbdir=$(mktemp -d --tmpdir $(basename $0).XXXXXX)
# first, pry the rpmdb out.
tar -C "${rpmdbdir}" --extract --file="${distribution}".tar --files-from="${rpmdbfiles}"
# conver db files to dump files
for x in "${rpmdbdir}"/var/lib/rpm/* ; do
  /usr/lib/rpm/rpmdb_dump "${x}" > "${x}.dump"
  rm "${x}"
done
cat "${rpmdbfiles}" | awk '{printf "%s.dump\n",$0}' | tar --numeric-owner --group=0 --owner=0 -C "${rpmdbdir}" --create --file="${distribution}"-rpmdb.tar --files-from=-
tar --delete --file="${distribution}".tar --files-from=- << EOA || true
./usr/lib/locale
./usr/share/locale
./lib/gconv
./lib64/gconv
./bin/localedef
./sbin/build-locale-archive
./usr/share/man
./usr/share/doc
./usr/share/info
./usr/share/gnome/help
./usr/share/cracklib
./usr/share/i18n
./var/cache/yum
./sbin/sln
./var/cache/ldconfig
./etc/ld.so.cache
./etc/sysconfig/network
./etc/hosts
./etc/hosts.rpmnew
./etc/yum.conf
./etc/yum.conf.rpmnew
./etc/yum/yum.conf
./builddir
$(cat "${rpmdbfiles}")
EOA

# bring it all together
tar --concatenate --file="${distribution}".tar "${devtar}"
tar --concatenate --file="${distribution}".tar "${conftar}"
tar --concatenate --file="${distribution}".tar "${distribution}"-rpmdb.tar

# feed to docker
docker import "${distribution}".tar "pre-${distribution}"

# kick docker
docker run -i --name "setup-${distribution}" -t "pre-${distribution}" /startup

# export that as a new image
docker export "setup-${distribution}" | docker import - "${distribution}"

# clean up scratch instance, image
docker rm "setup-${distribution}"
docker rmi "pre-${distribution}"

# make sure image works
docker run --rm=true "${distribution}" yum check-update

if [ $? -eq 0 ] ; then
  reltime=$(date +%s)
  # tag as 'latest' - TODO: branching on version, not just build.
  docker tag  "${DNAME}:latest" "${distribution}"
  docker tag  "${DNAME}:${reltime}" "${distribution}"
  docker push "${DNAME}:latest"
  docker push "${DNAME}:${reltime}"
fi
