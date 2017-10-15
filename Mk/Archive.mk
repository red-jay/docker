location = $(CURDIR)/$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
self := $(location)

%/:
	mkdir -p $@

archive/openbsd/%/amd64/index.txt:
	$(MAKE) -f $(self) $(dir $@)
	pwd
	cp Mk/Archive-openbsd.mk $(dir $@)Makefile
	$(MAKE) -C $(dir $@) index.txt
	rm $(dir $@)Makefile
