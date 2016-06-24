#!/usr/bin/perl
use strict;
use warnings;
use Data::Dumper;

use lib qq(/opt/perlLib);
use FBOS::Client;

use Storable qw(lock_store lock_nstore lock_retrieve);
use MIME::Base64 qw/ encode_base64 decode_base64 /;

use MIME::Lite;

sub unique  { %_=(),grep(!$_{$_}++,@_) }

my $storageFile = '/etc/opt/checkIntruder.files';

# Instanciation client FBOS
my $fbc = new FBOS::Client("FBPerl", "FBPerlTest");

eval {
	$fbc->connect();
} or do {
	print "\n[".localtime. "] I'm sorry Dave, I can't connect to the Freebox Server.\n";
	exit 1;
};

my $connectedHosts = [];
for (@{$fbc->api_lan_browser('pub')}) { 
	if($_->{active} eq 1) {
		push $connectedHosts, $_;
	}
}

my $staticHosts = [];
for (@{$fbc->api_dhcp_static_lease}) { 
	push $staticHosts, $_;
}

my %connectedHosts = map{ $_->{l2ident}->{id} => $_ } @$connectedHosts;
my %staticHosts = map{$_->{mac}=>1} @$staticHosts;

my @unknowHosts = grep(!defined $staticHosts{ $_->{l2ident}->{id} }, @$connectedHosts);



my $intruders;
my $intrudersFile;

my $letsAlert = 0;

eval { 
	if( scalar @unknowHosts > 0 ) {
		eval { 
			$intrudersFile = lock_retrieve($storageFile);
		} or do {
			$intrudersFile = [];
		};

		if( ! scalar @{$intrudersFile} ) {
			$letsAlert = 1;
			$intruders = \@unknowHosts;
		} else {
			my %intrudersFile = map{$_->{l2ident}->{id}=>1} @$intrudersFile;
			my @notYetIntruder = grep(!defined $intrudersFile{ $_->{l2ident}->{id} }, @unknowHosts);

			if( scalar @notYetIntruder > 0) {
				$letsAlert = 1;
				$intruders = \@notYetIntruder;
			}		
		}
	}
} ;


if ($letsAlert) {

	my $to = 'to@email';
	my $from = 'from@email';
	my $subject = 'Mail Subject';
	my $message = "Unknow host(s) !\n\n";
	$message .= sprintf Dumper(@unknowHosts);
	
	my $msg = MIME::Lite->new(
					 From     => $from,
					 To       => $to,
					 Subject  => $subject,
					 Data     => $message
					 );
					 
	#$msg->send;
	
	$msg->send('smtp', "smtp.free.fr"); 
	### If you need SMTP authentication :
	#, AuthUser=>'user', AuthPass=>'password' );

	print "Email Sent Successfully\n";
	
	my @intruders = unique(@$intruders);
	$intruders = \@intruders;
	
	lock_store $intruders, $storageFile;
}
else {
	print "Nothing to do, Sir.";
}

1;
