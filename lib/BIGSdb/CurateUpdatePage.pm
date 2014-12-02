#Written by Keith Jolley
#Copyright (c) 2010-2014, University of Oxford
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
use List::MoreUtils qw(any none);
use BIGSdb::Page qw(DATABANKS ALLELE_FLAGS);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant FAILURE => 2;

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery noCache);
	return;
}

sub print_content {
	my ($self)      = @_;
	my $q           = $self->{'cgi'};
	my $table       = $q->param('table');
	my $record_name = $self->get_record_name($table);
	if ( !$self->{'datastore'}->is_table($table) && !( $table eq 'samples' && @{ $self->{'xmlHandler'}->get_sample_field_list } ) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Table $table does not exist!</p></div>";
		return;
	}
	print "<h1>Update $record_name</h1>\n";
	if ( !$self->can_modify_table($table) ) {
		if ( $table eq 'sequences' && $q->param('locus') ) {
			my $locus = $q->param('locus');
			say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update $locus sequences in "
			  . "the database.</p></div>";
		} else {
			say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update this record.</p></div>";
		}
		return;
	}
	if ( $table eq 'allele_sequences' ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Sequence tags cannot be updated using this function.</p></div>";
		return;
	}
	if ( $table eq 'scheme_fields' && $self->{'system'}->{'dbtype'} eq 'sequences' && !$q->param('sent') ) {
		say "<div class=\"box\" id=\"warning\"><p>Please be aware that any changes to the structure of a scheme will "
		  . " result in all data being removed from it.  This will happen if you modify the type or change whether "
		  . " the field is a primary key.  All other changes are ok.</p>";
		if ( ( $self->{'system'}->{'materialized_views'} // '' ) eq 'yes' ) {
			say "<p>If you change the index status of a field you will also need to rebuild the scheme table to reflect this change. "
			  . "This can be done by selecting 'Configuration repair' on the main curation page.</p>";
		}
		say "</div>";
	}
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my @query_values;
	foreach (@$attributes) {
		my $value = $q->param( $_->{'name'} );
		next if !defined $value;
		$value =~ s/'/\\'/g;
		if ( $_->{'primary_key'} ) {
			push @query_values, "$_->{name} = E'$value'";
		}
	}
	if ( !@query_values ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No identifying attributes sent.</p>";
		return;
	}
	local $" = ' AND ';
	my $sql = $self->{'db'}->prepare("SELECT * FROM $table WHERE @query_values");
	eval { $sql->execute };
	if ($@) {
		$logger->error($@);
		say "<div class=\"box\" id=\"statusbad\"><p>No identifying attributes sent.</p>";
		return;
	}
	my $data = $sql->fetchrow_hashref;
	if ( $table eq 'sequences' ) {
		$sql = $self->{'db'}->prepare("SELECT field,value FROM sequence_extended_attributes WHERE locus=? AND allele_id=?");
		eval { $sql->execute( $data->{'locus'}, $data->{'allele_id'} ) };
		$logger->error($@) if $@;
		while ( my ( $field, $value ) = $sql->fetchrow_array ) {
			$data->{$field} = $value;
		}
	}
	my $buffer = $self->create_record_table( $table, $data, { update => 1 } );
	my %newdata;
	foreach (@$attributes) {
		if ( defined $q->param( $_->{'name'} ) && $q->param( $_->{'name'} ) ne '' ) {
			$newdata{ $_->{'name'} } = $q->param( $_->{'name'} );
		}
	}
	$newdata{'datestamp'}    = $self->get_datestamp;
	$newdata{'curator'}      = $self->get_curator_id();
	$newdata{'date_entered'} = $data->{'date_entered'};
	my @problems;
	my $extra_inserts = [];
	if ( $q->param('sent') ) {
		@problems = $self->check_record( $table, \%newdata, 1, $data );
		if (@problems) {
			local $" = "<br />\n";
			say "<div class=\"box\" id=\"statusbad\"><p>@problems</p></div>";
		} else {
			my $status;
			if ( $table eq 'users' ) {
				$status = $self->_check_users( \%newdata );
			} elsif ( $table eq 'scheme_fields' ) {
				$status = $self->_check_scheme_fields( \%newdata );
			} elsif ( $table eq 'sequences' ) {
				$status = $self->_check_allele_data( \%newdata, $extra_inserts );
			} elsif ( $table eq 'locus_descriptions' ) {
				$status = $self->_check_locus_descriptions( \%newdata, $extra_inserts );
			} elsif ( $table eq 'loci' ) {
				$status = $self->_check_loci( \%newdata );
				if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
					$newdata{'locus'} = $newdata{'id'};
					my $desc_status = $self->_prepare_extra_inserts_for_loci( \%newdata, $extra_inserts );
					$status = $desc_status if !$status;
				}
				$self->_check_locus_aliases_when_updating_other_table( $newdata{'id'}, \%newdata, $extra_inserts );
			} elsif ( $table eq 'sequence_bin' ) {
				$status = $self->_prepare_extra_inserts_for_seqbin( \%newdata, $extra_inserts );
			} elsif ( ( $table eq 'allele_designations' || $table eq 'sequence_bin' )
				&& !$self->is_allowed_to_view_isolate( $newdata{'isolate_id'} ) )
			{
				my $record_type = $self->get_record_name($table);
				print <<"HTML";
<div class="box" id="statusbad"><p>Your user account is not allowed to update $record_type for isolate $newdata{'isolate_id'}.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>
HTML
				$status = FAILURE;
			}
			if ( ( $status // 0 ) != FAILURE ) {
				my ( @table_fields, @placeholders, @values );
				my %new_value;
				my $scheme_structure_changed = 0;
				foreach my $att (@$attributes) {
					next if $att->{'user_update'} && $att->{'user_update'} eq 'no';
					push @table_fields, $att->{'name'};
					push @placeholders, '?';
					if ( $self->{'system'}->{'dbtype'} eq 'sequences' && $table eq 'scheme_fields' && any { $att->{'name'} eq $_ }
						qw(type primary_key) )
					{
						if (   ( $newdata{ $att->{'name'} } eq 'true' && !$data->{ $att->{'name'} } )
							|| ( $newdata{ $att->{'name'} } eq 'false' && $data->{ $att->{'name'} } )
							|| ( $att->{'type'} ne 'bool' && $newdata{ $att->{'name'} } ne $data->{ $att->{'name'} } ) )
						{
							$scheme_structure_changed = 1;
						}
					}
					if ( $att->{'name'} =~ /sequence$/ && $newdata{ $att->{'name'} } ) {
						$newdata{ $att->{'name'} } = uc( $newdata{ $att->{'name'} } );
						$newdata{ $att->{'name'} } =~ s/\s//g;
					}
					if ( ( $newdata{ $att->{'name'} } // '' ) ne '' ) {
						push @values, $newdata{ $att->{'name'} };
						$new_value{ $att->{'name'} } = $newdata{ $att->{'name'} };
					} else {
						push @values, undef;
					}
				}
				local $" = ',';
				my $qry = "UPDATE $table SET (@table_fields) = (@placeholders) WHERE ";
				local $" = ' AND ';
				$qry .= "@query_values";
				eval {
					$self->{'db'}->do( $qry, undef, @values );
					foreach (@$extra_inserts) {
						$self->{'db'}->do( $_->{'statement'}, undef, @{ $_->{'arguments'} } );
					}
					if ( $table eq 'scheme_fields' && $self->{'system'}->{'dbtype'} eq 'sequences' && $scheme_structure_changed ) {
						$self->remove_profile_data( $data->{'scheme_id'} );
						$self->drop_scheme_view( $data->{'scheme_id'} );
						$self->create_scheme_view( $data->{'scheme_id'} );
					}
				};
				if ($@) {
					say qq(<div class="box" id="statusbad"><p>Update failed - transaction cancelled - no records have been touched.</p>);
					if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
						say qq(<p>Data entry would have resulted in records with either duplicate ids or another unique field with )
						  . qq(duplicate values.</p></div>);
					} else {
						say "<p>Error message: $@</p></div>";
					}
					$self->{'db'}->rollback;
				} else {
					$self->{'db'}->commit && say qq(<div class="box" id="resultsheader"><p>$record_name updated!</p>);
					say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableQuery&amp;table=$table">)
					  . qq(Update another</a> | <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a>)
					  . qq(</p></div>);
					if ( $table eq 'allele_designations' ) {
						$self->update_history( $data->{'isolate_id'}, "$data->{'locus'}: $data->{'allele_id'} -> $new_value{'allele_id'}" );
					}
					return;
				}
			}
		}
	}
	print $buffer;
	return;
}

sub _check_users {
	my ( $self, $newdata ) = @_;
	if (   $newdata->{'id'} == $self->get_curator_id
		&& $newdata->{'status'} eq 'user' )
	{
		print <<"HTML";
<div class="box" id="statusbad"><p>It's not a good idea to remove curator status from yourself 
as you will lock yourself out!  If you really wish to do this, you'll need to do 
it from another curator account.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>
HTML
		return FAILURE;
	} elsif ( $self->is_admin
		&& $newdata->{'id'} == $self->get_curator_id
		&& $newdata->{'status'} ne 'admin' )
	{
		print <<"HTML";
<div class="box" id="statusbad"><p>It's not a good idea to remove admin status from yourself 
as you will lock yourself out!  If you really wish to do this, you'll need to do 
it from another admin account.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>
HTML
		return FAILURE;
	}
	return;
}

sub _check_scheme_fields {

	#Check that only one primary key field is set for a scheme field
	my ( $self, $newdata ) = @_;
	if ( $newdata->{'primary_key'} eq 'true' ) {
		my $primary_key_ref;
		eval {
			$primary_key_ref =
			  $self->{'datastore'}
			  ->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $newdata->{'scheme_id'} );
		};
		$logger->error($@) if $@;
		my $primary_key = ref $primary_key_ref eq 'ARRAY' ? $primary_key_ref->[0] : undef;
		if ( $primary_key && $primary_key ne $newdata->{'field'} ) {
			print <<"HTML";
<div class="box" id="statusbad"><p>This scheme already has a primary key field set ($primary_key).</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>
HTML
			return FAILURE;
		}
	}
}

sub _check_loci {

	#Check that changing a locus allele_id_format to integer is allowed with currently existing data
	my ( $self, $newdata ) = @_;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $non_int;
		if ( $newdata->{'allele_id_format'} eq 'integer' ) {
			my $ids = $self->{'datastore'}->run_list_query( "SELECT allele_id FROM sequences WHERE locus=?", $newdata->{'id'} );
			foreach (@$ids) {
				if ( !BIGSdb::Utils::is_int($_) && $_ ne 'N' ) {
					$non_int = 1;
					last;
				}
			}
		}
		if ($non_int) {
			print <<"HTML";
<div class="box" id="statusbad"><p>The sequence table already contains data with non-integer allele ids.  You will need to remove
these before you can change the allele_id_format to 'integer'.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>
HTML
			return FAILURE;

			#special case to ensure that a locus length is set if it is not marked as variable length
		} elsif ( $newdata->{'length_varies'} ne 'true' && !$newdata->{'length'} ) {
			print <<"HTML";
<div class="box" id="statusbad"><p>Locus set as non variable length but no length is set.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>
HTML
			return FAILURE;
		}
	}
}

sub _check_allele_data {

	#check extended attributes if they exist
	#Prepare extra inserts for PubMed/Genbank records and sequence flags.
	my ( $self, $newdata, $extra_inserts ) = @_;
	my $q   = $self->{'cgi'};
	my $sql = $self->{'db'}->prepare("SELECT field,required,value_format,value_regex FROM locus_extended_attributes WHERE locus=?");
	eval { $sql->execute( $newdata->{'locus'} ) };
	$logger->error($@) if $@;
	my @missing_field;
	while ( my ( $field, $required, $format, $regex ) = $sql->fetchrow_array ) {
		$newdata->{$field} = $q->param($field);
		if ( $required && $newdata->{$field} eq '' ) {
			push @missing_field, $field;
		} elsif ( $format eq 'integer' && $newdata->{$field} ne '' && !BIGSdb::Utils::is_int( $newdata->{$field} ) ) {
			print <<"HTML";
<div class="box" id="statusbad"><p>$field must be an integer.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>
HTML
			return FAILURE;
		} elsif ( $newdata->{$field} ne '' && $regex && $newdata->{$field} !~ /$regex/ ) {
			print <<"HTML";
<div class="box" id="statusbad"><p>Field '$field' does not conform to specified format.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>
HTML
			return FAILURE;
		} else {
			if ( $newdata->{$field} ne '' ) {
				if (
					$self->{'datastore'}->run_query(
						"SELECT EXISTS(SELECT * FROM sequence_extended_attributes WHERE locus=? AND field=? AND allele_id=?)",
						[ $newdata->{'locus'}, $field, $newdata->{'allele_id'} ],
						{ cache => 'CurateUpdatePage::check_allele_data' }
					)
				  )
				{
					push @$extra_inserts,
					  {
						statement => 'UPDATE sequence_extended_attributes SET (value,datestamp,curator) = (?,?,?) WHERE '
						  . '(locus,field,allele_id) = (?,?,?)',
						arguments =>
						  [ $newdata->{$field}, 'now', $newdata->{'curator'}, $newdata->{'locus'}, $field, $newdata->{'allele_id'} ]
					  };
				} else {
					push @$extra_inserts,
					  {
						statement => 'INSERT INTO sequence_extended_attributes(locus,field,allele_id,value,datestamp,curator) VALUES '
						  . '(?,?,?,?,?,?)',
						arguments =>
						  [ $newdata->{'locus'}, $field, $newdata->{'allele_id'}, $newdata->{$field}, 'now', $newdata->{'curator'} ]
					  };
				}
			} else {
				push @$extra_inserts,
				  {
					statement => 'DELETE FROM sequence_extended_attributes WHERE (locus,field,allele_id) = (?,?,?)',
					arguments => [ $newdata->{'locus'}, $field, $newdata->{'allele_id'} ]
				  };
			}
		}
	}
	if (@missing_field) {
		local $" = ', ';
		print <<"HTML";
<div class="box" id="statusbad"><p>Please fill in all extended attribute fields.  The following extended attribute fields are missing: @missing_field.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>
HTML
		return FAILURE;
	}
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		my $existing_flags = $self->{'datastore'}->run_query(
			"SELECT flag FROM allele_flags WHERE locus=? AND allele_id=?",
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
	}
	my $existing_pubmeds = $self->{'datastore'}->run_query(
		"SELECT pubmed_id FROM sequence_refs WHERE locus=? AND allele_id=?",
		[ $newdata->{'locus'}, $newdata->{'allele_id'} ],
		{ fetch => 'col_arrayref' }
	);
	my @new_pubmeds = split /\r?\n/, $q->param('pubmed');
	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !@$existing_pubmeds || none { $new eq $_ } @$existing_pubmeds ) {
			if ( !BIGSdb::Utils::is_int($new) ) {
				print <<"HTML";
<div class="box" id="statusbad"><p>PubMed ids must be integers.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>
HTML
				return FAILURE;
			}
			push @$extra_inserts,
			  {
				statement => 'INSERT INTO sequence_refs (locus,allele_id,pubmed_id,curator,datestamp) VALUES (?,?,?,?,?)',
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
		my $existing_accessions =
		  $self->{'datastore'}->run_list_query( "SELECT databank_id FROM accession WHERE locus=? AND allele_id=? AND databank=?",
			$newdata->{'locus'}, $newdata->{'allele_id'}, $databank );
		my @new_accessions = split /\r?\n/, $q->param("databank_$databank");
		foreach my $new (@new_accessions) {
			chomp $new;
			next if $new eq '';
			if ( !@$existing_accessions || none { $new eq $_ } @$existing_accessions ) {
				push @$extra_inserts,
				  {
					statement => 'INSERT INTO accession (locus,allele_id,databank,databank_id,curator,datestamp) VALUES (?,?,?,?,?,?)',
					arguments => [ $newdata->{'locus'}, $newdata->{'allele_id'}, $databank, $new, $newdata->{'curator'}, 'now' ]
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

sub _prepare_extra_inserts_for_loci {
	my ( $self, $newdata, $extra_inserts ) = @_;
	my $q = $self->{'cgi'};
	my $existing_desc =
	  $self->{'datastore'}->run_query( "SELECT * FROM locus_descriptions WHERE locus=?", $newdata->{'locus'}, { fetch => 'row_hashref' } );
	my ( $full_name, $product, $description ) = ( $q->param('full_name'), $q->param('product'), $q->param('description') );
	if ($existing_desc) {
		if (   $full_name ne ( $existing_desc->{'full_name'} // '' )
			|| $product ne ( $existing_desc->{'product'} // '' )
			|| $description ne ( $existing_desc->{'description'} // '' ) )
		{
			push @$extra_inserts,
			  {
				statement => 'UPDATE locus_descriptions SET (full_name,product,description,curator,datestamp) = (?,?,?,?,?) WHERE locus=?',
				arguments => [ $full_name, $product, $description, $newdata->{'curator'}, 'now', $newdata->{'locus'} ]
			  };
		}
	} else {
		push @$extra_inserts,
		  {
			statement => 'INSERT INTO locus_descriptions (locus,full_name,product,description,curator,datestamp) VALUES (?,?,?,?,?,?)',
			arguments => [ $newdata->{'locus'}, $full_name, $product, $description, $newdata->{'curator'}, 'now' ]
		  };
	}
	return $self->_check_locus_descriptions( $newdata, $extra_inserts );
}

sub _check_locus_aliases_when_updating_other_table {
	my ( $self, $locus, $newdata, $extra_inserts ) = @_;
	my $q = $self->{'cgi'};
	my $existing_aliases =
	  $self->{'datastore'}->run_query( "SELECT alias FROM locus_aliases WHERE locus=?", $locus, { fetch => 'col_arrayref' } );
	my @new_aliases = split /\r?\n/, $q->param('aliases');
	foreach my $new (@new_aliases) {
		chomp $new;
		next if $new eq '';
		next if $new eq $locus;
		if ( !@$existing_aliases || none { $new eq $_ } @$existing_aliases ) {
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
				push @$extra_inserts,
				  {
					statement => 'INSERT INTO locus_aliases (locus,alias,use_alias,curator,datestamp) VALUES (?,?,?,?,?)',
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
			  { statement => 'DELETE FROM locus_aliases WHERE (locus,alias) = (?,?)', arguments => [ $locus, $existing ] };
		}
	}
	return;
}

sub _check_locus_descriptions {
	my ( $self, $newdata, $extra_inserts ) = @_;
	my $q = $self->{'cgi'};
	$self->_check_locus_aliases_when_updating_other_table( $newdata->{'locus'}, $newdata, $extra_inserts )
	  if $q->param('table') eq 'locus_descriptions';
	my $existing_pubmeds = $self->{'datastore'}->run_list_query( "SELECT pubmed_id FROM locus_refs WHERE locus=?", $newdata->{'locus'} );
	my @new_pubmeds = split /\r?\n/, $q->param('pubmed');
	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !@$existing_pubmeds || none { $new eq $_ } @$existing_pubmeds ) {
			if ( !BIGSdb::Utils::is_int($new) ) {
				print <<"HTML";
<div class="box" id="statusbad"><p>PubMed ids must be integers.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>
HTML
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
			  { statement => 'DELETE FROM locus_refs WHERE (locus,pubmed_id) = (?,?)', arguments => [ $newdata->{'locus'}, $existing ] };
		}
	}
	my @new_links;
	my $i = 1;
	foreach ( split /\r?\n/, $q->param('links') ) {
		next if $_ eq '';
		push @new_links, "$i|$_";
		$i++;
	}
	my @existing_links;
	my $sql = $self->{'db'}->prepare("SELECT link_order,url,description FROM locus_links WHERE locus=? ORDER BY link_order");
	eval { $sql->execute( $newdata->{'locus'} ) };
	$logger->error($@) if $@;
	while ( my ( $order, $url, $desc ) = $sql->fetchrow_array ) {
		push @existing_links, "$order|$url|$desc";
	}
	foreach my $existing (@existing_links) {
		if ( !@new_links || none { $existing eq $_ } @new_links ) {
			if ( $existing =~ /^\d+\|(.+?)\|.+$/ ) {
				my $url = $1;
				push @$extra_inserts,
				  { statement => 'DELETE FROM locus_links WHERE (locus,url) = (?,?)', arguments => [ $newdata->{'locus'}, $url ] };
			}
		}
	}
	foreach my $new (@new_links) {
		chomp $new;
		next if $new eq '';
		if ( !@existing_links || none { $new eq $_ } @existing_links ) {
			if ( $new !~ /^(.+?)\|(.+)\|(.+)$/ ) {
				print <<"HTML";
	<div class="box" id="statusbad"><p>Links must have an associated description separated from the URL by a '|'.</p>
	<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>
HTML
				return FAILURE;
			} else {
				my ( $field_order, $url, $desc ) = ( $1, $2, $3 );
				push @$extra_inserts,
				  {
					statement => 'INSERT INTO locus_links (locus,url,description,link_order,curator,datestamp) VALUES (?,?,?,?,?,?)',
					arguments => [ $newdata->{'locus'}, $url, $desc, $field_order, $newdata->{'curator'}, 'now' ]
				  };
			}
		}
	}
	return;
}

sub _prepare_extra_inserts_for_seqbin {
	my ( $self, $newdata, $extra_inserts ) = @_;
	my $q = $self->{'cgi'};
	my $seq_attributes =
	  $self->{'datastore'}
	  ->run_query( "SELECT key,type FROM sequence_attributes ORDER BY key", undef, { fetch => 'all_arrayref', slice => {} } );
	my $existing_values = $self->{'datastore'}->run_query( "SELECT key,value FROM sequence_attribute_values WHERE seqbin_id=?",
		$newdata->{'id'}, { fetch => 'all_arrayref', slice => {} } );
	my %existing_value = map { $_->{'key'} => $_->{'value'} } @$existing_values;
	my @type_errors;
	foreach my $attribute (@$seq_attributes) {
		next if !defined $q->param( $attribute->{'key'} );
		( my $value = $q->param( $attribute->{'key'} ) ) =~ s/'/\\'/g;
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
						statement =>
						  'UPDATE sequence_attribute_values SET (value,curator,datestamp) = (?,?,?) WHERE (seqbin_id,key) = (?,?)',
						arguments => [ $value, $newdata->{'curator'}, 'now', $newdata->{'id'}, $attribute->{'key'} ]
					  };
				}
			}
		} else {
			if ( $value ne '' ) {
				push @$extra_inserts,
				  {
					statement => 'INSERT INTO sequence_attribute_values (seqbin_id,key,value,curator,datestamp) VALUES (?,?,?,?,?)',
					arguments => [ $newdata->{'id'}, $attribute->{'key'}, $value, $newdata->{'curator'}, 'now' ]
				  };
			}
		}
	}
	if (@type_errors) {
		local $" = '<br />';
		say qq(<div class="box" id="statusbad"><p>@type_errors</p></div>);
		return FAILURE;
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	my $type  = $self->get_record_name($table);
	return "Update $type - $desc";
}
1;
