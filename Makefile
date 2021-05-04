VER=0.1
TCLSH=tclsh
DESTDIR=/usr/local

all: tm docs

tm/tty-$(VER).tm: tty.tcl
	mkdir -p tm
	cp tty.tcl tm/tty-$(VER).tm

doc/tty.n: doc/tty.md
	pandoc --standalone --from markdown --to man doc/tty.md --output doc/tty.n

README.md: doc/tty.md
	pandoc --standalone --from markdown --to gfm doc/tty.md --output README.md

install-tm: tm
	mkdir -p "$(DESTDIR)/lib/tcl8/site-tcl/"
	cp tm/tty-$(VER).tm "$(DESTDIR)/lib/tcl8/site-tcl/"

tm: tm/tty-$(VER).tm

test: all
	$(TCLSH) tests/all.tcl $(VER) $(TESTFLAGS)

install: install-tm install-doc

docs: doc/tty.n README.md

install-doc: docs
	mkdir -p "$(DESTDIR)/man/mann"
	cp doc/tty.n "$(DESTDIR)/man/mann/"

clean:
	-rm -r tm doc/tty.n

.PHONY: all test tm install docs install-tm install-doc clean
