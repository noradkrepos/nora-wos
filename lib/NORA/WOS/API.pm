package NORA::WOS::API;

use strict;
use warnings;
use NORA::WOS;
use LWP::UserAgent;
use HTTP::Request;
use IO::Socket::SSL qw(SSL_VERIFY_NONE);
use JSON::XS;

sub new
{
    my ($class, $verbose) = @_;

    my $self = {verbose => $verbose};
    $self->{'wos'} = new NORA::WOS ();
    $self->{'jxs'} = JSON::XS->new->allow_nonref->canonical(1);
    if (open (my $fin, '/etc/nora-wos/wos.tab')) {
        while (<$fin>) {
            chomp;
            my ($key, $val) = split (' ', $_, 2);
            $self->{'conf'}{$key} = $val;
        }
        close ($fin);
    } else {
        die ("fatal: failed to open /etc/nora-wos/wos.tab for reading: $!\n");
    }
    $self->{'normalize'} = [
        'dynamic_data/cluster_related/identifiers/identifier',
        'static_data/contributors/contributor',
        'static_data/fullrecord_metadata/abstracts/abstract/abstract_text/p',
        'static_data/fullrecord_metadata/addresses/address_name',
        'static_data/fullrecord_metadata/addresses/address_name[]/address_spec/organizations/organization',
        'static_data/fullrecord_metadata/addresses/address_name[]/address_spec/suborganizations/suborganization',
        'static_data/fullrecord_metadata/addresses/address_name[]/address_spec/zip',
        'static_data/fullrecord_metadata/addresses/address_name[]/names/name',
        'static_data/fullrecord_metadata/addresses/address_name[]/names/name[]/data-item-ids/data-item-id',
        'static_data/fullrecord_metadata/category_info/subjects/subject',
        'static_data/fullrecord_metadata/category_info/headings/headings',
        'static_data/fullrecord_metadata/category_info/subheadings/subheading',
        'static_data/fullrecord_metadata/fund_ack/fund_text/p',
        'static_data/fullrecord_metadata/fund_ack/grants/grant',
        'static_data/fullrecord_metadata/fund_ack/grants/grant[]/grant_ids/grant_id',
        'static_data/fullrecord_metadata/keywords/keyword',
        'static_data/fullrecord_metadata/languages/language',
        'static_data/fullrecord_metadata/normalized_doctypes/doctype',
        'static_data/fullrecord_metadata/reprint_addresses/address_name',
        'static_data/fullrecord_metadata/reprint_addresses/address_name[]/address_spec/organizations/organization',
        'static_data/fullrecord_metadata/reprint_addresses/address_name[]/address_spec/suborganizations/suborganization',
        'static_data/fullrecord_metadata/reprint_addresses/address_name[]/address_spec/zip',
        'static_data/fullrecord_metadata/reprint_addresses/address_name[]/names/name',
        'static_data/item/book_desc',
        'static_data/item/book_notes/book_note',
        'static_data/item/keywords_plus/keyword',
        'static_data/summary/EWUID/edition',
        'static_data/summary/conferences/conference',
        'static_data/summary/conferences/conference[]/sponsors/sponsor',
        'static_data/summary/doctypes/doctype',
        'static_data/summary/names/name',
        'static_data/summary/names/name[]/data-item-ids/data-item-id',
        'static_data/summary/titles/title',
    ];
    return (bless ($self, $class));
}

