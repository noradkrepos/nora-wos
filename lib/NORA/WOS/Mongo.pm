package NORA::WOS::Mongo;

use strict;
use warnings;
use NORA::WOS;
use JSON::XS;
use MongoDB::MongoClient;
use MongoDB::Database;
use MongoDB::Collection;


sub new
{
    my ($class, $dbfile) = @_;
    my $self = {};

    $self->{'wos'} = new NORA::WOS ();
    my $mongo = new MongoDB::MongoClient (
                        host               => $self->{'wos'}->conf ('mongo-server'),
                        auth_mechanism     => 'DEFAULT',
                        username           => $self->{'wos'}->conf ('mongo-user'),
                        password           => $self->{'wos'}->conf ('mongo-pass'),
                        db_name            => $self->{'wos'}->conf ('mongo-db'),
                        connect_timeout_ms => 120000,
                        socket_timeout_ms  => 120000,
                    );
    $self->{'db'} = $mongo->get_database ('nora-wos');
    return (bless ($self, $class));
}

sub count
{
    my ($self, $col) = @_;

    return ($self->{'db'}->get_collection ($col)->count_documents ({}));
}

sub sql
{
    my ($self, $sql, @args) = @_;

#   print ("debug: SQL: $sql\n");
    my $sth = $self->prepare ($sql);
    $self->execute ($sth, @args);
    return ($sth);
}

sub find
{
    my ($self, $col, $req) = @_;

    if ($req) {
        return ($self->{'db'}->get_collection ($col)->find ($req));
    } else {
        return ($self->{'db'}->get_collection ($col)->find ());
    }
}

sub ct_micro
{
    my ($self, $ut) = @_;

    if (!exists ($self->{'ct_micro'})) {
        my $oamap = {
            'free to read'    => 'publisherfree2read',
            'gold'            => 'publisherfullgold',
            'gold hybrid'     => 'publisherhybridgold',
            'green accepted'  => 'repository',
            'green only'      => 'repository',
            'green published' => 'repository',
            'green submitted' => 'repository',
        };
        $self->{'wos'}->log ('i', 'loading indicator micro CT');
        my $jxs = JSON::XS->new->allow_nonref->canonical(1);
        my $rs = $self->find ('indicator'); 
        my $rc;
        while ($rc = $rs->next ()) {
            my $ind = $jxs->decode ($rc->{'json'});
            foreach my $cat (@{$ind->{'PERCENTILE'}}) {
                if ($cat->{'LEVEL'} == 3) {
                    my $ct = $cat->{'SUBJECT'};
                    $ct =~ s/^\s+//;
                    $ct =~ s/\s+.*//;
                    $ct =~ s/[^0-9\.]//g;
                    if ($ct) {
                        if (exists ($self->{'ct_micro'}{$rc->{'ut'}})) {
                            push (@{$self->{'ct_micro'}{$rc->{'ut'}}}, $ct);
                        } else {
                            $self->{'ct_micro'}{$rc->{'ut'}} = [$ct];
                        }
                    }
                }
            }
            if ($ind->{'OPEN_ACCESS'}{'OA_FLAG'}) {
                my $types = {all => 1};
                foreach my $status (@{$ind->{'OPEN_ACCESS'}{'STATUS'}}) {
                    my $type = lc ($status->{'TYPE'});
                    $type =~ s/[^a-z]+/ /g;
                    $type =~ s/^ //;
                    $type =~ s/ $//;
                    if ($oamap->{$type}) {
                        $types->{$oamap->{$type}} = 1;
                    } else {
                        $self->{'wos'}->log ('w', 'unknown OA type: %s (%s)', $type, $status->{'TYPE'});
                    }
                }
                $self->{'open_access'}{$rc->{'ut'}} = join (' ', sort (keys (%{$types})));
            }
        }
        $self->{'wos'}->log ('i', '- done');
    }
    if ($ut) {
        if (exists ($self->{'ct_micro'}{$ut})) {
            return (@{$self->{'ct_micro'}{$ut}});
        } else {
            return ();
        }
    } else {
        return ();
    }
}

sub open_access
{
    my ($self, $ut) = @_;

    if (!exists ($self->{'open_access'})) {
        $self->ct_micro ();
    }
    if ($ut) {
        if (exists ($self->{'open_access'}{$ut})) {
            return ($self->{'open_access'}{$ut});
        } else {
            return ();
        }
    } else {
        return ();
    }
}

1;

