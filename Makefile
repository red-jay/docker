ifeq ($(tmpdir),)

location = $(CURDIR)/$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
self := $(location)

%:
	@tmpdir=`mktemp -d`; \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	$(MAKE) -f $(self) --no-print-directory tmpdir=$$tmpdir $@
else
CENTOS_URI = http://wcs.bbxn.us/centos
C7_URI = $(CENTOS_URI)/7
EPEL7_URI = http://wcs.bbxn.us/epel/7
OBSD_BASE_URI = http://wcs.bbxn.us/OpenBSD

# keying
well-known-keys/.git:
	git submodule update --init

well-known-keys/authorized_keys: well-known-keys/.git

# OpenBSD
archive/openbsd/%/amd64/index.txt:
	$(MAKE) -f Mk/Archive.mk OBSD_BASE_URI=$(OBSD_BASE_URI) $@

# Centos 7 Repository
archive/centos%/repodata/repomd.xml:
	$(MAKE) -f Mk/Archive.mk $@

archive/centos7/group-packages: archive/centos7/repodata/repomd.xml ks/installed-groups.txt
	env YUM1=$(C7_URI) YUM2=$(EPEL7_URI) ./build-scripts/unwind-groups.sh ks/installed-groups.txt > archive/centos7/group-packages

archive/centos7/Packages/.downloaded: ks/installed-packages.txt archive/centos7/group-packages archive/centos7/repodata/repomd.xml
	env YUM1=$(C7_URI) YUM2=$(EPEL7_URI) repotrack -c ./yum.conf -a x86_64 -p archive/centos7/Packages $$(cat archive/centos7/group-packages) $$(cat ks/installed-packages.txt) wireshark
	touch archive/centos7/Packages/.downloaded

# Kickstart recognition file
archive/centos7/discinfo:
	$(MAKE) -f Mk/Archive.mk CENTOS_URI=$(CENTOS_URI) archive/centos7/discinfo

# Centos 7 Kickstarts
kscheck: ks/Makefile
	$(MAKE) -C ks ksvalidate

ks/installed-groups.txt: ks/Makefile
	$(MAKE) -C ks DUMPGROUP=$(CURDIR)/build-scripts/ks-dumpgroups.py installed-groups.txt

ks/installed-packages.txt: ks/Makefile
	$(MAKE) -C ks DUMPPKGS=$(CURDIR)/build-scripts/ks-dumppkgs.py installed-packages.txt

REPOFILES= = archive/centos7/Packages/.downloaded archive/centos7/discinfo

# Boot files
archive/centos7/images/pxeboot/%:
	$(MAKE) -f Mk/Archive.mk CENTOS_URI=$(CENTOS_URI) $@

archive/centos7/LiveOS/squashfs.img:
	$(MAKE) -f Mk/Archive.mk CENTOS_URI=$(CENTOS_URI) $@

archive/centos7/EFI/BOOT/%:
	$(MAKE) -f Mk/Archive.mk CENTOS_URI=$(CENTOS_URI) $@

archive/centos7/EFI/BOOT/fonts/%:
	$(MAKE) -f Mk/Archive.mk CENTOS_URI=$(CENTOS_URI) $@

BOOTFILES = archive/centos7/EFI/BOOT/fonts/unicode.pf2
BOOTFILES += archive/centos7/EFI/BOOT/grubx64.efi archive/centos7/EFI/BOOT/grubia32.efi
BOOTFILES += archive/centos7/EFI/BOOT/mmx64.efi archive/centos7/EFI/BOOT/mmia32.efi
BOOTFILES += archive/centos7/EFI/BOOT/BOOTX64.EFI archive/centos7/EFI/BOOT/BOOTIA32.EFI
BOOTFILES += archive/centos7/images/pxeboot/vmlinuz archive/centos7/images/pxeboot/initrd.img
BOOTFILES += archive/centos7/LiveOS/squashfs.img

LIVEFILES = syslinux.cfg openbsd-dist/$(OBSD_VER)/amd64/index.txt
IMAGEFILES = $(REPOFILES) $(LIVEFILES) $(EFIFILES)

