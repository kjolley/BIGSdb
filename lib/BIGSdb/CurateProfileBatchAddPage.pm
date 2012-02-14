#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
package BIGSdb::CurateProfileBatchAddPage;
use strict;
use warnings;
use parent qw(BIGSdb::CurateProfileAddPage);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(none);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	if ( !$self->{'datastore'}->scheme_exists($scheme_id) ) {
		print "<h1>batch insert profiles</h1>\n";
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid scheme passed.</p></div>\n";
		return;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print
"<div class=\"box\" id=\"statusbad\"><p>You can only add profiles to a sequence/profile database - this is an isolate database.</p></div>\n";
		return;
	} elsif ( !$self->can_modify_table('profiles') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to add new profiles.</p></div>\n";
		return;
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	print "<h1>Batch insert $scheme_info->{'description'} profiles</h1>\n";
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $primary_key;
	eval {
		$primary_key =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
	};

	if ( !$primary_key ) {
		print
"<div class=\"box\" id=\"statusbad\"><p>This scheme doesn't have a primary key field defined.  Profiles can not be entered until this has been done.</p></div>\n";
		return;
	} elsif ( !@$loci ) {
		print
"<div class=\"box\" id=\"statusbad\"><p>This scheme doesn't have any loci belonging to it.  Profiles can not be entered until there is at least one locus defined.</p></div>\n";
		return;
	}
	my $integer_pk =
	  $self->{'datastore'}
	  ->run_simple_query( "SELECT COUNT(*) FROM scheme_fields WHERE scheme_id=? AND primary_key AND type=?", $scheme_id, 'integer' )->[0];
	if ( $q->param('checked_buffer') ) {
		my $dir      = $self->{'config'}->{'secure_tmp_dir'};
		my $tmp_file = $dir . '/' . $q->param('checked_buffer');
		my @records;
		if ( open( my $tmp_fh, '<', $tmp_file ) ) {
			@records = <$tmp_fh>;
			close $tmp_fh;
		}
		if ( $tmp_file =~ /^(.*\/BIGSdb_[0-9_]+\.txt)$/ ) {
			$logger->info("Deleting temp file $tmp_file");
			unlink $1;
		} else {
			$logger->error("Can't delete temp file $tmp_file");
		}
		my $headerline = shift @records || '';
		$headerline =~ s/[\r\n]//g;
		my @fieldorder = split /\t/, $headerline;
		my %fieldorder;
		for ( my $i = 0 ; $i < scalar @fieldorder ; $i++ ) {
			$fieldorder{ $fieldorder[$i] } = $i;
		}
		my @fields_to_include = qw(sender curator date_entered datestamp);
		foreach my $record (@records) {
			$record =~ s/\r//g;
			if ($record) {
				my @data = split /\t/, $record;
				@data = $self->_process_fields( \@data );
				my @value_list;
				my ( $pk, $sender );
				foreach (@fields_to_include) {
					$pk = $data[ $fieldorder{$_} ] if $_ eq $primary_key;
					if ( $_ eq 'date_entered' || $_ eq 'datestamp' ) {
						push @value_list, "'today'";
					} elsif ( $_ eq 'curator' ) {
						push @value_list, $self->get_curator_id;
					} elsif ( defined $fieldorder{$_}
						&& $data[ $fieldorder{$_} ] ne 'null' )
					{
						push @value_list, "'$data[$fieldorder{$_}]'";
						if ( $_ eq 'sender' ) {
							$sender = $data[ $fieldorder{$_} ];
						}
					} elsif ( $_ eq 'sender' ) {
						if ( $q->param('sender') ) {
							$sender = $q->param('sender');
							push @value_list, $sender;
						} else {
							push @value_list, 'null';
							$logger->error("No sender!");
						}
					} else {
						push @value_list, 'null';
					}
				}
				my @inserts;
				my $qry;
				local $" = ',';
				$qry =
"INSERT INTO profiles (scheme_id,profile_id,@fields_to_include) VALUES ($scheme_id,'$data[$fieldorder{$primary_key}]',@value_list)";
				push @inserts, $qry;
				my $curator = $self->get_curator_id;
				foreach (@$loci) {
					$data[ $fieldorder{$_} ] =~ s/^\s*//g;
					$data[ $fieldorder{$_} ] =~ s/\s*$//g;
					if (   defined $fieldorder{$_}
						&& $data[ $fieldorder{$_} ] ne 'null'
						&& $data[ $fieldorder{$_} ] ne '' )
					{
						$qry =
"INSERT INTO profile_members (scheme_id,locus,profile_id,allele_id,curator,datestamp) VALUES ($scheme_id,'$_','$data[$fieldorder{$primary_key}]','$data[$fieldorder{$_}]','$curator','today')";
						push @inserts, $qry;
						$logger->debug("INSERT: $qry");
					}
				}
				foreach (@$scheme_fields) {
					my $value = defined $fieldorder{$_} ? $data[ $fieldorder{$_} ] : '';
					$value = defined $value ? $value : '';
					$value =~ s/^\s*//g;
					$value =~ s/\s*$//g;
					if (   defined $fieldorder{$_}
						&& $value ne 'null'
						&& $value ne '' )
					{
						$qry =
"INSERT INTO profile_fields (scheme_id,scheme_field,profile_id,value,curator,datestamp) VALUES ($scheme_id,'$_','$data[$fieldorder{$primary_key}]','$value','$curator','today')";
						push @inserts, $qry;
					}
				}
				local $" = ';';
				eval { $self->{'db'}->do("@inserts"); };
				if ($@) {
					print
"<div class=\"box\" id=\"statusbad\"><p>Database update failed - transaction cancelled - no records have been touched.</p>\n";
					if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
						print
"<p>Data entry would have resulted in records with either duplicate ids or another unique field with duplicate values.</p>\n";
					} else {
						print "<p>Error message: $@</p>\n";
					}
					print "</div>\n";
					$self->{'db'}->rollback;
					$logger->error("Can't insert: $@");
					return;
				}
			}
		}
		$self->{'db'}->commit
		  && print "<div class=\"box\" id=\"resultsheader\"><p>Database updated ok</p>";
		print "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
	} elsif ( $q->param('data') ) {
		my @checked_buffer;
		my @fieldorder = ( $primary_key, @$loci );
		my %is_field;
		my %is_locus;
		my $scheme_field_info;
		my %pks_so_far;
		my %profiles_so_far;
		local $" = '</th><th>';
		my $table_buffer = "<table class=\"resultstable\"><tr><th>$primary_key</th><th>@$loci</th>";

		foreach (@$scheme_fields) {
			$is_field{$_} = 1;
			$scheme_field_info->{$_} = $self->{'datastore'}->get_scheme_field_info($scheme_id, $_);
			
			if ( $_ ne $primary_key ) {
				push @fieldorder, $_;
				$table_buffer .= "<th>$_</th>";
			}
		}
		push @fieldorder, qw (sender curator date_entered datestamp);
		$table_buffer .= "</tr>\n";
		my ( $firstname, $surname, $userid );
		my $sender_message;
		my $sender = $q->param('sender');
		if ( !$sender ) {
			print "<div class=\"box\" id=\"statusbad\"><p>Please go back and select the sender for this submission.</p></div>\n";
			return;
		} elsif ( $sender == -1 ) {
			$sender_message = "<p>Using sender field in pasted data.</p>\n";
		} else {
			my $sender_ref = $self->{'datastore'}->get_user_info($sender);
			$sender_message = "<p>Sender: $sender_ref->{'first_name'} $sender_ref->{'surname'}</p>\n";
		}
		my %problems;
		my $tablebuffer;
		$tablebuffer .= "<table class=\"resultstable\"><tr>";
		local $" = "</th><th>";
		$tablebuffer .= "<th>@fieldorder</th></tr>";
		my @records   = split /\n/, $q->param('data');
		my $td        = 1;
		my $headerRow = shift @records;
		$headerRow =~ s/\r//g;
		my @fileheaderFields = split /\t/, $headerRow;
		my %fileheaderPos;
		my $i = 0;
		my $pk_included;

		foreach (@fileheaderFields) {
			$fileheaderPos{$_} = $i;
			$i++;
			$pk_included = 1 if $_ eq $primary_key;
		}
		my $pk;
		$pk = $self->next_id( 'profiles', $scheme_id );
		my $qry                   = "SELECT profile_id FROM profiles WHERE scheme_id=? AND profile_id=?";
		my $primary_key_check_sql = $self->{'db'}->prepare($qry);
		my %locus_format;
		foreach (@$loci) {
			my $locus_info = $self->{'datastore'}->get_locus_info($_);
			$locus_format{$_} = $locus_info->{'allele_id_format'};
			$is_locus{$_}     = 1;
		}

		my $first_record = 1;
		my $header_row;
		my $record_count;
		$qry =
"SELECT profiles.profile_id FROM profiles LEFT JOIN profile_members ON profiles.scheme_id = profile_members.scheme_id AND profiles.profile_id = profile_members.profile_id WHERE ";
		my @locus_temp;
		foreach (@$loci) {
			push @locus_temp, "(locus='$_' AND allele_id=?)";
		}
		local $" = ' OR ';
		$qry .= "(@locus_temp)";
		$qry .= ' GROUP BY profiles.profile_id having count(*)=' . scalar @locus_temp;
		my $profile_check_sql = $self->{'db'}->prepare($qry);
		foreach my $record (@records) {
			$record =~ s/\r//g;
			next if $record =~ /^\s*$/;
			my @profile;
			my $checked_record;
			my @data = split /\t/, $record;
			if ( $integer_pk && !$first_record && !$pk_included ) {
				do {
					$pk++;
				} while ( $self->_is_pk_used( $scheme_id, $pk ) );
			} elsif ($pk_included) {
				$pk = $data[ $fileheaderPos{$primary_key} ];
			}
			$record_count++;
			$tablebuffer .= "<tr class=\"td$td\">";
			$i = 0;
			foreach my $field (@fieldorder) {
				my $value;
				if ( $field eq $primary_key ) {
					$header_row .= "$primary_key\t"
					  if $first_record && !$pk_included;
					$value = $pk;
				}
				my $problem;
				if ( $field eq 'datestamp' || $field eq 'date_entered' ) {
					$value = $self->get_datestamp();
				} elsif ( $field eq 'sender' ) {
					if ( defined $fileheaderPos{$field} ) {
						$value = $data[ $fileheaderPos{$field} ];
						$header_row .= "$field\t" if $first_record;
						if ( !BIGSdb::Utils::is_int($value) ) {
							$problems{$pk} .= "Sender must be an integer.<br />";
							$problem = 1;
						} else {
							my $sender_exists =
							  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM users WHERE id=?", $value )->[0];
							if ( !$sender_exists ) {
								$problems{$pk} .= "Sender '$value' does not exist.<br />";
								$problem = 1;
							}
						}
					} else {
						$value = $q->param('sender')
						  if $q->param('sender') != -1;
					}
				} elsif ( $field eq 'curator' ) {
					$value = $self->get_curator_id;
				} else {
					if ( defined $fileheaderPos{$field} ) {
						$header_row .= "$field\t" if $first_record;
						$value = $data[ $fileheaderPos{$field} ];
					}
				}
				if ( $is_locus{$field} ) {
					push @profile, $value;
					my $locus_info = $self->{'datastore'}->get_locus_info($field);
					if ( !defined $value ) {
						$problems{$pk} .= "Locus $field requires a value.<br />";
						$problem = 1;
					} elsif ( $locus_format{$field} eq 'integer' && !BIGSdb::Utils::is_int($value) ) {
						$problems{$pk} .= "Locus $field must be an integer.<br />";
						$problem = 1;
					}

					#check for regex which is defined in loci table
					elsif ( $locus_info->{'allele_id_regex'} && $value !~ /$locus_info->{'allele_id_regex'}/ ) {
						$problems{$pk} .=
						  "Locus $field value is invalid - it must match the regular expression /$locus_info->{'allele_id_regex'}/.<br />";
						$problem = 1;
					}

					#check allele exists
					elsif ( !$self->{'datastore'}->sequence_exists( $field, $value ) ) {
						$problems{$pk} .= "Sequence $field $value does not exist.<br />";
						$problem = 1;
					}
				} elsif ($is_field{$field} && defined $value){
					if ( $scheme_field_info->{$field}->{'primary_key'} && $value eq ''){
						$problems{$pk} .= "Field $field is required and must not be left blank.<br />";
						$problem = 1;
					} elsif ( $scheme_field_info->{$field}->{'type'} eq 'integer' && !BIGSdb::Utils::is_int($value) ) {
						$problems{$pk} .= "Field $field must be an integer.<br />";
						$problem = 1;
					}
				}
				$value = defined $value ? $value : '';
				my $display_value = $value;
				if ( !$problem ) {
					$tablebuffer .= "<td>$display_value</td>";
				} else {
					$tablebuffer .= "<td><font color=\"red\">$display_value</font></td>";
				}
				$checked_record .= "$value\t"
				  if defined $fileheaderPos{$field}
					  or ( $field eq $primary_key );
			}

			#check if profile exists
			eval { $profile_check_sql->execute(@profile) };
			$logger->error($@) if $@;
			my ($exists) = $profile_check_sql->fetchrow_array;
			if ($exists) {
				$problems{$pk} .= "The profile for $primary_key-$pk already exists in the database ($primary_key-$exists).<br />";
			}

			#check if primary key already exists
			eval { $primary_key_check_sql->execute( $scheme_id, $pk ) };
			$logger->error($@) if $@;
			($exists) = $primary_key_check_sql->fetchrow_array;
			if ($exists) {
				$problems{$pk} .= "The primary key '$primary_key-$pk' already exists in the database.<br />";
			}
			if ( $pks_so_far{$pk} ) {
				$problems{$pk} .= "This primary key has been included more than once in this submission.<br />";
			}
			{
				no warnings 'uninitialized';
				local $" = ',';
				if ( $profiles_so_far{"@profile"} && none {$_ eq ''} @profile) {
					$problems{$pk} .= "The profile '@profile' has been included more than once in this submission.<br />";
				}
				$profiles_so_far{"@profile"} = 1;
			}
			$pks_so_far{$pk} = 1;
			$tablebuffer .= "</tr>\n";
			$td = $td == 1 ? 2 : 1;    #row stripes
			push @checked_buffer, $header_row if $first_record;
			$checked_record =~ s/\t$//;
			push @checked_buffer, $checked_record;
			$first_record = 0;
		}
		$tablebuffer .= "</table>\n";
		if ( !$record_count ) {
			print "<div class=\"box\" id=\"statusbad\"><p>No valid data entered. Make sure you've included the header line.</p></div>\n";
			return;
		}
		if (%problems) {
			print "<div class=\"box\" id=\"statusbad\"><h2>Import status</h2>\n";
			print "<table class=\"resultstable\">";
			print "<tr><th>$primary_key</th><th>Problem(s)</th></tr>\n";
			my $td = 1;
			foreach my $id ( sort { $a <=> $b || $a cmp $b } keys %problems ) {
				print "<tr class=\"td$td\"><td>$id</td><td style=\"text-align:left\">$problems{$id}</td></tr>";
				$td = $td == 1 ? 2 : 1;    #row stripes
			}
			print "</table></div>\n";
		} else {
			print
"<div class=\"box\" id=\"resultsheader\"><h2>Import status</h2>$sender_message<p>No obvious problems identified so far.</p>\n";
			my $filename = $self->make_temp_file(@checked_buffer);
			print $q->start_form;
			print $q->hidden($_) foreach qw (data page table db sender scheme_id);
			print $q->hidden( 'checked_buffer', $filename );
			print $q->submit( -name => 'Import data', -class => 'submit' );
			print $q->endform;
			print "</div>\n";
		}
		print "<div class=\"box\" id=\"resultstable\"><h2>Data to be imported</h2>\n";
		print "<p>The following table shows your data.  Any field coloured red has a problem and needs to be checked.</p>\n";
		print $tablebuffer;
		print "</div><p />";
	} else {
		print << "HTML";
<div class="box" id="queryform">
<p>This page allows you to upload profiles as tab-delimited text or 
copied from a spreadsheet.</p>
<ul>
<li>Field header names must be included and fields
can be in any order. Optional fields can be omitted if you wish.</li>
HTML
		if ($integer_pk) {
			my $article = $primary_key =~ /^[AaEeIiOoUu]/ ? 'an' : 'a';
			print << "HTML";
<li>You can choose whether or not to include $article $primary_key 
field - if it is omitted, the next available $primary_key will be used automatically.  If however, you include
it in the header line, then you must also provide it for each profile record.</li>
HTML
		}
		print << "HTML";
</ul>
<ul>
<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableHeader&amp;table=profiles&amp;scheme=$scheme_id">Download tab-delimited 
header for your spreadsheet</a> - use Paste special &rarr; text to paste the data.</li>
</ul>
HTML
		print $q->start_form;
		my $qry = "select id,user_name,first_name,surname from users WHERE id> 0 order by surname";
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute };
		$logger->error($@) if $@;
		my @users;
		my %usernames;
		$usernames{''} = 'Select sender ...';

		while ( my ( $userid, $username, $firstname, $surname ) = $sql->fetchrow_array ) {
			push @users, $userid;
			$usernames{$userid} = "$surname, $firstname ($username)";
		}
		print "<p>Please select the sender from the list below:</p>\n";
		$usernames{-1} = 'Override with sender field';
		print "<table><tr><td>\n";
		print $q->popup_menu( -name => 'sender', -values => [ '', -1, @users ], -labels => \%usernames );
		print "</td><td class=\"comment\">Value will be overridden if you include a sender field in your pasted data.</td></tr></table>\n";
		print "<p>Please paste in tab-delimited text (<strong>include a field header line</strong>).</p>\n";
		print $q->hidden($_) foreach qw (page db scheme_id);
		print $q->textarea( -name => 'data', -rows => 20, -columns => 120 );
		print "<table style=\"width:95%\"><tr><td>";
		print $q->reset( -class => 'reset' );
		print "</td><td style=\"text-align:right\">";
		print $q->submit( -class => 'submit' );
		print "</td></tr></table><p />\n";
		print $q->end_form;
		print "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back</a></p>\n";
		print "</div>\n";
	}
	return;
}

