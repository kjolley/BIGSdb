#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
use 5.010;
use parent qw(BIGSdb::CurateAddPage BIGSdb::SeqbinPage);
use Log::Log4perl qw(get_logger);
use constant MAX_UPLOAD_SIZE => 32 * 1024 * 1024;    #32Mb
my $logger = get_logger('BIGSdb.Page');
use Error qw(:try);
use BIGSdb::Page 'SEQ_METHODS';

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say "<h1>Batch insert sequences</h1>";
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		say "<div class=\"box\" id=\"statusbad\"><p>This function can only be called for an isolate database.</p></div>";
		return;
	} elsif ( !$self->can_modify_table('sequence_bin') ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to upload sequences to the database.</p></div>";
		return;
	}
	if ( $q->param('checked_buffer') ) {
		$self->_upload;
		return;
	}
	$self->_print_seqbin_warnings( $q->param('isolate_id') );
	if ( $q->param('data') ) {
		$self->_check_data;
	} elsif ( $q->param('fasta_upload') ) {
		my $upload_file = $self->_upload_fasta_file;
		my $full_path   = "$self->{'config'}->{'secure_tmp_dir'}/$upload_file";
		if ( -e $full_path ) {
			open( my $fh, '<', $full_path ) or $logger->error("Can't open sequence file $full_path");
			my $sequence = do { local $/; <$fh> };    #slurp
			unlink $full_path;
			$self->_check_data( \$sequence );
		}
	} else {
		$self->_print_interface;
	}
	return;
}

