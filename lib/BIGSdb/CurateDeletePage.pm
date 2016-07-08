#Written by Keith Jolley
#Copyright (c) 2010-2016, University of Oxford
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
package BIGSdb::CurateDeletePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Constants qw(DATABANKS);

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $table = $q->param('table') || '';
	my $record_name = $self->get_record_name($table) // q();
	say qq(<h1>Delete $record_name</h1>);
	if (   !$self->{'datastore'}->is_table($table)
		&& !( $table eq 'samples' && @{ $self->{'xmlHandler'}->get_sample_field_list } ) )
	{
		say qq(<div class="box" id="statusbad"><p>Table $table does not exist!</p></div>);
		return;
	}
	if ( $table eq 'profiles' ) {
		my $scheme_id = $q->param('scheme_id');
		if ( !BIGSdb::Utils::is_int($scheme_id) ) {
			say q(<div class="box" id="statusbad">Invalid scheme id.</p></div>);
			return;
		}
		my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		if ( !$scheme_info ) {
			say q(<div class="box" id="statusbad">Scheme does not exist.</p></div>);
			return;
		}
	}
	if ( !$self->can_modify_table($table) ) {
		if ( $table eq 'sequences' && $q->param('locus') ) {
			my $locus = $q->param('locus');
			say q(<div class="box" id="statusbad"><p>Your user account is not allowed to delete )
			  . qq($locus sequences from the database.</p></div>);
		} else {
			say q(<div class="box" id="statusbad"><p>Your user account is not allowed to delete )
			  . qq(records from the $table table.</p></div>);
		}
		return;
	} elsif ( ( $table eq 'sequence_refs' || $table eq 'accession' ) && $q->param('locus') ) {
		my $locus = $q->param('locus');
		if (   !$self->is_admin
			&& !$self->{'datastore'}->is_allowed_to_modify_locus_sequences( $locus, $self->get_curator_id ) )
		{
			say q(<div class="box" id="statusbad"><p>Your user account is not allowed to delete )
			  . ( $table eq 'sequence_refs' ? 'references' : 'accession numbers' )
			  . q( for this locus.</p></div>);
			return;
		}
	}
	$self->_display_record($table);
	return;
}

sub _show_modification_warning {
	my ( $self, $table ) = @_;
	my $q = $self->{'cgi'};
	if (   ( $table eq 'scheme_fields' || $table eq 'scheme_members' )
		&& $self->{'system'}->{'dbtype'} eq 'sequences'
		&& !$q->param('sent') )
	{
		say q(<div class="box" id="warning"><p>Please be aware that any modifications to the structure of )
		  . q(this scheme will result in the removal of all data from it. This is done to ensure data integrity. )
		  . q(This does not affect allele designations, but any profiles will have to be reloaded.</p></div>);
	}
	return;
}

sub _get_fields_and_values {
	my ( $self, $table ) = @_;
	my $q = $self->{'cgi'};
	my ( @query_fields, @query_values, $err );
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my %primary_keys;
	foreach my $att (@$attributes) {
		if ( $att->{'primary_key'} ) {
			my $value = $q->param( $att->{'name'} ) // '';
			push @query_fields, $att->{'name'};
			push @query_values, $value;
			$primary_keys{ $att->{'name'} } = 1 if defined $q->param( $att->{'name'} );
			if ( $att->{'type'} eq 'int' && !BIGSdb::Utils::is_int( $q->param( $att->{'name'} ) ) ) {
				$err = qq(Field $att->{'name'} must be an integer.);
			}
		}
	}
	if ( @query_fields != keys %primary_keys ) {
		$err = q(Insufficient identifying attributes sent.);
	}
	return ( \@query_fields, \@query_values, $err );
}

