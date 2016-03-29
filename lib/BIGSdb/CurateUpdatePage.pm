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
package BIGSdb::CurateUpdatePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use BIGSdb::Utils;
use List::MoreUtils qw(any none);
use BIGSdb::Constants qw(ALLELE_FLAGS SUBMITTER_ALLOWED_PERMISSIONS DATABANKS);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant FAILURE => 2;

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery jQuery.multiselect noCache);
	return;
}

#Sanity check table and user permissions
sub _pre_check_failed {
	my ( $self, $table ) = @_;
	my $q = $self->{'cgi'};
	if (   !$self->{'datastore'}->is_table($table)
		&& !( $table eq 'samples' && @{ $self->{'xmlHandler'}->get_sample_field_list } ) )
	{
		say qq(<div class="box" id="statusbad"><p>Table $table does not exist!</p></div>);
		return 1;
	}
	if ( !$self->can_modify_table($table) ) {
		say q(<div class="box" id="statusbad"><p>Your user account is not )
		  . q(allowed to update this record.</p></div>);
		return 1;
	}
	if ( $table eq 'allele_sequences' ) {
		say q(<div class="box" id="statusbad"><p>Sequence tags cannot be updated ) . q(using this function.</p></div>);
		return 1;
	}
	if ( $table eq 'scheme_fields' && $self->{'system'}->{'dbtype'} eq 'sequences' && !$q->param('sent') ) {
		say q(<div class="box" id="warning"><p>Please be aware that any changes to the )
		  . q(structure of a scheme will result in all data being removed from it. This )
		  . q(will happen if you modify the type or change whether the field is a primary key. )
		  . q(All other changes are ok.</p>);
		if ( ( $self->{'system'}->{'materialized_views'} // '' ) eq 'yes' ) {
			say q(<p>If you change the index status of a field you will also need to rebuild the )
			  . q(scheme table to reflect this change. This can be done by selecting 'Configuration )
			  . q(repair' on the main curation page.</p>);
		}
		say q(</div>);
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $table  = $q->param('table');
	my $record_name = $self->get_record_name($table) // 'record';
	say qq(<h1>Update $record_name</h1>);
	return if $self->_pre_check_failed($table);
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my ( @query_terms, @query_values );

	foreach my $att (@$attributes) {
		my $value = $q->param( $att->{'name'} );
		next if !defined $value;
		if ( $att->{'primary_key'} ) {
			push @query_terms,  qq($att->{name}=?);
			push @query_values, $value;
		}
	}
	if ( !@query_values ) {
		say q(<div class="box" id="statusbad"><p>No identifying attributes sent.</p>);
		return;
	}
	local $" = q( AND );
	my $record_count =
	  $self->{'datastore'}->run_query( "SELECT COUNT(*) FROM $table WHERE @query_terms", \@query_values );
	if ( $record_count != 1 ) {
		say q(<div class="box" id="statusbad"><p>The search terms did not unique identify a single record.</p></div>);
		return;
	}
	my $data =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM $table WHERE @query_terms", \@query_values, { fetch => 'row_hashref' } );
	if ( $table eq 'sequences' ) {
		my $ext_dataset = $self->{'datastore'}->run_query(
			'SELECT field,value FROM sequence_extended_attributes WHERE (locus,allele_id)=(?,?)',
			[ $data->{'locus'}, $data->{'allele_id'} ],
			{ fetch => 'all_arrayref', slice => {} }
		);
		foreach my $ext_data (@$ext_dataset) {
			$data->{ $ext_data->{'field'} } = $ext_data->{'value'};
		}
	}
	my $buffer = $self->create_record_table( $table, $data, { update => 1 } );
	my %newdata;
	foreach (@$attributes) {
		if ( defined $q->param( $_->{'name'} ) && $q->param( $_->{'name'} ) ne '' ) {
			$newdata{ $_->{'name'} } = $q->param( $_->{'name'} );
		}
	}
	$newdata{'datestamp'}    = BIGSdb::Utils::get_datestamp();
	$newdata{'curator'}      = $self->get_curator_id();
	$newdata{'date_entered'} = $data->{'date_entered'};
	if ( $q->param('sent') ) {
		my $retval = $self->_upload( $table, \%newdata, $data, \@query_terms, \@query_values );
		say $buffer if $retval;
		return;
	}
	say $buffer;
	return;
}

sub _has_scheme_structure_changed {
	my ( $self, $data, $newdata, $attribute ) = @_;
	if ( any { $attribute->{'name'} eq $_ } qw(type primary_key) ) {
		if (
			   ( $newdata->{ $attribute->{'name'} } eq 'true' && !$data->{ $attribute->{'name'} } )
			|| ( $newdata->{ $attribute->{'name'} } eq 'false' && $data->{ $attribute->{'name'} } )
			|| (   $attribute->{'type'} ne 'bool'
				&& $newdata->{ $attribute->{'name'} } ne $data->{ $attribute->{'name'} } )
		  )
		{
			return 1;
		}
	}
	return;
}

sub _upload {
	my ( $self, $table, $newdata, $data, $query_terms, $query_values ) = @_;
	my $attributes    = $self->{'datastore'}->get_table_field_attributes($table);
	my $extra_inserts = [];
	$self->format_data( $table, $newdata );
	my @problems      = $self->check_record( $table, $newdata, 1, $data );
	my $status;
	if (@problems) {
		local $" = qq(<br />\n);
		say qq(<div class="box" id="statusbad"><p>@problems</p></div>);
	} else {
		my %methods = (
			users => sub {
				$status = $self->_check_users($newdata);
				$self->_prepare_extra_inserts_for_users( $newdata, $extra_inserts );
			},
			scheme_fields => sub {
				$status = $self->_check_scheme_fields($newdata);
			},
			sequences => sub {
				$status = $self->_check_allele_data( $newdata, $extra_inserts );
			},
			locus_descriptions => sub {
				$status = $self->_check_locus_descriptions( $newdata, $extra_inserts );
			},
			loci => sub {
				$status = $self->_check_loci($newdata);
				if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
					$newdata->{'locus'} = $newdata->{'id'};
					my $desc_status = $self->_prepare_extra_inserts_for_loci( $newdata, $extra_inserts );
					$status = $desc_status if !$status;
				}
				$self->_check_locus_aliases_when_updating_other_table( $newdata->{'id'}, $newdata, $extra_inserts );
			},
			allele_designations => sub {
				$status = $self->_check_allele_designations($newdata);
			},
			sequence_bin => sub {
				$status = $self->_prepare_extra_inserts_for_seqbin( $newdata, $extra_inserts );
			}
		);
		$methods{$table}->() if $methods{$table};
		if ( ( $status // 0 ) != FAILURE ) {
			my ( @table_fields, @placeholders, @values );
			my %new_value;
			my $scheme_structure_changed = 0;
			foreach my $att (@$attributes) {
				next if $att->{'user_update'} && $att->{'user_update'} eq 'no';
				push @table_fields, $att->{'name'};
				push @placeholders, '?';
				if ( $self->{'system'}->{'dbtype'} eq 'sequences' && $table eq 'scheme_fields' ) {
					$scheme_structure_changed = 1 if $self->_has_scheme_structure_changed( $data, $newdata, $att );
				}
				if ( $att->{'name'} =~ /sequence$/x && $newdata->{ $att->{'name'} } ) {
					$newdata->{ $att->{'name'} } = uc( $newdata->{ $att->{'name'} } );
					$newdata->{ $att->{'name'} } =~ s/\s//gx;
				}
				if ( ( $newdata->{ $att->{'name'} } // q() ) ne q() ) {
					push @values, $newdata->{ $att->{'name'} };
					$new_value{ $att->{'name'} } = $newdata->{ $att->{'name'} };
				} else {
					push @values, undef;
				}
			}
			local $" = q(,);
			my $qry = "UPDATE $table SET (@table_fields)=(@placeholders) WHERE ";
			local $" = ' AND ';
			$qry .= "@$query_terms";
			eval {
				$self->{'db'}->do( $qry, undef, @values, @$query_values );
				foreach (@$extra_inserts) {
					$self->{'db'}->do( $_->{'statement'}, undef, @{ $_->{'arguments'} } );
				}
				if ($scheme_structure_changed) {
					$self->remove_profile_data( $data->{'scheme_id'} );
					$self->drop_scheme_view( $data->{'scheme_id'} );
					$self->create_scheme_view( $data->{'scheme_id'} );
				}
			};
			if ($@) {
				say q(<div class="box" id="statusbad"><p>Update failed - transaction cancelled - )
				  . q(no records have been touched.</p>);
				if ( $@ =~ /duplicate/x && $@ =~ /unique/x ) {
					say q(<p>Data entry would have resulted in records with either duplicate ids or )
					  . q(another unique field with duplicate values.</p></div>);
				} else {
					say qq(<p>Error message: $@</p></div>);
				}
				$self->{'db'}->rollback;
			} else {
				my $record_name = $self->get_record_name($table);
				$self->{'db'}->commit && say qq(<div class="box" id="resultsheader"><p>$record_name updated!</p>);
				say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
				  . qq(page=tableQuery&amp;table=$table">Update another</a> | )
				  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a>)
				  . q(</p></div>);
				if ( $table eq 'allele_designations' ) {
					$self->update_history( $data->{'isolate_id'},
						"$data->{'locus'}: $data->{'allele_id'} -> $new_value{'allele_id'}" );
				}
			}
		}
	}
	return $status;
}

sub _check_users {
	my ( $self, $newdata ) = @_;
	if (   $self->is_admin
		&& $newdata->{'id'} == $self->get_curator_id
		&& $newdata->{'status'} ne 'admin' )
	{
		say q(<div class="box" id="statusbad"><p>It is not a good idea to remove admin status from )
		  . q(yourself as you will lock yourself out!  If you really wish to do this, you will need )
		  . q(to do it from another admin account.</p>)
		  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
		  . q(Back to main page</a></p></div>);
		return FAILURE;
	}
	return;
}

sub _check_scheme_fields {

	#Check that only one primary key field is set for a scheme field
	my ( $self, $newdata ) = @_;
	if ( $newdata->{'primary_key'} eq 'true' ) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $newdata->{'scheme_id'}, { get_pk => 1 } );
		my $primary_key = $scheme_info->{'primary_key'};
		if ( $primary_key && $primary_key ne $newdata->{'field'} ) {
			say q(<div class="box" id="statusbad"><p>This scheme already has a primary key field )
			  . qq(set ($primary_key).</p>)
			  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
			  . q(Back to main page</a></p></div>);
			return FAILURE;
		}
	}
}

sub _check_allele_designations {
	my ( $self, $newdata ) = @_;
	if ( !$self->is_allowed_to_view_isolate( $newdata->{'isolate_id'} ) ) {
		say q(<div class="box" id="statusbad"><p>Your user account is not allowed to update )
		  . qq(record_type for isolate $newdata->{'isolate_id'}.</p>)
		  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
		  . q(Back to main page</a></p></div>);
		return FAILURE;
	}
	return;
}

sub _check_loci {

	#Check that changing a locus allele_id_format to integer is allowed with currently existing data
	my ( $self, $newdata ) = @_;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $non_int;
		if ( $newdata->{'allele_id_format'} eq 'integer' ) {
			my $ids = $self->{'datastore'}->run_query( 'SELECT allele_id FROM sequences WHERE locus=?',
				$newdata->{'id'}, { fetch => 'col_arrayref' } );
			foreach (@$ids) {
				if ( !BIGSdb::Utils::is_int($_) && $_ ne 'N' ) {
					$non_int = 1;
					last;
				}
			}
		}
		if ($non_int) {
			say q(<div class="box" id="statusbad"><p>The sequence table already contains data with )
			  . q(non-integer allele ids. You will need to remove these before you can change the )
			  . q(allele_id_format to 'integer'.</p>)
			  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
			  . q(Back to main page</a></p></div>);
			return FAILURE;

			#special case to ensure that a locus length is set if it is not marked as variable length
		} elsif ( $newdata->{'length_varies'} ne 'true' && !$newdata->{'length'} ) {
			say q(<div class="box" id="statusbad"><p>Locus set as non variable length but no length is set.</p>)
			  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
			  . q(Back to main page</a></p></div>);
			return FAILURE;
		}
	}
}

sub _check_allele_data {

	#check extended attributes if they exist
	#Prepare extra inserts for PubMed/Genbank records and sequence flags.
	my ( $self, $newdata, $extra_inserts ) = @_;
	my $q = $self->{'cgi'};
	my $ext_dataset =
	  $self->{'datastore'}
	  ->run_query( 'SELECT field,required,value_format,value_regex FROM locus_extended_attributes WHERE locus=?',
		$newdata->{'locus'}, { fetch => 'all_arrayref' } );
	my @missing_field;
	foreach my $ext_data (@$ext_dataset) {
		my ( $field, $required, $format, $regex ) = @$ext_data;
		$newdata->{$field} = $q->param($field);
		if ( $required && $newdata->{$field} eq '' ) {
			push @missing_field, $field;
		} elsif ( $format eq 'integer' && $newdata->{$field} ne '' && !BIGSdb::Utils::is_int( $newdata->{$field} ) ) {
			say qq(<div class="box" id="statusbad"><p>$field must be an integer.</p>)
			  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
			  . q(Back to main page</a></p></div>);
			return FAILURE;
		} elsif ( $newdata->{$field} ne '' && $regex && $newdata->{$field} !~ /$regex/x ) {
			say qq(<div class="box" id="statusbad"><p>Field '$field' does not conform to specified format.</p>)
			  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
			  . q(Back to main page</a></p></div>);
			return FAILURE;
		} else {
			$self->_get_allele_extended_attribute_inserts( $newdata, $field, $extra_inserts );
		}
	}
	if (@missing_field) {
		local $" = ', ';
		say q(<div class="box" id="statusbad"><p>Please fill in all extended attribute fields. )
		  . qq( The following extended attribute fields are missing: @missing_field.</p>)
		  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>);
		return FAILURE;
	}
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		$self->_get_allele_flag_inserts( $newdata, $extra_inserts );
	}
	my $existing_pubmeds = $self->{'datastore'}->run_query(
		'SELECT pubmed_id FROM sequence_refs WHERE (locus,allele_id)=(?,?)',
		[ $newdata->{'locus'}, $newdata->{'allele_id'} ],
		{ fetch => 'col_arrayref' }
	);
	my @new_pubmeds = split /\r?\n/x, $q->param('pubmed');
	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !@$existing_pubmeds || none { $new eq $_ } @$existing_pubmeds ) {
			if ( !BIGSdb::Utils::is_int($new) ) {
				say q(<div class="box" id="statusbad"><p>PubMed ids must be integers.</p>)
				  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
				  . q(Back to main page</a></p></div>);
				return FAILURE;
			}
			push @$extra_inserts,
			  {
				statement => 'INSERT INTO sequence_refs (locus,allele_id,pubmed_id,curator,datestamp) '
				  . 'VALUES (?,?,?,?,?)',
				arguments => [ $newdata->{'locus'}, $newdata->{'allele_id'}, $new, $newdata->{'curator'}, 'now' ]
			  };
		}
	}
	foreach my $existing (@$existing_pubmeds) {
		if ( !@new_pubmeds || none { $existing eq $_ } @new_pubmeds ) {
			push @$extra_inserts,
			  {
				statement => 'DELETE FROM sequence_refs WHERE (locus,allele_id,pubmed_id) = (?,?,?)',
				arguments => [ $newdata->{'locus'}, $newdata->{'allele_id'}, $existing ]
			  };
		}
	}
	my @databanks = DATABANKS;
	foreach my $databank (@databanks) {
		my $existing_accessions = $self->{'datastore'}->run_query(
			'SELECT databank_id FROM accession WHERE (locus,allele_id,databank)=(?,?,?)',
			[ $newdata->{'locus'}, $newdata->{'allele_id'}, $databank ],
			{ fetch => 'col_arrayref' }
		);
		my @new_accessions = split /\r?\n/x, $q->param("databank_$databank");
		foreach my $new (@new_accessions) {
			chomp $new;
			next if $new eq '';
			if ( !@$existing_accessions || none { $new eq $_ } @$existing_accessions ) {
				push @$extra_inserts,
				  {
					statement => 'INSERT INTO accession (locus,allele_id,databank,databank_id,curator,datestamp) '
					  . 'VALUES (?,?,?,?,?,?)',
					arguments =>
					  [ $newdata->{'locus'}, $newdata->{'allele_id'}, $databank, $new, $newdata->{'curator'}, 'now' ]
				  };
			}
		}
		foreach my $existing (@$existing_accessions) {
			if ( !@new_accessions || none { $existing eq $_ } @new_accessions ) {
				push @$extra_inserts,
				  {
					statement => 'DELETE FROM accession WHERE (locus,allele_id,databank,databank_id) = (?,?,?,?)',
					arguments => [ $newdata->{'locus'}, $newdata->{'allele_id'}, $databank, $existing ]
				  };
			}
		}
	}
	return;
}

