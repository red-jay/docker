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
ELK_URI = http://elrepo.org/linux/kernel/el7
OBSD_BASE_URI = http://wcs.bbxn.us/OpenBSD
INCLUDE_PRIVATE = true

# keying
well-known-keys/.git:
	git submodule update --init

well-known-keys/authorized_keys: well-known-keys/.git

# iPXE
ipxe-cfgs/.git:
	git submodule update --init

ipxe-cfgs/ipxe-binaries.tgz: ipxe-cfgs/.git
	cd ipxe-cfgs && ./build.sh

# intCA
intca-pub/.git:
	git submodule update --init

intca-pub/index.txt: intca-pub/.git
	cd intca-pub && ls -ln > index.txt

# certs
certs/index.txt: certs
	cd certs && ls -ln > index.txt

# OpenBSD
archive/openbsd/%/amd64/index.txt:
	$(MAKE) -f Mk/Archive.mk OBSD_BASE_URI=$(OBSD_BASE_URI) $@

archive/openbsd-syspatch/%/amd64/.all:
	$(MAKE) -f Mk/Archive.mk OBSD_BASE_URI=$(OBSD_BASE_URI) $@

archive/openbsd-packages/%/amd64/index.txt:
	$(MAKE) -f Mk/Archive.mk OBSD_BASE_URI=$(OBSD_BASE_URI) $@

# Centos 7 Repository
archive/centos%/repodata/repomd.xml:
	$(MAKE) -f Mk/Archive.mk $@

archive/centos7/group-packages: archive/centos7/repodata/repomd.xml ks/installed-groups.txt
	env YUM1=$(C7_URI) YUM2=$(EPEL7_URI) YUM3=$(ELK_URI) ./build-scripts/unwind-groups.sh ks/installed-groups.txt > archive/centos7/group-packages

archive/centos7/Packages/.downloaded: ks/installed-packages.txt archive/centos7/group-packages archive/centos7/repodata/repomd.xml
	env YUM1=$(C7_URI) YUM2=$(EPEL7_URI) YUM3=$(ELK_URI) repotrack -c ./yum.conf -a x86_64 -p archive/centos7/Packages $$(cat archive/centos7/group-packages) $$(cat ks/installed-packages.txt) wireshark
	cd $(subst Packages/,,$(dir $@)) && createrepo_c -g ./comps/c7-x86_64-comps.xml .
	touch archive/centos7/Packages/.downloaded

# Ubuntu Repository
archive/ubuntu/xenial/.downloaded: build-scripts/make-archive.sh build-scripts/dl-pkgs.sh
	./build-scripts/make-archive.sh

# Kickstart recognition files
archive/centos7/discinfo:
	$(MAKE) -f Mk/Archive.mk CENTOS_URI=$(CENTOS_URI) archive/centos7/discinfo

archive/centos7/treeinfo:
	$(MAKE) -f Mk/Archive.mk CENTOS_URI=$(CENTOS_URI) archive/centos7/treeinfo

# private ISOs
private-isos/%.iso: Mk/Private.mk
	$(MAKE) -f Mk/Private.mk $@

# keep archive files
.SECONDARY: archive/centos7/EFI/BOOT/fonts/unicode.pf2 archive/centos7/EFI/BOOT/grubia32.efi archive/centos7/EFI/BOOT/mmia32.efi archive/centos7/EFI/BOOT/BOOTX64.EFI archive/centos7/images/pxeboot/initrd.img archive/centos7/EFI/BOOT/mmx64.efi archive/centos7/EFI/BOOT/grubx64.efi archive/centos7/images/pxeboot/vmlinuz archive/centos7/EFI/BOOT/BOOTIA32.EFI archive/openbsd/6.2/amd64/index.txt

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

REPOFILES = archive/centos7/Packages/.downloaded archive/centos7/discinfo archive/centos7/treeinfo

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
BOOTFILES += well-known-keys/authorized_keys intca-pub/index.txt certs/index.txt

distclean:
	$(MAKE) clean
	-rm -rf archive/openbsd
	-rm -rf archive/centos7/discinfo
	-rm -rf archive/centos7/treeinfo
	-rm -rf archive/centos7/EFI
	-rm -rf archive/centos7/images
	-rm -rf archive/centos7/LiveOS
	-rm -rf archive/centos7/Packages
	-rm -rf archice/centos7/repodata
	-rm -rf ipxe-cfgs/ipxe
	-rm -rf ipxe-cfgs/ipxe-binaries.tgz

clean:
	-rm -rf *.iso
	-rm -rf archive/centos7/Packages/.downloaded
	-rm -rf archive/centos7/group-packages
	$(MAKE) -C ks clean