sub get_title {
	my $self        = shift;
	my $desc        = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table       = $self->{'cgi'}->param('table');
	my $scheme_id   = $self->{'cgi'}->param('scheme_id');
	my $scheme_desc = '';
	if ( $scheme_id && BIGSdb::Utils::is_int($scheme_id) ) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		$scheme_desc = $scheme_info->{'description'} || '';
	}
	my $type = $self->get_record_name($table);
	return "Batch add new $scheme_desc profiles - $desc";
}

sub _is_pk_used {

	#TODO this could be improved by storing query handle
	my ( $self, $scheme_id, $profile_id ) = @_;
	my $qry = "SELECT count(*) FROM profiles WHERE scheme_id=? AND profile_id=?";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute( $scheme_id, $profile_id ) };
	$logger->error($@) if $@;
	my ($used) = $sql->fetchrow_array;
	return $used;
}

sub _process_fields {
	my ( $self, $data ) = @_;
	my @return_data;
	foreach (@$data) {

		#remove trailing spaces
		$_ =~ s/^\s+//;
		$_ =~ s/\s+$//;
		$_ =~ s/'/\'\'/g;
		if ( $_ eq '' ) {
			push @return_data, 'null';
		} else {
			push @return_data, $_;
		}
	}
	return @return_data;
}
1;
