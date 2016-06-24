#!/usr/bin/perl

# où se trouve votre module FBOS
use lib qq(/opt/perlLib);

use DateTime qw( );

use FBOS::Client;

use Data::Dumper;

use Term::Menus;


# L'api Freebox OS encode les chemins en Base64
use MIME::Base64 qw/ encode_base64 decode_base64 /;


my $SourcePartition = 'Disque dur';

my $SourceDir = 'Téléchargements';

my $foundSource = 0;
my $mountedState = {state=>'mounted'};
my $unmountedState = {state=>'umounted'};
my $ret;

my $checkingNbr = 0;

$| = 1;

sub unique  { %_=(),grep(!$_{$_}++,@_) }

# Instanciation client FBOS
my $fbc = new FBOS::Client("FBPerl", "FBPerlTest");

sub checkDisks {
        my($disk,$dir,$checkingNbr) = @_;
        my $found = 0;
        if(! defined $checkingNbr) {
                $checkingNbr = 0;
        }

        $checkingNbr ++;
        if($checkingNbr > 3) {
                return 0;
        }

        for (@{$fbc->api_storage_partitions()}) {
                if($_->{label} eq $disk) {
                        if($_->{state} ne 'mounted') {
                                print "Disk '$disk' not mounted, trying to...\n";
                                $ret = $fbc->api_storage_update_partition($_->{id},$mountedState);
                                sleep(3);
                                return checkDisks($disk,$dir,$checkingNbr);
                        }
                        else {
                                #print "disk '$disk' is mounted.\n";
                        }

                        eval {
                                $ret = $fbc->api_fs_info(encode_base64("$disk/$dir",'')) ;
                                $found = 1;
                        };
                        return $found;
                }
        }
        return $found;
}

sub dismountPartitions {
        my ($partition) = @_;
        my $found;
        for (@{$fbc->api_storage_disks()}) {
                undef $found ;
                if($_->{type} eq 'usb') {

                        my @aoaoh = @{$_->{partitions}};
                        my ($found) = grep { $_->{label} eq $partition } @aoaoh;

                        if(defined $found ) {
                                for(@{$_->{partitions}}) {
                                        $fbc->api_storage_update_partition($_->{id}, $unmountedState);
                                }
                                undef $found;
                        }
                }
        }
}


eval {
        $fbc->connect();
} or do {
        print "\n[".localtime. "] I'm sorry Dave, I can't connect to the Freebox Server.\n";
        exit 1;
};


$foundSource = checkDisks($SourcePartition, $SourceDir);

if( $foundSource ne 1 ) {
        print "\n[".localtime. "] I am sorry Dave, there is no SourcePartition '/$SourcePartition/$SourceDir'.\n\n" ;
        exit 1;
}


my $doneFiles = [];


my $dtTo = DateTime->now( time_zone => 'local' );

DL_TASK: for(@{$fbc->api_dl_tasks()}) {
        my $dlTask = $_;
        #Ne copie que les tâches terminées
        next DL_TASK if ! ($dlTask->{status} eq 'seeding' || $dlTask->{status} eq 'done') ;

        if( $dlTask->{download_dir} ne encode_base64("/$SourcePartition/$SourceDir/",'') ) {
                $dlTask->{name} = '/'. $dlTask->{name};
        }
        my $dtFrom = DateTime->from_epoch( epoch => $dlTask->{created_ts}, time_zone => 'local' );

        $dlTask->{ms} = $dtTo->delta_ms($dtFrom)->in_units( 'minutes' );
        eval {
                $dlTask->{upRate} = $dlTask->{tx_bytes} / ($dlTask->{ms}*60);
        } or do {
                $dlTask->{upRate} = 0;
        };
        push $doneFiles, $dlTask;
}

my @sorted =  sort { $a->{upRate} <=> $b->{upRate} } @$doneFiles;

for(@sorted) {
    print sprintf("%10.2f",$_->{upRate}/1024)." KB/s => ". $_->{name}."\n";
}

1;
