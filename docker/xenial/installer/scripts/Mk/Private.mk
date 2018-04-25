ifeq ($(p_tmpdir),)

location = $(CURDIR)/$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
self := $(location)

%:
	@tmpdir=`mktemp -d`; \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	$(MAKE) -f $(self) --no-print-directory p_tmpdir=$$tmpdir $@
else

SYSTEM=$(basename $(notdir $(MAKECMDGOALS)))

private-isos/tgw.%.iso:
ifneq ("$(wildcard private/openvpn/$(SYSTEM).key)","")
	cp private/openvpn/$(SYSTEM).key $(p_tmpdir)/openvpn.key
endif
ifneq ("$(wildcard private/openvpn/$(SYSTEM)-client.key)","")
	cp private/openvpn/$(SYSTEM)-client.key $(p_tmpdir)/openvpn-client.key
endif
	cp private/openvpn/TA.key $(p_tmpdir)/openvpn-TA.key
	mkisofs -quiet -o $@ -rational-rock -J -V cidata -hide-joliet-trans-tbl -hide-rr-moved $(p_tmpdir)
endif
