ifeq ($(tmpdir),)

location = $(CURDIR)/$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
self := $(location)

%:
	@tmpdir=`mktemp -d`; \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	$(MAKE) -f $(self) --no-print-directory tmpdir=$$tmpdir $@
else
C7_URI = http://wcs.bbxn.us/centos/7
EPEL7_URI = http://wcs.bbxn.us/epel/7


kscheck: ks.cfg
	ksvalidator ks.cfg -v RHEL7

Packages:
	mkdir Packages

repodata:
	mkdir repodata

# thie _guarantees_ we can resolve the base group data, even if not mirrored.
repodata/repomd.xml: centos-comps/c7-x86_64-comps.xml
	createrepo_c -g ./centos-comps/c7-x86_64-comps.xml .

repodata/installed-groups.txt: ks.cfg ks/netmgmt.ks ks-dumpgroups.py repodata
	./ks-dumpgroups.py ks.cfg > repodata/installed-groups.in
	./ks-dumpgroups.py ks/netmgmt.ks >> repodata/installed-groups.in
	sort -u repodata/installed-groups.in > repodata/installed-groups.txt

repodata/installed-packages.txt: ks.cfg ks/netmgmt.ks ks-dumppkgs.py repodata
	./ks-dumppkgs.py ks.cfg > repodata/installed-packages.in
	./ks-dumppkgs.py ks/netmgmt.ks >> repodata/installed-packages.in
	sort -u repodata/installed-packages.in > repodata/installed-packages.txt

repodata/.unwound-groups: repodata/installed-groups.txt repodata/repomd.xml unwind-groups.sh
	env YUM1=$(C7_URI) YUM2=$(EPEL7_URI) ./unwind-groups.sh repodata/installed-groups.txt
	touch repodata/.unwound-groups

Packages/.downloaded: repodata/.unwound-groups ks.cfg repodata/installed-packages.txt
	env YUM1=$(C7_URI) YUM2=$(EPEL7_URI) repotrack -c ./yum.conf -a x86_64 -p ./Packages $$(cat ./repodata/group-*.txt) $$(cat ./repodata/installed-packages.txt) wireshark
	$(MAKE) -B repodata/repomd.xml
	touch Packages/.downloaded

LiveOS:
	mkdir LiveOS

LiveOS/squashfs.img: LiveOS
	cd LiveOS && curl -LO $(C7_URI)/os/x86_64/LiveOS/squashfs.img

EFI:
	mkdir EFI

EFI/BOOT: EFI
	-mkdir EFI/BOOT

EFI/BOOT/fonts: EFI/BOOT
	-mkdir EFI/BOOT/fonts

EFI/BOOT/BOOTX64.EFI: EFI/BOOT
	cd EFI/BOOT && curl -LO $(C7_URI)/os/x86_64/EFI/BOOT/BOOTX64.EFI

EFI/BOOT/MokManager.efi: EFI/BOOT
	cd EFI/BOOT && curl -LO $(C7_URI)/os/x86_64/EFI/BOOT/MokManager.efi

EFI/BOOT/grub.cfg: EFI/BOOT grub.cfg
	cp grub.cfg EFI/BOOT

EFI/BOOT/grubx64.efi: EFI/BOOT
	cd EFI/BOOT && curl -LO $(C7_URI)/os/x86_64/EFI/BOOT/grubx64.efi

EFI/BOOT/fonts/unicode.pf2: EFI/BOOT/fonts
	cd EFI/BOOT/fonts && curl -LO $(C7_URI)/os/x86_64/EFI/BOOT/fonts/unicode.pf2

images:
	mkdir images

images/pxeboot: images
	mkdir images/pxeboot

images/pxeboot/vmlinuz: images/pxeboot
	cd images/pxeboot && curl -LO $(C7_URI)/os/x86_64/images/pxeboot/vmlinuz

images/pxeboot/initrd.img: images/pxeboot
	cd images/pxeboot && curl -LO $(C7_URI)/os/x86_64/images/pxeboot/initrd.img

images/initrd.img: images

discinfo:
	curl -L -o discinfo $(C7_URI)/os/x86_64/.discinfo

EFIFILES = EFI/BOOT/fonts/unicode.pf2 EFI/BOOT/grubx64.efi EFI/BOOT/MokManager.efi EFI/BOOT/BOOTX64.EFI EFI/BOOT/grub.cfg
REPOFILES = Packages/.downloaded repodata/repomd.xml discinfo
LIVEFILES = LiveOS/squashfs.img syslinux.cfg images/pxeboot/vmlinuz images/pxeboot/initrd.img
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
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s Packages ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s repodata ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s EFI ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s LiveOS ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@$$(cat usb.offset) -s images ::

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
	mkdir -p $(tmpdir)/isolinux/images/pxeboot
	ln $(tmpdir)/images/pxeboot/vmlinuz $(tmpdir)/isolinux/images/pxeboot/vmlinuz
	ln $(tmpdir)/images/pxeboot/initrd.img $(tmpdir)/isolinux/images/pxeboot/initrd.img
	find $(tmpdir) -exec chmod a+r {} \;
	find $(tmpdir) -type d -exec chmod a+rx {} \;
	mkisofs -quiet -o cdrom.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -rational-rock -J -T -V HVINABOX -hide-joliet-trans-tbl -hide-rr-moved $(tmpdir)

endif
