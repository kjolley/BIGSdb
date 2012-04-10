#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
package BIGSdb::CurateBatchAddPage;
use strict;
use warnings;
use List::MoreUtils qw(any none uniq);
use parent qw(BIGSdb::CurateAddPage);
use Log::Log4perl qw(get_logger);
use BIGSdb::Page qw(ALLELE_FLAGS);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $table         = $q->param('table') || '';
	my $cleaned_table = $table;
	my $locus         = $q->param('locus');
	$cleaned_table =~ tr/_/ /;
	if ( !$self->{'datastore'}->is_table($table) && !( $table eq 'samples' && @{ $self->{'xmlHandler'}->get_sample_field_list } ) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Table $table does not exist!</p></div>\n";
		return;
	}
	if ( $table eq 'sequences' && $locus ) {
		if ( !$self->{'datastore'}->is_locus($locus) ) {
			print "<div class=\"box\" id=\"statusbad\"><p>Locus $locus does not exist!</p></div>\n";
			return;
		}
		my $cleaned_locus = $self->clean_locus($locus);
		print "<h1>Batch insert $cleaned_locus sequences</h1>\n";
	} else {
		print "<h1>Batch insert $cleaned_table</h1>\n";
	}
	if ( !$self->can_modify_table($table) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to add records to the $table table.</p></div>\n";
		return;
	}
	if ( $table eq 'pending_allele_designations' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>You can not use this interface to add pending allele designations.</p></div>\n";
		return;
	} elsif ( $table eq 'sequence_bin' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>You can not use this interface to add sequences to the bin.</p></div>\n";
		return;
	} elsif ( $table eq 'allele_sequences' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Tag allele sequences using the scan interface.</p></div>\n";
		return;
	}
	if (   ( $table eq 'scheme_fields' || $table eq 'scheme_members' )
		&& $self->{'system'}->{'dbtype'} eq 'sequences'
		&& !$q->param('data')
		&& !$q->param('checked_buffer') )
	{
		print "<div class=\"box\" id=\"warning\"><p>Please be aware that any modifications to the structure of a scheme will result in the
		removal of all data from it. This is done to ensure data integrity.  This does not affect allele designations, but any profiles
		will have to be reloaded.</p></div>\n";
	}
	my ( $uses_integer_id, $has_sender_field );
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		$uses_integer_id  = 1;
		$has_sender_field = 1;
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach (@$attributes) {
			if ( $_->{'name'} eq 'id' && $_->{'type'} eq 'int' ) {
				$uses_integer_id = 1;
			} elsif ( $_->{'name'} eq 'sender' ) {
				$has_sender_field = 1;
			}
		}
	}
	if ( $q->param('checked_buffer') ) {
		$self->_upload_data( { 'table' => $table, 'locus' => $locus } );
	} elsif ( $q->param('data') || $q->param('query') ) {
		$self->_check_data(
			{ 'table' => $table, 'uses_integer_id' => $uses_integer_id, 'locus' => $locus, 'has_sender_field' => $has_sender_field } );
	} else {
		$self->_print_interface(
			{ 'table' => $table, 'uses_integer_id' => $uses_integer_id, 'has_sender_field' => $has_sender_field, 'locus' => $locus } );
	}
	return;
}

sub _print_interface {
	my ( $self, $arg_ref ) = @_;
	my $table       = $arg_ref->{'table'};
	my $record_name = $self->get_record_name($table);
	my $q           = $self->{'cgi'};
	print << "HTML";
<div class="box" id="queryform">
<p>This page allows you to upload $record_name data as tab-delimited text or 
copied from a spreadsheet.</p>
<ul>
<li>Field header names must be included and fields
can be in any order. Optional fields can be omitted if you wish.</li>
HTML
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		print << "HTML";
<li>Enter aliases (alternative names) for your isolates as a semi-colon (;) separated list.</li>	
<li>Enter references for your isolates as a semi-colon (;) separated list of PubMed ids 
(non integer ids will be ignored).</li>				  
<li>You can also upload allele fields along with the other isolate data - simply create a 
new column with the locus name. These will be
added with a confirmed status and method set as 'manual'.</li>	
HTML
	}
	if ( $table eq 'loci' && $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print << "HTML";
<li>Enter aliases (alternative names) for your locus as a semi-colon (;) separated list.</li>			
HTML
	}
	if ( $arg_ref->{'uses_integer_id'} ) {
		print << "HTML";
<li>You can choose whether or not to include an id number 
field - if it is omitted, the next available id will be used automatically.</li>
HTML
	}
	my $locus_attribute = '';
	if ( $table eq 'sequences' ) {
		$locus_attribute = "&amp;locus=$arg_ref->{'locus'}" if $arg_ref->{'locus'};
		print "<li>If the locus uses integer allele ids you can leave the allele_id "
		  . "field blank and the next available number will be used.</li>\n";
		if ( $self->{'system'}->{'allele_flags'} ) {
			print "<li>Sequence flags can be added as a semi-colon (;) separated list</li>\n";
		}
	}
	print << "HTML";
</ul>
<ul>
<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=tableHeader&amp;table=$table$locus_attribute">Download tab-delimited 
header for your spreadsheet</a> - use Paste special &rarr; text to paste the data.</li>
HTML
	if ( $table eq 'sequences' && !$q->param('locus') ) {
		$self->_print_interface_locus_selection;
	}
	print "</ul>\n";
	print $q->start_form;
	if ( $arg_ref->{'has_sender_field'} ) {
		$self->_print_interface_sender_field;
	}
	if ( $table eq 'sequences' ) {
		$self->_print_interface_sequence_switches;
	}
	print "<p>Please paste in tab-delimited text (<strong>include a field header line</strong>).</p>\n";
	print $q->hidden($_) foreach qw (page db table locus);
	print $q->textarea( -name => 'data', -rows => 20, -columns => 120 );
	print "<table style=\"width:95%\"><tr><td>";
	print $q->reset( -class => 'reset' );
	print "</td><td style=\"text-align:right\">";
	print $q->submit( -class => 'submit' );
	print "</td></tr></table><p />\n";
	print $q->end_form;
	print "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back</a></p>\n";
	print "</div>\n";
	return;
}

sub _print_interface_sender_field {
	my ($self) = @_;
	my $qry    = "select id,user_name,first_name,surname from users WHERE id>0 order by surname";
	my $sql    = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my @users;
	my %usernames;
	$usernames{''} = 'Select sender ...';

	while ( my ( $userid, $username, $firstname, $surname ) = $sql->fetchrow_array ) {
		push @users, $userid;
		$usernames{$userid} = "$surname, $firstname ($username)";
	}
	print "<p>Please select the sender from the list below:</p>\n";
	$usernames{-1} = 'Override with sender field';
	print $self->{'cgi'}->popup_menu( -name => 'sender', -values => [ '', -1, @users ], -labels => \%usernames );
	print "<span class=\"comment\"> Value will be overridden if you include a sender field in your pasted data.</span>\n";
	return;
}

sub _print_interface_locus_selection {
	my ($self)             = @_;
	my $q                  = $self->{'cgi'};
	my $loci_with_extended = $self->{'datastore'}->run_list_query("SELECT DISTINCT locus FROM locus_extended_attributes ORDER BY locus");
	if ( ref $loci_with_extended eq 'ARRAY' ) {
		print "<li>Please note, some loci have extended attributes which may be required.  For affected loci please use the batch insert
				page specific to that locus: ";
		if ( @$loci_with_extended > 10 ) {
			print $q->start_form;
			print $q->hidden($_) foreach qw (page db table);
			print "Reload page specific for locus: ";
			my @values = @$loci_with_extended;
			my %labels;
			unshift @values, '';
			$labels{''} = 'Select ...';
			print $q->popup_menu( -name => 'locus', -values => \@values, -labels => \%labels );
			print $q->submit( -name => 'Reload', -class => 'submit' );
			print $q->end_form;
		} else {
			my $first = 1;
			foreach (@$loci_with_extended) {
				print ' | ' if !$first;
				print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchAdd&amp;table=sequences&amp;locus=$_\">$_</a>";
				$first = 0;
			}
		}
		print "</li>\n";
	}
	return;
}

sub _print_interface_sequence_switches {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	print "<ul style=\"list-style-type:none\"><li>\n";
	print $q->checkbox( -name => 'ignore_existing', -label => 'Ignore existing sequences', -checked => 'checked' );
	print "</li><li>\n";
	print $q->checkbox( -name => 'ignore_non_DNA', -label => 'Ignore sequences containing non-nucleotide characters' );
	print "</li><li>\n";
	print $q->checkbox(
		-name => 'complete_CDS',
		-label =>
'Silently reject all sequences that are not complete reading frames - these must have a start and in-frame stop codon at the ends and no internal stop codons.  Existing sequences are also ignored.'
	);
	print "</li><li>\n";
	print $q->checkbox( -name => 'ignore_similarity', -label => 'Override sequence similarity check' );
	print "</li></ul>\n";
	return;
}

sub _check_data {
	my ( $self, $arg_ref ) = @_;
	my $table = $arg_ref->{'table'};
	my $locus = $arg_ref->{'locus'};
	my $q     = $self->{'cgi'};
	if ( !$q->param('data') ) {
		$q->param( 'data', $self->_convert_query( $q->param('table'), $q->param('query') ) );
	}
	my @checked_buffer;
	my @fieldorder = $self->_get_fields_in_order($table);
	my $extended_attributes;
	my $required_extended_exist;
	my %last_id;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' && $table eq 'sequences' ) {
		if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
			push @fieldorder, 'flags';
		}
		if ($locus) {
			my $sql =
			  $self->{'db'}->prepare(
"SELECT field,value_format,value_regex,required,option_list FROM locus_extended_attributes WHERE locus=? ORDER BY field_order"
			  );
			eval { $sql->execute($locus) };
			$logger->error($@) if $@;
			while ( my ( $field, $format, $regex, $required, $optlist ) = $sql->fetchrow_array ) {
				push @fieldorder, $field;
				$extended_attributes->{$field}->{'format'}      = $format;
				$extended_attributes->{$field}->{'regex'}       = $regex;
				$extended_attributes->{$field}->{'required'}    = $required;
				$extended_attributes->{$field}->{'option_list'} = $optlist;
			}
		} else {
			$required_extended_exist =
			  $self->{'datastore'}->run_list_query("SELECT DISTINCT locus FROM locus_extended_attributes WHERE required");
		}
	}
	my ( $firstname, $surname, $userid );
	my $sender_message = '';
	if ( $arg_ref->{'has_sender_field'} ) {
		my $sender = $q->param('sender');
		if ( !$sender ) {
			print "<div class=\"box\" id=\"statusbad\"><p>Please go back and select the sender for this submission.</p></div>\n";
			return;
		} elsif ( $sender == -1 ) {
			$sender_message = "<p>Using sender field in pasted data.</p>\n";
		} else {
			my $sender_ref = $self->{'datastore'}->get_user_info($sender);
			$sender_message = "<p>Sender: $sender_ref->{'first_name'} $sender_ref->{'surname'}</p>\n";
		}
	}
	my %problems;
	my $tablebuffer;
	$tablebuffer .= "<div class=\"scrollable\"><table class=\"resultstable\"><tr>";
	$tablebuffer .= $self->_get_field_table_header($table);
	$tablebuffer .= "</tr>";
	my @records = split /\n/, $q->param('data');
	my $td = 1;
	my $header;

	while ( $header = shift @records ) {    #ignore blank lines before header
		$header =~ s/\r//g;
		last if $header ne '';
	}
	my @file_header_fields = split /\t/, $header;
	my %file_header_pos;
	my $pos = 0;
	foreach (@file_header_fields) {
		$file_header_pos{$_} = $pos;
		$pos++;
	}
	my $id;
	my %unique_field;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		$id = $self->next_id($table);
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach (@$attributes) {
			if ( $_->{'name'} eq 'id' && $_->{'type'} eq 'int' ) {
				$id = $self->next_id($table);
			}
			if ( $_->{'unique'} && $_->{'unique'} eq 'yes' ) {
				$unique_field{ $_->{'name'} } = 1;
			}
		}
	}
	my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
	my %locus_format;
	my %locus_regex;
	my $first_record = 1;
	my $header_row;
	my $record_count;
	my ( $sql_sequence_exists, $sql_allele_id_exists );

	foreach my $record (@records) {
		$record =~ s/\r//g;
		next if $record =~ /^\s*$/;
		my @profile;
		my $checked_record;
		if ($record) {
			my @data = split /\t/, $record;
			my $first = 1;
			if ( $arg_ref->{'uses_integer_id'} && !$first_record ) {
				do {
					$id++;
				} while ( $self->_is_id_used( $table, $id ) );
			}
			my ( $pk_combination, $pk_values_ref ) = $self->_get_primary_key_values(
				{
					'primary_keys'    => \@primary_keys,
					'file_header_pos' => \%file_header_pos,
					'id'              => $id,
					'locus'           => $locus,
					'table'           => $table,
					'first'           => \$first,
					'data'            => \@data,
					'record_count'    => \$record_count
				}
			);
			my $rowbuffer;
			my $continue = 1;
			foreach my $field (@fieldorder) {

				#Prepare checked header
				if ( $first_record && ( defined $file_header_pos{$field} || $field eq 'id' ) ) {
					$header_row .= "$field\t";
				}

				#Check individual values for correctness.
				my $value = $self->_extract_value(
					{
						'field'               => $field,
						'data'                => \@data,
						'id'                  => $id,
						'file_header_pos'     => \%file_header_pos,
						'extended_attributes' => $extended_attributes
					}
				);
				my $special_problem;
				my %args = (
					'locus'                   => $locus,
					'field'                   => $field,
					'value'                   => \$value,
					'file_header_pos'         => \%file_header_pos,
					'data'                    => \@data,
					'required_extended_exist' => $required_extended_exist,
					'pk_combination'          => $pk_combination,
					'problems'                => \%problems,
					'special_problem'         => \$special_problem,
					'continue'                => \$continue,
					'last_id'                 => \%last_id,
					'extended_attributes'     => $extended_attributes,
					'unique_field'            => \%unique_field
				);
				$self->_check_data_duplicates( \%args );
				if ( $table eq 'sequences' ) {
					$file_header_pos{'allele_id'} = keys %file_header_pos if !defined $file_header_pos{'allele_id'};
					$self->_check_data_sequences( \%args );
				} elsif ( $table eq 'allele_designations' ) {
					$self->_check_data_allele_designations( \%args );
				} elsif ( $table eq 'users' ) {
					$self->_check_data_users( \%args );
				} elsif ( $table eq 'scheme_group_group_members' ) {
					$self->_check_data_scheme_group_group_members( \%args );
				}

				#Display field - highlight in red if invalid.
				my $display_value;
				if ( $field =~ /sequence/ && $field ne 'coding_sequence' ) {
					$value ||= '';
					$display_value = "<span class=\"seq\">" . ( BIGSdb::Utils::truncate_seq( \$value, 40 ) ) . "</span>";
				} else {
					$display_value = $value;
				}
				if ( !( ( my $problem .= $self->is_field_bad( $table, $field, $value, 'insert' ) ) || $special_problem ) ) {
					if ( $table eq 'sequences' && $field eq 'flags' ) {
						my @flags = split /;/, ( $display_value // '' );
						local $" = "</a> <a class=\"seqflag_tooltip\">";
						$display_value = "<a class=\"seqflag_tooltip\">@flags</a>" if @flags;
					}
					$rowbuffer .= defined $display_value ? "<td>$display_value</td>" : '<td />';
				} else {
					$rowbuffer .= defined $display_value ? "<td><font color=\"red\">$display_value</font></td>" : '<td />';
					if ($problem) {
						my $problem_text = "$field $problem<br />";
						$problems{$pk_combination} .= $problem_text
						  if !defined $problems{$pk_combination} || $problems{$pk_combination} !~ /$problem_text/;
					}
				}
				$value = defined $value ? $value : '';
				$checked_record .= "$value\t"
				  if defined $file_header_pos{$field}
					  or ( $field eq 'id' );
			}
			if ( !$continue ) {
				undef $header_row if $first_record;
				next;
			}
			$tablebuffer .= "<tr class=\"td$td\">$rowbuffer";
			my %args = (
				'file_header_fields' => \@file_header_fields,
				'header_row'         => \$header_row,
				'first_record'       => $first_record,
				'file_header_pos'    => \%file_header_pos,
				'data'               => \@data,
				'locus_format'       => \%locus_format,
				'locus_regex'        => \%locus_regex,
				'primary_keys'       => \@primary_keys,
				'pk_combination'     => $pk_combination,
				'pk_values'          => $pk_values_ref,
				'problems'           => \%problems,
				'checked_record'     => \$checked_record,
				'table'              => $table
			);
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {

				#Check for locus values that can also be uploaded with an isolate record.
				$tablebuffer .= $self->_check_data_isolate_record_locus_fields( \%args );
			}
			$tablebuffer .= "</tr>\n";

			#Check for various invalid combinations of fields
			if ( $table ne 'sequences' ) {
				try {
					$self->_check_data_primary_key( \%args );
				}
				catch BIGSdb::DataException with {
					$continue = 0;
				};
				last if !$continue;
			}
			if ( $self->{'system'}->{'dbtype'} eq 'sequences' && ( $table eq 'accession' || $table eq 'sequence_refs' ) ) {

				#check that sequence exists when adding accession or PubMed number
				if ( !$self->{'datastore'}->sequence_exists(@$pk_values_ref) ) {
					$problems{$pk_combination} .= "Sequence $pk_values_ref->[0]-$pk_values_ref->[1] does not exist.";
				}
			} elsif ( $table eq 'loci' ) {
				$self->_check_data_loci( \%args );

				#check that user is allowed to access this sequence bin record (controlled by isolate ACL)
			} elsif (
				(
					$self->{'system'}->{'read_access'} eq 'acl'
					|| ( $self->{'system'}->{'write_access'} && $self->{'system'}->{'write_access'} eq 'acl' )
				)
				&& $self->{'username'}
				&& !$self->is_admin
				&& $table eq 'accession'
				&& $self->{'system'}->{'dbtype'} eq 'isolates'
			  )
			{
				my $isolate_id_ref =
				  $self->{'datastore'}
				  ->run_simple_query( "SELECT isolate_id FROM sequence_bin WHERE id=?", $data[ $file_header_pos{'seqbin_id'} ] );
				if ( ref $isolate_id_ref eq 'ARRAY' && !$self->is_allowed_to_view_isolate( $isolate_id_ref->[0] ) ) {
					$problems{$pk_combination} .=
"The sequence you are trying to add an accession to belongs to an isolate to which your user account is not allowed to access.";
				}

				#check that user is allowed to access this isolate record
			} elsif (
				(
					$self->{'system'}->{'read_access'} eq 'acl'
					|| ( $self->{'system'}->{'write_access'} && $self->{'system'}->{'write_access'} eq 'acl' )
				)
				&& $self->{'username'}
				&& !$self->is_admin
				&& ( $table eq 'allele_designations' || $table eq 'sequence_bin' || $table eq 'isolate_aliases' )
				&& !$self->is_allowed_to_view_isolate( $data[ $file_header_pos{'isolate_id'} ] )
			  )
			{
				$problems{$pk_combination} .= "Your user account is not allowed to modify data for this isolate.";

				#check that user is allowed to add sequences for this locus
			}
			if (   ( $table eq 'sequences' || $table eq 'sequence_refs' || $table eq 'accession' )
				&& $self->{'system'}->{'dbtype'} eq 'sequences'
				&& !$self->is_admin )
			{
				if (
					!$self->{'datastore'}->is_allowed_to_modify_locus_sequences(
						( $locus ? $locus : $data[ $file_header_pos{'locus'} ] ),
						$self->get_curator_id
					)
				  )
				{
					$problems{$pk_combination} .= "Your user account is not allowed to add or modify sequences for locus "
					  . ( $locus || $data[ $file_header_pos{'locus'} ] ) . ".";
				}
			}
		}
		$td = $td == 1 ? 2 : 1;    #row stripes
		push @checked_buffer, $header_row if $first_record;
		$checked_record =~ s/\t$// if defined $checked_record;
		push @checked_buffer, $checked_record;
		$first_record = 0;
	}
	$tablebuffer .= "</table></div>\n";
	if ( !$record_count ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No valid data entered. Make sure you've included the header line.</p></div>\n";
		return;
	}
	if (%problems) {
		print "<div class=\"box\" id=\"statusbad\"><h2>Import status</h2>\n";
		print "<table class=\"resultstable\">";
		print "<tr><th>Primary key</th><th>Problem(s)</th></tr>\n";
		my $td = 1;
		foreach my $id ( sort keys %problems ) {
			print "<tr class=\"td$td\"><td>$id</td><td style=\"text-align:left\">$problems{$id}</td></tr>";
			$td = $td == 1 ? 2 : 1;    #row stripes
		}
		print "</table></div>\n";
	} else {
		print
		  "<div class=\"box\" id=\"resultsheader\"><h2>Import status</h2>$sender_message<p>No obvious problems identified so far.</p>\n";
		my $filename = $self->make_temp_file(@checked_buffer);
		print $q->start_form;
		print $q->hidden($_) foreach qw (page table db sender locus);
		print $q->hidden( 'checked_buffer', $filename );
		print $q->submit( -name => 'Import data', -class => 'submit' );
		print $q->endform;
		print "</div>\n";
	}
	print "<div class=\"box\" id=\"resultstable\"><h2>Data to be imported</h2>\n";
	my $caveat =
	  ( $table eq 'sequences' && ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' )
	  ? '<em>Note: valid sequence flags are displayed with a red background not red text.</em>'
	  : '';
	print "<p>The following table shows your data.  Any field with red text has a problem and needs to be checked. $caveat</p>\n";
	print $tablebuffer;
	print "</div><p />";
	return;
}

sub _extract_value {
	my ( $self, $arg_ref ) = @_;
	my $q               = $self->{'cgi'};
	my $field           = $arg_ref->{'field'};
	my @data            = @{ $arg_ref->{'data'} };
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	my $value;
	if ( $field eq 'id' ) {
		$value = $arg_ref->{'id'};
	}
	if ( $field eq 'datestamp' || $field eq 'date_entered' ) {
		$value = $self->get_datestamp;
	} elsif ( $field eq 'sender' ) {
		if ( defined $file_header_pos{$field} ) {
			$value = $data[ $file_header_pos{$field} ];
		} else {
			$value = $q->param('sender')
			  if $q->param('sender') != -1;
		}
	} elsif ( $field eq 'curator' ) {
		$value = $self->get_curator_id;
	} elsif ( $arg_ref->{'extended_attributes'}->{$field}->{'format'}
		&& $arg_ref->{'extended_attributes'}->{$field}->{'format'} eq 'boolean' )
	{
		if ( defined $file_header_pos{$field} ) {
			$value = $data[ $file_header_pos{$field} ];
			$value = lc($value);
		}
	} else {
		if ( defined $file_header_pos{$field} ) {
			$value = $data[ $file_header_pos{$field} ];
		}
	}
	return $value;
}

sub _get_primary_key_values {
	my ( $self, $arg_ref ) = @_;
	my @data            = @{ $arg_ref->{'data'} };
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	my $pk_combination;
	my @pk_values;
	foreach ( @{ $arg_ref->{'primary_keys'} } ) {
		if ( !defined $file_header_pos{$_} ) {
			if ( $_ eq 'id' && $arg_ref->{'id'} ) {
				$pk_combination .= "id: " . BIGSdb::Utils::pad_length( $arg_ref->{'id'}, 10 );
			} else {
				if ( $arg_ref->{'table'} eq 'sequences' && $arg_ref->{'locus'} && $_ eq 'locus' ) {
					push @pk_values, $arg_ref->{'locus'};
					$pk_combination .= "$_: " . BIGSdb::Utils::pad_length( $arg_ref->{'locus'}, 10 );
				} else {
					$pk_combination .= '; ' if $pk_combination;
					$pk_combination .= "$_: undef";
				}
			}
		} else {
			$pk_combination .= '; ' if !${ $arg_ref->{'first'} };
			$pk_combination .=
			  "$_: " . ( defined $data[ $file_header_pos{$_} ] ? BIGSdb::Utils::pad_length( $data[ $file_header_pos{$_} ], 10 ) : 'undef' );
			push @pk_values, $data[ $file_header_pos{$_} ];
		}
		${ $arg_ref->{'first'} } = 0;
		${ $arg_ref->{'record_count'} }++;
	}
	return ( $pk_combination, \@pk_values );
}

sub _check_data_isolate_record_locus_fields {
	my ( $self, $arg_ref ) = @_;
	my $first_record    = $arg_ref->{'first_record'};
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	my @data            = @{ $arg_ref->{'data'} };
	my $pk_combination  = $arg_ref->{'pk_combination'};
	my %is_locus;
	$is_locus{$_} = 1 foreach @{ $self->{'datastore'}->get_loci };
	my $locusbuffer;

	foreach ( @{ $arg_ref->{'file_header_fields'} } ) {
		if ( $is_locus{$_} ) {
			${ $arg_ref->{'header_row'} } .= "$_\t" if $first_record;
			my $value = defined $file_header_pos{$_} ? $data[ $file_header_pos{$_} ] : undef;
			if ( !$arg_ref->{'locus_format'}->{$_} ) {
				my $locus_info = $self->{'datastore'}->get_locus_info($_);
				$arg_ref->{'locus_format'}->{$_} = $locus_info->{'allele_id_format'};
				$arg_ref->{'locus_regex'}->{$_}  = $locus_info->{'allele_id_regex'};
			}
			if ( defined $value && $value ne '' ) {
				if ( $arg_ref->{'locus_format'}->{$_} eq 'integer'
					&& !BIGSdb::Utils::is_int($value) )
				{
					$locusbuffer .= "<span><font color='red'>$_:&nbsp;$value</font></span><br />";
					$arg_ref->{'problems'}->{$pk_combination} .= "'$_' must be an integer<br />";
				} elsif ( $arg_ref->{'locus_regex'}->{$_} && $value !~ /$arg_ref->{'locus_regex'}->{$_}/ ) {
					$locusbuffer .= "<span><font color='red'>$_:&nbsp;$value</font></span><br />";
					$arg_ref->{'problems'}->{$pk_combination} .= "'$_' does not conform to specified format.<br />";
				} else {
					$locusbuffer .= "$_:&nbsp;$value<br />";
				}
				${ $arg_ref->{'checked_record'} } .= "$value\t";
			} else {
				${ $arg_ref->{'checked_record'} } .= "\t";
			}
		}
	}
	return defined $locusbuffer ? "<td>$locusbuffer</td>" : '<td />';
}

sub _check_data_users {

	#special case to prevent a new user with curator or admin status unless user is admin themselves
	my ( $self, $arg_ref ) = @_;
	my $field          = $arg_ref->{'field'};
	my $value          = ${ $arg_ref->{'value'} };
	my $pk_combination = $arg_ref->{'pk_combination'};
	if ( $field eq 'status' ) {
		if ( defined $value && $value ne 'user' && !$self->is_admin() ) {
			my $problem_text = "Only a user with admin status can add a user with a status other than 'user'<br />";
			$arg_ref->{'problems'}->{$pk_combination} .= $problem_text
			  if !defined $arg_ref->{'problems'}->{$pk_combination} || $arg_ref->{'problems'}->{$pk_combination} !~ /$problem_text/;
			${ $arg_ref->{'special_problem'} } = 1;
		}
	}
	return;
}

sub _check_data_primary_key {
	my ( $self, $arg_ref ) = @_;
	my $pk_combination = $arg_ref->{'pk_combination'};
	my @primary_keys   = @{ $arg_ref->{'primary_keys'} };
	if ( !$self->{'sql'}->{'primary_key_check'} ) {
		local $" = '=? AND ';
		my $qry = "SELECT COUNT(*) FROM $arg_ref->{'table'} WHERE @primary_keys=?";
		$self->{'sql'}->{'primary_key_check'} = $self->{'db'}->prepare($qry);
	}
	if ( $self->{'primary_key_combination'}->{$pk_combination} && $pk_combination !~ /\:\s*$/ ) {
		my $problem_text = "Primary key submitted more than once in this batch.<br />";
		$arg_ref->{'problems'}->{$pk_combination} .= $problem_text
		  if !defined $arg_ref->{'problems'}->{$pk_combination} || $arg_ref->{'problems'}->{$pk_combination} !~ /$problem_text/;
	}
	$self->{'primary_key_combination'}->{$pk_combination}++;

	#Check if primary key already in database
	if ( @{ $arg_ref->{'pk_values'} } ) {
		eval { $self->{'sql'}->{'primary_key_check'}->execute( @{ $arg_ref->{'pk_values'} } ) };
		if ($@) {
			my $message = $@;
			local $" = ', ';
			$logger->debug(
"Can't execute primary key check (incorrect data pasted): primary keys: @primary_keys values: @{$arg_ref->{'pk_values'}} $message"
			);
			my $plural = scalar @primary_keys > 1 ? 's' : '';
			if ( $message =~ /invalid input/ ) {
				print
				  "<div class=\"box statusbad\"><p>Your pasted data has invalid primary key field$plural (@primary_keys) data.</p></div>\n";
				throw BIGSdb::DataException("Invalid primary key");
			}
			print
"<div class=\"box statusbad\"><p>Your pasted data does not appear to contain the primary key field$plural (@primary_keys) required for this table.</p></div>\n";
			throw BIGSdb::DataException("no primary key field$plural (@primary_keys)");
		}
		my ($exists) = $self->{'sql'}->{'primary_key_check'}->fetchrow_array;
		if ($exists) {
			my $problem_text = "Primary key already exists in the database.<br />";
			$arg_ref->{'problems'}->{$pk_combination} .= $problem_text
			  if !defined $arg_ref->{'problems'}->{$pk_combination} || $arg_ref->{'problems'}->{$pk_combination} !~ /$problem_text/;
		}
	}
	return;
}

sub _check_data_loci {

	#special case to ensure that a locus length is set if it is not marked as variable length
	my ( $self, $arg_ref ) = @_;
	my @data            = @{ $arg_ref->{'data'} };
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	my $pk_combination  = $arg_ref->{'pk_combination'};
	if (
		(
			   defined $file_header_pos{'length_varies'}
			&& defined $data[ $file_header_pos{'length_varies'} ]
			&& none { $data[ $file_header_pos{'length_varies'} ] eq $_ } qw (true TRUE 1)
		)
		&& !$data[ $file_header_pos{'length'} ]
	  )
	{
		$arg_ref->{'problems'}->{$pk_combination} .= "Locus set as non variable length but no length is set.<br />";
	}
	if ( $data[ $file_header_pos{'id'} ] =~ /^\d/ ) {
		$arg_ref->{'problems'}->{$pk_combination} .=
		  "Locus names can not start with a digit.  Try prepending an underscore (_) which will get hidden in the query interface.<br />";
	}
	if ( $data[ $file_header_pos{'id'} ] =~ /[^\w_']/ ) {
		$arg_ref->{'problems'}->{$pk_combination} .=
		  "Locus names can only contain alphanumeric, underscore (_) and prime (') characters (no spaces or other symbols).<br />";
	}
	return;
}

sub _check_data_duplicates {

	#check if unique value exists twice in submission
	my ( $self, $arg_ref ) = @_;
	my $field          = $arg_ref->{'field'};
	my $value          = ${ $arg_ref->{'value'} };
	my $pk_combination = $arg_ref->{'pk_combination'};
	if ( $arg_ref->{'unique_field'}->{$field} ) {
		if ( $self->{'unique_values'}->{$field}->{$value} ) {
			my $problem_text = "unique field '$field' already has a value of '$value' set within this submission.<br />";
			$arg_ref->{'problems'}->{$pk_combination} .= $problem_text
			  if !defined $arg_ref->{'problems'}->{$pk_combination} || $arg_ref->{'problems'}->{$pk_combination} !~ /$problem_text/;
			${ $arg_ref->{'special_problem'} } = 1;
		}
		$self->{'unique_values'}->{$field}->{$value}++;
	}
	return;
}

sub _check_data_allele_designations {

	#special case to check for allele id format and regex which is defined in loci table
	my ( $self, $arg_ref ) = @_;
	my $field           = $arg_ref->{'field'};
	my $pk_combination  = $arg_ref->{'pk_combination'};
	my @data            = @{ $arg_ref->{'data'} };
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	if ( $field eq 'allele_id' ) {
		my $format;
		eval {
			$format =
			  $self->{'datastore'}
			  ->run_simple_query( "SELECT allele_id_format,allele_id_regex FROM loci WHERE id=?", $data[ $file_header_pos{'locus'} ] );
		};
		$logger->error($@) if $@;
		if (   defined $format->[0]
			&& $format->[0] eq 'integer'
			&& !BIGSdb::Utils::is_int( ${ $arg_ref->{'value'} } ) )
		{
			my $problem_text = "$field must be an integer.<br />";
			$arg_ref->{'problems'}->{$pk_combination} .= $problem_text
			  if !defined $arg_ref->{'problems'}->{$pk_combination} || $arg_ref->{'problems'}->{$pk_combination} !~ /$problem_text/;
			${ $arg_ref->{'special_problem'} } = 1;
		} elsif ( $format->[1] && ${ $arg_ref->{'value'} } !~ /$format->[1]/ ) {
			$arg_ref->{'problems'}->{$pk_combination} .=
			  "$field value is invalid - it must match the regular expression /$format->[1]/.<br />";
			${ $arg_ref->{'special_problem'} } = 1;
		}
	}
	return;
}

sub _check_data_scheme_group_group_members {
	my ( $self, $arg_ref ) = @_;
	my $field           = $arg_ref->{'field'};
	my $pk_combination  = $arg_ref->{'pk_combination'};
	my @data            = @{ $arg_ref->{'data'} };
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	if (   $field eq 'group_id'
		&& $data[ $file_header_pos{'parent_group_id'} ] == $data[ $file_header_pos{'group_id'} ] )
	{
		$arg_ref->{'problems'}->{$pk_combination} .= "A scheme group can't be a member of itself.";
		${ $arg_ref->{'special_problem'} } = 1;
	}
	return;
}

sub _check_data_sequences {
	my ( $self, $arg_ref ) = @_;
	my $locus           = $arg_ref->{'locus'};
	my $field           = $arg_ref->{'field'};
	my $pk_combination  = $arg_ref->{'pk_combination'};
	my %file_header_pos = %{ $arg_ref->{'file_header_pos'} };
	my @data            = @{ $arg_ref->{'data'} };
	my $q               = $self->{'cgi'};
	my $buffer;

	if ( !$self->{'sql'}->{'sequence_exists'} ) {
		$self->{'sql'}->{'sequence_exists'} = $self->{'db'}->prepare("SELECT allele_id FROM sequences WHERE locus=? AND sequence=?");
	}
	if ( !$self->{'sql'}->{'allele_id_exists'} ) {
		$self->{'sql'}->{'allele_id_exists'} = $self->{'db'}->prepare("SELECT COUNT(*) FROM sequences WHERE locus=? AND allele_id=?");
	}
	if ( $field eq 'locus' && $q->param('locus') ) {
		${ $arg_ref->{'value'} } = $q->param('locus');
	}
	if ( $field eq 'allele_id' ) {
		if ( $q->param('locus') ) {
			$locus = $q->param('locus');
		} else {
			$locus =
			  ( defined $file_header_pos{'locus'} && defined $data[ $file_header_pos{'locus'} ] )
			  ? $data[ $file_header_pos{'locus'} ]
			  : undef;
		}
		if (   defined $file_header_pos{'locus'}
			&& $data[ $file_header_pos{'locus'} ]
			&& any { $_ eq $data[ $file_header_pos{'locus'} ] } @{ $arg_ref->{'required_extended_exist'} } )
		{
			$buffer .= "Locus $locus has required extended attributes - please use specific batch upload form for this locus.<br />";
		}
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		if (
			   defined $locus_info->{'allele_id_format'}
			&& $locus_info->{'allele_id_format'} eq 'integer'
			&& (   !defined $file_header_pos{'allele_id'}
				|| !defined $data[ $file_header_pos{'allele_id'} ]
				|| $data[ $file_header_pos{'allele_id'} ] eq '' )
		  )
		{
			if ( $arg_ref->{'last_id'}->{$locus} ) {
				${ $arg_ref->{'value'} } = $arg_ref->{'last_id'}->{$locus};
			} else {
				${ $arg_ref->{'value'} } = $self->{'datastore'}->get_next_allele_id($locus) - 1;
			}
			my $exists;
			do {
				${ $arg_ref->{'value'} }++;
				eval { $self->{'sql'}->{'allele_id_exists'}->execute( $locus, ${ $arg_ref->{'value'} } ) };
				if ($@) {
					$logger->error("Can't execute allele id exists check. values $locus,${$arg_ref->{'value'}} $@");
					last;
				}
				($exists) = $self->{'sql'}->{'allele_id_exists'}->fetchrow_array;
			} while $exists;
			$arg_ref->{'last_id'}->{$locus} = ${ $arg_ref->{'value'} };
		} elsif ( defined $file_header_pos{'allele_id'}
			&& !BIGSdb::Utils::is_int( $data[ $file_header_pos{'allele_id'} ] )
			&& defined $locus_info->{'allele_id_format'}
			&& $locus_info->{'allele_id_format'} eq 'integer' )
		{
			$buffer .= "Allele id must be an integer.<br />";
		}
		my $regex = $locus_info->{'allele_id_regex'};
		if ( $regex && $data[ $file_header_pos{'allele_id'} ] !~ /$regex/ ) {
			$buffer .= "Allele id value is invalid - it must match the regular expression /$regex/<br />";
		}
	}

	#special case to check for sequence length in sequences table, and that sequence doesn't already exist
	#and is similar to existing.
	if ( $field eq 'sequence' ) {
		if ( $q->param('locus') ) {
			$locus = $q->param('locus');
		} else {
			$locus =
			  ( defined $file_header_pos{'locus'} && defined $data[ $file_header_pos{'locus'} ] )
			  ? $data[ $file_header_pos{'locus'} ]
			  : undef;
		}
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		my $length     = defined ${ $arg_ref->{'value'} } ? length( ${ $arg_ref->{'value'} } ) : 0;
		my $units      = ( !defined $locus_info->{'data_type'} || $locus_info->{'data_type'} eq 'DNA' ) ? 'bp' : 'residues';
		if ( !$locus_info->{'length_varies'} && defined $locus_info->{'length'} && $locus_info->{'length'} != $length ) {
			my $problem_text =
			  "Sequence is $length $units long but this locus is set as a standard length of $locus_info->{'length'} $units.<br />";
			$buffer .= $problem_text
			  if !$buffer || $buffer !~ /$problem_text/;
			${ $arg_ref->{'special_problem'} } = 1;
		} elsif ( $locus_info->{'min_length'} && $length < $locus_info->{'min_length'} ) {
			my $problem_text =
			  "Sequence is $length $units long but this locus is set with a minimum length of $locus_info->{'min_length'} $units.<br />";
			$buffer .= $problem_text;
		} elsif ( $locus_info->{'max_length'} && $length > $locus_info->{'max_length'} ) {
			my $problem_text =
			  "Sequence is $length $units long but this locus is set with a maximum length of $locus_info->{'max_length'} $units.<br />";
			$buffer .= $problem_text;
		} elsif ( defined $file_header_pos{'allele_id'}
			&& defined $data[ $file_header_pos{'allele_id'} ]
			&& $data[ $file_header_pos{'allele_id'} ] =~ /\s/ )
		{
			$buffer .= "Allele id must not contain spaces - try substituting with underscores (_).<br />";
		} else {
			${ $arg_ref->{'value'} } = uc( ${ $arg_ref->{'value'} } );
			${ $arg_ref->{'value'} } =~ s/[\W]//g;
			eval { $self->{'sql'}->{'sequence_exists'}->execute( $locus, ${ $arg_ref->{'value'} } ) };
			if ($@) {
				$logger->error("Can't execute sequence exists check. values $locus,${$arg_ref->{'value'}} $@");
			}
			my ($exists) = $self->{'sql'}->{'sequence_exists'}->fetchrow_array;
			if ($exists) {
				if ( $q->param('complete_CDS') || $q->param('ignore_existing') ) {
					${ $arg_ref->{'continue'} } = 0;
				} else {
					$buffer .= "Sequence already exists in the database ($locus: $exists).<br />";
				}
			}
			if ( $q->param('complete_CDS') ) {
				my $first_codon = substr( ${ $arg_ref->{'value'} }, 0, 3 );
				${ $arg_ref->{'continue'} } = 0 if none { $first_codon eq $_ } qw (ATG GTG TTG);
				my $end_codon = substr( ${ $arg_ref->{'value'} }, -3 );
				${ $arg_ref->{'continue'} } = 0 if none { $end_codon eq $_ } qw (TAA TGA TAG);
				my $multiple_of_3 = ( length( ${ $arg_ref->{'value'} } ) / 3 ) == int( length( ${ $arg_ref->{'value'} } ) / 3 ) ? 1 : 0;
				${ $arg_ref->{'continue'} } = 0 if !$multiple_of_3;
				my $internal_stop;
				for ( my $pos = 0 ; $pos < length( ${ $arg_ref->{'value'} } ) - 3 ; $pos += 3 ) {
					my $codon = substr( ${ $arg_ref->{'value'} }, $pos, 3 );
					if ( any { $codon eq $_ } qw (TAA TGA TAG) ) {
						$internal_stop = 1;
					}
				}
				${ $arg_ref->{'continue'} } = 0 if $internal_stop;
			}
		}
		if ( ${ $arg_ref->{'continue'} } ) {
			if ( ( !defined $locus_info->{'data_type'} || $locus_info->{'data_type'} eq 'DNA' )
				&& !BIGSdb::Utils::is_valid_DNA( ${ $arg_ref->{'value'} } ) )
			{
				if ( $q->param('complete_CDS') || $q->param('ignore_non_DNA') ) {
					${ $arg_ref->{'continue'} } = 0;
				} else {
					$buffer .= "Sequence contains non nucleotide (G|A|T|C) characters.<br />";
				}
			} elsif ( ( !defined $locus_info->{'data_type'} || $locus_info->{'data_type'} eq 'DNA' )
				&& $self->{'datastore'}->sequences_exist($locus)
				&& !$q->param('ignore_similarity')
				&& !$self->sequence_similar_to_others( $locus, $arg_ref->{'value'} ) )
			{
				$buffer .=
				    "Sequence is too dissimilar to existing alleles (less than 70% identical or an alignment of "
				  . "less than 90% its length). Similarity is determined by the output of the best match from the BLAST "
				  . "algorithm - this may be conservative.  If you're sure that this sequence should be entered, please "
				  . "select the 'Override sequence similarity check' box.<br />";
			}
		}
	}

	#check extended attributes if they exist
	if ( $arg_ref->{'extended_attributes'}->{$field} ) {
		my @optlist;
		my %options;
		if ( $arg_ref->{'extended_attributes'}->{$field}->{'option_list'} ) {
			@optlist = split /\|/, $arg_ref->{'extended_attributes'}->{$field}->{'option_list'};
			foreach (@optlist) {
				$options{$_} = 1;
			}
		}
		if (
			$arg_ref->{'extended_attributes'}->{$field}->{'required'}
			&& (   !defined $file_header_pos{$field}
				|| !defined $data[ $file_header_pos{$field} ]
				|| $data[ $file_header_pos{$field} ] eq '' )
		  )
		{
			$buffer .= "'$field' is a required field and cannot be left blank.<br />";
		} elsif ( $arg_ref->{'extended_attributes'}->{$field}->{'option_list'}
			&& defined $file_header_pos{$field}
			&& defined $data[ $file_header_pos{$field} ]
			&& $data[ $file_header_pos{$field} ] ne ''
			&& !$options{ $data[ $file_header_pos{$field} ] } )
		{
			local $" = ', ';
			$buffer .= "Field '$field' value is not on the allowed list (@optlist).<br />";
		} elsif ( $arg_ref->{'extended_attributes'}->{$field}->{'format'}
			&& $arg_ref->{'extended_attributes'}->{$field}->{'format'} eq 'integer'
			&& ( defined $file_header_pos{$field} && defined $data[ $file_header_pos{$field} ] && $data[ $file_header_pos{$field} ] ne '' )
			&& !BIGSdb::Utils::is_int( $data[ $file_header_pos{$field} ] ) )
		{
			$buffer .= "Field '$field' must be an integer.<br />";
		} elsif (
			$arg_ref->{'extended_attributes'}->{$field}->{'format'}
			&& $arg_ref->{'extended_attributes'}->{$field}->{'format'} eq 'boolean'
			&& (   defined $file_header_pos{$field}
				&& lc( $data[ $file_header_pos{$field} ] ) ne 'false'
				&& lc( $data[ $file_header_pos{$field} ] ) ne 'true' )
		  )
		{
			$buffer .= "Field '$field' must be boolean (either true or false).<br />";
		} elsif ( defined $file_header_pos{$field}
			&& defined $data[ $file_header_pos{$field} ]
			&& $data[ $file_header_pos{$field} ] ne ''
			&& $arg_ref->{'extended_attributes'}->{$field}->{'regex'}
			&& $data[ $file_header_pos{$field} ] !~ /$arg_ref->{'extended_attributes'}->{$field}->{'regex'}/ )
		{
			$buffer .= "Field '$field' does not conform to specified format.<br />\n";
		}
	}

	#check sequence flags
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' && $field eq 'flags' && defined $file_header_pos{'flags'} ) {
		my @flags = split /;/, $data[ $file_header_pos{'flags'} ] // '';
		foreach my $flag (@flags) {
			if ( none { $flag eq $_ } ALLELE_FLAGS ) {
				$buffer .= "Flag '$flag' is not on the list of allowed flags.<br />\n";
			}
		}
	}
	if ($buffer) {
		$arg_ref->{'problems'}->{$pk_combination} .= $buffer;
		${ $arg_ref->{'special_problem'} } = 1;
	}
	return;
}

sub _upload_data {
	my ( $self, $arg_ref ) = @_;
	my $table    = $arg_ref->{'table'};
	my $locus    = $arg_ref->{'locus'};
	my $loci     = $self->{'datastore'}->get_loci;
	my $q        = $self->{'cgi'};
	my $dir      = $self->{'config'}->{'secure_tmp_dir'};
	my $tmp_file = $dir . '/' . $q->param('checked_buffer');
	my %schemes;
	my @records;

	if ( -e $tmp_file ) {
		open( my $tmp_fh, '<', $tmp_file ) or $logger->error("Can't open $tmp_file");
		@records = <$tmp_fh>;
		close $tmp_fh;
	}
	if ( $tmp_file =~ /^(.*\/BIGSdb_[0-9_]+\.txt)$/ ) {
		$logger->info("Deleting temp file $tmp_file");
		unlink $1;
	} else {
		$logger->error("Can't delete temp file $tmp_file");
	}
	my $headerline = shift @records;
	my @fieldorder;
	if ( defined $headerline ) {
		$headerline =~ s/[\r\n]//g;
		@fieldorder = split /\t/, $headerline;
	}
	my %fieldorder;
	my $extended_attributes;
	for ( my $i = 0 ; $i < @fieldorder ; $i++ ) {
		$fieldorder{ $fieldorder[$i] } = $i;
	}
	my @fields_to_include;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		foreach ( @{ $self->{'xmlHandler'}->get_field_list } ) {
			push @fields_to_include, $_;
		}
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach (@$attributes) {
			push @fields_to_include, $_->{'name'};
		}
		if ( $table eq 'sequences' && $locus ) {
			$extended_attributes =
			  $self->{'datastore'}->run_list_query( "SELECT field FROM locus_extended_attributes WHERE locus=?", $locus );
		}
	}
	my @history;
	foreach my $record (@records) {
		$record =~ s/\r//g;
		my @profile;
		if ($record) {
			my @data = split /\t/, $record;
			@data = $self->_process_fields( \@data );
			my @value_list;
			my ( @extras, @ref_extras );
			my ( $id,     $sender );
			foreach (@fields_to_include) {
				$id = $data[ $fieldorder{$_} ] if $_ eq 'id';
				if ( $_ eq 'date_entered' || $_ eq 'datestamp' ) {
					push @value_list, "'today'";
				} elsif ( $_ eq 'curator' ) {
					push @value_list, $self->get_curator_id;
				} elsif ( defined $fieldorder{$_}
					&& defined $data[ $fieldorder{$_} ]
					&& $data[ $fieldorder{$_} ] ne 'null'
					&& $data[ $fieldorder{$_} ] ne '' )
				{
					push @value_list, "'$data[$fieldorder{$_}]'";
					if ( $_ eq 'sender' ) {
						$sender = $data[ $fieldorder{$_} ];
					}
				} elsif ( $_ eq 'sender' ) {
					if ( $q->param('sender') ) {
						$sender = $q->param('sender');
						push @value_list, $q->param('sender');
					} else {
						push @value_list, 'null';
						$logger->error("No sender!");
					}
				} elsif ( $table eq 'sequences' && !defined $fieldorder{$_} && $locus ) {
					( my $cleaned_locus = $locus ) =~ s/'/\\'/g;
					push @value_list, "'$cleaned_locus'";
				} else {
					push @value_list, 'null';
				}
				if ( $_ eq 'scheme_id' ) {
					$schemes{ $data[ $fieldorder{'scheme_id'} ] } = 1;
				}
			}
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' && ( $table eq 'loci' || $table eq $self->{'system'}->{'view'} ) ) {
				@extras     = split /;/, $data[ $fieldorder{'aliases'} ]    if defined $fieldorder{'aliases'};
				@ref_extras = split /;/, $data[ $fieldorder{'references'} ] if defined $fieldorder{'references'};
			}
			my @inserts;
			my $qry;
			local $" = ',';
			$qry = "INSERT INTO $table (@fields_to_include) VALUES (@value_list)";
			push @inserts, $qry;
			if ( $table eq 'allele_designations' ) {
				push @history,
				  "$data[$fieldorder{'isolate_id'}]|$data[$fieldorder{'locus'}]: new designation '$data[$fieldorder{'allele_id'}]'";
			}
			$logger->debug("INSERT: $qry");
			my $curator = $self->get_curator_id;
			if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {

				#Set read ACL for 'All users' group
				push @inserts, "INSERT INTO isolate_usergroup_acl (isolate_id,user_group_id,read,write) VALUES ($id,0,true,false)";

				#Set read/write ACL for curator
				push @inserts, "INSERT INTO isolate_user_acl (isolate_id,user_id,read,write) VALUES ($id,$curator,true,true)";

				#Remove duplicate loci which may occur if they belong to more than one scheme.
				my @locus_list = uniq @$loci;
				foreach (@locus_list) {
					next if !$fieldorder{$_};
					my $value = $data[ $fieldorder{$_} ];
					$value = defined $value ? $value : '';
					$value =~ s/^\s*//g;
					$value =~ s/\s*$//g;
					if (   defined $fieldorder{$_}
						&& $value ne 'null'
						&& $value ne '' )
					{
						( my $cleaned_locus = $_ ) =~ s/'/\\'/g;
						$qry =
"INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,date_entered,datestamp) VALUES ('$id',E'$cleaned_locus','$value','$sender','confirmed','manual','$curator','today','today')";
						push @inserts, $qry;
						$logger->debug("INSERT: $qry");
					}
				}
				foreach (@extras) {
					next if $_ eq 'null';
					$_ =~ s/^\s*//g;
					$_ =~ s/\s*$//g;
					if ( $_ && $_ ne $id && $data[ $fieldorder{ $self->{'system'}->{'labelfield'} } ] ne 'null' ) {
						$qry = "INSERT INTO isolate_aliases (isolate_id,alias,curator,datestamp) VALUES ($id,'$_',$curator,'today')";
						push @inserts, $qry;
						$logger->debug("INSERT: $qry");
					}
				}
				foreach (@ref_extras) {
					next if $_ eq 'null';
					$_ =~ s/^\s*//g;
					$_ =~ s/\s*$//g;
					if ( $_ && $_ ne $id && $data[ $fieldorder{ $self->{'system'}->{'labelfield'} } ] ne 'null' ) {
						if ( BIGSdb::Utils::is_int($_) ) {
							$qry = "INSERT INTO refs (isolate_id,pubmed_id,curator,datestamp) VALUES ($id,$_,$curator,'today')";
							push @inserts, $qry;
							$logger->debug("INSERT: $qry");
						}
					}
				}
			} elsif ( $table eq 'loci' ) {
				foreach (@extras) {
					$_ =~ s/^\s*//g;
					$_ =~ s/\s*$//g;
					if ( $_ && $_ ne $id && $_ ne 'null' ) {
						$qry =
						  "INSERT INTO locus_aliases (locus,alias,use_alias,curator,datestamp) VALUES ('$id','$_','TRUE',$curator,'today')";
						push @inserts, $qry;
						$logger->debug("INSERT: $qry");
					}
				}
			} elsif ( $table eq 'users' ) {
				$qry = "INSERT INTO user_group_members (user_id,user_group,curator,datestamp) VALUES ($id,0,$curator,'today')";
				push @inserts, $qry;
				$logger->debug("INSERT: $qry");
			} elsif ( $table eq 'sequences' ) {
				( my $cleaned_locus = $locus // $data[ $fieldorder{'locus'} ] ) =~ s/'/\\'/g;
				( my $allele_id = $data[ $fieldorder{'allele_id'} ] ) =~ s/'/\\'/g;
				if ( $locus && ref $extended_attributes eq 'ARRAY' ) {
					my @values;
					foreach (@$extended_attributes) {
						( my $cleaned_field = $_ ) =~ s/'/\\'/g;
						if (   defined $fieldorder{$_}
							&& defined $data[ $fieldorder{$_} ]
							&& $data[ $fieldorder{$_} ] ne ''
							&& $data[ $fieldorder{$_} ] ne 'null' )
						{
							push @inserts,
"INSERT INTO sequence_extended_attributes (locus,field,allele_id,value,datestamp,curator) VALUES (E'$cleaned_locus',E'$cleaned_field',E'$allele_id','$data[$fieldorder{$_}]','today',$curator)";
						}
					}
				}
				if (   ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes'
					&& defined $fieldorder{'flags'}
					&& $data[ $fieldorder{'flags'} ] ne 'null' )
				{
					my @flags = split /;/, $data[ $fieldorder{'flags'} ];
					foreach (@flags) {
						push @inserts,
"INSERT INTO allele_flags (locus,allele_id,flag,datestamp,curator) VALUES (E'$cleaned_locus',E'$allele_id','$_','today',$curator)";
					}
				}
				$self->mark_cache_stale;
			}
			local $" = ';';
			eval {
				$self->{'db'}->do("@inserts");
				if ( ( $table eq 'scheme_members' || $table eq 'scheme_fields' ) && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
					foreach ( keys %schemes ) {
						$self->remove_profile_data($_);
						$self->drop_scheme_view($_);
						$self->create_scheme_view($_);
					}
				}
			};
			if ($@) {
				my $err = $@;
				print
"<div class=\"box\" id=\"statusbad\"><p>Database update failed - transaction cancelled - no records have been touched.</p>\n";
				if ( $err =~ /duplicate/ && $err =~ /unique/ ) {
					print
"<p>Data entry would have resulted in records with either duplicate ids or another unique field with duplicate values.</p>\n";
				} else {
					print "<p>An error has occurred - more details will be available in the server log.</p>\n";
					$logger->error($err);
				}
				print "</div>\n";
				$self->{'db'}->rollback;
				return;
			}
		}
	}
	$self->{'db'}->commit
	  && print "<div class=\"box\" id=\"resultsheader\"><p>Database updated ok</p>";
	foreach (@history) {
		my ( $isolate_id, $action ) = split /\|/, $_;
		$self->update_history( $isolate_id, $action );
	}
	print "<p><a href=\"" . $q->script_name . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	my $type  = $self->get_record_name($table) || '';
	return "Batch add new $type records - $desc";
}

sub _get_fields_in_order {

	#Return list of fields in order
	my ( $self, $table ) = @_;
	my @fieldnums;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		foreach ( @{ $self->{'xmlHandler'}->get_field_list() } ) {
			push @fieldnums, $_;
			if ( $_ eq $self->{'system'}->{'labelfield'} ) {
				push @fieldnums, 'aliases';
				push @fieldnums, 'references';
			}
		}
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach (@$attributes) {
			push @fieldnums, $_->{'name'};
			if ( $table eq 'loci' && $self->{'system'}->{'dbtype'} eq 'isolates' && $_->{'name'} eq 'id' ) {
				push @fieldnums, 'aliases';
			}
		}
	}
	return @fieldnums;
}

sub _get_field_table_header {
	my ( $self, $table ) = @_;
	my @headers;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		foreach ( @{ $self->{'xmlHandler'}->get_field_list } ) {
			push @headers, $_;
			if ( $_ eq $self->{'system'}->{'labelfield'} ) {
				push @headers, 'aliases';
				push @headers, 'references';
			}
		}
		push @headers, 'loci';
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach (@$attributes) {
			push @headers, $_->{'name'};
			if ( $table eq 'loci' && $self->{'system'}->{'dbtype'} eq 'isolates' && $_->{'name'} eq 'id' ) {
				push @headers, 'aliases';
			}
		}
		if ( $self->{'system'}->{'dbtype'} eq 'sequences' && $table eq 'sequences' ) {
			if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
				push @headers, 'flags';
			}
			if ( $self->{'cgi'}->param('locus') ) {
				my $extended_attributes_ref =
				  $self->{'datastore'}->run_list_query( "SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order",
					$self->{'cgi'}->param('locus') );
				if ( ref $extended_attributes_ref eq 'ARRAY' ) {
					push @headers, @$extended_attributes_ref;
				}
			}
		}
	}
	local $" = "</th><th>";
	return "<th>@headers</th>";
}

sub _is_id_used {
	my ( $self, $table, $id ) = @_;
	my $qry = "SELECT count(id) FROM $table WHERE id=?";
	if ( !$self->{'sql'}->{'id_used'} ) {
		$self->{'sql'}->{'id_used'} = $self->{'db'}->prepare($qry);
	}
	eval { $self->{'sql'}->{'id_used'}->execute($id) };
	$logger->error($@) if $@;
	my ($used) = $self->{'sql'}->{'id_used'}->fetchrow_array;
	return $used;
}

sub _process_fields {
	my ( $self, $data ) = @_;
	my @return_data;
	foreach my $value (@$data) {
		$value =~ s/^\s+//;
		$value =~ s/\s+$//;
		$value =~ s/'/\'\'/g;
		$value =~ s/\r//g;
		$value =~ s/\n/ /g;
		if ( $value eq '' ) {
			push @return_data, 'null';
		} else {
			push @return_data, $value;
		}
	}
	return @return_data;
}

sub _convert_query {
	my ( $self, $table, $qry ) = @_;
	return if !$self->{'datastore'}->is_table($table);
	if ( any { lc($qry) =~ /;\s*$_\s/ } (qw (insert delete update alter create drop)) ) {
		$logger->warn("Malicious SQL injection attempt '$qry'");
		return;
	}
	my $data;
	if ( $table eq 'project_members' ) {
		my $project_id = $self->{'cgi'}->param('project');
		$data = "project_id\tisolate_id\n";
		$qry =~ s/SELECT \*/SELECT id/;
		$qry =~ s/ORDER BY .*/ORDER BY id/;
		my $ids = $self->{'datastore'}->run_list_query($qry);
		$data .= "$project_id\t$_\n" foreach (@$ids);
	}
	return $data;
}
1;
