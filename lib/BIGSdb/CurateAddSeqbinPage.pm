#Written by Keith Jolley
#Copyright (c) 2010-2021, University of Oxford
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
package BIGSdb::CurateAddSeqbinPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateAddPage BIGSdb::SeqbinPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use Bio::DB::GenBank;
use Try::Tiny;
use File::Type;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use BIGSdb::Constants qw(SEQ_METHODS :interface :limits);

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery jQuery.multiselect modernizr noCache);
	$self->set_level1_breadcrumbs;
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Upload sequences</h1>);
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		$self->print_bad_status( { message => q(This function can only be called for an isolate database.) } );
		return;
	} elsif ( !$self->can_modify_table('sequence_bin') ) {
		$self->print_bad_status(
			{
				message => q(Your user account is not allowed to upload sequences to the database.)
			}
		);
		return;
	}
	if ( $q->param('checked_buffer') ) {
		$self->_upload;
		return;
	}
	$self->print_seqbin_warnings( scalar $q->param('isolate_id') );
	if ( $q->param('data') ) {
		$self->_check_data;
	} elsif ( $q->param('fasta_upload') ) {
		my $upload_file = $self->_upload_fasta_file;
		my $full_path   = "$self->{'config'}->{'secure_tmp_dir'}/$upload_file";
		if ( -e $full_path ) {
			my $seq_ref = BIGSdb::Utils::slurp($full_path);
			unlink $full_path;
			$self->_check_data($seq_ref);
		}
	} elsif ( $q->param('accession') ) {
		try {
			my $acc_seq_ref = $self->_upload_accession;
			if ($acc_seq_ref) {
				$self->_check_data($acc_seq_ref);
			}
		}
		catch {
			if ( $_->isa('BIGSdb::Exception::Data') ) {
				$logger->debug($_);
				if ( $_ eq 'INVALID_ACCESSION' ) {
					$self->print_bad_status( { message => q(Accession is invalid.) } );
				} elsif ( $_ eq 'NO_DATA' ) {
					$self->print_bad_status(
						{ message => q(The accession is valid but it contains no sequence data.) } );
				}
				$self->_print_interface;
			} else {
				$logger->logdie($_);
			}
		};
	} else {
		$self->_print_interface;
	}
	return;
}

