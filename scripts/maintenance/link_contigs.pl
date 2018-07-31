#!/usr/bin/env perl
#Link remote contigs to isolate records
#Written by Keith Jolley
#Copyright (c) 2017-2018, University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#
#This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
#
#BIGSdb is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#BIGSdb is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
use strict;
use warnings;
use 5.010;
###########Local configuration################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	HOST             => 'localhost',
	PORT             => 5432,
	USER             => 'apache',
	PASSWORD         => undef
};
#######End Local configuration################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use BIGSdb::Offline::ProcessRemoteContigs;
use BIGSdb::Utils;
use Error qw(:try);
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use POSIX;
use Carp;
use List::MoreUtils qw(notall none);
use Log::Log4perl qw(get_logger);

#Direct all library logging calls to screen
my $log_conf =
    qq(log4perl.category.BIGSdb.Script        = INFO, Screen\n)
  . qq(log4perl.category.BIGSdb.Dataconnector = WARN, Screen\n)
  . qq(log4perl.category.BIGSdb.Datastore     = WARN, Screen\n)
  . qq(log4perl.appender.Screen               = Log::Log4perl::Appender::Screen\n)
  . qq(log4perl.appender.Screen.stderr        = 1\n)
  . qq(log4perl.appender.Screen.layout        = Log::Log4perl::Layout::SimpleLayout\n);
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
my %opts;
GetOptions(
	'a|append'     => \$opts{'a'},
	'c|curator=i'  => \$opts{'c'},
	'd|database=s' => \$opts{'d'},
	'i|isolate=i'  => \$opts{'i'},
	'h|help'       => \$opts{'h'},
	'p|process'    => \$opts{'p'},
	'u|uri=s'      => \$opts{'u'}
) or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( notall { $opts{$_} } (qw(c d i u)) ) {
	say "\nUsage: link_contigs.pl --database <NAME> --isolate <ID> --uri <FILE> --curator <ID>\n";
	say 'Help: link_contigs.pl --help';
	exit;
}
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		host             => HOST,
		port             => PORT,
		user             => USER,
		password         => PASSWORD,
		options          => { %opts, always_run => 1 },
		instance         => $opts{'d'},
	}
);

#Check arguments make sense
my $isolate_exists =
  $script->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM isolates WHERE id=?)', $opts{'i'} );
exit_cleanly("Isolate id-$opts{'i'} does not exist.") if !$isolate_exists;
my $seqbin_exists =
  $script->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM seqbin_stats WHERE isolate_id=?)', $opts{'i'} );
exit_cleanly("Isolate id-$opts{'i'} already has contigs uploaded.") if $seqbin_exists && !$opts{'a'};
my $curator_exists =
  $script->{'datastore'}
  ->run_query( q(SELECT EXISTS(SELECT * FROM users WHERE id=? AND status IN ('curator','admin'))), $opts{'c'} );
exit_cleanly("Curator id-$opts{'c'} does not exist (or user is not a curator).") if !$curator_exists;
main();
undef $script;
exit;

sub main {
	my $isolate_data = get_isolate_data( $opts{'u'} );
	my $contigs_list = $isolate_data->{'sequence_bin'}->{'contigs'};
	exit_cleanly('No contig link in record.') if !$contigs_list;
	my $contig_count = $isolate_data->{'sequence_bin'}->{'contig_count'};
	my $length       = BIGSdb::Utils::commify( $isolate_data->{'sequence_bin'}->{'total_length'} );
	my $plural       = $contig_count == 1 ? q() : q(s);
	print "$contig_count contig$plural; Total length: $length ...";
	my $contigs = get_contigs($contigs_list);
	my $existing =
	  $script->{'datastore'}->run_query(
		'SELECT r.uri FROM remote_contigs r INNER JOIN sequence_bin s ON r.seqbin_id=s.id AND s.isolate_id=?',
		$opts{'i'}, { fetch => 'col_arrayref' } );
	my %existing = map { $_ => 1 } @$existing;
	my $insert_sql =
	  $script->{'db'}->prepare( 'INSERT INTO sequence_bin(isolate_id,remote_contig,sequence,sender,curator,'
		  . 'date_entered,datestamp) VALUES (?,?,?,?,?,?,?) RETURNING id' );
	my $insert_remote_sql = $script->{'db'}->prepare('INSERT INTO remote_contigs (seqbin_id,uri) VALUES (?,?)');
	eval {
		$script->{'db'}->do('ALTER TABLE sequence_bin DISABLE TRIGGER check_sequence_bin');

		foreach my $contig (@$contigs) {
			next if $existing{$contig};    #Don't add duplicates
			$insert_sql->execute( $opts{'i'}, 'true', '', $opts{'c'}, $opts{'c'}, 'now', 'now' );
			my ($seqbin_id) = $insert_sql->fetchrow_array;
			$insert_remote_sql->execute( $seqbin_id, $contig );
		}
		$script->{'db'}->do('ALTER TABLE sequence_bin ENABLE TRIGGER check_sequence_bin');
	};
	if ($@) {
		say q(failed!);
		$logger->error($@);
		$script->{'db'}->rollback;
		exit_cleanly('Contig upload failed.');
	}
	say q(done.);
	$script->{'db'}->commit;
	process( $opts{'i'} ) if $opts{'p'};
	return;
}

