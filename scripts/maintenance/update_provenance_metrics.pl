#!/usr/bin/env perl
#Update cache of provenance completion metrics.
#Written by Keith Jolley
#Copyright (c) 2023, University of Oxford
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
#Version: 20230301
use strict;
use warnings;
use 5.010;
###########Local configuration################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	LOCK_DIR         => '/var/run/lock'         #Override in bigsdb.conf
};
#######End Local configuration################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use BIGSdb::Constants qw(LOG_TO_SCREEN NULL_TERMS);
use Term::Cap;
use POSIX;
use Getopt::Long qw(:config no_ignore_case);
my %opts;
GetOptions(
	'database=s' => \$opts{'d'},
	'help'       => \$opts{'help'},
);

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
$log_conf =~ s/INFO/WARN/gx if $opts{'quiet'};
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
if ( $opts{'help'} || !defined $opts{'d'} ) {
	show_help();
	exit;
}
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		instance         => $opts{'d'},
		logger           => $logger,
		options          => { mark_job => 1 }
	}
);
if ( !defined $script->{'system'}->{'dbtype'} ) {
	$logger->fatal("$opts{'d'} is an invalid database configuration.");
	exit(1);
}
if ( ( $script->{'system'}->{'dbtype'} // q() ) ne 'isolates' ) {
	$logger->fatal("$opts{'d'} is not an isolate database.");
	exit(1);
}
main();
undef $script;

sub main {
	my $att    = $script->{'xmlHandler'}->get_all_field_attributes;
	my $fields = $script->{'xmlHandler'}->get_field_list( { show_hidden => 1 } );
	my @metric_fields;
	foreach my $field (@$fields) {
		next if ( $att->{$field}->{'annotation_metric'} // q() ) ne 'yes';
		push @metric_fields, $field;
	}
	my %null_terms = map { lc($_) => 1 } NULL_TERMS;
	my $table      = 'temp_provenance_completion';
	my $table_exists =
	  $script->{'datastore'}
	  ->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );
	my $create_index;
	eval {
		if ($table_exists) {
			$script->{'db'}->do("TRUNCATE $table");
		} else {
			$script->{'db'}->do("CREATE TABLE $table (id int NOT NULL,field_count int NOT NULL,PRIMARY KEY(id));");
			$create_index = 1;    #Do this after adding data otherwise as it will be quicker.
		}
		local $" = q(,);
		my $data = $script->{'datastore'}->run_query( "SELECT id,@metric_fields FROM $script->{'system'}->{'view'}",
			undef, { fetch => 'all_arrayref', slice => {} } );
		$script->{'db'}->do("COPY $table(id,field_count) FROM STDIN");
		foreach my $record (@$data) {
			my $count = 0;
			foreach my $field (@metric_fields) {
				if ( defined $record->{ lc($field) } && !$null_terms{ lc( $record->{ lc($field) } ) } ) {
					$count++;
				}
			}
			$script->{'db'}->pg_putcopydata("$record->{'id'}\t$count\n");
		}
		$script->{'db'}->pg_putcopyend;
		if ($create_index) {
			$script->{'db'}->do("CREATE INDEX ON $table(field_count)");
		}
	};
	if ($@) {
		$logger->error($@);
		$script->{'db'}->rollback;
	} else {
		$script->{'db'}->commit;
	}
	return;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t      = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}update_provenance_metrics.pl$norm - Update cache of provenance completion metrics
    
${bold}SYNOPSIS$norm
    ${bold}update_provenance_metrics.pl$norm --database ${under}DB_CONFIG$norm

Fields that have the annotation_metric attribute set to 'yes' in the database 
config.xml file will be counted in the metrics.

${bold}OPTIONS$norm

${bold}--database$norm ${under}DATABASE CONFIG$norm
    Database configuration name.
    
${bold}--help$norm
    This help page.    
HELP
	return;
}