sub print_seqbin_warnings {
	my ( $self, $isolate_id ) = @_;
	if ( $isolate_id && BIGSdb::Utils::is_int($isolate_id) ) {
		my $seqbin = $self->{'datastore'}->run_query(
			'SELECT * FROM seqbin_stats WHERE isolate_id=? AND isolate_id IN '
			  . "(SELECT id FROM $self->{'system'}->{'view'})",
			$isolate_id,
			{ fetch => 'row_hashref' }
		);
		my $remote_clause =
		  ( $self->{'system'}->{'remote_contigs'} // q() ) eq 'yes'
		  ? q( Reported total contig length may not be accurate if these refer to remotely hosted contigs which have )
		  . q(not yet been validated.)
		  : q();
		if ($seqbin) {
			say q(<div class="box" id="warning"><p>Sequences have already been uploaded for this isolate.</p>)
			  . qq(<ul><li>Contigs: $seqbin->{'contigs'}</li><li>Total length: $seqbin->{'total_length'} bp</li></ul>)
			  . qq(<p>Please make sure that you intend to add new sequences for this isolate.$remote_clause</p></div>);
		}
	}
	return;
}

sub _print_interface {
	my ( $self, $options ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="queryform"><div class="scrollable">);
	my $icon = $self->get_form_icon( 'sequence_bin', 'plus' );
	say $icon;
	say q(<p>This page allows you to upload sequence data for a specified isolate record in FASTA format.</p>);
	say q(<p><em>Please note that you can reach this page for a specific isolate by )
	  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query">querying isolates</a> )
	  . q(and then clicking 'Upload' within the isolate table.</em></p>);
	say $q->start_form;
	my ( $users, $user_names ) =
	  $self->{'datastore'}->get_users( { blank_message => 'Select sender...' } );
	say q(<p>Please fill in the following fields - required fields are marked with an exclamation mark (!).</p>);
	say q(<fieldset style="float:left"><legend>Paste in sequences in FASTA format:</legend>);
	say $q->hidden($_) foreach qw (page db);
	say $q->textarea( -name => 'data', -rows => 20, -columns => 80 );
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Attributes</legend><ul>);
	my $sender;
	my $isolate_count = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'}");

	if ( $q->param('isolate_id') && !$options->{'error'} ) {
		say q(<li><label class="parameter">isolate id: !</label>);
		my $isolate_id = $q->param('isolate_id');
		my $isolate_name;
		if ( BIGSdb::Utils::is_int($isolate_id) ) {
			$isolate_name =
			  $self->{'datastore'}
			  ->run_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?",
				$isolate_id );
			$isolate_name //= 'Invalid isolate';
			$sender =
			  $self->{'datastore'}
			  ->run_query( "SELECT sender FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id );
		} else {
			$isolate_name = 'Invalid isolate';
		}
		say qq{<span id="isolate_id">$isolate_id) $isolate_name</span>};
		say $q->hidden( 'isolate_id', $isolate_id );
	} elsif ( $isolate_count > MAX_ISOLATES_DROPDOWN ) {
		say q(<li><label for="isolate_id" class="parameter">isolate id: !</label>);
		say $self->textfield(
			-name       => 'isolate_id',
			id          => 'isolate_id',
			required    => 'required',
			type        => 'number',
			placeholder => 'Enter isolate id...'
		);
	} else {
		say q(<li><label for="isolate_id" class="parameter">isolate id: !</label>);
		my $id_arrayref =
		  $self->{'datastore'}
		  ->run_query( "SELECT id,$self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} ORDER BY id",
			undef, { fetch => 'all_arrayref' } );
		my @ids = ('');
		my %labels;
		$labels{''} = 'Select isolate id...';
		foreach (@$id_arrayref) {
			push @ids, $_->[0];
			$labels{ $_->[0] } = "$_->[0]) $_->[1]";
		}
		say $self->popup_menu(
			-name     => 'isolate_id',
			-id       => 'isolate_id',
			-values   => \@ids,
			-labels   => \%labels,
			-required => 'required',
		);
	}
	say q(</li><li><label for="sender" class="parameter">sender: !</label>);
	say $self->popup_menu(
		-name     => 'sender',
		-id       => 'sender',
		-values   => [ '', @$users ],
		-labels   => $user_names,
		-required => 'required',
		-default  => $sender
	);
	say q(</li><li><label for="method" class="parameter">method: </label>);
	my $method_labels = { '' => ' ' };
	say $q->popup_menu( -name => 'method', -id => 'method', -values => [ '', SEQ_METHODS ], -labels => $method_labels );
	say q(</li><li><label for="run_id" class="parameter">run id: </label>);
	say $q->textfield( -name => 'run_id', -id => 'run_id', -size => 32 );
	say q(</li><li><label for="assembly_id" class="parameter">assembly id: </label>);
	say $q->textfield( -name => 'assembly_id', -id => 'assembly_id', -size => 32 );
	my $seq_attributes =
	  $self->{'datastore'}->run_query( 'SELECT key,type,description FROM sequence_attributes ORDER BY key',
		undef, { fetch => 'all_arrayref', slice => {} } );

	if (@$seq_attributes) {
		foreach my $attribute (@$seq_attributes) {
			( my $label = $attribute->{'key'} ) =~ s/_/ /;
			say qq(<li><label for="$attribute->{'key'}" class="parameter">$label:</label>\n);
			say $q->textfield( -name => $attribute->{'key'}, -id => $attribute->{'key'} );
			if ( $attribute->{'description'} ) {
				say $self->get_tooltip(qq($attribute->{'key'} - $attribute->{'description'}.));
			}
		}
	}
	say q(</li></ul></fieldset><fieldset style="float:left"><legend>Options</legend>);
	say q(<ul><li>);
	say $q->checkbox(
		-name    => 'size_filter',
		-label   => q(Don't insert sequences shorter than ),
		-checked => 'checked'
	);
	say $q->popup_menu(
		-name    => 'size',
		-values  => [qw(25 50 100 200 300 400 500 1000)],
		-default => MIN_CONTIG_LENGTH
	);
	say q( bps.);
	say $self->get_tooltip( q(Contig size - There is little point to uploading very short contigs. )
		  . q(They are too short to contain most loci, will simply clutter the database unnecessarily )
		  . q(and slow down BLAST queries.) );
	say q(</li><li>);
	say $q->checkbox(
		-name    => 'remove_homopolymers',
		-label   => q(Don't insert sequences containing only homopolymers.),
		-checked => 'checked'
	);
	say $self->get_tooltip( q(Homopolymers - These are sequences such as 'NNNNNNNNNNNNN' or 'GGGGGGGGGGGGG' )
		  . q(that seem to be produced by some assemblers. There is no benefit to including these in the database.) );
	say q(</li>);
	my @experiments = ('');
	my $exp_data =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id,description FROM experiments ORDER BY description', undef, { fetch => 'all_arrayref' } );
	my $exp_labels = { '' => ' ' };

	foreach my $data (@$exp_data) {
		push @experiments, $data->[0];
		$exp_labels->{ $data->[0] } = $data->[1];
	}
	if ( @experiments > 1 ) {
		say q(<li><label for="experiment" class="parameter">Link to experiment: </label>);
		say $q->popup_menu(
			-name   => 'experiment',
			-id     => 'experiment',
			-values => \@experiments,
			-labels => $exp_labels
		);
		say q(</li>);
	}
	say q(</ul></fieldset>);
	say qq(<fieldset style="float:left">\n<legend>Alternatively upload FASTA file</legend>);
	say q(Select FASTA file: );
	say $self->get_tooltip( q(FASTA files - FASTA files can be either uncompressed (.fas, .fasta) or )
		  . q(gzip/zip compressed (.fas.gz, .fas.zip). ) );
	say q(<div class="fasta_upload">);
	say $q->filefield(
		-name     => 'fasta_upload',
		-id       => 'fasta_upload',
		-onchange => '$("input#fakefile").val(this.files[0].name)'
	);
	say q(<div class="fakefile"><input id='fakefile' placeholder="Click to select or drag and drop..." /></div>);
	say q(</div>);
	say q(</fieldset>);

	if ( !$self->{'config'}->{'intranet'} ) {
		say q(<fieldset style="float:left"><legend>or enter Genbank accession</legend>);
		say $q->textfield( -name => 'accession' );
		say q(</fieldset>);
	}
	my %args =
	  defined $q->param('isolate_id') ? ( isolate_id => scalar $q->param('isolate_id') ) : ();
	$self->print_action_fieldset( \%args );
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _check_data {
	my ( $self, $passed_seq_ref ) = @_;
	my $q        = $self->{'cgi'};
	my $continue = 1;
	if ( !$q->param('isolate_id') ) {
		$self->print_bad_status( { message => q(Isolate id is required.) } );
		$continue = 0;
	} elsif (
		$q->param('isolate_id')
		&& (
			!BIGSdb::Utils::is_int( scalar $q->param('isolate_id') )
			|| !$self->{'datastore'}->run_query(
				"SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)",
				scalar $q->param('isolate_id')
			)
		)
	  )
	{
		$self->print_bad_status( { message => q(Isolate id must be an integer and exist in the isolate table.) } );
		$continue = 0;
	} elsif ( !$q->param('sender')
		|| !BIGSdb::Utils::is_int( scalar $q->param('sender') )
		|| !$self->{'datastore'}
		->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE id=?)', scalar $q->param('sender') ) )
	{
		$self->print_bad_status( { message => q(Sender is required and must exist in the users table.) } );
		$continue = 0;
	}
	my $seq_attributes = $self->{'datastore'}->run_query( 'SELECT key,type FROM sequence_attributes ORDER BY key',
		undef, { fetch => 'all_arrayref', slice => {} } );
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
		$self->print_bad_status( { message => qq(@att_problems) } );
		$continue = 0;
	}
	my $seq_ref;
	if ($continue) {
		try {
			my $data = $q->param('data');
			$seq_ref = BIGSdb::Utils::read_fasta( $passed_seq_ref // \$data, { keep_comments => 1 } );
		}
		catch {
			if ( $_->isa('BIGSdb::Exception::Data') ) {
				if ( $_ =~ /DNA/x ) {
					my $header;
					if ( $_ =~ /DNA\ -\ (.*)$/x ) {
						$header = $1;
					}
					$self->print_bad_status(
						{ message => qq(FASTA data '$header' contains non-valid nucleotide characters.) } );
					$continue = 0;
				} else {
					$self->print_bad_status( { message => q(Sequence data is not in valid FASTA format.) } );
					$continue = 0;
				}
			} else {
				$logger->logdie($_);
			}
		};
	}
	if ( !$continue ) {
		$self->_print_interface( { error => 1 } );
		return;
	}
	$self->_check_records( $seq_ref, $seq_attributes );
	return;
}

sub _check_records {
	my ( $self, $seq_ref, $seq_attributes ) = @_;
	my $q              = $self->{'cgi'};
	my $checked_buffer = [];
	my $td             = 1;
	my $min_size       = 0;
	if ( $q->param('size_filter') && BIGSdb::Utils::is_int( scalar $q->param('size') ) ) {
		$min_size = $q->param('size');
	}
	my $buffer;
	foreach my $contig_id ( sort { $a cmp $b } keys %$seq_ref ) {
		my $length = length( $seq_ref->{$contig_id} );
		next if $length < $min_size;
		next if $q->param('remove_homopolymers') && BIGSdb::Utils::is_homopolymer( $seq_ref, $contig_id );
		push @$checked_buffer, ">$contig_id";
		push @$checked_buffer, $seq_ref->{$contig_id};
		my ( $designation, $comments );
		if ( $contig_id =~ /(\S*)\s+(.*)/x ) {
			( $designation, $comments ) = ( $1, $2 );
		} else {
			$designation = $contig_id;
		}
		$buffer .= qq(<tr class="td$td"><td>$designation</td>);
		$buffer .= qq(<td>$length</td>);
		$buffer .= defined $comments ? qq(<td>$comments</td>) : q(<td></td>);
		$buffer .= qq(</tr>\n);
		$td = $td == 1 ? 2 : 1;
	}
	if ($buffer) {
		say q(<div class="box" id="resultstable">);
		say q(<fieldset style="float:left"><legend>The following sequences will be entered.</legend>);
		say q(<table class="resultstable"><tr><th>Original designation</th>)
		  . q(<th>Sequence length</th><th>Comments</th></tr>);
		say $buffer if $buffer;
		say q(</table></fieldset>);
		my $num;
		my $min = 0;
		my $max = 0;
		my ( $mean, $total );
		my @lengths;

		foreach my $contig_id ( keys %$seq_ref ) {
			my $length = length( $seq_ref->{$contig_id} );
			next if $length < $min_size;
			next if $q->param('remove_homopolymers') && BIGSdb::Utils::is_homopolymer( $seq_ref, $contig_id );
			$min = $length if !$min || $length < $min;
			$max = $length if $length > $max;
			$total += $length;
			push @lengths, $length;
			$num++;
		}
		@lengths = sort { $b <=> $a } @lengths;
		$mean = int $total / $num if $num;
		my $n_stats = BIGSdb::Utils::get_N_stats( $total, \@lengths );
		say q(<fieldset style="float:left"><legend>Summary</legend>);
		say $self->get_list_block(
			[
				{ title => 'Number of contigs', data => BIGSdb::Utils::commify($num) },
				{ title => 'Minimum length',    data => BIGSdb::Utils::commify($min) },
				{ title => 'Maximum length',    data => BIGSdb::Utils::commify($max) },
				{ title => 'Total length',      data => BIGSdb::Utils::commify($total) },
				{ title => 'Mean length',       data => BIGSdb::Utils::commify($mean) },
				{ title => 'N50',               data => BIGSdb::Utils::commify( $n_stats->{'N50'} ) },
				{ title => 'L50',               data => BIGSdb::Utils::commify( $n_stats->{'L50'} ) },
				{ title => 'N90',               data => BIGSdb::Utils::commify( $n_stats->{'N90'} ) },
				{ title => 'L50',               data => BIGSdb::Utils::commify( $n_stats->{'L90'} ) },
				{ title => 'N95',               data => BIGSdb::Utils::commify( $n_stats->{'N95'} ) },
				{ title => 'L95',               data => BIGSdb::Utils::commify( $n_stats->{'L95'} ) },
			],
			{ width => 15 }
		);
		say q(</fieldset>);
		say $q->start_form;
		$self->print_action_fieldset( { no_reset => 1, submit_label => 'Upload' } );
		my $filename = $self->make_temp_file(@$checked_buffer);
		$q->param( 'checked_buffer', $filename );
		say $q->hidden($_)
		  foreach qw (db page checked_buffer isolate_id sender method run_id assembly_id comments experiment);
		say $q->hidden( $_->{'key'} ) foreach (@$seq_attributes);
		say $q->end_form;
	} else {
		$self->print_bad_status( { message => q(No valid sequences to upload.) } );
	}
	say q(</div>);
	return;
}

sub _upload {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $dir      = $self->{'config'}->{'secure_tmp_dir'};
	my $tmp_file = $dir . '/' . $q->param('checked_buffer');
	my $fasta_ref;
	if ( -e $tmp_file ) {
		$fasta_ref = BIGSdb::Utils::slurp($tmp_file);
	} else {
		$self->print_bad_status(
			{
				message   => q(Checked temporary file is no longer available. Please start again.),
				navbar    => 1,
				back_page => 'addSeqbin'
			}
		);
		return;
	}
	my $seq_ref;
	my $continue = 1;
	try {
		$seq_ref = BIGSdb::Utils::read_fasta( $fasta_ref, { keep_comments => 1 } );
	}
	catch {
		if ( $_->isa('BIGSdb::Exception::Data') ) {
			$logger->error('Invalid FASTA file');
			$continue = 0;
		} else {
			$logger->logdie($_);
		}
	};
	if ( $tmp_file =~ /^(.*\/BIGSdb_[0-9_]+)$/x ) {
		$logger->info("Deleting temp file $tmp_file");
		unlink $1;
	} else {
		$logger->error("Can't delete temp file $tmp_file");
	}
	if ( !$continue ) {
		$self->print_bad_status(
			{
				message   => q(Unable to upload sequences. Please try again.),
				navbar    => 1,
				back_page => 'addSeqbin'
			}
		);
		return;
	}
	my $qry = 'INSERT INTO sequence_bin (isolate_id,sequence,method,run_id,assembly_id,original_designation,'
	  . 'comments,sender,curator,date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?,?,?,?)';
	my $sql = $self->{'db'}->prepare($qry);
	$qry = 'INSERT INTO experiment_sequences (experiment_id,seqbin_id,curator,datestamp) VALUES (?,?,?,?)';
	my $sql_experiment = $self->{'db'}->prepare($qry);
	my $experiment     = BIGSdb::Utils::is_int( scalar $q->param('experiment') ) ? $q->param('experiment') : undef;
	my $curator        = $self->get_curator_id;
	my $sender         = $q->param('sender');
	my $seq_attributes = $self->{'datastore'}->run_query( 'SELECT key,type FROM sequence_attributes ORDER BY key',
		undef, { fetch => 'all_arrayref', slice => {} } );
	my @attribute_sql;

	if (@$seq_attributes) {
		foreach my $attribute (@$seq_attributes) {
			if ( $q->param( $attribute->{'key'} ) ) {
				( my $value = $q->param( $attribute->{'key'} ) ) =~ s/'/\\'/gx;
				$qry = q(INSERT INTO sequence_attribute_values (seqbin_id,key,value,curator,datestamp) VALUES )
				  . qq((?,'$attribute->{'key'}',E'$value',$curator,'now'));
				push @attribute_sql, $self->{'db'}->prepare($qry);
			}
		}
	}
	eval {
		foreach ( keys %$seq_ref ) {
			my ( $designation, $comments );
			if ( $_ =~ /(\S*)\s+(.*)/x ) {
				( $designation, $comments ) = ( $1, $2 );
			} else {
				$designation = $_;
			}
			my $isolate_id = $q->param('isolate_id') ? $q->param('isolate_id') : $designation;
			undef $designation if !$q->param('isolate_id') || $designation eq q();
			foreach my $field (qw(method run_id assembly_id)) {
				$q->delete($field) if defined $q->param($field) && $q->param($field) eq q();
			}
			my @values = (
				$isolate_id, $seq_ref->{$_},
				$q->param('method')      // undef,
				$q->param('run_id')      // undef,
				$q->param('assembly_id') // undef,
				$designation, $comments, $sender, $curator, 'now', 'now'
			);
			$sql->execute(@values);
			my $id = $self->{'db'}->last_insert_id( undef, undef, 'sequence_bin', 'id' );
			$sql_experiment->execute( $experiment, $id, $curator, 'now' ) if $experiment;
			$_->execute($id) foreach @attribute_sql;
		}
	};
	if ($@) {
		local $" = ', ';
		my $message = 'Failed! - transaction cancelled - no records have been touched.';
		my $detail;
		if ( $@ =~ /duplicate/x && $@ =~ /unique/x ) {
			$detail = q(Data entry would have resulted in records with either duplicate ids or )
			  . q(another unique field with duplicate values.);
		} else {
			$detail = qq(Error message: $@);
		}
		$self->print_bad_status( { message => $message, detail => $detail } );
		$self->{'db'}->rollback;
		return;
	} else {
		$self->{'db'}->commit;
		$self->print_good_status(
			{
				message  => q(Sequences uploaded.),
				navbar   => 1,
				more_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=addSeqbin&amp;)
				  . qq(sender=$sender")
			}
		);
	}
	return;
}

sub _upload_fasta_file {
	my ($self)   = @_;
	my $temp     = BIGSdb::Utils::get_random();
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/${temp}_upload.fas";
	my $buffer;
	my $fh2 = $self->{'cgi'}->upload('fasta_upload');
	binmode $fh2;
	read( $fh2, $buffer, $self->{'config'}->{'max_upload_size'} );
	my $ft        = File::Type->new;
	my $file_type = $ft->checktype_contents($buffer);
	my $method    = {
		'application/x-gzip' => sub { gunzip \$buffer => $filename or $logger->error("gunzip failed: $GunzipError"); },
		'application/zip'    => sub { unzip \$buffer  => $filename or $logger->error("unzip failed: $UnzipError"); }
	};

	if ( $method->{$file_type} ) {
		$method->{$file_type}->();
		return "${temp}_upload.fas";
	}
	open( my $fh, '>', $filename ) || $logger->error("Cannot open $filename for writing.");
	binmode $fh;
	print $fh $buffer;
	close $fh;
	return "${temp}_upload.fas";
}

sub _upload_accession {
	my ($self)    = @_;
	my $accession = $self->{'cgi'}->param('accession');
	my $seq_db    = Bio::DB::GenBank->new;
	$seq_db->retrieval_type('tempfile');    #prevent forking resulting in duplicate error message on fail.
	my $sequence;
	try {
		my $seq_obj = $seq_db->get_Seq_by_acc($accession);
		$sequence = $seq_obj->seq;
	}
	catch {
		my $err = shift;
		$logger->debug($err);
		BIGSdb::Exception::Data->throw('INVALID_ACCESSION');
	};
	if ( !length($sequence) ) {
		BIGSdb::Exception::Data->throw('NO_DATA');
	}
	return \">$accession\n$sequence";
}

sub get_title {
	my ($self) = @_;
	return 'Add new sequences';
}
1;
