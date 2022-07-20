DESTDIR=/usr/local
PACKAGE_NAME=aio
VER=1.0
TCLSH=tclsh

all: tm/$(PACKAGE_NAME)-$(VER).tm README.md doc/$(PACKAGE_NAME).n

tm/$(PACKAGE_NAME)-$(VER).tm: aio.tcl
	mkdir -p tm
	cp aio.tcl tm/$(PACKAGE_NAME)-$(VER).tm

install: tm/$(PACKAGE_NAME)-$(VER).tm
	mkdir -p $(DESTDIR)/lib/tcl8/site-tcl
	cp $< $(DESTDIR)/lib/tcl8/site-tcl/

clean:
	rm -r tm

README.md: doc/$(PACKAGE_NAME).md
	pandoc --standalone --from markdown --to gfm doc/$(PACKAGE_NAME).md --output README.md

doc/$(PACKAGE_NAME).n: doc/$(PACKAGE_NAME).md
	pandoc --standalone --from markdown --to man doc/$(PACKAGE_NAME).md --output doc/$(PACKAGE_NAME).n

test: tm/$(PACKAGE_NAME)-$(VER).tm
	#$(TCLSH) tests/all.tcl $(TESTFLAGS) -load "package ifneeded $(PACKAGE_NAME) $(VER) [list apply {{} {uplevel #0 {source [file join $::tcltest::testsDirectory .. tm/$(PACKAGE_NAME)-$(VER).tm]; package provide $(PACKAGE_NAME) $(VER)}}}]"
	$(TCLSH) tests/all.tcl $(TESTFLAGS) -load "source [file join $$::tcltest::testsDirectory .. tm $(PACKAGE_NAME)-$(VER).tm]; package provide $(PACKAGE_NAME) $(VER)"

.PHONY: all clean install test