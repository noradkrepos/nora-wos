use 5.020002;
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME              => 'NORA::WOS',
    VERSION_FROM      => 'lib/NORA/WOS.pm',
    PREREQ_PM         => {},
    AUTHOR            => 'franck <fkybus@gmail.com>',
);

sub MY::postamble
{
    return <<'MAKE_FRAG';
debian: all
	@dpkg-buildpackage -rfakeroot -uc -us

install::
	@mkdir -p $(DESTDIR)/etc/nora-wos
	@mkdir -p $(DESTDIR)/var/log/nora-wos
	@mkdir -p $(DESTDIR)/var/lib/nora-wos/db
	@mkdir -p $(DESTDIR)/var/lib/nora-wos/cache
	@mkdir -p $(DESTDIR)/var/lib/nora-wos/data
	@mkdir -p $(DESTDIR)/var/lib/nora-wos/rdf
	@mkdir -p $(DESTDIR)/var/lib/nora-wos/staging
	@mkdir -p $(DESTDIR)/var/lib/nora-wos/vivo
	@mkdir -p $(DESTDIR)/var/run/nora-wos
	@install -D -m 775 bin/nora-wos $(DESTDIR)/usr/bin/nora-wos
	@for file in sbin/*; \
        do \
            install -D -m 775 $$file $(DESTDIR)/usr/$$file; \
        done
	@for file in etc/*; \
        do \
            ffile=`basename $$file`; \
            install -D -m 664 $$file $(DESTDIR)/etc/nora-wos/$$ffile; \
        done

distclean::
	rm -rf debian/nora-wos
	rm -f debian/files debian/nora-wos.substvars build-stamp install-stamp
MAKE_FRAG
}

