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
package BIGSdb::TableAttributes;
use strict;
use warnings;
use List::MoreUtils qw(any);
use BIGSdb::Page qw(SEQ_METHODS DATABANKS SEQ_FLAGS SEQ_STATUS);

#Attributes
#hide => 'yes': Do not display in results table and do not return field values in query
#hide_public =>'yes': Only display in results table in curation interface
#hide_query => 'yes': Do not display in results table or allow querying but do return field values in query
sub get_isolate_aliases_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int',  required => 'yes', primary_key => 'yes', foreign_key => 'isolates' },
		{ name => 'alias',      type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'datestamp',  type => 'date', required => 'yes' },
		{ name => 'curator', type => 'int', required => 'yes', dropdown_query => 'yes' }
	];
	return $attributes;
}

sub get_users_table_attributes {
	my ($self) = @_;
	my $status = ( $self->{'system'}->{'dbtype'} // '' ) eq 'isolates' ? 'user;curator;submitter;admin' : 'user;curator;admin';
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 'yes', length => 6,  unique         => 'yes', primary_key    => 'yes' },
		{ name => 'user_name',   type => 'text', required => 'yes', length => 12, unique         => 'yes', dropdown_query => 'yes' },
		{ name => 'surname',     type => 'text', required => 'yes', length => 40, dropdown_query => 'yes' },
		{ name => 'first_name',  type => 'text', required => 'yes', length => 40, dropdown_query => 'yes' },
		{ name => 'email',       type => 'text', required => 'yes', length => 50 },
		{ name => 'affiliation', type => 'text', required => 'yes', length => 255 },
		{ name => 'status',       type => 'text', required => 'yes', optlist => $status, default => 'user' },
		{ name => 'date_entered', type => 'date', required => 'yes' },
		{ name => 'datestamp',    type => 'date', required => 'yes' },
		{ name => 'curator', type => 'int', required => 'yes', dropdown_query => 'yes' }
	];
	return $attributes;
}

sub get_user_groups_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 'yes', length => 6,  unique => 'yes', primary_key    => 'yes' },
		{ name => 'description', type => 'text', required => 'yes', length => 60, unique => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',   type => 'date', required => 'yes' },
		{ name => 'curator', type => 'int', required => 'yes', dropdown_query => 'yes' }
	];
	return $attributes;
}

sub get_user_group_members_table_attributes {
	my $attributes = [
		{
			name           => 'user_id',
			type           => 'int',
			required       => 'yes',
			foreign_key    => 'users',
			primary_key    => 'yes',
			dropdown_query => 'yes',
			labels         => '|$surname|, |$first_name|'
		},
		{
			name           => 'user_group',
			type           => 'int',
			required       => 'yes',
			foreign_key    => 'user_groups',
			dropdown_query => 'yes',
			labels         => '|$id|) |$description|'
		},
		{ name => 'datestamp', type => 'date', required => 'yes' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' }
	];
	return $attributes;
}

sub get_curator_permissions_table_attributes {
	my ($self) = @_;
	my @optlist = $self->{'system'}->{'dbtype'} eq 'isolates'
	  ? qw (disable_access modify_users modify_usergroups set_user_passwords modify_isolates modify_projects modify_loci modify_schemes
	  modify_composites modify_field_attributes modify_value_attributes modify_probes modify_sequences modify_experiments tag_sequences
	  designate_alleles delete_all sample_management)
	  : qw(disable_access modify_users modify_usergroups set_user_passwords modify_loci modify_schemes);
	local $" = ';';
	my $attributes = [
		{
			name           => 'user_id',
			type           => 'int',
			required       => 'yes',
			foreign_key    => 'users',
			primary_key    => 'yes',
			dropdown_query => 'yes',
			labels         => '|$surname|, |$first_name|'
		},
		{ name => 'permission', type => 'text', required => 'yes', optlist        => "@optlist", primary_key => 'yes' },
		{ name => 'curator',    type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',  type => 'date', required => 'yes' },
	];
	return $attributes;
}

sub get_history_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int',       required => 'yes', primary_key => 'yes', foreign_key     => 'isolates' },
		{ name => 'timestamp',  type => 'timestamp', required => 'yes', primary_key => 'yes', query_datestamp => 'yes' },
		{ name => 'action',     type => 'text',      required => 'yes' },
		{ name => 'curator', type => 'int', required => 'yes', dropdown_query => 'yes' },
	];
	return $attributes;
}

sub get_profile_history_table_attributes {
	my $attributes = [
		{ name => 'scheme_id', type => 'int', required => 'yes', primary_key => 'yes', foreign_key => 'schemes', dropdown_query => 'yes' },
		{ name => 'profile_id', type => 'text',      required => 'yes', primary_key => 'yes' },
		{ name => 'timestamp',  type => 'timestamp', required => 'yes', primary_key => 'yes', query_datestamp => 'yes' },
		{ name => 'action',  type => 'text', required => 'yes' },
		{ name => 'curator', type => 'int',  required => 'yes', dropdown_query => 'yes' },
	];
	return $attributes;
}