usb.img: $(IMAGEFILES)
	mkdiskimage -FM4os usb.img 2048 256 63 > usb.offset
	dd conv=notrunc bs=440 count=1 if=/usr/share/syslinux/mbr.bin of=usb.img
	env MTOOLS_SKIP_CHECK=1 mlabel -i usb.img@@$$(cat usb.offset) ::HVINABOX
	syslinux -t $$(cat usb.offset) usb.img
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s syslinux.cfg ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s /usr/share/syslinux/chain.c32 ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s /usr/share/syslinux/libcom32.c32 ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s /usr/share/syslinux/libutil.c32 ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s discinfo ::.discinfo
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s ks.cfg ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s ks ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s bootstrap-scripts ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s ipxe-images.tgz ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s Packages ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s repodata ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s EFI ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s LiveOS ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s images ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s openbsd-dist ::

cdrom.iso: $(IMAGEFILES)
	mkdir -p $(tmpdir)/isolinux
	cp syslinux.cfg $(tmpdir)/isolinux/
	cp /usr/share/syslinux/chain.c32 $(tmpdir)/isolinux/
ifneq ("$(wildcard /usr/share/syslinux/ldlinux.c32)","")
	cp /usr/share/syslinux/ldlinux.c32 $(tmpdir)/isolinux/
endif
	cp /usr/share/syslinux/isolinux.bin $(tmpdir)/isolinux/
	cp discinfo $(tmpdir)/.discinfo
	cp ks.cfg $(tmpdir)/
	cp -r ks/ $(tmpdir)/
	cp -r bootstrap-scripts/ $(tmpdir)/
	cp ipxe-images.tgz $(tmpdir)/
	cp -r Packages $(tmpdir)/
	cp -r repodata $(tmpdir)/
	cp -r EFI $(tmpdir)/
	cp -r LiveOS $(tmpdir)/
	cp -r images $(tmpdir)/
	cp -r openbsd-dist $(tmpdir)/
	mkdir -p $(tmpdir)/isolinux/images/pxeboot
	ln $(tmpdir)/images/pxeboot/vmlinuz $(tmpdir)/isolinux/images/pxeboot/vmlinuz
	ln $(tmpdir)/images/pxeboot/initrd.img $(tmpdir)/isolinux/images/pxeboot/initrd.img
	find $(tmpdir) -exec chmod a+r {} \;
	find $(tmpdir) -type d -exec chmod a+rx {} \;
	mkisofs -quiet -o cdrom.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -rational-rock -J -V HVINABOX -hide-joliet-trans-tbl -hide-rr-moved $(tmpdir)

netmgmt.iso: $(IMAGEFILES)
	mkdir -p $(tmpdir)/isolinux
	cp syslinux-siteprompt.cfg $(tmpdir)/isolinux/syslinux.cfg
	cp /usr/share/syslinux/chain.c32 $(tmpdir)/isolinux/
ifneq ("$(wildcard /usr/share/syslinux/ldlinux.c32)","")
	cp /usr/share/syslinux/ldlinux.c32 $(tmpdir)/isolinux/
endif
	cp /usr/share/syslinux/isolinux.bin $(tmpdir)/isolinux/
	cp discinfo $(tmpdir)/.discinfo
	cp ks/netmgmt.ks $(tmpdir)/ks.cfg
	cp -r bootstrap-scripts/ $(tmpdir)/
	cp ipxe-images.tgz $(tmpdir)/
	cp -r Packages $(tmpdir)/
	cp -r repodata $(tmpdir)/
	cp -r EFI $(tmpdir)/
	cp -r LiveOS $(tmpdir)/
	cp -r images $(tmpdir)/
	cp -r openbsd-dist $(tmpdir)/
	mkdir -p $(tmpdir)/isolinux/images/pxeboot
	ln $(tmpdir)/images/pxeboot/vmlinuz $(tmpdir)/isolinux/images/pxeboot/vmlinuz
	ln $(tmpdir)/images/pxeboot/initrd.img $(tmpdir)/isolinux/images/pxeboot/initrd.img
	find $(tmpdir) -exec chmod a+r {} \;
	find $(tmpdir) -type d -exec chmod a+rx {} \;
	mkisofs -quiet -o netmgmt.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -rational-rock -J -V NETMGMT -hide-joliet-trans-tbl -hide-rr-moved $(tmpdir)

endif