sub add_core
{
    my ($self, $rec, $rc) = @_;

    foreach my $ti (@{$rec->{'static_data'}{'summary'}{'titles'}{'title'}}) {
        if ($ti->{'type'} eq 'item') {
            $rc->{'title'} = $ti->{'content'};
            next;
        }
        if ($ti->{'type'} eq 'source') {
            $rc->{'source'} = $ti->{'content'};
            next;
        }
    }
    if (!$rc->{'title'}) {
        $self->{'wos'}->log ('w', '%s: could not find title', $rc->{'ut'});
    }
    if (!$rc->{'source'}) {
        $self->{'wos'}->log ('w', '%s: could not find source', $rc->{'ut'});
    }
    if ($rec->{'static_data'}{'summary'}{'doctypes'}{'count'} == 1) {
        $rc->{'doctype'} = $rec->{'static_data'}{'summary'}{'doctypes'}{'doctype'};
    } else {
        $rc->{'doctype'} = join ('; ', sort (@{$rec->{'static_data'}{'summary'}{'doctypes'}{'doctype'}}));
    }
    if (exists ($rec->{'dynamic_data'}{'citation_related'}{'tc_list'}{'silo_tc'}{'local_count'})) {
        $rc->{'cited'} = $rec->{'dynamic_data'}{'citation_related'}{'tc_list'}{'silo_tc'}{'local_count'};
    } else {
        $self->{'wos'}->log ('w', '%s: missing citations', $rc->{'ut'});
    }
    if (exists ($rec->{'static_data'}{'fullrecord_metadata'}{'refs'}{'count'})) {
        $rc->{'refs'} = $rec->{'static_data'}{'fullrecord_metadata'}{'refs'}{'count'};
    } else {
        $self->{'wos'}->log ('w', '%s: missing refs', $rc->{'ut'});
    }
    if ($rec->{'static_data'}{'summary'}{'pub_info'}{'pubyear'}) {
        $rc->{'year'} = $rec->{'static_data'}{'summary'}{'pub_info'}{'pubyear'};
        $rc->{'pubdate'} = $rec->{'static_data'}{'summary'}{'pub_info'}{'sortdate'};
        $rc->{'volume'} = $rec->{'static_data'}{'summary'}{'pub_info'}{'vol'};
        $rc->{'issue'} = $rec->{'static_data'}{'summary'}{'pub_info'}{'issue'};
    } else {
        $self->{'wos'}->log ('w', '%s: missing pubyear', $rc->{'ut'});
    }
    if (ref ($rec->{'dynamic_data'}{'cluster_related'}{'identifiers'}) eq 'HASH') {
        if (ref ($rec->{'dynamic_data'}{'cluster_related'}{'identifiers'}{'identifier'}) eq 'ARRAY') {
            foreach my $id (@{$rec->{'dynamic_data'}{'cluster_related'}{'identifiers'}{'identifier'}}) {
                if ($id->{'type'} eq 'doi') {
                    $rc->{'doi'} = $id->{'value'};
                }
            }
        } else {
            my $id = $rec->{'dynamic_data'}{'cluster_related'}{'identifiers'}{'identifier'};
            if ($id->{'type'} eq 'doi') {
                $rc->{'doi'} = $id->{'value'};
            }
        }
    }
    my @names = ();
    if ($rec->{'static_data'}{'summary'}{'names'}{'count'} == 1) {
        push (@names, $rec->{'static_data'}{'summary'}{'names'}{'name'});
    } elsif ($rec->{'static_data'}{'summary'}{'names'}{'count'} > 1) {
        @names = @{$rec->{'static_data'}{'summary'}{'names'}{'name'}};
    }
    my $n = 0;
    my @au = ();
    foreach my $name (@names) {
        if ($n == 6) {
            push (@au, '[et al.]');
            last;
        }
        if ($name->{'role'} eq 'author') {
            push (@au, $name->{'wos_standard'});
            $n++;
        }
    }
    $rc->{'authors'} = join ('; ', @au);
}

sub doctype_code
{
    my ($self, $doctype) = @_;

    if (!exists ($self->{'doctype-map'})) {
        $self->{'doctype-map'} = {
            'abstract'                 => 'abstract',
            'article'                  => 'article',
            'bibliography'             => 'other',
            'biographical item'        => 'other',
            'book chapter'             => '',
            'book review'              => 'other',
            'book'                     => 'other',
            'correction'               => 'correction',
            'correction addition'      => 'correction',
            'data paper'               => 'other',
            'discussion'               => 'other',
            'early access'             => '',
            'editorial material'       => 'other',
            'item about an individual' => 'other',
            'letter'                   => 'other',
            'meeting abstract'         => 'abstract',
            'news item'                => 'other',
            'note'                     => 'other',
            'other'                    => 'other',
            'proceedings paper'        => 'proceedings paper',
            'reprint'                  => 'other',
            'retracted publication'    => 'only-other',
            'retraction'               => 'other',
            'review'                   => 'review',
            'software review'          => 'other',
        };
        $self->{'doctype-code'} = {
            'article'           =>  1,
            'proceedings paper' =>  2,
            'abstract'          =>  4,
            'review'            =>  8,
            'correction'        => 16,
            'other'             => 32,
        };
    }
    my $code = 0;
    if ($doctype eq 'all') {
        foreach my $dt (keys (%{$self->{'doctype-code'}})) {
            $code += $self->{'doctype-code'}{$dt};
        }
        return ($code);
    }
    foreach my $type (split (';', lc ($doctype))) {
        $type =~ s/[^a-z]+/ /g;
        $type =~ s/^\s//;
        $type =~ s/\s$//;
        if (exists ($self->{'doctype-map'}{$type})) {
            $type = $self->{'doctype-map'}{$type};
            if ($type eq '') {
                next;
            }
            if ($type =~ s/^only-//) {
                if (exists ($self->{'doctype-code'}{$type})) {
                    $code = $self->{'doctype-code'}{$type};
                    last;
                } else {
                    $self->{'wos'}->log ('e', "undefined document type code: '%s'", $type);
                }
            } else {
                if (exists ($self->{'doctype-code'}{$type})) {
                    $code = $code | $self->{'doctype-code'}{$type};
                } else {
                    $self->{'wos'}->log ('e', "undefined document type code: '%s'", $type);
                }
            }
        } else {
            $self->{'wos'}->log ('w', "undefined document type: '%s'", $type);
        }
    }
    return ($code);
}