sub get_loci_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'id', type => 'text', length => 50, required => 'yes', unique => 'yes', primary_key => 'yes' },
		{ name => 'formatted_name', type => 'text', hide_public => 'yes', tooltip => 'formatted name - Name with HTML formatting.' },
		{
			name        => 'common_name',
			type        => 'text',
			hide_public => 'yes',
			tooltip     => 'common name - Name that the locus is commonly known as.'
		},
		{
			name        => 'formatted_common_name',
			type        => 'text',
			hide_public => 'yes',
			tooltip     => 'formatted common name - Common name with HTML formatting.'
		},
		{ name => 'data_type', type => 'text', required => 'yes', optlist => 'DNA;peptide', default => 'DNA' },
		{
			name     => 'allele_id_format',
			type     => 'text',
			required => 'yes',
			optlist  => 'integer;text',
			default  => 'integer',
			tooltip  => 'allele id format - Format for allele identifiers'
		},
		{
			name        => 'allele_id_regex',
			type        => 'text',
			hide_public => 'yes',
			tooltip     => 'allele id regex - Regular expression that constrains allele id values.'
		},
		{ name => 'length', type => 'int', tooltip => 'length - Standard or most common length of sequences at this locus.' },
		{
			name     => 'length_varies',
			type     => 'bool',
			required => 'yes',
			default  => 'false',
			tooltip  => 'length varies - Set to true if this locus can have variable length sequences.'
		}
	];
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		push @$attributes,
		  (
			{ name => 'min_length', type => 'int', tooltip => 'minimum length - Shortest length that sequences at this locus can be.' },
			{ name => 'max_length', type => 'int', tooltip => 'maximum length - Longest length that sequences at this locus can be.' }
		  );
	}
	push @$attributes,
	  (
		{ name => 'coding_sequence', type => 'bool', required => 'yes', default => 'true' },
		{
			name    => 'orf',
			type    => 'int',
			optlist => '1;2;3;4;5;6',
			tooltip => 'open reading frame - This is used for certain analyses that require translation.'
		},
		{
			name    => 'genome_position',
			type    => 'int',
			length  => 10,
			tooltip => 'genome position - starting position in reference genome.  This is used to order concatenated output functions.'
		},
		{
			name        => 'match_longest',
			type        => 'bool',
			hide_public => 'yes',
			tooltip     => 'match longest - Only select the longest exact match when tagging/querying.  This is useful when there may be '
			  . 'overlapping alleles that are identical apart from one lacking an end sequence.'
		}
	  );
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my %defaults;
		if ( $self->{'system'}->{'default_seqdef_dbase'} ) {
			$defaults{'dbase_name'} = $self->{'system'}->{'default_seqdef_dbase'};
		}
		if ( $self->{'system'}->{'default_seqdef_config'} ) {
			@defaults{qw(dbase_table dbase_id_field dbase_id2_field dbase_seq_field)} = qw(sequences allele_id locus sequence);
			$defaults{'dbase_id2_value'} = 'PUT_LOCUS_NAME_HERE';
			my $default_script = $self->{'system'}->{'default_seqdef_script'} // '/cgi-bin/bigsdb/bigsdb.pl';
			$defaults{'description_url'} =
			  "$default_script?db=$self->{'system'}->{'default_seqdef_config'}&page=locusInfo&locus=PUT_LOCUS_NAME_HERE";
			$defaults{'url'} = "$default_script?db=$self->{'system'}->{'default_seqdef_config'}&page=alleleInfo&locus=PUT_LOCUS_NAME_HERE"
			  . "&allele_id=[?]";
		}
		push @$attributes,
		  (
			{
				name        => 'reference_sequence',
				type        => 'text',
				length      => 30000,
				hide_public => 'yes',
				tooltip     => 'reference_sequence - Used by the automated sequence comparison algorithms to identify sequences '
				  . 'matching this locus.'
			},
			{
				name        => 'pcr_filter',
				type        => 'bool',
				hide_public => 'yes',
				tooltip     => 'pcr filter - Set to true to specify that sequences used for tagging are filtered to only include regions '
				  . 'that are amplified by in silico PCR reaction.'
			},
			{
				name        => 'probe_filter',
				type        => 'bool',
				hide_public => 'yes',
				tooltip     => 'probe filter - Set to true to specify that sequences used for tagging are filtered to only include regions '
				  . 'within a specified distance of a hybdridization probe.'
			},
			{
				name     => 'dbase_name',
				type     => 'text',
				hide     => 'yes',
				length   => 60,
				comments => 'Name of the database holding allele sequences',
				default  => $defaults{'dbase_name'}
			},
			{
				name     => 'dbase_host',
				type     => 'text',
				hide     => 'yes',
				comments => 'IP address of database host',
				tooltip => 'dbase host - Leave this blank if your database engine is running on the same machine as the webserver software.'
			},
			{
				name     => 'dbase_port',
				type     => 'int',
				hide     => 'yes',
				comments => 'Network port accepting database connections',
				tooltip  => 'dbase port - This can be left blank unless the database engine is listening on a non-standard port.'
			},
			{
				name    => 'dbase_user',
				type    => 'text',
				hide    => 'yes',
				tooltip => 'dbase user - Depending on configuration of the database engine you may be able to leave this blank.'
			},
			{
				name    => 'dbase_password',
				type    => 'text',
				hide    => 'yes',
				tooltip => 'dbase password - Depending on configuration of the database engine you may be able to leave this blank.'
			},
			{
				name     => 'dbase_table',
				type     => 'text',
				hide     => 'yes',
				comments => 'Database table that holds sequence information for this locus',
				default  => $defaults{'dbase_table'}
			},
			{
				name     => 'dbase_id_field',
				type     => 'text',
				hide     => 'yes',
				comments => 'Primary field in sequence database that defines allele, e.g. \'allele_id\'',
				default  => $defaults{'dbase_id_field'}
			},
			{
				name     => 'dbase_id2_field',
				type     => 'text',
				hide     => 'yes',
				comments => 'Secondary field that defines allele, e.g. \'locus\'',
				tooltip  => 'dbase id2 field - Use where the sequence database table requires more than the id to define the allele. '
				  . 'This could, for example, be something like \'locus\' where the database table holds the sequences for multiple loci '
				  . 'and therefore has a \'locus\' field.  Leave blank if a secondary id field is not used.',
				default => $defaults{'dbase_id2_field'}
			},
			{
				name     => 'dbase_id2_value',
				type     => 'text',
				hide     => 'yes',
				comments => 'Secondary field value, e.g. locus name',
				tooltip  => 'dbase id2 value - Set the value that the secondary id field must include to select this locus.  This will '
				  . 'probably be the name of the locus.  Leave blank if a secondary id field is not used.',
				default => $defaults{'dbase_id2_value'}
			},
			{
				name     => 'dbase_seq_field',
				type     => 'text',
				hide     => 'yes',
				comments => 'Field in sequence database containing allele sequence',
				default  => $defaults{'dbase_seq_field'}
			},
			{
				name        => 'flag_table',
				type        => 'bool',
				required    => 'yes',
				hide_public => 'yes',
				default     => 'true',
				comments    => 'Seqdef database supports allele flags',
				tooltip     => 'flag_table - Set to true to specify that the seqdef database contains an allele flag table (which is the '
				  . 'case for BIGSdb versions 1.4 onwards).',
			},
			{
				name    => 'description_url',
				type    => 'text',
				length  => 150,
				hide    => 'yes',
				tooltip => 'description url - The URL used to hyperlink to locus information in the isolate information page.',
				default => $defaults{'description_url'}
			},
			{
				name    => 'url',
				type    => 'text',
				length  => 150,
				hide    => 'yes',
				tooltip => 'url - The URL used to hyperlink allele numbers in the isolate information page.  Instances of [?] within '
				  . 'the URL will be substituted with the allele id.',
				default => $defaults{'url'}
			},
			{
				name     => 'isolate_display',
				type     => 'text',
				required => 'yes',
				optlist  => 'allele only;sequence;hide',
				default  => 'allele only',
				tooltip  => 'isolate display - Sets how to display the locus in the isolate info page (can be overridden '
				  . 'by user preference).'
			},
			{
				name     => 'main_display',
				type     => 'bool',
				required => 'yes',
				default  => 'false',
				tooltip  => 'main display - Sets whether to display locus in isolate query results table (can be overridden '
				  . 'by user preference).'
			},
			{
				name     => 'query_field',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip  => 'query field - Sets whether this locus can be used in isolate queries (can be overridden by user preference).'
			},
			{
				name     => 'analysis',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip  => 'analysis - Sets whether to include this locus in analysis functions (can be overridden by user preference).'
			}
		  );
	}
	push @$attributes,
	  (
		{ name => 'curator',      type => 'int',  required => 'yes', dropdown_query => 'yes', hide => 'yes' },
		{ name => 'date_entered', type => 'date', required => 'yes', hide           => 'yes' },
		{ name => 'datestamp',    type => 'date', required => 'yes', hide           => 'yes' }
	  );
	return $attributes;
}