sub _get_allele_flag_inserts {
	my ( $self, $newdata, $extra_inserts ) = @_;
	my $q              = $self->{'cgi'};
	my $existing_flags = $self->{'datastore'}->run_query(
		'SELECT flag FROM allele_flags WHERE (locus,allele_id)=(?,?)',
		[ $newdata->{'locus'}, $newdata->{'allele_id'} ],
		{ fetch => 'col_arrayref' }
	);
	my @new_flags = $q->param('flags');
	foreach my $new (@new_flags) {
		next if none { $new eq $_ } ALLELE_FLAGS;
		if ( !@$existing_flags || none { $new eq $_ } @$existing_flags ) {
			push @$extra_inserts,
			  {
				statement => 'INSERT INTO allele_flags (locus,allele_id,flag,curator,datestamp) VALUES (?,?,?,?,?)',
				arguments => [ $newdata->{'locus'}, $newdata->{'allele_id'}, $new, $newdata->{'curator'}, 'today' ]
			  };
		}
	}
	foreach my $existing (@$existing_flags) {
		if ( !@new_flags || none { $existing eq $_ } @new_flags ) {
			push @$extra_inserts,
			  {
				statement => 'DELETE FROM allele_flags WHERE (locus,allele_id,flag) = (?,?,?)',
				arguments => [ $newdata->{'locus'}, $newdata->{'allele_id'}, $existing ]
			  };
		}
	}
	return;
}

