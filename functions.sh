#!/usr/bin/env sh

cwd="`realpath | sed 's|/scripts||g'`"
liveuser=ghostbsd
desktop=$1
workdir="/usr/local"
livecd="${workdir}/ghostbsd-build"
base="${livecd}/base"
iso="${livecd}/iso"
software_packages="${livecd}/software_packages"
base_packages="${livecd}/base_packages"
release="${livecd}/release"
cdroot="${livecd}/cdroot"
version="19.09"
# version=""
release_stamp=""
# release_stamp="-RC4"
# time_stamp=`date "+-%Y-%m-%d-%H-%M"`
time_stamp=`date "+-%Y-%m-%d"`
# time_stamp=""
label="GhostBSD"

if [ "$desktop" = "kde" ] ; then
  union_dirs=${union_dirs:-"boot cdrom dev etc libexec media mnt root tmp usr/home usr/local/etc usr/local/share/plasma var"}
fi

if [ "$desktop" = "mate" ] ; then
  union_dirs=${union_dirs:-"boot cdrom dev etc libexec media mnt root tmp usr/home usr/local/
etc usr/local/share/mate-panel var"}
else
  union_dirs=${union_dirs:-"boot cdrom dev etc libexec media mnt root tmp usr/home usr/local/
etc var"}
fi
kernrel="`uname -r`"

# Only run as superuser
if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

case $kernrel in
  '13.0-CURRENT')
    echo "Using correct kernel release" 1>&2
    ;;
  '12.1-STABLE')
    echo "Using correct kernel release" 1>&2
    ;;
  *)
   echo "Using wrong kernel release. Use TrueOS 18.12 or GhostBSD 19 to build iso."
   exit 1
   ;;
esac

validate_desktop()
{
  if [ ! -f "${cwd}/packages/${desktop}" ] ; then
    echo "Invalid choice specified"
    echo "Possible choices are:"
    ls ${cwd}/packages
    echo "Usage: ./build.sh mate"
    exit 1
  fi
}

# Validate package selection if chosen
if [ -z "${desktop}" ] ; then
  desktop=mate
else
  validate_desktop
fi

if [ "${desktop}" != "mate" ] ; then
  DESKTOP=$(echo ${desktop} | tr [a-z] [A-Z])
  community="-${DESKTOP}"
else
  community=""
fi


isopath="${iso}/${label}${version}${release_stamp}${time_stamp}${community}.iso"

workspace()
{
  umount ${release}/var/cache/pkg >/dev/null 2>/dev/null
  if [ -d "${livecd}" ] ;then
    chflags -R noschg ${release} ${cdroot} >/dev/null 2>/dev/null
    rm -rfv ${release} ${cdroot} >/dev/null 2>/dev/null
  fi
  mkdir -pv ${livecd} ${base} ${iso} ${software_packages} ${base_packages} ${release} >/dev/null 2>/dev/null
}

base()
{
  mkdir -pv ${release}/etc
  cp -rfv /etc/resolv.conf ${release}/etc/resolv.conf
  mkdir -pv ${release}/var/cache/pkg
  mount_nullfs ${base_packages} ${release}/var/cache/pkg
  pkg-static -r ${release} -R ${cwd}/repos/usr/local/etc/pkg/repos/ -C GhostBSD install -y -g os-generic-kernel os-generic-userland os-generic-userland-lib32

  rm -rfv ${release}/etc/resolv.conf
  umount -fv ${release}/var/cache/pkg
  touch ${release}/etc/fstab
  mkdir -pv ${release}/cdrom
}

packages_software()
{
  cp -Rfv ${cwd}/repos/ ${release}
  cp -rfv /etc/resolv.conf ${release}/etc/resolv.conf
  mkdir -pv ${release}/var/cache/pkg
  mount_nullfs ${software_packages} ${release}/var/cache/pkg
  mount -t devfs devfs ${release}/dev
  case $desktop in
    mate)
      cat ${cwd}/packages/mate | xargs pkg -c ${release} install -y ;;
    xfce)
      cat ${cwd}/packages/xfce | xargs pkg -c ${release} install -y ;;
    cinnamon)
      cat ${cwd}/packages/cinnamon | xargs pkg-static -c ${release} install -y ;;
    kde)
      cat ${cwd}/packages/kde | xargs pkg -c ${release} install -y ;;
  esac

  rm -rfv ${release}/etc/resolv.conf
  umount -fv ${release}/var/cache/pkg

  cp -Rfv ${cwd}/repos/ ${release}

}

