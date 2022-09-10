package NORA::WOS::DB;

use strict;
use warnings;
use NORA::WOS;
use JSON::XS;
use DBI qw(:sql_types);

sub new
{
    my ($class, $dbfile) = @_;
    my $self = {};

    if (-e '/var/lib/nora-wos/db') {
        $self->{'dbfile'} = '/var/lib/nora-wos/db/nora-wos.sqlite3';
    } else {
        $self->{'dbfile'} = 'nora-wos.sqlite3';
    }
    $self->{'dbh'} = DBI->connect ('dbi:SQLite:' . $self->{'dbfile'}, undef, undef, {PrintError => 1, RaiseError => 0});
    $self->{'wos'} = new NORA::WOS ();
    return (bless ($self, $class));
}

sub reconnect
{
    my ($self) = @_;

    $self->{'dbh'} = DBI->connect ('dbi:SQLite:' . $self->{'dbfile'}, undef, undef, {PrintError => 1, RaiseError => 0});
}

sub dbfile
{
    my ($self) = @_;

    return ($self->{'dbfile'});
}

sub doctype
{
    my $type = {
        article => 1,
        review  => 1,
    };
}

sub ind_update
{
    my ($self, $rec) = @_;

    if ($rec->{'stamp'}) {
        $rec->{'stamp'} = time;
        my @fld = ();
        my @val = ();
        foreach my $key (sort (keys (%{$rec}))) {
            if (exists ($self->{'ind'}{$key})) {
                push (@fld, $self->{'ind'}{$key} . '=?');
                push (@val, $rec->{$key});
            } else {
                $self->log ('f', 'unmapped Incites indicator: "%s"', $key);
                exit (1);
            }
        }
        $self->sql ('update ind set ' . join (',', @fld) . " where ut='" . $rec->{'ut'} . "'");
    } else {
        $rec->{'stamp'} = time;
        my @fld = ();
        my @pla = ();
        my @val = ();
        foreach my $key (sort (keys (%{$rec}))) {
            if (exists ($self->{'ind'}{$key})) {
                push (@fld, $self->{'ind'}{$key});
                push (@pla, '?');
                push (@val, $rec->{$key});
            } else {
                $self->log ('f', 'unmapped Incites indicator: "%s"', $key);
                exit (1);
            }
        }
        $self->sql ('insert into ind (' . join (',', @fld) . ') VALUES (' . join (',', @pla) . ')', @val);
    }
}

sub doc_core_update
{
    my ($self, $rec) = @_;

    if (($rec->{'stamp'}) || ($self->{'doc_core_update'}{$rec->{'ut'}})) {
        if (!$rec->{'stamp'}) {
            warn ("info: update double: $rec->{'ut'}\n");
        }
        $rec->{'stamp'} = time;
        my @fld = ();
        my @val = ();
        foreach my $key (sort (keys (%{$rec}))) {
            push (@fld, $key . '=?');
            push (@val, $rec->{$key});
        }
        $self->sql ('update doc_core set ' . join (',', @fld) . " where ut='" . $rec->{'ut'} . "'");
    } else {
        $self->{'doc_core_update'}{$rec->{'ut'}} = 1;
        $rec->{'stamp'} = time;
        my @fld = ();
        my @pla = ();
        my @val = ();
        foreach my $key (sort (keys (%{$rec}))) {
            push (@fld, $key);
            push (@pla, '?');
            push (@val, $rec->{$key});
        }
        $self->sql ('insert into doc_core (' . join (',', @fld) . ') VALUES (' . join (',', @pla) . ')', @val);
    }
}

sub doc_person_insert
{
    my ($self, $rec) = @_;

    $rec->{'stamp'} = time;
    my @fld = ();
    my @pla = ();
    my @val = ();
    foreach my $key (sort (keys (%{$rec}))) {
        push (@fld, $key);
        push (@pla, '?');
        push (@val, $rec->{$key});
    }
    $self->sql ('insert into doc_person (' . join (',', @fld) . ') VALUES (' . join (',', @pla) . ')', @val);
}

sub close
{
    my ($self) = @_;

    $self->{'dbh'}->disconnect ();
}

sub json_load
{
    my ($file) = @_;

#   open (my $fin, $file);
#   my $json = join ('', <$fin>);
#   close ($fin);
#   return (decode_json ($json));
}

sub create
{   
    my ($self) = @_;

    $self->sql ('create table if not exists doc (
                     ut                  string primary key,
                     stamp               integer,
                     year                integer,
                     doctype             string,
                     title               string,
                     authors             string,
                     source              string,
                     volume              string,
                     issue               string,
                     pubdate             string,
                     cited               integer,
                     refs                integer,
                     doi                 string,
                     json                string)'); 
    $self->sql ('create table if not exists indicator (
                     ut                  string primary key,
                     stamp               integer,
                     incites_date        string,
                     json                string)'); 
    $self->sql ('create index if not exists indicator_incites_date on indicator (incites_date)');
    $self->sql ('create table if not exists updates (
                     id                  integer primary key autoincrement,
                     stamp               integer,
                     upd                 string,
                     updlong             string)'); 
}

sub ind_mapping
{
    my ($self, $key) = @_;

    if (defined ($key)) {
        if (exists ($self->{'ind'}{$key})) {
            return ($self->{'ind'}{$key});
        } else {
            die ("fatal: unmapped indicator: '$key'");
        }
    } else {
        return ($self->{'ind'});
    }
}

sub update
{
    my ($self, $table, $key, $rec) = @_;

    if (($key) && ($rec->{$key})) {
        $rec->{'stamp'} = time;
        my @fld = ();
        my @val = ();
        foreach my $fld (sort (keys (%{$rec}))) {
            push (@fld, $fld . '=?');
            push (@val, $self->trim ($rec->{$fld}));
        }
        if ($rec->{$key} =~ m/^[0-9]+$/) {
            $self->sql ("update $table set " . join (',', @fld) . " where $key=" . $rec->{$key}, @val);
        } else {
            $self->sql ("update $table set " . join (',', @fld) . " where $key='" . $rec->{$key} . "'", @val);
        }
    } else {
        $rec->{'stamp'} = time;
        my @fld = ();
        my @pla = ();
        my @val = ();
        foreach my $fld (sort (keys (%{$rec}))) {
            push (@fld, $fld);
            push (@pla, '?');
            push (@val, $self->trim ($rec->{$fld}));
        }
        $self->sql ("insert into $table (" . join (',', @fld) . ') VALUES (' . join (',', @pla) . ')', @val);
    }
}

sub trim
{
    my ($self, $txt) = @_;

    if (!defined ($txt)) {
        return ('');
    }
    $txt =~ s/^[\s\t\r\n]+//;
    $txt =~ s/[\s\t\r\n]+$//;
    return ($txt);
}

sub sql
{
    my ($self, $sql, @args) = @_;

#   print ("debug: SQL: $sql\n");
    my $sth = $self->prepare ($sql);
    $self->execute ($sth, @args);
    return ($sth);
}

sub prepare
{
    my ($self, $sql) = @_;
    my ($sth);

    my $dbh = $self->{'dbh'};
    if ($sth = $dbh->prepare ($sql)) {
        return ($sth);
    } else {
        die ('fatal: ' . $dbh->errstr . " ($sql)");
    }
}

sub execute
{
    my ($self, $sth, @args) = @_;
    my ($status);

    $sth->execute (@args);
    if ((defined ($sth->errstr)) && (length ($sth->errstr))) {
        die ('fatal: ' . $sth->errstr);
    } else {
        return (1);
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
        my $rs = $self->sql ('select ut,json from indicator');
        my $rc;
        while ($rc = $rs->fetchrow_hashref) {
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
        $self->ct_micro ($ut);
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

