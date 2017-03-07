#!/usr/bin/perl
#Send E-mail reminders to curators about pending submissions
#Written by Keith Jolley
#Copyright (c) 2016-2017, University of Oxford
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
use Carp;
use DBI;
use DateTime;
use Email::Sender::Transport::SMTP;
use Email::Sender::Simple qw(try_to_sendmail);
use Email::MIME;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use 5.010;
###########Local configuration################################
#Define database passwords in .pgpass file in user directory
#See PostgreSQL documentation for details.
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	USER             => 'apache',
	DOMAIN           => 'PubMLST',
	SMTP_SERVER      => '127.0.0.1',
	SMTP_PORT        => 25,
	SENDER           => 'no_reply@pubmlst.org',

	#Only remind about submissions last updated earlier than
	AGE => 7
};
#######End Local configuration################################
my %opts;
GetOptions( 'q|quiet' => \$opts{'q'}, 'h|help' => \$opts{'h'}, 't|test' => \$opts{'t'} )
  or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
main();

#This must be run on the server hosting the databases
#TODO Enable this to run on remote server, respecting the db.conf settings.
sub main {
	binmode( STDOUT, ':encoding(UTF-8)' );
	my $dbases         = get_databases_with_submissions();
	my $name_by_email  = {};
	my $dbase_by_email = {};
	my $ids_by_email   = {};
	foreach my $db_name ( sort { $dbases->{$a}->{'description'} cmp $dbases->{$b}->{'description'} } keys %$dbases ) {
		my ( $curators, $ids ) = get_curators( $dbases->{$db_name} );
		$ids_by_email->{$db_name} = $ids;
		foreach my $curator (@$curators) {
			$curator->{'email'} = lc( $curator->{'email'} );
			next if $curator->{'email'} !~ /@/x;
			$name_by_email->{ $curator->{'email'} } = "$curator->{'first_name'} $curator->{'surname'}"
			  if !$name_by_email->{ $curator->{'email'} };

			#Make shallow copy of hash, otherwise very weird things happen!
			push @{ $dbase_by_email->{ $curator->{'email'} } }, { %{ $dbases->{$db_name} } };
		}
	}
	foreach my $email ( sort keys %$dbase_by_email ) {
		my $summary;
		my %mentioned;
		my $buffer;
		foreach my $run (qw(answered new)) {
			my $run_buffer;
			foreach my $dbase ( @{ $dbase_by_email->{$email} } ) {
				my $user_ids = $ids_by_email->{ $dbase->{'name'} }->{$email} // [];
				my @list;
				foreach my $user_id (@$user_ids) {
					my $submissions =
					  $run eq 'answered'
					  ? get_submissions_answered_by_curator( $dbase, $user_id )
					  : get_new_submissions($dbase);
					foreach my $submission (@$submissions) {
						next if $mentioned{ $submission->{'id'} };
						my $submission = get_submission_details( $dbase, $submission->{'id'} );
						next if !( is_allowed_to_curate( $dbase, $submission, $user_id ) );
						push @list,
						  "$submission->{'description'}; submitted $submission->{'date_submitted'} "
						  . "($submission->{'age'} days ago) by $submission->{'submitter_name'}";
						$mentioned{ $submission->{'id'} } = 1;
					}
				}
				if (@list) {
					$run_buffer .= ( ( $dbase->{'description'} // $dbase->{'name'} ) . qq(:\n) );
					local $" = qq(\n);
					$run_buffer .= "@list";
					$run_buffer .= qq(\n\n);
				}
			}
			if ($run_buffer) {
				$summary .= qq($run\t\n) . ( '=' x length $run ) . qq(\t\n);
				$summary .= $run_buffer;
				$buffer  .= get_message($run) . $run_buffer;
			}
		}
		if ($buffer) {
			my $message = get_message('intro');
			$message .= $buffer;
			if ( $opts{'t'} ) {
				say "E-mail to $email (TEST - NOT SENDING)";
				say $summary;
			} else {
				say "Sending E-mail to $email" if !$opts{'q'};
				email( $email, $message );
			}

			#Don't spam the outgoing mail server
			sleep 5 if !$opts{'t'};
		}
	}
	return;
}

sub is_allowed_to_curate {
	my ( $dbase, $submission, $user_id ) = @_;
	my $db = db_connect($dbase);
	my $status = $db->selectrow_array( q(SELECT status FROM users WHERE id=?), undef, $user_id );
	return 1 if $status eq 'admin';
	return   if $status ne 'curator';
	my $is_allowed;
	my %method = (
		alleles => sub {
			my $locus_curator =
			  $db->selectrow_array( q(SELECT EXISTS(SELECT * FROM locus_curators WHERE (locus,curator_id)=(?,?))),
				undef, $submission->{'locus'}, $user_id );
			$is_allowed = 1 if $locus_curator;
		},
		profiles => sub {
			my $scheme_curator =
			  $db->selectrow_array( q(SELECT EXISTS(SELECT * FROM scheme_curators WHERE (scheme_id,curator_id)=(?,?))),
				undef, $submission->{'scheme_id'}, $user_id );
			$is_allowed = 1 if $scheme_curator;
		},
		isolates => sub {
			$is_allowed = is_isolate_curator( $dbase, $user_id );
		},
		genomes => sub {
			$is_allowed = is_isolate_curator( $dbase, $user_id );
		}
	);
	if ( $method{ $submission->{'type'} } ) {
		$method{ $submission->{'type'} }->();
	}
	$db->disconnect;
	return $is_allowed;
}

sub is_isolate_curator {
	my ( $dbase, $user_id ) = @_;
	my $db = db_connect($dbase);
	my $isolate_curator =
	  $db->selectrow_array( q(SELECT EXISTS(SELECT * FROM permissions WHERE (permission,user_id)=(?,?))),
		undef, 'modify_isolates', $user_id );
	$db->disconnect;
	return $isolate_curator;
}

sub get_message {
	my ($section) = @_;
	my ( $age, $domain ) = ( AGE, DOMAIN );

	#Tabs are included at end of lines to stop Outlook removing line breaks!
	my %message = (
		intro => qq(This is an automated message from the $domain submission system\t\n)
		  . qq(to notify you of any outstanding submissions pending. You have\t\n)
		  . qq(been sent this message because you have curator status for the\t\n)
		  . qq(respective databases and have submission E-mail notifications\t\n)
		  . qq(switched on. Please note that you may not be the only curator to\t\n)
		  . qq(whom this message has been sent.\t\n\t\n),
		answered => qq(You have sent correspondence for the following submissions which\t\n)
		  . qq(have not been updated in $age days. Please either accept or reject\t\n)
		  . qq(each record, then close the submission.\n\n),
		new => qq[The following submissions have not been answered by any curator and\t\n]
		  . qq[have not been updated in $age days. Please handle these soon (either\t\n]
		  . qq[assign or reject).\t\n\t\n]
	);
	return $message{$section};
}

sub get_submission_details {
	my ( $dbase, $submission_id ) = @_;
	my $db             = db_connect($dbase);
	my $submission     = $db->selectrow_hashref( q(SELECT * FROM submissions WHERE id=?), undef, $submission_id );
	my $submitter_info = $db->selectrow_hashref( q(SELECT * FROM users WHERE id=?), undef, $submission->{'submitter'} );
	if ( $submitter_info->{'user_db'} ) {
		my $remote_db =
		  $db->selectrow_hashref( 'SELECT * FROM user_dbases WHERE id=?', undef, $submitter_info->{'user_db'} );
		my $remote_user = get_remote_user( $remote_db, $submitter_info->{'user_name'} );
		foreach my $att (qw(surname first_name email)) {
			$submitter_info->{$att} = $remote_user->{$att};
		}
	}
	$submission->{'submitter_name'} = "$submitter_info->{'first_name'} $submitter_info->{'surname'}";
	my %method = (
		alleles => sub {
			my $allele_submission =
			  $db->selectrow_hashref( q(SELECT * FROM allele_submissions WHERE submission_id=?), undef,
				$submission_id );
			my $allele_count =
			  $db->selectrow_array( q(SELECT COUNT(*) FROM allele_submission_sequences WHERE submission_id=?),
				undef, $submission_id );
			my $plural = $allele_count == 1 ? q() : q(s);
			$submission->{'locus'}       = $allele_submission->{'locus'};
			$submission->{'description'} = "$allele_count $allele_submission->{'locus'} sequence$plural";
		},
		profiles => sub {
			my $profile_submission = $db->selectrow_hashref( q(SELECT * FROM profile_submissions WHERE submission_id=?),
				undef, $submission_id );
			my $profile_count =
			  $db->selectrow_array( q(SELECT COUNT(*) FROM profile_submission_profiles WHERE submission_id=?),
				undef, $submission_id );
			$submission->{'scheme_id'} = $profile_submission->{'scheme_id'};
			my $plural = $profile_count == 1 ? q() : q(s);
			my $desc =
			  $db->selectrow_array( q(SELECT name FROM schemes WHERE id=?), undef, $profile_submission->{'scheme_id'} );
			$submission->{'description'} = "$profile_count $desc profile$plural";
		},
		isolates => sub {
			add_isolate_submission_details( $dbase, $submission );
		},
		genomes => sub {
			add_isolate_submission_details( $dbase, $submission );
		},
	);
	if ( $method{ $submission->{'type'} } ) {
		$method{ $submission->{'type'} }->();
	}
	$db->disconnect;
	$submission->{'age'} = calculate_age_in_days( $submission->{'date_submitted'} );
	return $submission;
}

sub add_isolate_submission_details {
	my ( $dbase, $submission ) = @_;
	my $db = db_connect($dbase);
	my $isolate_count =
	  $db->selectrow_array( q(SELECT COUNT(DISTINCT index) FROM isolate_submission_isolates WHERE submission_id=?),
		undef, $submission->{'id'} );
	my $plural = $isolate_count == 1 ? q() : q(s);
	my $type = $submission->{'type'};
	$type =~ s/s$//x;
	$submission->{'description'} = "$isolate_count $type$plural";
	return;
}

sub get_submissions_answered_by_curator {
	my ( $dbase, $curator ) = @_;
	my $db          = db_connect($dbase);
	my $age_days    = AGE;
	my $submissions = $db->selectall_arrayref(
		qq(SELECT * FROM submissions WHERE status='pending' AND datestamp < NOW()-INTERVAL '$age_days days' AND id IN )
		  . q((SELECT submission_id FROM messages WHERE user_id=?) ORDER BY id),
		{ Slice => {} },
		$curator
	);
	$db->disconnect;
	return $submissions;
}

sub get_new_submissions {
	my ($dbase)     = @_;
	my $db          = db_connect($dbase);
	my $age_days    = AGE;
	my $submissions = $db->selectall_arrayref(
		qq(SELECT * FROM submissions WHERE status='pending' AND datestamp < NOW()-INTERVAL '$age_days days' )
		  . q(AND id NOT IN (SELECT submission_id FROM messages WHERE user_id!=submissions.submitter) ORDER BY id),
		{ Slice => {} }
	);
	$db->disconnect;
	return $submissions;
}

sub get_curators {
	my ($dbase)  = @_;
	my $db       = db_connect($dbase);
	my $curators = $db->selectall_arrayref(
		q(SELECT * FROM users WHERE status IN ('admin','curator') AND submission_emails AND id>0 ORDER BY email),
		{ Slice => {} } );
	my $ids_by_email = {};
	foreach my $curator (@$curators) {
		if ( $curator->{'user_db'} ) {
			my $remote_db =
			  $db->selectrow_hashref( 'SELECT * FROM user_dbases WHERE id=?', undef, $curator->{'user_db'} );
			my $remote_user = get_remote_user( $remote_db, $curator->{'user_name'} );
			foreach my $att (qw(surname first_name email)) {
				$curator->{$att} = $remote_user->{$att};
			}
		}
		push @{ $ids_by_email->{ lc $curator->{'email'} } }, $curator->{'id'};
	}
	$db->disconnect;
	return ( $curators, $ids_by_email );
}

sub get_remote_user {
	my ( $remote_db, $user_name ) = @_;
	my $att = {
		name => $remote_db->{'dbase_name'},
		host => $remote_db->{'dbase_host'} // 'localhost',
		port => $remote_db->{'dbase_port'} // 5432
	};
	my $db = db_connect($att);
	my $user_info = $db->selectrow_hashref( 'SELECT * FROM users WHERE user_name=?', undef, $user_name );
	$db->disconnect;
	return $user_info;
}

sub db_connect {
	my ($dbase) = @_;
	my $db = DBI->connect( "DBI:Pg:host=$dbase->{'host'};port=$dbase->{'port'};dbname=$dbase->{'name'}",
		USER, undef, { AutoCommit => 0, RaiseError => 1, PrintError => 0, pg_enable_utf8 => 1 } );
	return $db;
}

sub get_databases_with_submissions {
	my $root = DBASE_CONFIG_DIR;
	opendir my $dh, $root || croak "$0: opendir: $!";
	my @dirs = grep { -d "$root/$_" && !/^\.{1,2}$/x } readdir($dh);
	closedir $dh;
	my %dbases;
	foreach my $dir (@dirs) {
		my $config_file = "$root/$dir/config.xml";
		next if !-e $config_file;
		my %attributes;
		my $submissions;
		open( my $config_fh, '<', $config_file ) || croak "Cannot open $config_file";
		while ( my $line = <$config_fh> ) {
			foreach my $term (qw(db submissions description host port)) {
				if ( $line =~ /^\s*$term\s*="([^"]*)"/x ) {
					$attributes{$term} = $1;
				}
			}
			$submissions = 1 if ( $attributes{'submissions'} // q() ) eq 'yes';
		}
		if ( !$attributes{'db'} ) {
			croak "No database name found in $config_file";
		}
		close $config_fh;
		my $system_override_file = "$root/$dir/system.overrides";
		if ( -e $system_override_file ) {
			open( my $fh_override, '<', $system_override_file ) || croak "Cannot open $system_override_file";
			my %override_values;
			while ( my $line = <$fh_override> ) {
				next if $line =~ /^\#/x;
				$line =~ s/^\s+//x;
				$line =~ s/\s+$//x;
				if ( $line =~ /^([^=\s]+)\s*=\s*"([^"]+)"$/x ) {
					$override_values{$1} = $2;
				}
			}
			close $fh_override;
			if ( $override_values{'db'} ) {
				$attributes{'db'} = $override_values{'db'};
			}
			if ( $override_values{'submissions'} ) {
				next if $override_values{'submissions'} ne 'yes';
				$dbases{ $attributes{'db'} } = 1;
				next;
			}
		}
		if ($submissions) {
			$dbases{ $attributes{'db'} } = {
				name        => $attributes{'db'},
				description => $attributes{'description'},
				host        => $attributes{'host'} // 'localhost',
				port        => $attributes{'port'} // 5432
			};
		}
	}
	return \%dbases;
}

