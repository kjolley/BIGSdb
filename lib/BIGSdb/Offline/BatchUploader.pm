#Written by Keith Jolley
#Copyright (c) 2021-2024, University of Oxford
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
package BIGSdb::Offline::BatchUploader;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Script);
use BIGSdb::Constants qw(:limits);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use Try::Tiny;
use JSON;

sub upload {
	my ($self) = @_;
	my (
		$records,       $username,    $field_order, $fields_to_include, $table,
		$locus,         $project_id,  $private,     $curator_id,        $sender_id,
		$submission_id, $status_file, $success_html
	  )
	  = @{ $self->{'params'} }{
		qw(records username field_order fields_to_include table locus project_id private curator_id sender_id
		  submission_id status_file success_html)
	  };
	$self->{'curator_id'} = $curator_id;
	$self->{'sender_id'}  = $sender_id;
	my $user_info = $self->{'datastore'}->get_user_info_from_username($username);
	my $field_att = $self->{'xmlHandler'}->get_all_field_attributes;
	my %loci;
	$loci{$locus} = 1 if $locus;
	my $status_filepath = qq($self->{'config'}->{'tmp_dir'}/$status_file);
	my $i               = 0;
	my %allow_null_term = map { $_ => 1 } qw(validation_conditions);
	my $isolate_ids     = [];

	foreach my $record (@$records) {
		$self->_update_status(
			$status_file,
			{
				status   => 'uploading',
				progress => int( $i * 100 / @$records )
			}
		);
		$i++;
		$record =~ s/\r//gx;
		next if !$record;
		my $data = [ split /\t/x, $record ];
		if ( $table eq 'isolates' ) {
			push @$isolate_ids, $data->[0];
		}
		@$data = $self->_process_fields( $data, { allow_null => $allow_null_term{$table} } );
		my @value_list;
		my ( @extras, @ref_extras, $codon_table );
		my $id;
		my $sender = $self->_get_sender( $field_order, $data, $user_info->{'status'} );
		foreach my $field (@$fields_to_include) {
			$id = $data->[ $field_order->{$field} ] if $field eq 'id';
			$self->_process_multivalues( $field_att, $field_order, $field, $data );
			push @value_list,
			  $self->_read_value(
				{
					table       => $table,
					field       => $field,
					field_order => $field_order,
					data        => $data,
					locus       => $locus,
					user_status => ( $user_info->{'status'} // undef ),
				}
			  ) // undef;
		}
		$loci{ $data->[ $field_order->{'locus'} ] } = 1 if defined $field_order->{'locus'};
		if ( $table eq 'loci' || $table eq 'isolates' ) {
			@extras = split /;/x, $data->[ $field_order->{'aliases'} ]
			  if defined $field_order->{'aliases'} && defined $data->[ $field_order->{'aliases'} ];
			@ref_extras = split /;/x, $data->[ $field_order->{'references'} ]
			  if defined $field_order->{'references'} && defined $data->[ $field_order->{'references'} ];
		}
		if ( $table eq 'isolates' && ( $self->{'system'}->{'alternative_codon_tables'} // q() ) eq 'yes' ) {
			$codon_table = $data->[ $field_order->{'codon_table'} ]
			  if defined $field_order->{'codon_table'} && defined $data->[ $field_order->{'codon_table'} ];
		}
		my @inserts;
		my $qry;
		local $" = ',';
		my @placeholders = ('?') x @$fields_to_include;
		$qry = "INSERT INTO $table (@$fields_to_include) VALUES (@placeholders)";
		push @inserts, { statement => $qry, arguments => \@value_list };
		if ( $table eq 'allele_designations' ) {
			my $action = "$data->[$field_order->{'locus'}]: new designation '$data->[$field_order->{'allele_id'}]'";
			push @inserts,
			  {
				statement => 'INSERT INTO history (isolate_id,timestamp,action,curator) VALUES '
				  . '(?,clock_timestamp()::TIMESTAMP,?,?)',
				arguments => [ $data->[ $field_order->{'isolate_id'} ], $action, $self->{'curator_id'} ]
			  };
		}
		my ( $upload_err, $failed_file );
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
			my $isolate_name = $data->[ $field_order->{ $self->{'system'}->{'labelfield'} } ];
			$self->{'submission_message'} .= "Isolate '$isolate_name' uploaded - id: $id.";
			my $isolate_extra_inserts = $self->_prepare_isolate_extra_inserts(
				{
					id          => $id,
					sender      => $sender,
					curator     => $curator_id,
					data        => $data,
					field_order => $field_order,
					extras      => \@extras,
					ref_extras  => \@ref_extras,
					codon_table => $codon_table,
					project_id  => $project_id,
					private     => $private
				}
			);
			push @inserts, @$isolate_extra_inserts;
			try {
				my ( $contigs_extra_inserts, $message ) = $self->_prepare_contigs_extra_inserts(
					{
						id            => $id,
						sender        => $sender,
						curator       => $curator_id,
						data          => $data,
						field_order   => $field_order,
						submission_id => $submission_id
					}
				);
				push @inserts, @$contigs_extra_inserts;
			} catch {
				if ( $_->isa('BIGSdb::Exception::Data') ) {
					if ( $_ =~ 'Not valid DNA' ) {
						$upload_err = 'Invalid characters';
					} else {
						$upload_err = 'Invalid FASTA file';
					}
					$failed_file = $data->[ $field_order->{'assembly_filename'} ];
				} else {
					$self->{'logger'}->logdie($_);
				}
			};
			$self->{'submission_message'} .= "\n";
			push @inserts,
			  {
				statement => 'INSERT INTO history (isolate_id,timestamp,action,curator) VALUES (?,?,?,?)',
				arguments => [ $id, 'now', 'Isolate record added', $self->{'curator_id'} ]
			  };
		}
		my $extra_methods = {
			loci => sub {
				return $self->_prepare_loci_extra_inserts(
					{
						id          => $id,
						curator     => $curator_id,
						data        => $data,
						field_order => $field_order,
						extras      => \@extras
					}
				);
			},
			projects => sub {
				return $self->_prepare_projects_extra_inserts(
					{
						id          => $id,
						curator     => $curator_id,
						data        => $data,
						field_order => $field_order,
					}
				);
			}
		};
		if ( $extra_methods->{$table} ) {
			my $extra_inserts = $extra_methods->{$table}->();
			push @inserts, @$extra_inserts;
		}
		eval {
			foreach my $insert (@inserts) {
				$self->{'db'}->do( $insert->{'statement'}, undef, @{ $insert->{'arguments'} } );
			}
		};
		if ( $@ || $upload_err ) {
			my $html = $self->_get_error_message( ( $upload_err // $@ ), $failed_file );
			$self->_update_status(
				$status_file,
				{
					status => 'finished',
					html   => $html
				}
			);
			$self->{'db'}->rollback;
			return;
		}
	}
	$self->_update_status(
		$status_file,
		{
			status   => 'finished',
			progress => 100,
			html     => $success_html
		}
	);
	if ($submission_id) {
		$self->_update_submission_database($submission_id);
		if ( $table eq 'isolates' ) {
			$self->_set_embargo( $submission_id, $isolate_ids );
		}
	}
	$self->{'db'}->commit;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		$self->_update_scheme_caches if ( $self->{'system'}->{'cache_schemes'} // q() ) eq 'yes';
	}
	return;
}

sub _set_embargo {
	my ( $self, $submission_id, $isolate_ids ) = @_;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission->{'embargo'};
	if ( $submission->{'embargo'} ) {
		eval {
			foreach my $isolate_id (@$isolate_ids) {
				if ( !BIGSdb::Utils::is_int($isolate_id) ) {
					$self->{'logger'}->error("Isolate id not integer - $isolate_id");
					next;
				}
				my $embargo_date = BIGSdb::Utils::get_future_date( $submission->{'embargo'} );
				$self->{'db'}->do(
					q[INSERT INTO private_isolates (isolate_id,user_id,datestamp,embargo) VALUES (?,?,?,?)],
					undef, $isolate_id, $submission->{'submitter'},
					'now', $embargo_date
				);
				$self->{'db'}->do(
					q[INSERT INTO embargo_history (isolate_id,timestamp,action,embargo,curator) VALUES (?,?,?,?,?)],
					undef, $isolate_id, 'now', 'Initial embargo',
					$embargo_date, $self->{'curator_id'}
				);
			}
		};
		if ($@) {
			$self->{'logger'}->error($@);
			$self->{'db'}->rollback;
		} 
	}
	return;
}

sub _get_error_message {
	my ( $self, $error, $failed_file ) = @_;
	my $detail;
	if ( $error eq 'Invalid FASTA file' ) {
		$detail = qq(The contig file '$failed_file' was not in valid FASTA format.);
	} elsif ( $error eq 'Invalid characters' ) {
		$detail =
			qq(The contig file '$failed_file' contains invalid characters. )
		  . q(Allowed IUPAC nucleotide codes are GATCUBDHVRYKMSWN.');
	} elsif ( $error =~ /duplicate/ && $error =~ /unique/ ) {
		$detail =
			q(Data entry would have resulted in records with either duplicate ids or another )
		  . q(unique field with duplicate values. This can result from pressing the upload button twice )
		  . q(or another curator adding data at the same time. Try pressing the browser back button twice )
		  . q(and then re-submit the records.);
	} else {
		$detail = q(An error has occurred - more details will be available in the server log.);
		$self->{'logger'}->error($error);
	}
	my $buffer = q();
	$buffer .= q(<div class="box statusbad" style="min-height:5em">);
	$buffer .= q(<p><span class="failure fas fa-times fa-5x fa-pull-left"></span></p>);
	$buffer .= q(<p class="outcome_message">Database update failed - transaction cancelled - )
	  . q(no records have been touched.</p>);
	$buffer .= qq(<p class="outcome_detail">$detail</p>);
	$buffer .= q(</div>);
	return $buffer;
}

sub _update_status {
	my ( $self, $status_file, $values ) = @_;
	my $file_path = qq($self->{'config'}->{'tmp_dir'}/$status_file);
	open my $fh, '>', $file_path || $self->{'logger'}->error("Cannot open $file_path for writing.");
	my $json = encode_json($values);
	say $fh $json;
	close $fh;
	return;
}

sub _process_fields {
	my ( $self, $data, $options ) = @_;
	my @return_data;
	foreach my $value (@$data) {
		$value =~ s/^\s+//x;
		$value =~ s/\s+$//x;
		$value =~ s/\r//gx;
		$value =~ s/\n/ /gx;
		$value =~ s/^null$//gxi if !$options->{'allow_null'};
		if ( $value eq q() ) {
			push @return_data, undef;
		} else {
			push @return_data, $value;
		}
	}
	return @return_data;
}

sub _get_sender {
	my ( $self, $field_order, $data, $user_status ) = @_;
	if ( $user_status eq 'submitter' ) {
		return $self->{'curator_id'};
	} elsif ( defined $field_order->{'sender'}
		&& defined $data->[ $field_order->{'sender'} ] )
	{
		return $data->[ $field_order->{'sender'} ];
	}
	if ( $self->{'sender_id'} ) {
		return $self->{'sender_id'};
	}
	return;
}

#Convert from semi-colon separated list in to an arrayref.
sub _process_multivalues {
	my ( $self, $field_att, $field_order, $field, $data ) = @_;
	my $divider = q(;);
	if (   ( $field_att->{$field}->{'multiple'} // q() ) eq 'yes'
		&& defined $field_order->{$field}
		&& defined $data->[ $field_order->{$field} ] )
	{
		$data->[ $field_order->{$field} ] = [ split /$divider/x, $data->[ $field_order->{$field} ] ];
		s/^\s+|\s+$//gx foreach @{ $data->[ $field_order->{$field} ] };
	}
	return;
}

sub _read_value {
	my ( $self, $args ) = @_;
	my ( $table, $field, $field_order, $data, $locus, $user_status ) =
	  @{$args}{qw(table field field_order data locus user_status )};
	if ( $field eq 'date_entered' || $field eq 'datestamp' ) {
		return 'now';
	}
	if ( $field eq 'curator' ) {
		return $self->{'curator_id'};
	}
	if ( $field eq 'sender' && $user_status eq 'submitter' ) {
		return $self->{'curator_id'};
	}
	if ( $table eq 'geography_point_lookup' && $field eq 'location' ) {
		if ( $data->[ $field_order->{$field} ] =~ /^\s*(\-?\d+\.?\d*)\s*,\s*(\-?\d+\.?\d*)\s*$/x ) {
			$data->[ $field_order->{$field} ] = $self->{'datastore'}->convert_coordinates_to_geography( $1, $2 );
		}
	}
	if ( defined $field_order->{$field} && defined $data->[ $field_order->{$field} ] ) {
		return $data->[ $field_order->{$field} ];
	}
	if ( $field eq 'sender' ) {
		return $self->{'sender_id'} ? $self->{'sender_id'} : undef;
	}
	if ( $table eq 'sequences' && !defined $field_order->{$field} && $locus && $field eq 'locus' ) {
		return $locus;
	}
	return;
}

sub _prepare_isolate_extra_inserts {
	my ( $self, $args ) = @_;
	my ( $id, $sender, $curator, $data, $field_order, $extras, $ref_extras, $codon_table, $project_id, $private ) =
	  @{$args}{qw(id sender curator data field_order extras ref_extras codon_table project_id private)};
	my @inserts;
	my $hidden_defaults = $self->_get_hidden_field_defaults;
	foreach my $field ( keys %$hidden_defaults ) {
		next if $hidden_defaults->{$field} eq q();
		push @inserts,
		  {
			statement => "UPDATE isolates SET $field=? WHERE id=?",
			arguments => [ $hidden_defaults->{$field}, $id ]
		  };
	}
	my $locus_list = $self->_get_locus_list;
	foreach (@$locus_list) {
		next if !$field_order->{$_};
		next if !defined $field_order->{$_};
		my $value = $data->[ $field_order->{$_} ];
		$value //= q();
		$value =~ s/^\s+|\s+$//gx;
		next if $value eq q();
		my $qry =
			'INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,'
		  . 'date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?,?)';
		push @inserts,
		  {
			statement => $qry,
			arguments => [ $id, $_, $value, $sender, 'confirmed', 'manual', $curator, 'now', 'now' ]
		  };
	}
	my $eav_fields = $self->{'datastore'}->get_eav_fields;
	foreach my $field (@$eav_fields) {
		my $fieldname = $field->{'field'};
		next if !$field_order->{$fieldname};
		next if !defined $field_order->{$fieldname};
		my $value = $data->[ $field_order->{$fieldname} ];
		$value =~ s/^\s+|\s+$//gx;
		next if $value eq q();
		my $table = $self->{'datastore'}->get_eav_table( $field->{'value_format'} );
		push @inserts,
		  {
			statement => "INSERT INTO $table (isolate_id,field,value) VALUES (?,?,?)",
			arguments => [ $id, $fieldname, $value ]
		  };
	}
	foreach (@$extras) {
		next if !defined $_;
		$_ =~ s/^\s*//gx;
		$_ =~ s/\s*$//gx;
		if ( $_ && $_ ne $id && defined $data->[ $field_order->{ $self->{'system'}->{'labelfield'} } ] ) {
			my $qry = 'INSERT INTO isolate_aliases (isolate_id,alias,curator,datestamp) VALUES (?,?,?,?)';
			push @inserts, { statement => $qry, arguments => [ $id, $_, $curator, 'now' ] };
		}
	}
	foreach (@$ref_extras) {
		next if !defined $_;
		$_ =~ s/^\s*//gx;
		$_ =~ s/\s*$//gx;
		if ( $_ && $_ ne $id && defined $data->[ $field_order->{ $self->{'system'}->{'labelfield'} } ] ) {
			if ( BIGSdb::Utils::is_int($_) ) {
				my $qry = 'INSERT INTO refs (isolate_id,pubmed_id,curator,datestamp) VALUES (?,?,?,?)';
				push @inserts, { statement => $qry, arguments => [ $id, $_, $curator, 'now' ] };
			}
		}
	}
	if ( defined $codon_table ) {
		push @inserts,
		  {
			statement => 'INSERT INTO codon_tables (isolate_id,codon_table,curator,datestamp) VALUES (?,?,?,?)',
			arguments => [ $id, $codon_table, $curator, 'now' ]
		  };
	}
	if ($project_id) {
		push @inserts,
		  {
			statement => 'INSERT INTO project_members (project_id,isolate_id,curator,datestamp) VALUES (?,?,?,?)',
			arguments => [ $project_id, $id, $curator, 'now' ]
		  };
	}
	if ($private) {
		push @inserts,
		  {
			statement => 'INSERT INTO private_isolates (isolate_id,user_id,datestamp) VALUES (?,?,?)',
			arguments => [ $id, $curator, 'now' ]
		  };
	}
	return \@inserts;
}

sub _prepare_contigs_extra_inserts {
	my ( $self, $args ) = @_;
	my ( $id, $sender, $curator, $data, $field_order, $submission_id ) =
	  @{$args}{qw(id sender curator data field_order submission_id)};
	$self->setup_submission_handler;
	return [] if !$submission_id || !defined $field_order->{'assembly_filename'};
	my $dir      = $self->{'submissionHandler'}->get_submission_dir($submission_id) . '/supporting_files';
	my $filename = "$dir/" . $data->[ $field_order->{'assembly_filename'} ];
	return [] if !-e $filename;
	my $seq_ref;
	my $fasta_ref = BIGSdb::Utils::slurp($filename);
	my $ft        = File::Type->new;
	my $file_type = $ft->checktype_contents($$fasta_ref);
	my $uncompressed;
	my $size;
	my $file_was_compressed = q();
	my $method              = {
		'application/x-gzip' =>
		  sub { gunzip $fasta_ref => \$uncompressed or $self->{'logger'}->error("gunzip failed: $GunzipError"); },
		'application/zip' =>
		  sub { unzip $fasta_ref => \$uncompressed or $self->{'logger'}->error("unzip failed: $UnzipError"); }
	};

	if ( $method->{$file_type} ) {
		$method->{$file_type}->();
		$seq_ref             = BIGSdb::Utils::read_fasta( \$uncompressed, { keep_comments => 1 } );
		$size                = BIGSdb::Utils::get_nice_size( length $uncompressed );
		$file_was_compressed = ' uncompressed';
	} else {
		$seq_ref = BIGSdb::Utils::read_fasta( $fasta_ref, { keep_comments => 1 } );
		$size    = BIGSdb::Utils::get_nice_size( -s $filename );
	}
	my @inserts;
	$self->{'submission_message'} .=
	  " Contig file '$data->[$field_order->{'assembly_filename'}]' ($size$file_was_compressed) uploaded.";
	foreach my $contig_name ( keys %$seq_ref ) {
		next if length $seq_ref->{$contig_name} < MIN_CONTIG_LENGTH;
		next if BIGSdb::Utils::is_homopolymer( $seq_ref, $contig_name );
		push @inserts,
		  {
			statement => 'INSERT INTO sequence_bin (isolate_id,sequence,method,original_designation,'
			  . 'sender,curator,date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?)',
			arguments => [
				$id,
				$seq_ref->{$contig_name},
				$data->[ $field_order->{'sequence_method'} ],
				$contig_name, $sender, $curator, 'now', 'now'
			]
		  };
	}
	return \@inserts;
}

sub _prepare_loci_extra_inserts {
	my ( $self, $args ) = @_;
	my ( $id, $curator, $data, $field_order, $extras ) = @{$args}{qw(id curator data field_order extras)};
	my @inserts;
	foreach (@$extras) {
		$_ =~ s/^\s*//gx;
		$_ =~ s/\s*$//gx;
		if ( defined $_ && $_ ne $id ) {
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
				my $qry = 'INSERT INTO locus_aliases (locus,alias,use_alias,curator,datestamp) VALUES (?,?,?,?,?)';
				push @inserts, { statement => $qry, arguments => [ $id, $_, 'TRUE', $curator, 'now' ] };
			} else {
				my $qry = 'INSERT INTO locus_aliases (locus,alias,curator,datestamp) VALUES (?,?,?,?)';
				push @inserts, { statement => $qry, arguments => [ $id, $_, $curator, 'now' ] };
			}
		}
	}
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $full_name = defined $field_order->{'full_name'} ? $data->[ $field_order->{'full_name'} ] : undef;
		my $product   = defined $field_order->{'product'}
		  && $data->[ $field_order->{'product'} ] ? $data->[ $field_order->{'product'} ] : undef;
		my $description =
		  defined $field_order->{'description'} ? $data->[ $field_order->{'description'} ] : undef;
		my $qry =
			'INSERT INTO locus_descriptions (locus,curator,datestamp,full_name,product,description) '
		  . 'VALUES (?,?,?,?,?,?)';
		push @inserts, { statement => $qry, arguments => [ $id, $curator, 'now', $full_name, $product, $description ] };
	}
	return \@inserts;
}

sub _prepare_projects_extra_inserts {
	my ( $self, $args ) = @_;
	my ( $id, $curator, $data, $field_order ) = @{$args}{qw(id curator data field_order )};
	my $private = $data->[ $field_order->{'private'} ];
	my %true    = map { $_ => 1 } qw(1 true);
	my @inserts;
	if ( $true{ lc $private } ) {
		my $project_id = $data->[ $field_order->{'id'} ];
		my $qry = 'INSERT INTO project_users (project_id,user_id,admin,modify,curator,datestamp) VALUES (?,?,?,?,?,?)';
		push @inserts,
		  {
			statement => $qry,
			arguments => [ $project_id, $curator, 'true', 'true', $curator, 'now' ]
		  };
	}
	return \@inserts;
}

sub _update_scheme_caches {
	my ($self) = @_;
	BIGSdb::Offline::UpdateSchemeCaches->new(
		{
			config_dir       => $self->{'config_dir'},
			lib_dir          => $self->{'lib_dir'},
			dbase_config_dir => $self->{'dbase_config_dir'},
			instance         => $self->{'system'}->{'curate_config'} // $self->{'instance'},
			options          => { method => 'daily' }
		}
	);
	return;
}

sub _update_submission_database {
	my ( $self, $submission_id ) = @_;
	eval {
		$self->{'db'}->do( 'UPDATE submissions SET outcome=? WHERE id=?', undef, 'good', $submission_id );
		$self->{'db'}->do( 'INSERT INTO messages (submission_id,timestamp,user_id,message) VALUES (?,?,?,?)',
			undef, $submission_id, 'now', $self->{'curator_id'}, $self->{'submission_message'} );
	};
	if ($@) {
		$self->{'logger'}->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->{'submissionHandler'}
		  ->append_message( $submission_id, $self->{'curator_id'}, $self->{'submission_message'} );
	}
	return;
}

sub _get_locus_list {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'loci'} ) {
		$self->{'cache'}->{'loci'} = $self->{'datastore'}->get_loci;
	}
	return $self->{'cache'}->{'loci'};
}

sub _get_hidden_field_defaults {
	my ($self) = @_;
	if ( !defined $self->{'cache'}->{'hidden_defaults'} ) {
		$self->{'cache'}->{'hidden_defaults'} = {};
		my $atts = $self->{'xmlHandler'}->get_all_field_attributes;
		foreach my $field ( keys %$atts ) {
			next if ( $atts->{$field}->{'hide'} // q() ) ne 'yes';
			next if !defined $atts->{$field}->{'default'};
			$self->{'cache'}->{'hidden_defaults'}->{$field} = $atts->{$field}->{'default'};
		}
	}
	return $self->{'cache'}->{'hidden_defaults'};
}
1;
