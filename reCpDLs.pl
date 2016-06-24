#!/usr/bin/perl
#print "[".localtime."]begin...\n";

# où se trouve votre module FBOS
use lib qq(/opt/perlLib);

use FBOS::Client;

use Data::Dumper;

use Term::Menus;

# Pour la persistance des données
use Storable qw(lock_store lock_nstore lock_retrieve);

# L'api Freebox OS encode les chemins en Base64
use MIME::Base64 qw/ encode_base64 decode_base64 /;
 
# Le fichier pour la persistance des données
my $storageFile = '/etc/opt/cpDLs.files';


my $SourcePartition = 'Disque dur';
my $DestPartition = 'KTINYXT4';
			   
my $SourceDir = 'Téléchargements';
my $DestDir = 'Téléchargements';

my $copyMode = 'overwrite';

my $copyConfig = {
	files => [ ],
	dst => '',
	mode => $copyMode
};

my $copiedFiles;

my $foundSource = 0;
my $foundDest = 0;
my $mountedState = {state=>'mounted'};
my $unmountedState = {state=>'umounted'};
my $ret;

my $checkingNbr = 0;

my $dismountDestDisk = 0;

my $letsCopy = 0;

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
				print "disk '$disk' is mounted.\n";
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

$copyConfig->{dst} = encode_base64("/$DestPartition/$DestDir",'');

my $doneFiles = [];


DL_TASK: for(@{$fbc->api_dl_tasks()}) {
	my $dlTask = $_;
	#Ne copie que les tâches terminées
	next DL_TASK if ! ($dlTask->{status} eq 'seeding' || $dlTask->{status} eq 'done') ;
	
	# Cas de un seul fichier à télécharger
	if( $dlTask->{download_dir} eq encode_base64("/$SourcePartition/$SourceDir/",'') ) {
	
		my $dlFile = encode_base64("/$SourcePartition/$SourceDir/".${$fbc->api_dl_task_files($dlTask->{id})}[0]->{name},'');
		push $doneFiles, $dlFile;
	}
	# Cas d'un dossier
	else {
		push $doneFiles, encode_base64(
			(substr decode_base64($dlTask->{download_dir}), 0, -1)
		,'');
	}
}

my $filesToCopy;
my @uniques;

my @decodedDoneFIles = map{ decode_base64($_) } @$doneFiles;

if( scalar @$doneFiles > 0 ) {

%Menu_1 = (

  Label   => 'Menu_1',

  Item_1  => {

    Text    =>      "]Convey[",
    Convey  =>      \@decodedDoneFIles,
                         # normally would be a handle
                         # exp: $ftp_remote->cmd('ls -1')
#    Include  =>       qr/$filter/,
    Default  =>       '',

  },

  Select  => 'Many',

  Banner  => '   Sélectionner les fichiers à copier à nouveau :',

);

	my @fichiersChoisis = map{encode_base64($_,'') } Menu(\%Menu_1);
	
	$filesToCopy = \@fichiersChoisis;

	if(  scalar @{$filesToCopy} > 0) {
		$letsCopy = 1;
	} 
}
	
$| = 1;

#$letsCopy = 0;

if(! $letsCopy ) {
	#On démonte les partitions
	if( $dismountDestDisk > 0 ) {
		dismountPartitions($DestPartition);
	}
	print "\n[".localtime. "] Nothing to copy, Dave.";
	exit 1;
}

$foundDest = checkDisks($DestPartition, $DestDir);

if( $foundDest ne 1 ) {
	print "\n[".localtime. "] I am sorry Dave, there is no DestPartition '/$DestPartition/$DestDir'.\n\n" ;
	exit 1;
}

sub copyFile {
	my ($subCopyConfig, $fileToCopy) = @_;

	my $taskId = -1;

	push $subCopyConfig->{files} = [$fileToCopy];
	print "\n[".localtime. "] Trying to copy '". decode_base64($fileToCopy)."'...";
	eval {
        	$ret = $fbc->api_fs_cp( $subCopyConfig );
        	$taskId = $ret->{id};
	} or do {
        print "\n[".localtime. "] I am sorry Dave, copy hasn't worked with '". decode_base64($fileToCopy)."'...\n";
		print Dumper $fbc->get_error_code();
		print Dumper $fbc->api_fs_task( $ret->{id} );
		exit 1;
	};
	## Attente de la fin de la tâche... 
	do {
		$ret = $fbc->api_fs_task( $taskId );
		print "\r".$ret->{progress}.' '.$ret->{nfiles}.'/'.$ret->{nfiles_done}.' | '. sprintf("%.2f",$ret->{rate}/1024).'kB/s => '.$ret->{to};
		sleep(3);
	} while( $ret->{state} eq 'running' || $ret->{state} eq 'queued' );
	print " done.\n";
	if($taskId > 0) {
		$fbc->api_fs_task_delete($taskId);
	}
}

my $alreadyCopiedFiles;


for( @$filesToCopy ) {
	$copyConfig->{files} = [];
	copyFile( $copyConfig, $_ );
	eval {
		$alreadyCopiedFiles = lock_retrieve($storageFile);
	} or do {
		$alreadyCopiedFiles = [];
	};

	@uniques = unique(@$alreadyCopiedFiles);
	$alreadyCopiedFiles = \@uniques;	
	
	push $alreadyCopiedFiles, $_;
	lock_store $alreadyCopiedFiles, $storageFile;
}


#On démonte les partitions
if( $dismountDestDisk > 0 ) {
	dismountPartitions($DestPartition);
}

print "\n[".localtime. "] All copied !\n\n";

1;

