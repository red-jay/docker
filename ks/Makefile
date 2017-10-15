KSFILES=$(wildcard *.ks)
VALIDATE=$(subst .ks,.val,$(KSFILES))
GROUPFILES=$(subst .ks,.groups,$(KSFILES))
PACKAGEFILES=$(subst .ks,.packages,$(KSFILES))

%.val: %.ks
	ksvalidator $< -v RHEL7

%.groups: %.ks
	$(DUMPGROUP) $< > $@

%.packages: %.ks
	$(DUMPPKGS) $< > $@

ksvalidate: $(VALIDATE)

installed-groups.txt: $(GROUPFILES)
	cat $(GROUPFILES) | sort | uniq > installed-groups.txt

installed-packages.txt: $(PACKAGEFILES)
	cat $(PACKAGEFILES) | sort | uniq > installed-packages.txt

clean:
	-rm *.groups *.packages *.txt
