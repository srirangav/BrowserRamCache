# Makefile - Makefile for ramcache
# $Id: Makefile 1314 2013-04-24 20:38:57Z ranga $

PGM_NAME = ramcache
PGM_REL  = 0.1.3
WORKDIR  = work
FILES    = ramcache.pl \
           org.calalum.ranga.ramcache.plist.in \
           Makefile

all:
	@echo Nothing to do

tgz:
	/bin/rm -rf $(WORKDIR)
	mkdir -p $(WORKDIR)/$(PGM_NAME)-$(PGM_REL)
	cp $(FILES) $(WORKDIR)/$(PGM_NAME)-$(PGM_REL)
	cd $(WORKDIR) && \
        tar -cvf ../$(PGM_NAME)-$(PGM_REL).tar $(PGM_NAME)-$(PGM_REL)
	gzip $(PGM_NAME)-$(PGM_REL).tar
	mv $(PGM_NAME)-$(PGM_REL).tar.gz $(PGM_NAME)-$(PGM_REL).tgz

install:
	sed -e "s@##HOME##@$$HOME@" < \
            org.calalum.ranga.ramcache.plist.in > \
            org.calalum.ranga.ramcache.plist
	mkdir -p "$$HOME/Applications/" \
              "$$HOME/Library/LaunchAgents/"
	cp ramcache.pl "$$HOME/Applications/"
	chmod u+x "$$HOME/Applications/ramcache.pl"
	cp org.calalum.ranga.ramcache.plist \
           "$$HOME/Library/LaunchAgents/"

clean:
	/bin/rm -rf *~ .*~ .DS_Store $(WORKDIR) $(PGM_NAME)*.tgz \
                org.calalum.ranga.ramcache.plist