sub url_incites
{
    my ($self, $type, $schema, @args) = @_;

    my $base = 'https://incites-api.clarivate.com/api/incites';
    if ($type =~ m/doclevel/i) {
        if ((!$schema) || ($schema eq 'wos')) {
            return ($base . '/DocumentLevelMetricsByUT/json?ver=2&schema=wos&esci=y&UT=' . join (',', @args));
        } elsif ($schema eq 'ct') {
            return ($base . '/DocumentLevelMetricsByUT/json?ver=2&schema=ct&esci=y&UT=' . join (',', @args));
        } else {
            $self->{'wos'}->log ('f', 'url_incites: unknown InCites request schema: "%s"', $schema);
            die ();
        }
    }
    if ($type =~ m/update/i) {
        return ($base . '/InCitesLastUpdated/json');
    }
    $self->{'wos'}->log ('f', 'url_incites: unknown InCites request type: "%s"', $type);
    die ();
}

sub api_call
{
    my ($self, $url) = @_;

    my $rs = $self->http_get ($url);
    my $n = 1;
    while (($rs->code == 503) || ($rs->code == 404)) {
        printf (STDERR "error: Service Temporarily Unavailable - sleeping %d seconds\n", (60 * $n));
        sleep (60 * $n);
        $n++;
        $rs = $self->http_get ($url);
    }
    if ($rs->is_success) {
        my $s = $rs->header ('Client-Aborted');
        if ((defined ($s)) && ($s !~ m/^\s*$/)) {
            if ($s eq 'die') {
                printf (STDERR "error: Client-Aborted while harvesting '%s': %s\n", $url, $s);
                return ($self->json_error ('500', "Client-Aborted while harvesting '%s': %s", $url, $s));
            } else {
                printf (STDERR "error: unknown Client-Aborted header while harvesting '%s': %s\n", $url, $s);
                return ($self->json_error ('500', "unknown Client-Aborted header while harvesting '%s': %s", $url, $s));
            }
        }
        $s = $rs->header ('X-Died');
        if ((defined ($s)) && ($s !~ m/^\s*$/)) {
            $s =~ s/ at \/.*//;
            if ($s =~ m/eof when chunk header expected/i) {
                printf (STDERR "error: connection lost '%s'\n", $url);
                return ($self->json_error ('408', "connection lost '%s'", $url));
            } elsif ($s =~ m/read timeout/i) {
                printf (STDERR "error: connection timeout '%s'\n", $url);
                return ($self->json_error ('408', "connection timeout '%s'", $url));
            } else {
                printf (STDERR "error: unknown X-Died header while harvesting '%s': %s", $url, $s);
                return ($self->json_error ('408', "unknown X-Died header while harvesting '%s': %s", $url, $s));
            }
        }
    } else {
        printf (STDERR "error: HTTP error: %d : %s\n", $rs->code, $rs->message);
        return ($self->json_error ($rs->code, $rs->message));
    }
    return ($rs->content);
}

