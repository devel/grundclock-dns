#!/usr/bin/env perl
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
use Text::ParseWords qw(shellwords);
use Term::Shell::MultiCmd;
use Sys::HostIP qw(interfaces);
use Net::IP;
use Data::Dump qw(pp);

my $rc_file = "/tmp/rc.conf";

# defaults
my %config = (
    # ifconfig_em0="DHCP"
    # ifconfig_em0_ipv6="inet6 accept_rtadv"
    'sshd_enable' => 'YES',
    'ntpd_enable' => 'YES',
    'dumpdev'     => 'NO',
);

my $interfaces = interfaces();

pp($interfaces);

my @cmds = (
    'hostname' => {
        help => 'set hostname',
        exec => sub {
            my ($o, %p) = @_;
            read_config();
            $config{hostname} = $p{ARGV}[0];
            say qq[Hostname set to "$config{hostname}"];
            system('hostname', $config{hostname});
            save_config();
          }
    },
    'show config' => {
        help => 'show configuration',
        opts => 'dump',
        exec => sub {
            my ($o, %p) = @_;
            my $data = read_config();
            if ($p{dump}) {
                say $data;
                require Data::Dumper;
                say Data::Dumper->Dump([\%config], ['config']);
                return;
            }
            for my $k (sort keys %config) {
                printf "%-20s : %s\n", $k, $config{$k};
            }
        } 
    },
    'interface' => 'Configure interfaces',
    'z' => {
        help => 'restart shell',
        exec => sub { exec($0); exit 1; }
    }
);

my $_set_ip_fn = sub {
    my ($if, $ipv) = @_;
    return sub {
        my ($o, %p) = @_;
        read_config();
        say "configuring ", pp(\%p);
        my $ip     = $p{ARGV}[0];
        my $rc_key = "ifconfig_$if";
        if ($ipv == 6) {
            $rc_key .= "_ipv6";
        }
        if (!$ip) {
            if (exists $config{$rc_key}) {
                say "Removing ip from $if";
                delete $config{$rc_key};
            }
        }
        else {
            $ip =~ s!/(\d+)$!!;
            my $netmask = $1;
            if (!$netmask) {
                say "Netmask (/24, /64, etc) required";
                return;
            }
            $ip = Net::IP->new($ip);
            if (!$ip) {
                say "Invalid IP address: ", Net::IP::Error();
                return;
            }
            if ($ip->version != $ipv) {
                say "Not an ipv$ipv address";
                return;
            }
            if ( ($ipv == 4 and ($netmask > 32 or $netmask < 8))
                 or ($ipv == 6 and ($netmask > 128 or $netmask < 32))
                ) {
                say "Invalid netmask: $netmask";
                return;
            }
            $config{$rc_key} = "inet" . ($ipv == 6 ? '6' : '') . ' ' . $ip->short . "/$netmask";
        }
        save_config();
    }
};

for my $if (keys %$interfaces) {
    push @cmds,
      "interface $if"    => "configure $if (ip, ipv6, etc)",
      "interface $if ip" => {
        help => 'set ip address',
        opts => 'alias=i',
        exec => $_set_ip_fn->($if, 4)
      },
      "interface $if ipv6" => {
        help => 'set ipv6 address',
        opts => 'alias=i',
        exec => $_set_ip_fn->($if, 6)
      };
}

my $hostname = Sys::Hostname::hostname();

my $shell = Term::Shell::MultiCmd->new(
   -root_cmd => 'root',
   -prompt => sub {
       return "$$ $hostname> ";
   }                           
)->populate(@cmds);
$shell->cmd('show config');
$shell->loop;

sub save_config {
    return unless %config;
    open my $fh, ">", "$rc_file.tmp" or die "Can't open $rc_file.tmp: $!";

    print $fh "# Maintained by NanoShell, don't edit by hand\n",
        "# Put manual additions/overrides in rc.conf.local\n";

    for my $k (sort keys %config) {
        printf $fh qq[%s="%s"\n], $k, $config{$k};
    }

    close $fh or die "Could not close $rc_file.tmp: $!";
    rename "$rc_file.tmp", $rc_file or die "Could not rename to $rc_file: $!";
};

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