sub calculate_age_in_days {
	my ($date) = @_;
	my ( $y, $m, $d ) = split /-/x, $date;
	my $dt_now   = DateTime->now;
	my $dt_date  = DateTime->new( year => $y, month => $m, day => $d );
	my $duration = $dt_now->delta_days($dt_date)->{'days'};
	return $duration;
}

sub email {
	my ( $address, $message ) = @_;
	my $domain  = DOMAIN;
	my $subject = "Submission reminder ($domain)";
	my $transport =
	  Email::Sender::Transport::SMTP->new( { host => SMTP_SERVER // 'localhost', port => SMTP_PORT // 25 } );
	my $email = Email::MIME->create(
		attributes => {
			encoding => 'quoted-printable',
			charset  => 'UTF-8',
		},
		header_str => [
			To      => $address,
			From    => SENDER,
			Subject => $subject
		],
		body_str => $message
	);
	try_to_sendmail( $email, { transport => $transport } )
	  || say "Cannot send E-mail to $address";
	return;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
    ${bold}nag_curators.pl$norm - Remind curators of pending submissions

${bold}SYNOPSIS$norm
    ${bold}nag_curators.pl$norm [${under}options$norm]

${bold}OPTIONS$norm
${bold}-h, --help$norm
    This help page.

${bold}-q, --quiet$norm
    Suppress output (except errors).
    
${bold}-t, --test$norm
    Perform run but do not send E-mails.
HELP
	return;
}
