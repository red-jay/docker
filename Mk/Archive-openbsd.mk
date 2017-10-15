ifeq ($(tmpdir),)

location = $(CURDIR)/$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
self := $(location)

%:
	@tmpdir=`mktemp -d`; \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	$(MAKE) -f $(self) --no-print-directory tmpdir=$$tmpdir $@
else

BASE_URI=http://wcs.bbxn.us/OpenBSD

DL_ARCH=$(notdir $(CURDIR))
DL_VER=$(notdir $(subst /$(DL_ARCH),,$(CURDIR)))
DL_NDVER=$(subst .,,$(DL_VER))

index.txt: base$(DL_NDVER).tgz bsd.rd bsd.mp bsd SHA256.sig
	ls -ln > index.txt

%:
	curl -L -o $(tmpdir)/$(notdir $@) $(BASE_URI)/$(DL_VER)/$(DL_ARCH)/$(notdir $@)
	mv $(tmpdir)/$(notdir $@) $(notdir $@)

endif
