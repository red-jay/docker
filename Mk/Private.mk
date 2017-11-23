ifeq ($(p_tmpdir),)

location = $(CURDIR)/$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
self := $(location)

%:
	@tmpdir=`mktemp -d`; \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	$(MAKE) -f $(self) --no-print-directory p_tmpdir=$$tmpdir $@
else

SYSTEM=$(basename $(notdir $(MAKECMDGOALS)))

private-isos/tgw.%.iso: private/openvpn/$(SYSTEM).key
	cp private/openvpn/$(SYSTEM).key $(p_tmpdir)/openvpn.key
	mkisofs -quiet -o $@ -rational-rock -J -V cidata -hide-joliet-trans-tbl -hide-rr-moved $(p_tmpdir)

endif