sub get_display_values {
	my ( $self, $table, $primary_key, $data, $att ) = @_;
	my $q = $self->{'cgi'};
	my ( $field, $value );
	( my $field_name = $att->{'name'} ) =~ tr/_/ /;
	if ( $table eq 'profiles' && $att->{'name'} eq 'profile_id' ) {
		$field = $primary_key;
	} else {
		$field = $field_name;
	}
	if ( $att->{'type'} eq 'bool' ) {
		$value = $data->{ $att->{'name'} } ? 'true' : 'false';
	} else {
		$value = $data->{ $att->{'name'} };
	}
	$value = BIGSdb::Utils::escape_html($value);
	if ( $att->{'name'} =~ /sequence$/x && $att->{'name'} ne 'coding_sequence' ) {
		$value //= ' ';
		my $value_length = length($value);
		if ( $value_length > 5000 ) {
			my $seq = BIGSdb::Utils::truncate_seq( \$value, 30 );
			return ( $field,
				qq(<span class="seq">$seq</span><br />Sequence is $value_length characters (too long to display)) );
		} else {
			my $seq = BIGSdb::Utils::split_line($value) || '';
			return ( $field, qq(<span class="seq">$seq</span>) );
		}
	}
	if ( $att->{'name'} eq 'curator' or $att->{'name'} eq 'sender' ) {
		my $user = $self->{'datastore'}->get_user_info($value);
		$user->{'first_name'} //= '';
		$user->{'surname'}    //= '';
		return ( $field, qq($user->{'first_name'} $user->{'surname'}) );
	}
	if ( $att->{'name'} eq 'scheme_id' ) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info($value);
		return ( $field, qq[$value) $scheme_info->{'description'}] );
	}
	if ( $att->{'foreign_key'} && $att->{'labels'} ) {
		my @fields_to_query;
		my @values = split /\|/x, $att->{'labels'};
		foreach my $value (@values) {
			if ( $value =~ /\$(.*)/x ) {
				push @fields_to_query, $1;
			}
		}
		local $" = ',';
		my $labels = $self->{'datastore'}->run_query( "SELECT @fields_to_query FROM $att->{'foreign_key'} WHERE id=?",
			$value, { fetch => 'row_hashref' } );
		my $label_value = $att->{'labels'};
		foreach my $field (@fields_to_query) {
			$label_value =~ s/$field/$labels->{lc $field}/x;
		}
		$label_value =~ s/[\|\$]//gx;
		return ( $field, $label_value );
	}
	if ( $att->{'name'} eq 'locus' ) {
		$value = $self->clean_locus($value);
		return ( $field, $value // q(&nbsp;) );
	}
	$value = '&nbsp;' if !defined $value || $value eq '';
	return ( $field, $value // q(&nbsp;) );
}

sub _display_record {
	my ( $self, $table ) = @_;
	my $q = $self->{'cgi'};
	$self->_show_modification_warning($table);
	my $icon       = $self->get_form_icon( $table, 'trash' );
	my $buffer     = $icon;
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my ( $query_fields, $query_values, $err ) = $self->_get_fields_and_values($table);
	if ($err) {
		say qq(<div class="box" id="statusbad"><p>$err</p></div>);
		return;
	}
	local $" = q(,);
	my @placeholders = (q(?)) x @$query_fields;
	my $qry          = qq(SELECT * FROM $table WHERE (@$query_fields)=(@placeholders));
	my $data         = $self->{'datastore'}->run_query( $qry, $query_values, { fetch => 'row_hashref' } );
	if ( !$data ) {
		say q(<div class="box" id="statusbad"><p>Selected record does not exist.</p></div>);
		return;
	}
	$buffer .= $q->start_form;
	$buffer .= q(<div class="box" id="resultspanel">);
	$buffer .= q(<div class="scrollable">);
	my %retire_table = map { $_ => 1 } qw(sequences);
	$buffer .= q(<p>You have chosen to delete the following record.);
	if ( $retire_table{$table} ) {
		$buffer .= q( Select 'Delete and Retire' to prevent the identifier being reused.);
	}
	$buffer .= q(</p>);
	$buffer .= $q->hidden($_) foreach qw(page db table);
	$buffer .= $q->hidden( sent => 1 );
	foreach my $att (@$attributes) {
		if ( $att->{'primary_key'} ) {
			$buffer .= $q->hidden( $att->{'name'}, $data->{ $att->{'name'} } );
		}
	}
	$buffer .= q(<div id="record"><dl class="data">);
	my $primary_key;
	if ( $table eq 'profiles' ) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $q->param('scheme_id'), { get_pk => 1 } );
		$primary_key = $scheme_info->{'primary_key'};
	}
	foreach my $att (@$attributes) {
		next if $att->{'hide_query'} eq 'yes';
		my ( $field, $value ) = $self->get_display_values( $table, $primary_key, $data, $att );
		$buffer .= qq(<dt>$field</dt><dd>$value</dd>);
		if ( $table eq 'profiles' && $att->{'name'} eq 'profile_id' ) {
			my $scheme_id = $q->param('scheme_id');
			$buffer .= $self->_get_profile_fields( $scheme_id, $primary_key, $data->{'profile_id'} );
		}
	}
	if    ( $table eq 'sequences' )    { $buffer .= $self->_get_extra_sequences_fields($data) }
	elsif ( $table eq 'sequence_bin' ) { $buffer .= $self->_get_extra_seqbin_fields($data) }
	$buffer .= q(</dl></div></div>);
	if ( $table eq 'allele_designations' ) {
		$buffer .= q(<div><fieldset><legend>Options</legend><ul><li>);
		if ( $self->can_modify_table('allele_sequences') ) {
			$buffer .= $q->checkbox(
				-name  => 'delete_tags',
				-label => 'Also delete all sequence tags for this isolate/locus combination'
			);
			$buffer .= qq(</li>\n);
		}
		$buffer .= qq(</ul></fieldset></div>\n);
	}
	if ( $retire_table{$table} ) {
		$buffer .= $self->print_action_fieldset(
			{
				submit_label  => 'Delete',
				submit2       => 'delete_and_retire',
				submit2_label => 'Delete and Retire',
				no_reset      => 1,
				get_only      => 1
			}
		);
	} else {
		$buffer .= $self->print_action_fieldset( { submit_label => 'Delete', no_reset => 1, get_only => 1 } );
	}
	$buffer .= q(</div>);
	$buffer .= $q->end_form;
	if ( $q->param('sent') ) {
		$buffer .=
		  $self->_delete( $table, $data, $query_fields, $query_values,
			{ retire => $q->param('delete_and_retire') ? 1 : 0 } )
		  || '';
		return if $q->param('submit') || $q->param('delete_and_retire');
	}
	say $buffer;
	return;
}

