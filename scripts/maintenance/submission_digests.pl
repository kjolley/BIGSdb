#!/usr/bin/env perl
#Send E-mail digests to curators summarising submissions since last digest
#Written by Keith Jolley
#Copyright (c) 2020, University of Oxford
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
#Version: 20220614
use strict;
use warnings;
use 5.010;
###########Local configuration#############################################
use constant {
	DOMAIN           => 'PubMLST',
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	USER_DATABASE    => 'pubmlst_bigsdb_users',
	SMTP_SERVER      => 'localhost',
	SMTP_PORT        => 25,
	SENDER           => 'no_reply@pubmlst.org', #Use if automated_email_address not set in bigsdb.conf
	ACCOUNT_URL => 'https://pubmlst.org/bigsdb'
};
#######End Local configuration#############################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use BIGSdb::Constants qw(LOG_TO_SCREEN);
use List::MoreUtils qw(uniq);
use Getopt::Long qw(:config no_ignore_case);
use Try::Tiny;
use Email::Sender::Transport::SMTP;
use Email::Sender::Simple qw(try_to_sendmail);
use Email::MIME;
use DBI;
binmode( STDOUT, ':encoding(UTF-8)' );

#Direct all library logging calls to screen
my $log_conf = LOG_TO_SCREEN;
Log::Log4perl->init( \$log_conf );
my $logger = Log::Log4perl::get_logger('BIGSdb.Script');
my %opts;
GetOptions( 'quiet' => \$opts{'quiet'}, 'user_database=s' => \$opts{'user_database'} )
  or die("Error in command line arguments\n");
if ( !$opts{'user_database'} ) {
	say "\nUsage: submission_digests.pl --user_database <NAME>\n";
	exit;
}
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		options          => \%opts
	}
);
die "Script initialization failed.\n" if !defined $script->{'db'};
my $is_user_db =
  $script->{'datastore'}
  ->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', 'registered_users' );
die "This script can only be run against a user database.\n"
  if !$is_user_db;
main();
undef $script;

sub main {
	clear_old_absent_until_dates();
	my $curators = get_curators();
	foreach my $curator (@$curators) {
		my $user_info = $script->{'datastore'}->get_user_info_from_username($curator);
		my $prefs     = $script->{'datastore'}
		  ->run_query( 'SELECT * FROM curator_prefs WHERE user_name=?', $curator, { fetch => 'row_hashref' } );
		next if $prefs->{'absent_until'};
		if ( $prefs->{'last_digest'} ) {
			my $digest_due = $script->{'datastore'}->run_query(
				"SELECT last_digest < now()-interval '$prefs->{'digest_interval'} minutes' "
				  . 'FROM curator_prefs WHERE user_name=?',
				$curator
			);
			next if !$digest_due;
		}
		my $digest = create_digest($curator);
		if ( !$opts{'quiet'} ) {
			say "Sending digest to $user_info->{'email'}";
			say $digest->{'content'};
			say qq(=============================\n\n);
		}
		email_digest( $curator, $digest );
		update_last_digest_time($curator);
	}
	return;
}

sub clear_old_absent_until_dates {
	eval { $script->{'db'}->do('UPDATE curator_prefs SET absent_until=NULL WHERE absent_until <= now()'); };
	if ($@) {
		$logger->error($@);
		$script->{'db'}->rollback;
	} else {
		$script->{'db'}->commit;
	}
	return;
}

sub update_last_digest_time {
	my ($curator) = @_;
	eval {
		$script->{'db'}->do( 'UPDATE curator_prefs SET last_digest=? WHERE user_name=?', undef, 'now', $curator );
		$script->{'db'}->do( 'DELETE FROM submission_digests WHERE user_name=?',         undef, $curator );
	};
	if ($@) {
		$logger->error($@);
		$script->{'db'}->rollback;
	} else {
		$script->{'db'}->commit;
	}
	return;
}

sub create_digest {
	my ($curator)   = @_;
	my $domain      = DOMAIN;
	my $digest_data = $script->{'datastore'}->run_query(
'SELECT * FROM submission_digests WHERE user_name=? ORDER BY dbase_description,submission_id,timestamp,submitter',
		$curator,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $current_db = q();
	my $buffer;
	if ( @$digest_data == 1 ) {
		$buffer = qq(The following submission has been received by $domain since your last submission digest.\n\n)
		  . qq(Please log in to the curator's interface to handle this submission.\n\n);
	} else {
		$buffer = qq(The following submissions have been received by $domain since your last submission digest.\n\n)
		  . qq(Please log in to the curator's interface to handle these submissions.\n);
	}
	my $account_url = ACCOUNT_URL;
	$buffer .= qq(You can update the frequency of digests from the account settings page ($account_url).\n);
	foreach my $submission (@$digest_data) {
		if ( $submission->{'dbase_description'} ne $current_db ) {
			$current_db = $submission->{'dbase_description'};
			$buffer .= qq(\n$current_db:\n);
		}
		$buffer .= qq(Sender: $submission->{'submitter'} - $submission->{'summary'}\n);
	}
	my $title = @$digest_data == 1 ? "New submission ($domain)" : "New submissions ($domain)";
	return { title => $title, content => $buffer };
}

sub email_digest {
	my ( $curator, $digest ) = @_;
	my $domain    = DOMAIN;
	my $user_info = $script->{'datastore'}->get_user_info_from_username($curator);
	my $transport =
	  Email::Sender::Transport::SMTP->new( { host => SMTP_SERVER // 'localhost', port => SMTP_PORT // 25 } );
	my $sender_address = $script->{'config'}->{'automated_email_address'} // SENDER;
	my $email = Email::MIME->create(
		attributes => {
			encoding => 'quoted-printable',
			charset  => 'UTF-8',
		},
		header_str => [
			To      => $user_info->{'email'},
			From    => $sender_address,
			Subject => $digest->{'title'}
		],
		body_str => $digest->{'content'}
	);
	try_to_sendmail( $email, { transport => $transport } )
	  || say "Cannot send E-mail to $user_info->{'email'}";
	sleep 5;    #Don't hammer the mail server
	return;
}

sub get_curators {
	return $script->{'datastore'}->run_query( 'SELECT DISTINCT(user_name) FROM submission_digests ORDER BY user_name',
		undef, { fetch => 'col_arrayref' } );
}
