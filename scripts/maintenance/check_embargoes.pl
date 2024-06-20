#!/usr/bin/env perl
#Publish embargoed records when embargo date is reached
#Notify users of embargoed records and when they are published.
#Written by Keith Jolley
#Copyright (c) 2024, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
#
#Version: 20240619
use strict;
use warnings;
use 5.010;
###########Local configuration################################
#Define database passwords in .pgpass file in user directory
#See PostgreSQL documentation for details.
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases'
};
#######End Local configuration################################
use lib (LIB_DIR);
use Term::Cap;
use POSIX;
use BIGSdb::Offline::Script;
use BIGSdb::Constants qw(LOG_TO_SCREEN);
use Getopt::Long qw(:config no_ignore_case);
my %opts;
GetOptions(
	'database=s' => \$opts{'d'},
	'exclude=s'  => \$opts{'exclude'},
	'help'       => \$opts{'help'},
	'quiet'      => \$opts{'quiet'}
);

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
$log_conf =~ s/INFO/WARN/gx if $opts{'quiet'};
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
if ( $opts{'help'} ) {
	show_help();
	exit;
}
main();

sub main {
	binmode( STDOUT, ':encoding(UTF-8)' );
	if ( $opts{'d'} ) {
		check_db( $opts{'d'} );
		return;
	}
	my $dbs = get_dbs();
	foreach my $db (@$dbs) {
		check_db($db);
	}
	return;
}

sub check_db {
	my ($config) = @_;
	my $script = BIGSdb::Offline::Script->new(
		{
			config_dir       => CONFIG_DIR,
			lib_dir          => LIB_DIR,
			dbase_config_dir => DBASE_CONFIG_DIR,
			instance         => $config,
			logger           => $logger,
		}
	);
	if ( ( $script->{'system'}->{'dbtype'} // q() ) ne 'isolates' ) {
		$logger->error("$config is not an isolate database.");
		return;
	}
	my $embargo_attributes = $script->{'datastore'}->get_embargo_attributes;
	return if !$embargo_attributes->{'embargo_enabled'};
	return
	  if !$script->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM private_isolates WHERE embargo IS NOT NULL)');
	print qq(\nChecking $config ... ) if !$opts{'quiet'};
	my $to_make_public = $script->{'datastore'}->run_query(
		"SELECT p.isolate_id,i.$script->{'system'}->{'labelfield'} AS name,p.user_id "
		  . 'FROM private_isolates p JOIN isolates i ON p.isolate_id=i.id WHERE p.embargo<=? '
		  . 'ORDER BY p.user_id,p.isolate_id',
		'now',
		{ fetch => 'all_arrayref', slice => {} }
	);
	if ( !@$to_make_public ) {
		say q(done (no action)) if !$opts{'quiet'};
		return;
	}
	my $count  = @$to_make_public;
	my $plural = $count > 1 ? q(s) : q();
	say qq(making $count record$plural public:);
	my $current_user;
	eval {
		foreach my $record (@$to_make_public) {
			if ( !defined $current_user || $record->{'user_id'} != $current_user ) {
				my $user_string = $script->{'datastore'}->get_user_string( $record->{'user_id'}, { affiliation => 1 } );
				say qq(\t$user_string:);
			}
			say qq[\t\tid-$record->{'isolate_id'}) $record->{'name'}];
			$script->{'db'}->do( 'DELETE FROM private_isolates WHERE isolate_id=?', undef, $record->{'isolate_id'} );
			$script->{'db'}->do(
				'INSERT INTO embargo_history (isolate_id,timestamp,action,embargo,curator) VALUES (?,?,?,?,?)',
				undef, $record->{'isolate_id'},
				'now', 'Record made public (embargo date reached)',
				undef, 0
			);
		}
	};
	if ($@) {
		$script->{'db'}->rollback;
		die "$@\n";
	}
	$script->{'db'}->commit;
	return;
}

sub get_dbs {
	opendir( DIR, DBASE_CONFIG_DIR ) or die "Unable to open dbase config directory! $!\n";
	my $config_dir  = DBASE_CONFIG_DIR;
	my @config_dirs = readdir(DIR);
	closedir DIR;
	my $configs = [];
	my %exclude = map { $_ => 1 } split /,/x, ( $opts{'exclude'} // q() );
	print 'Retrieving list of isolate databases ... ' if !$opts{'quiet'};
	foreach my $dir ( sort @config_dirs ) {
		next if !-e "$config_dir/$dir/config.xml" || -l "$config_dir/$dir/config.xml";
		my $script = BIGSdb::Offline::Script->new(
			{
				config_dir       => CONFIG_DIR,
				lib_dir          => LIB_DIR,
				dbase_config_dir => DBASE_CONFIG_DIR,
				instance         => $dir,
				logger           => $logger,
				options          => {}
			}
		);
		next if ( $script->{'system'}->{'dbtype'} // q() ) ne 'isolates';
		if ( !$script->{'db'} ) {
			$logger->error("Skipping $dir ... database does not exist.");
			next;
		}
		next if $exclude{$dir};
		push @$configs, $dir;
	}
	say scalar @$configs . ' found.' if !$opts{'quiet'};
	return $configs;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}check_embargoes.pl$norm - Publish records when embargo date reached.

${bold}SYNOPSIS$norm
    ${bold}check_embargoes.pl$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--database$norm ${under}DATABASE CONFIG$norm
    Database configuration name. If not included then all isolate databases
    defined on the system will be checked.
    
${bold}--exclude$norm ${under}CONFIG NAMES $norm
    Comma-separated list of config names to exclude.
    
${bold}--help$norm
    This help page.
    
${bold}--quiet$norm
    Only show errors.
HELP
	return;
}