rc()
{
  chroot ${release} sysrc -f /etc/rc.conf root_rw_mount="YES"
  chroot ${release} sysrc -f /etc/rc.conf hostname='livecd'
  chroot ${release} sysrc -f /etc/rc.conf sendmail_enable="NONE"
  chroot ${release} sysrc -f /etc/rc.conf sendmail_submit_enable="NO"
  chroot ${release} sysrc -f /etc/rc.conf sendmail_outbound_enable="NO"
  chroot ${release} sysrc -f /etc/rc.conf sendmail_msp_queue_enable="NO"
  # DEVFS rules
  chroot ${release} sysrc -f /etc/rc.conf devfs_system_ruleset="devfsrules_common"
  # Load the following kernel modules
  chroot ${release} sysrc -f /etc/rc.conf kld_list="linux linux64 /boot/modules/i915kms.ko /boot/modules/radeonkms.ko amdgpu"
  chroot ${release} sysrc -f /etc/rc.conf kld_list="geom_mirror"
  # remove kldload_nvidia on rc.conf
  ( echo 'g/kldload_nvidia="nvidia-modeset nvidia"/d' ; echo 'wq' ) | ex -s ${release}/etc/rc.conf
  chroot ${release} rc-update add devfs default
  chroot ${release} rc-update add moused default
  chroot ${release} rc-update add dbus default
  chroot ${release} rc-update add hald default
  chroot ${release} rc-update add sddm default
  chroot ${release} rc-update add webcamd default
  chroot ${release} rc-update delete vboxguest default
  chroot ${release} rc-update delete vboxservice default
  chroot ${release} rc-update add cupsd default
  chroot ${release} rc-update add avahi-daemon default
  chroot ${release} rc-update add avahi-dnsconfd default
  chroot ${release} rc-update add ntpd default
  chroot ${release} sysrc -f /etc/rc.conf ntpd_sync_on_start="YES"
}

user()
{
  chroot ${release} pw useradd ${liveuser} \
  -c "GhostBSD Live User" -d "/usr/home/${liveuser}" \
  -g wheel -G operator -m -s /usr/local/bin/fish -k /usr/share/skel -w yes
}

extra_config()
{
  . ${cwd}/extra/common-live-setting.sh
  . ${cwd}/extra/common-base-setting.sh
  . ${cwd}/extra/setuser.sh
  . ${cwd}/extra/dm.sh
  . ${cwd}/extra/finalize.sh
  . ${cwd}/extra/autologin.sh
  . ${cwd}/extra/gitpkg.sh
  set_live_system
  git_pc_sysinstall
  ## git_gbi is for development testing and gbi should be
  ## remove from the package list to avoid conflict
  git_gbi
  setup_liveuser
  setup_base
  if [ -z "${desktop}" == "kde" ] ; then
    sddm_setup
  else
    lightdm_setup
    setup_autologin
  fi
  # setup_xinit
  final_setup
  echo "gop set 0" >> ${release}/boot/loader.rc.local
  # To fix lightdm crashing to be remove on the new base update.
  sed -i '' -e 's/memorylocked=128M/memorylocked=256M/' ${release}/etc/login.conf
  chroot ${release} cap_mkdb /etc/login.conf
  mkdir -pv ${release}/usr/local/share/ghostbsd
  echo "${desktop}" > ${release}/usr/local/share/ghostbsd/desktop
}