sub _print_seqbin_warnings {
	my ( $self, $isolate_id ) = @_;
	if ( $isolate_id && BIGSdb::Utils::is_int($isolate_id) ) {
		my $seqbin =
		  $self->{'datastore'}->run_query( "SELECT * FROM seqbin_stats WHERE isolate_id=?", $isolate_id, { fetch => 'row_hashref' } );
		if ($seqbin) {
			say qq(<div class="box" id="warning"><p>Sequences have already been uploaded for this isolate.</p>)
			  . qq(<ul><li>Contigs: $seqbin->{'contigs'}</li><li>Total length: $seqbin->{'total_length'} bp</li></ul>)
			  . qq(<p>Please make sure that you intend to add new sequences for this isolate.</p></div>);
		}
	}
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print <<"HTML";
<div class="box" id="queryform"><div class="scrollable">
<p>This page allows you to upload sequence data for a specified isolate record in FASTA format.</p>
<p>If an isolate id is chosen, then all sequences will be associated with that isolate. Alternatively, the isolate id, or any other 
isolate table field that uniquely defines the isolate, can be named in the identifier rows of the FASTA file.  This allows data 
for multiple isolates to be uploaded.</p>
<p><em>Please note that you can reach this page for a specific isolate by 
<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query">querying isolates</a> 
and then clicking 'Upload' within the isolate table.</em></p>
HTML
	say $q->start_form( -onMouseMove => 'enable_identifier_field()' );
	my $qry = "select id,user_name,first_name,surname from users WHERE id>0 order by surname";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my @users;
	my %usernames;
	$usernames{''} = ' ';

	while ( my ( $userid, $username, $firstname, $surname ) = $sql->fetchrow_array ) {
		push @users, $userid;
		$usernames{$userid} = "$surname, $firstname ($username)";
	}
	$qry = "SELECT id,$self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} ORDER BY id";
	$sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my $id_arrayref = $sql->fetchall_arrayref;
	say "<p>Please fill in the following fields - required fields are marked with an exclamation mark (!).</p>";
	say qq(<fieldset style="float:left"><legend>Paste in sequences in FASTA format:</legend>);
	say $q->hidden($_) foreach qw (page db);
	say $q->textarea( -name => 'data', -rows => 20, -columns => 80 );
	say "</fieldset>";
	say qq(<fieldset style="float:left"><legend>Attributes</legend>\n<ul>);

	if ( $q->param('isolate_id') ) {
		say qq(<li><label class="parameter">isolate id: !</label>);
		my $isolate_id = $q->param('isolate_id');
		my $isolate_name;
		if ( BIGSdb::Utils::is_int($isolate_id) ) {
			$isolate_name =
			  $self->{'datastore'}
			  ->run_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id );
			$isolate_name //= 'Invalid isolate';
		} else {
			$isolate_name = 'Invalid isolate';
		}
		say qq{<span id="isolate_id">$isolate_id) $isolate_name</span>};
		say $q->hidden( 'isolate_id', $isolate_id );
	} else {
		say qq(<li><label for="isolate_id" class="parameter">isolate id: !</label>);
		my @ids = (0);
		my %labels;
		$labels{'0'} = 'Read identifier from FASTA';
		foreach (@$id_arrayref) {
			push @ids, $_->[0];
			$labels{ $_->[0] } = "$_->[0]) $_->[1]";
		}
		say $q->popup_menu( -name => 'isolate_id', -id => 'isolate_id', -values => \@ids, -labels => \%labels );
		say qq(</li><li><label for="identifier_field" class="parameter">identifier field: </label>);
		my $fields = $self->{'xmlHandler'}->get_field_list;
		say $q->popup_menu( -name => 'identifier_field', -id => 'identifier_field', -values => $fields );
	}
	say qq(</li><li><label for="sender" class="parameter">sender: !</label>);
	say $q->popup_menu( -name => 'sender', -id => 'sender', -values => [ '', @users ], -labels => \%usernames, -required => 'required' );
	say qq(</li><li><label for="method" class="parameter">method: </label>);
	my $method_labels = { '' => ' ' };
	say $q->popup_menu( -name => 'method', -id => 'method', -values => [ '', SEQ_METHODS ], -labels => $method_labels );
	say qq(</li><li><label for="run_id" class="parameter">run id: </label>);
	say $q->textfield( -name => 'run_id', -id => 'run_id', -size => 32 );
	say qq(</li><li><label for="assembly_id" class="parameter">assembly id: </label>);
	say $q->textfield( -name => 'assembly_id', -id => 'assembly_id', -size => 32 );
	my $seq_attributes =
	  $self->{'datastore'}
	  ->run_query( "SELECT key,type,description FROM sequence_attributes ORDER BY key", undef, { fetch => 'all_arrayref', slice => {} } );

	if (@$seq_attributes) {
		foreach my $attribute (@$seq_attributes) {
			( my $label = $attribute->{'key'} ) =~ s/_/ /;
			say qq(<li><label for="$attribute->{'key'}" class="parameter">$label:</label>\n);
			say $q->textfield( -name => $attribute->{'key'}, -id => $attribute->{'key'} );
			if ( $attribute->{'description'} ) {
				say qq( <a class="tooltip" title="$attribute->{'key'} - $attribute->{'description'}">&nbsp;<i>i</i>&nbsp;</a>);
			}
		}
	}
	say qq(</li>\n</ul>\n</fieldset>\n<fieldset style="float:left">\n<legend>Options</legend>);
	say "<ul><li>";
	say $q->checkbox( -name => 'size_filter', -label => "Don't insert sequences shorter than " );
	say $q->popup_menu( -name => 'size', -values => [qw(25 50 100 200 300 400 500 1000)], -default => 250 );
	say " bps.</li>";
	my @experiments = ('');
	$qry = "SELECT id,description FROM experiments ORDER BY description";
	$sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my $exp_labels = { '' => ' ' };

	while ( my @data = $sql->fetchrow_array ) {
		push @experiments, $data[0];
		$exp_labels->{ $data[0] } = $data[1];
	}
	if ( @experiments > 1 ) {
		say qq(<li><label for="experiment" class="parameter">Link to experiment: </label>);
		say $q->popup_menu( -name => 'experiment', -id => 'experiment', -values => \@experiments, -labels => $exp_labels );
		say "</li>";
	}
	say "</ul>\n</fieldset>";
	say qq(<fieldset style="float:left">\n<legend>Alternatively upload FASTA file</legend>);
	say "Select FASTA file:<br />";
	say $q->filefield( -name => 'fasta_upload', -id => 'fasta_upload' );
	say "</fieldset>";
	my %args = defined $q->param('isolate_id') ? ( isolate_id => $q->param('isolate_id') ) : ();
	$self->print_action_fieldset( \%args );
	say $q->end_form;
	say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back</a></p>);
	say "</div></div>";
	return;
}