sub _get_allele_extended_attribute_inserts {
	my ( $self, $newdata, $field, $extra_inserts ) = @_;
	if ( $newdata->{$field} ne '' ) {
		if (
			$self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM sequence_extended_attributes WHERE (locus,field,allele_id)=(?,?,?))',
				[ $newdata->{'locus'}, $field, $newdata->{'allele_id'} ],
				{ cache => 'CurateUpdatePage::check_allele_data' }
			)
		  )
		{
			push @$extra_inserts,
			  {
				statement => 'UPDATE sequence_extended_attributes SET (value,datestamp,curator) = (?,?,?) WHERE '
				  . '(locus,field,allele_id) = (?,?,?)',
				arguments => [
					$newdata->{$field},  'now',  $newdata->{'curator'},
					$newdata->{'locus'}, $field, $newdata->{'allele_id'}
				]
			  };
		} else {
			push @$extra_inserts,
			  {
				statement => 'INSERT INTO sequence_extended_attributes(locus,field,allele_id,value,'
				  . 'datestamp,curator) VALUES (?,?,?,?,?,?)',
				arguments => [
					$newdata->{'locus'}, $field, $newdata->{'allele_id'},
					$newdata->{$field},  'now',  $newdata->{'curator'}
				]
			  };
		}
	} else {
		push @$extra_inserts,
		  {
			statement => 'DELETE FROM sequence_extended_attributes WHERE (locus,field,allele_id) = (?,?,?)',
			arguments => [ $newdata->{'locus'}, $field, $newdata->{'allele_id'} ]
		  };
	}
	return;
}

