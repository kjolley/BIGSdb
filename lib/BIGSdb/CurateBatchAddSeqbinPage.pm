#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
package BIGSdb::CurateBatchAddSeqbinPage;
use strict;
use warnings;
use base qw(BIGSdb::CurateAddPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use Error qw(:try);
use BIGSdb::Page 'SEQ_METHODS';

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<h1>Batch insert sequences</h1>\n";
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>This function can only be called for an isolate database.</p></div>\n";
		return;
	} elsif ( !$self->can_modify_table('sequence_bin') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to upload sequences to the database.</p></div>\n";
		return;
	}
	if ( $q->param('checked_buffer') ) {
		$self->_upload;
	} elsif ( $q->param('data') ) {
		$self->_check_data;
	} else {
		$self->_print_interface;
	}
}

sub _print_interface {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print
"<div class=\"box\" id=\"queryform\"><p>This page allows you to upload sequence data for a specified isolate record in FASTA format.</p>\n";
	print "<p>If an isolate id is chosen, then all sequences will be associated with that isolate.  
	Alternatively, the isolate id, or any other isolate table field that uniquely defines the isolate, 
	can be named in the identifier rows of the FASTA file.  This allows data for multiple isolates to be uploaded.</p>";
	print $q->start_form( -onMouseMove => 'enable_identifier_field()' );
	my $qry = "select id,user_name,first_name,surname from users WHERE id>0 order by surname";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my @users;
	my %usernames;

	while ( my ( $userid, $username, $firstname, $surname ) = $sql->fetchrow_array ) {
		push @users, $userid;
		$usernames{$userid} = "$surname, $firstname ($username)";
	}
	$qry = "SELECT id,$self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} ORDER BY id";
	$sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my $id_arrayref = $sql->fetchall_arrayref;
	print "<p>Please fill in the following fields - required fields are marked with an exclamation mark (!).</p>\n";
	print "<fieldset><legend>Attributes</legend>\n<ul>";
	print "<li><label for=\"isolate_id\" class=\"parameter\">isolate id: !</label>\n";
	my %labels;

	if ( $q->param('isolate_id') ) {
		my $isolate_id = $q->param('isolate_id');
		my $isolate_name;
		if ( BIGSdb::Utils::is_int($isolate_id) ) {
			my $isolate_name_ref =
			  $self->{'datastore'}
			  ->run_simple_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id );
			$isolate_name = ref $isolate_name_ref eq 'ARRAY' ? $isolate_name_ref->[0] : 'Invalid isolate';
		} else {
			$isolate_name = 'Invalid isolate';
		}
		print "<span id=\"isolate_id\">$isolate_id) $isolate_name</span>\n";
		print $q->hidden( 'isolate_id', $isolate_id );
	} else {
		my @ids = (0);
		$labels{'0'} = 'Read identifier from FASTA';
		foreach (@$id_arrayref) {
			push @ids, $_->[0];
			$labels{ $_->[0] } = "$_->[0]) $_->[1]";
		}
		print $q->popup_menu( -name => 'isolate_id', -id => 'isolate_id', -values => \@ids, -labels => \%labels );
		print "</li><li><label for=\"identifier_field\" class=\"parameter\">identifier field: </label>\n";
		my $fields = $self->{'xmlHandler'}->get_field_list;
		print $q->popup_menu( -name => 'identifier_field', -id => 'identifier_field', -values => $fields );
	}
	print "</li><li><label for=\"sender\" class=\"parameter\">sender: !</label>\n";
	print $q->popup_menu( -name => 'sender', -id => 'sender', -values => [ '', @users ], -labels => \%usernames );
	print "</li><li><label for=\"method\" class=\"parameter\">method: </label>\n";
	print $q->popup_menu( -name => 'method', -id => 'method', -values => [ '', SEQ_METHODS ] );
	print "</li>\n</ul>\n</fieldset>\n<fieldset>\n<legend>Options</legend>\n";
	print "<ul><li>";
	print $q->checkbox( -name => 'size_filter', -label => "Don't insert sequences shorter than " );
	print $q->popup_menu( -name => 'size', -values => [qw(25 50 100 250 500 1000)], -default => 250 );
	print " bps.</li>\n";
	my @experiments = ('');
	$qry = "SELECT id,description FROM experiments ORDER BY description";
	$sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;

	while ( my @data = $sql->fetchrow_array ) {
		push @experiments, $data[0];
		$labels{ $data[0] } = $data[1];
	}
	if ( @experiments > 1 ) {
		print "<li><label for=\"experiment\" class=\"parameter\">Link to experiment: </label>\n";
		print $q->popup_menu( -name => 'experiment', -id => 'experiment', -values => \@experiments, -labels => \%labels );
		print "</li>\n";
	}
	print "</ul>\n</fieldset>\n";
	print "<p>Please paste in sequences in FASTA format:</p>\n";
	print $q->hidden($_) foreach qw (page db);
	print $q->textarea( -name => 'data', -rows => 20, -columns => 120 );
	print "<table style=\"width:95%\"><tr><td>";
	print $q->reset( -class => 'reset' );
	print "</td><td style=\"text-align:right\">";
	print $q->submit( -class => 'submit' );
	print "</td></tr></table><p />\n";
	print $q->end_form;
	print "<p><a href=\"" . $q->script_name . "/?db=$self->{'instance'}\">Back</a></p>\n";
	print "</div>\n";
}

