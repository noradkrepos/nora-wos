package NORA::WOS;

use strict;
use warnings;

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
    return (bless ($self, $class));
}

sub conf
{
    my ($self, $key) = @_;

    return ($self->{'conf'}{$key});
}

sub eta
{
    my ($self, $time) = @_;

    $time += time;
    my ($sec, $min, $hour, $day, $mon, $year) = localtime (int ($time));
    return (sprintf ('%04d-%02d-%02d %02d:%02d:%02d', 1900 + $year, $mon + 1, $day, $hour, $min, $sec));
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

sub log
{
    my ($self, $level, $msg, @args) = @_;

    my ($sec, $min, $hour, $day, $mon, $year) = localtime (time);
    printf (STDERR "%04d-%02d-%02d %02d:%02d:%02d %s $msg\n", 1900 + $year, $mon + 1, $day, $hour, $min, $sec, $level, @args);
}

1;