ISOFILES = $(REPOFILES) $(BOOTFILES)
ifneq ($(MINIMAL),1)
ISOFILES += archive/openbsd/6.2/amd64/index.txt archive/openbsd-syspatch/6.2/amd64/.all ipxe-cfgs/ipxe-binaries.tgz
ISOFILES += archive/openbsd-packages/6.2/amd64/index.txt
ifeq ($(findstring hypervisor,$(MAKECMDGOALS)),hypervisor)
ifeq ($(INCLUDE_PRIVATE),true)
ISOFILES += private-isos/tgw.sv1.iso private-isos/tgw.sv1a.iso private-isos/tgw.sv2.iso
endif
endif
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
	cp archive/centos7/treeinfo $(tmpdir)/.treeinfo
	cp ks/$(basename $(notdir $@)).ks $(tmpdir)/ks.cfg
	cp well-known-keys/authorized_keys $(tmpdir)/
	cp -r intca-pub $(tmpdir)/
	cp -r certs $(tmpdir)/
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
ifneq ($(MINIMAL),1)
ifeq ($(findstring hypervisor,$(MAKECMDGOALS)),hypervisor)
ifeq ($(INCLUDE_PRIVATE),true)
	cp -r private-isos $(tmpdir)/
endif
	cp -r bootstrap-scripts $(tmpdir)/
	cp -r ks $(tmpdir)/
	cp -r archive/openbsd $(tmpdir)/openbsd-dist
	cp -r archive/openbsd-syspatch $(tmpdir)/openbsd-dist/syspatch
	cp -r archive/openbsd-packages/6.2 $(tmpdir)/openbsd-dist/6.2/packages
	cp ipxe-cfgs/ipxe-binaries.tgz $(tmpdir)
endif
endif
ifeq ($(findstring netmgmt,$(MAKECMDGOALS)),netmgmt)
	cp -r archive/openbsd $(tmpdir)/openbsd-dist
	cp -r archive/openbsd-syspatch $(tmpdir)/openbsd-dist/syspatch
	cp -r archive/openbsd-packages/6.2 $(tmpdir)/openbsd-dist/6.2/packages
	cp ipxe-cfgs/ipxe-binaries.tgz $(tmpdir)
endif
	cp ks-scripts/fs-layout.sh $(tmpdir)
	cp ks-scripts/install-stack.sh $(tmpdir)
	cp tf-output/common/hv-bridge-map.sh $(tmpdir)
	cp tf-output/common/intmac-remap.sh $(tmpdir)
	cp tf-output/common/intmac-bridge.sh $(tmpdir)
	mkisofs -quiet -o $@ -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -rational-rock -J -V KICKSTART -hide-joliet-trans-tbl -hide-rr-moved $(tmpdir)

%.img: $(ISOFILES) syslinux/%.cfg grub/%.cfg ks/%.ks
	mkdiskimage -FM4os $(basename $(notdir $@)).img 2560 256 63 > usb.offset
	dd conv=notrunc bs=440 count=1 if=/usr/share/syslinux/mbr.bin of=$(basename $(notdir $@)).img
	env MTOOLS_SKIP_CHECK=1 mlabel -i $(basename $(notdir $@)).img@@$$(cat usb.offset) ::KICKSTART
	syslinux -t $$(cat usb.offset) $(basename $(notdir $@)).img
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s syslinux/$(basename $(notdir $@)).cfg ::syslinux.cfg 
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s /usr/share/syslinux/chain.c32 ::
ifneq ("$(wildcard /usr/share/syslinux/libcom32.c32)","")
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s /usr/share/syslinux/libcom32.c32 ::
endif
ifneq ("$(wildcard /usr/share/syslinux/libutil.c32)","")
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s /usr/share/syslinux/libutil.c32 ::
endif
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s archive/centos7/discinfo ::.discinfo
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s archive/centos7/treeinfo ::.treeinfo
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s ks/$(basename $(notdir $@)).ks ::ks.cfg
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s well-known-keys/authorized_keys ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s intca-pub ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s certs ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s archive/centos7/Packages ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s archive/centos7/repodata ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s archive/centos7/EFI ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s grub/$(basename $(notdir $@)).cfg ::EFI/BOOT/grub.cfg
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s archive/centos7/LiveOS ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s archive/centos7/images ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s ks-scripts/fs-layout.sh ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s ks-scripts/install-stack.sh ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s tf-output/common/hv-bridge-map.sh ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s tf-output/common/intmac-remap.sh ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s tf-output/common/intmac-bridge.sh ::
ifneq ($(MINIMAL),1)
ifeq ($(findstring hypervisor,$(MAKECMDGOALS)),hypervisor)
ifeq ($(INCLUDE_PRIVATE),true)
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s private-isos ::
endif
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s bootstrap-scripts ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s ks ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s archive/openbsd ::openbsd-dist
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s archive/openbsd-syspatch ::openbsd-dist/syspatch
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s archive/openbsd-packages/6.2 ::openbsd-dist/6.2/packages
	env MTOOLS_SKIP_CHECK=1 mcopy -i $(basename $(notdir $@)).img@@$$(cat usb.offset) -s ipxe-cfgs/ipxe-binaries.tgz ::
endif
endif

endif