sub http_get
{
    my ($self, $url, $redirect) = @_;

    my $time = time;
    if (exists ($self->{'limit'}{$time})) {
        if ($self->{'limit'}{$time} < 3) {
            $self->{'limit'}{$time}++;
        } else {
            $self->{'wos'}->log ('i', 'sleeping 1 sec. to avoid limit');
            sleep (1);
            $time = time;
            $self->{'limit'} = {$time => 1};
        }
    } else {
        $self->{'limit'} = {$time => 1};
    }
    my ($sec) = localtime (time);
    my $ua;
    if (exists ($self->{'ua'})) {
        $ua = $self->{'ua'};
    } else {
        $ua = new LWP::UserAgent;
        $ua->agent ('RAP-ADH/0.2');
        $ua->timeout (180);
        $ua->ssl_opts (SSL_verify_mode => SSL_VERIFY_NONE, verify_hostnames => 0);
        $self->{'ua'} = $ua;
    }
    if (!defined ($redirect)) {
        $redirect = 0;
    }
    my $authkey;
    if ($url =~ m|/incites/|) {
        $authkey = $self->{'conf'}{'incites-key'};
    } else {
        $authkey = $self->{'conf'}{'wos-key'};
    }
    my $re = new HTTP::Request ('GET' => $url);
    $re->header ('Accept' => 'application/json');
    $re->header ('X-ApiKey' => $authkey);
    my $rs = $ua->request ($re);
    my $code = $rs->code;
    if (($code == 301) || ($code == 302)) {
        my $location = $rs->header ('Location');
        if ($location) {
            if ($redirect < 6) {
                if ($location eq $url) {
                    printf (STDERR "fatal: ignore redirect to same location: '%s'\n", $location);
                    exit (1);
                } else {
                    printf (STDERR "i redirect from '%s' to '%s'\n", $url, $location);
                    return ($self->http_get ($location, $redirect + 1));
                }
            } else {
                printf (STDERR "fatal: exceeded number of redirect: %d\n", $redirect);
                exit (1);
            }
        }
    }
    return ($rs);
}

sub normalize_record
{
    my ($self, $rec, $id, $path) = @_;

    if (($path) && ($self->{'verbose'})) {
        printf (STDERR "%s: path: %s, json: %s\n\n", $id, $path, $self->{'jxs'}->encode ($rec));
    }
    if ($path) {
        my $rc = $rec;
        my @pa = split ('/', $path);
        my $pa;
        while ($pa = shift (@pa)) {
            if ($pa =~ s/\[\]$//) {
                if (!exists ($rc->{$pa})) {
                    return ();
                }
                if (ref ($rc->{$pa}) eq 'ARRAY') {
                    foreach my $r (@{$rc->{$pa}}) {
                        $self->normalize_record ($r, $id, join ('/', @pa));
                    }
                } else {
                    die ("normalize error: $id path not array: $pa\n");
                }
            } else {
                if (ref ($rc) ne 'HASH') {
                    printf (STDERR "id: %s, path: %s, ref: %s, json: %s\n", $id, $pa, ref ($rc), $self->{'jxs'}->encode ($rc));
                }
                if (!exists ($rc->{$pa})) {
                    return ();
                }
                if (@pa) {
                    if (ref ($rc->{$pa}) ne 'HASH') {
                        printf (STDERR "fixing non-hash - id: %s, path: %s, ref: %s, json: %s\n", $id, $pa, ref ($rc), $self->{'jxs'}->encode ($rc));
                        $rc->{$pa} = {};
                        return ();
                    }
                    $rc = $rc->{$pa};
                } else {
                    if (ref ($rc->{$pa}) ne 'ARRAY') {
                        $rc->{$pa} = [$rc->{$pa}];
                    }
                }
            }
        }
    } else {
        foreach my $path (@{$self->{'normalize'}}) {
            $self->normalize_record ($rec, $rec->{'UID'}, $path);
        }
    }
}

sub wos_array
{
    my ($self, $rec, $path) = @_;

    my $ut = $rec->{'UID'};
    my @path = split ('/', $path);
    my $fld = pop (@path);
    foreach my $f (@path) {
        if (!exists ($rec->{$f})) {
            return ();
        }
        if (ref ($rec->{$f}) eq 'HASH') {
            $rec = $rec->{$f};
        } else {
            $self->{'wos'}->log ('e', '%s: error with element %s in path %s', $ut, $f, $path);
            return ();
        }
    }
    if (ref ($rec->{$fld}) eq 'ARRAY') {
        return (@{$rec->{$fld}});
    } else {
        if (defined ($rec->{$fld})) {
            return ($rec->{$fld});
        } else {
            return ();
        }
    }
}

sub url_encode
{
    my ($self, $txt) = @_;

    $txt =~ s/([^-_\.\!\~\*\'\(\)\s0-9A-Za-z])/sprintf ('%%%02X', ord ($1))/geo;
    $txt =~ s/\s/+/g;
    return ($txt);
}

sub json_error
{
    my ($self, $code, $msg, @args) = @_;

    if (@args) {
        $msg = sprintf ($msg, @args);
    }
    my $rec = {http_error => {code => $code, message => $msg}};
    return ($self->{'jxs'}->encode ($rec));
}

1;

