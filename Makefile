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
ifeq ($(MINIMAL),1)
	$(MAKE) -C ks KSFILES=$(basename $(MAKECMDGOALS)).ks
else
	$(MAKE) -C ks ksvalidate
endif

ks/installed-groups.txt: ks/Makefile
ifeq ($(MINIMAL),1)
	$(MAKE) -C ks DUMPGROUP=$(CURDIR)/build-scripts/ks-dumpgroups.py KSFILES=$(basename $(MAKECMDGOALS)).ks installed-groups.txt
else
	$(MAKE) -C ks DUMPGROUP=$(CURDIR)/build-scripts/ks-dumpgroups.py installed-groups.txt
endif

ks/installed-packages.txt: ks/Makefile
ifeq ($(MINIMAL),1)
	$(MAKE) -C ks DUMPPKGS=$(CURDIR)/build-scripts/ks-dumppkgs.py KSFILES=$(basename $(MAKECMDGOALS)).ks installed-packages.txt
else
	$(MAKE) -C ks DUMPPKGS=$(CURDIR)/build-scripts/ks-dumppkgs.py installed-packages.txt
endif

REPOFILES = archive/centos7/Packages/.downloaded archive/centos7/discinfo

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

distclean:
	-rm -rf archive/openbsd
	-rm -rf archive/centos7/discinfo
	-rm -rf archive/centos7/EFI
	-rm -rf archive/centos7/group-packages
	-rm -rf archive/centos7/images
	-rm -rf archive/centos7/LiveOS
	-rm -rf archive/centos7/Packages
	-rm -rf archice/centos7/repodata
	$(MAKE) -C ks clean

clean:
	rm -rf archive/centos7/group-packages
	$(MAKE) -C ks clean

ISOFILES = $(REPOFILES) $(BOOTFILES)
ifneq ($(MINIMAL),1)
ISOFILES += archive/openbsd/6.2/amd64/index.txt
endif

%.iso: $(ISOFILES) syslinux/%.cfg grub/%.cfg ks/%.ks
	mkdir -p $(tmpdir)/isolinux
	cp syslinux/$(basename $(notdir $@)).cfg $(tmpdir)/isolinux/syslinux.cfg
	cp /usr/share/syslinux/chain.c32 $(tmpdir)/isolinux/
ifneq ("$(wildcard /usr/share/syslinux/ldlinux.c32)","")
	cp /usr/share/syslinux/ldlinux.c32 $(tmpdir)/isolinux/
endif
	cp /usr/share/syslinux/isolinux.bin $(tmpdir)/isolinux/
	cp archive/centos7/discinfo $(tmpdir)/.discinfo
	cp ks/$(basename $(notdir $@)).ks $(tmpdir)/ks.cfg
	cp -r archive/centos7/Packages $(tmpdir)/
	cp -r archive/centos7/repodata $(tmpdir)/
	cp -r archive/centos7/EFI $(tmpdir)/
	cp -r archive/centos7/LiveOS $(tmpdir)/
	cp -r archive/centos7/images $(tmpdir)/
	mkdir -p $(tmpdir)/isolinux/images/pxeboot
	ln $(tmpdir)/images/pxeboot/vmlinuz $(tmpdir)/isolinux/images/pxeboot/vmlinuz
	ln $(tmpdir)/images/pxeboot/initrd.img $(tmpdir)/isolinux/images/pxeboot/initrd.img
	find $(tmpdir) -exec chmod a+r {} \;
	find $(tmpdir) -type d -exec chmod a+rx {} \;
	mkisofs -quiet -o $@ -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -rational-rock -J -V HVINABOX -hide-joliet-trans-tbl -hide-rr-moved $(tmpdir)

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

endif