sub _check_data {
	my ( $self, $passed_seq_ref ) = @_;
	my $q        = $self->{'cgi'};
	my $continue = 1;
	if (
		$q->param('isolate_id')
		&& (   !BIGSdb::Utils::is_int( $q->param('isolate_id') )
			|| !$self->{'datastore'}
			->run_query( "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)", $q->param('isolate_id') ) )
	  )
	{
		say qq(<div class="box" id="statusbad"><p>Isolate id must be an integer and exist in the isolate table.</p></div>);
		$continue = 0;
	} elsif ( !$q->param('sender')
		|| !BIGSdb::Utils::is_int( $q->param('sender') )
		|| !$self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM users WHERE id=?)", $q->param('sender') ) )
	{
		say qq(<div class="box" id="statusbad"><p>Sender is required and must exist in the users table.</p></div>);
		$continue = 0;
	}
	my $seq_attributes =
	  $self->{'datastore'}
	  ->run_query( "SELECT key,type FROM sequence_attributes ORDER BY key", undef, { fetch => 'all_arrayref', slice => {} } );
	my @att_problems;
	foreach my $attribute (@$seq_attributes) {
		my $value = $q->param( $attribute->{'key'} );
		next if !defined $value || $value eq '';
		if ( $attribute->{'type'} eq 'integer' && !BIGSdb::Utils::is_int($value) ) {
			push @att_problems, "$attribute->{'key'} must be an integer.";
		} elsif ( $attribute->{'type'} eq 'float' && !BIGSdb::Utils::is_float($value) ) {
			push @att_problems, "$attribute->{'key'} must be a floating point value.";
		} elsif ( $attribute->{'type'} eq 'date' && !BIGSdb::Utils::is_date($value) ) {
			push @att_problems, "$attribute->{'key'} must be a valid date in yyyy-mm-dd format.";
		}
	}
	if (@att_problems) {
		local $" = '<br />';
		say qq(<div class="box" id="statusbad"><p>@att_problems</p></div>);
		$continue = 0;
	}
	my $seq_ref;
	if ($continue) {
		try {
			$seq_ref = BIGSdb::Utils::read_fasta( $passed_seq_ref // \$q->param('data') );
		}
		catch BIGSdb::DataException with {
			my $ex = shift;
			if ( $ex =~ /DNA/ ) {
				my $header;
				if ( $ex =~ /DNA (.*)$/ ) {
					$header = $1;
				}
				say "<div class=\"box\" id=\"statusbad\"><p>FASTA data '$header' contains non-valid nucleotide characters.</p></div>";
				$continue = 0;
			} else {
				say "<div class=\"box\" id=\"statusbad\"><p>Sequence data is not in valid FASTA format.</p></div>";
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
			$buffer .= defined $comments ? "<td>$comments</td>" : '<td></td>';
			$buffer .= "</tr>\n";
			$td = $td == 1 ? 2 : 1;
		}
		if ($buffer) {
			say "<div class=\"box\" id=\"resultstable\"><p>The following sequences will be entered.</p>";
			say "<table><tr><td style=\"vertical-align:top\">";
			say "<table class=\"resultstable\"><tr><th>Original designation</th><th>Sequence length</th><th>Comments</th></tr>";
			say $buffer if $buffer;
			say "</table>";
			say "</td><td style=\"padding-left:2em; vertical-align:top\">";
			my $num;
			my $min = 0;
			my $max = 0;
			my ( $mean, $total );
			my @lengths;

			foreach ( values %$seq_ref ) {
				my $length = length $_;
				next if $length < $min_size;
				$min = $length if !$min || $length < $min;
				$max = $length if $length > $max;
				$total += $length;
				push @lengths, $length;
				$num++;
			}
			@lengths = sort { $b <=> $a } @lengths;
			$mean = int $total / $num if $num;
			my $n_stats = BIGSdb::Utils::get_N_stats( $total, \@lengths );
			print << "STATS";
<ul><li>Number of contigs: $num</li>
<li>Minimum length: $min</li>
<li>Maximum length: $max</li>
<li>Total length: $total</li>
<li>Mean length: $mean</li>
<li>N50: $n_stats->{'N50'}</li>
<li>N90: $n_stats->{'N90'}</li>
<li>N95: $n_stats->{'N95'}</li></ul>
STATS
			say $q->start_form;
			say $q->submit( -name => 'Upload', -class => 'submit' );
			my $filename = $self->make_temp_file(@checked_buffer);
			$q->param( 'checked_buffer', $filename );
			say $q->hidden($_) foreach qw (db page checked_buffer isolate_id sender method run_id assembly_id comments experiment);
			say $q->hidden( $_->{'key'} ) foreach (@$seq_attributes);
			say $q->end_form;
			say "</td></tr></table>";
		} else {
			say "<div class=\"box\" id=\"statusbad\"><p>No valid sequences to upload.</p></div>";
		}
		say "</div>";
	} else {
		say "<div class=\"box\" id=\"resultstable\">";
		say "<p>The following sequences will be entered.  Any problems are highlighted.</p>";
		say "<table><tr><td>";
		say "<table class=\"resultstable\"><tr><th>BIGSdb id</th>";
		my $id_field = $q->param('identifier_field');
		say "<th>Identifier field ($id_field)</th>" if $id_field ne 'id';
		say "<th>Sequence length</th><th>Comments</th><th>Status</th></tr>";
		my $td       = 1;
		my $min_size = 0;

		if ( $q->param('size_filter') && BIGSdb::Utils::is_int( $q->param('size') ) ) {
			$min_size = $q->param('size_filter') && $q->param('size');
		}
		my $attributes   = $self->{'xmlHandler'}->get_field_attributes($id_field);
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
			if ( $attributes->{'type'} eq 'int' && !BIGSdb::Utils::is_int($_) ) {
				$status = 'BIGSdb id must be an integer';
				say "<tr class=\"td$td\"><td class=\"statusbad\">$designation</td>";
				say $identifier_field_html if $identifier_field_html;
				say "<td>$length</td><td>$comments</td><td class=\"statusbad\">$status</td></tr>";
			} elsif ( $length < $min_size ) {
				$status = 'Sequence too short - will be ignored';
				say "<tr class=\"td$td\"><td>$designation</td>$identifier_field_html<td class=\"statusbad\">$length</td><td>$comments</td>"
				  . "<td class=\"statusbad\">$status</td></tr>";
			} elsif ($id_error) {
				say "<tr class=\"td$td\"><td>$designation</td>$identifier_field_html<td>$length</td><td>$comments</td><td "
				  . "class=\"statusbad\">$id_error</td></tr>";
			} else {
				push @checked_buffer, ">$designation";
				push @checked_buffer, $seq_ref->{$_};
				$status = 'Will upload';
				say "<tr class=\"td$td\"><td>$designation</td>";
				say $identifier_field_html if $identifier_field_html;
				say "<td>$length</td><td>$comments</td><td class=\"statusgood\">$status</td></tr>";
				$allow_upload = 1;
			}
			$td = $td == 1 ? 2 : 1;
		}
		say "</table>";
		say "</td><td style=\"padding-left:2em; vertical-align:top\">";
		if ($allow_upload) {
			say $q->start_form;
			say $q->submit( -name => 'Upload', -class => 'submit' );
			my $filename = $self->make_temp_file(@checked_buffer);
			$q->param( 'checked_buffer', $filename );
			say $q->hidden($_) foreach qw (db page checked_buffer isolate_id identifier_field sender method run_id assembly_id comments);
			say $q->end_form;
		} else {
			say "<p>Nothing to upload.</p>";
		}
		say "</td></tr></table>\n</div>";
	}
	return;
}

sub _upload {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $dir      = $self->{'config'}->{'secure_tmp_dir'};
	my $tmp_file = $dir . '/' . $q->param('checked_buffer');
	my @data;
	if ( -e $tmp_file ) {
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
		say "<div class=\"box\" id=\"statusbad\"><p>Unable to upload sequences.  Please try again.</p></div>";
		return;
	}
	my $qry = "INSERT INTO sequence_bin (id,isolate_id,sequence,method,run_id,assembly_id,original_designation,comments,sender,curator,"
	  . "date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)";
	my $sql = $self->{'db'}->prepare($qry);
	$qry = "INSERT INTO experiment_sequences (experiment_id,seqbin_id,curator,datestamp) VALUES (?,?,?,?)";
	my $sql_experiment = $self->{'db'}->prepare($qry);
	my $experiment     = BIGSdb::Utils::is_int( $q->param('experiment') ) ? $q->param('experiment') : undef;
	my $curator        = $self->get_curator_id;
	my $sender         = $q->param('sender');
	my $seq_attributes =
	  $self->{'datastore'}
	  ->run_query( "SELECT key,type FROM sequence_attributes ORDER BY key", undef, { fetch => 'all_arrayref', slice => {} } );
	my @attribute_sql;

	if (@$seq_attributes) {
		foreach my $attribute (@$seq_attributes) {
			if ( $q->param( $attribute->{'key'} ) ) {
				( my $value = $q->param( $attribute->{'key'} ) ) =~ s/'/\\'/g;
				$qry = "INSERT INTO sequence_attribute_values (seqbin_id,key,value,curator,datestamp) VALUES "
				  . "(?,'$attribute->{'key'}',E'$value',$curator,'now')";
				push @attribute_sql, $self->{'db'}->prepare($qry);
			}
		}
	}
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
				$id, $isolate_id, $seq_ref->{$_}, $q->param('method'), $q->param('run_id'), $q->param('assembly_id'),
				$designation, $comments, $sender, $curator, 'today', 'today'
			);
			$sql->execute(@values);
			$sql_experiment->execute( $experiment, $id, $curator, 'today' ) if $experiment;
			foreach (@attribute_sql) {
				$_->execute($id);
			}
		}
	};
	if ($@) {
		local $" = ', ';
		say "<div class=\"box\" id=\"statusbad\"><p>Database update failed - transaction cancelled - no records have been touched.</p>";
		if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
			say "<p>Data entry would have resulted in records with either duplicate ids or another unique field with duplicate "
			  . "values.</p>";
		} else {
			say "<p>Error message: $@</p>";
		}
		say "</div>";
		$self->{'db'}->rollback;
		return;
	} else {
		$self->{'db'}->commit;
		say "<div class=\"box\" id=\"resultsheader\"><p>Database updated ok</p>";
		say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAddSeqbin&amp;sender=$sender\">"
		  . "Add more</a> | <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p></div>";
	}
	return;
}

sub _upload_fasta_file {
	my ($self)   = @_;
	my $temp     = BIGSdb::Utils::get_random();
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/$temp\_upload.fas";
	my $buffer;
	open( my $fh, '>', $filename ) || $logger->error("Could not open $filename for writing.");
	my $fh2 = $self->{'cgi'}->upload('fasta_upload');
	binmode $fh2;
	binmode $fh;
	read( $fh2, $buffer, MAX_UPLOAD_SIZE );
	print $fh $buffer;
	close $fh;
	return "$temp\_upload.fas";
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
