package NORA::WOS;

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);

our $VERSION = '0.01';

sub new
{
    my ($class) = @_;

    my $self = {};
    if (open (my $fin, '/etc/nora-wos/conf.tab')) {
        while (<$fin>) {
            chomp;
            my ($key, $val) = split (' ', $_, 2);
            $self->{'conf'}{$key} = $val;
        }
        close ($fin);
    } else {
        die ("fatal: failed to open /etc/nora-wos/conf.tab for reading: $!\n");
    }
    $self->{'field-variant'} = {
        language => [
            'static_data/fullrecord_metadata/normalized_languages/language[type=primary]/content',
            'static_data/fullrecord_metadata/languages/language[type=primary]/content',
            'static_data/fullrecord_metadata/normalized_languages[]/language/content',
            'static_data/fullrecord_metadata/languages/language[]/content',
        ],
    };
    return (bless ($self, $class));
}

sub conf
{
    my ($self, $key) = @_;

    return ($self->{'conf'}{$key});
}

sub stat_start
{
    my ($self, $name) = @_;

    $self->{'stat'}{$name} = time;
}

sub stat_time
{
    my ($self, $name) = @_;

    return (time - $self->{'stat'}{$name});
}

sub stat_display_time
{
    my ($self, $name) = @_;

    return ($self->display_time (time - $self->{'stat'}{$name}));
}

sub display_time
{
    my ($self, $sec) = @_;

    my $hour = int ($sec / 3600);
    $sec = ($sec % 3600);
    my $min = int ($sec / 60);
    $sec = ($sec % 60);
    if ($hour) {
        return (sprintf ('%d:%2d:%02d', $hour, $min, $sec));
    } else {
        return (sprintf ('%2d:%02d', $min, $sec));
    }
}

sub counter
{
    my ($self, $name, $inc) = @_;

    if (!exists ($self->{'counter'}{$name})) {
        $self->{'counter'}{$name} = 0;
    }
    if ($inc) {
        if ($inc eq 'reset') {
            $self->{'counter'}{$name} = 0;
        } else {
            $self->{'counter'}{$name} += $inc;
        }
    }
    return ($self->{'counter'}{$name});
}

sub eta
{
    my ($self, $time) = @_;

    $time += time;
    my ($sec, $min, $hour, $day, $mon, $year) = localtime (int ($time));
    return (sprintf ('%04d-%02d-%02d %02d:%02d:%02d', 1900 + $year, $mon + 1, $day, $hour, $min, $sec));
}

sub date
{
    my ($self, $time) = @_;

    if (!$time) {
        $time = time;
    }
    my ($sec, $min, $hour, $day, $mon, $year) = localtime ($time);
    return (sprintf ('%04d-%02d-%02d', 1900 + $year, $mon + 1, $day));
}

sub search_key
{
    my ($self, @fld) = @_;

    my $words = {};
    foreach my $f (@fld) {
        $f =~ s/[^0-9A-Za-z\.]+/ /g;
        $f =~ s/([0-9])\.([0-9])/$1-$2/g;
        $f =~ s/[\.\s]+/ /g;
        $f =~ s/-/./g;
        $f =~ s/^\s//;
        $f =~ s/\s$//;
        foreach my $w (split (' ', lc ($f))) {
            $words->{$w} = 1;
        }
    }
    return (sort (keys (%{$words})));
}

