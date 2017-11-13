location = $(CURDIR)/$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
self := $(location)

%/:
	mkdir -p $@

archive/openbsd/%/amd64/index.txt:
	$(MAKE) -f $(self) $(dir $@)
	cp Mk/Archive-openbsd.mk $(dir $@)Makefile
	$(MAKE) -C $(dir $@) BASE_URI=$(OBSD_BASE_URI) index.txt
	rm $(dir $@)Makefile

archive/openbsd-syspatch/%/amd64/.all:
	$(MAKE) -f $(self) $(dir $@)
	cp Mk/Archive-openbsd-syspatch.mk $(dir $@)Makefile
	$(MAKE) -C $(dir $@) BASE_URI=$(OBSD_BASE_URI) .all
	rm $(dir $@)Makefile

archive/openbsd-packages/%/amd64/index.txt:
	$(MAKE) -f $(self) $(dir $@)
	cp Mk/Archive-openbsd-package.mk $(dir $@)Makefile
	$(MAKE) -C $(dir $@) BASE_URI=$(OBSD_BASE_URI) index.txt
	rm $(dir $@)Makefile

archive/centos%/comps/.git:
	git submodule update --init

archive/centos%/comps/c7-x86_64-comps.xml: archive/centos%/comps/.git

archive/centos%/repodata/repomd.xml: archive/centos%/comps/c7-x86_64-comps.xml | archive/centos%/repodata/
	$(MAKE) -f $(self) $(dir $@)
	cd archive/centos7 && createrepo_c -g ./comps/c7-x86_64-comps.xml .

archive/centos%/discinfo: | archive/centos%/
	$(MAKE) -f $(self) $(dir $@)
	cd $(dir $@) && curl -L -o discinfo $(CENTOS_URI)/$(subst archive/centos,,$(dir $@))os/x86_64/.discinfo

archive/centos%/images/pxeboot/vmlinuz: | archive/centos%/images/pxeboot/
	$(MAKE) -f $(self) $(dir $@)
	cd $(dir $@) && curl -LO $(CENTOS_URI)/$(subst images/pxeboot/,,$(subst archive/centos,,$(dir $@)))os/x86_64/images/pxeboot/vmlinuz

archive/centos%/images/pxeboot/initrd.img: | archive/centos%/images/pxeboot/
	$(MAKE) -f $(self) $(dir $@)
	cd $(dir $@) && curl -LO $(CENTOS_URI)/$(subst images/pxeboot/,,$(subst archive/centos,,$(dir $@)))os/x86_64/images/pxeboot/initrd.img

archive/centos%/LiveOS/squashfs.img: | archive/centos%/LiveOS/
	$(MAKE) -f $(self) $(dir $@)
	cd $(dir $@) && curl -LO $(CENTOS_URI)/$(subst LiveOS/,,$(subst archive/centos,,$(dir $@)))os/x86_64/LiveOS/squashfs.img

archive/centos7/EFI/BOOT/%: | archive/centos7/EFI/BOOT/
	cd $(dir $@) && curl -LO $(CENTOS_URI)/7/os/x86_64/EFI/BOOT/$(notdir $@)

archive/centos7/EFI/BOOT/fonts:
	mkdir -p $@

archive/centos7/EFI/BOOT/fonts/%: | archive/centos7/EFI/BOOT/fonts
	cd $(dir $@) && curl -LO $(CENTOS_URI)/7/os/x86_64/EFI/BOOT/fonts/$(notdir $@)
