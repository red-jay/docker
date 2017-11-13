ifeq ($(tmpdir),)

location = $(CURDIR)/$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
self := $(location)

%:
	@tmpdir=`mktemp -d`; \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	$(MAKE) -f $(self) --no-print-directory tmpdir=$$tmpdir $@
else

DL_ARCH=$(notdir $(CURDIR))
DL_VER=$(notdir $(subst /$(DL_ARCH),,$(CURDIR)))
DL_NDVER=$(subst .,,$(DL_VER))

PHONY: .all

.all: SHA256.sig SHA256
	$(MAKE) $(shell awk '$$1 == "SHA256" {print substr($$2, 2, (length($$2) - 2))}' < SHA256.sig)

%:
	curl -L -o $(tmpdir)/$(notdir $@) $(BASE_URI)/syspatch/$(DL_VER)/$(DL_ARCH)/$(notdir $@)
	mv $(tmpdir)/$(notdir $@) $(notdir $@)

endif
