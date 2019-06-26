#Written by Keith Jolley
#Copyright (c) 2010-2019, University of Oxford
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
use BIGSdb::Constants qw(:interface ALLELE_FLAGS SUBMITTER_ALLOWED_PERMISSIONS DATABANKS SCHEME_FLAGS);
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
	if ( !$self->{'datastore'}->is_table($table) ) {
		$self->print_bad_status( { message => qq(Table $table does not exist!), navbar => 1 } );
		return 1;
	}
	if ( !$self->can_modify_table($table) ) {
		$self->print_bad_status(
			{ message => q(Your user account is not allowed to update this record.), navbar => 1 } );
		return 1;
	}
	if ( $table eq 'allele_sequences' ) {
		$self->print_bad_status( { message => q(Sequence tags cannot be updated using this function.), navbar => 1 } );
		return 1;
	}
	if ( $table eq 'scheme_fields' && $self->{'system'}->{'dbtype'} eq 'sequences' && !$q->param('sent') ) {
		say q(<div class="box" id="warning"><p>Please be aware that any changes to the )
		  . q(structure of a scheme will result in all data being removed from it. This )
		  . q(will happen if you modify the type or change whether the field is a primary key. )
		  . q(All other changes are ok.</p>)
		  . q(<p>If you change the index status of a field you will also need to rebuild the )
		  . q(scheme table to reflect this change. This can be done by selecting 'Configuration )
		  . q(repair' on the main curation page.</p>);
		say q(</div>);
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $vars   = $q->Vars;
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
		$self->print_bad_status( { message => q(No identifying attributes sent.), navbar => 1 } );
		return;
	}
	local $" = q( AND );
	my $record_count =
	  $self->{'datastore'}->run_query( "SELECT COUNT(*) FROM $table WHERE @query_terms", \@query_values );
	if ( $record_count != 1 ) {
		$self->print_bad_status(
			{ message => q(The search terms did not uniquely identify a single record.), navbar => 1 } );
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
	my $buffer = $self->_get_message( $table, $data, { update => 1 } );
	$self->modify_dataset_if_needed( $table, [$data] );
	local $" = q( );
	my $disabled_fields = $self->_get_disabled_fields( $table, $data );
	my $icon = $self->get_form_icon( $table, 'edit' );
	$buffer .= $icon;
	$buffer .= $self->create_record_table( $table, $data, { update => 1, disabled => $disabled_fields } );
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
sub _get_disabled_fields {
	my ( $self, $table, $data ) = @_;
	my $fields = ['user_db'];
	if ( $table eq 'users' && $data->{'user_db'} ) {
		return $fields if $self->{'permissions'}->{'modify_site_users'};
		push @$fields, qw(user_name surname first_name email affiliation);
	}
	return $fields;
}

sub _get_message {
	my ( $self, $table, $data, $options ) = @_;
	if ( $table eq 'users' && $options->{'update'} ) {
		if ( $data->{'user_db'} ) {
			my $msg =
			    q(<div class="box" id="message"><p>The name, E-mail and affiliation of this user are )
			  . q(imported from the site user database. Modifying these here will change them for all )
			  . q(databases on the system that this account uses. Changes to status affect only this )
			  . q(database.</p>);
			if ( !$self->{'permissions'}->{'modify_site_users'} ) {
				$msg .= q(<p>Your account does not have permission to modify external user data.</p>);
			}
			$msg .= q(</div>);
			return $msg;
		}
	}
	return q();
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
	my $attributes         = $self->{'datastore'}->get_table_field_attributes($table);
	my $extra_inserts      = [];
	my $extra_transactions = [];
	$self->format_data( $table, $newdata );
	$self->_populate_disabled_fields( $table, $newdata );
	my @problems = $self->check_record( $table, $newdata, 1, $data );
	my $status;

	if (@problems) {
		local $" = qq(<br />\n);
		$self->print_bad_status( { message => qq(@problems), navbar => 1 } );
	} else {
		my %methods = (
			users => sub {
				$status = $self->_check_users($newdata);
				$self->_prepare_extra_inserts_for_users( $newdata, $extra_inserts, $extra_transactions );
			},
			schemes => sub {
				$status = $self->_prepare_extra_inserts_for_schemes( $newdata, $extra_inserts );
			},
			scheme_fields => sub {
				$status = $self->_check_scheme_fields($newdata);
			},
			eav_fields => sub {
				$status = $self->_check_eav_fields($newdata);
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
				next if $att->{'no_user_update'};
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
				foreach my $transaction (@$extra_transactions) {
					$transaction->{'db'}->do( $transaction->{'statement'}, undef, @{ $transaction->{'arguments'} } );
				}
				if ($scheme_structure_changed) {
					$self->remove_profile_data( $data->{'scheme_id'} );
				}
			};
			if ($@) {
				$logger->error($@);
				my $detail;
				if ( $@ =~ /duplicate/x && $@ =~ /unique/x ) {
					$detail = q(Data entry would have resulted in records with either duplicate ids or )
					  . q(another unique field with duplicate values.);
				}
				$self->print_bad_status(
					{
						message => q(Update failed - transaction cancelled - no records have been touched.),
						detail  => $detail,
						navbar  => 1
					}
				);
				$self->{'db'}->rollback;
				foreach my $transaction (@$extra_transactions) {
					$transaction->{'db'}->rollback;
				}
			} else {
				my $record_name = $self->get_record_name($table);
				$self->{'db'}->commit;
				foreach my $transaction (@$extra_transactions) {
					$transaction->{'db'}->commit;
				}
				$self->print_good_status(
					{
						message        => qq($record_name updated.),
						navbar         => 1,
						query_more_url => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
						  . qq(page=tableQuery&amp;table=$table)
					}
				);
				if ( $table eq 'allele_designations' ) {
					$self->update_history( $data->{'isolate_id'},
						"$data->{'locus'}: $data->{'allele_id'} -> $new_value{'allele_id'}" );
				}
			}
		}
	}
	return $status;
}

#If user data is stored in separate user database we need to import these values.
sub _populate_disabled_fields {
	my ( $self, $table, $newdata ) = @_;
	return if $table ne 'users';
	my $user_data = $self->{'datastore'}->get_user_info( $newdata->{'id'} );
	if ( $user_data->{'user_db'} ) {
		foreach my $field (qw(user_name surname first_name affiliation email user_db)) {
			$newdata->{$field} //= $user_data->{$field};
		}
	}
	return;
}

sub _check_users {
	my ( $self, $newdata ) = @_;
	if (   $self->is_admin
		&& $newdata->{'id'} == $self->get_curator_id
		&& $newdata->{'status'} ne 'admin' )
	{
		$self->print_bad_status(
			{
				message => q(It is not a good idea to remove admin status from )
				  . q(yourself as you will lock yourself out!  If you really wish to do this, you will need )
				  . q(to do it from another admin account.),
				navbar => 1
			}
		);
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
			$self->print_bad_status(
				{ message => qq(This scheme already has a primary key field set ($primary_key).), navbar => 1 } );
			return FAILURE;
		}
	}
}

sub _check_eav_fields {
	my ( $self, $newdata ) = @_;
	my $existing = $self->{'datastore'}
	  ->run_query( 'SELECT * FROM eav_fields WHERE field=?', $newdata->{'field'}, { fetch => 'row_hashref' } );
	if ( $newdata->{'value_format'} ne $existing->{'value_format'} ) {
		$self->print_bad_status( { message => q(You cannot change the data type of a field.), navbar => 1 } );
		return FAILURE;
	}
	my $eav_table = {
		integer => 'eav_int',
		float   => 'eav_float',
		text    => 'eav_text',
		date    => 'eav_date'
	};
	if ( defined $newdata->{'length'} && $newdata->{'value_format'} eq 'text' ) {
		my $bad_length =
		  $self->{'datastore'}->run_query(
			"SELECT EXISTS(SELECT * FROM $eav_table->{$newdata->{'value_format'}} WHERE field=? AND length(value)>?)",
			[ $newdata->{'field'}, $newdata->{'length'} ] );
		if ($bad_length) {
			$self->print_bad_status(
				{
					message => q(There is already data defined with a length longer than you have selected.),
					navbar  => 1
				}
			);
			return FAILURE;
		}
	}
	return if $newdata->{'value_format'} ne 'integer' && $newdata->{'value_format'} ne 'float';
	if ( defined $newdata->{'min_value'} ) {
		my $bad_length =
		  $self->{'datastore'}->run_query(
			"SELECT EXISTS(SELECT * FROM $eav_table->{$newdata->{'value_format'}} WHERE field=? AND value<?)",
			[ $newdata->{'field'}, $newdata->{'min_value'} ] );
		if ($bad_length) {
			$self->print_bad_status(
				{
					message =>
					  q(There is already data defined with a value smaller than the minimum you have selected.),
					navbar => 1
				}
			);
			return FAILURE;
		}
	}
	if ( defined $newdata->{'max_value'} ) {
		my $bad_length =
		  $self->{'datastore'}->run_query(
			"SELECT EXISTS(SELECT * FROM $eav_table->{$newdata->{'value_format'}} WHERE field=? AND value>?)",
			[ $newdata->{'field'}, $newdata->{'max_value'} ] );
		if ($bad_length) {
			$self->print_bad_status(
				{
					message =>
					  q(There is already data defined with a value greater than the maximum you have selected.),
					navbar => 1
				}
			);
			return FAILURE;
		}
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
			$self->print_bad_status(
				{
					message => q(The sequence table already contains data with )
					  . q(non-integer allele ids. You will need to remove these before you can change the )
					  . q(allele_id_format to 'integer'.),
					navbar => 1
				}
			);
			return FAILURE;

			#special case to ensure that a locus length is set if it is not marked as variable length
		} elsif ( $newdata->{'length_varies'} ne 'true' && !$newdata->{'length'} ) {
			$self->print_bad_status(
				{ message => q(Locus set as non variable length but no length is set.), navbar => 1 } );
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
			$self->print_bad_status( { message => qq($field must be an integer.), navbar => 1 } );
			return FAILURE;
		} elsif ( $newdata->{$field} ne '' && $regex && $newdata->{$field} !~ /$regex/x ) {
			$self->print_bad_status(
				{ message => qq(Field '$field' does not conform to specified format.), navbar => 1 } );
			return FAILURE;
		} else {
			$self->_get_allele_extended_attribute_inserts( $newdata, $field, $extra_inserts );
		}
	}
	if (@missing_field) {
		local $" = ', ';
		$self->print_bad_status(
			{
				message => q(Please fill in all extended attribute fields. )
				  . qq( The following extended attribute fields are missing: @missing_field.),
				navbar => 1
			}
		);
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
				$self->print_bad_status( { message => q(PubMed ids must be integers.), navbar => 1 } );
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
				$self->print_bad_status( { message => q(PubMed ids must be integers.), navbar => 1 } );
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
		$new =~ s/^\s+|\s+$//xg;
		next if $new eq '';
		if ( !@existing_links || none { $new eq $_ } @existing_links ) {
			if ( $new !~ /^(.+?)\|(.+)\|(.+)$/x ) {
				$self->print_bad_status(
					{
						message => q(Links must have an associated description separated from the URL by a '|'.),
						navbar  => 1
					}
				);
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

sub _prepare_extra_inserts_for_users {
	my ( $self, $newdata, $extra_inserts, $extra_transactions ) = @_;

	#Remove additional permissions for submitter if downgraded from curator.
	if ( $newdata->{'status'} eq 'submitter' ) {
		local $" = q(',');
		my @permissions = SUBMITTER_ALLOWED_PERMISSIONS;
		push @$extra_inserts,
		  {
			statement => "DELETE FROM permissions WHERE user_id=? AND permission NOT IN ('@permissions')",
			arguments => [ $newdata->{'id'} ]
		  };
	}
	if ( $newdata->{'user_db'} ) {
		if ( $self->{'permissions'}->{'modify_site_users'} ) {
			my $user_db = $self->{'datastore'}->get_user_db( $newdata->{'user_db'} );
			push @$extra_transactions,
			  {
				statement =>
				  'UPDATE users SET (surname,first_name,email,affiliation,datestamp)=(?,?,?,?,?) WHERE user_name=?',
				arguments => [
					$newdata->{'surname'},     $newdata->{'first_name'}, $newdata->{'email'},
					$newdata->{'affiliation'}, 'now',                    $newdata->{'user_name'}
				],
				db => $user_db
			  };
		}
		$newdata->{$_} = undef foreach qw(surname first_name email affiliation);
	}

	#Set private data quota
	if ( $newdata->{'status'} ne 'user' && $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $existing_quota =
		  $self->{'datastore'}->run_query( 'SELECT value FROM user_limits WHERE (user_id,attribute)=(?,?)',
			[ $newdata->{'id'}, 'private_isolates' ] );
		my $q = $self->{'cgi'};
		$newdata->{'quota'} = $q->param('quota');
		if ( defined $existing_quota ) {
			if ( BIGSdb::Utils::is_int( $newdata->{'quota'} ) ) {
				push @$extra_inserts,
				  {
					statement =>
					  'UPDATE user_limits SET (value,curator,datestamp)=(?,?,?) WHERE (user_id,attribute)=(?,?)',
					arguments =>
					  [ $newdata->{'quota'}, $newdata->{'curator'}, 'now', $newdata->{'id'}, 'private_isolates' ]
				  };
			} else {
				push @$extra_inserts,
				  {
					statement => 'DELETE FROM user_limits WHERE (user_id,attribute)=(?,?)',
					arguments => [ $newdata->{'id'}, 'private_isolates' ]
				  };
			}
		} else {
			if ( BIGSdb::Utils::is_int( $newdata->{'quota'} ) ) {
				push @$extra_inserts,
				  {
					statement =>
					  'INSERT INTO user_limits (user_id,attribute,value,curator,datestamp) VALUES (?,?,?,?,?)',
					arguments =>
					  [ $newdata->{'id'}, 'private_isolates', $newdata->{'quota'}, $newdata->{'curator'}, 'now' ]
				  };
			}
		}
	}
	return;
}

sub _prepare_extra_inserts_for_schemes {
	my ( $self, $newdata, $extra_inserts ) = @_;
	my %allowed = map { $_ => 1 } SCHEME_FLAGS;
	my $q       = $self->{'cgi'};
	my @flags   = $q->param('flags');
	push @$extra_inserts,
	  { statement => 'DELETE FROM scheme_flags WHERE scheme_id=?', arguments => [ $newdata->{'id'} ] };
	foreach my $flag (@flags) {
		if ( $allowed{$flag} ) {
			push @$extra_inserts,
			  {
				statement => 'INSERT INTO scheme_flags (scheme_id,flag,curator,datestamp) VALUES (?,?,?,?)',
				arguments => [ $newdata->{'id'}, $flag, $newdata->{'curator'}, 'now' ]
			  };
		}
	}
	my $existing_pubmeds = $self->{'datastore'}->run_query( 'SELECT pubmed_id FROM scheme_refs WHERE scheme_id=?',
		$newdata->{'id'}, { fetch => 'col_arrayref' } );
	my @new_pubmeds = split /\r?\n/x, $q->param('pubmed');
	foreach my $new (@new_pubmeds) {
		$new =~ s/\s//gx;
		next if $new eq '';
		if ( !@$existing_pubmeds || none { $new eq $_ } @$existing_pubmeds ) {
			if ( !BIGSdb::Utils::is_int($new) ) {
				$self->print_bad_status(
					{
						message => q(PubMed ids must be integers.),
						navbar  => 1
					}
				);
				return FAILURE;
			}
			push @$extra_inserts,
			  {
				statement => 'INSERT INTO scheme_refs (scheme_id,pubmed_id,curator,datestamp) VALUES (?,?,?,?)',
				arguments => [ $newdata->{'id'}, $new, $newdata->{'curator'}, 'now' ]
			  };
		}
	}
	foreach my $existing (@$existing_pubmeds) {
		if ( !@new_pubmeds || none { $existing eq $_ } @new_pubmeds ) {
			push @$extra_inserts,
			  {
				statement => 'DELETE FROM scheme_refs WHERE (scheme_id,pubmed_id) = (?,?)',
				arguments => [ $newdata->{'id'}, $existing ]
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
	  ->run_query( 'SELECT link_order,url,description FROM scheme_links WHERE scheme_id=? ORDER BY link_order',
		$newdata->{'id'}, { fetch => 'all_arrayref', slice => {} } );
	foreach my $link_data (@$link_dataset) {
		push @existing_links, "$link_data->{'link_order'}|$link_data->{'url'}|$link_data->{'description'}";
	}
	foreach my $existing (@existing_links) {
		if ( !@new_links || none { $existing eq $_ } @new_links ) {
			if ( $existing =~ /^\d+\|(.+?)\|.+$/x ) {
				my $url = $1;
				push @$extra_inserts,
				  {
					statement => 'DELETE FROM scheme_links WHERE (scheme_id,url) = (?,?)',
					arguments => [ $newdata->{'id'}, $url ]
				  };
			}
		}
	}
	foreach my $new (@new_links) {
		chomp $new;
		next if $new eq '';
		if ( !@existing_links || none { $new eq $_ } @existing_links ) {
			if ( $new !~ /^(.+?)\|(.+)\|(.+)$/x ) {
				$self->print_bad_status(
					{
						message => q(Links must have an associated description separated from the URL by a '|'.),
						navbar  => 1
					}
				);
				return FAILURE;
			} else {
				my ( $field_order, $url, $desc ) = ( $1, $2, $3 );
				push @$extra_inserts,
				  {
					statement => 'INSERT INTO scheme_links (scheme_id,url,description,link_order,'
					  . 'curator,datestamp) VALUES (?,?,?,?,?,?)',
					arguments => [ $newdata->{'id'}, $url, $desc, $field_order, $newdata->{'curator'}, 'now' ]
				  };
			}
		}
	}
	return;
}

sub _prepare_extra_inserts_for_seqbin {
	my ( $self, $newdata, $extra_inserts ) = @_;
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
				push @$extra_inserts,
				  {
					statement => 'INSERT INTO sequence_attribute_values (seqbin_id,key,value,curator,datestamp) '
					  . 'VALUES (?,?,?,?,?)',
					arguments => [ $newdata->{'id'}, $attribute->{'key'}, $value, $newdata->{'curator'}, 'now' ]
				  };
			}
		}
	}
	if (@type_errors) {
		local $" = q(<br />);
		$self->print_bad_status( { message => qq(@type_errors) } );
		return FAILURE;
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	my $type  = $self->get_record_name($table) // 'record';
	return qq(Update $type - $desc);
}
1;
