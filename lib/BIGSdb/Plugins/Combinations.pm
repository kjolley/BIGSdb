#Combinations.pm - Unique combinations plugin for BIGSdb
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
package BIGSdb::Plugins::Combinations;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use BIGSdb::Constants qw(:interface);
use List::MoreUtils qw(uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use constant MAX_FIELDS => 100;

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 0 };
	return;
}

sub get_initiation_values {
	return { 'jQuery.jstree' => 1 };
}

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'Unique Combinations',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Determine frequencies of unique field combinations',
		category    => 'Breakdown',
		buttontext  => 'Combinations',
		menutext    => 'Unique combinations',
		module      => 'Combinations',
		url         => "$self->{'config'}->{'doclink'}/data_analysis/unique_combinations.html",
		version     => '1.4.2',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		input       => 'query',
		help        => 'tooltips',
		requires    => 'js_tree,offline_jobs',
		order       => 15
	);
	return \%att;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Frequencies of field combinations</h1>);
	return if $self->has_set_changed;
	if ( !$q->param('submit') ) {
		$self->_print_interface;
		return;
	}
	my $selected_fields = $self->get_selected_fields;
	if ( !@$selected_fields ) {
		$self->print_bad_status( { message => q(No fields have been selected!) } );
		$self->_print_interface;
		return;
	} elsif ( @$selected_fields > MAX_FIELDS ) {
		my $limit          = MAX_FIELDS;
		my $selected_count = @$selected_fields;
		$self->print_bad_status(
			{ message => qq(This analysis is limited to $limit fields. You have selected $selected_count!) } );
		$self->_print_interface;
		return;
	}
	my $ids = $self->filter_list_to_ids( [ $q->multi_param('isolate_id') ] );
	my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
	push @$ids, @$pasted_cleaned_ids;
	@$ids = uniq @$ids;
	if ( !@$ids ) {
		$self->print_bad_status( { message => q(No valid ids have been selected!) } );
		$self->_print_interface;
		return;
	}
	if (@$invalid_ids) {
		local $" = ', ';
		$self->print_bad_status(
			{ message => qq(The following isolates in your pasted list are invalid: @$invalid_ids.) } );
		$self->_print_interface;
		return;
	}
	my $params = {};
	local $" = '||';
	$params->{'selected_fields'} = "@$selected_fields";
	delete $params->{'isolate_paste_list'};
	my $att       = $self->get_attributes;
	my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
	my $job_id    = $self->{'jobManager'}->add_job(
		{
			dbase_config => $self->{'instance'},
			ip_address   => $q->remote_host,
			module       => $att->{'module'},
			priority     => $att->{'priority'},
			parameters   => $params,
			username     => $self->{'username'},
			email        => $user_info->{'email'},
			isolates     => $ids
		}
	);
	say $self->get_job_redirect($job_id);
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->{'exit'} = 0;

	#Terminate cleanly on kill signals
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3;
	my $ids = $self->{'jobManager'}->get_job_isolates($job_id);
	$self->{'datastore'}->create_temp_list_table_from_array( 'integer', $ids, { table => 'temp_list' } );
	my @fields = split /\|\|/x, $params->{'selected_fields'};
	my $header = [];
	my %schemes;
	foreach (@fields) {
		my $field = $_;
		if ( $field =~ /^s_(\d+)_f/x ) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($1);
			$field .= " ($scheme_info->{'name'})"
			  if $scheme_info->{'name'};
			$schemes{$1} = 1;
		}
		$field =~ s/^(s_\d+_l|s_\d+_f|f|l|c|eav)_//gx;    #strip off prefix for header row
		$field =~ s/^meta_.+?://x;
		$field =~ s/^.*___//x;
		$field =~ tr/_/ / if !$self->{'datastore'}->is_locus($field);
		push @$header, $field;
	}
	my $scheme_field_pos;
	foreach my $scheme_id ( keys %schemes ) {
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		my $i             = 0;
		foreach my $field (@$scheme_fields) {
			$scheme_field_pos->{$scheme_id}->{$field} = $i;
			$i++;
		}
	}
	my $qry = "SELECT * FROM $self->{'system'}->{'view'} WHERE id IN (SELECT value FROM temp_list)";
	my $dataset = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	my $total;
	my $values   = {};
	my $progress = 0;
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Checking values' } );
	foreach my $data (@$dataset) {
		$total++;
		my $allele_ids = $self->{'datastore'}->get_all_allele_ids( $data->{'id'} );
		foreach my $field (@fields) {
			if ( $field =~ /^f_(.*)/x ) {
				my $prov_field = $1;
				$values->{ $data->{'id'} }->{$field} = $self->_get_field_value( $prov_field, $data );
				next;
			}
			if ( $field =~ /^eav_(.*)/x ) {
				my $eav_field = $1;
				$values->{ $data->{'id'} }->{$field} =
				  $self->{'datastore'}->get_eav_field_value( $data->{'id'}, $eav_field ) // q(-);
			}
			if ( $field =~ /^(s_\d+_l_|l_)(.*)/x ) {
				my $locus = $2;
				if ( defined $allele_ids->{$locus} && $allele_ids->{$locus} ne '' ) {
					my @alleles = sort @{ $allele_ids->{$locus} };
					local $" = q(; );
					$values->{ $data->{'id'} }->{$field} = qq(@alleles);
				} else {
					$values->{ $data->{'id'} }->{$field} = q(-);
				}
				next;
			}
			if ( $field =~ /^s_(\d+)_f_(.*)/x ) {
				my $scheme_id    = $1;
				my $scheme_field = lc($2);
				my $scheme_field_values =
				  $self->get_scheme_field_values(
					{ isolate_id => $data->{'id'}, scheme_id => $scheme_id, field => $scheme_field } );
				foreach my $value (@$scheme_field_values) {
					$value //= '-';
				}
				if (@$scheme_field_values) {
					my @field_values = sort @{$scheme_field_values};
					local $" = q(; );
					$values->{ $data->{'id'} }->{$field} = qq(@field_values);
				} else {
					$values->{ $data->{'id'} }->{$field} = q(-);
				}
				next;
			}
			if ( $field =~ /^c_(.*)/x ) {
				my $value = $self->{'datastore'}->get_composite_value( $data->{'id'}, $1, $data );
				$values->{ $data->{'id'} }->{$field} = $value;
			}
		}
		my $new_progress = int( $total / @$ids * 70 );

		#Only update when progress percentage changes when rounded to nearest 1 percent
		if ( $new_progress > $progress ) {
			$progress = $new_progress;
			$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $progress } );
			$self->{'db'}->commit;    #prevent idle in transaction table locks
		}
		last if $self->{'exit'};
	}
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Counting combinations' } );
	my $combs = $self->_calculate_combinations( \@fields, $values );
	$self->_output_results( $job_id, $header, $combs, $total );
	return;
}

sub _output_results {
	my ( $self, $job_id, $header, $combs, $total ) = @_;
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Creating text file', percent_complete => 80 } );
	my $filename  = "$job_id.txt";
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$filename";
	open( my $fh, '>:encoding(utf8)', $full_path )
	  or $logger->error("Can't open temp file $filename for writing");
	foreach my $heading (@$header) {
		my $cleaned_text = $heading;
		if ( $self->{'datastore'}->is_locus($heading) ) {
			$cleaned_text = $self->clean_locus( $heading, { text_output => 1, no_common_name => 1 } );
		}
		print $fh qq($cleaned_text\t);
	}
	say $fh qq(Frequency\tPercentage);
	my $td = 1;
	foreach ( sort { $combs->{$b} <=> $combs->{$a} } keys %$combs ) {
		my @values = split /_\|_/x, $_;
		my $pc = BIGSdb::Utils::decimal_place( 100 * $combs->{$_} / $total, 2 );
		local $" = q(</td><td>);
		local $" = "\t";
		say $fh qq(@values\t$combs->{$_}\t$pc);
		$td = $td == 1 ? 2 : 1;
	}
	close $fh;
	my $msg = q(<p>Number of unique combinations: ) . ( keys %$combs ) . q(</p>);
	$self->{'jobManager'}->update_job_status( $job_id, { message_html => $msg } );
	$self->{'jobManager'}->update_job_output(
		$job_id,
		{
			filename      => $filename,
			description   => '01_Combinations table (text)',
			compress      => 1,
			keep_original => 1                                 #Original needed to generate Excel file
		}
	);
	$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Creating Excel file', percent_complete => 90 } );
	my $excel_file = BIGSdb::Utils::text2excel(
		$full_path,
		{
			worksheet   => 'Combinations',
			tmp_dir     => $self->{'config'}->{'secure_tmp_dir'},
			text_fields => $self->{'system'}->{'labelfield'}
		}
	);
	if ( -e $excel_file ) {
		$self->{'jobManager'}->update_job_output( $job_id,
			{ filename => "$job_id.xlsx", description => '02_Combinations table (Excel)', compress => 1 } );
	}
	unlink $filename if -e "$filename.gz";
	return;
}

sub _get_field_value {
	my ( $self, $field, $data ) = @_;
	my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
	if ( defined $metaset ) {
		my $value = $self->{'datastore'}->get_metadata_value( $data->{'id'}, $metaset, $metafield );
		$value = '-' if $value eq '';
		return $value;
	} elsif ( $field eq 'aliases' ) {
		my $aliases = $self->{'datastore'}->get_isolate_aliases( $data->{'id'} );
		local $" = '; ';
		my $value = @$aliases ? "@$aliases" : '-';
		return $value;
	} elsif ( $field =~ /(.*)___(.*)/x ) {
		my ( $isolate_field, $attribute ) = ( $1, $2 );
		my $value = $self->{'datastore'}->run_query(
			'SELECT value FROM isolate_value_extended_attributes WHERE '
			  . '(isolate_field,attribute,field_value)=(?,?,?)',
			[ $isolate_field, $attribute, $data->{$isolate_field} ],
			{ cache => 'Combinations::extended_values' }
		);
		$value = '-' if !defined $value || $value eq '';
		return $value;
	} else {
		my $value = ( defined $data->{lc $field} && $data->{lc $field} ne '' ) ? $data->{lc $field} : '-';
		return $value;
	}
}

sub _print_interface {
	my ($self) = @_;
	say q(<div class="box" id="queryform"><p>Here you can determine the frequencies of unique field )
	  . q(combinations in the dataset. Please select your combination of fields. Select loci either )
	  . q(from the locus list or by selecting one or more schemes to include all loci (and/or fields) )
	  . q(from a scheme.</p>);
	say q(<div class="scrollable">);
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $selected_ids;
	if ( $q->param('isolate_id') ) {
		my @ids = $q->multi_param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query_file ) {
		my $qry_ref = $self->get_query($query_file);
		$selected_ids = $self->get_ids_from_query($qry_ref);
	} else {
		$selected_ids = [];
	}
	my $set_id = $self->get_set_id;
	say $q->start_form;
	$self->print_seqbin_isolate_fieldset( { use_all => 1, selected_ids => $selected_ids, isolate_paste_list => 1 } );
	$self->print_isolate_fields_fieldset( { extended_attributes => 1 } );
	$self->print_eav_fields_fieldset;
	$self->print_composite_fields_fieldset;
	$self->print_isolates_locus_fieldset;
	$self->print_scheme_fieldset( { fields_or_loci => 1 } );
	$self->print_action_fieldset( { no_reset => 1 } );
	say q(<div style="clear:both"></div>);
	$q->param( set_id => $set_id );
	say $q->hidden($_) foreach qw (db page name set_id);
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub _calculate_combinations {
	my ( $self, $fields, $values ) = @_;
	my $combs = {};
	foreach my $isolate_id ( keys %$values ) {
		my @keys;
		my @fields_to_check = @$fields;
		my $current_field   = shift @fields_to_check;
		$self->_append_keys( \@keys, \@fields_to_check, $current_field, $values->{$isolate_id} );
		$combs->{$_}++ foreach @keys;
	}
	return $combs;
}

sub _append_keys {
	my ( $self, $keys, $fields_to_check, $current_field, $values ) = @_;
	my $value = $values->{$current_field};
	if ( !@$keys ) {
		push @$keys, $value;
	} else {
		foreach my $i ( 0 .. @$keys - 1 ) {
			my $existing_value = $keys->[$i];
			my $j              = 0;
			my %used;
			next if $used{$value};
			if ($j) {
				my $new_value = "$existing_value\_|_$value";
				push @$keys, $new_value;
			} else {
				$keys->[$i] .= "_|_$value";
				$j = 1;
			}
			$used{$value} = 1;
		}
	}
	return if !@$fields_to_check;
	$current_field = shift @$fields_to_check;
	$self->_append_keys( $keys, $fields_to_check, $current_field, $values );
	return;
}
1;
