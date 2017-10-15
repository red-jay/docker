location = $(CURDIR)/$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
self := $(location)

%/:
	mkdir -p $@

archive/openbsd/%/amd64/index.txt:
	$(MAKE) -f $(self) $(dir $@)
	cp Mk/Archive-openbsd.mk $(dir $@)Makefile
	$(MAKE) -C $(dir $@) BASE_URI=$(OBSD_BASE_URI) index.txt
	rm $(dir $@)Makefile

archive/centos%/comps/.git:
	git submodule update --init

archive/centos%/comps/c7-x86_64-comps.xml: archive/centos%/comps/.git

archive/centos%/repodata/repomd.xml: archive/centos%/comps/c7-x86_64-comps.xml | archive/centos%/repodata/
	$(MAKE) -f $(self) $(dir $@)
	cd archive/centos7 ; createrepo_c -g ./comps/c7-x86_64-comps.xml .

archive/centos%/discinfo: | archive/centos%/
	cd $(dir $@) ; curl -L -o discinfo $(CENTOS_URI)/$(subst archive/centos,,$(dir $@))os/x86_64/.discinfo

archive/centos%/images/pxeboot/vmlinuz: | archive/centos%/images/pxeboot/
	cd $(dir $@) ; curl -LO $(CENTOS_URI)/$(subst images/pxeboot/,,$(subst archive/centos,,$(dir $@)))os/x86_64/images/pxeboot/vmlinuz

archive/centos%/images/pxeboot/initrd.img: | archive/centos%/images/pxeboot/
	cd $(dir $@) ; curl -LO $(CENTOS_URI)/$(subst images/pxeboot/,,$(subst archive/centos,,$(dir $@)))os/x86_64/images/pxeboot/initrd.img
