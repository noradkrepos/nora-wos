package NORA::WOS::API;

use strict;
use warnings;
use NORA::WOS;
use LWP::UserAgent;
use HTTP::Request;
use IO::Socket::SSL qw(SSL_VERIFY_NONE);

sub new
{
    my ($class) = @_;

    my $self = {};
    $self->{'wos'} = new NORA::WOS ();
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
    my ($self, $type, @args) = @_;

    my $base = 'https://api.clarivate.com/api/incites';
    if ($type =~ m/doclevel/i) {
        return ($base . '/DocumentLevelMetricsByUT/json?esci=y&ver=2&UT=' . join (',', @args));
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
                printf (STDERR "fatal: Client-Aborted while harvesting '%s': %s\n", $url, $s);
            } else {
                printf (STDERR "fatal: unknown Client-Aborted header while harvesting '%s': %s\n", $url, $s);
            }
            exit (1);
        }
        $s = $rs->header ('X-Died');
        if ((defined ($s)) && ($s !~ m/^\s*$/)) {
            $s =~ s/ at \/.*//;
            if ($s =~ m/eof when chunk header expected/i) {
                printf (STDERR "fatal: connection lost '%s'\n", $url);
            } elsif ($s =~ m/read timeout/i) {
                printf (STDERR "fatal: connection timeout '%s'\n", $url);
            } else {
                printf (STDERR "fatal: unknown X-Died header while harvesting '%s': %s", $url, $s);
            }
            exit (1);
        }
    } else {
        printf (STDERR "fatal: HTTP error: %d : %s\n", $rs->code, $rs->message);
        exit (1);
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

1;

