#!/usr/bin/env perl
package NanoShell;
use strict;
use warnings;
use 5.14.2;

my $VERSION = 1;

say "Loading NanoShell ($VERSION)";

$SIG{__DIE__} = sub {
    say shift;
    exec("/bin/sh");
    exit 2;
};
use Sys::Hostname;
use Text::ParseWords qw(shellwords quotewords);
use base qw(Term::Shell);
use Data::Dump qw(pp);

my $rc_file = "/tmp/rc.conf";
my %config;

sub init {
    my $self = shift;
    $self->{API}->{check_idle} = 2;
}

sub run_set {
    my $self = shift;
    my @argv = @_;
    read_config();
    pp(@argv);

}

sub comp_set {
    my ($self, $comp, $line, $pos) = @_;
    $line =~ s/^set\s+//;
    my @args = $self->line_parsed($line);
    if ($line =~ m/^x/) {
        return qw(xxe xxf);
    }
    if (@args == 1 and $comp) {
        return $self->possible_actions($comp, "", 0, [qw(interface hostname)]);
    }
    elsif ($args[0] eq 'interface') {
        if (@args == 1 or (@args == 2 and $comp)) {
            return $self->possible_actions($comp, "", 0, [qw(em0 vl3)]);
        }
        if (@args == 2 or (@args == 3 and $comp)) {
            return $self->possible_actions($comp, "", 0, [qw(ip)]);
        }
    }
    return ();
}

sub run_dump {
    my $data = read_config();
    say "# =====================",
        $data,
        "# =====================";

    require Data::Dumper;
    say Data::Dumper->Dump([\%config], ['config']);

}

sub prompt_str {
    my $hostname = Sys::Hostname::hostname();
    return "$$ $hostname> ";
}

sub run_exit   { exit 0;         }
sub alias_exit { return qw(quit) }
sub run_r { exec($0); exit 1; }

sub read_config {
    open my $fh, "<", $rc_file or die "Can't open $rc_file: $!";
    my $data = "";
    while (<$fh>) {
        $data .= $_;
        chomp;
        next if m/^\s*\#/;
        next if m/^\s*$/;
        my ($key, $value) = split /\s*=\s*/, $_, 2;
        ($value) = shellwords($value);
        $config{$key} = $value;
    }
    return $data;
}

package main;

my $shell = NanoShell->new;
$shell->cmdloop;