sub _prepare_extra_inserts_for_loci {
	my ( $self, $newdata, $extra_inserts ) = @_;
	my $q = $self->{'cgi'};
	my $existing_desc =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM locus_descriptions WHERE locus=?', $newdata->{'locus'}, { fetch => 'row_hashref' } );
	my ( $full_name, $product, $description ) =
	  ( $q->param('full_name'), $q->param('product'), $q->param('description') );
	if ($existing_desc) {
		if (   $full_name ne ( $existing_desc->{'full_name'} // '' )
			|| $product ne ( $existing_desc->{'product'} // '' )
			|| $description ne ( $existing_desc->{'description'} // '' ) )
		{
			push @$extra_inserts,
			  {
				statement => 'UPDATE locus_descriptions SET (full_name,product,description,curator,datestamp)='
				  . '(?,?,?,?,?) WHERE locus=?',
				arguments => [ $full_name, $product, $description, $newdata->{'curator'}, 'now', $newdata->{'locus'} ]
			  };
		}
	} else {
		push @$extra_inserts,
		  {
			statement => 'INSERT INTO locus_descriptions (locus,full_name,product,description,curator,datestamp) '
			  . 'VALUES (?,?,?,?,?,?)',
			arguments => [ $newdata->{'locus'}, $full_name, $product, $description, $newdata->{'curator'}, 'now' ]
		  };
	}
	return $self->_check_locus_descriptions( $newdata, $extra_inserts );
}

sub _check_locus_aliases_when_updating_other_table {
	my ( $self, $locus, $newdata, $extra_inserts ) = @_;
	my $q = $self->{'cgi'};
	my $existing_aliases =
	  $self->{'datastore'}
	  ->run_query( 'SELECT alias FROM locus_aliases WHERE locus=?', $locus, { fetch => 'col_arrayref' } );
	my @new_aliases = split /\r?\n/x, $q->param('aliases');
	foreach my $new (@new_aliases) {
		chomp $new;
		next if $new eq '';
		next if $new eq $locus;
		if ( !@$existing_aliases || none { $new eq $_ } @$existing_aliases ) {
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
				push @$extra_inserts,
				  {
					statement => 'INSERT INTO locus_aliases (locus,alias,use_alias,curator,datestamp) '
					  . 'VALUES (?,?,?,?,?)',
					arguments => [ $locus, $new, 'true', $newdata->{'curator'}, 'now' ]
				  };
			} else {
				push @$extra_inserts,
				  {
					statement => 'INSERT INTO locus_aliases (locus,alias,curator,datestamp) VALUES (?,?,?,?)',
					arguments => [ $locus, $new, $newdata->{'curator'}, 'now' ]
				  };
			}
		}
	}
	foreach my $existing (@$existing_aliases) {
		if ( !@new_aliases || none { $existing eq $_ } @new_aliases ) {
			push @$extra_inserts,
			  {
				statement => 'DELETE FROM locus_aliases WHERE (locus,alias) = (?,?)',
				arguments => [ $locus, $existing ]
			  };
		}
	}
	return;
}

sub _check_locus_descriptions {
	my ( $self, $newdata, $extra_inserts ) = @_;
	my $q = $self->{'cgi'};
	$self->_check_locus_aliases_when_updating_other_table( $newdata->{'locus'}, $newdata, $extra_inserts )
	  if $q->param('table') eq 'locus_descriptions';
	my $existing_pubmeds =
	  $self->{'datastore'}
	  ->run_query( 'SELECT pubmed_id FROM locus_refs WHERE locus=?', $newdata->{'locus'}, { fetch => 'col_arrayref' } );
	my @new_pubmeds = split /\r?\n/x, $q->param('pubmed');
	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !@$existing_pubmeds || none { $new eq $_ } @$existing_pubmeds ) {
			if ( !BIGSdb::Utils::is_int($new) ) {
				say q(<div class="box" id="statusbad"><p>PubMed ids must be integers.</p>)
				  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
				  . q(Back to main page</a></p></div>);
				return FAILURE;
			}
			push @$extra_inserts,
			  {
				statement => 'INSERT INTO locus_refs (locus,pubmed_id,curator,datestamp) VALUES (?,?,?,?)',
				arguments => [ $newdata->{'locus'}, $new, $newdata->{'curator'}, 'now' ]
			  };
		}
	}
	foreach my $existing (@$existing_pubmeds) {
		if ( !@new_pubmeds || none { $existing eq $_ } @new_pubmeds ) {
			push @$extra_inserts,
			  {
				statement => 'DELETE FROM locus_refs WHERE (locus,pubmed_id) = (?,?)',
				arguments => [ $newdata->{'locus'}, $existing ]
			  };
		}
	}
	my @new_links;
	my $i = 1;
	foreach ( split /\r?\n/x, $q->param('links') ) {
		next if $_ eq '';
		push @new_links, "$i|$_";
		$i++;
	}
	my @existing_links;
	my $link_dataset =
	  $self->{'datastore'}
	  ->run_query( 'SELECT link_order,url,description FROM locus_links WHERE locus=? ORDER BY link_order',
		$newdata->{'locus'}, { fetch => 'all_arrayref', slice => {} } );
	foreach my $link_data (@$link_dataset) {
		push @existing_links, "$link_data->{'link_order'}|$link_data->{'url'}|$link_data->{'description'}";
	}
	foreach my $existing (@existing_links) {
		if ( !@new_links || none { $existing eq $_ } @new_links ) {
			if ( $existing =~ /^\d+\|(.+?)\|.+$/x ) {
				my $url = $1;
				push @$extra_inserts,
				  {
					statement => 'DELETE FROM locus_links WHERE (locus,url) = (?,?)',
					arguments => [ $newdata->{'locus'}, $url ]
				  };
			}
		}
	}
	foreach my $new (@new_links) {
		chomp $new;
		next if $new eq '';
		if ( !@existing_links || none { $new eq $_ } @existing_links ) {
			if ( $new !~ /^(.+?)\|(.+)\|(.+)$/x ) {
				say q(<div class="box" id="statusbad"><p>Links must have an associated description separated )
				  . q(from the URL by a '|'.</p>)
				  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
				  . q(Back to main page</a></p></div>);
				return FAILURE;
			} else {
				my ( $field_order, $url, $desc ) = ( $1, $2, $3 );
				push @$extra_inserts,
				  {
					statement => 'INSERT INTO locus_links (locus,url,description,link_order,'
					  . 'curator,datestamp) VALUES (?,?,?,?,?,?)',
					arguments => [ $newdata->{'locus'}, $url, $desc, $field_order, $newdata->{'curator'}, 'now' ]
				  };
			}
		}
	}
	return;
}

#Remove additional permissions for submitter if downgraded from curator.
sub _prepare_extra_inserts_for_users {
	my ( $self, $newdata, $extra_inserts ) = @_;
	if ( $newdata->{'status'} eq 'submitter' ) {
		local $" = q(',');
		my @permissions = SUBMITTER_ALLOWED_PERMISSIONS;
		push @$extra_inserts,
		  {
			statement => "DELETE FROM curator_permissions WHERE user_id=? AND permission NOT IN ('@permissions')",
			arguments => [ $newdata->{'id'} ]
		  };
	}
	return;
}

sub _prepare_extra_inserts_for_seqbin {
	my ( $self, $newdata, $extra_inserts ) = @_;
	if ( !$self->is_allowed_to_view_isolate( $newdata->{'isolate_id'} ) ) {
		say q(<div class="box" id="statusbad"><p>Your user account is not allowed to update )
		  . qq(record_type for isolate $newdata->{'isolate_id'}.</p>)
		  . qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">)
		  . q(Back to main page</a></p></div>);
		return FAILURE;
	}
	my $q              = $self->{'cgi'};
	my $seq_attributes = $self->{'datastore'}->run_query( 'SELECT key,type FROM sequence_attributes ORDER BY key',
		undef, { fetch => 'all_arrayref', slice => {} } );
	my $existing_values =
	  $self->{'datastore'}->run_query( 'SELECT key,value FROM sequence_attribute_values WHERE seqbin_id=?',
		$newdata->{'id'}, { fetch => 'all_arrayref', slice => {} } );
	my %existing_value = map { $_->{'key'} => $_->{'value'} } @$existing_values;
	my @type_errors;
	foreach my $attribute (@$seq_attributes) {
		next if !defined $q->param( $attribute->{'key'} );
		my $value = $q->param( $attribute->{'key'} );
		if ( $value ne '' ) {
			if ( $attribute->{'type'} eq 'integer' && !BIGSdb::Utils::is_int($value) ) {
				push @type_errors, "$attribute->{'key'} must be an integer.";
			} elsif ( $attribute->{'type'} eq 'float' && !BIGSdb::Utils::is_float($value) ) {
				push @type_errors, "$attribute->{'key'} must be a floating point value.";
			} elsif ( $attribute->{'type'} eq 'date' && !BIGSdb::Utils::is_date($value) ) {
				push @type_errors, "$attribute->{'key'} must be a valid date in yyyy-mm-dd format.";
			}
		}
		if ( defined $existing_value{ $attribute->{'key'} } ) {
			if ( $value eq '' ) {
				push @$extra_inserts,
				  {
					statement => 'DELETE FROM sequence_attribute_values WHERE (seqbin_id,key) = (?,?)',
					arguments => [ $newdata->{'id'}, $attribute->{'key'} ]
				  };
			} else {
				if ( $value ne $existing_value{ $attribute->{'key'} } ) {
					push @$extra_inserts,
					  {
						statement => 'UPDATE sequence_attribute_values SET (value,curator,datestamp) = (?,?,?) '
						  . 'WHERE (seqbin_id,key) = (?,?)',
						arguments => [ $value, $newdata->{'curator'}, 'now', $newdata->{'id'}, $attribute->{'key'} ]
					  };
				}
			}
		} else {
			if ( $value ne '' ) {
				push @$extra_inserts, {
					statement =>
					  'INSERT INTO sequence_attribute_values (seqbin_id,key,value,curator,datestamp) '
					  . 'VALUES (?,?,?,?,?)',
					arguments => [ $newdata->{'id'}, $attribute->{'key'}, $value, $newdata->{'curator'}, 'now' ]
				};
			}
		}
	}
	if (@type_errors) {
		local $" = q(<br />);
		say qq(<div class="box" id="statusbad"><p>@type_errors</p></div>);
		return FAILURE;
	}
	return;
}

sub get_javascript {
	my $buffer = << "END";
\$(function () {
  	if (Modernizr.touch){
  	 	\$(".no_touch").css("display","none");
  	}
});
END
	return $buffer;
}

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	my $type  = $self->get_record_name($table) // 'record';
	return qq(Update $type - $desc);
}
1;
