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