sub get_pcr_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 'yes', unique   => 'yes', primary_key => 'yes' },
		{ name => 'description', type => 'text', length   => '50',  required => 'yes' },
		{ name => 'primer1', type => 'text', length => '128', required => 'yes', regex => '^[ACGTURYSWKMBDHVNacgturyswkmbdhvn ]+$' },
		{ name => 'primer2', type => 'text', length => '128', required => 'yes', regex => '^[ACGTURYSWKMBDHVNacgturyswkmbdhvn ]+$' },
		{ name => 'min_length', type => 'int', comments => 'Minimum length of product to return' },
		{ name => 'max_length', type => 'int', comments => 'Maximum length of product to return' },
		{
			name     => 'max_primer_mismatch',
			type     => 'int',
			optlist  => '0;1;2;3;4;5',
			comments => 'Maximum sequence mismatch per primer',
			tooltip  => 'max primer mismatch - Do not set this too high or the reactions will run slowly.'
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_pcr_locus_table_attributes {
	my $attributes = [
		{
			name           => 'pcr_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'pcr',
			dropdown_query => 'yes',
			labels         => '|$id|) |$description|',
		},
		{ name => 'locus',     type => 'text', required => 'yes', primary_key    => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_probes_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 'yes', unique   => 'yes', primary_key => 'yes' },
		{ name => 'description', type => 'text', length   => '50',  required => 'yes' },
		{ name => 'sequence', type => 'text', length => '2048', required => 'yes', regex => '^[ACGTURYSWKMBDHVNacgturyswkmbdhvn ]+$' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_probe_locus_table_attributes {
	my $attributes = [
		{
			name           => 'probe_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'probes',
			dropdown_query => 'yes',
			labels         => '|$id|) |$description|',
		},
		{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'max_distance', type => 'int', required => 'yes', comments => 'Maximum distance of probe from end of locus' },
		{ name => 'min_alignment', type => 'int',  comments => 'Minimum length of alignment (default: length of probe)' },
		{ name => 'max_mismatch',  type => 'int',  comments => 'Maximum sequence mismatch (default: 0)' },
		{ name => 'max_gaps',      type => 'int',  comments => 'Maximum gaps in alignment (default: 0)' },
		{ name => 'curator',       type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',     type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_locus_aliases_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'alias', type => 'text', required => 'yes', primary_key => 'yes' }
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes, ( { name => 'use_alias', type => 'bool', required => 'yes', default => 'true' } );
	}
	push @$attributes,
	  (
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	  );
	return $attributes;
}

sub get_locus_links_table_attributes {
	my $attributes = [
		{ name => 'locus',       type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'url',         type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'description', type => 'text', length   => 256 },
		{ name => 'link_order',  type => 'int',  length   => 4 },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_locus_refs_table_attributes {
	my $attributes = [
		{ name => 'locus',     type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'pubmed_id', type => 'int',  required => 'yes', primary_key => 'yes' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_locus_extended_attributes_table_attributes {
	my $attributes = [
		{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'field', type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'value_format', type => 'text', required => 'yes', optlist => 'integer;text;boolean', default => 'text' },
		{ name => 'value_regex', type => 'text', tooltip => 'value regex - Regular expression that constrains values.' },
		{ name => 'description', type => 'text', length  => 256 },
		{ name => 'option_list', type => 'text', length  => 128, tooltip => 'option list - \'|\' separated list of allowed values.' },
		{ name => 'length', type => 'integer' },
		{
			name     => 'required',
			required => 'yes',
			type     => 'bool',
			default  => 'false',
			tooltip  => 'required - Specifies whether value is required for each sequence.'
		},
		{ name => 'field_order', type => 'int',  length   => 4 },
		{ name => 'curator',     type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',   type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_locus_descriptions_table_attributes {
	my $attributes = [
		{ name => 'locus',       type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'full_name',   type => 'text', length   => 120 },
		{ name => 'product',     type => 'text', length   => 120 },
		{ name => 'description', type => 'text', length   => 2048 },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_sequence_extended_attributes_table_attributes {
	my $attributes = [
		{ name => 'locus',     type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'field',     type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'allele_id', type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'value',     type => 'text', required => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' },
		{ name => 'curator', type => 'int', required => 'yes', dropdown_query => 'yes' }
	];
	return $attributes;
}

sub get_client_dbases_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 'yes', primary_key => 'yes' },
		{ name => 'name',        type => 'text', required => 'yes', length      => 30 },
		{ name => 'description', type => 'text', required => 'yes', length      => 256 },
		{
			name     => 'dbase_name',
			type     => 'text',
			required => 'yes',
			hide     => 'yes',
			length   => 60,
			comments => 'Name of the database holding isolate data'
		},
		{
			name     => 'dbase_config_name',
			type     => 'text',
			required => 'yes',
			hide     => 'yes',
			length   => 60,
			comments => 'Name of the database configuration'
		},
		{
			name     => 'dbase_host',
			type     => 'text',
			hide     => 'yes',
			comments => 'IP address of database host',
			tooltip  => 'dbase_host - Leave this blank if your database engine is running on the same machine as the webserver software.'
		},
		{
			name     => 'dbase_port',
			type     => 'int',
			hide     => 'yes',
			comments => 'Network port accepting database connections',
			tooltip  => 'dbase_port - This can be left blank unless the database engine is listening on a non-standard port.'
		},
		{
			name    => 'dbase_user',
			type    => 'text',
			hide    => 'yes',
			tooltip => 'dbase_user - Depending on configuration of the database engine you may be able to leave this blank.'
		},
		{
			name    => 'dbase_password',
			type    => 'text',
			hide    => 'yes',
			tooltip => 'dbase_password - Depending on configuration of the database engine you may be able to leave this blank.'
		},
		{ name => 'dbase_view', type => 'text', required => 'no',  comments       => 'View of isolates table to use' },
		{ name => 'url',        type => 'text', length   => 80,    required       => 'no', comments => 'Web URL to database script' },
		{ name => 'curator',    type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_client_dbase_loci_fields_table_attributes {
	my $attributes = [
		{
			name           => 'client_dbase_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'client_dbases',
			labels         => '|$id|) |$name|',
			dropdown_query => 'yes'
		},
		{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'isolate_field', type => 'text', length => 50, required => 'yes', primary_key => 'yes' },
		{
			name     => 'allele_query',
			type     => 'bool',
			default  => 'true',
			comments => 'set to true to display field values when an allele query is done.'
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_experiments_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  length   => 10,    required       => 'yes', primary_key => 'yes' },
		{ name => 'description', type => 'text', required => 'yes', length         => 48,    unique      => 'yes' },
		{ name => 'curator',     type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',   type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_experiment_sequences_table_attributes {
	my $attributes = [
		{
			name           => 'experiment_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'experiments',
			labels         => '|$id|) |$description|',
			dropdown_query => 'yes'
		},
		{ name => 'seqbin_id', type => 'int',  required => 'yes', primary_key    => 'yes', foreign_key => 'sequence_bin' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_client_dbase_loci_table_attributes {
	my $attributes = [
		{
			name           => 'client_dbase_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'client_dbases',
			labels         => '|$id|) |$name|',
			dropdown_query => 'yes'
		},
		{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{
			name     => 'locus_alias',
			type     => 'text',
			required => 'no',
			comments => 'name that this locus is referred by in client database (if different)'
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_client_dbase_schemes_table_attributes {
	my $attributes = [
		{
			name           => 'client_dbase_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'client_dbases',
			labels         => '|$id|) |$name|',
			dropdown_query => 'yes'
		},
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$description|',
			dropdown_query => 'yes'
		},
		{ name => 'client_scheme_id', type => 'int',  comments => 'id number of the scheme in the client database (if different)' },
		{ name => 'curator',          type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',        type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_refs_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int',  required => 'yes', primary_key    => 'yes', foreign_key => 'isolates' },
		{ name => 'pubmed_id',  type => 'int',  required => 'yes', primary_key    => 'yes' },
		{ name => 'curator',    type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',  type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_sequence_refs_table_attributes {
	my $attributes = [
		{ name => 'locus',     type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'allele_id', type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'pubmed_id', type => 'int',  required => 'yes', primary_key => 'yes' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_allele_flags_table_attributes {
	my $attributes = [
		{ name => 'locus',     type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'allele_id', type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'flag',      type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_profile_refs_table_attributes {
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$description|',
			dropdown_query => 'yes'
		},
		{ name => 'profile_id', type => 'text', required => 'yes', primary_key    => 'yes' },
		{ name => 'pubmed_id',  type => 'int',  required => 'yes', primary_key    => 'yes' },
		{ name => 'curator',    type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',  type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_allele_designations_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int',  required => 'yes', primary_key => 'yes', foreign_key => 'isolates' },
		{ name => 'locus',      type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'allele_id', type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'sender',    type => 'int',  required => 'yes', foreign_key => 'users', dropdown_query => 'yes' },
		{ name => 'status', type => 'text', required => 'yes', optlist => 'confirmed;provisional;ignore', default => 'confirmed' },
		{ name => 'method',       type => 'text', required => 'yes', optlist        => 'manual;automatic', default => 'manual' },
		{ name => 'curator',      type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',    type => 'date', required => 'yes' },
		{ name => 'date_entered', type => 'date', required => 'yes' },
		{ name => 'comments',     type => 'text', length   => 64 }
	];
	return $attributes;
}

sub get_schemes_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'id', type => 'int', required => 'yes', unique => 'yes', primary_key => 'yes' },
		{
			name     => 'description',
			type     => 'text',
			required => 'yes',
			length   => 50,
			tooltip  => 'description - Ensure this is short since it is used in table headings and drop-down lists.'
		}
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  (
			{
				name        => 'dbase_name',
				type        => 'text',
				hide_public => 'yes',
				tooltip     => 'dbase_name - Name of the database holding profile or field information for this scheme',
				length      => 60
			},
			{
				name        => 'dbase_host',
				type        => 'text',
				hide_public => 'yes',
				tooltip => 'dbase_host - Leave this blank if your database engine is running on the same machine as the webserver software.'
			},
			{
				name        => 'dbase_port',
				type        => 'int',
				hide_public => 'yes',
				tooltip => 'dbase_port - Leave this blank if your database engine is running on the same machine as the webserver software.'
			},
			{
				name    => 'dbase_user',
				type    => 'text',
				hide    => 'yes',
				tooltip => 'dbase_user - Depending on configuration of the database engine you may be able to leave this blank.'
			},
			{
				name    => 'dbase_password',
				type    => 'text',
				hide    => 'yes',
				tooltip => 'dbase_password - Depending on configuration of the database engine you may be able to leave this blank.'
			},
			{
				name        => 'dbase_table',
				type        => 'text',
				hide_public => 'yes',
				tooltip     => 'dbase_table - Database table that holds profile or field information for this scheme.'
			},
			{
				name     => 'isolate_display',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip  => 'isolate_display - Sets whether to display the scheme in the isolate info page, setting to false overrides '
				  . 'values for individual loci and scheme fields (can be overridden by user preference)'
			},
			{
				name     => 'main_display',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip  => 'main_display - Sets whether to display the scheme in isolate query results table, setting to false overrides '
				  . 'values for individual loci and scheme fields (can be overridden by user preference).'
			},
			{
				name     => 'query_field',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip  => 'query_field - Sets whether this scheme can be used in isolate queries, setting to false overrides values '
				  . 'for individual loci and scheme fields (can be overridden by user preference).'
			},
			{
				name     => 'query_status',
				type     => 'bool',
				required => 'yes',
				default  => 'false',
				tooltip  => 'query_status - Sets whether a drop-down list box should be used in query interface to select profile '
				  . 'completion status for this scheme.'
			},
			{
				name     => 'analysis',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip  => 'analysis - Sets whether to include this scheme in analysis functions (can be overridden by user preference).'
			}
		  );
	}
	push @$attributes,
	  (
		{ name => 'display_order', type => 'int', hide_public => 'yes', tooltip => 'display_order - order of appearance in interface.' },
		{
			name        => 'allow_missing_loci',
			type        => 'bool',
			hide_public => 'yes',
			tooltip     => "allow_missing_loci - Allow profiles to contain '0' (locus missing) or 'N' (any allele)."
		},
		{ name => 'curator',      type => 'int',  hide_public => 'yes', required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',    type => 'date', hide_public => 'yes', required => 'yes' },
		{ name => 'date_entered', type => 'date', hide_public => 'yes', required => 'yes' }
	  );
	return $attributes;
}

sub get_scheme_members_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$description|',
			dropdown_query => 'yes'
		},
		{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' }
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  {
			name     => 'profile_name',
			type     => 'text',
			required => 'no',
			tooltip  => 'profile_name - This is the name of the locus within the sequence definition database.'
		  };
	}
	push @$attributes,
	  (
		{ name => 'field_order', type => 'int',  required => 'no' },
		{ name => 'curator',     type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',   type => 'date', required => 'yes' }
	  );
	return $attributes;
}

sub get_scheme_fields_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$description|',
			dropdown_query => 'yes'
		},
		{ name => 'field', type => 'text', required => 'yes', primary_key => 'yes', regex => '^[a-zA-Z][\w_]*$' },
		{ name => 'type',  type => 'text', required => 'yes', optlist     => 'text;integer;date' },
		{
			name     => 'primary_key',
			type     => 'bool',
			required => 'yes',
			default  => 'false',
			tooltip  => 'primary key - Sets whether this field defines a profile (you can only have one primary key field).'
		},
		{ name => 'description', type => 'text', required => 'no', length => 30, },
		{ name => 'field_order', type => 'int',  required => 'no' }
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  (
			{ name => 'url', type => 'text', required => 'no', length => 120, },
			{
				name     => 'isolate_display',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip  => 'isolate display - Sets how to display the locus in the isolate info page (can be overridden '
				  . 'by user preference).'
			},
			{
				name     => 'main_display',
				type     => 'bool',
				required => 'yes',
				default  => 'false',
				tooltip  => 'main display - Sets whether to display locus in isolate query results table (can be overridden by '
				  . 'user preference).'
			},
			{
				name     => 'query_field',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip  => 'query field - Sets whether this locus can be used in isolate queries (can be overridden by '
				  . 'user preference).'
			},
			{
				name     => 'dropdown',
				type     => 'bool',
				required => 'yes',
				default  => 'false',
				tooltip  => 'dropdown - Sets whether to display a dropdown list box in the query interface (can be overridden by '
				  . 'user preference).'
			}
		  );
	} else {
		if ( ( $self->{'system'}->{'materialized_views'} // '' ) eq 'yes' ) {
			push @$attributes,
			  (
				{
					name     => 'index',
					type     => 'bool',
					required => 'no',
					tooltip  => 'index - Sets whether the field is indexed in the database.  This setting is ignored for primary key '
					  . 'fields which are always indexed.'
				}
			  );
		}
		push @$attributes,
		  (
			{
				name     => 'dropdown',
				type     => 'bool',
				required => 'yes',
				default  => 'false',
				tooltip  => 'dropdown - Sets whether to display a dropdown list box in the query interface (can be '
				  . 'overridden by user preference).'
			}
		  );
		push @$attributes,
		  ( { name => 'value_regex', type => 'text', tooltip => 'value regex - Regular expression that constrains value of field' } );
	}
	push @$attributes,
	  (
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	  );
	return $attributes;
}

sub get_scheme_groups_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'id', type => 'int', required => 'yes', unique => 'yes', primary_key => 'yes' },
		{
			name           => 'name',
			type           => 'text',
			required       => 'yes',
			length         => 50,
			dropdown_query => 'yes',
			tooltip        => 'name - Ensure this is short since it is used in table headings and drop-down lists.'
		},
		{ name => 'description',   type => 'text', length => 256 },
		{ name => 'display_order', type => 'int' }
	];
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		push @$attributes,
		  (
			{
				name    => 'seq_query',
				type    => 'bool',
				tooltip => 'seq_query - Sets whether the group appears in the dropdown list of targets when performing a sequence query.'
			}
		  );
	}
	push @$attributes,
	  (
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	  );
	return $attributes;
}

sub get_scheme_group_scheme_members_table_attributes {
	my $attributes = [
		{
			name           => 'group_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'scheme_groups',
			labels         => '|$name|',
			dropdown_query => 'yes'
		},
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$description|',
			dropdown_query => 'yes'
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_scheme_group_group_members_table_attributes {
	my $attributes = [
		{
			name           => 'parent_group_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'scheme_groups',
			labels         => '|$name|',
			dropdown_query => 'yes'
		},
		{
			name           => 'group_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'scheme_groups',
			labels         => '|$name|',
			dropdown_query => 'yes'
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_composite_fields_table_attributes {
	my $attributes = [
		{
			name        => 'id',
			type        => 'text',
			required    => 'yes',
			primary_key => 'yes',
			comments    => 'name of the field as it will appear in the web interface'
		},
		{
			name           => 'position_after',
			type           => 'text',
			required       => 'yes',
			comments       => 'field present in the isolate table',
			dropdown_query => 'yes',
			optlist        => 'isolate_fields'
		},
		{
			name     => 'main_display',
			type     => 'bool',
			required => 'yes',
			default  => 'false',
			comments => 'Sets whether to display field in isolate query results table (can be overridden by user preference).'
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_composite_field_values_table_attributes {
	my $attributes = [
		{
			name           => 'composite_field_id',
			type           => 'text',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'composite_fields',
			dropdown_query => 'yes'
		},
		{ name => 'field_order', type => 'int', required => 'yes', primary_key => 'yes' },
		{ name => 'empty_value', type => 'text' },
		{
			name    => 'regex',
			type    => 'text',
			length  => 50,
			tooltip => 'regex - You can use regular expressions here to do some complex text manipulations on the displayed value. '
			  . 'For example: <br /><br /><b>s/ST-(\S+) complex.*/cc$1/</b><br /><br />will convert something like '
			  . '\'ST-41/44 complex/lineage III\' to \'cc41/44\''
		},
		{ name => 'field',     type => 'text', length   => 40,    required       => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' },
		{ name => 'int',       type => 'text', required => 'yes', dropdown_query => 'yes' }
	];
	return $attributes;
}

sub get_sequences_table_attributes {
	my ($self) = @_;
	my @optlist = SEQ_STATUS;
	local $" = ';';
	my $attributes = [
		{ name => 'locus',     type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'allele_id', type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'sequence',     type => 'text', required => 'yes', length         => 32768,      user_update => 'no' },
		{ name => 'status',       type => 'text', required => 'yes', optlist        => "@optlist", hide_public => 'yes' },
		{ name => 'sender',       type => 'int',  required => 'yes', dropdown_query => 'yes',      hide_public => 'yes' },
		{ name => 'curator',      type => 'int',  required => 'yes', dropdown_query => 'yes',      hide_public => 'yes' },
		{ name => 'date_entered', type => 'date', required => 'yes', hide_public    => 'yes' },
		{ name => 'datestamp',    type => 'date', required => 'yes', hide_public    => 'yes' }
	];
	if ( ( $self->{'system'}->{'allele_comments'} // '' ) eq 'yes' ) {
		push @$attributes, ( { name => 'comments', type => 'text', required => 'no', length => 120 } );
	}
	return $attributes;
}

sub get_accession_table_attributes {
	my ($self) = @_;
	my @databanks = DATABANKS;
	my $attributes;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		push @$attributes,
		  (
			{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
			{ name => 'allele_id', type => 'text', required => 'yes', primary_key => 'yes' },
		  );
	} elsif ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  ( { name => 'seqbin_id', type => 'int', required => 'yes', primary_key => 'yes', foreign_key => 'sequence_bin' } );
	}
	local $" = ';';
	push @$attributes,
	  (
		{ name => 'databank',    type => 'text', required => 'yes', primary_key    => 'yes', optlist => "@databanks" },
		{ name => 'databank_id', type => 'text', required => 'yes', primary_key    => 'yes' },
		{ name => 'curator',     type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',   type => 'date', required => 'yes' },
	  );
	return $attributes;
}

sub get_allele_sequences_table_attributes {
	my $attributes = [
		{ name => 'id',         type => 'int',  hide_query => 'yes', primary_key => 'yes' },
		{ name => 'isolate_id', type => 'int',  required   => 'yes', foreign_key => 'isolates' },
		{ name => 'seqbin_id',  type => 'int',  required   => 'yes', foreign_key => 'sequence_bin' },
		{ name => 'locus',      type => 'text', required   => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'start_pos',  type => 'int',  required   => 'yes', comments    => 'start position of locus within sequence' },
		{ name => 'end_pos',    type => 'int',  required   => 'yes', comments    => 'end position of locus within sequence' },
		{
			name     => 'reverse',
			type     => 'bool',
			required => 'yes',
			comments => 'true if sequence is reverse complemented',
			default  => 'false'
		},
		{ name => 'complete', type => 'bool', required => 'yes', comments => 'true if complete locus represented', default => 'true' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_sequence_flags_table_attributes {
	my @flags = SEQ_FLAGS;
	local $" = ';';
	my $attributes = [
		{ name => 'id',        type => 'int',  required => 'yes', primary_key    => 'yes', foreign_key => 'allele_sequences' },
		{ name => 'flag',      type => 'text', required => 'yes', optlist        => "@flags" },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_profiles_table_attributes {
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$description|',
			dropdown_query => 'yes'
		},
		{ name => 'profile_id',   type => 'text', required => 'yes', primary_key    => 'yes' },
		{ name => 'sender',       type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'curator',      type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'date_entered', type => 'date', required => 'yes' },
		{ name => 'datestamp',    type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_scheme_curators_table_attributes {
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$description|',
			dropdown_query => 'yes'
		},
		{
			name           => 'curator_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'users',
			labels         => '|$surname|, |$first_name| (|$user_name|)',
			dropdown_query => 'yes'
		}
	];
	return $attributes;
}

sub get_locus_curators_table_attributes {
	my $attributes = [
		{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{
			name           => 'curator_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'users',
			labels         => '|$surname|, |$first_name| (|$user_name|)',
			dropdown_query => 'yes'
		},
		{ name => 'hide_public', type => 'bool', comments => 'set to true to not list curator in lists', default => 'false' },
	];
	return $attributes;
}

sub get_sequence_attributes_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'key',         type => 'text', required => 'yes', primary_key => 'yes',                     regex   => '^[A-z]\w*$' },
		{ name => 'type',        type => 'text', required => 'yes', optlist     => 'text;integer;float;date', default => 'text' },
		{ name => 'description', type => 'text' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_sequence_attribute_values_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'seqbin_id', type => 'int',  required => 'yes', primary_key => 'yes', foreign_key => 'sequence_bin' },
		{ name => 'key',       type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'sequence_attributes' },
		{ name => 'value',     type => 'text', required => 'yes' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_sequence_bin_table_attributes {
	my ($self) = @_;
	my @methods = SEQ_METHODS;
	local $" = ';';
	my $attributes = [
		{ name => 'id',         type => 'int',  required => 'yes', primary_key => 'yes' },
		{ name => 'isolate_id', type => 'int',  required => 'yes', foreign_key => 'isolates' },
		{ name => 'sequence',   type => 'text', required => 'yes', length      => 2048, user_update => 'no' },
		{ name => 'method',     type => 'text', required => 'yes', optlist     => "@methods" },
		{ name => 'run_id',               type => 'text', length   => 32 },
		{ name => 'assembly_id',          type => 'text', length   => 32 },
		{ name => 'original_designation', type => 'text', length   => 100 },
		{ name => 'comments',             type => 'text', length   => 64 },
		{ name => 'sender',               type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'curator',              type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'date_entered',         type => 'date', required => 'yes' },
		{ name => 'datestamp',            type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_isolate_field_extended_attributes_table_attributes {
	my ($self) = @_;
	my $fields = $self->{'xmlHandler'}->get_field_list;
	my @select_fields;
	foreach my $field (@$fields) {
		next if any { $field eq $_ } qw (id date_entered datestamp sender curator comments);
		push @select_fields, $field;
	}
	local $" = ';';
	my $attributes = [
		{ name => 'isolate_field', type => 'text', required => 'yes', primary_key => 'yes', optlist => "@select_fields" },
		{ name => 'attribute',     type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'value_format', type => 'text', required => 'yes', optlist => 'integer;float;text;date', default => 'text' },
		{ name => 'value_regex', type => 'text', tooltip => 'value regex - Regular expression that constrains values.' },
		{ name => 'description', type => 'text', length  => 256 },
		{
			name    => 'url',
			type    => 'text',
			length  => 120,
			hide    => 'yes',
			tooltip => 'url - The URL used to hyperlink values in the isolate information page.  Instances of [?] within '
			  . 'the URL will be substituted with the value.'
		},
		{ name => 'length',      type => 'integer' },
		{ name => 'field_order', type => 'int', length => 4 },
		{ name => 'curator',     type => 'int', required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_isolate_value_extended_attributes_table_attributes {
	my ($self) = @_;
	my $fields = $self->{'xmlHandler'}->get_field_list;
	my @select_fields;
	foreach my $field (@$fields) {
		next if any { $field eq $_ } qw (id date_entered datestamp sender curator comments);
		push @select_fields, $field;
	}
	my $attributes = $self->run_query( "SELECT DISTINCT attribute FROM isolate_field_extended_attributes ORDER BY attribute",
		undef, { fetch => 'col_arrayref' } );
	local $" = ';';
	$attributes = [
		{ name => 'isolate_field', type => 'text', required => 'yes', primary_key => 'yes', optlist => "@select_fields" },
		{ name => 'attribute',     type => 'text', required => 'yes', primary_key => 'yes', optlist => "@$attributes" },
		{ name => 'field_value',   type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'value',         type => 'text', required => 'yes' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_projects_table_attributes {
	my $attributes = [
		{ name => 'id', type => 'int', required => 'yes', primary_key => 'yes' },
		{
			name           => 'short_description',
			type           => 'text',
			required       => 'yes',
			length         => 40,
			dropdown_query => 'yes',
			tooltip        => 'description - Ensure this is short since it is used in table headings and drop-down lists.'
		},
		{
			name    => 'full_description',
			type    => 'text',
			length  => 512,
			tooltip => "full description - This text will appear on the record pages of isolates belonging to the project.  You can use '
			 . 'HTML markup here.  If you don't enter anything here then the project will not be listed on the isolate record page."
		},
		{
			name    => 'isolate_display',
			type    => 'bool',
			tooltip => 'isolate display - Select to list this project on an isolate information page (also requires a full description '
			  . 'to be entered).'
		},
		{ name => 'list',      type => 'bool', tooltip  => 'list - Select to include in list of projects linked from the contents page.' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_project_members_table_attributes {
	my $attributes = [
		{
			name           => 'project_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'projects',
			labels         => '|$short_description|',
			dropdown_query => 'yes'
		},
		{ name => 'isolate_id', type => 'int',  required => 'yes', primary_key    => 'yes', foreign_key => 'isolates' },
		{ name => 'curator',    type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',  type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_sets_table_attributes {
	my $attributes = [
		{ name => 'id',               type => 'int',  required => 'yes', primary_key => 'yes' },
		{ name => 'description',      type => 'text', required => 'yes', length      => 40 },
		{ name => 'long_description', type => 'text', length   => 256 },
		{ name => 'display_order',    type => 'int' },
		{
			name    => 'hidden',
			type    => 'bool',
			tooltip => "hidden - Don't show this set in selection lists.  When selected this set can "
			  . "only be used by specifying the set_id in the database configuration file."
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_set_loci_table_attributes {
	my $attributes = [
		{
			name           => 'set_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'sets',
			labels         => '|$description|',
			dropdown_query => 'yes'
		},
		{ name => 'locus',    type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'set_name', type => 'text', length   => 40 },
		{ name => 'formatted_set_name',        type => 'text', length   => 60 },
		{ name => 'set_common_name',           type => 'text', length   => 40 },
		{ name => 'formatted_set_common_name', type => 'text', length   => 60 },
		{ name => 'curator',                   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',                 type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_set_schemes_table_attributes {
	my $attributes = [
		{
			name           => 'set_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'sets',
			labels         => '|$description|',
			dropdown_query => 'yes'
		},
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$description|',
			dropdown_query => 'yes'
		},
		{ name => 'set_name',  type => 'text', length   => 40 },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_set_metadata_table_attributes {
	my ($self) = @_;
	my $metadata = $self->{'xmlHandler'}->get_metadata_list;
	local $" = ';';
	my $attributes = [
		{
			name           => 'set_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'sets',
			labels         => '|$description|',
			dropdown_query => 'yes'
		},
		{
			name           => 'metadata_id',
			type           => 'text',
			required       => 'yes',
			primary_key    => 'yes',
			optlist        => "@$metadata",
			dropdown_query => 'yes'
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_set_view_table_attributes {
	my ($self) = @_;
	my @views = $self->{'system'}->{'views'} ? ( split /,/, $self->{'system'}->{'views'} ) : ();
	local $" = ';';
	my $attributes = [
		{
			name           => 'set_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'sets',
			labels         => '|$description|',
			dropdown_query => 'yes'
		},
		{ name => 'view',      type => 'text', required => 'yes', optlist        => "@views", dropdown_query => 'yes' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub get_samples_table_attributes {
	my ($self) = @_;
	my $fields = $self->{'xmlHandler'}->get_sample_field_list;
	if ( !@$fields ) {
		return \%;;
	}
	my $attributes;
	foreach (@$fields) {
		my $field_attributes = $self->{'xmlHandler'}->get_sample_field_attributes($_);
		my $optlist = ( $field_attributes->{'optlist'} // '' ) eq 'yes' ? $self->{'xmlHandler'}->get_field_option_list($_) : [];
		local $" = ';';
		push @$attributes,
		  (
			{
				name        => $_,
				type        => $field_attributes->{'type'},
				required    => $field_attributes->{'required'},
				primary_key => ( $_ eq 'isolate_id' || $_ eq 'sample_id' ) ? 'yes' : '',
				foreign_key => $_ eq 'isolate_id' ? 'isolates' : '',
				optlist => "@$optlist",
				main_display => $field_attributes->{'maindisplay'},
				length       => $field_attributes->{'length'} || ( $field_attributes->{'type'} eq 'int' ? 6 : 12 )
			}
		  );
	}
	return $attributes;
}
1;