xorg()
{
  if [ -n "${desktop}" ] ; then
    install -o root -g wheel -m 755 "${cwd}/xorg/bin/xconfig" "${release}/usr/local/bin/"
    install -o root -g wheel -m 755 "${cwd}/xorg/rc.d/xconfig" "${release}/usr/local/etc/rc.d/"
    if [ -f "${release}/sbin/openrc-run" ] ; then
      install -o root -g wheel -m 755 "${cwd}/xorg/init.d/xconfig" "${release}/usr/local/etc/init.d/"
    fi
    if [ ! -d "${release}/usr/local/etc/X11/cardDetect/" ] ; then
      mkdir -p ${release}/usr/local/etc/X11/cardDetect
    fi
    install -o root -g wheel -m 755 "${cwd}/xorg/cardDetect/XF86Config.vesa" "${release}/usr/local/etc/X11/cardDetect/"
    install -o root -g wheel -m 755 "${cwd}/xorg/cardDetect/XF86Config.scfb" "${release}/usr/local/etc/X11/cardDetect/"
    install -o root -g wheel -m 755 "${cwd}/xorg/cardDetect/XF86Config.virtualbox" "${release}/usr/local/etc/X11/cardDetect/"
    install -o root -g wheel -m 755 "${cwd}/xorg/cardDetect/XF86Config.vmware" "${release}/usr/local/etc/X11/cardDetect/"
    install -o root -g wheel -m 755 "${cwd}/xorg/cardDetect/XF86Config.nvidia" "${release}/usr/local/etc/X11/cardDetect/"
    install -o root -g wheel -m 755 "${cwd}/xorg/cardDetect/XF86Config.intel" "${release}/usr/local/etc/X11/cardDetect/"
    install -o root -g wheel -m 755 "${cwd}/xorg/cardDetect/XF86Config.modesetting" "${release}/usr/local/etc/X11/cardDetect/"
  fi
}

uzip()
{
  umount ${release}/dev
  install -o root -g wheel -m 755 -d "${cdroot}"
  mkdir -pv "${cdroot}/data"
  makefs "${cdroot}/data/system.ufs" "${release}"
  mkuzip -o "${cdroot}/data/system.uzip" "${cdroot}/data/system.ufs"
  rm -rfv "${cdroot}/data/system.ufs"
}

ramdisk()
{
  ramdisk_root="${cdroot}/data/ramdisk"
  mkdir -pv "${ramdisk_root}"
  cd "${release}"
  tar -cf - rescue | tar -xf - -C "${ramdisk_root}"
  cd "${cwd}"
  install -o root -g wheel -m 755 "init.sh.in" "${ramdisk_root}/init.sh"
  sed "s/@VOLUME@/GHOSTBSD/" "init.sh.in" > "${ramdisk_root}/init.sh"
  mkdir -pv "${ramdisk_root}/dev"
  mkdir -pv "${ramdisk_root}/etc"
  touch "${ramdisk_root}/etc/fstab"
  cp ${release}/etc/login.conf ${ramdisk_root}/etc/login.conf
  makefs -b '10%' "${cdroot}/data/ramdisk.ufs" "${ramdisk_root}"
  gzip "${cdroot}/data/ramdisk.ufs"
  rm -rfv "${ramdisk_root}"
}

mfs()
{
  for dir in ${union_dirs}; do
    echo ${dir} >> ${cdroot}/data/uniondirs
    cd ${release} && tar -cpzf ${cdroot}/data/mfs.tgz ${union_dirs}
  done
}

boot()
{
  cd "${release}"
  tar -cf - boot | tar -xf - -C "${cdroot}"
  cd "${cwd}"
  cp -R boot/ ${cdroot}/boot/
  mkdir ${cdroot}/etc
}

image()
{
  sh mkisoimages.sh -b $label $isopath ${cdroot}
  ls -lh $isopath
  cd ${iso}
  shafile=$(echo ${isopath} | cut -d / -f6).sha256
  torrent=$(echo ${isopath} | cut -d / -f6).torrent
  tracker1="http://tracker.openbittorrent.com:80/announce"
  tracker2="udp://tracker.opentrackr.org:1337"
  tracker3="udp://tracker.coppersurfer.tk:6969"
  echo "Creating sha256 \"${iso}/${shafile}\""
  sha256 `echo ${isopath} | cut -d / -f6` > ${iso}/${shafile}
  transmission-create -o ${iso}/${torrent} -t ${tracker1} -t ${tracker3} -t ${tracker3} ${isopath}
  chmod 644 ${iso}/${torrent}
  cd -
}
