KSFILES=$(wildcard *.ks)
VALIDATE=$(subst .ks,.val,$(KSFILES))

%.val: %.ks
	ksvalidator $< -v RHEL7

ksvalidate: $(VALIDATE)
