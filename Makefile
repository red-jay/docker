kscheck: ks.cfg
	ksvalidator ks.cfg -v RHEL7

Packages:
	mkdir Packages

# thie _guarantees_ we can resolve the base group data, even if not mirrored.
Packages/repodata/repomd.xml: Packages centos-comps/c7-x86_64-comps.xml
	cd Packages && createrepo_c -g ../centos-comps/c7-x86_64-comps.xml .

Packages/repodata/installed-groups.txt: ks.cfg ks-dumpgroups.py
	./ks-dumpgroups.py > Packages/repodata/installed-groups.txt

Packages/repodata/.unwound-groups: Packages/repodata/installed-groups.txt Packages/repodata/repomd.xml unwind-groups.sh
	./unwind-groups.sh Packages/repodata/installed-groups.txt
	touch Packages/repodata/.unwound-groups

Packages/.downloaded: Packages/repodata/base-group.txt Packages/repodata/core-group.txt ks.cfg
	repotrack -a x86_64 -p ./Packages $$(cat Packages/repodata/group-*.txt)
	$(MAKE) Packages/repodata/repomd.xml
	touch Packages/.downloaded

LiveOS:
	mkdir LiveOS

LiveOS/squashfs.img: LiveOS
	cd LiveOS && curl -LO http://mirrors.kernel.org/centos/7/os/x86_64/LiveOS/squashfs.img

EFI:
	mkdir EFI

EFI/BOOT: EFI
	mkdir EFI/BOOT

EFI/BOOT/fonts: EFI/BOOT
	mkdir EFI/BOOT/fonts

EFI/BOOT/BOOTX64.EFI: EFI/BOOT
	cd EFI/BOOT && curl -LO http://mirrors.kernel.org/centos/7/os/x86_64/EFI/BOOT/BOOTX64.EFI

EFI/BOOT/MokManager.efi: EFI/BOOT
	cd EFI/BOOT && curl -LO http://mirrors.kernel.org/centos/7/os/x86_64/EFI/BOOT/MokManager.efi

EFI/BOOT/grub.cfg: EFI/BOOT grub.cfg
	cp grub.cfg EFI/BOOT

EFI/BOOT/grubx64.efi: EFI/BOOT
	cd EFI/BOOT && curl -LO http://mirrors.kernel.org/centos/7/os/x86_64/EFI/BOOT/grubx64.efi

EFI/BOOT/fonts/unicode.pf2: EFI/BOOT/fonts
	cd EFI/BOOT/fonts && curl -LO http://mirrors.kernel.org/centos/7/os/x86_64/EFI/BOOT/fonts/unicode.pf2

images:
	mkdir images

images/pxeboot: images
	mkdir images/pxeboot

images/pxeboot/vmlinuz: images/pxeboot
	cd images/pxeboot && curl -LO http://mirrors.kernel.org/centos/7/os/x86_64/images/pxeboot/vmlinuz

images/pxeboot/initrd.img: images/pxeboot
	cd images/pxeboot && curl -LO http://mirrors.kernel.org/centos/7/os/x86_64/images/pxeboot/initrd.img

images/initrd.img: images

overhead.img:
	dd if=/dev/zero of=overhead.img bs=2M count=1

usb.img: Packages/.downloaded LiveOS/squashfs.img EFI/BOOT/fonts/unicode.pf2 EFI/BOOT/grubx64.efi EFI/BOOT/MokManager.efi EFI/BOOT/BOOTX64.EFI EFI/BOOT/grub.cfg overhead.img
	truncate -s $$(du -ks --total Packages/ LiveOS/ EFI/ images/ overhead.img|tail -n1|cut - -f1)k usb.img
	parted -s usb.img mklabel msdos
	parted -s usb.img mkpart primary fat32 1M 100%
	parted -s usb.img set 1 boot on
	dd conv=notrunc bs=440 count=1 if=/usr/share/syslinux/mbr.bin of=usb.img
	guestfish -a usb.img run : mkfs vfat /dev/sda1
	syslinux -t 1048576 usb.img
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@1M -s Packages ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@1M -s EFI ::
	env MTOOLS_SKIP_CHECK=1 mcopy -i usb.img@@1M -s LiveOS ::
