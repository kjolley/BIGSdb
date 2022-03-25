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
package BIGSdb::CurateIsolateAddPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateAddPage);
use BIGSdb::Utils;
use BIGSdb::Constants qw(:interface :submissions);
use List::MoreUtils qw(any uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant SUCCESS => 1;

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/curator_guide/0090_adding_isolates.html#adding-isolate-records";
}

sub get_javascript {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = << "END";
\$(function () {
  if (!Modernizr.inputtypes.date){
 	\$(".no_date_picker").css("display","inline");
  }
  \$("#aliases").on('keyup paste',alias_change);
  \$(".allow_null").on('change',allow_null_change);
});
function alias_change(){
  	if (\$("#aliases").val().indexOf(";") > -1 || \$("#aliases").val().indexOf(",") > -1){
  		\$("span#alias_warning").html("Put each alias on a separate line - do not use semi-colon or comma to separate."); 		
  	} else {
  		\$("span#alias_warning").html("");
  	}
}
function allow_null_change(){
	var field = \$(this).attr('id').replace('allow_null_','');
	\$("#field_" + field).prop("disabled",\$(this).prop('checked'));
}
END
	return $buffer;
}

sub print_content {
	my ($self) = @_;
	say q(<h1>Add new isolate</h1>);
	if ( !$self->can_modify_table('isolates') ) {
		$self->print_bad_status(
			{
				message => q(our user account is not allowed to add records ) . q(to the isolates table.)
			}
		);
		return;
	}
	if ( $self->{'permissions'}->{'only_private'} ) {
		$self->print_bad_status(
			{
				    message => q(Your user account is not allowed to add records )
				  . q(to the isolates table using this interface. You can only upload private data using )
				  . q(the batch upload page.)
			}
		);
		return;
	}
	my $q = $self->{'cgi'};
	my %newdata;
	foreach my $field ( @{ $self->{'xmlHandler'}->get_field_list } ) {
		if ( $q->param($field) ) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			if ( ( $thisfield->{'multiple'} // q() ) eq 'yes' ) {
				@{ $newdata{$field} } = $q->multi_param($field);
			} else {
				$newdata{$field} = $q->param($field);
			}
		} else {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			if ( $thisfield->{'type'} eq 'int'
				&& lc($field) eq 'id' )
			{
				$newdata{$field} = $self->next_id('isolates');
			}
		}
	}
	if ( $q->param('sent') ) {
		return if ( $self->_check( \%newdata ) // 0 ) == SUCCESS;
	}
	$self->_print_interface( \%newdata );
	return;
}

sub _check {
	my ( $self, $newdata ) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	my $loci   = $self->{'datastore'}->get_loci( { query_pref => 1, set_id => $set_id } );
	@$loci = uniq @$loci;
	my @bad_field_buffer;
	my $insert                      = 1;
	my $bad_codon_table_buffer      = $self->check_codon_table($newdata);
	my $bad_provenance_field_buffer = $self->check_provenance_fields($newdata);
	my $bad_eav_field_buffer        = $self->check_eav_fields($newdata);
	push @bad_field_buffer, @$bad_codon_table_buffer, @$bad_provenance_field_buffer, @$bad_eav_field_buffer;

	if ( $self->alias_duplicates_name ) {
		push @bad_field_buffer, 'Aliases: duplicate isolate name - aliases are ALTERNATIVE names for the isolate.';
	}
	if ( $self->alias_null_term ) {
		push @bad_field_buffer,
		  'Aliases: this is an optional field - leave blank rather than using a term to indicate no value.';
	}
	my $validation_failures = $self->{'submissionHandler'}->run_validation_checks($newdata);
	if (@$validation_failures) {
		push @bad_field_buffer, @$validation_failures;
	}
	$self->{'submissionHandler'}->cleanup_validation_rules;
	foreach my $locus (@$loci) {
		if ( $q->param("locus:$locus") ) {
			$newdata->{"locus:$locus"}         = $q->param("locus:$locus");
			$newdata->{"locus:$locus\_status"} = $q->param("locus:$locus\_status");
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			if ( $locus_info->{'allele_id_format'} eq 'integer'
				&& !BIGSdb::Utils::is_int( $newdata->{"locus:$locus"} ) )
			{
				push @bad_field_buffer, "Locus '$locus': allele value must be an integer.";
			} elsif ( $locus_info->{'allele_id_regex'}
				&& $newdata->{"locus:$locus"} !~ /$locus_info->{'allele_id_regex'}/x )
			{
				push @bad_field_buffer, qq(Locus '$locus' allele value is invalid - )
				  . qq(it must match the regular expression /$locus_info->{'allele_id_regex'}/);
			}
		}
	}
	if (@bad_field_buffer) {
		local $" = '<br />';
		$self->print_bad_status(
			{
				message => q(There are problems with your record submission. Please address the following:),
				detail  => qq(@bad_field_buffer)
			}
		);
		$insert = 0;
	}
	foreach my $field ( keys %$newdata ) {    #Strip any trailing spaces
		if ( defined $newdata->{$field} && !ref $newdata->{$field} ) {
			$newdata->{$field} =~ s/^\s*//gx;
			$newdata->{$field} =~ s/\s*$//gx;
		}
	}
	if ($insert) {
		if ( $self->id_exists( $newdata->{'id'} ) ) {
			$self->print_bad_status(
				{
					message => qq(id-$newdata->{'id'} has already been defined - )
					  . q(please choose a different id number.)
				}
			);
			$insert = 0;
		} elsif ( $self->retired_id_exists( $newdata->{'id'} ) ) {
			$self->print_bad_status(
				{ message => qq(id-$newdata->{'id'} has been retired - please choose a different id number.) } );
			$insert = 0;
		}
		return $self->_insert($newdata) if $insert;
	}
	return;
}

sub check_codon_table {
	my ( $self, $newdata, $options ) = @_;
	my $q          = $self->{'cgi'};
	my $bad_buffer = [];
	return $bad_buffer
	  if ( $self->{'system'}->{'alternative_codon_tables'} // q() ) ne 'yes' || !$q->param('codon_table');
	my $tables = Bio::Tools::CodonTable->tables;
	my %allowed = map { $_ => 1 } keys %$tables;
	if ( !$allowed{ $q->param('codon_table') } ) {
		push @$bad_buffer, q(Invalid codon table);
	}
	return $bad_buffer;
}

sub check_provenance_fields {
	my ( $self, $newdata, $options ) = @_;
	my $q                = $self->{'cgi'};
	my $set_id           = $self->get_set_id;
	my $field_list       = $self->{'xmlHandler'}->get_field_list;
	my $user_info        = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $bad_field_buffer = [];
	foreach my $field (@$field_list) {
		my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
		my $value_expected = ( $thisfield->{'required'} // q() ) eq 'expected';
		if ( $field eq 'curator' ) {
			$newdata->{$field} = $self->get_curator_id;
		} elsif ( $field eq 'sender' && $user_info->{'status'} eq 'submitter' && !$options->{'update'} ) {
			$newdata->{$field} = $self->get_curator_id;
		} elsif ( ( $options->{'update'} && $field eq 'datestamp' )
			|| ( !$options->{'update'} && ( $field eq 'datestamp' || $field eq 'date_entered' ) ) )
		{
			$newdata->{$field} = BIGSdb::Utils::get_datestamp();
		} else {
			if ( ( $thisfield->{'multiple'} // q() ) eq 'yes' ) {
				if ( ( $thisfield->{'optlist'} // q() ) eq 'yes' ) {
					$newdata->{$field} = scalar $q->multi_param($field) ? [ $q->multi_param($field) ] : q();
				} else {
					my @new_values = split /\r?\n/x, $q->param($field) // q();
					@new_values = uniq(@new_values);
					if (@new_values) {
						$newdata->{$field} = \@new_values;
					} else {
						$newdata->{$field} = $value_expected ? 'null' : undef;
					}
				}
			} else {
				if ( $value_expected && ( $q->param($field) // q() ) eq q() ) {
					$newdata->{$field} = 'null';
				} else {
					$newdata->{$field} = $q->param($field);
				}
			}
		}
		my $bad_field =
		  $self->{'submissionHandler'}->is_field_bad( 'isolates', $field, $newdata->{$field}, undef, $set_id );

		#We may have set a value of 'null' for expected fields with no values in order to pass submission checks.
		#It should now be set back to undefined for upload to the database.
		if ( ( $newdata->{$field} // q() ) eq 'null' ) {
			undef $newdata->{$field};
		}
		if ($bad_field) {
			push @$bad_field_buffer, qq(Field '$field': $bad_field);
		}
	}
	return $bad_field_buffer;
}

sub check_eav_fields {
	my ( $self, $newdata ) = @_;
	my $q                = $self->{'cgi'};
	my $set_id           = $self->get_set_id;
	my $eav_fields       = $self->{'datastore'}->get_eav_fields;
	my $bad_field_buffer = [];
	foreach my $eav_field (@$eav_fields) {
		my $field_name = $eav_field->{'field'};
		if ( $q->param($field_name) ) {
			$newdata->{$field_name} = $q->param($field_name);
		}
		my $bad_field =
		  $self->{'submissionHandler'}
		  ->is_field_bad( 'isolates', $field_name, $newdata->{$field_name}, undef, $set_id );
		if ($bad_field) {
			push @$bad_field_buffer, qq(Field '$field_name': $bad_field);
		}
	}
	return $bad_field_buffer;
}

sub alias_duplicates_name {
	my ($self)       = @_;
	my $q            = $self->{'cgi'};
	my $isolate_name = $q->param( $self->{'system'}->{'labelfield'} );
	my @aliases = split /\r?\n/x, $q->param('aliases');
	foreach my $alias (@aliases) {
		$alias =~ s/\s+$//x;
		$alias =~ s/^\s+//x;
		next if $alias eq q();
		return 1 if $alias eq $isolate_name;
	}
	return;
}

sub alias_null_term {
	my ($self)       = @_;
	my $q            = $self->{'cgi'};
	my $isolate_name = $q->param( $self->{'system'}->{'labelfield'} );
	my @aliases = split /\r?\n/x, $q->param('aliases');
	my %null_terms = map { lc($_) => 1 } NULL_TERMS;
	foreach my $alias (@aliases) {
		$alias =~ s/\s+$//x;
		$alias =~ s/^\s+//x;
		next if $alias eq q();
		return 1 if $null_terms{ lc($alias) };
	}
	return;
}

sub _insert {
	my ( $self, $newdata ) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	my @fields_with_values;
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	foreach my $field (@$field_list) {
		if ( ( $newdata->{$field} // q() ) ne q() ) {
			push @fields_with_values, $field;
		}
	}
	my $inserts      = [];
	my @placeholders = ('?') x @fields_with_values;
	local $" = ',';
	my $qry    = "INSERT INTO isolates (@fields_with_values) VALUES (@placeholders)";
	my $values = [];
	foreach my $field (@fields_with_values) {
		my $cleaned = $self->clean_value( $newdata->{$field}, { no_escape => 1 } );
		push @$values, $cleaned;
	}
	push @$inserts, { statement => $qry, arguments => $values };
	$self->_prepare_codon_table_inserts( $inserts, $newdata );
	$self->_prepare_locus_inserts( $inserts, $newdata );
	$self->_prepare_alias_inserts( $inserts, $newdata );
	return if $self->_prepare_pubmed_inserts( $inserts, $newdata );
	return if $self->_prepare_sparse_field_inserts( $inserts, $newdata );
	local $" = ';';

	foreach (@$inserts) {
		$self->{'db'}->do( $_->{'statement'}, undef, @{ $_->{'arguments'} } );
	}
	if ($@) {
		my $detail;
		if ( $@ =~ /duplicate/x && $@ =~ /unique/x ) {
			$detail = q(Data entry would have resulted in records with either duplicate ids or another )
			  . q(unique field with duplicate values.);
		} else {
			$logger->error("Insert failed: $qry  $@");
		}
		$self->print_bad_status(
			{
				message => q(Insert failed - transaction cancelled - no records have been touched.),
				detail  => $detail
			}
		);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		my ( $upload_contigs_url, $link_contigs_url );
		$upload_contigs_url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=addSeqbin&amp;isolate_id=$newdata->{'id'});
		if ( ( $self->{'system'}->{'remote_contigs'} // q() ) eq 'yes' ) {
			$link_contigs_url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=batchAddRemoteContigs&amp;isolate_id=$newdata->{'id'});
		}
		$self->print_good_status(
			{
				message            => qq(Isolate id-$newdata->{'id'} added.),
				navbar             => 1,
				more_url           => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=isolateAdd),
				upload_contigs_url => $upload_contigs_url,
				link_contigs_url   => $link_contigs_url
			}
		);
		$self->update_history( $newdata->{'id'}, 'Isolate record added' );
		return SUCCESS;
	}
	return;
}

sub _prepare_codon_table_inserts {
	my ( $self, $inserts, $newdata ) = @_;
	my $q = $self->{'cgi'};
	return if !$q->param('codon_table');
	push @$inserts,
	  {
		statement => 'INSERT INTO codon_tables (isolate_id,codon_table,curator,datestamp) VALUES (?,?,?,?)',
		arguments => [ $newdata->{'id'}, scalar $q->param('codon_table'), $newdata->{'curator'}, 'now' ]
	  };
	return;
}

sub _prepare_locus_inserts {
	my ( $self, $inserts, $newdata ) = @_;
	my $set_id = $self->get_set_id;
	my $loci = $self->{'datastore'}->get_loci( { query_pref => 1, set_id => $set_id } );
	@$loci = uniq @$loci;
	my $q = $self->{'cgi'};
	foreach my $locus (@$loci) {
		if ( $q->param("locus:$locus") ) {
			push @$inserts,
			  {
				statement => 'INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,'
				  . 'curator,date_entered,datestamp) VALUES (?,?,?,?,?,?,?,?,?)',
				arguments => [
					$newdata->{'id'},           $locus,
					$newdata->{"locus:$locus"}, $newdata->{'sender'},
					'confirmed',                'manual',
					$newdata->{'curator'},      'now',
					'now'
				]
			  };
		}
	}
	return;
}

sub _prepare_alias_inserts {
	my ( $self, $inserts, $newdata ) = @_;
	my $q = $self->{'cgi'};
	my @new_aliases = split /\r?\n/x, $q->param('aliases');
	@new_aliases = uniq(@new_aliases);
	foreach my $new (@new_aliases) {
		$new = $self->clean_value( $new, { no_escape => 1 } );
		next if $new eq '';
		push @$inserts,
		  {
			statement => 'INSERT INTO isolate_aliases (isolate_id,alias,curator,datestamp) VALUES (?,?,?,?)',
			arguments => [ $newdata->{'id'}, $new, $newdata->{'curator'}, 'now' ]
		  };
	}
	return;
}

sub _prepare_pubmed_inserts {
	my ( $self, $inserts, $newdata ) = @_;
	my $q = $self->{'cgi'};
	my @new_pubmeds = split /\r?\n/x, $q->param('pubmed');
	@new_pubmeds = uniq(@new_pubmeds);
	my $error;
	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !BIGSdb::Utils::is_int($new) ) {
			$self->print_bad_status( { message => q(PubMed ids must be integers.) } );
			$error = 1;
		}
		push @$inserts,
		  {
			statement => 'INSERT INTO refs (isolate_id,pubmed_id,curator,datestamp) VALUES (?,?,?,?)',
			arguments => [ $newdata->{'id'}, $new, $newdata->{'curator'}, 'now' ]
		  };
	}
	return $error;
}

sub _prepare_sparse_field_inserts {
	my ( $self, $inserts, $newdata ) = @_;
	my $fields = $self->{'datastore'}->get_eav_fields;
	my $error  = 0;
	foreach my $field (@$fields) {
		my $method = "_prepare_eav_$field->{'value_format'}_inserts";
		eval { $error = $self->$method( $field, $inserts, $newdata ); };
		if ($@) {
			$logger->error($@);
			last;
		}
		last if $error;
	}
	return $error;
}

sub _prepare_eav_integer_inserts {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $inserts, $newdata ) = @_;
	my $field_name = $field->{'field'};
	my $q          = $self->{'cgi'};
	my $value      = $q->param($field_name);
	return if !defined $value || $value eq q();
	push @$inserts,
	  {
		statement => 'INSERT INTO eav_int (isolate_id,field,value) VALUES (?,?,?)',
		arguments => [ $newdata->{'id'}, $field_name, $value ]
	  };
	return;
}

sub _prepare_eav_float_inserts {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $inserts, $newdata ) = @_;
	my $field_name = $field->{'field'};
	my $q          = $self->{'cgi'};
	my $value      = $q->param($field_name);
	return if !defined $value || $value eq q();
	push @$inserts,
	  {
		statement => 'INSERT INTO eav_float (isolate_id,field,value) VALUES (?,?,?)',
		arguments => [ $newdata->{'id'}, $field_name, $value ]
	  };
	return;
}

sub _prepare_eav_text_inserts {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $inserts, $newdata ) = @_;
	my $field_name = $field->{'field'};
	my $q          = $self->{'cgi'};
	my $value      = $q->param($field_name);
	return if !defined $value || $value eq q();
	push @$inserts,
	  {
		statement => 'INSERT INTO eav_text (isolate_id,field,value) VALUES (?,?,?)',
		arguments => [ $newdata->{'id'}, $field_name, $value ]
	  };
	return;
}

sub _prepare_eav_date_inserts {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $inserts, $newdata ) = @_;
	my $field_name = $field->{'field'};
	my $q          = $self->{'cgi'};
	my $value      = $q->param($field_name);
	return if !defined $value || $value eq q();
	push @$inserts,
	  {
		statement => 'INSERT INTO eav_date (isolate_id,field,value) VALUES (?,?,?)',
		arguments => [ $newdata->{'id'}, $field_name, $value ]
	  };
	return;
}

sub _prepare_eav_boolean_inserts {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $field, $inserts, $newdata ) = @_;
	my $field_name = $field->{'field'};
	my $q          = $self->{'cgi'};
	my $value      = $q->param($field_name);
	return if !defined $value || $value eq q();
	push @$inserts,
	  {
		statement => 'INSERT INTO eav_boolean (isolate_id,field,value) VALUES (?,?,?)',
		arguments => [ $newdata->{'id'}, $field_name, $value ]
	  };
	return;
}

sub _print_interface {
	my ( $self, $newdata ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="queryform"><p>Please fill in the fields below - )
	  . q(required fields are marked with an exclamation mark (!).</p>);
	say q(<div class="scrollable">);
	say $q->start_form;
	$q->param( sent => 1 );
	say $q->hidden($_) foreach qw(page db sent);
	$self->print_codon_table_selection($newdata);
	$self->print_provenance_form_elements($newdata);
	$self->print_sparse_field_form_elements($newdata);
	$self->_print_allele_designation_form_elements($newdata);
	$self->print_action_fieldset;
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _get_field_width {
	my ( $self, $field_list ) = @_;
	my $longest_name = BIGSdb::Utils::get_largest_string_length($field_list);
	my $width        = int( 0.5 * $longest_name ) + 2;
	$width = 15 if $width > 15;
	$width = 6  if $width < 6;
	return $width;
}

sub _get_html5_args {
	my ( $self, $args ) = @_;
	my ( $required_field, $field, $thisfield ) = @{$args}{qw(required_field field thisfield)};
	my $html5_args = {};
	$html5_args->{'required'} = 'required' if $required_field;
	if ( $thisfield->{'type'} eq 'date' && !$thisfield->{'optlist'} ) {
		$html5_args->{'type'} = 'date';
		$html5_args->{'min'}  = $thisfield->{'min'} if defined $thisfield->{'min'};
		$html5_args->{'max'}  = $thisfield->{'max'} if defined $thisfield->{'max'};
	}
	if ( $thisfield->{'type'} =~ /^int/x || $thisfield->{'type'} eq 'float' ) {
		if ( $field ne 'sender' && !$thisfield->{'optlist'} ) {
			$html5_args->{'type'} = 'number';
		}
		$html5_args->{'step'} = $thisfield->{'type'} =~ /^int/x ? 1 : 'any';
		$html5_args->{'min'} = $thisfield->{'min'} if defined $thisfield->{'min'};
		$html5_args->{'max'} = $thisfield->{'max'} if defined $thisfield->{'max'};
	}
	$html5_args->{'pattern'} = $thisfield->{'regex'} if $thisfield->{'regex'};
	return $html5_args;
}

sub print_codon_table_selection {
	my ( $self, $newdata, $options ) = @_;
	return if ( $self->{'system'}->{'alternative_codon_tables'} // q() ) ne 'yes';
	my $codon_table;
	if ($options->{'update'}){
		$codon_table = $self->{'datastore'}->run_query('SELECT codon_table FROM codon_tables WHERE isolate_id=?',$newdata->{'id'});
	}
	my $q           = $self->{'cgi'};
	my $db_codon_table = $self->{'datastore'}->get_codon_table;
	my $tables      = Bio::Tools::CodonTable->tables;
	my $labels      = {};
	my @ids         = sort { $a <=> $b } keys %$tables;
	foreach my $id (@ids) {
		$labels->{$id} = "$id - $tables->{$id}";
	}
	say q(<fieldset style="float:left"><legend>Codon table</legend>);
	say q(<p>Set codon table to use if different from the database default )
	  . qq(($db_codon_table - $tables->{$db_codon_table}).</p>);
	say $q->popup_menu(
		-name    => 'codon_table',
		-id      => 'codon_table',
		-values  => [ '', @ids ],
		-labels  => $labels,
		-default => $codon_table
	);
	say q(</fieldset>);
	return;
}

sub print_provenance_form_elements {
	my ( $self, $newdata, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q          = $self->{'cgi'};
	my $user_info  = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $set_id     = $self->get_set_id;
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	say q(<fieldset style="float:left"><legend>Primary metadata</legend>);
	say q(<div style="white-space:nowrap">);
	my $width = $self->_get_field_width($field_list);
	say q(<ul>);

	#Display required fields first
	foreach my $required ( 1, 0 ) {
		foreach my $field (@$field_list) {
			my $thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			next if ( $thisfield->{'no_curate'} // '' ) eq 'yes';
			next if ( $thisfield->{'prefixes'} );
			my $required_field = !( ( $thisfield->{'required'} // '' ) eq 'no' );
			if ( $required_field == $required ) {
				if ( $thisfield->{'prefixed_by'} ) {
					$self->_print_field(
						{
							field        => $thisfield->{'prefixed_by'},
							required     => $required,
							newdata      => $newdata,
							width        => $width,
							update       => $options->{'update'},
							user_info    => $user_info,
							prefix       => 1,
							display_name => $field
						}
					);
					if ( $thisfield->{'prefix_separator'} ) {
						print $thisfield->{'prefix_separator'};
					}
				}
				$self->_print_field(
					{
						field        => $field,
						required     => $required,
						newdata      => $newdata,
						width        => $width,
						update       => $options->{'update'},
						user_info    => $user_info,
						postfix      => $thisfield->{'prefixed_by'} ? 1 : 0,
						display_name => $thisfield->{'prefixed_by'} ? q() : $field
					}
				);
			}
		}
	}
	my $aliases;
	if ( $options->{'update'} ) {
		$aliases = $self->{'datastore'}->get_isolate_aliases( scalar $q->param('id') );
	} else {
		$aliases = [];
	}
	say qq(<li><label for="aliases" class="form" style="width:${width}em">aliases:&nbsp;</label>);
	local $" = "\n";
	say $q->textarea(
		-name        => 'aliases',
		-id          => 'aliases',
		-rows        => 2,
		-cols        => 12,
		-style       => 'width:10em',
		-default     => "@$aliases",
		-placeholder => 'Enter one per line...'
	);
	say $self->get_tooltip(q(List of alternative names for this isolate. Put each alias on a separate line.));
	say q(<span id="alias_warning" class="form_warning"></span>);
	say q(</li>);
	my $pubmed;

	if ( $options->{'update'} ) {
		$pubmed = $self->{'datastore'}->get_isolate_refs( scalar $q->param('id') );
	} else {
		$pubmed = [];
	}
	say qq(<li><label for="pubmed" class="form" style="width:${width}em">PubMed ids:&nbsp;</label>);
	say $q->textarea(
		-name        => 'pubmed',
		-id          => 'pubmed',
		-rows        => 2,
		-cols        => 12,
		-style       => 'width:10em',
		-default     => "@$pubmed",
		-placeholder => 'Enter one per line...'
	);
	say $self->get_tooltip( q(List of PubMed ids of publications associated with this isolate. )
		  . q(Put each identifier on a separate line.) );
	say q(</li></ul>);
	say q(</div></fieldset>);
	return;
}

sub _print_field {
	my ( $self, $values ) = @_;
	my ( $field, $required, $newdata, $width, $update, $user_info, $display_name, $prefix, $postfix ) =
	  @{$values}{qw (field required newdata width update user_info display_name prefix postfix)};
	my $q              = $self->{'cgi'};
	my $thisfield      = $self->{'xmlHandler'}->get_field_attributes($field);
	my $required_field = !( ( $thisfield->{'required'} // '' ) eq 'no' );
	my $html5_args     = $self->_get_html5_args(
		{
			required_field => $required_field,
			field          => $field,
			thisfield      => $thisfield
		}
	);
	if (
		( $thisfield->{'required'} // q() ) eq 'expected'
		&& ( $q->param("allow_null_$field")
			|| ( $update && !defined $newdata->{$field} && !defined $q->param($field) ) )
	  )
	{
		$html5_args->{'disabled'} = 1;
	}
	$thisfield->{'length'} = $thisfield->{'length'} // ( $thisfield->{'type'} eq 'int' ? 15 : 50 );
	( my $cleaned_name = $display_name ) =~ tr/_/ /;
	my ( $label, $title ) = $self->get_truncated_label( $cleaned_name, 25 );
	my $title_attribute = $title ? qq( title="$title") : q();
	my %no_label_field = map { $_ => 1 } qw (curator date_entered datestamp);
	my $for = $no_label_field{$field} ? q() : qq( for="field_$field");
	print q(<li>) if !$postfix;

	if ( defined $display_name && $display_name ne q() ) {
		print qq(<label$for class="form" style="width:${width}em"$title_attribute>);
		print $label;
		print ':';
		print '!' if $required;
		say q(</label>);
	}
	print q(<div style="display:inline-block" class="field_warning">) if $thisfield->{'warning'};
	my $methods = {
		update_id        => '_print_id_no_update',
		optlist          => '_print_optlist',
		bool             => '_print_bool',
		datestamp        => '_print_datestamp',
		date_entered     => '_print_date_entered',
		curator          => '_print_curator',
		sender_submitter => '_print_sender_when_submitting',
		user_field       => '_print_user',
		long_text_field  => '_print_long_text_field',
		default_field    => '_print_default_field'
	};
	foreach my $condition (
		qw(update_id optlist bool datestamp date_entered curator sender_submitter
		user_field long_text_field default_field)
	  )
	{
		my $method = $methods->{$condition};
		my $args   = {
			newdata    => $newdata,
			field      => $field,
			thisfield  => $thisfield,
			html5_args => $html5_args,
			update     => $update,
			user_info  => $user_info
		};
		if ( $self->$method($args) ) {
			last;
		}
	}
	if ( $thisfield->{'suffix'} ) {
		say $thisfield->{'suffix'};
	}
	if ( $thisfield->{'warning'} ) {
		say q(</div>);
		say $self->get_warning_tooltip( $thisfield->{'warning'} );
	}
	if ( $thisfield->{'comments'} ) {
		say $self->get_tooltip( $thisfield->{'comments'} );
	}
	if ( ( $thisfield->{'required'} // '' ) eq 'expected' ) {
		my %args = (
			-name  => "allow_null_$field",
			-id    => "allow_null_$field",
			-label => 'Value unknown',
			-class => 'allow_null'
		);
		$args{'-checked'} = 'checked'
		  if $update && ( $newdata->{$field} // q() ) eq q();
		say $q->checkbox(%args);
	}
	my %special_date_field = map { $_ => 1 } qw(datestamp date_entered);
	if ( !$special_date_field{$field} && lc( $thisfield->{'type'} ) eq 'date' ) {
		say q( <span class="no_date_picker" style="display:none">format: yyyy-mm-dd</span>);
	}
	say q(</li>) if !$prefix;
	return;
}

sub _print_id_no_update {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self,  $args )    = @_;
	my ( $field, $newdata ) = @{$args}{qw(field newdata)};
	my $q = $self->{'cgi'};
	if ( $field eq 'id' && $q->param('page') eq 'isolateUpdate' ) {
		say qq(<b>$newdata->{'id'}</b>);
		say $q->hidden('id');
		return 1;
	}
	return;
}

sub _print_optlist {         ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $field, $newdata, $thisfield, $html5_args ) = @{$args}{qw(field newdata thisfield html5_args)};
	if ( $thisfield->{'optlist'} ) {
		my $q        = $self->{'cgi'};
		my $optlist  = $thisfield->{'option_list_values'} // $self->{'xmlHandler'}->get_field_option_list($field);
		my $multiple = ( $thisfield->{'multiple'} // q() ) eq 'yes';
		my %args     = (
			-name   => $field,
			-id     => "field_$field",
			-values => $multiple ? $optlist : [ '', @$optlist ],
			-labels => { '' => ' ' },
			-default => $newdata->{ lc $field } // $thisfield->{'default'},
			-multiple => $multiple ? 'true' : 'false',
			-style => $multiple ? q(border:1px solid #008) : q()
		);
		if ( $multiple && @$optlist ) {
			my $size = @$optlist <= 10 ? @$optlist : 10;
			$args{'-size'} = $size;
		}
		say q(<div style="display:inline-block">);
		say $self->popup_menu( %args, %$html5_args );
		if ($multiple) {
			say q(<br /><span class="comment" style="color:#008">Supports multiple values</span>);
		}
		say q(</div>);
		return 1;
	}
	return;
}

sub _print_bool {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $field, $newdata, $thisfield ) = @{$args}{qw(field newdata thisfield )};
	return if $thisfield->{'type'} !~ /^bool/x;
	my $default = $newdata->{ lc($field) } // $thisfield->{'default'};
	my $q = $self->{'cgi'};
	if ( defined $default ) {
		$default = 'true'  if $default eq '1';
		$default = 'false' if $default eq '0';
	} elsif ( !defined $q->param($field) ) {

		#Without this, the first option is selected if form is reloaded due to failed validation
		$q->delete($field);
	}
	say $q->radio_group(
		-name    => $field,
		-id      => "field_$field",
		-values  => [qw(true false)],
		-default => $default // q()
	);
	return 1;
}

sub _print_datestamp {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $field, $newdata, $thisfield ) = @{$args}{qw(field newdata thisfield )};
	if ( lc($field) eq 'datestamp' ) {
		say '<b>' . BIGSdb::Utils::get_datestamp() . '</b>';
		return 1;
	}
	return;
}

sub _print_date_entered {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $field, $newdata, $update ) = @{$args}{qw(field newdata update)};
	if ( lc($field) eq 'date_entered' ) {
		if ($update) {
			my $q = $self->{'cgi'};
			say qq(<b>$newdata->{'date_entered'}</b>);
			say $q->hidden( 'date_entered' => $newdata->{'date_entered'} );
		} else {
			my $datestamp = BIGSdb::Utils::get_datestamp();
			say qq(<b>$datestamp</b>);
		}
		return 1;
	}
	return;
}

sub _print_curator {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ($field) = @{$args}{qw(field )};
	if ( lc($field) eq 'curator' ) {
		my $name = $self->get_curator_name;
		say qq(<b>$name ($self->{'username'})</b>);
		return 1;
	}
	return;
}

sub _print_sender_when_submitting {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $field, $update, $user_info ) = @{$args}{qw(field update user_info)};
	if (   lc($field) eq 'sender'
		&& $user_info->{'status'} eq 'submitter'
		&& !$update )
	{
		my $name = $self->get_curator_name;
		say qq(<b>$name ($self->{'username'})</b>);
		return 1;
	}
	return;
}

sub _print_user {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $field, $newdata, $thisfield, $html5_args, $user_info ) =
	  @{$args}{qw(field newdata thisfield html5_args user_info)};
	if (   lc($field) eq 'sender'
		|| lc($field) eq 'sequenced_by'
		|| ( $thisfield->{'userfield'} // '' ) eq 'yes' )
	{
		my ( $users, $user_labels );
		if ( $user_info->{'status'} eq 'submitter' ) {
			( $users, $user_labels ) =
			  $self->{'datastore'}->get_users( { same_user_group => 1, user_id => $user_info->{'id'} } );
		} else {
			( $users, $user_labels ) = $self->{'datastore'}->get_users;
		}
		$user_labels->{''} = ' ';
		my $q = $self->{'cgi'};
		say $q->popup_menu(
			-name    => $field,
			-id      => "field_$field",
			-values  => [ '', @$users ],
			-labels  => $user_labels,
			-default => ( $newdata->{ lc($field) } // $thisfield->{'default'} ),
			%$html5_args
		);
		return 1;
	}
}

sub _print_long_text_field {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $field, $newdata, $thisfield, $html5_args ) =
	  @{$args}{qw(field newdata thisfield html5_args)};
	my $multiple = ( $thisfield->{'multiple'} // q() ) eq 'yes';
	return if ( $thisfield->{'length'} // 0 ) <= 60 && !$multiple;
	if ($multiple) {
		my $values = $newdata->{ lc($field) } // [];
		$values = [] if !ref $values;
		@$values =
		  $thisfield->{'type'} eq 'text'
		  ? sort { $a cmp $b } @$values
		  : sort { $a <=> $b } @$values;
		local $" = qq(\n);
		$newdata->{ lc($field) } = qq(@$values);
	}
	my $q = $self->{'cgi'};
	say q(<div style="display:inline-block">);
	say $q->textarea(
		-name => $field,
		-id   => "field_$field",
		-rows => 3,
		-cols => $thisfield->{'length'} < 60 ? $thisfield->{'length'} : 60,
		-default => ( $newdata->{ lc($field) } // $thisfield->{'default'} ),
		-placeholder => $multiple ? q(Enter one per line...) : q(),
		-style       => $multiple ? q(border:1px solid #008) : q(),
		%$html5_args
	);
	if ($multiple) {
		say q(<br /><span class="comment" style="color:#008">)
		  . q(Supports multiple values - enter each one on separate line</span>);
	}
	say q(</div>);
	return 1;
}

sub _print_default_field {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $args ) = @_;
	my ( $field, $newdata, $thisfield, $html5_args ) =
	  @{$args}{qw(field newdata thisfield html5_args)};
	my $q = $self->{'cgi'};
	say $self->textfield(
		name      => $field,
		id        => "field_$field",
		size      => $thisfield->{'length'},
		maxlength => $thisfield->{'length'},
		value     => ( scalar $q->param($field) // $newdata->{ lc($field) } // $thisfield->{'default'} ),
		%$html5_args
	);
	return;
}

sub print_sparse_field_form_elements {
	my ( $self, $newdata, $options ) = @_;
	my $fields =
	  $self->{'datastore'}->run_query( 'SELECT * FROM eav_fields WHERE NOT no_curate ORDER BY field_order,field',
		undef, { fetch => 'all_arrayref', slice => {} } );
	return if !@$fields;
	my @fieldnames = map { $_->{'field'} } @$fields;
	my $width      = $self->_get_field_width( \@fieldnames );
	my $field_name = ucfirst( $self->{'system'}->{'eav_fields'} // 'secondary metadata' );
	say qq(<fieldset style="float:left"><legend>$field_name</legend>);
	my $categories =
	  $self->{'datastore'}
	  ->run_query( 'SELECT DISTINCT category FROM eav_fields WHERE NOT no_curate ORDER BY category NULLS LAST',
		undef, { fetch => 'col_arrayref' } );
	say q(<div style="white-space:nowrap">);
	say q(<p class="comment">These fields are listed and stored separately<br />)
	  . q(as they may be infrequently populated.</p>);

	foreach my $cat (@$categories) {
		if ( @$categories > 1 && $categories->[0] ) {
			say $cat ? qq(<h3>$cat</h3>) : q(<h3>Other</h3>);
		}
		say q(<ul>);
		foreach my $field (@$fields) {
			if ( $field->{'category'} ) {
				next if !$cat || $cat ne $field->{'category'};
			} else {
				next if $cat;
			}
			my $thisfield = {
				type   => $field->{'value_format'},
				length => $field->{'length'},
				min    => $field->{'min_value'},
				max    => $field->{'max_value'},
				regex  => $field->{'value_regex'}
			};
			if ( defined $field->{'option_list'} ) {
				$thisfield->{'optlist'} = 1;
				$thisfield->{'option_list_values'} = [ split /;/x, $field->{'option_list'} ];
			}
			my $html5_args = $self->_get_html5_args(
				{
					field     => $field->{'field'},
					thisfield => $thisfield
				}
			);
			$field->{'length'} = $field->{'length'} // ( $field->{'value_format'} eq 'integer' ? 15 : 50 );
			( my $cleaned_name = $field->{'field'} ) =~ tr/_/ /;
			my ( $label, $title ) = $self->get_truncated_label( $cleaned_name, 25 );
			my $title_attribute = $title ? qq( title="$title") : q();
			my $for = qq( for="field_$field->{'field'}");
			print qq(<li><label$for class="form" style="width:${width}em"$title_attribute>);
			print $label;
			print ':';
			say q(</label>);
			my $methods = {
				optlist         => '_print_optlist',
				bool            => '_print_bool',
				long_text_field => '_print_long_text_field',
				default_field   => '_print_default_field'
			};

			foreach my $condition (qw( optlist bool long_text_field default_field)) {
				my $method = $methods->{$condition};
				my $args   = {
					newdata    => $newdata,
					field      => $field->{'field'},
					thisfield  => $thisfield,
					html5_args => $html5_args,
				};
				if ( $self->$method($args) ) {
					last;
				}
			}
			say $self->get_tooltip( $field->{'description'} ) if $field->{'description'};
			say q( <span class="no_date_picker" style="display:none">format: yyyy-mm-dd</span>)
			  if $field->{'value_format'} eq 'date';
		}
		say q(</ul>);
	}
	say q(</div></fieldset>);
	return;
}

sub _print_allele_designation_form_elements {
	my ( $self, $newdata ) = @_;
	my $locus_buffer;
	my $set_id = $self->get_set_id;
	my $q      = $self->{'cgi'};
	my $loci   = $self->{'datastore'}->get_loci( { set_id => $set_id } );
	@$loci = uniq @$loci;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my $schemes_with_display_order = any { defined $_->{'display_order'} } @$schemes;

	if ( @$loci <= 100 ) {
		foreach my $scheme (@$schemes) {
			$locus_buffer .= $self->_print_scheme_form_elements( $scheme->{'id'}, $newdata );
		}
		$locus_buffer .= $self->_print_scheme_form_elements( 0, $newdata );
	} elsif ($schemes_with_display_order) {
		foreach my $scheme (@$schemes) {
			next if !defined $scheme->{'display_order'};
			$locus_buffer .= $self->_print_scheme_form_elements( $scheme->{'id'}, $newdata );
		}
	} else {
		$locus_buffer .= '<p>Too many to display. You can batch add allele designations '
		  . "after entering isolate provenance data.</p>\n";
	}
	if (@$loci) {
		say q(<div id="scheme_loci_add">);
		say qq(<fieldset style="float:left"><legend>Allele&nbsp;designations</legend>\n$locus_buffer</fieldset>);
		say q(</div>);
	}
	return;
}

sub _print_scheme_form_elements {
	my ( $self, $scheme_id, $newdata ) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	my $loci;
	my $buffer = '';
	if ($scheme_id) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		$loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
		$buffer = @$loci ? qq(<h3 class="scheme" style="clear:both">$scheme_info->{'name'}</h3>\n) : '';
	} else {
		$loci = $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
		$buffer = @$loci ? qq(<h3 class="scheme" style="clear:both">Loci not in a scheme</h3>\n) : '';
	}
	foreach my $locus (@$loci) {
		my $cleaned_name = $self->clean_locus($locus);
		$buffer .= q(<dl class="profile">);
		$buffer .= qq(<dt>$cleaned_name</dt><dd style="min-height:initial">);
		if ( $self->{'locus_displayed'}->{$locus} ) {
			$buffer .= $q->textfield( -name => 'disabled_locus', -size => 10, -default => '-', -disabled );
		} else {
			$buffer .= $q->textfield(
				-name    => "locus:$locus",
				-id      => "locus:$locus",
				-size    => 10,
				-default => $newdata->{$locus}
			);
		}
		$buffer .= q(</dd></dl>);
		$self->{'locus_displayed'}->{$locus} = 1;
	}
	return $buffer;
}

sub get_title {
	return 'Add new isolate';
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery jQuery.multiselect modernizr noCache);
	$self->set_level1_breadcrumbs;
	return;
}
1;
