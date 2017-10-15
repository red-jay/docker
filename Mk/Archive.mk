location = $(CURDIR)/$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
self := $(location)

%/:
	mkdir -p $@

archive/openbsd/%/amd64/index.txt:
	$(MAKE) -f $(self) $(dir $@)
	cp Mk/Archive-openbsd.mk $(dir $@)Makefile
	$(MAKE) -C $(dir $@) BASE_URI=$(OBSD_BASE_URI) index.txt
	rm $(dir $@)Makefile
