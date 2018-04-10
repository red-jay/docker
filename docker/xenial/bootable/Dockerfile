FROM redjays/xenial:lxcore
MAINTAINER RJ <rbergero@gmail.com>
RUN env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y software-properties-common && apt-get clean all
RUN env LC_ALL=C DEBIAN_FRONTENV=noninteractive add-apt-repository ppa:notarrjay/fio-dkms && apt-get update && apt-get clean all

RUN env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get install -q -y ubuntu-standard \
                 casper lupin-casper discover laptop-detect os-prober \
                 linux-generic \
                 lvm2 thin-provisioning-tools cryptsetup mdadm xfsprogs bcache-tools \
                 memtest86+ nwipe smartmontools lm-sensors ethtool smartmontools fio \
                 openssh-server augeas-tools \
                 dbus \
                 grub-efi-amd64-bin grub-efi-ia32-bin grub-efi-amd64-signed shim syslinux isolinux hfsprogs hfsplus && apt-get clean all

RUN dpkg-divert --rename /usr/sbin/update-grub && ln -s /bin/true /usr/sbin/update-grub && \
    env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get -q -y install tboot && \
    rm /usr/sbin/update-grub && dpkg-divert --rename --remove /usr/sbin/update-grub

RUN apt-get update && env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get -q -y install iomemory-vsl-dkms && \
    bash -c 'i=(/usr/src/iomemory-vsl*) && k=(/boot/vmlinuz-*) && k=${k[0]#*-} && \
    dkms add "${i[0]}" && dkms autoinstall -k "${k}"' && apt-get -q -y clean all && \
    rm -f /boot/initrd.*.old-dkms

RUN wget -o /boot/macboot.img http://mirrors.kernel.org/fedora/releases/27/Server/x86_64/os/images/macboot.img

RUN mkdir /isolinux && cp /usr/lib/ISOLINUX/isolinux.bin /isolinux/isolinux.bin && \
                       cp /usr/lib/syslinux/modules/bios/*.c32 /isolinux && \
                       cp /usr/lib/ISOLINUX/isohd*.bin /isolinux

RUN grub-mkimage -O i386-efi -d /usr/lib/grub/i386-efi -o /usr/lib/grub/i386-efi/gcdia32.efi -p /EFI/BOOT \
     all_video boot btrfs cat chain configfile echo efifwsetup efinet ext2 fat font gfxmenu gfxterm gzio halt hfsplus iso9660 jpeg loadenv lvm mdraid09 mdraid1x minicmd normal part_apple part_msdos part_gpt password_pbkdf2 png reboot search search_fs_uuid search_fs_file search_label sleep syslinuxcfg test tftp regexp video xfs

RUN truncate -s 12M /boot/efiboot.img && mkfs.vfat -F16 /boot/efiboot.img && \
      mmd -i /boot/efiboot.img efi && mmd -i /boot/efiboot.img efi/boot && \
      mcopy -i /boot/efiboot.img /usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed ::efi/boot/bootx64.efi && \
      mcopy -i /boot/efiboot.img /usr/lib/grub/i386-efi/gcdia32.efi ::efi/boot/bootia32.efi && \
      mmd -i /boot/efiboot.img efi/boot/i386-efi && mcopy -i /boot/efiboot.img /usr/lib/grub/i386-efi/*.mod ::efi/boot/i386-efi && \
      mkdir -p /EFI/BOOT/i386-efi && cp /usr/lib/grub/i386-efi/*.mod /EFI/BOOT/i386-efi

RUN bash -c 'd="" ; c="/isolinux/syslinux.cfg.tpl" ; for i in /boot/initrd.img* ; do v="${i%-generic*}" ; v="${v#*.img-}" ; { [ ! -z "${d}" ] && d="${v}" ; echo "DEFAULT ${v}" >> "${c}" ; } ; echo "LABEL ${v}" >> "${c}" ; echo " KERNEL vmlinuz-${v}-generic" >> "${c}" ; echo " INITRD initrd.img-${v}-generic" >> "${c}" ; echo " APPEND console=tty0 root=UNSET rw" >> "${c}" ; done'

RUN mktemp /.bootid.XXXXXX
