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
        'opera'        => 'http://vivo.deffopera.dk/ontology/osrap/',
        'orcid'        => 'https://orcid.org/',
        'cla'          => 'https://www.nora.dtu.dk/ontology/clarivate/',
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
    my ($self, $type, $id, $code, @val) = @_;

    $id = $self->pused ('id', $id);
    $code = $self->pused ('code', $code);
    if (!exists ($self->{'data'}{$type}{$id})) {
        $self->{'data'}{$type}{$id} = {};
    }
    if (!exists ($self->{'data'}{$type}{$id}{$code})) {
        $self->{'data'}{$type}{$id}{$code} = {};
    }
    foreach my $val (@val) {
        $val = $self->pused ('value', $val);
        $self->{'data'}{$type}{$id}{$code}{$val} = 1;

    }
}

sub add_text
{
    my ($self, $type, $id, $code, @val) = @_;

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
    if (!exists ($self->{'data'}{$type}{$id})) {
        $self->{'data'}{$type}{$id} = {};
    }
    if (!exists ($self->{'data'}{$type}{$id}{$code})) {
        $self->{'data'}{$type}{$id}{$code} = {};
    }
    foreach my $val (@VAL) {
        if ($val =~ m/^[0-9]+$/) {
            $self->{'data'}{$type}{$id}{$code}{$val} = 1;
        } else {
            $val =~ s/\\/\\\\/g;
            $val =~ s/"/\\"/g;
            $self->{'data'}{$type}{$id}{$code}{'"' . $val . '"'} = 1;
        }
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
        if ((($type ne 'code') || ($code ne 'a')) && ($code !~ m/^(true|false)$/)) {
            die ("fatal: missing prefix in $type: $code");
        }
        return ($code);
    }
}

sub output
{
    my ($self, $basefile) = @_;

    my $len = 0;
    foreach my $key (sort (keys (%{$self->{'pused'}}))) {
        if (length ($key) > $len) {
            $len = length ($key);
        }
    }
    $len++;
    my $prefix = '';
    foreach my $key (sort (keys (%{$self->{'pused'}}))) {
        $prefix .= sprintf ("\@prefix %-${len}s <%s> .\n", $key . ':', $self->{'prefix'}{$key});
    }
    $prefix .= "\n";
    my $fou;
    if ($basefile eq '-') {
        $fou = *STDOUT;
        binmode ($fou, ':utf8');
        print ($fou $prefix);
    }
    foreach my $type (sort (keys (%{$self->{'data'}}))) {
        my $fc = '01';
        my $lc = 60;
        if ($basefile ne '-') {
            if (!open ($fou, "> $basefile-$type-$fc.ttl")) {
                die ("fatal: failed to open '$basefile-$type-$fc.ttl' for output: $!");
            }
            binmode ($fou, ':utf8');
            print ($fou $prefix);
        }
        foreach my $id (sort (keys (%{$self->{'data'}{$type}}))) {
            printf ($fou "%s\n", $id);
            $lc++;
            my @codes = sort (keys (%{$self->{'data'}{$type}{$id}}));
            my $code;
            while ($code = shift (@codes)) {
                my $pos = '.';
                if (@codes) {
                    $pos = ';';
                }
                if (length ($code) > 30) {
                    printf ($fou "    %s\n", $code);
                    printf ($fou "    %-30s %s %s\n", '', join (' , ', sort (keys (%{$self->{'data'}{$type}{$id}{$code}}))), $pos);
                    $lc += 2;
                } else {
                    printf ($fou "    %-30s %s %s\n", $code, join (' , ', sort (keys (%{$self->{'data'}{$type}{$id}{$code}}))), $pos);
                    $lc++;
                }
            }
            if ($lc >= 10000000) {
                $fc = sprintf ('%02d', ($fc + 1));
                close ($fou);
                if (!open ($fou, "> $basefile-$type-$fc.ttl")) {
                     die ("fatal: failed to open '$basefile-$type-$fc.ttl' for output: $!");
                }
                binmode ($fou, ':utf8');
                print ($fou $prefix);
                $lc = 60;
            }
        }
        if ($basefile ne '-') {
            close ($fou);
        }
    }
}

sub output_nt
{
    my ($self, $basefile) = @_;

    my $fou;
    if ($basefile eq '-') {
        $fou = *STDOUT;
        binmode ($fou, ':utf8');
    }
    foreach my $type (sort (keys (%{$self->{'data'}}))) {
        if ($basefile ne '-') {
            if (!open ($fou, "> $basefile-$type.nt")) {
                die ("fatal: failed to open '$basefile-$type.nt' for output: $!");
            }
            binmode ($fou, ':utf8');
        }
        foreach my $id (sort (keys (%{$self->{'data'}{$type}}))) {
            my $nt1 = $self->output_nt_value ($id);
            foreach my $code (sort (keys (%{$self->{'data'}{$type}{$id}}))) {
                my $nt2 = $self->output_nt_value ($code);
                foreach my $val (sort (keys (%{$self->{'data'}{$type}{$id}{$code}}))) {
                    print ($fou join (' ', $nt1, $nt2, $self->output_nt_value ($val)), " .\n");
                }
            }
        }
        if ($basefile ne '-') {
            close ($fou);
        }
    }
}

sub output_nt_value
{
    my ($self, $val) = @_;

    if ($val =~ s/^([a-z]+)://) {
        if ($self->{'prefix'}{$1}) {
            return ('<' . $self->{'prefix'}{$1} . $val . '>');
        } else {
            die ("fatal: unknown prefix '$1' in: $1:$val\n");
        }
    }
    if ($val =~ m/^[<"]/) {
        return ($val);
    }
    if ($val eq 'a') {
        return ('<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>');
    }
    if ($val =~ m/^[0-9]+$/) {
        return ('"' . $val . '"^^<http://www.w3.org/2001/XMLSchema#integer>');
    }
    if ($val =~ m/^(true|false)$/) {
        return ('"' . $val . '"^^<http://www.w3.org/2001/XMLSchema#boolean>');
    }
    die ("fatal: unexpected value: $val\n");
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

