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

repodata/installed-groups.txt: ks.cfg ks-dumpgroups.py repodata
	./ks-dumpgroups.py > repodata/installed-groups.txt

repodata/installed-packages.txt: ks.cfg ks-dumppkgs.py repodata
	./ks-dumppkgs.py > repodata/installed-packages.txt

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

usb.img: Packages/.downloaded repodata/repomd.xml LiveOS/squashfs.img EFI/BOOT/fonts/unicode.pf2 EFI/BOOT/grubx64.efi EFI/BOOT/MokManager.efi EFI/BOOT/BOOTX64.EFI EFI/BOOT/grub.cfg syslinux.cfg discinfo images/pxeboot/vmlinuz images/pxeboot/initrd.img
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
