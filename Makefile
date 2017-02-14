kscheck: ks.cfg
	ksvalidator ks.cfg -v RHEL7

Packages:
	mkdir Packages

# thie _guarantees_ we can resolve the base group data, even if not mirrored.
Packages/repodata/repomd.xml: Packages centos-comps/c7-x86_64-comps.xml
	cd Packages && createrepo_c -g ../centos-comps/c7-x86_64-comps.xml .

Packages/repodata/installed-groups.txt: ks.cfg ks-dumpgroups.py
	./ks-dumpgroups.py > Packages/repodata/installed-groups.txt

Packages/repodata/.unwound-groups: Packages/repodata/installed-groups.txt Packages/repodata/repomd.xml unwind-groups.sh
	./unwind-groups.sh Packages/repodata/installed-groups.txt
	touch Packages/repodata/.unwound-groups

Packages/.downloaded: Packages/repodata/base-group.txt Packages/repodata/core-group.txt ks.cfg
	repotrack -a x86_64 -p ./Packages $$(cat Packages/repodata/group-*.txt)
	$(MAKE) Packages/repodata/repomd.xml
	touch Packages/.downloaded
