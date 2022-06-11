package NORA::WOS::DOI;

use strict;
use warnings;
use NORA::WOS;
use NORA::WOS::DB;
use LWP::UserAgent;
use HTTP::Request;
use IO::Socket::SSL qw(SSL_VERIFY_NONE);

sub new
{
    my ($class) = @_;
    my $self = {baseurl => 'https://api.operanora.qa.dataverz.com/search/'};
    $self->{'baseurl'} = 'https://65.21.141.182/search/';
    $self->{'wos'} = new NORA::WOS ();
    $self->{'db'} = new NORA::WOS::DB ();
    $self->{'db'}->create ();

    return (bless ($self, $class));
}

sub normalize
{
    my ($self, $doi) = @_;

    if (!$doi) {
        return ();
    }
    $doi =~ s/[\s\t\r\n]//g;
    $doi =~ s/^.*?10\./10./;
    $doi =~ s/[\.,]+$//;
    if ($doi =~ m/^10\./) {
        return (lc ($doi));
    }
    return ();
}

sub harvest
{
    my ($self, $doi) = @_;

    my $url = $self->{'baseurl'} . '?id=' . $doi;
    my $rs = $self->http_request ($url);
    if ($rs->code != 200) {
        $self->{'wos'}->log ('e', 'DOI service error "%s", %s - %s', $url, $rs->code, $rs->message);
        $self->{'wos'}->log ('e', 'DOI service error "%s", %s', $url, $rs->status_line());
        return (undef);
    } else {
        return ($rs->content);
    }
}

sub harvest_batch
{
    my ($self) = @_;

    if (!exists ($self->{'skip'})) {
        $self->{'skip'} = 0;
    }
    my $url = $self->{'baseurl'} . '?limit=1000&skip=' . $self->{'skip'};
    $self->{'skip'} += 1000;
    my $rs = $self->http_request ($url);
    if ($rs->code != 200) {
        $self->{'wos'}->log ('e', 'DOI service error "%s", %s - %s', $url, $rs->code, $rs->message);
        return (undef);
    } else {
        return ($rs->content);
    }
}

sub http_request
{
    my ($self, $url) = @_;

    my $ua;
    if (exists ($self->{'ua'})) {
        $ua = $self->{'ua'};
    } else {
        $ua = new LWP::UserAgent;
        $ua->agent ('NORA-WOS-DOI/0.1');
        $ua->timeout (180);
        $ua->ssl_opts (verify_hostname => 0, SSL_verify_mode => 0x00);
        $self->{'ua'} = $ua;
    }
    my $re = new HTTP::Request (GET => $url);
    $re->header ('Accept' => 'application/json');
    my $rs = $ua->request ($re);
    return ($rs);
}

sub lookup
{
    my ($self, $doi) = @_;

    if (!($doi = $self->normalize ($doi))) {
        return ();
    }
    if (!exists ($self->{'lookup'})) {
        my $rs = $self->{'db'}->sql ('select doi,bfiLevel,bfiMra,bfiPubYear,bfiSubYear,oaiClass,oaiMra,oaiPubYear,oaiSubyear,dimID from doi');
        my $rc;
        while ($rc = $rs->fetchrow_hashref) {
            $self->{'lookup'}{$rc->{'doi'}} = $rc;
        }
    }
    return ($self->{'lookup'}{$doi});
}

1;

