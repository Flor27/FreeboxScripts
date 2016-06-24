#!/usr/bin/perl
$datestring = localtime();	

use lib qq(/opt/perlLib);
use Data::Dumper;
use FBOS::Client;
use Template;


my $template =Template->new({
	INCLUDE_PATH=>'/etc/powerdns/bind',
	OUTPUT_PATH=>'/etc/powerdns/bind',
});


my $fbc = new FBOS::Client("FBPerl", "FBPerlTest");

$fbc->connect();

my @hosts = ();

for (@{$fbc->api_dhcp_static_lease}) { 
	my $hostname = lc $_->{hostname} =~ s/ /-/gr;
	print "$_->{id} => $hostname / $_->{ip}\n";
	if ($hostname =~ /^(.*)-\((.*)\)/) {
		$hostname =~ s/^(.*)-\((.*)\)/\1-\2/;
	}
	$hostname =~ s/-eth//;
	
	my $host = {
		'HOSTNAME' => $hostname ,
		'FULLIP'=>$_->{ip},
		'SUBIP'=> $_->{ip} =~ /\.(\d+)$/
	};
	
	push @hosts, $host;
}

my %vars1 = (
	creationDate => $datestring,
	hosts  => \@hosts
);

$template->process('yyy.zzz.zone.template', \%vars1, 'yyy.zzz.zone') or die $template->error;
$template->process('x.xxx.xxx.in-addr.arpa.template', \%vars1, 'x.xxx.xxx.in-addr.arpa') or die $template->error;