sub field
{
    my ($self, $id, $rec, $path, $filter) = @_;

    if ($filter) {
        if (ref ($rec) ne 'HASH') {
            $self->log ('e', '%s: not a HASH for filter %s: %s', $id, $filter, $path);
            return (undef);
        }
        my ($fld, $val) = split ('=', $filter);
        if (!exists ($rec->{$fld})) {
            return (undef);
        }
        if (($val) && ($rec->{$fld} ne $val)) {
            return (undef);
        }
    }
    my @path = split ('/', $path);
    my $e;
    while ($e = shift (@path)) {
        if (ref ($rec) ne 'HASH') {
            $self->log ('e', '%s: not a HASH for %s: %s', $id, $e, $path);
            return (undef);
        }
        if ($e =~ s/\]$//) {
            my @val = ();
            my ($fld, $flt) = split (/\[/, $e);
            if (!exists ($rec->{$fld})) {
                return ();
            }
            if (ref ($rec->{$fld}) eq 'HASH') {
                $rec->{$fld} = [$rec->{$fld}];
            }
            if (ref ($rec->{$fld}) eq 'ARRAY') {
                foreach my $rc (@{$rec->{$fld}}) {
                    if (($flt) || (@path)) {
                        my @res = $self->field ($id, $rc, join ('/', @path), $flt);
                        if (@res) {
                            push (@val, @res);
                        }
                    } else {
                        if ($rc) {
                            push (@val, $rc);
                        }
                    }
                }
            } else {
                if ((ref ($rec->{$fld}) eq '') && (!$flt)) {
                    push (@val, $rec->{$fld});
                } else {
                    $self->log ('e', '%s: not an ARRAY for %s: %s - %s', $id, $fld, $path, ref ($rec->{$fld}));
                    return (undef);
                }
            }
            return (@val);
        } else {
            if (exists ($rec->{$e})) {
                $rec = $rec->{$e}
            } else {
                return ();
            }
        }
    }
    return ($rec);
}

sub field_map
{
    my ($self, $name, $key, $value) = @_;

    if (!defined ($key)) {
        $self->{'field_map'}{$name} = {};
        return ($self->{'field_map'}{$name});
    }
    if (!exists ($self->{'field_map'}{$name})) {
        $self->log ('w', 'using undefined file_map: %s', $key);
        $self->{'field_map'}{$name} = {};
    }
    if (defined ($name)) {
        $self->{'field_map'}{$name}{$key} = $name;
    }
    return ($self->{'field_map'}{$name}{$key});
}

sub key_id
{
    my ($self, $name) = @_;

    $name = lc ($name);
    $name =~ s/[^[:alnum:]]+/ /g;
    $name =~ s/^\s//;
    $name =~ s/\s$//;
    my $md5 = $name;
    utf8::encode($md5);
    return ($name, md5_hex ($md5));
}

sub field_variant
{
    my ($self, $id, $rec, $name) = @_;

    if (!exists ($self->{'field-variant'}{$name})) {
        $self->log ('f', '%s: field variant not defined: %s', $id, $name);
        exit (1);
    }
    my @val = ();
    foreach my $path (@{$self->{'field-variant'}{$name}}) {
        if (@val = $self->field ($id, $rec, $path)) {
#           $self->log ('d', '"%s" got: "%s"', $path, join (';; ', @val));
            return (@val);
        }
#       $self->log ('d', '"%s" got: null', $path);
    }
    return (undef);
}

sub country_code
{
    my ($self, $name) = @_;

    if (!exists ($self->{'country-code'})) {
        if (!-e '/etc/nora-wos/countries.tsv') {
            $self->log ('f', 'missing country mapping: /etc/nora-wos/countries.tsv');
            exit (1);
        }
        if (open (my $fin, '/etc/nora-wos/countries.tsv')) {
            $self->{'country-code'} = {};
            while (<$fin>) {
                chomp;
                my ($key, $code) = split ("\t");
                $self->{'country-code'}{$key} = $code;
            }
            close ($fin);
        } else {
            $self->log ('f', 'failed to open /etc/nora-wos/countries.tsv for reading: %s', $!);
            exit (1);
        }
    }
    my ($key) = $self->key_id ($name);
    if ($self->{'country-code'}{$key}) {
        return ($self->{'country-code'}{$key});
    } else {
        $self->log ('w', 'missing country mapping for "%s" (%s)', $name, $key);
        return ('');
    }
}

sub log
{
    my ($self, $level, $msg, @args) = @_;

    my ($sec, $min, $hour, $day, $mon, $year) = localtime (time);
    printf (STDERR "%04d-%02d-%02d %02d:%02d:%02d %s $msg\n", 1900 + $year, $mon + 1, $day, $hour, $min, $sec, $level, @args);
}

1;