sub _check_data {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $continue = 1;
	if (
		$q->param('isolate_id')
		&& (   !BIGSdb::Utils::is_int( $q->param('isolate_id') )
			|| !$self->{'datastore'}
			->run_simple_query( "SELECT COUNT(*) FROM $self->{'system'}->{'view'} WHERE id=?", $q->param('isolate_id') )->[0] )
	  )
	{
		print "<div class=\"box\" id=\"statusbad\"><p>Isolate id must be an integer and exist in the isolate table.</p></div>\n";
		$continue = 0;
	} elsif (
		$q->param('isolate_id')
		&& ( $self->{'system'}->{'read_access'} eq 'acl'
			|| ( $self->{'system'}->{'write_access'} && $self->{'system'}->{'write_access'} eq 'acl' ) )
		&& $self->{'username'}
		&& !$self->is_admin
		&& !$self->is_allowed_to_view_isolate( $q->param('isolate_id') )
	  )
	{
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to modify this isolate record.</p></div>\n";
		$continue = 0;
	} elsif ( !$q->param('sender')
		|| !BIGSdb::Utils::is_int( $q->param('sender') )
		|| !$self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM users WHERE id=?", $q->param('sender') )->[0] )
	{
		print "<div class=\"box\" id=\"statusbad\"><p>Sender is required and must exist in the users table.</p></div>\n";
		$continue = 0;
	}
	my $seq_ref;
	if ($continue) {
		try {
			$seq_ref = BIGSdb::Utils::read_fasta( \$q->param('data') );
		}
		catch BIGSdb::DataException with {
			my $ex = shift;
			if ( $ex =~ /DNA/ ) {
				my $header;
				if ( $ex =~ /DNA (.*)$/ ) {
					$header = $1;
				}
				print "<div class=\"box\" id=\"statusbad\"><p>FASTA data '$header' contains non-valid nucleotide characters.</p></div>\n";
				$continue = 0;
			} else {
				print "<div class=\"box\" id=\"statusbad\"><p>Sequence data is not in valid FASTA format.</p></div>\n";
				$continue = 0;
			}
		};
	}
	if ( !$continue ) {
		$self->_print_interface;
		return;
	}
	my @checked_buffer;
	if ( $q->param('isolate_id') ) {
		my $td       = 1;
		my $min_size = 0;
		if ( $q->param('size_filter') && BIGSdb::Utils::is_int( $q->param('size') ) ) {
			$min_size = $q->param('size_filter') && $q->param('size');
		}
		my $buffer;
		foreach ( sort { $a cmp $b } keys %$seq_ref ) {
			my $length = length( $seq_ref->{$_} );
			next if $length < $min_size;
			push @checked_buffer, ">$_";
			push @checked_buffer, $seq_ref->{$_};
			my ( $designation, $comments );
			if ( $_ =~ /(\S*)\s+(.*)/ ) {
				( $designation, $comments ) = ( $1, $2 );
			} else {
				$designation = $_;
			}
			$buffer .= "<tr class=\"td$td\"><td>$designation</td>";
			$buffer .= "<td>$length</td>";
			$buffer .= defined $comments ? "<td>$comments</td>" : '<td />';
			$buffer .= "</tr>\n";
			$td = $td == 1 ? 2 : 1;
		}
		if ($buffer) {
			print "<div class=\"box\" id=\"resultstable\"><p>The following sequences will be entered.</p>\n";
			print "<table><tr><td>";
			print "<table class=\"resultstable\"><tr><th>Original designation</th><th>Sequence length</th><th>Comments</th></tr>\n";
			print $buffer if $buffer;
			print "</table>\n";
			print "</td><td style=\"padding-left:2em; vertical-align:top\">\n";
			my $num;
			my $min = 0;
			my $max = 0;
			my ( $mean, $total );

			foreach ( values %$seq_ref ) {
				my $length = length $_;
				next if $length < $min_size;
				$min = $length if !$min || $length < $min;
				$max = $length if $length > $max;
				$total += $length;
				$num++;
			}
			$mean = int $total / $num if $num;
			print "<ul><li>Number of contigs: $num</li>\n";
			print "<li>Minimum length: $min</li>\n";
			print "<li>Maximum length: $max</li>\n";
			print "<li>Total length: $total</li>\n";
			print "<li>Mean length: $mean</li></ul>\n";
			print $q->start_form;
			print $q->submit( -name => 'Upload', -class => 'submit' );
			my $filename = $self->make_temp_file(@checked_buffer);
			$q->param( 'checked_buffer', $filename );
			print $q->hidden($_) foreach qw (db page checked_buffer isolate_id sender method comments experiment);
			print $q->end_form;
			print "</td></tr></table>\n";
		} else {
			print "<div class=\"box\" id=\"statusbad\"><p>No valid sequences to upload.</p></div>\n";
		}
		print "</div>\n";
	} else {
		print "<div class=\"box\" id=\"resultstable\">";
		print "<p>The following sequences will be entered.  Any problems are highlighted.</p>\n";
		print "<table><tr><td>";
		print "<table class=\"resultstable\"><tr><th>BIGSdb id</th>";
		my $id_field = $q->param('identifier_field');
		print "<th>Identifier field ($id_field)</th>" if $id_field ne 'id';
		print "<th>Sequence length</th><th>Comments</th><th>Status</th></tr>\n";
		my $td       = 1;
		my $min_size = 0;
		my $problem_css;

		if ( $q->param('size_filter') && BIGSdb::Utils::is_int( $q->param('size') ) ) {
			$min_size = $q->param('size_filter') && $q->param('size');
		}
		my %attributes   = $self->{'xmlHandler'}->get_field_attributes($id_field);
		my $allow_upload = 0;
		my $sql          = $self->{'db'}->prepare("SELECT id FROM $self->{'system'}->{'view'} WHERE $id_field = ?");
		foreach ( sort { $a cmp $b } keys %$seq_ref ) {
			my $length = length( $seq_ref->{$_} );
			my ( $designation, $comments, $status );
			if ( $_ =~ /(\S*)\s+(.*)/ ) {
				( $designation, $comments ) = ( $1, $2 );
			} else {
				$designation = $_;
			}
			$comments ||= '';
			my $identifier_field_html;
			my $id_error;
			if ( $id_field ne 'id' ) {
				$identifier_field_html = "<td>$_</td>";
				eval { $sql->execute($_) };
				$logger->error($@) if $@;
				my @ids;
				while ( my ($id) = $sql->fetchrow_array ) {
					push @ids, $id;
				}
				if ( !@ids ) {
					$id_error    = "No matching record";
					$designation = '-';
				} elsif ( @ids > 1 ) {
					$id_error    = scalar @ids . " matching records - can't uniquely identify isolate";
					$designation = '-';
				} else {
					($designation) = @ids;
				}
			}
			if ( $attributes{'type'} eq 'int' && !BIGSdb::Utils::is_int($_) ) {
				$status = 'BIGSdb id must be an integer';
				print
"<tr class=\"td$td\"><td class=\"statusbad\">$designation</td>$identifier_field_html<td>$length</td><td>$comments</td><td class=\"statusbad\">$status</td></tr>\n";
			} elsif ( $length < $min_size ) {
				$status = 'Sequence too short - will be ignored';
				print
"<tr class=\"td$td\"><td>$designation</td>$identifier_field_html<td class=\"statusbad\">$length</td><td>$comments</td><td class=\"statusbad\">$status</td></tr>\n";
			} elsif ($id_error) {
				print
"<tr class=\"td$td\"><td>$designation</td>$identifier_field_html<td>$length</td><td>$comments</td><td class=\"statusbad\">$id_error</td></tr>\n";
			} else {
				push @checked_buffer, ">$designation";
				push @checked_buffer, $seq_ref->{$_};
				$status = 'Will upload';
				print
"<tr class=\"td$td\"><td>$designation</td>$identifier_field_html<td>$length</td><td>$comments</td><td class=\"statusgood\">$status</td></tr>\n";
				$allow_upload = 1;
			}
			$td = $td == 1 ? 2 : 1;
		}
		print "</table>\n";
		print "</td><td style=\"padding-left:2em; vertical-align:top\">\n";
		if ($allow_upload) {
			print $q->start_form;
			print $q->submit( -name => 'Upload', -class => 'submit' );
			my $filename = $self->make_temp_file(@checked_buffer);
			$q->param( 'checked_buffer', $filename );
			print $q->hidden($_) foreach qw (db page checked_buffer isolate_id identifier_field sender method comments);
			print $q->end_form;
		} else {
			print "<p>Nothing to upload.</p>\n";
		}
		print "</td></tr></table>\n</div>\n";
	}
}

sub _upload {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $dir      = $self->{'config'}->{'secure_tmp_dir'};
	my $tmp_file = $dir . '/' . $q->param('checked_buffer');
	my @data;
	if (-e $tmp_file){
		open( my $file_fh, '<', $tmp_file ) or $logger->error("Can't open $tmp_file");
		@data = <$file_fh>;
		close $file_fh;
	}
	local $" = "\n";
	my $seq_ref;
	my $continue = 1;
	try {
		$seq_ref = BIGSdb::Utils::read_fasta( \"@data" );
	}
	catch BIGSdb::DataException with {
		$logger->error("Invalid FASTA file");
		$continue = 0;
	};
	if ( $tmp_file =~ /^(.*\/BIGSdb_[0-9_]+\.txt)$/ ) {
		$logger->info("Deleting temp file $tmp_file");
		unlink $1;
	} else {
		$logger->error("Can't delete temp file $tmp_file");
	}
	if ( !$continue ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Unable to upload sequences.  Please try again.</p></div>\n";
		return;
	}
	my $qry =
"INSERT INTO sequence_bin (id,isolate_id,sequence,method,original_designation,comments,sender,curator,date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?,?,?)";
	my $sql = $self->{'db'}->prepare($qry);
	$qry = "INSERT INTO experiment_sequences (experiment_id,seqbin_id,curator,datestamp) VALUES (?,?,?,?)";
	my $sql_experiment = $self->{'db'}->prepare($qry);
	my $experiment     = BIGSdb::Utils::is_int( $q->param('experiment') ) ? $q->param('experiment') : undef;
	my $curator        = $self->get_curator_id;
	eval {
		my $id;
		foreach ( keys %$seq_ref ) {
			$id = $self->next_id( 'sequence_bin', 0, $id );
			my ( $designation, $comments );
			if ( $_ =~ /(\S*)\s+(.*)/ ) {
				( $designation, $comments ) = ( $1, $2 );
			} else {
				$designation = $_;
			}
			my $isolate_id = $q->param('isolate_id') ? $q->param('isolate_id') : $designation;
			my @values = (
				$id,          $isolate_id, $seq_ref->{$_},      $q->param('method'),
				$designation, $comments,   $q->param('sender'), $curator,
				'today',      'today'
			);
			$sql->execute(@values);
			$sql_experiment->execute( $experiment, $id, $curator, 'today' ) if $experiment;
		}
	};
	if ($@) {
		local $" = ', ';
		print "<div class=\"box\" id=\"statusbad\"><p>Database update failed - transaction cancelled - no records have been touched.</p>\n";
		if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
			print
			  "<p>Data entry would have resulted in records with either duplicate ids or another unique field with duplicate values.</p>\n";
		} else {
			print "<p>Error message: $@</p>\n";
		}
		print "</div>\n";
		$self->{'db'}->rollback;
		return;
	} else {
		$self->{'db'}->commit;
		print "<div class=\"box\" id=\"resultsheader\"><p>Database updated ok</p>";
		print "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
	}
	return;
}

sub get_javascript {
	my $buffer = << "END";

function enable_identifier_field(){
	var element = document.getElementById('isolate_id');
	if (element.value == 0){
		document.getElementById('identifier_field').disabled=false;
	} else {
		document.getElementById('identifier_field').disabled=true;
	}
}
	
END
	return $buffer;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Batch add new sequences - $desc";
}
1;
