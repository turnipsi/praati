prefix = /usr/local

.PHONY: all
all:

.PHONY: installdirs
installdirs:
	mkdir -p $(DESTDIR)$(prefix)/bin
	mkdir -p $(DESTDIR)$(prefix)/libdata/perl5/site_perl
	mkdir -p $(DESTDIR)$(prefix)/libdata/perl5/site_perl/Praati
	mkdir -p $(DESTDIR)$(prefix)/libdata/perl5/site_perl/Praati/View

.PHONY: install
install: installdirs
	install -m 555 praati $(DESTDIR)$(prefix)/bin
	install -m 444 Praati.pm $(DESTDIR)$(prefix)/libdata/perl5/site_perl
	install -m 444 Praati/Controller.pm Praati/Model.pm Praati/View.pm \
	    $(DESTDIR)$(prefix)/libdata/perl5/site_perl/Praati
	install -m 444 Praati/View/L10N.pm \
	    $(DESTDIR)$(prefix)/libdata/perl5/site_perl/Praati/View

.PHONY: clean
clean:
