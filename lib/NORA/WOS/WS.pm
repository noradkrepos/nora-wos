package NORA::WOS::WS;

use strict;
use warnings;
use POSIX;
use JSON::XS;
use NORA::WOS::DB;
use NORA::WOS::API;
use Time::HiRes qw(time);

sub new
{
    my ($class) = @_;

    my $self = {};
    $self->{'adh'} = new NORA::WOS ();
    $self->{'db'} = new NORA::WOS::DB ();
    $self->{'wos'} = new NORA::WOS::API ();
    my $utf8 = $self->{'adh'}->conf ('utf8-decode');
    if ($utf8 =~ m/on/i) {
        $self->{'utf8-decode'} = 1;
    } else {
        $self->{'utf8-decode'} = 0;
    }
    return (bless ($self, $class));
}

sub process
{
    my ($self) = @_;
    my $v;

    $self->{'start'} = time;
    $self->{'result'} = {request => {datestamp => 'requestDatestamp'}, response => {datestamp => 'responseDatestamp', elapse => 'responseElapse', cache => 'responseCached'}};
    $self->{'args'} = [];
    ($v, $self->{'comm'}, @{$self->{'args'}}) = split ('/', $ENV{'PATH_INFO'});
    $self->{'result'}{'request'}{'command'} = $self->{'comm'};
    my $param = $self->cgi_params ();
    if ($self->{'comm'} eq 'department_options') {
        $self->comm_department_options ();
    }
    if ($self->{'comm'} eq 'researchers') {
        $self->comm_researchers ();
    }
    if ($self->{'comm'} eq 'researcher_name') {
        $self->comm_researcher_name ();
    }
    if ($self->{'comm'} eq 'researcher') {
        $self->comm_researcher ();
    }
    if ($self->{'comm'} eq 'records') {
        $self->comm_records ();
    }
    if ($self->{'comm'} eq 'record') {
        $self->comm_record ();
    }
    if ($self->{'comm'} eq 'departments') {
        $self->comm_departments ();
    }
    if ($self->{'comm'} eq 'unit_name') {
        $self->comm_unit_name ();
    }
    if ($self->{'comm'} eq 'unit') {
        $self->comm_unit ();
    }
    if ($self->{'comm'} eq 'rep_professors') {
        $self->comm_rep_professors ();
    }
    if ($self->{'comm'} eq 'rep_professors_sheet') {
        $self->comm_rep_professors_sheet ();
    }
    if ($self->{'comm'} eq 'rep_departments_sheet') {
        $self->comm_rep_departments_sheet ();
    }
    if ($self->{'comm'} eq 'last_update') {
        $self->comm_last_update ();
    }
    $self->{'adh'}->log ('e', 'unknown command: "%s"', $self->{'comm'});
    return (1);
}

sub cgi_params
{
    my ($self, $key) = @_;
    if (!defined ($key)) {
        my $params = {};

        foreach my $par (split ('&', $ENV{'QUERY_STRING'})) {
            my ($name, $value) = split ('=', $par, 2);
            $name =~ s/\+/ /g;
            $name =~ s/%([0-9a-f][0-9a-f])/pack ("C", hex ($1))/gie;
            $value =~ s/\+/ /g;
            $value =~ s/%([0-9a-f][0-9a-f])/pack ("C", hex ($1))/gie;
            $params->{$name} = $value;
            warn ("cgi: '$name': '$value'\n");
        }
        $self->{'cgi_params'} = $params;
        return;
    }
    if (!defined ($self->{'cgi_params'})) {
        die ('cgi_params: call $self->cgi_params (), first');
    }
    return ($self->{'cgi_params'}{$key});
}

sub comm_department_options
{
    my ($self) = @_;

    my $rc;
    my $rs = $self->{'db'}->sql ('select department,upd,sheet from sheets');
    my $sheet = {};
    while ($rc = $rs->fetchrow_hashref) {
        $rc->{'sheet'} = $rc->{'sheet'};
        $sheet->{$rc->{'department'}} = $rc;
        delete ($sheet->{$rc->{'department'}}{'department'});
    }
    my $ret = {options => [['', 'All']]};
    $rs = $self->{'db'}->sql ('select key,name from department order by name');
    while ($rc = $rs->fetchrow_hashref) {
        if ($self->{'utf8-decode'}) {
            utf8::decode($rc->{'name'});
        }
        push (@{$ret->{'options'}}, [$rc->{'key'}, $rc->{'name'}]);
        if ($sheet->{$rc->{'key'}}) {
            $ret->{'sheet'}{$rc->{'key'}} = $sheet->{$rc->{'key'}};
        }
        $ret->{$rc->{'key'}} = [['', 'All']];
    }
    foreach my $dep (keys (%{$ret})) {
        if (($dep ne 'options') && ($dep ne 'sheet')) {
            $rs = $self->{'db'}->sql ('select key,name from section where department=? order by name', $dep);
            while ($rc = $rs->fetchrow_hashref) {
                if ($self->{'utf8-decode'}) {
                    utf8::decode($rc->{'name'});
                }
                push (@{$ret->{$dep}}, [$rc->{'key'}, $rc->{'name'}]);
            }
        }
    }
    $self->{'result'}{'response'}{'body'} = $ret;
    $self->respond ();
}

sub comm_researchers
{
    my ($self) = @_;

    my $ret = {};
    my $mod = $self->{'args'}->[0];
    if (!defined ($mod)) {
        $mod = '';
    } else {
        if ($mod eq 'head') {
            $self->{'result'}{'request'}{'modifier'} = 'head';
            $mod = ' limit 20';
        } elsif ($mod eq 'rest') {
            $self->{'result'}{'request'}{'modifier'} = 'rest';
            $mod = ' limit 20,6000';
        } else {
            if ($mod) {
                $self->{'adh'}->log ('e', 'researchers: unknown mod value: "%s"', $mod);
            }
            $mod = '';
        }
    }
    my @where   = ();
    my @vals    = ();
    my $dep = $self->cgi_params ('dep');
    my $sec = $self->cgi_params ('sec');
    if ($dep) {
        push (@where, 'department=?');
        push (@vals, $dep);
    }
    if ($sec) {
        push (@where, 'section=?');
        push (@vals, $sec);
    }
    my $where = '';
    if (@where) {
        $where .= ' and ' . join (' and ', @where);
    }
    my $rc;
    my $rs = $self->{'db'}->sql ('select orcid,count(*) as n from person_docs group by orcid');
    my $pubs = {};
    while ($rc = $rs->fetchrow_hashref) {
        $pubs->{$rc->{'orcid'}} = $rc->{'n'};
    }
    $rs = $self->{'db'}->sql ('select lname,fname,orcid,email,name,title from person,department where department=key ' . $where . ' order by lname,fname' . $mod, @vals);
    $self->{'result'}{'response'}{'body'} = [];
    $self->{'result'}{'response'}{'hits'} = 0;
    while ($rc = $rs->fetchrow_hashref) {
        my $row = [];
        if ($pubs->{$rc->{'orcid'}}) {
            push (@{$row}, $pubs->{$rc->{'orcid'}});
        } else {
            push (@{$row}, 0);
        }
        if ($rc->{'fname'}) {
            push (@{$row}, join (', ', $rc->{'lname'}, $rc->{'fname'}));
        } else {
            push (@{$row}, $rc->{'lname'});
        }
        if ($self->{'utf8-decode'}) {
            utf8::decode($row->[1]);
        }
        foreach my $f ('orcid', 'email', 'name', 'title') {
            push (@{$row}, $rc->{$f});
        }
        push (@{$self->{'result'}{'response'}{'body'}}, $row);
        $self->{'result'}{'response'}{'hits'}++;
    }
    $self->respond ();
}

sub comm_researcher_name
{
    my ($self) = @_;

    my $orcid = $self->{'args'}->[0];
    $self->{'result'}{'request'}{'orcid'} = $orcid;
    my $rc;
    my $rs;
    if ($orcid =~ m/^id:/) {
        my $id = $orcid;
        $id =~ s/^id://;
        $rs = $self->{'db'}->sql ('select fname,lname from person where id=?', $id);
    } else {
        $rs = $self->{'db'}->sql ('select fname,lname from person where orcid=?', $orcid);
    }
    if ($rc = $rs->fetchrow_hashref) {
        if ($self->{'utf8-decode'}) {
            utf8::decode($rc->{'lname'});
        }
        if ($rc->{'fname'}) {
            if ($self->{'utf8-decode'}) {
                utf8::decode($rc->{'fname'});
            }
            $self->{'result'}{'response'}{'name'} =  join (', ', $rc->{'lname'}, $rc->{'fname'});
        } else {
            $self->{'result'}{'response'}{'name'} = $rc->{'lname'};
        }
    }
    $self->respond ();
}

sub comm_researcher
{
    my ($self) = @_;

    my $orcid = $self->{'args'}->[0];
    $self->{'result'}{'request'}{'orcid'} = $orcid;
    my $syear = $self->{'args'}->[1];
    my $eyear = $self->{'args'}->[2];
    if (!$syear) {
        $syear = 0;
    }
    if (!$eyear) {
        $eyear = 9999;
    }
    $self->{'result'}{'request'}{'year-start'} = $syear;
    $self->{'result'}{'request'}{'year-end'} = $eyear;
    my $doctype = 0;
    foreach my $dt (split (';', $self->{'args'}->[3])) {
        $doctype = $doctype | $self->{'wos'}->doctype_code ($dt);
    }
    $self->{'result'}{'request'}{'doctype'} = $self->{'args'}->[3] . ' (' . $doctype . ')';
    $self->{'result'}{'response'}{'body'} = $self->get_researcher ($orcid, $syear, $eyear, $doctype, affiliation => 1, summary => 1, pubCite => 1, lastYearCurrent => 1);
    $self->respond ();
}

sub comm_rep_professors
{
    my ($self) = @_;

    my $doctype = 0;
    foreach my $dt (split (';', $self->cgi_params ('doctype'))) {
        $doctype = $doctype | $self->{'wos'}->doctype_code ($dt);
    }
    my $cacheFile;
    if ($doctype) {
        $cacheFile = 'rep_professors-' . join ('-', split (';', $self->cgi_params ('doctype'))) . '.json';
    } else {
        $cacheFile = 'rep_professors-all.json';
        $doctype = $self->{'wos'}->doctype_code ('all');
    }
    if (!$self->cgi_params ('nocache')) {
        $self->cache ($cacheFile);
    }
    my $rc;
    my @orcid = ();
    my $title = {};
    my $rs = $self->{'db'}->sql ('select id,orcid,title from person where title like "%professor%" order by lname,fname');
    while ($rc = $rs->fetchrow_hashref) {
        my $tis = {};
        my $match = 0;
        foreach my $ti (split (';', $rc->{'title'})) {
            my $key = lc ($ti);
            $key =~ s/[^a-z]//g;
            if ($key !~ m/^(professor|professormso)$/) {
                next;
            }
            $match = 1;
            $ti =~ s/^\s+//;
            $ti =~ s/\s+$//;
            $tis->{$ti} = 1;
        }
        if ($match) {
            if ($rc->{'orcid'} !~ m/[0-9]/) {
                $rc->{'orcid'} = 'id:' . $rc->{'id'};
            }
            push (@orcid, $rc->{'orcid'});
            $title->{$rc->{'orcid'}} = join ('; ', sort (keys (%{$tis})));
        }
    }
    my $department = {};
    $rs = $self->{'db'}->sql ('select key,name from department');
    while ($rc = $rs->fetchrow_hashref) {
        $department->{$rc->{'key'}} = $rc->{'name'};
    }
    my $rows = [];
    my $yearMin = 9999;
    my $yearMax = 0;
    foreach my $id (@orcid) {
        $rc = $self->get_researcher ($id, 0, 9999, $doctype);
        if (($self->{'result'}{'request'}{'year-start'}) && ($self->{'result'}{'request'}{'year-start'} < $yearMin)) {
            $yearMin = $self->{'result'}{'request'}{'year-start'};
        }
        if ($self->{'result'}{'request'}{'year-end'} > $yearMax) {
            $yearMax = $self->{'result'}{'request'}{'year-start'};
        }
        my $row = [];
        push (@{$row}, $rc->{'person'}{'displayName'});
        if ($id =~ m/^id:/) {
            push (@{$row}, '', $title->{$id});
        } else {
            push (@{$row}, $id, $title->{$id});
        }
        push (@{$row}, $department->{$rc->{'person'}{'department'}});
        $rc = $rc->{'ind'};
        push (@{$row}, $rc->{'absFirst'}, $rc->{'pubs'}, $rc->{'cites'}, $rc->{'citesPerPub'}, $rc->{'citesPerYear'}, $rc->{'hindex'}, $rc->{'pInt'}, $rc->{'pOA'});
        push (@{$rows}, $row);
    }
    $self->{'result'}{'request'}{'year-start'} = $yearMin;
    $self->{'result'}{'request'}{'year-end'} = $yearMax;
    $self->{'result'}{'response'}{'body'}{'rows'} = $rows;
    $rs = $self->{'db'}->sql ('select min(stamp) as upd from person_docs');
    if ($rc = $rs->fetchrow_hashref) {
        my ($sec, $min, $hour, $day, $mon, $year) = localtime ($rc->{'upd'});
        $self->{'result'}{'response'}{'body'}{'update'} = sprintf ('%02d-%02d-%04d', $day, $mon + 1, 1900 + $year);
    }
    $self->cache ($cacheFile, $self->{'result'});
    $self->respond ();
}

sub comm_rep_professors_sheet
{
    my ($self) = @_;

    my $date = $self->cgi_params ('date');
    if ($date) {
        my $file = '/var/lib/rap-adh/cache/rep_professors-' . $date . '.xlsx';
        if (-e $file) {
            print ("Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\n\n");
            if (open (my $fin, $file)) {
                print (<$fin>);
                close ($fin);
            } else {
                warn ("error: faile to open '$file' for reading: $!");
            }
            exit (0);
        } else {
            warn ("error: file not found: '$file'");
        }
    } else {
        my @dates = ();
        if (opendir (my $dh, '/var/lib/rap-adh/cache')) {
            my $file;
            while ($file = readdir ($dh)) {
                if ($file =~ m/rep_professors-([0-9]{4}-[0-9]{2}-[0-9]{2}).xlsx/) {
                    push (@dates, $1);
                }
            }
            closedir ($dh);
            $self->{'result'}{'response'}{'body'} = [sort {$b cmp $a} @dates];
            $self->respond ();
        } else {
            warn ("error: failed to open directory '/var/lib/rap-adh/cache': $!");
        }
    }
}

sub comm_rep_departments_sheet
{
    my ($self) = @_;

    my $date = $self->cgi_params ('date');
    if ($date) {
        my $file = '/var/lib/rap-adh/cache/rep_departments-' . $date . '.xlsx';
        if (-e $file) {
            print ("Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\n\n");
            if (open (my $fin, $file)) {
                print (<$fin>);
                close ($fin);
            } else {
                warn ("error: faile to open '$file' for reading: $!");
            }
            exit (0);
        } else {
            warn ("error: file not found: '$file'");
        }
    } else {
        my @dates = ();
        if (opendir (my $dh, '/var/lib/rap-adh/cache')) {
            my $file;
            while ($file = readdir ($dh)) {
                if ($file =~ m/rep_departments-([0-9]{4}-[0-9]{2}-[0-9]{2}).xlsx/) {
                    push (@dates, $1);
                }
            }
            closedir ($dh);
            $self->{'result'}{'response'}{'body'} = [sort {$b cmp $a} @dates];
            $self->respond ();
        } else {
            warn ("error: failed to open directory '/var/lib/rap-adh/cache': $!");
        }
    }
}

sub get_researcher
{
    my ($self, $orcid, $syear, $eyear, $doctype, %args) = @_;
    my $ret = {};

    my $rc;
    my $rs;
    if ($orcid =~ m/^id:/) {
        my $id = $orcid;
        $id =~ s/^id://;
        $rs = $self->{'db'}->sql ('select * from person where id=?', $id);
    } else {
        $rs = $self->{'db'}->sql ('select * from person where orcid=?', $orcid);
    }
    if ($rc = $rs->fetchrow_hashref) {
        if ($self->{'utf8-decode'}) {
            utf8::decode($rc->{'lname'});
        }
        if ($rc->{'fname'}) {
            if ($self->{'utf8-decode'}) {
                utf8::decode($rc->{'fname'});
            }
            $rc->{'name'} = join (', ', $rc->{'lname'}, $rc->{'fname'});
        } else {
            $rc->{'name'} = $rc->{'lname'};
        }
        $rc->{'displayName'} = $rc->{'fname'} . ' ' . $rc->{'lname'};
        $ret->{'person'} = $rc;
    }
    if ($args{'affiliation'}) {
        $ret->{'affiliation'} = [];
        $rs = $self->{'db'}->sql ('select year,department,section,title from affiliation where orcid=? order by year desc', $orcid);
        while ($rc = $rs->fetchrow_hashref) {
            my $row = [];
            foreach my $f ('year', 'department', 'section', 'title') {
                push (@{$row}, $rc->{$f});
            }
            push (@{$ret->{'affiliation'}}, $row);
        }
    }
    if ($args{'summary'}) {
        foreach my $dt ('all', 'article', 'proceedings paper', 'abstract', 'review', 'correction', 'other') {
            $ret->{'summary'}{$dt} = 0;
        }
        $rs = $self->{'db'}->sql ('select doctype,count(*) as n from person_docs where orcid=? group by doctype', $orcid);
        while ($rc = $rs->fetchrow_hashref) {
            foreach my $dt ('article', 'proceedings paper', 'abstract', 'review', 'correction', 'other') {
                if ($self->{'wos'}->doctype_code ($dt) & $rc->{'doctype'}) {
                    $ret->{'summary'}{$dt} += $rc->{'n'};
                }
            }
        }
        $rs = $self->{'db'}->sql ('select count(*) as n from person_docs where orcid=?', $orcid);
        if ($rc = $rs->fetchrow_hashref) {
            $ret->{'summary'}{'all'} = $rc->{'n'};
        }
        if ($ret->{'summary'}{'other'} > 0) {
            my $doctypes = {};
            $rs = $self->{'db'}->sql ('select doctype_other from person_docs where orcid=?', $orcid);
            while ($rc = $rs->fetchrow_hashref) {
                foreach my $dt (split (';', $rc->{'doctype_other'})) {
                    $doctypes->{$dt} = 1;
                }
            }
            $ret->{'summary'}{'doctype_other'} = join (', ', sort (keys (%{$doctypes})));
        } else {
            $ret->{'summary'}{'doctype_other'} = '';
        }
    }
    $rs = $self->{'db'}->sql ('select min(year) as first,max(year) as last from person_docs where orcid=?', $orcid);
    if ($rc = $rs->fetchrow_hashref) {
        if ($rc->{'first'}) {
            $ret->{'ind'}{'absFirst'} = $rc->{'first'};
            $ret->{'ind'}{'absLast'} = $rc->{'last'};
            if ((!defined ($syear)) || (!defined ($rc->{'first'}))) {
                warn ("$orcid - $syear : $rc->{'first'}\n");
            }
            if ($syear < $rc->{'first'}) {
                $syear = $rc->{'first'};
            }
            if ($args{'lastYearCurrent'}) {
                if ($eyear > $self->year ()) {
                    $eyear = $self->year ();
                }
            } else {
                if ($eyear > $rc->{'last'}) {
                    $eyear = $rc->{'last'};
                }
            }
        } else {
            $ret->{'ind'}{'absFirst'} = $ret->{'ind'}{'absLast'} = 'NA';
        }
    }
    $self->{'result'}{'request'}{'year-start'} = $syear;
    $self->{'result'}{'request'}{'year-end'} = $eyear;
    my $years = $eyear - $syear + 1;
    if (!$doctype) {
        $doctype = $self->{'wos'}->doctype_code ('all');
    }
    $rs = $self->{'db'}->sql ('select count(*) as pubs,min(year) as first,sum(cited) as cites,count(distinct(year)) as years,sum(is_international) as int,sum(oa_flag) as oa ' .
                              'from person_docs where orcid=? and doctype & ? and year >= ? and year <= ?', $orcid, $doctype, $syear, $eyear);
    if ($rc = $rs->fetchrow_hashref) {
        if ($rc->{'pubs'}) {
            $rc->{'citesPerPub'} = sprintf ('%0.1f', $rc->{'cites'} / $rc->{'pubs'});
            $rc->{'citesPerYear'} = sprintf ('%0.1f', $rc->{'cites'} / $years);
            $rc->{'pInt'} = sprintf ('%0.1f', $rc->{'int'} / $rc->{'pubs'} * 100);
            $rc->{'pOA'} = sprintf ('%0.1f', $rc->{'oa'} / $rc->{'pubs'} * 100);
        } else {
            $rc->{'citesPerPub'} = 'NA';
            $rc->{'citesPerYear'} = 'NA';
            $rc->{'pInt'} = 'NA';
            $rc->{'pOA'} = 'NA';
            $rc->{'cites'} = 0;
            $rc->{'first'} = 'NA';
        }
        $rc->{'absFirst'} = $ret->{'ind'}{'absFirst'};
        $rc->{'absLast'} = $ret->{'ind'}{'absLast'};
        $ret->{'ind'} = $rc;
    }
    $rs = $self->{'db'}->sql ('select cited from person_docs where orcid=? and doctype & ? and year >= ? and year <= ? order by cited desc', $orcid, $doctype, $syear, $eyear);
    my $n = 0;
    while ($rc = $rs->fetchrow_hashref) {
        if ($rc->{'cited'} > $n) {
            $n++;
        } else {
            last;
        }
    }
    $ret->{'ind'}{'hindex'} = $n;
    if ($args{'pubCite'}) {
        $ret->{'pubCite'} = [];
        my $pubYears = 0;
        for (my $year = $ret->{'ind'}{'absFirst'}; $year <= $ret->{'ind'}{'absLast'}; $year++) {
            $rs = $self->{'db'}->sql ('select count(*) as pubs,sum(cited) as cites,sum(oa_flag) as oa from person_docs where orcid=? and year=?', $orcid, $year);
            if ($rc = $rs->fetchrow_hashref) {
                foreach my $f (keys (%{$rc})) {
                    if (!defined ($rc->{$f})) {
                        $rc->{$f} = 0;
                    }
                }
                $rc->{'year'} = $year;
                if ($rc->{'pubs'}) {
                    $pubYears++;
                }
                push (@{$ret->{'pubCite'}}, $rc);
            } else {
                $rc = {year => $year, pubs => 0, cites => 0, oa => 0};
                push (@{$ret->{'pubCite'}}, $rc);
            }
        }
        if ($pubYears < 2) {
            delete ($ret->{'pubCite'});
        }
    }
    return ($ret);
}

sub comm_records
{
    my ($self, $excel) = @_;

    my @where = ();
    my @vals  = ();
    my $idfld = '';
    my $idval = '';
    my $fld;
    if (($fld = $self->cgi_params ('id')) && ($fld !~ m/^[\s\t\r\n]*$/)) {
        $self->{'result'}{'request'}{'id'} = $fld;
        my ($type, $code) = split (':', $fld, 2);
        if ($type eq 'orcid') {
            push (@where, 'p.orcid=?');
            push (@vals, $code);
            $idfld = 'orcid=?';
            $idval = $code;
            my $rc;
            my $rs = $self->{'db'}->sql ('select lname,fname from person where orcid=?', $code);
            if ($rc = $rs->fetchrow_hashref) {
                if ($rc->{'fname'}) {
                    $rc->{'name'} = join (', ', $rc->{'lname'}, $rc->{'fname'});
                } else {
                    $rc->{'name'} = $rc->{'lname'};
                }
                if ($self->{'utf8-decode'}) {
                    utf8::decode($rc->{'name'});
                }
                $self->{'result'}{'response'}{'name'} = $rc->{'name'};
            }
        } elsif ($type eq 'dep') {
            push (@where, 'p.department=?');
            push (@vals, $code);
            $idfld = 'department=?';
            $idval = $code;
            my $rc;
            my $rs = $self->{'db'}->sql ('select name from department where key=?', $code);
            if ($rc = $rs->fetchrow_hashref) {
                if ($self->{'utf8-decode'}) {
                    utf8::decode($rc->{'name'});
                }
                $self->{'result'}{'response'}{'name'} = $rc->{'name'};
            }
        } elsif ($type eq 'sec') {
            push (@where, 'p.section=?');
            push (@vals, $code);
            $idfld = 'section=?';
            $idval = $code;
            my $rc;
            my $rs = $self->{'db'}->sql ('select name from section where key=?', $code);
            if ($rc = $rs->fetchrow_hashref) {
                if ($self->{'utf8-decode'}) {
                    utf8::decode($rc->{'name'});
                }
                $self->{'result'}{'response'}{'name'} = $rc->{'name'};
            }
        } elsif ($type eq 'uni') {
            $self->{'result'}{'response'}{'name'} = 'DTU - Technical University of Denmark';
        } else {
            $self->{'adh'}->log ('e', 'unknown ID type: "%s" (%s)', $type, $fld);
        }
    }
    if (($fld = $self->cgi_params ('year')) && ($fld !~ m/^[\s\t\r\n]*$/)) {
        $self->{'result'}{'request'}{'year'} = $fld;
        push (@where, 'p.year=?');
        push (@vals, $fld);
    }
    if (($fld = $self->cgi_params ('year-start')) && ($fld !~ m/^[\s\t\r\n]*$/)) {
        $self->{'result'}{'request'}{'year-start'} = $fld;
        push (@where, 'p.year>=?');
        push (@vals, $fld);
    }
    if (($fld = $self->cgi_params ('year-end')) && ($fld !~ m/^[\s\t\r\n]*$/)) {
        $self->{'result'}{'request'}{'year-end'} = $fld;
        push (@where, 'p.year<=?');
        push (@vals, $fld);
    }
    if (($fld = $self->cgi_params ('doctype')) && ($fld !~ m/^[\s\t\r\n]*$/)) {
        $self->{'result'}{'request'}{'doctype'} = $fld;
        push (@where, 'p.doctype & ?');
        push (@vals, $self->{'wos'}->doctype_code ($fld));
    }
    if ((defined ($fld = $self->cgi_params ('dtu'))) && ($fld !~ m/^[\s\t\r\n]*$/)) {
        $self->{'result'}{'request'}{'dtu'} = $fld;
        if ($fld) {
            push (@where, 'p.dtu > 0');
        } else {
            push (@where, 'p.dtu=0');
        }
    }
    if (($fld = $self->cgi_params ('impact')) && ($fld !~ m/^[\s\t\r\n]*$/)) {
        $self->{'result'}{'request'}{'impact'} = $fld;
        if ($fld eq 'top1') {
            push (@where, 'percentile1=1');
        } elsif ($fld eq 'top10') {
            push (@where, 'percentile10=1');
        } elsif ($fld eq 'avg') {
            push (@where, 'nci >= 1');
        } elsif ($fld eq 'blw') {
            push (@where, 'nci < 1');
        } else {
            $self->{'adh'}->log ('e', 'unknown impact: "%s"', $fld);
        }
    }
    if (($fld = $self->cgi_params ('access')) && ($fld !~ m/^[\s\t\r\n]*$/)) {
        $self->{'result'}{'request'}{'access'} = $fld;
        if ($fld eq 'oa') {
            push (@where, 'oa_flag=1');
        } elsif ($fld eq 'notoa') {
            push (@where, 'oa_flag=0');
        } else {
            $self->{'adh'}->log ('e', 'unknown access: "%s"', $fld);
        }
    }
    if ((defined ($fld = $self->cgi_params ('sea'))) && ($fld !~ m/^[\s\t\r\n]*$/)) {
        $self->{'result'}{'request'}{'sea'} = $fld;
        $fld = '% ' . join ('% ', $self->{'adh'}->search_key ($fld)) . '%';
        push (@where, 'search_key like ?');
        push (@vals, $fld);
    }
    $self->{'result'}{'response'}{'body'} = [];
    my $rs;
    if (@where) {
        $rs = $self->{'db'}->sql ('select count(distinct(ut)) as hits from person_docs as p where ' . join (' and ', @where), @vals);
    } else {
        $rs = $self->{'db'}->sql ('select count(distinct(ut)) as hits from person_docs as p');
    }
    my $rc = $rs->fetchrow_hashref;
    $self->{'result'}{'response'}{'hits'} = $rc->{'hits'};
    $self->{'result'}{'response'}{'pages'} = ceil ($rc->{'hits'} / 10);
    if ($idfld) {
        $rs = $self->{'db'}->sql ("select distinct(year) from person_docs where $idfld order by year desc", $idval);
    } else {
        $rs = $self->{'db'}->sql ('select distinct(year) from person_docs order by year desc');
    }
    my $years = [];
    while ($rc = $rs->fetchrow_hashref) {
        push (@{$years}, $rc->{'year'});
    }
    $self->{'result'}{'response'}{'years'} = $years;
    if ($idfld) {
        $rs = $self->{'db'}->sql ("select distinct(doctype) from person_docs where $idfld", $idval);
    } else {
        $rs = $self->{'db'}->sql ('select distinct(doctype) from person_docs');
    }
    my $doctypes = {};
    while ($rc = $rs->fetchrow_hashref) {
        foreach my $dt ('article', 'proceedings paper', 'abstract', 'review', 'correction', 'other') {
            if ($self->{'wos'}->doctype_code ($dt) & $rc->{'doctype'}) {
                $doctypes->{$dt} = 1;
            }
        }
    }
    $self->{'result'}{'response'}{'doctype'} = $doctypes;
    if ($idfld) {
        $rs = $self->{'db'}->sql ("select distinct(dtu) from person_docs where $idfld", $idval);
    } else {
        $rs = $self->{'db'}->sql ('select distinct(dtu) from person_docs');
    }
    my $orgs = {};
    while ($rc = $rs->fetchrow_hashref) {
        if ($rc->{'dtu'} == 2) {
            $rc->{'dtu'} = 1;
        }
        $orgs->{$rc->{'dtu'}} = 1;
    }
    $self->{'result'}{'response'}{'dtu'} = $orgs;
    my $impact = {};
    if ($idfld) {
        $rs = $self->{'db'}->sql ("select count(*) as n from person_docs where percentile1=1 and $idfld", $idval);
    } else {
        $rs = $self->{'db'}->sql ('select count(*) as n from person_docs where percentile1=1');
    }
    $rc = $rs->fetchrow_hashref;
    if ($rc->{'n'} > 0) {
        $impact->{'top1'} = 1;
    }
    if ($idfld) {
        $rs = $self->{'db'}->sql ("select count(*) as n from person_docs where percentile10=1 and $idfld", $idval);
    } else {
        $rs = $self->{'db'}->sql ('select count(*) as n from person_docs where percentile10=1');
    }
    $rc = $rs->fetchrow_hashref;
    if ($rc->{'n'} > 0) {
        $impact->{'top10'} = 1;
    }
    if ($idfld) {
        $rs = $self->{'db'}->sql ("select count(*) as n from person_docs where nci >= 1 and $idfld", $idval);
    } else {
        $rs = $self->{'db'}->sql ('select count(*) as n from person_docs where nci >= 1');
    }
    $rc = $rs->fetchrow_hashref;
    if ($rc->{'n'} > 0) {
        $impact->{'avg'} = 1;
    }
    if ($idfld) {
        $rs = $self->{'db'}->sql ("select count(*) as n from person_docs where nci < 1 and $idfld", $idval);
    } else {
        $rs = $self->{'db'}->sql ('select count(*) as n from person_docs where nci < 1');
    }
    $rc = $rs->fetchrow_hashref;
    if ($rc->{'n'} > 0) {
        $impact->{'blw'} = 1;
    }
    $self->{'result'}{'response'}{'impact'} = $impact;
    my $acc = {};
    if ($idfld) {
        $rs = $self->{'db'}->sql ("select count(*) as n from person_docs where oa_flag = 1 and $idfld", $idval);
    } else {
        $rs = $self->{'db'}->sql ('select count(*) as n from person_docs where oa_flag = 1');
    }
    $rc = $rs->fetchrow_hashref;
    if ($rc->{'n'} > 0) {
        $acc->{'oa'} = 1;
    }
    if ($idfld) {
        $rs = $self->{'db'}->sql ("select count(*) as n from person_docs where oa_flag = 0 and $idfld", $idval);
    } else {
        $rs = $self->{'db'}->sql ('select count(*) as n from person_docs where oa_flag = 0');
    }
    $rc = $rs->fetchrow_hashref;
    if ($rc->{'n'} > 0) {
        $acc->{'notoa'} = 1;
    }
    $self->{'result'}{'response'}{'access'} = $acc;
    my $page;
    my $offset;
    my $recs;
    if ($excel) {
        $offset = 0;
        $recs = 999999;
    } else {
        $recs = 10;
        if (($page = $self->cgi_params ('page')) && ($page !~ m/^[\s\t\r\n]*$/)) {
            $page = int ($page);
            $self->{'result'}{'request'}{'page'} = $page;
        } else {
            $self->{'result'}{'request'}{'page'} = $page = 1;
        }
        $offset = ($page - 1) * $recs;
    }
    if (@where) {
        $rs = $self->{'db'}->sql ('select d.ut,d.dtu,d.year,d.title,d.authors,d.source,d.pubdate,d.cited,d.refs,d.doi,d.volume,d.issue,d.doctype from person_docs as p,doc as d ' .
                                  'where p.ut=d.ut and ' . join (' and ', @where) . " group by p.ut order by p.year desc,d.title,d.ut limit $offset,$recs", @vals);
    } else {
        $rs = $self->{'db'}->sql ('select d.ut,d.dtu,d.year,d.title,d.authors,d.source,d.pubdate,d.cited,d.refs,d.doi,d.volume,d.issue,d.doctype from person_docs as p,doc as d ' .
                                  "where p.ut=d.ut group by p.ut order by p.year desc,d.title,d.ut limit $offset,$recs");
    }
    while ($rc = $rs->fetchrow_hashref) {
        if ($self->{'utf8-decode'}) {
            foreach my $f (qw(title authors source)) {
                utf8::decode($rc->{$f});
            }
        }
        push (@{$self->{'result'}{'response'}{'body'}}, $rc);
    }
    if ($excel) {
        return ($self->{'result'}{'response'}{'body'});
    } else {
        $self->respond ();
    }
}

sub comm_record
{
    my ($self) = @_;
    my $ret = {};

    my ($ut);
    $self->{'result'}{'request'}{'ut'} = $ut = $self->{'args'}->[0];
    my $rc;
    my $rec = {test => 1};
    my $rs = $self->{'db'}->sql ('select * from doc where ut=?', $ut);
    if ($rc = $rs->fetchrow_hashref) {
        foreach my $f (qw(ut dtu doctype title source pubdate cited refs doi)) {
            if ($rc->{$f}) {
                $rec->{$f} = $rc->{$f};
            }
        }
        $rc = JSON::XS->new->allow_nonref->decode ($rc->{'json'});
        foreach my $id ($self->{'wos'}->wos_array ($rc, 'dynamic_data/cluster_related/identifiers/identifier')) {
            if ($id->{'type'} eq 'issn') {
                $rec->{'issn'} = $id->{'value'};
            }
            if ($id->{'type'} eq 'eissn') {
                $rec->{'eissn'} = $id->{'value'};
            }
            if ($id->{'type'} eq 'isbn') {
                $rec->{'isbn'} = $id->{'value'};
            }
        }
        $rec->{'abstract'} = [];
        foreach my $abs ($self->{'wos'}->wos_array ($rc, 'static_data/fullrecord_metadata/abstracts/abstract/abstract_text/p')) {
            push (@{$rec->{'abstract'}}, $abs);
        }
        $rec->{'address'} = [];
        foreach my $add ($self->{'wos'}->wos_array ($rc, 'static_data/fullrecord_metadata/addresses/address_name')) {
            my $e = {
                id => $add->{'address_spec'}{'addr_no'},
                text => $add->{'address_spec'}{'full_address'},
            };
            push (@{$rec->{'address'}}, $e);
        }
        $rec->{'category'} = [];
        foreach my $cat ($self->{'wos'}->wos_array ($rc, 'static_data/fullrecord_metadata/category_info/subjects/subject')) {
            if ($cat->{'ascatype'} eq 'traditional') {
                push (@{$rec->{'category'}}, $cat->{'content'});
            }
        }
        $rec->{'keywords'} = [];
        foreach my $cat ($self->{'wos'}->wos_array ($rc, 'static_data/item/keywords_plus/keyword')) {
            push (@{$rec->{'keywords'}}, $cat);
        }
        ($rec->{'conference'}) = $self->{'wos'}->wos_array ($rc, 'static_data/summary/conferences/conference/conf_infos/conf_info');
        $rec->{'names'} = [];
        foreach my $name ($self->{'wos'}->wos_array ($rc, 'static_data/summary/names/name')) {
            my $e = {
                id => $name->{'addr_no'},
                name => $name->{'wos_standard'},
            };
            if ($e->{'id'}) {
                $e->{'id'} =~ s/ +/, /g;
            }
            if ($self->author_key ($name->{'display_name'}) ne $self->author_key ($name->{'wos_standard'})) {
                $e->{'name'} .= ' (' . $name->{'display_name'} . ')';
            }
            push (@{$rec->{'names'}}, $e);
        }

        ($rec->{'volume'}) = $self->{'wos'}->wos_array ($rc, 'static_data/summary/pub_info/vol');
        ($rec->{'issue'}) = $self->{'wos'}->wos_array ($rc, 'static_data/summary/pub_info/issue');
        ($rec->{'pages'}) = $self->{'wos'}->wos_array ($rc, 'static_data/summary/pub_info/page/content');
        $rec->{'grants'} = [];
        foreach my $grant ($self->{'wos'}->wos_array ($rc, 'static_data/fullrecord_metadata/fund_ack/grants/grant')) {
            my $e = {
                name => $grant->{'grant_agency'},
                id => join (', ', $self->{'wos'}->wos_array ($grant, 'grant_ids/grant_id')),
            };
            push (@{$rec->{'grants'}}, $e);
        }
    } else {
        warn ("fatal: failed to find record UT: '$ut'\n");
    }
    $rs = $self->{'db'}->sql ('select * from person_docs where ut=?', $ut);
    if ($rc = $rs->fetchrow_hashref) {
        foreach my $f (qw(oa_types tot_cites)) {
            $rec->{'ind'}{$f} = $rc->{$f};
        }
        foreach my $f (qw(ae_rate impact_factor jou_act_exp_cit jou_exp_cit percentile)) {
            $rec->{'ind'}{$f} = sprintf('%0.1f', $rc->{$f});
        }
        foreach my $f (qw(cnci nci)) {
            $rec->{'ind'}{$f} = sprintf('%0.2f', $rc->{$f});
        }
        if ($rec->{'ind'}{'impact_factor'} < 0) {
            $rec->{'ind'}{'impact_factor'} = 'NA';
        }
        foreach my $f (qw(esi_most_cited hot_paper is_industry is_institution is_international oa_flag percentile1 percentile10)) {
            if ($rc->{$f}) {
                $rec->{'ind'}{$f} = 'Yes';
            } else {
                $rec->{'ind'}{$f} = 'No';
            }
        }
        if (($rc->{'percentile_json'}) && ($rc->{'percentile_json'} =~ m/\[/)) {
            $rec->{'ind'}{'percentiles'} = JSON::XS->new->allow_nonref->decode ($rc->{'percentile_json'});
        } else {
            $rec->{'ind'}{'percentiles'} = [];
        }
    } else {
        warn ("fatal: failed to find record UT in person_docs: '$ut'\n");
    }
    $self->{'result'}{'response'}{'body'} = $rec;
    $self->respond ();
}

sub comm_departments
{
    my ($self) = @_;

    my $rc;
    my $name = {};
    my $rs = $self->{'db'}->sql ('select key,name from department');
    while ($rc = $rs->fetchrow_hashref) {
        $name->{$rc->{'key'}} = $rc->{'name'};
    }
    my $syear = $self->{'args'}->[0];
    if (!$syear) {
        $syear = 1900;
    }
    my $eyear = $self->{'args'}->[1];
    if (!$eyear) {
        $eyear = $self->year ();
    }
    $self->{'result'}{'request'}{'year-start'} = $syear;
    $self->{'result'}{'request'}{'year-end'} = $eyear;
    my $doctype = 0;
    if ($self->{'args'}->[2]) {
        foreach my $dt (split (';', $self->{'args'}->[2])) {
            $doctype = $doctype | $self->{'wos'}->doctype_code ($dt);
        }
        $self->{'result'}{'request'}{'doctype'} = $self->{'args'}->[2] . ' (' . $doctype . ')';
    } else {
        $doctype = $self->{'wos'}->doctype_code ('all');
        $self->{'result'}{'request'}{'doctype'} = 'all (' . $doctype . ')';
    }
    $rs = $self->{'db'}->sql ('select min(year) as min,max(year) as max from person_docs where year > 1950');
    if ($rc = $rs->fetchrow_hashref) {
        $self->{'result'}{'response'}{'body'}{'yearmin'} = $rc->{'min'};
        $self->{'result'}{'response'}{'body'}{'yearmax'} = $rc->{'max'};
    }
    my $data = {'000/dtu' => {id => 'dtu', name => 'DTU', cited => 0, cnci => 0, percentile1 => 0, percentile10 => 0}};
    my $done = {};
    $rs = $self->{'db'}->sql ('select department,ut,cited,cnci,percentile1,percentile10,impact_factor from person_docs where dtu > 0 and doctype & ? and year >= ? and year <= ?', $doctype, $syear, $eyear);
    while ($rc = $rs->fetchrow_hashref) {
        if ($done->{$rc->{'ut'} . $rc->{'department'}}) {
            next;
        }
        $done->{$rc->{'ut'} . $rc->{'department'}} = 1;
        my $key = lc ($name->{$rc->{'department'}}) . '/' . $rc->{'department'};
        if (!exists ($data->{$key})) {
            $data->{$key} = {id => $rc->{'department'}, name => $name->{$rc->{'department'}}, cited => 0, cnci => 0, percentile1 => 0, percentile10 => 0};
        }
        $data->{$key}{'pubs'}++;
        if (defined ($rc->{'impact_factor'})) {
            $data->{$key}{'incs'}++;
        }
        foreach my $f (qw(cited cnci percentile1 percentile10)) {
            $data->{$key}{$f} += $rc->{$f};
        }
        if ($done->{$rc->{'ut'}}) {
            next;
        }
        $done->{$rc->{'ut'}} = 1;
        $data->{'000/dtu'}{'pubs'}++;
        if (defined ($rc->{'impact_factor'})) {
            $data->{'000/dtu'}{'incs'}++;
        }
        foreach my $f (qw(cited cnci percentile1 percentile10)) {
            $data->{'000/dtu'}{$f} += $rc->{$f};
        }
    }
    my $max = {cited => 0, cnci => 0, percentile10 => 0, percentile1 => 0};
    foreach my $dep (keys (%{$data})) {
        $data->{$dep}{'cited'} = ($data->{$dep}{'cited'} / $data->{$dep}{'pubs'});
        $data->{$dep}{'cnci'} = ($data->{$dep}{'cnci'} / $data->{$dep}{'incs'});
        $data->{$dep}{'percentile10'} = ($data->{$dep}{'percentile10'} / $data->{$dep}{'incs'} * 100);
        $data->{$dep}{'percentile1'} = ($data->{$dep}{'percentile1'} / $data->{$dep}{'incs'} * 100);
        foreach my $f (keys (%{$max})) {
            if ($data->{$dep}{$f} > $max->{$f}) {
                $max->{$f} = $data->{$dep}{$f};
            }
        }
    }
    my $ret = [];
    foreach my $dep (sort (keys (%{$data}))) {
        my $row = [$data->{$dep}{'id'}, $data->{$dep}{'name'}, $data->{$dep}{'pubs'}];
        foreach my $f (qw(cited cnci percentile10 percentile1)) {
            my $pc = int ($data->{$dep}{$f} / $max->{$f} * 100);
            if ($pc < 0) {
                $pc = 0;
            }
            push (@{$row}, [sprintf ('%0.2f', $data->{$dep}{$f}), $pc]);
        }
        push (@{$ret}, $row);
    }
    $self->{'result'}{'response'}{'body'}{'rows'} = $ret;
    $self->respond ();
}

sub comm_departments_org
{
    my ($self) = @_;
    my $ret = {};

    my $rc;
    my $name = {};
    my $rs = $self->{'db'}->sql ('select key,name from department');
    while ($rc = $rs->fetchrow_hashref) {
        $name->{$rc->{'key'}} = $rc->{'name'};
    }
    my $syear = $self->{'args'}->[0];
    if (!$syear) {
        $syear = 1900;
    }
    my $eyear = $self->{'args'}->[1];
    if (!$eyear) {
        $eyear = $self->year ();
    }
    $self->{'result'}{'request'}{'year-start'} = $syear;
    $self->{'result'}{'request'}{'year-end'} = $eyear;
    my $doctype = 0;
    if ($self->{'args'}->[2]) {
        foreach my $dt (split (';', $self->{'args'}->[2])) {
            $doctype = $doctype | $self->{'wos'}->doctype_code ($dt);
        }
        $self->{'result'}{'request'}{'doctype'} = $self->{'args'}->[2] . ' (' . $doctype . ')';
    } else {
        $doctype = $self->{'wos'}->doctype_code ('all');
        $self->{'result'}{'request'}{'doctype'} = 'all (' . $doctype . ')';
    }
    $rs = $self->{'db'}->sql ('select min(year) as min,max(year) as max from person_docs where year > 1950');
    if ($rc = $rs->fetchrow_hashref) {
        $self->{'result'}{'response'}{'body'}{'yearmin'} = $rc->{'min'};
        $self->{'result'}{'response'}{'body'}{'yearmax'} = $rc->{'max'};
    }
    my $max = {cites => 0, impact => 0, p10 => 0, p1 => 0};
    $rs = $self->{'db'}->sql ('select department,count(*) as pubs,sum(tot_cites) as cites,avg(impact_factor) as impact,sum(percentile1) as p1,sum(percentile10) as p10 ' .
                              'from person_docs where doctype & ? and year >= ? and year <= ? group by department', $doctype, $syear, $eyear);
    while ($rc = $rs->fetchrow_hashref) {
        my $n;
        $n = ($rc->{'cites'} / $rc->{'pubs'});
        if ($n > $max->{'cites'}) {
            $max->{'cites'} = $n;
        }
        $n = $rc->{'impact'};
        if ($n > $max->{'impact'}) {
            $max->{'impact'} = $n;
        }
        $n = ($rc->{'p10'} / $rc->{'pubs'} * 100);
        if ($n > $max->{'p10'}) {
            $max->{'p10'} = $n;
        }
        $n = ($rc->{'p1'} / $rc->{'pubs'} * 100);
        if ($n > $max->{'p1'}) {
            $max->{'p1'} = $n;
        }
    }
    $rs = $self->{'db'}->sql ('select count(*) as pubs,sum(tot_cites) as cites,avg(impact_factor) as impact,sum(percentile1) as p1,sum(percentile10) as p10 ' .
                              'from person_docs where doctype & ? and year >= ? and year <= ?', $doctype, $syear, $eyear);
    my @ret = ();
    while ($rc = $rs->fetchrow_hashref) {
        my $row = ['dtu', 'DTU', $rc->{'pubs'}];
        my $n;
        $n = ($rc->{'cites'} / $rc->{'pubs'});
        push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'cites'} * 100)]);
        $n = $rc->{'impact'};
        if ($n > 0) {
            push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'impact'} * 100)]);
        } else {
            push (@{$row}, [sprintf ('%0.2f', $n), 0]);
        }
        $n = ($rc->{'p10'} / $rc->{'pubs'} * 100);
        push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'p10'} * 100)]);
        $n = ($rc->{'p1'} / $rc->{'pubs'} * 100);
        push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'p1'} * 100)]);
        push (@ret, $row);
    }
    warn ("select department,count(*) as pubs,sum(tot_cites) as cites,avg(impact_factor) as impact,sum(percentile1) as p1,sum(percentile10) as p10 from person_docs where doctype & $doctype and year >= $syear and year <= $eyear group by department\n");
    $rs = $self->{'db'}->sql ('select department,count(*) as pubs,sum(tot_cites) as cites,avg(impact_factor) as impact,sum(percentile1) as p1,sum(percentile10) as p10 ' .
                              'from person_docs where doctype & ? and year >= ? and year <= ? group by department', $doctype, $syear, $eyear);
    while ($rc = $rs->fetchrow_hashref) {
        my $row = [$rc->{'department'}, $name->{$rc->{'department'}}, $rc->{'pubs'}];
        my $n;
        $n = ($rc->{'cites'} / $rc->{'pubs'});
        push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'cites'} * 100)]);
        $n = $rc->{'impact'};
        if ($n > 0) {
            push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'impact'} * 100)]);
        } else {
            push (@{$row}, [sprintf ('%0.2f', $n), 0]);
        }
        $n = ($rc->{'p10'} / $rc->{'pubs'} * 100);
        push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'p10'} * 100)]);
        $n = ($rc->{'p1'} / $rc->{'pubs'} * 100);
        push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'p1'} * 100)]);
        push (@ret, $row);
    }
    $self->{'result'}{'response'}{'body'}{'rows'} = [sort {$a->[1] cmp $b->[1]} @ret];
    $self->respond ();
}

sub comm_department
{
    my ($self) = @_;
    my $ret = {};

#   select count(*) as n from person where department='chem'
#   select section,count(*) as n from person where department='chem' group by section
#   select count(*) as pubs,sum(cited) as cites,avg(impact_factor) as impact,sum(percentile10) as p10,sum(percentile1) as p1,sum(is_international) as int,sum(oa_flag) as oa from person_docs where department='chem';
    my $rc;
    my $name = {};
    my $rs = $self->{'db'}->sql ('select key,name from department');
    while ($rc = $rs->fetchrow_hashref) {
        $name->{$rc->{'key'}} = $rc->{'name'};
    }
    my $syear = $self->{'args'}->[0];
    if (!$syear) {
        $syear = 1900;
    }
    my $eyear = $self->{'args'}->[1];
    if (!$eyear) {
        $eyear = $self->year ();
    }
    $self->{'result'}{'request'}{'year-start'} = $syear;
    $self->{'result'}{'request'}{'year-end'} = $eyear;
    my $doctype = 0;
    if ($self->{'args'}->[2]) {
        foreach my $dt (split (';', $self->{'args'}->[2])) {
            $doctype = $doctype | $self->{'wos'}->doctype_code ($dt);
        }
        $self->{'result'}{'request'}{'doctype'} = $self->{'args'}->[2] . ' (' . $doctype . ')';
    } else {
        $doctype = $self->{'wos'}->doctype_code ('all');
        $self->{'result'}{'request'}{'doctype'} = 'all (' . $doctype . ')';
    }
    $rs = $self->{'db'}->sql ('select min(year) as min,max(year) as max from person_docs where year > 1950');
    if ($rc = $rs->fetchrow_hashref) {
        $self->{'result'}{'response'}{'body'}{'yearmin'} = $rc->{'min'};
        $self->{'result'}{'response'}{'body'}{'yearmax'} = $rc->{'max'};
    }
    my $max = {cites => 0, impact => 0, p10 => 0, p1 => 0};
    $rs = $self->{'db'}->sql ('select department,count(*) as pubs,sum(tot_cites) as cites,avg(impact_factor) as impact,sum(percentile1) as p1,sum(percentile10) as p10 ' .
                              'from person_docs where doctype & ? and year >= ? and year <= ? group by department', $doctype, $syear, $eyear);
    while ($rc = $rs->fetchrow_hashref) {
        my $n;
        $n = ($rc->{'cites'} / $rc->{'pubs'});
        if ($n > $max->{'cites'}) {
            $max->{'cites'} = $n;
        }
        $n = $rc->{'impact'};
        if ($n > $max->{'impact'}) {
            $max->{'impact'} = $n;
        }
        $n = ($rc->{'p10'} / $rc->{'pubs'} * 100);
        if ($n > $max->{'p10'}) {
            $max->{'p10'} = $n;
        }
        $n = ($rc->{'p1'} / $rc->{'pubs'} * 100);
        if ($n > $max->{'p1'}) {
            $max->{'p1'} = $n;
        }
    }
    $rs = $self->{'db'}->sql ('select count(*) as pubs,sum(tot_cites) as cites,avg(impact_factor) as impact,sum(percentile1) as p1,sum(percentile10) as p10 ' .
                              'from person_docs where doctype & ? and year >= ? and year <= ?', $doctype, $syear, $eyear);
    my @ret = ();
    while ($rc = $rs->fetchrow_hashref) {
        my $row = ['dtu', 'DTU', $rc->{'pubs'}];
        my $n;
        $n = ($rc->{'cites'} / $rc->{'pubs'});
        push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'cites'} * 100)]);
        $n = $rc->{'impact'};
        if ($n > 0) {
            push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'impact'} * 100)]);
        } else {
            push (@{$row}, [sprintf ('%0.2f', $n), 0]);
        }
        $n = ($rc->{'p10'} / $rc->{'pubs'} * 100);
        push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'p10'} * 100)]);
        $n = ($rc->{'p1'} / $rc->{'pubs'} * 100);
        push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'p1'} * 100)]);
        push (@ret, $row);
    }
    warn ("select department,count(*) as pubs,sum(tot_cites) as cites,avg(impact_factor) as impact,sum(percentile1) as p1,sum(percentile10) as p10 from person_docs where doctype & $doctype and year >= $syear and year <= $eyear group by department\n");
    $rs = $self->{'db'}->sql ('select department,count(*) as pubs,sum(tot_cites) as cites,avg(impact_factor) as impact,sum(percentile1) as p1,sum(percentile10) as p10 ' .
                              'from person_docs where doctype & ? and year >= ? and year <= ? group by department', $doctype, $syear, $eyear);
    while ($rc = $rs->fetchrow_hashref) {
        my $row = [$rc->{'department'}, $name->{$rc->{'department'}}, $rc->{'pubs'}];
        my $n;
        $n = ($rc->{'cites'} / $rc->{'pubs'});
        push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'cites'} * 100)]);
        $n = $rc->{'impact'};
        if ($n > 0) {
            push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'impact'} * 100)]);
        } else {
            push (@{$row}, [sprintf ('%0.2f', $n), 0]);
        }
        $n = ($rc->{'p10'} / $rc->{'pubs'} * 100);
        push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'p10'} * 100)]);
        $n = ($rc->{'p1'} / $rc->{'pubs'} * 100);
        push (@{$row}, [sprintf ('%0.2f', $n), int ($n / $max->{'p1'} * 100)]);
        push (@ret, $row);
    }
    $self->{'result'}{'response'}{'body'}{'rows'} = [sort {$a->[1] cmp $b->[1]} @ret];
    $self->respond ();
}

sub comm_unit_name
{
    my ($self) = @_;

    my ($type, $unit) = split (':', $self->cgi_params ('id'));
    $self->{'result'}{'request'}{'type'} = $type;
    $self->{'result'}{'request'}{'unit'} = $unit;
    my $name;
    if ($type eq 'uni') {
        $name = 'DTU - Technical University of Denmark';
    } elsif ($type eq 'dep') {
        my $rc;
        my $rs = $self->{'db'}->sql ('select name from department where key=?', $unit);
        if ($rc = $rs->fetchrow_hashref) {
            $name = $rc->{'name'};
        } else {
            $self->{'adh'}->log ('e', 'name not found for Unit "%s" of type dep', $unit);
        }
    } elsif ($type eq 'sec') {
        my $rc;
        my $rs = $self->{'db'}->sql ('select department,name from section where key=?', $unit);
        if ($rc = $rs->fetchrow_hashref) {
            $name = $rc->{'name'};
            $rs = $self->{'db'}->sql ('select name from department where key=?', $rc->{'department'});
            if ($rc = $rs->fetchrow_hashref) {
                $name = $rc->{'name'} . ' / ' . $name;
            }
        } else {
            $self->{'adh'}->log ('e', 'name not found for Unit "%s" of type sec', $unit);
        }
    } else {
        $self->{'adh'}->log ('e', 'unknown Unit type: "%s", for Unit: "%s"', $type, $unit);
    }
    if ($self->{'utf8-decode'}) {
        utf8::decode($name);
    }
    $self->{'result'}{'response'}{'name'} = $name;
    $self->respond ();
}

sub comm_unit
{
    my ($self) = @_;

    my ($type, $unit) = split (':', $self->cgi_params ('id'));
    $self->{'result'}{'request'}{'type'} = $type;
    $self->{'result'}{'request'}{'unit'} = $unit;
    my $name;
    my $where;
    if ($type eq 'uni') {
        $name = 'DTU - Technical University of Denmark';
        $where = '';
    } elsif ($type eq 'dep') {
        $self->{'result'}{'response'}{'body'}{'dep'} = $unit;
        $where = ' and department=?';
        my $rc;
        my $rs = $self->{'db'}->sql ('select name,lead_orcid,lead_name from department where key=?', $unit);
        if ($rc = $rs->fetchrow_hashref) {
            $name = $rc->{'name'};
            $self->unit_lead ($rc);
        } else {
            $self->{'adh'}->log ('e', 'name not found for Unit "%s" of type dep', $unit);
        }
    } elsif ($type eq 'sec') {
        $self->{'result'}{'response'}{'body'}{'sec'} = $unit;
        $where = ' and section=?';
        my $rc;
        my $rs = $self->{'db'}->sql ('select department,name,lead_orcid,lead_name from section where key=?', $unit);
        if ($rc = $rs->fetchrow_hashref) {
            $self->{'result'}{'response'}{'body'}{'dep'} = $rc->{'department'};
            $name = $rc->{'name'};
            $self->unit_lead ($rc);
            $rs = $self->{'db'}->sql ('select name from department where key=?', $rc->{'department'});
            if ($rc = $rs->fetchrow_hashref) {
                $name = $rc->{'name'} . ' / ' . $name;
            }
        } else {
            $self->{'adh'}->log ('e', 'name not found for Unit "%s" of type sec', $unit);
        }
    } else {
        $where = '';
        $self->{'adh'}->log ('e', 'unknown Unit type: "%s", for Unit: "%s"', $type, $unit);
    }
    if ($self->{'utf8-decode'}) {
        utf8::decode ($name);
    }
    $self->{'result'}{'response'}{'body'}{'name'} = $name;
    my $syear = $self->cgi_params ('syear');
    my $eyear = $self->cgi_params ('eyear');
    my $doctype = 0;
    if ($self->cgi_params ('doctype')) {
        foreach my $dt (split (';', $self->cgi_params ('doctype'))) {
            $doctype = $doctype | $self->{'wos'}->doctype_code ($dt);
        }
        $self->{'result'}{'request'}{'doctype'} = $self->cgi_params ('doctype') . ' (' . $doctype . ')';
    } else {
        $doctype = $self->{'wos'}->doctype_code ('all');
        $self->{'result'}{'request'}{'doctype'} = 'all (' . $doctype . ')';
    }
    my $rc;
    my $rs;
    if ($where) {
        $rs = $self->{'db'}->sql ('select min(year) as min,max(year) as max from person_docs where year > 1950' . $where, $unit);
    } else {
        $rs = $self->{'db'}->sql ('select min(year) as min,max(year) as max from person_docs where year > 1950');
    }
    if ($rc = $rs->fetchrow_hashref) {
        $self->{'result'}{'response'}{'body'}{'yearmin'} = $rc->{'min'};
        $self->{'result'}{'response'}{'body'}{'yearmax'} = $rc->{'max'};
        if ((!$syear) || ($syear < $rc->{'min'})) {
            $syear = $rc->{'min'};
        }
        if (!$eyear) {
            $eyear = $rc->{'max'};
        }
    }
    $self->{'result'}{'request'}{'year-start'} = $syear;
    $self->{'result'}{'request'}{'year-end'} = $eyear;
    my $done = {};
    $self->{'result'}{'response'}{'body'}{'summary'} = {'all' => 0, 'article' => 0, 'proceedings paper' => 0, 'abstract' => 0, 'review' => 0, 'correction' => 0, 'other' => 0};
    if ($where) {
        $rs = $self->{'db'}->sql ('select ut,doctype from person_docs where year > 1950' . $where, $unit);
    } else {
        $rs = $self->{'db'}->sql ('select ut,doctype from person_docs where year > 1950');
    }
    while ($rc = $rs->fetchrow_hashref) {
        if ($done->{$rc->{'ut'}}) {
            next;
        }
        $done->{$rc->{'ut'}} = 1;
        $self->{'result'}{'response'}{'body'}{'summary'}{'all'}++;
        foreach my $dt ('article', 'proceedings paper', 'abstract', 'review', 'correction', 'other') {
            if ($self->{'wos'}->doctype_code ($dt) & $rc->{'doctype'}) {
                $self->{'result'}{'response'}{'body'}{'summary'}{$dt}++;
            }
        }
    }
    if ($self->{'result'}{'response'}{'body'}{'summary'}{'other'} > 0) {
        my $doctypes = {};
        if ($where) {
            $rs = $self->{'db'}->sql ('select doctype_other from person_docs where year > 1950' . $where, $unit);
        } else {
            $rs = $self->{'db'}->sql ('select doctype_other from person_docs where year > 1950');
        }
        while ($rc = $rs->fetchrow_hashref) {
            foreach my $dt (split (';', $rc->{'doctype_other'})) {
                $doctypes->{$dt} = 1;
            }
        }
        $self->{'result'}{'response'}{'body'}{'summary'}{'doctype_other'} = join (', ', sort (keys (%{$doctypes})));
    } else {
        $self->{'result'}{'response'}{'body'}{'summary'}{'doctype_other'} = '';
    }

    $done = {};
    my $data = {pubs => 0, cites => 0, cited => 0, cnci => 0, top10 => 0, top1 => 0, international => 0, oa => 0};
    if ($where) {
        $rs = $self->{'db'}->sql ('select ut,cited,nci,percentile10,percentile1,is_international,oa_flag from person_docs where doctype & ? and year >= ? and year <= ?' . $where, $doctype, $syear, $eyear, $unit);
    } else {
        $rs = $self->{'db'}->sql ('select ut,cited,nci,percentile10,percentile1,is_international,oa_flag from person_docs where doctype & ? and year >= ? and year <= ?', $doctype, $syear, $eyear);
    }
    while ($rc = $rs->fetchrow_hashref) {
        if ($done->{$rc->{'ut'}}) {
            next;
        }
        $done->{$rc->{'ut'}} = 1;
        $data->{'pubs'}++;
        if ((defined ($rc->{'nci'})) && ($rc->{'nci'} =~ m/[0-9]/)) {
            $data->{'incs'}++;
        }
        if ($rc->{'cited'}) {
            $data->{'cited'}++;
            $data->{'cites'} += $rc->{'cited'};
        }
        foreach my $f (keys (%{$rc})) {
            if (!defined ($rc->{$f})) {
                $rc->{$f} = 0;
            }
        }
        $data->{'cnci'}          += $rc->{'nci'};
        $data->{'top10'}         += $rc->{'percentile10'};
        $data->{'top1'}          += $rc->{'percentile1'};
        $data->{'international'} += $rc->{'is_international'};
        $data->{'oa'}            += $rc->{'oa_flag'};
    }
    $self->{'result'}{'response'}{'body'}{'ind'}{'pubs'}         = $data->{'pubs'};
    $self->{'result'}{'response'}{'body'}{'ind'}{'cites'}        = $data->{'cites'};
    if ($data->{'pubs'} == 0) {
        $self->respond ();
    }
    $self->{'result'}{'response'}{'body'}{'ind'}{'citesPerPub'}  = sprintf ('%0.1f', ($data->{'cites'} / $data->{'pubs'}));
    $self->{'result'}{'response'}{'body'}{'ind'}{'citesPerYear'} = sprintf ('%0.1f', ($data->{'cites'} / ($eyear - $syear + 1)));
    $self->{'result'}{'response'}{'body'}{'ind'}{'pCited'}       = sprintf ('%0.1f', ($data->{'cited'} / $data->{'incs'} * 100));
    $self->{'result'}{'response'}{'body'}{'ind'}{'cnci'}         = sprintf ('%0.2f', ($data->{'cnci'} / $data->{'incs'}));
    $self->{'result'}{'response'}{'body'}{'ind'}{'top10'}        = sprintf ('%0.1f', ($data->{'top10'} / $data->{'incs'} * 100));
    $self->{'result'}{'response'}{'body'}{'ind'}{'top1'}         = sprintf ('%0.1f', ($data->{'top1'} / $data->{'incs'} * 100));
    $self->{'result'}{'response'}{'body'}{'ind'}{'pInt'}         = sprintf ('%0.1f', ($data->{'international'} / $data->{'incs'} * 100));
    $self->{'result'}{'response'}{'body'}{'ind'}{'pOA'}          = sprintf ('%0.1f', ($data->{'oa'} / $data->{'incs'} * 100));
    if ($where) {
        $rs = $self->{'db'}->sql ('select ut,cited from person_docs where doctype & ? and year >= ? and year <= ?' . $where . ' order by cited desc', $doctype, $syear, $eyear, $unit);
    } else {
        $rs = $self->{'db'}->sql ('select ut,cited from person_docs where doctype & ? and year >= ? and year <= ? order by cited desc', $doctype, $syear, $eyear);
    }
    $done = {};
    my $n = 0;
    while ($rc = $rs->fetchrow_hashref) {
        if ($done->{$rc->{'ut'}}) {
            next;
        }
        $done->{$rc->{'ut'}} = 1;
        if ($rc->{'cited'} > $n) {
            $n++;
        } else {
            last;
        }
    }
    $self->{'result'}{'response'}{'body'}{'ind'}{'hindex'} = $n;
    $self->{'result'}{'response'}{'body'}{'pubCite'} = [];
    my $pubYears = 0;
    for (my $year = $self->{'result'}{'response'}{'body'}{'yearmin'}; $year <= $self->{'result'}{'response'}{'body'}{'yearmax'}; $year++) {
        my $done = {};
        if ($where) {
            $rs = $self->{'db'}->sql ('select ut,cited,oa_flag from person_docs where year=?' . $where , $year, $unit);
        } else {
            $rs = $self->{'db'}->sql ('select ut,cited,oa_flag from person_docs where year=?', $year);
        }
        my $pub = 0;
        my $cit = 0;
        my $oa = 0;
        while ($rc = $rs->fetchrow_hashref) {
            if ($done->{$rc->{'ut'}}) {
                next;
            }
            $done->{$rc->{'ut'}} = 1;
            $pub++;
            $cit += $rc->{'cited'};
            $oa += $rc->{'oa_flag'};
        }
        if ($pub) {
            $pubYears++;
        }
        $rc = {year => $year, pubs => $pub, cites => $cit, oa => $oa};
        push (@{$self->{'result'}{'response'}{'body'}{'pubCite'}}, $rc);
    }
    if ($pubYears < 2) {
        delete ($self->{'result'}{'response'}{'body'}{'pubCite'});
    }
    $self->respond ();
}

sub unit_lead
{
    my ($self, $rc) = @_;

    if ($rc->{'lead_name'}) {
        if ($self->{'utf8-decode'}) {
            utf8::decode ($rc->{'lead_name'});
        }
        $self->{'result'}{'response'}{'body'}{'leader'}{'name'} = $rc->{'lead_name'};
    } else {
        $self->{'result'}{'response'}{'body'}{'leader'}{'name'} = 'NA';
    }
    if ($rc->{'lead_orcid'}) {
        $self->{'result'}{'response'}{'body'}{'leader'}{'orcid'} = $rc->{'lead_orcid'};
    } else {
        $self->{'result'}{'response'}{'body'}{'leader'}{'orcid'} = 'NA';
    }
    $self->{'result'}{'response'}{'body'}{'leader'}{'pubs'} = 0;
    if ($self->{'result'}{'response'}{'body'}{'leader'}{'orcid'} ne 'NA') {
        my $rs = $self->{'db'}->sql ('select count(*) as n from person_docs where orcid=?', $self->{'result'}{'response'}{'body'}{'leader'}{'orcid'});
        if ($rc = $rs->fetchrow_hashref) {
            $self->{'result'}{'response'}{'body'}{'leader'}{'pubs'} = $rc->{'n'};
        }
    }
}

sub comm_last_update
{
    my ($self) = @_;

    my $rs = $self->{'db'}->sql ('select upd,updlong from updates order by id desc limit 1');
    my $rc;
    if ($rc = $rs->fetchrow_hashref) {
        $self->{'result'}{'response'}{'body'} = $rc;
    } else {
        $self->{'result'}{'response'}{'body'} = {};
    }
    $self->respond ();
}

sub author_key
{
    my ($self, $name) = @_;

    $name = lc ($name);
    $name =~ s/[^0-9a-z]+//g;
    return ($name);
}

sub respond
{
    my ($self) = @_;
    my $result;

    print ("Content-Type: application/json\n\n");
    $result = JSON::XS->new->allow_nonref->encode ({rapas => $self->{'result'}});
    $result =~ s/requestDatestamp/$self->date ($self->{'start'})/e;
    $result =~ s/responseDatestamp/$self->date (time)/e;
    $result =~ s/responseElapse/sprintf ('%0.6f', time - $self->{'start'})/e;
    $result =~ s/responseCached/No/;
    print ($result);
    exit (0);
}

sub cache
{
    my ($self, $file, $result) = @_;

    my $cache = '/var/lib/rap-adh/cache';
    if (defined ($result)) {
        my $json = JSON::XS->new->allow_nonref->encode ({rapas => $result});
        if (open (my $fou, "> $cache/$file")) {
            print ($fou $json);
            close ($fou);
        } else {
            warn ("error: failed to open '$cache/$file' for writing: $!");
        }
    } else {
        if (-e "$cache/$file") {
            my $fin;
            if (!open ($fin, "$cache/$file")) {
                warn ("error: failed to open '$cache/$file' for reading: $!");
                return;
            }
            my $result = join ('', <$fin>);
            close ($fin);
            $result =~ s/requestDatestamp/$self->date ($self->{'start'})/e;
            $result =~ s/responseDatestamp/$self->date (time)/e;
            $result =~ s/responseElapse/sprintf ('%0.6f', time - $self->{'start'})/e;
            $result =~ s/responseCached/Yes/;
            print ("Content-Type: application/json\n\n");
            print ($result);
            exit (0);
        }
    }
}

sub date
{
    my ($self, $time) = @_;
    my ($sec, $min, $hour, $day, $mon, $year) = localtime ($time);
    
    return (sprintf ("%04d-%02d-%02d %02d:%02d:%02d", 1900 + $year, $mon + 1, $day, $hour, $min, $sec));
}

sub year
{
    my ($self, $time) = @_;

    if (!defined ($time)) {
        $time = time;
    }
    my ($sec, $min, $hour, $day, $mon, $year) = localtime ($time);
    return (1900 + $year);
}

sub display_issn
{
    my ($self, $issn) = @_;

    my $ISSN = uc ($issn);
    $ISSN =~ s/[^0-9X]//g;
    if ($ISSN =~ m/^[0-9]{7}[0-9Xx]/) {
        return (substr ($ISSN, 0, 4) . '-' . substr ($ISSN, 4));
    } else {
        if ($ISSN =~ m/[0-9X]/) {
            return ($issn);
        } else {
            return ('');
        }
    }
}

sub error
{
    my ($self, $message) = @_;

    print (STDERR $message, "\n");
    $self->{'result'}{'response'}{'error'} = $message;
    $self->respond ();
}

1;