sub process {
	my ($isolate_id) = @_;
	say q(Processing contigs:);
	my $processor = BIGSdb::Offline::ProcessRemoteContigs->new(
		{
			config_dir       => CONFIG_DIR,
			lib_dir          => LIB_DIR,
			dbase_config_dir => DBASE_CONFIG_DIR,
			host             => HOST,
			port             => PORT,
			user             => USER,
			password         => PASSWORD,
			options          => {
				always_run => 1,
				i          => $isolate_id
			},
			instance => $opts{'d'},
			logger   => $logger
		}
	);
	say q(Done.);
	return;
}

sub get_isolate_data {
	my ($isolate_uri) = @_;
	if ( $isolate_uri !~ /\/isolates\/\d+$/x ) {
		exit_cleanly('URI is not in valid format (http://base_uri/{db}/isolates/{id})');
	}
	my $isolate_data;
	my $err;
	try {
		$isolate_data = $script->{'contigManager'}->get_remote_isolate($isolate_uri);
	}
	catch BIGSdb::AuthenticationException with {
		$err = q(Failed - check OAuth authentication settings.);
	}
	catch BIGSdb::FileException with {
		$err = q(Failed - URI is inaccesible.);
	}
	catch BIGSdb::DataException with {
		$err = q(Failed - Returned data is not in valid format.);
	};
	if ($err) {
		exit_cleanly($err);
	}
	return $isolate_data;
}

sub get_contigs {
	my ($contigs_list) = @_;
	my $data;
	my $err;
	my $all_records;
	do {
		try {
			$data = $script->{'contigManager'}->get_remote_contig_list($contigs_list);
		}
		catch BIGSdb::AuthenticationException with {
			$err = q(OAuth authentication failed.);
		}
		catch BIGSdb::FileException with {
			$err = q(URI is inaccessible.);
		}
		catch BIGSdb::DataException with {
			$err = q(Contigs list is not valid JSON.);
		};
		if ( $data->{'paging'} ) {
			$contigs_list = $data->{'paging'}->{'return_all'};
		} else {
			$all_records = 1;
		}
	} until ( $err || $all_records );
	if ($err) {
		exit_cleanly($err);
	}
	my $contigs = $data->{'contigs'};
	return $contigs;
}

sub exit_cleanly {
	my ($msg) = @_;
	undef $script;
	die "$msg\n";
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}link_contigs.pl$norm - Link contigs to BIGSdb isolate database via API

${bold}SYNOPSIS$norm
    ${bold}link_contigs.pl --database ${under}NAME$norm ${bold}--isolate ${under}ID${norm} ${bold}--uri ${under}URI$norm 
          ${bold}--curator ${under}ID$norm [${under}OPTIONS$norm]

${bold}OPTIONS$norm
${bold}-a, --append$norm
    Upload contigs even if isolate already has sequences in the bin.
    
${bold}-c, --curator$norm ${under}ID$norm  
    Curator id number. 
    
${bold}-d, --database$norm ${under}NAME$norm
    Database configuration name.
    
${bold}-h, --help$norm
    This help page.

${bold}-i, --isolate$norm ${under}ID$norm  
    Isolate id of record to upload to.  
    
${bold}-p, --process$norm
    Download each contig to update metadata and generate checksums.
    This will take much longer and is not strictly necessary to start using
    the contigs. It will enable the system to determine if the remote sequences
    ever change or you need information about the sequencing technology used to
    generate the contigs. 
     
${bold}-u, --uri$norm ${under}URI$norm  
    URI to the REST API record for the isolate whose contigs 
    are to be imported.           
HELP
	return;
}
