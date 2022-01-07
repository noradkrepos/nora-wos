package NORA::WOS::N3;

use strict;
use warnings;

our $VERSION = '0.01';

sub new
{
    my ($class) = @_;

    my $self = {};
    $self->{'prefix'} = {
        'bibo'         => 'http://purl.org/ontology/bibo/',
        'c4o'          => 'http://purl.org/spar/c4o/',
        'cito'         => 'http://purl.org/spar/cito/',
        'dcterms'      => 'http://purl.org/dc/terms/',
        'event'        => 'http://purl.org/NET/c4dm/event.owl#',
        'fabio'        => 'http://purl.org/spar/fabio/',
        'foaf'         => 'http://xmlns.com/foaf/0.1/',
        'geo'          => 'http://aims.fao.org/aos/geopolitical.owl#',
        'norao'        => 'https://www.nora.dtu.dk/ontology/nora/',
        'obo'          => 'http://purl.obolibrary.org/obo/',
        'ocrer'        => 'http://purl.org/net/OCRe/research.owl#',
        'ocresd'       => 'http://purl.org/net/OCRe/study_design.owl#',
        'ocresp'       => 'http://purl.org/net/OCRe/study_protocol.owl#',
        'ocresst'      => 'http://purl.org/net/OCRe/statistics.owl#',
        'osrap'        => 'http://vivo.deffopera.dk/ontology/osrap/',
        'owl'          => 'http://www.w3.org/2002/07/owl#',
        'rdf'          => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#',
        'rdfs'         => 'http://www.w3.org/2000/01/rdf-schema#',
        'ro'           => 'http://purl.obolibrary.org/obo/ro.owl#',
        'scires'       => 'http://vivoweb.org/ontology/scientific-research#',
        'skos'         => 'http://www.w3.org/2004/02/skos/core#',
        'swo'          => 'http://www.ebi.ac.uk/efo/swo/',
        'swrl'         => 'http://www.w3.org/2003/11/swrl#',
        'swrlb'        => 'http://www.w3.org/2003/11/swrlb#',
        'vann'         => 'http://purl.org/vocab/vann/',
        'vcard'        => 'http://www.w3.org/2006/vcard/ns#',
        'vitro'        => 'http://vitro.mannlib.cornell.edu/ns/vitro/0.7#',
        'vitro-public' => 'http://vitro.mannlib.cornell.edu/ns/vitro/public#',
        'vivo'         => 'http://vivoweb.org/ontology/core#',
        'wos'          => 'https://wos.nora.dtu.dk/individual/',
        'xsd'          => 'http://www.w3.org/2001/XMLSchema#',
    };
    $self->{'pused'} = {};
    $self->{'data'} = {};
    return (bless ($self, $class));
}

sub prefix
{
    my ($self, $code, $uri) = @_;

    if ($code !~ m/^[-0-9A-Za-z]+$/) {
        die ("fatal: invalid character in prefix code '$code', valid characters are: 0-9, A-Z, a-z and hyphen (-).\n");
    }
    $self->{'prefix'}{$code} = $uri;
}

sub add
{
    my ($self, $id, $code, @val) = @_;

    $id = $self->pused ('id', $id);
    $code = $self->pused ('code', $code);
    if (!exists ($self->{'data'}{$id})) {
        $self->{'data'}{$id} = {};
    }
    if (!exists ($self->{'data'}{$id}{$code})) {
        $self->{'data'}{$id}{$code} = [];
    }
    foreach my $val (@val) {
        $val = $self->pused ('value', $val);
        push (@{$self->{'data'}{$id}{$code}}, $val);
    }
}

sub add_text
{
    my ($self, $id, $code, @val) = @_;

    my @VAL = ();
    foreach my $val (@val) {
        if ((defined ($val)) && ($val !~ m/^[\s\t\r\n]*$/)) {
            push (@VAL, $val);
        }
    }
    if (!@VAL) {
        return;
    }
    $id = $self->pused ('id', $id);
    $code = $self->pused ('code', $code);
    if (!exists ($self->{'data'}{$id})) {
        $self->{'data'}{$id} = {};
    }
    if (!exists ($self->{'data'}{$id}{$code})) {
        $self->{'data'}{$id}{$code} = [];
    }
    foreach my $val (@VAL) {
        $val =~ s/"/\\"/g;
        push (@{$self->{'data'}{$id}{$code}}, '"' . $val . '"');
    }
}

sub pused
{
    my ($self, $type, $code) = @_;

    if ($code =~ m/^https?:/) {
        return ('<' . $code . '>');
    }
    if ($code =~ m/^([-0-9A-Za-z]+):/) {
        my $pf = $1;
        if (!exists ($self->{'prefix'}{$pf})) {
            die ("fatal: unknown prefix '$pf' in $type: $code");
        }
        $self->{'pused'}{$pf} = 1;
        return ($code);
    } else {
        if (($type ne 'code') || ($code ne 'a')) {
            die ("fatal: missing prefix in $type: $code");
        }
        return ($code);
    }
}

sub output
{
    my ($self, $fh) = @_;

    if (!defined ($fh)) {
        die ("fatal: output requires a filehandle\n");
    }
    my $len = 0;
    foreach my $key (sort (keys (%{$self->{'pused'}}))) {
        if (length ($key) > $len) {
            $len = length ($key);
        }
    }
    foreach my $key (sort (keys (%{$self->{'pused'}}))) {
        printf ($fh "\@prefix %-${len}s <%s> .\n", $key, $self->{'prefix'}{$key});
    }
    printf ($fh "\n");
    foreach my $id (sort (keys (%{$self->{'data'}}))) {
        printf ($fh "%s\n", $id);
        my @codes = sort (keys (%{$self->{'data'}{$id}}));
        my $code;
        while ($code = shift (@codes)) {
            my $pos = '.';
            if (@codes) {
                $pos = ';';
            }
            if (length ($code) > 30) {
                printf ($fh "    %s\n", $code);
                printf ($fh "    %-30s %s %s\n", '', join (',', @{$self->{'data'}{$id}{$code}}), $pos);
            } else {
                printf ($fh "    %-30s %s %s\n", $code, join (',', @{$self->{'data'}{$id}{$code}}), $pos);
            }
        }
    }
}

sub prefix_code
{
    my ($self, $uri) = @_;

    $uri =~ s/^[<\s]+//;
    $uri =~ s/[>\s]+$//;
    foreach my $pre (keys (%{$self->{'prefix'}})) {
        if ($self->{'prefix'}{$pre} eq $uri) {
            return ($pre);
        }
    }
    return (undef);
}

1;

