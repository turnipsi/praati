prefix = /usr/local

.PHONY: all
all:

.PHONY: installdirs
installdirs:
	mkdir -p $(DESTDIR)$(prefix)/bin
	mkdir -p $(DESTDIR)$(prefix)/libdata/perl5/site_perl/Praati/View

.PHONY: install
install: installdirs
	install -m 555 praati $(DESTDIR)$(prefix)/bin
	install -m 444 Praati.pm $(DESTDIR)$(prefix)/libdata/perl5/site_perl
	install -m 444 Praati/View/L10N.pm \
	    $(DESTDIR)$(prefix)/libdata/perl5/site_perl/Praati/View

.PHONY: clean
clean:
