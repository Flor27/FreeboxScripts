#!/usr/bin/perl
$datestring = localtime();	

use lib qq(/opt/perlLib);
use Data::Dumper;
use FBOS::Client;

use POSIX qw(strftime);

use LWP::Simple;
use LWP::UserAgent;

use Data::Dumper;

my $trackerListURL = 'http://torrenttrackerlist.com/torrent-tracker-list/';

my $openTrackersFile = '/etc/opt/openBittorentServersList.txt';

my $foundTracker = 0;

my @openTrackers;

$numArgs = $#ARGV + 1;

if ($numArgs > 0) {
	eval {

		my $ua = LWP::UserAgent->new( );
		$ua->agent('Mozilla/5.0 (Windows NT 6.1; WOW64; rv:30.0) Gecko/20100101 Firefox/30.0');

		 $ua->default_header(
					'ACCEPT'                    => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
				$ua->default_header(
						'ACCEPT-ENCODING'       => 'gzip, deflate');
				$ua->default_header(
						'ACCEPT-LANGUAGE'       => 'fr,fr-FR;q=0.8,en-US;q=0.5,en;q=0.3');
				$ua->default_header(
						'CACHE-CONTROL'         => 'max-age=0');
				$ua->default_header(
						'PRAGMA'                => 'no-cache');

		my $resp = $ua->get( $trackerListURL );

		die "Unable to get the tracker page" unless $resp->is_success;

		my $content = $resp->decoded_content() ;

		$content =~ s/^.*<pre>(.*)<\/pre>.*$/\1/s;
		if( defined $content && length($content) > 0 ) {
			
			if( open($fd,'>',$openTrackersFile) ) {
				while( $content =~ /\s((udp|http)(.[^\s]*))\s/g ) {
					if(length($1)> 0) {
						print( $fd "$1\n" );
						push @openTrackers, $1;
					}
				}
				close( $fd );
			}		
		}
		return 1;
	}
	or do { return 1; };
	exit 1;
} else {
	eval {
		open my $handle, '<', $openTrackersFile;
		chomp(@openTrackers = <$handle>);
		close $handle;
	} or do {
		exit 1;
	};
}


my $fbc = new FBOS::Client("FBPerl", "FBPerlTest");

$fbc->connect();

my @hosts = ();
my $tracker = {announce => ''};
my $trackerUpdate = {announce => '', is_enabled => JSON::true};


DL_TASK: for (@{$fbc->api_dl_tasks}) { 
	# Seulement pour les Torrents
	next DL_TASK if ( $_->{type} ne 'bt' || $_->{status} eq 'done' );

	eval {
		my @trackers = @{$fbc->api_dl_task_trackers($_->{id})};

	        my @matching_items = grep {
        		$_->{announce} =~ /yourFavoriteTracker/
	        } @trackers;

	        if( scalar @matching_items < 1) {
        	        print "***************************\n\n";
                	print "Not a yourFavoriteTracker torrent : ";
	                print Dumper($_);
        	        my $id = $_->{id};
                	for my $i (0 .. @openTrackers) {
                        	if(@openTrackers[$i] && !( @openTrackers[$i] =~ /^#/) ) {
	                                $tracker->{announce} = @openTrackers[$i];
	                                $trackerUpdate->{announce} = @openTrackers[$i];
	                                eval {
	                                        my @res = $fbc->api_dl_task_add_tracker(
	                                                $id,
	                                                $tracker
	                                        ) ;
	                                        @res = $fbc->api_dl_task_update_tracker(
	                                                $id,
	                                                $trackerUpdate->{announce},
	                                                $trackerUpdate
	                                        ) ;
	                                } or do {
	                                        print "It fails to add ".@openTrackers[$i]."...\n";
	                                };
	                        }
	                }
		}
		1;
	} or do {
		print "Where is task ".$_->{id}." ??\n";
	};
}

1;