sub _delete {
	my ( $self, $table, $data, $query_fields, $query_values, $options ) = @_;
	my $q = $self->{'cgi'};
	my $buffer;
	my $proceed = 1;
	my $nogo_buffer;
	if ( $table eq 'users' ) {
		$self->_delete_user( $data, \$nogo_buffer, \$proceed );
	}
	my %dont_check = map { $_ => 1 } qw(composite_fields schemes classification_schemes);

	#Check if record is a foreign key in another table
	if ( $proceed && !$dont_check{$table} ) {
		my %tables_to_check = $self->_get_tables_which_reference_table($table);
		foreach my $table_to_check ( keys %tables_to_check ) {

			#cascade deletion of locus
			next
			  if $table eq 'loci' && any { $table_to_check eq $_ }
			qw (locus_aliases locus_descriptions allele_designations
			  allele_sequences locus_curators client_dbase_loci locus_extended_attributes);

			#cascade deletion of user
			next if $table eq 'users' && any { $table_to_check eq $_ } qw ( curator_permissions user_group_members);

			#cascade deletion of sequence bin records
			next if $table eq 'sequence_bin' && $table_to_check eq 'allele_sequences';

			#cascade deletion of scheme group
			next
			  if $table eq 'scheme_groups' && any { $table_to_check eq $_ }
			qw ( scheme_group_group_members scheme_group_scheme_members );
			my $num =
			  $self->{'datastore'}
			  ->run_query( "SELECT COUNT(*) FROM $table_to_check WHERE $tables_to_check{$table_to_check} =?",
				$data->{'id'} );
			if ($num) {
				my $record_name = $self->get_record_name($table);
				my $plural = $num > 1 ? 's' : '';
				$data->{'id'} =~ s/'/\\'/gx;
				$nogo_buffer .= qq($record_name '$data->{'id'}' is referenced by $num record$plural in table )
				  . qq('$table_to_check' - cannot delete!<br />);
				$proceed = 0;
			}
		}
	}

	#special case to check that allele sequence is not used in a profile (profile database)
	if ( $proceed && $table eq 'sequences' && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $num = $self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM profile_members WHERE (locus,allele_id)=(?,?)',
			[ $data->{'locus'}, $data->{'allele_id'} ] );
		if ($num) {
			my $plural = $num > 1 ? 's' : '';
			$nogo_buffer .= qq(Sequence $data->{'locus'}-$data->{'allele_id'} is referenced by )
			  . qq($num allelic profile$plural - can not delete!<br />);
			$proceed = 0;
		}
	} elsif ( $proceed
		&& $table eq 'allele_designations'
		&& !$self->is_allowed_to_view_isolate( $data->{'isolate_id'} ) )
	{
		$nogo_buffer .= q(Your user account is not allowed to delete allele designations for this isolate.<br />);
		$proceed = 0;
	}
	if ( !$proceed ) {
		say qq(<div class="box" id="statusbad"><p>$nogo_buffer</p><p>)
		  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>);
		return;
	}
	$buffer .= "</p>\n";
	if ( ( $q->param('submit') || $q->param('delete_and_retire') ) && $proceed ) {
		$self->_confirm( $table, $data, $query_fields, $query_values, $options );
		return;
	}
	return $buffer;
}

sub _delete_user {
	my ( $self, $data, $nogo_buffer_ref, $proceed_ref ) = @_;

	#Don't delete yourself
	if ( defined $data->{'id'} && $data->{'id'} == $self->get_curator_id ) {
		$$nogo_buffer_ref .= q(It is not a good idea to remove yourself as a curator!  If you really wish to )
		  . q(do this, you'll need to do it from another curator account.<br />);
		$$proceed_ref = 0;
	}

	#Don't delete curators or admins unless you are an admin yourself
	elsif ( defined $data->{'status'} && $data->{'status'} ne 'user' && !$self->is_admin ) {
		$$nogo_buffer_ref .= q(Only administrators can delete users with curator or admin status!<br />);
		$$proceed_ref = 0;
	}
	if ($$proceed_ref) {
		my $sample_fields = $self->{'xmlHandler'}->get_sample_field_list;
		foreach my $table ( $self->{'datastore'}->get_tables_with_curator ) {
			next if !@$sample_fields && $table eq 'samples';
			my $num = $self->{'datastore'}->run_query( "SELECT COUNT(*) FROM $table WHERE curator=?", $data->{'id'} );
			my $num_senders;
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
				$num_senders =
				  $self->{'datastore'}->run_query( "SELECT COUNT(*) FROM $table WHERE sender=?", $data->{'id'} );
			}
			if ( $num || $num_senders ) {
				if ($num) {
					my $plural = $num > 1 ? 's' : '';
					$$nogo_buffer_ref .=
					    qq(User '$data->{'id'}' is the curator for $num record$plural )
					  . qq(in table '$table' - can not delete!<br />)
					  if $num;
				}
				if ($num_senders) {
					my $plural = $num_senders > 1 ? 's' : '';
					$$nogo_buffer_ref .=
					    qq(User '$data->{'id'}' is the sender for $num_senders record$plural )
					  . qq(in table '$table' - can not delete!<br />)
					  if $num_senders;
				}
				$$proceed_ref = 0;
			}
		}
	}
	return;
}

sub _confirm {
	my ( $self, $table, $data, $query_fields, $query_values, $options ) = @_;
	my $q = $self->{'cgi'};
	local $" = q(,);
	my @placeholders = (q(?)) x @$query_fields;
	my $qry          = qq(DELETE FROM $table WHERE (@$query_fields)=(@placeholders));
	my @queries      = ( { statement => $qry, arguments => $query_values } );
	if ( $table eq 'allele_designations' && $self->can_modify_table('allele_sequences') && $q->param('delete_tags') ) {
		push @queries,
		  {
			statement => q[DELETE FROM allele_sequences WHERE seqbin_id IN ]
			  . qq[(SELECT id FROM sequence_bin WHERE $query_fields->[0]=?) AND $query_fields->[1]=?],
			arguments => [ $query_values->[0], $query_values->[1] ]
		  };
	}
	if ( $options->{'retire'} ) {
		my $curator_id = $self->get_curator_id;
		if ( $table eq 'sequences' ) {
			push @queries,
			  {
				statement => q(INSERT INTO retired_allele_ids (locus,allele_id,curator,datestamp) VALUES (?,?,?,?)),
				arguments => [ @$query_values, $curator_id, 'now' ]
			  };
		}
	}
	eval {
		foreach my $qry (@queries)
		{
			$self->{'db'}->do( $qry->{'statement'}, undef, @{ $qry->{'arguments'} } );
		}
		if ( ( $table eq 'scheme_members' || $table eq 'scheme_fields' )
			&& $self->{'system'}->{'dbtype'} eq 'sequences' )
		{
			$self->remove_profile_data( $data->{'scheme_id'} );
		}
	};
	if ($@) {
		my $err = $@;
		$logger->error($err);
		say q(<div class="box" id="statusbad"><p>Delete failed - transaction cancelled - )
		  . q(no records have been touched.</p>);
		say qq(<p>Failed SQL: $qry</p>);
		say qq(<p>Error message: $err</p></div>);
		$self->{'db'}->rollback;
		return;
	}
	my $record_name = $self->get_record_name($table);
	$self->{'db'}->commit && say qq(<div class="box" id="resultsheader"><p>$record_name deleted!</p>);
	if ( $table eq 'composite_fields' ) {
		say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . q(page=compositeQuery">Query another</a>);
	} elsif ( $table eq 'profiles' ) {
		my $scheme_id = $q->param('scheme_id');
		say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;)
		  . qq(scheme_id=$scheme_id">Query another</a>);
	} else {
		say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=tableQuery&amp;table=$table">Query another</a>);
	}
	say qq( | <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Back to main page</a></p></div>);
	$logger->debug("Deleted record: $qry");
	if ( $table eq 'allele_designations' ) {
		my $deltags = $q->param('delete_tags') ? "<br />$data->{'locus'}: sequence tag(s) deleted" : '';
		$self->update_history( $data->{'isolate_id'},
			qq($data->{'locus'}: designation '$data->{'allele_id'}' deleted$deltags" ) );
	} elsif ( $table eq 'sequences' ) {
		$self->{'datastore'}->mark_cache_stale;
		$self->update_blast_caches;
	}
	return;
}

sub _get_extra_sequences_fields {
	my ( $self, $data ) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = '';
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		my $flags = $self->{'datastore'}->get_allele_flags( $q->param('locus'), $q->param('allele_id') );
		local $" = '</a> <a class="seqflag_tooltip">';
		if (@$flags) {
			$buffer .= qq(<dt>flags&nbsp;</dt><dd><a class="seqflag_tooltip">@$flags</a></dd>\n);
		}
	}
	foreach my $databank (DATABANKS) {
		my $accessions = $self->{'datastore'}->run_query(
			'SELECT databank_id FROM accession WHERE (locus,allele_id,databank)=(?,?,?) ORDER BY databank_id',
			[ $q->param('locus'), $q->param('allele_id'), $databank ],
			{ fetch => 'col_arrayref' }
		);
		foreach my $accession (@$accessions) {
			if ( $databank eq 'Genbank' ) {
				$accession = qq(<a href="http://www.ncbi.nlm.nih.gov/nuccore/$accession">$accession</a>);
			} elsif ( $databank eq 'ENA' ) {
				$accession = qq(<a href="http://www.ebi.ac.uk/ena/data/view/$accession">$accession</a>);
			}
			$buffer .= qq(<dt>$databank&nbsp;</dt><dd>$accession</dd>\n);
		}
	}
	my $pubmed_list = $self->{'datastore'}->run_query(
		'SELECT pubmed_id FROM sequence_refs WHERE (locus,allele_id)=(?,?) ORDER BY pubmed_id',
		[ $q->param('locus'), $q->param('allele_id') ],
		{ fetch => 'col_arrayref' }
	);
	my $citations =
	  $self->{'datastore'}->get_citation_hash( $pubmed_list, { formatted => 1, all_authors => 1, link_pubmed => 1 } );
	foreach my $pmid (@$pubmed_list) {
		$buffer .= qq(<dt>reference&nbsp;</dt><dd>$citations->{$pmid}</dd>\n);
	}
	my $extended_attributes =
	  $self->{'datastore'}->get_allele_extended_attributes( $q->param('locus'), $q->param('allele_id') );
	foreach my $ext (@$extended_attributes) {
		my $cleaned_field = $ext->{'field'};
		$cleaned_field =~ tr/_/ /;
		if ( $cleaned_field =~ /sequence$/x ) {
			my $seq = BIGSdb::Utils::split_line( $ext->{'value'} );
			$buffer .= qq(<dt>$cleaned_field&nbsp;</dt><dd class="seq">$seq</dd>\n);
		} else {
			$buffer .= qq(<dt>$cleaned_field&nbsp;</dt><dd>$ext->{'value'}</dd>\n);
		}
	}
	return $buffer;
}

sub _get_extra_seqbin_fields {
	my ( $self, $data ) = @_;
	my $q = $self->{'cgi'};
	my $attributes =
	  $self->{'datastore'}->run_query( 'SELECT key,value FROM sequence_attribute_values WHERE seqbin_id=? ORDER BY key',
		$data->{'id'}, { fetch => 'all_arrayref', slice => {} } );
	my $buffer = '';
	foreach my $att (@$attributes) {
		( my $cleaned_field = $att->{'key'} ) =~ tr/_/ /;
		$buffer .= qq(<dt>$cleaned_field</dt><dd>$att->{'value'}</dd>\n);
	}
	return $buffer;
}

sub _get_profile_fields {
	my ( $self, $scheme_id, $primary_key, $profile_id ) = @_;
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $buffer;
	foreach my $locus (@$loci) {
		my $mapped = $self->clean_locus( $locus, { no_common_name => 1 } );
		$buffer .= qq(<dt>$mapped&nbsp;</dt>);
		my $allele_id =
		  $self->{'datastore'}
		  ->run_query( 'SELECT allele_id FROM profile_members WHERE (scheme_id,locus,profile_id)=(?,?,?)',
			[ $scheme_id, $locus, $profile_id ] );
		$buffer .= qq(<dd>$allele_id</dd>\n);
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$scheme_fields) {
		next if $field eq $primary_key;
		$buffer .= qq(<dt>$field&nbsp;</dt>);
		my $value =
		  $self->{'datastore'}
		  ->run_query( 'SELECT value FROM profile_fields WHERE (scheme_id,scheme_field,profile_id)=(?,?,?)',
			[ $scheme_id, $field, $profile_id ] );
		$buffer .= defined $value ? qq(<dd>$value</dd>\n) : qq(<dd>&nbsp;</dd>\n);
	}
	return $buffer;
}

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	my $type  = $self->get_record_name($table) || 'record';
	return "Delete $type - $desc";
}

sub _get_tables_which_reference_table {
	my ( $self, $table ) = @_;
	my %tables;
	foreach my $table2 ( $self->{'datastore'}->get_tables ) {
		if (
			!(
				$self->{'system'}->{'dbtype'} eq 'isolates'
				&& ( $table2 eq $self->{'system'}->{'view'} || $table2 eq 'isolates' )
			)
			&& $table2 ne $table
		  )
		{
			my $attributes = $self->{'datastore'}->get_table_field_attributes($table2);
			if ( ref $attributes eq 'ARRAY' ) {
				foreach my $att (@$attributes) {
					if (   ( $att->{'foreign_key'} && $att->{'foreign_key'} eq $table )
						|| ( $table eq 'users' && $att->{'name'} eq 'sender' ) )
					{
						$tables{$table2} = $att->{'name'};
					}
				}
			}
		}
	}
	return %tables;
}
1;
