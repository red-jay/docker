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

PHONY: .all .index recursive

%:
	curl -L -o $(tmpdir)/$(notdir $@) $(BASE_URI)/$(DL_VER)/packages/$(DL_ARCH)/$(notdir $@)
	mv $(tmpdir)/$(notdir $@) $(notdir $@)


recursive: $(PKG)
	DEPS=$$(tar xOf $(PKG) +CONTENTS | grep ^@depend | cut -d: -f3) ; \
		if [ ! -z "$$DEPS" ] ; then for d in $$DEPS ; do \
		$(MAKE) PKG=$$d.tgz recursive ; done ; fi

.index:
	curl -L -o $(tmpdir)/index $(BASE_URI)/$(DL_VER)/packages/$(DL_ARCH)
	awk -F'<a href="' '$$2 != "" {split($$2,a,"\"");print a[1]}' < $(tmpdir)/index > $(tmpdir)/index.txt

%.name: .index
	set -e ; PKG=$$(grep ^$(@:.name=)-[0-9] $(tmpdir)/index.txt) && $(MAKE) PKG=$$PKG recursive

index.txt: apg.name openvpn.name SHA256 SHA256.sig
	ls -ln > index.txt

endif
