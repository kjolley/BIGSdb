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
package BIGSdb::TableAttributes;
use strict;
use warnings;
use List::MoreUtils qw(any);
use BIGSdb::Constants qw(SEQ_METHODS SEQ_STATUS SEQ_FLAGS DATABANKS IDENTITY_THRESHOLD OPERATORS);

#Attributes
#hide => 1: Do not display in results table and do not return field values in query
#hide_public =>1: Only display in results table in curation interface
#hide_query => 1: Do not display in results table or allow querying but do return field values in query
#hide_in_form => 1: Do not display in add/update forms.
sub get_isolate_aliases_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int',  required => 1, primary_key => 1, foreign_key => 'isolates' },
		{ name => 'alias',      type => 'text', required => 1, primary_key => 1 },
		{ name => 'datestamp',  type => 'date', required => 1 },
		{ name => 'curator', type => 'int', required => 1, dropdown_query => 1 }
	];
	return $attributes;
}

sub get_users_table_attributes {
	my ($self) = @_;
	my $status =
	  ( $self->{'system'}->{'dbtype'} // '' ) eq 'isolates' ? 'user;curator;submitter;admin' : 'user;curator;admin';
	my $attributes = [
		{ name => 'id', type => 'int', required => 1, length => 6, unique => 1, primary_key => 1 },
		{
			name           => 'user_name',
			type           => 'text',
			required       => 1,
			length         => 12,
			unique         => 1,
			dropdown_query => 1,
			no_user_update => 1
		},
		{ name => 'surname',      type => 'text', required => 1, length  => 40,      dropdown_query => 1 },
		{ name => 'first_name',   type => 'text', required => 1, length  => 40,      dropdown_query => 1 },
		{ name => 'email',        type => 'text', required => 1, length  => 50 },
		{ name => 'affiliation',  type => 'text', required => 1, length  => 255 },
		{ name => 'status',       type => 'text', required => 1, optlist => $status, default        => 'user' },
		{ name => 'date_entered', type => 'date', required => 1 },
		{ name => 'datestamp',    type => 'date', required => 1 },
		{ name => 'curator', type => 'int', required     => 1, dropdown_query => 1 },
		{ name => 'user_db', type => 'int', hide_in_form => 1 }
	];
	if ( ( $self->{'system'}->{'submissions'} // '' ) eq 'yes' && $self->{'config'}->{'submission_dir'} ) {
		push @$attributes,
		  {
			name     => 'submission_emails',
			type     => 'bool',
			comments => 'Receive new submission E-mails (curators only)',
			tooltip  => 'submission emails - The user will be notified of new submissions that they have sufficient '
			  . 'privileges to curate. This is only relevant to curators and admins.',
			default => 'false'
		  };
	}
	if ( $self->{'config'}->{'site_user_dbs'} ) {
		push @$attributes,
		  {
			name     => 'account_request_emails',
			type     => 'bool',
			comments => 'Receive new account request E-mails (curators only)',
			tooltip  => 'account request emails - The user will be notified if new accounts are requested. They must '
			  . 'the permission set to allow them to import site user accounts. This is only relevant to curators '
			  . 'and admins.',
			default => 'false'
		  };
	}
	return $attributes;
}

sub get_user_dbases_table_attributes {
	my $attributes = [
		{ name => 'id',   type => 'int',  required => 1, primary_key => 1 },
		{ name => 'name', type => 'text', required => 1, length      => 30, comments => 'Site/domain name' },
		{ name => 'list_order',        type => 'int' },
		{ name => 'auto_registration', type => 'bool', comments => 'Allow user to register themself for database' },
		{
			name     => 'dbase_name',
			type     => 'text',
			required => 1,
			length   => 60,
			comments => 'Name of the database holding user data'
		},
		{
			name     => 'dbase_host',
			type     => 'text',
			hide     => 1,
			comments => 'IP address of database host',
			tooltip  => 'dbase_host - Leave this blank if your database engine is running on the '
			  . 'same machine as the webserver software.'
		},
		{
			name     => 'dbase_port',
			type     => 'int',
			hide     => 1,
			comments => 'Network port accepting database connections',
			tooltip  => 'dbase_port - This can be left blank unless the database engine is '
			  . 'listening on a non-standard port.'
		},
		{
			name    => 'dbase_user',
			type    => 'text',
			hide    => 1,
			tooltip => 'dbase_user - Depending on configuration of the database engine '
			  . 'you may be able to leave this blank.'
		},
		{
			name    => 'dbase_password',
			type    => 'text',
			hide    => 1,
			tooltip => 'dbase_password - Depending on configuration of the database engine '
			  . 'you may be able to leave this blank.'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_user_groups_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'id', type => 'int', required => 1, length => 6, unique => 1, primary_key => 1 },
		{
			name           => 'description',
			type           => 'text',
			required       => 1,
			length         => 60,
			unique         => 1,
			dropdown_query => 1
		}
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  (
			{
				name     => 'co_curate',
				type     => 'bool',
				required => 1,
				default  => 'false',
				tooltip  => 'co_curate - Setting to true allows members with a status of submitter '
				  . 'to curate data of other members of the usergroup.'
			}
		  );
	}
	push @$attributes,
	  (
		{ name => 'datestamp', type => 'date', required => 1 },
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 }
	  );
	return $attributes;
}

sub get_user_group_members_table_attributes {
	my $attributes = [
		{
			name           => 'user_id',
			type           => 'int',
			required       => 1,
			foreign_key    => 'users',
			primary_key    => 1,
			dropdown_query => 1,
			user_field     => 1
		},
		{
			name           => 'user_group',
			type           => 'int',
			required       => 1,
			foreign_key    => 'user_groups',
			primary_key    => 1,
			dropdown_query => 1,
			labels         => '|$description|'
		},
		{ name => 'datestamp', type => 'date', required => 1 },
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 }
	];
	return $attributes;
}

sub get_permissions_table_attributes {
	my ($self) = @_;
	my @optlist = $self->{'system'}->{'dbtype'} eq 'isolates'
	  ? qw ( query_users modify_users modify_isolates modify_projects modify_sequences tag_sequences designate_alleles
	  modify_usergroups set_user_passwords modify_loci modify_schemes modify_composites modify_field_attributes
	  modify_value_attributes modify_sparse_fields modify_probes modify_experiments delete_all
	  import_site_users modify_site_users only_private disable_access)
	  : qw( query_users modify_users modify_usergroups set_user_passwords modify_loci modify_locus_descriptions
	  modify_schemes delete_all import_site_users modify_site_users disable_access );
	local $" = ';';
	my $attributes = [
		{
			name           => 'user_id',
			type           => 'int',
			required       => 1,
			foreign_key    => 'users',
			primary_key    => 1,
			dropdown_query => 1,
			labels         => '|$surname|, |$first_name|'
		},
		{ name => 'permission', type => 'text', required => 1, optlist        => "@optlist", primary_key => 1 },
		{ name => 'curator',    type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',  type => 'date', required => 1 },
	];
	return $attributes;
}

sub get_history_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int',       required => 1, primary_key => 1, foreign_key     => 'isolates' },
		{ name => 'timestamp',  type => 'timestamp', required => 1, primary_key => 1, query_datestamp => 1 },
		{ name => 'action',     type => 'text',      required => 1 },
		{ name => 'curator', type => 'int', required => 1, dropdown_query => 1 },
	];
	return $attributes;
}

sub get_profile_history_table_attributes {
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'schemes',
			dropdown_query => 1
		},
		{ name => 'profile_id', type => 'text',      required => 1, primary_key => 1 },
		{ name => 'timestamp',  type => 'timestamp', required => 1, primary_key => 1, query_datestamp => 1 },
		{ name => 'action',  type => 'text', required => 1 },
		{ name => 'curator', type => 'int',  required => 1, dropdown_query => 1 },
	];
	return $attributes;
}

sub get_loci_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'id', type => 'text', length => 50, required => 1, unique => 1, primary_key => 1 },
		{
			name        => 'formatted_name',
			type        => 'text',
			hide_public => 1,
			tooltip     => 'formatted name - Name with HTML formatting.'
		},
		{
			name        => 'common_name',
			type        => 'text',
			hide_public => 1,
			tooltip     => 'common name - Name that the locus is commonly known as.'
		},
		{
			name        => 'formatted_common_name',
			type        => 'text',
			hide_public => 1,
			tooltip     => 'formatted common name - Common name with HTML formatting.'
		},
		{ name => 'data_type', type => 'text', required => 1, optlist => 'DNA;peptide', default => 'DNA' },
		{
			name     => 'allele_id_format',
			type     => 'text',
			required => 1,
			optlist  => 'integer;text',
			default  => 'integer',
			tooltip  => 'allele id format - Format for allele identifiers'
		},
		{
			name        => 'allele_id_regex',
			type        => 'text',
			hide_public => 1,
			tooltip     => 'allele id regex - Regular expression that constrains allele id values.'
		},
		{
			name    => 'length',
			type    => 'int',
			tooltip => 'length - Standard or most common length of sequences at this locus.'
		},
		{
			name     => 'length_varies',
			type     => 'bool',
			required => 1,
			default  => 'false',
			tooltip  => 'length varies - Set to true if this locus can have variable length sequences.'
		}
	];
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		push @$attributes,
		  (
			{
				name    => 'min_length',
				type    => 'int',
				tooltip => 'minimum length - Shortest length that sequences at this locus can be.'
			},
			{
				name    => 'max_length',
				type    => 'int',
				tooltip => 'maximum length - Longest length that sequences at this locus can be.'
			}
		  );
	}
	push @$attributes,
	  (
		{ name => 'coding_sequence', type => 'bool', required => 1, default => 'true' },
		{
			name        => 'complete_cds',
			type        => 'bool',
			hide_public => 1,
			tooltip     => 'complete cds - Sequences should be complete reading frames with a start '
			  . 'and stop codon and no internal stop codons.'
		},
		{
			name        => 'orf',
			type        => 'int',
			optlist     => '1;2;3;4;5;6',
			hide_public => 1,
			tooltip     => 'open reading frame - This is used for certain analyses that require translation.'
		},
		{
			name        => 'genome_position',
			type        => 'int',
			length      => 10,
			hide_public => 1,
			tooltip     => 'genome position - starting position in reference genome.  '
			  . 'This is used to order concatenated output functions.'
		},
		{
			name        => 'match_longest',
			type        => 'bool',
			hide_public => 1,
			tooltip     => 'match longest - Only select the longest exact match when tagging/querying.  '
			  . 'This is useful when there may be overlapping alleles that are identical apart '
			  . 'from one lacking an end sequence.'
		}
	  );
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my %defaults;
		if ( $self->{'system'}->{'default_seqdef_dbase'} ) {
			$defaults{'dbase_name'} = $self->{'system'}->{'default_seqdef_dbase'};
		}
		if ( $self->{'system'}->{'default_seqdef_config'} ) {
			$defaults{'dbase_id'} = 'PUT_LOCUS_NAME_HERE';
			my $default_script = $self->{'system'}->{'default_seqdef_script'} // '/cgi-bin/bigsdb/bigsdb.pl';
			$defaults{'description_url'} = "$default_script?db=$self->{'system'}->{'default_seqdef_config'}&"
			  . 'page=locusInfo&locus=PUT_LOCUS_NAME_HERE';
			$defaults{'url'} = "$default_script?db=$self->{'system'}->{'default_seqdef_config'}&"
			  . 'page=alleleInfo&locus=PUT_LOCUS_NAME_HERE&allele_id=[?]';
		}
		push @$attributes,
		  (
			{
				name        => 'reference_sequence',
				type        => 'text',
				length      => 30000,
				hide_public => 1,
				tooltip     => 'reference_sequence - Used by the automated sequence comparison algorithms '
				  . 'to identify sequences matching this locus.'
			},
			{
				name        => 'pcr_filter',
				type        => 'bool',
				hide_public => 1,
				comments    => 'Do NOT set to true unless you define PCR reactions linked to this locus.',
				tooltip     => 'pcr filter - Set to true to specify that sequences used for tagging are filtered '
				  . 'to only include regions that are amplified by <i>in silico</i> PCR reaction. If you do not also '
				  . 'define the PCR reactions, and link them to this locus, you will prevent scan/tagging of '
				  . 'this locus.'
			},
			{
				name        => 'probe_filter',
				type        => 'bool',
				hide_public => 1,
				comments    => 'Do NOT set to true unless you define probe sequences linked to this locus.',
				tooltip     => 'probe filter - Set to true to specify that sequences used for tagging are filtered '
				  . 'to only include regions within a specified distance of a hybdridization probe.'
			}
		  );
		if ( $self->{'config'}->{'blat_path'} ) {
			push @$attributes,
			  (
				{
					name        => 'introns',
					type        => 'bool',
					hide_public => 1,
					comments    => 'Set to true if locus can contain introns.'
				}
			  );
		}
		push @$attributes,
		  (
			{
				name     => 'dbase_name',
				type     => 'text',
				hide     => 1,
				length   => 60,
				comments => 'Name of the database holding allele sequences',
				default  => $defaults{'dbase_name'}
			},
			{
				name     => 'dbase_host',
				type     => 'text',
				hide     => 1,
				comments => 'IP address of database host',
				tooltip  => 'dbase host - Leave this blank if your database engine is running on the same '
				  . 'machine as the webserver software.'
			},
			{
				name     => 'dbase_port',
				type     => 'int',
				hide     => 1,
				comments => 'Network port accepting database connections',
				tooltip  => 'dbase port - This can be left blank unless the database engine is '
				  . 'listening on a non-standard port.'
			},
			{
				name    => 'dbase_user',
				type    => 'text',
				hide    => 1,
				tooltip => 'dbase user - Depending on configuration of the database engine you '
				  . 'may be able to leave this blank.'
			},
			{
				name    => 'dbase_password',
				type    => 'text',
				hide    => 1,
				tooltip => 'dbase password - Depending on configuration of the database engine '
				  . 'you may be able to leave this blank.'
			},
			{
				name     => 'dbase_id',
				type     => 'text',
				hide     => 1,
				comments => 'Name of locus in seqdef database',
				default  => $defaults{'dbase_id'}
			},
			{
				name    => 'description_url',
				type    => 'text',
				length  => 150,
				hide    => 1,
				tooltip => 'description url - The URL used to hyperlink to locus information in '
				  . 'the isolate information page.',
				default => $defaults{'description_url'}
			},
			{
				name    => 'url',
				type    => 'text',
				length  => 150,
				hide    => 1,
				tooltip => 'url - The URL used to hyperlink allele numbers in the isolate information '
				  . 'page.  Instances of [?] within the URL will be substituted with the allele id.',
				default => $defaults{'url'}
			},
			{
				name     => 'isolate_display',
				type     => 'text',
				required => 1,
				optlist  => 'allele only;sequence;hide',
				default  => 'allele only',
				tooltip  => 'isolate display - Sets how to display the locus in the isolate info page '
				  . '(can be overridden by user preference).'
			},
			{
				name     => 'main_display',
				type     => 'bool',
				required => 1,
				default  => 'false',
				tooltip  => 'main display - Sets whether to display locus in isolate query results '
				  . 'table (can be overridden by user preference).'
			},
			{
				name     => 'query_field',
				type     => 'bool',
				required => 1,
				default  => 'true',
				tooltip  => 'query field - Sets whether this locus can be used in isolate queries '
				  . '(can be overridden by user preference).'
			},
			{
				name     => 'analysis',
				type     => 'bool',
				required => 1,
				default  => 'true',
				tooltip  => 'analysis - Sets whether to include this locus in analysis functions '
				  . '(can be overridden by user preference).'
			},
			{
				name        => 'submission_template',
				type        => 'bool',
				hide_public => 1,
				default     => 'false',
				comments    => 'Include column in isolate submission template for this locus',
				tooltip     => 'submission_template - Do not include too many loci by default as the submission '
				  . 'template will become unwieldy.'
			}
		  );
		if ( $self->{'system'}->{'views'} ) {
			my @views = split /,/x, $self->{'system'}->{'views'};
			local $" = q(;);
			push @$attributes,
			  (
				{
					name    => 'view',
					type    => 'text',
					optlist => qq(@views),
					tooltip => 'view - restrict locus to only isolates belonging to specified database view.'
				}
			  );
		}
	} else {    #Seqdef database
		my $id_threshold = IDENTITY_THRESHOLD;
		push @$attributes,
		  {
			name        => 'no_submissions',
			type        => 'bool',
			hide_public => 1,
			comments    => 'Set to true to prevent submission of alleles of this '
			  . 'locus via the automated submission system.'
		  },
		  {
			name     => 'id_check_type_alleles',
			type     => 'bool',
			comments => 'Select to only use type alleles when checking similarity '
			  . 'of new alleles to existing sequences.',
			tooltip => 'id_check_type_alleles - You must ensure that you define type alleles if you use this.'
		  },
		  {
			name     => 'id_check_threshold',
			type     => 'float',
			comments => q(Set the percentage threshold for the identity match to existing )
			  . qq(alleles when adding new alleles. Leave blank to use the default ($id_threshold%).)
		  };
	}
	push @$attributes,
	  (
		{ name => 'curator',      type => 'int',  required => 1, dropdown_query => 1, hide => 1 },
		{ name => 'date_entered', type => 'date', required => 1, hide           => 1 },
		{ name => 'datestamp',    type => 'date', required => 1, hide           => 1 }
	  );
	return $attributes;
}

sub get_pcr_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 1,    unique   => 1, primary_key => 1 },
		{ name => 'description', type => 'text', length   => '50', required => 1 },
		{
			name     => 'primer1',
			type     => 'text',
			length   => '128',
			required => 1,
			regex    => '^[ACGTURYSWKMBDHVNacgturyswkmbdhvn ]+$'
		},
		{
			name     => 'primer2',
			type     => 'text',
			length   => '128',
			required => 1,
			regex    => '^[ACGTURYSWKMBDHVNacgturyswkmbdhvn ]+$'
		},
		{ name => 'min_length', type => 'int', comments => 'Minimum length of product to return' },
		{ name => 'max_length', type => 'int', comments => 'Maximum length of product to return' },
		{
			name     => 'max_primer_mismatch',
			type     => 'int',
			optlist  => '0;1;2;3;4;5',
			comments => 'Maximum sequence mismatch per primer',
			tooltip  => 'max primer mismatch - Do not set this too high or the reactions will run slowly.'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_pcr_locus_table_attributes {
	my $attributes = [
		{
			name           => 'pcr_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'pcr',
			dropdown_query => 1,
			labels         => '|$id|) |$description|',
		},
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_probes_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 1,    unique   => 1, primary_key => 1 },
		{ name => 'description', type => 'text', length   => '50', required => 1 },
		{
			name     => 'sequence',
			type     => 'text',
			length   => '2048',
			required => 1,
			regex    => '^[ACGTURYSWKMBDHVNacgturyswkmbdhvn ]+$'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_probe_locus_table_attributes {
	my $attributes = [
		{
			name           => 'probe_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'probes',
			dropdown_query => 1,
			labels         => '|$id|) |$description|',
		},
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{
			name     => 'max_distance',
			type     => 'int',
			required => 1,
			comments => 'Maximum distance of probe from end of locus'
		},
		{
			name     => 'min_alignment',
			type     => 'int',
			comments => 'Minimum length of alignment (default: length of probe)'
		},
		{ name => 'max_mismatch', type => 'int',  comments => 'Maximum sequence mismatch (default: 0)' },
		{ name => 'max_gaps',     type => 'int',  comments => 'Maximum gaps in alignment (default: 0)' },
		{ name => 'curator',      type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',    type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_locus_aliases_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'alias', type => 'text', required => 1, primary_key => 1 }
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes, ( { name => 'use_alias', type => 'bool', required => 1, default => 'true' } );
	}
	push @$attributes,
	  (
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	  );
	return $attributes;
}

sub get_locus_links_table_attributes {
	my $attributes = [
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'url',         type => 'text', required => 1, primary_key    => 1 },
		{ name => 'description', type => 'text', required => 1, length         => 256 },
		{ name => 'link_order',  type => 'int',  length   => 4 },
		{ name => 'curator',     type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',   type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_locus_refs_table_attributes {
	my $attributes = [
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'pubmed_id', type => 'int',  required => 1, primary_key    => 1 },
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_retired_allele_ids_table_attributes {
	my $attributes = [
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'allele_id', type => 'string', required => 1, primary_key    => 1 },
		{ name => 'curator',   type => 'int',    required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date',   required => 1 }
	];
	return $attributes;
}

sub get_retired_profiles_table_attributes {
	my $attributes = [
		{
			name            => 'scheme_id',
			type            => 'int',
			required        => 1,
			primary_key     => 1,
			foreign_key     => 'schemes',
			labels          => '|$name| (id |$id|)',
			dropdown_query  => 1,
			with_pk_only    => 1,
			is_curator_only => 1
		},
		{ name => 'profile_id', type => 'text', required => 1, primary_key    => 1 },
		{ name => 'curator',    type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',  type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_retired_isolates_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int',  required => 1, primary_key    => 1 },
		{ name => 'curator',    type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',  type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_locus_extended_attributes_table_attributes {
	my $attributes = [
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'field', type => 'text', required => 1, primary_key => 1 },
		{
			name     => 'value_format',
			type     => 'text',
			required => 1,
			optlist  => 'integer;text;boolean',
			default  => 'text'
		},
		{
			name    => 'value_regex',
			type    => 'text',
			tooltip => 'value regex - Regular expression that constrains values.'
		},
		{ name => 'description', type => 'text', length => 256 },
		{
			name    => 'option_list',
			type    => 'text',
			length  => 128,
			tooltip => q(option list - '|' separated list of allowed values.)
		},
		{
			name    => 'url',
			type    => 'text',
			length  => 100,
			tooltip => 'url - URL to for hyperlinking value. The term [?] will be substituted by the value'
		},
		{ name => 'length', type => 'integer' },
		{
			name     => 'required',
			required => 1,
			type     => 'bool',
			default  => 'false',
			tooltip  => 'required - Specifies whether value is required for each sequence.'
		},
		{ name => 'field_order', type => 'int', length => 4 },
		{
			name     => 'main_display',
			type     => 'bool',
			required => 1,
			default  => 'true',
			tooltip  => 'main display - Specifies whether to display field in main results table.'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_locus_descriptions_table_attributes {
	my $attributes = [
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'full_name',   type => 'text', length   => 120 },
		{ name => 'product',     type => 'text', length   => 120 },
		{ name => 'description', type => 'text', length   => 2048 },
		{ name => 'curator',     type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',   type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_sequence_extended_attributes_table_attributes {
	my $attributes = [
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'field',     type => 'text', required => 1, primary_key    => 1 },
		{ name => 'allele_id', type => 'text', required => 1, primary_key    => 1 },
		{ name => 'value',     type => 'text', required => 1 },
		{ name => 'datestamp', type => 'date', required => 1 },
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 }
	];
	return $attributes;
}

sub get_client_dbases_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 1, primary_key => 1 },
		{ name => 'name',        type => 'text', required => 1, length      => 30 },
		{ name => 'description', type => 'text', required => 1, length      => 256 },
		{
			name     => 'dbase_name',
			type     => 'text',
			required => 1,
			hide     => 1,
			length   => 60,
			comments => 'Name of the database holding isolate data'
		},
		{
			name     => 'dbase_config_name',
			type     => 'text',
			required => 1,
			hide     => 1,
			length   => 60,
			comments => 'Name of the database configuration'
		},
		{
			name     => 'dbase_host',
			type     => 'text',
			hide     => 1,
			comments => 'IP address of database host',
			tooltip  => 'dbase_host - Leave this blank if your database engine is running on the '
			  . 'same machine as the webserver software.'
		},
		{
			name     => 'dbase_port',
			type     => 'int',
			hide     => 1,
			comments => 'Network port accepting database connections',
			tooltip  => 'dbase_port - This can be left blank unless the database engine is '
			  . 'listening on a non-standard port.'
		},
		{
			name    => 'dbase_user',
			type    => 'text',
			hide    => 1,
			tooltip => 'dbase_user - Depending on configuration of the database engine '
			  . 'you may be able to leave this blank.'
		},
		{
			name    => 'dbase_password',
			type    => 'text',
			hide    => 1,
			tooltip => 'dbase_password - Depending on configuration of the database engine '
			  . 'you may be able to leave this blank.'
		},
		{ name => 'dbase_view', type => 'text', required => 0, comments => 'View of isolates table to use' },
		{ name => 'url', type => 'text', length => 80, required => 0, comments => 'Web URL to database script' },
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_client_dbase_loci_fields_table_attributes {
	my $attributes = [
		{
			name           => 'client_dbase_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'client_dbases',
			labels         => '|$id|) |$name|',
			dropdown_query => 1
		},
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'isolate_field', type => 'text', length => 50, required => 1, primary_key => 1 },
		{
			name     => 'allele_query',
			type     => 'bool',
			default  => 'true',
			comments => 'set to true to display field values when an allele query is done.'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_experiments_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  length   => 10, required       => 1,  primary_key => 1 },
		{ name => 'description', type => 'text', required => 1,  length         => 48, unique      => 1 },
		{ name => 'curator',     type => 'int',  required => 1,  dropdown_query => 1 },
		{ name => 'datestamp',   type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_experiment_sequences_table_attributes {
	my $attributes = [
		{
			name           => 'experiment_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'experiments',
			labels         => '|$id|) |$description|',
			dropdown_query => 1
		},
		{ name => 'seqbin_id', type => 'int',  required => 1, primary_key    => 1, foreign_key => 'sequence_bin' },
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_client_dbase_loci_table_attributes {
	my $attributes = [
		{
			name           => 'client_dbase_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'client_dbases',
			labels         => '|$id|) |$name|',
			dropdown_query => 1
		},
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{
			name     => 'locus_alias',
			type     => 'text',
			required => 0,
			comments => 'name that this locus is referred by in client database (if different)'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_client_dbase_schemes_table_attributes {
	my $attributes = [
		{
			name           => 'client_dbase_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'client_dbases',
			labels         => '|$id|) |$name|',
			dropdown_query => 1
		},
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'schemes',
			labels         => '|$name|',
			dropdown_query => 1
		},
		{
			name     => 'client_scheme_id',
			type     => 'int',
			comments => 'id number of the scheme in the client database (if different)'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_client_dbase_cschemes_table_attributes {
	my $attributes = [
		{
			name           => 'client_dbase_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'client_dbases',
			labels         => '|$id|) |$name|',
			dropdown_query => 1
		},
		{
			name           => 'cscheme_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'classification_schemes',
			labels         => '|$id|) |$name|',
			dropdown_query => 1
		},
		{
			name     => 'client_cscheme_id',
			type     => 'int',
			comments => 'id number of the classification scheme in the client database (if different)'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_refs_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int',  required => 1, primary_key    => 1, foreign_key => 'isolates' },
		{ name => 'pubmed_id',  type => 'int',  required => 1, primary_key    => 1 },
		{ name => 'curator',    type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',  type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_sequence_refs_table_attributes {
	my $attributes = [
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'allele_id', type => 'text', required => 1, primary_key    => 1 },
		{ name => 'pubmed_id', type => 'int',  required => 1, primary_key    => 1 },
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_allele_flags_table_attributes {
	my $attributes = [
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'allele_id', type => 'text', required => 1, primary_key    => 1 },
		{ name => 'flag',      type => 'text', required => 1, primary_key    => 1 },
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_profile_refs_table_attributes {
	my $attributes = [
		{
			name            => 'scheme_id',
			type            => 'int',
			required        => 1,
			primary_key     => 1,
			foreign_key     => 'schemes',
			labels          => '|$name| (id |$id|)',
			dropdown_query  => 1,
			with_pk_only    => 1,
			is_curator_only => 1
		},
		{ name => 'profile_id', type => 'text', required => 1, primary_key    => 1 },
		{ name => 'pubmed_id',  type => 'int',  required => 1, primary_key    => 1 },
		{ name => 'curator',    type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',  type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_allele_designations_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int', required => 1, primary_key => 1, foreign_key => 'isolates' },
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'allele_id', type => 'text', required => 1, primary_key => 1 },
		{ name => 'sender',    type => 'int',  required => 1, foreign_key => 'users', dropdown_query => 1 },
		{
			name     => 'status',
			type     => 'text',
			required => 1,
			optlist  => 'confirmed;provisional;ignore',
			default  => 'confirmed'
		},
		{ name => 'method',  type => 'text', required => 1, optlist        => 'manual;automatic', default => 'manual' },
		{ name => 'curator', type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',    type => 'date', required => 1 },
		{ name => 'date_entered', type => 'date', required => 1 },
		{ name => 'comments',     type => 'text', length   => 64 }
	];
	return $attributes;
}

sub get_schemes_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'id', type => 'int', required => 1, unique => 1, primary_key => 1 },
		{
			name     => 'name',
			type     => 'text',
			required => 1,
			length   => 50,
			unique   => 1,
			tooltip  => 'name - Ensure this is short since it is used in table headings and drop-down lists.'
		},
		{ name => 'description', type => 'text', hide => 1, length => 1000 }
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  (
			{
				name        => 'dbase_name',
				type        => 'text',
				hide_public => 1,
				tooltip     => 'dbase_name - Name of the database holding profile or field information for this scheme',
				length      => 60
			},
			{
				name        => 'dbase_host',
				type        => 'text',
				hide_public => 1,
				tooltip     => 'dbase_host - Leave this blank if your database engine is running on the same '
				  . 'machine as the webserver software.'
			},
			{
				name        => 'dbase_port',
				type        => 'int',
				hide_public => 1,
				tooltip     => 'dbase_port - Leave this blank if your database engine is running on the same '
				  . 'machine as the webserver software.'
			},
			{
				name    => 'dbase_user',
				type    => 'text',
				hide    => 1,
				tooltip => 'dbase_user - Depending on configuration of the database engine you '
				  . 'may be able to leave this blank.'
			},
			{
				name    => 'dbase_password',
				type    => 'text',
				hide    => 1,
				tooltip => 'dbase_password - Depending on configuration of the database engine you may be able '
				  . 'to leave this blank.'
			},
			{
				name        => 'dbase_id',
				type        => 'int',
				hide_public => 1,
				tooltip     => 'dbase_id - Scheme id in remote database.'
			},
			{
				name     => 'isolate_display',
				type     => 'bool',
				required => 1,
				default  => 'true',
				tooltip  => 'isolate_display - Sets whether to display the scheme in the isolate info page, '
				  . 'setting to false overrides values for individual loci and scheme fields '
				  . '(can be overridden by user preference)'
			},
			{
				name     => 'main_display',
				type     => 'bool',
				required => 1,
				default  => 'true',
				tooltip  => 'main_display - Sets whether to display the scheme in isolate query results table, '
				  . 'setting to false overrides values for individual loci and scheme fields '
				  . '(can be overridden by user preference).'
			},
			{
				name     => 'query_field',
				type     => 'bool',
				required => 1,
				default  => 'true',
				tooltip  => 'query_field - Sets whether this scheme can be used in isolate queries, '
				  . 'setting to false overrides values for individual loci and scheme fields '
				  . '(can be overridden by user preference).'
			},
			{
				name     => 'query_status',
				type     => 'bool',
				required => 1,
				default  => 'false',
				tooltip  => 'query_status - Sets whether a drop-down list box should be used in '
				  . 'query interface to select profile completion status for this scheme.'
			},
			{
				name     => 'analysis',
				type     => 'bool',
				required => 1,
				default  => 'true',
				tooltip  => 'analysis - Sets whether to include this scheme in analysis functions '
				  . '(can be overridden by user preference).'
			}
		  );
		if ( $self->{'system'}->{'views'} ) {
			my @views = split /,/x, $self->{'system'}->{'views'};
			local $" = q(;);
			push @$attributes,
			  (
				{
					name    => 'view',
					type    => 'text',
					optlist => qq(@views),
					tooltip => 'view - restrict scheme to only isolates belonging to specified database view.'
				}
			  );
		}
	}
	push @$attributes,
	  (
		{
			name        => 'display_order',
			type        => 'int',
			hide_public => 1,
			tooltip     => 'display_order - order of appearance in interface.'
		},
		{
			name        => 'allow_missing_loci',
			type        => 'bool',
			hide_public => 1,
			comments    => q(This is only relevant to schemes with primary key fields, e.g. MLST.),
			tooltip     => q(allow_missing_loci - Allow profiles to contain '0' (locus missing) or 'N' (any allele).)
		}
	  );
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		push @$attributes,
		  (
			{
				name     => 'max_missing',
				type     => 'int',
				comments => q(Number of loci that are allowed to be missing for a profile to be defined. ),
				tooltip  => q(max_missing - The allow_missing_loci attribute must be set for this to take effect. )
				  . q(If left blank then any number of missing loci will be allowed.)
			},
			{
				name     => 'disable',
				type     => 'bool',
				comments => q(Set to true to disable scheme. This can be overridden by user preference settings.)
			},
			{
				name        => 'no_submissions',
				type        => 'bool',
				hide_public => 1,
				comments    => q(Set to true to prevent submission of profiles of this )
				  . q(scheme via the automated submission system.)
			}
		  );
	}
	push @$attributes,
	  (
		{ name => 'curator',      type => 'int',  hide_public => 1, required => 1, dropdown_query => 1 },
		{ name => 'datestamp',    type => 'date', hide_public => 1, required => 1 },
		{ name => 'date_entered', type => 'date', hide_public => 1, required => 1 }
	  );
	return $attributes;
}

sub get_scheme_members_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'schemes',
			labels         => '|$name|',
			dropdown_query => 1
		},
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		}
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  {
			name     => 'profile_name',
			type     => 'text',
			required => 0,
			tooltip  => 'profile_name - This is the name of the locus within the sequence definition database.'
		  };
	}
	push @$attributes,
	  (
		{ name => 'field_order', type => 'int',  required => 0 },
		{ name => 'curator',     type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',   type => 'date', required => 1 }
	  );
	return $attributes;
}

sub get_scheme_fields_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'schemes',
			labels         => '|$name|',
			dropdown_query => 1
		},
		{ name => 'field', type => 'text', required => 1, primary_key => 1, regex => '^[a-zA-Z][\w_]*$' },
		{ name => 'type', type => 'text', required => 1, optlist => 'text;integer;date' },
		{
			name     => 'primary_key',
			type     => 'bool',
			required => 1,
			default  => 'false',
			tooltip  => 'primary key - Sets whether this field defines a profile '
			  . '(you can only have one primary key field).'
		},
		{ name => 'description', type => 'text', required => 0, length      => 64, },
		{ name => 'field_order', type => 'int',  required => 0, hide_public => 1 }
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  (
			{ name => 'url', type => 'text', required => 0, length => 120, hide_public => 1 },
			{
				name     => 'isolate_display',
				type     => 'bool',
				required => 1,
				default  => 'true',
				tooltip  => 'isolate display - Sets how to display the locus in the isolate info page '
				  . '(can be overridden by user preference).'
			},
			{
				name     => 'main_display',
				type     => 'bool',
				required => 1,
				default  => 'false',
				tooltip  => 'main display - Sets whether to display locus in isolate query results table '
				  . '(can be overridden by user preference).'
			},
			{
				name     => 'query_field',
				type     => 'bool',
				required => 1,
				default  => 'true',
				tooltip  => 'query field - Sets whether this locus can be used in isolate queries '
				  . '(can be overridden by user preference).'
			},
			{
				name     => 'dropdown',
				type     => 'bool',
				required => 1,
				default  => 'false',
				tooltip  => 'dropdown - Sets whether to display a dropdown list box in the query interface '
				  . '(can be overridden by user preference).'
			}
		  );
	} else {
		push @$attributes,
		  (
			{
				name     => 'index',
				type     => 'bool',
				required => 0,
				tooltip  => 'index - Sets whether the field is indexed in the database.  This setting '
				  . 'is ignored for primary key fields which are always indexed.'
			},
			{
				name     => 'dropdown',
				type     => 'bool',
				required => 1,
				default  => 'false',
				tooltip  => 'dropdown - Sets whether to display a dropdown list box in the query interface '
				  . '(can be overridden by user preference).'
			},
			{
				name    => 'value_regex',
				type    => 'text',
				tooltip => 'value regex - Regular expression that constrains value of field'
			}
		  );
	}
	push @$attributes,
	  (
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	  );
	return $attributes;
}

sub get_scheme_groups_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'id', type => 'int', required => 1, unique => 1, primary_key => 1 },
		{
			name           => 'name',
			type           => 'text',
			required       => 1,
			length         => 50,
			dropdown_query => 1,
			unique         => 1,
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
				tooltip => 'seq_query - Sets whether the group appears in the dropdown list of '
				  . 'targets when performing a sequence query.'
			}
		  );
	}
	push @$attributes,
	  (
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	  );
	return $attributes;
}

sub get_scheme_group_scheme_members_table_attributes {
	my $attributes = [
		{
			name           => 'group_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'scheme_groups',
			labels         => '|$name|',
			dropdown_query => 1
		},
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'schemes',
			labels         => '|$name|',
			dropdown_query => 1
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_scheme_group_group_members_table_attributes {
	my $attributes = [
		{
			name           => 'parent_group_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'scheme_groups',
			labels         => '|$name|',
			dropdown_query => 1
		},
		{
			name           => 'group_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'scheme_groups',
			labels         => '|$name|',
			dropdown_query => 1
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_composite_fields_table_attributes {
	my $attributes = [
		{
			name        => 'id',
			type        => 'text',
			required    => 1,
			primary_key => 1,
			comments    => 'name of the field as it will appear in the web interface'
		},
		{
			name           => 'position_after',
			type           => 'text',
			required       => 1,
			comments       => 'field present in the isolate table',
			dropdown_query => 1,
			optlist        => 'isolate_fields'
		},
		{
			name     => 'main_display',
			type     => 'bool',
			required => 1,
			default  => 'false',
			comments => 'Sets whether to display field in isolate query results table '
			  . '(can be overridden by user preference).'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_composite_field_values_table_attributes {
	my $attributes = [
		{
			name           => 'composite_field_id',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'composite_fields',
			dropdown_query => 1
		},
		{ name => 'field_order', type => 'int', required => 1, primary_key => 1 },
		{ name => 'empty_value', type => 'text' },
		{
			name    => 'regex',
			type    => 'text',
			length  => 50,
			tooltip => q(regex - You can use regular expressions here to do some complex text manipulations )
			  . q(on the displayed value. For example: <br /><br /><b>s/ST-(\S+) complex.*/cc$1/</b><br /><br />)
			  . q(will convert something like 'ST-41/44 complex/lineage III' to 'cc41/44')
		},
		{ name => 'field',     type => 'text', length   => 40, required       => 1 },
		{ name => 'datestamp', type => 'date', required => 1 },
		{ name => 'int',       type => 'text', required => 1,  dropdown_query => 1 }
	];
	return $attributes;
}

sub get_sequences_table_attributes {
	my ($self) = @_;
	my @optlist = SEQ_STATUS;
	local $" = ';';
	my $attributes = [
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'allele_id', type => 'text', required => 1, primary_key => 1 },
		{ name => 'sequence',  type => 'text', required => 1, length      => 32768, no_user_update => 1 },
		{ name => 'status',    type => 'text', required => 1, optlist     => "@optlist", hide_public => 1 },
		{
			name     => 'type_allele',
			type     => 'bool',
			comments => 'New allele searches can be constrained to use just type alleles in comparisons',
		},
		{ name => 'sender',       type => 'int',  required => 1, dropdown_query => 1, hide_public => 1 },
		{ name => 'curator',      type => 'int',  required => 1, dropdown_query => 1, hide_public => 1 },
		{ name => 'date_entered', type => 'date', required => 1, hide_public    => 1 },
		{ name => 'datestamp',    type => 'date', required => 1, hide_public    => 1 }
	];
	if ( ( $self->{'system'}->{'allele_comments'} // '' ) eq 'yes' ) {
		push @$attributes, ( { name => 'comments', type => 'text', required => 0, length => 120 } );
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
			{
				name           => 'locus',
				type           => 'text',
				required       => 1,
				primary_key    => 1,
				foreign_key    => 'loci',
				dropdown_query => 1
			},
			{ name => 'allele_id', type => 'text', required => 1, primary_key => 1 },
		  );
	} elsif ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  (
			{
				name        => 'seqbin_id',
				type        => 'int',
				required    => 1,
				primary_key => 1,
				foreign_key => 'sequence_bin'
			}
		  );
	}
	local $" = ';';
	push @$attributes,
	  (
		{ name => 'databank',    type => 'text', required => 1, primary_key    => 1, optlist => "@databanks" },
		{ name => 'databank_id', type => 'text', required => 1, primary_key    => 1 },
		{ name => 'curator',     type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',   type => 'date', required => 1 },
	  );
	return $attributes;
}

sub get_allele_sequences_table_attributes {
	my $attributes = [
		{ name => 'id',         type => 'int',  hide_query => 1, primary_key => 1 },
		{ name => 'isolate_id', type => 'int',  required   => 1, foreign_key => 'isolates' },
		{ name => 'seqbin_id',  type => 'int',  required   => 1, foreign_key => 'sequence_bin' },
		{ name => 'locus',      type => 'text', required   => 1, foreign_key => 'loci', dropdown_query => 1 },
		{
			name     => 'start_pos',
			type     => 'int',
			required => 1,
			comments => 'start position of locus within sequence'
		},
		{ name => 'end_pos', type => 'int', required => 1, comments => 'end position of locus within sequence' },
		{
			name     => 'reverse',
			type     => 'bool',
			required => 1,
			comments => 'true if sequence is reverse complemented',
			default  => 'false'
		},
		{
			name     => 'complete',
			type     => 'bool',
			required => 1,
			comments => 'true if complete locus represented',
			default  => 'true'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_sequence_flags_table_attributes {
	my @flags = SEQ_FLAGS;
	local $" = ';';
	my $attributes = [
		{ name => 'id',        type => 'int',  required => 1, primary_key    => 1, foreign_key => 'allele_sequences' },
		{ name => 'flag',      type => 'text', required => 1, optlist        => "@flags" },
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_profiles_table_attributes {
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'schemes',
			labels         => '|$name|',
			dropdown_query => 1
		},
		{ name => 'profile_id',   type => 'text', required => 1, primary_key    => 1 },
		{ name => 'sender',       type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'curator',      type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'date_entered', type => 'date', required => 1 },
		{ name => 'datestamp',    type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_scheme_curators_table_attributes {
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'schemes',
			labels         => '|$name|',
			dropdown_query => 1
		},
		{
			name            => 'curator_id',
			type            => 'int',
			required        => 1,
			primary_key     => 1,
			foreign_key     => 'users',
			is_curator_only => 1,
			user_field      => 1,
			dropdown_query  => 1
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_locus_curators_table_attributes {
	my $attributes = [
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{
			name            => 'curator_id',
			type            => 'int',
			required        => 1,
			primary_key     => 1,
			foreign_key     => 'users',
			is_curator_only => 1,
			user_field      => 1,
			dropdown_query  => 1
		},
		{
			name     => 'hide_public',
			type     => 'bool',
			comments => 'set to true to not list curator in lists',
			default  => 'false'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_sequence_attributes_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'key', type => 'text', required => 1, primary_key => 1, regex => '^[A-z]\w*$' },
		{ name => 'type', type => 'text', required => 1, optlist => 'text;integer;float;date', default => 'text' },
		{ name => 'description', type => 'text' },
		{ name => 'curator',     type => 'int', required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_sequence_attribute_values_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'seqbin_id', type => 'int', required => 1, primary_key => 1, foreign_key => 'sequence_bin' },
		{
			name        => 'key',
			type        => 'text',
			required    => 1,
			primary_key => 1,
			foreign_key => 'sequence_attributes'
		},
		{ name => 'value',     type => 'text', required => 1 },
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_sequence_bin_table_attributes {
	my ($self) = @_;
	my @methods = SEQ_METHODS;
	local $" = ';';
	my $attributes = [
		{ name => 'id',         type => 'int',  required => 1, primary_key => 1 },
		{ name => 'isolate_id', type => 'int',  required => 1, foreign_key => 'isolates' },
		{ name => 'sequence',   type => 'text', required => 1, length      => 2048, no_user_update => 1 },
		{ name => 'method',     type => 'text', required => 1, optlist     => "@methods" },
		{ name => 'run_id',               type => 'text', length   => 32 },
		{ name => 'assembly_id',          type => 'text', length   => 32 },
		{ name => 'original_designation', type => 'text', length   => 100 },
		{ name => 'comments',             type => 'text', length   => 64 },
		{ name => 'sender',               type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'curator',              type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'date_entered',         type => 'date', required => 1 },
		{ name => 'datestamp',            type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_oauth_credentials_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'base_uri',        type => 'text', required => 1, length => 200, primary_key => 1 },
		{ name => 'consumer_key',    type => 'text', required => 1 },
		{ name => 'consumer_secret', type => 'text', required => 1 },
		{ name => 'access_token',    type => 'text', required => 1 },
		{ name => 'access_secret',   type => 'text', required => 1 },
		{ name => 'curator',      type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'date_entered', type => 'date', required => 1 },
		{ name => 'datestamp',    type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_isolate_field_extended_attributes_table_attributes {
	my ($self) = @_;
	my $fields = $self->{'xmlHandler'}->get_field_list;
	my @select_fields;
	foreach my $field (@$fields) {
		next if any { $field eq $_ } qw (id date_entered datestamp sender curator comments);
		my $field_att = $self->{'xmlHandler'}->get_field_attributes($field);
		next if ( $field_att->{'multiple'} // q() ) eq 'yes';
		push @select_fields, $field;
	}
	local $" = ';';
	my $attributes = [
		{
			name     => 'isolate_field',
			type     => 'text',
			required => 1,
			optlist  => "@select_fields"
		},
		{ name => 'attribute', type => 'text', required => 1, primary_key => 1 },
		{
			name     => 'value_format',
			type     => 'text',
			required => 1,
			optlist  => 'integer;float;text;date',
			default  => 'text'
		},
		{
			name    => 'value_regex',
			type    => 'text',
			tooltip => 'value regex - Regular expression that constrains values.'
		},
		{ name => 'description', type => 'text', length => 256 },
		{
			name    => 'url',
			type    => 'text',
			length  => 120,
			hide    => 1,
			tooltip => 'url - The URL used to hyperlink values in the isolate information page.  '
			  . 'Instances of [?] within the URL will be substituted with the value.'
		},
		{ name => 'length',      type => 'integer' },
		{ name => 'field_order', type => 'int', length => 4 },
		{ name => 'curator',     type => 'int', required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_isolate_value_extended_attributes_table_attributes {
	my ($self) = @_;
	my $fields =
	  $self->run_query( 'SELECT DISTINCT isolate_field FROM isolate_field_extended_attributes ORDER BY isolate_field',
		undef, { fetch => 'col_arrayref' } );
	my @select_fields;
	foreach my $field (@$fields) {
		push @select_fields, $field;
	}
	my $attributes =
	  $self->run_query( 'SELECT DISTINCT attribute FROM isolate_field_extended_attributes ORDER BY attribute',
		undef, { fetch => 'col_arrayref' } );
	local $" = ';';
	$attributes = [
		{
			name     => 'isolate_field',
			type     => 'text',
			required => 1,
			optlist  => "@select_fields"
		},
		{ name => 'attribute',   type => 'text', required => 1, primary_key => 1, optlist => "@$attributes" },
		{ name => 'field_value', type => 'text', required => 1, primary_key => 1 },
		{ name => 'value',       type => 'text', required => 1 },
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_projects_table_attributes {
	my $attributes = [
		{ name => 'id', type => 'int', required => 1, primary_key => 1 },
		{
			name           => 'short_description',
			type           => 'text',
			required       => 1,
			length         => 40,
			dropdown_query => 1,
			unique         => 1,
			tooltip => 'description - Ensure this is short since it is used in table headings and drop-down lists.'
		},
		{
			name    => 'full_description',
			type    => 'text',
			length  => 512,
			tooltip => q(full description - This text will appear on the record pages of isolates belonging )
			  . q(to the project.  You can use HTML markup here.  If you don't enter anything here then the )
			  . q(project will not be listed on the isolate record page.)
		},
		{
			name    => 'isolate_display',
			type    => 'bool',
			tooltip => 'isolate display - Select to list this project on an isolate information page '
			  . '(also requires a full description to be entered).',
			required => 1,
			default  => 'false'
		},
		{
			name     => 'list',
			type     => 'bool',
			tooltip  => 'list - Select to include in list of projects linked from the contents page.',
			required => 1,
			default  => 'false'
		},
		{
			name    => 'private',
			type    => 'bool',
			tooltip => 'private - Select to make the project private. You will be set as the project user '
			  . 'and will be the only user able to access it. You can add additional users or user groups who '
			  . 'will be able to access and update the project data later.',
			required => 1,
			default  => 'false'
		},
		{
			name    => 'no_quota',
			type    => 'bool',
			tooltip => q(no_quota - Isolates added to this project will not count against a user's quota of )
			  . q(private records (only relevant to private projects)),
			required => 1,
			default  => 'true'
		},
		{
			name    => 'restrict_user',
			type    => 'bool',
			tooltip => q(restrict_user - Only allow isolates submitted by sender to be added to the project. )
			  . q(This can be used in combination with restrict_usergroup. This is only relevant for private )
			  . q(projects and only affects adding records following a query - where it is easy to accidentally )
			  . q(add more than intended.),
			required => 1,
			default  => 'false'
		},
		{
			name    => 'restrict_usergroup',
			type    => 'bool',
			tooltip => q(restrict_usergroup - Only allow isolates submitted by sender's usergroup to be added )
			  . q(to the project. This can be used in combination with restrict_user. This is only relevant for )
			  . q(private projects and only affects adding records following a query - where it is easy to )
			  . q(accidentally add more than intended.),
			required => 1,
			default  => 'false'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_project_members_table_attributes {
	my $attributes = [
		{
			name           => 'project_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'projects',
			labels         => '|$id|) |$short_description|',
			dropdown_query => 1
		},
		{ name => 'isolate_id', type => 'int',  required => 1, primary_key    => 1, foreign_key => 'isolates' },
		{ name => 'curator',    type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',  type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_sets_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 1, primary_key => 1 },
		{ name => 'description', type => 'text', required => 1, length      => 40, unique => 1 },
		{ name => 'long_description', type => 'text', length => 256 },
		{ name => 'display_order',    type => 'int' },
		{
			name    => 'hidden',
			type    => 'bool',
			tooltip => 'hidden - Do not show this set in selection lists.  When selected this set can '
			  . 'only be used by specifying the set_id in the database configuration file.'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_set_loci_table_attributes {
	my $attributes = [
		{
			name           => 'set_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'sets',
			labels         => '|$description|',
			dropdown_query => 1
		},
		{
			name           => 'locus',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'loci',
			dropdown_query => 1
		},
		{ name => 'set_name',                  type => 'text', length   => 40 },
		{ name => 'formatted_set_name',        type => 'text', length   => 60 },
		{ name => 'set_common_name',           type => 'text', length   => 40 },
		{ name => 'formatted_set_common_name', type => 'text', length   => 60 },
		{ name => 'curator',                   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',                 type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_set_schemes_table_attributes {
	my $attributes = [
		{
			name           => 'set_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'sets',
			labels         => '|$description|',
			dropdown_query => 1
		},
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'schemes',
			labels         => '|$name|',
			dropdown_query => 1
		},
		{ name => 'set_name',  type => 'text', length   => 40 },
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_classification_schemes_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'id', type => 'int', required => 1, unique => 1, primary_key => 1 },
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'schemes',
			labels         => '|$name|',
			dropdown_query => 1,
			with_pk_only   => 1,
		},
		{
			name     => 'name',
			type     => 'text',
			required => 1,
			length   => 50,
			unique   => 1,
			tooltip  => 'name - This can be up to 50 characters - it is short since '
			  . 'it is used in table headings and drop-down lists.'
		},
		{ name => 'description', type => 'text', length => 256 },
		{
			name     => 'inclusion_threshold',
			type     => 'int',
			required => 1,
			comments =>
			  'Maximum number of different alleles allowed between profile and at least one group member profile.'
		},
		{
			name     => 'use_relative_threshold',
			type     => 'bool',
			required => 1,
			comments => 'Calculate threshold using ratio of shared/present in both profiles in pairwise comparison.',
			tooltip  => 'use_relative_threshold - Due to missing data the threshold can be calculated using the '
			  . 'number of loci present in both samples as the denominator instead of the number of loci in the '
			  . 'scheme.',
			default => 'false'
		}
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  (
			{
				name     => 'seqdef_cscheme_id',
				type     => 'int',
				comments => 'cscheme_id number defined in seqdef database',
				tooltip =>
				  'seqdef_cscheme_id - The id used in the isolate database will be used if this is not defined.'
			}
		  );
	}
	push @$attributes,
	  (
		{ name => 'display_order', type => 'int' },
		{
			name     => 'status',
			type     => 'text',
			required => 1,
			optlist  => 'experimental;stable',
			default  => 'experimental'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	  );
	return $attributes;
}

sub get_classification_group_fields_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{
			name           => 'cg_scheme_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'classification_schemes',
			labels         => '|$name|',
			dropdown_query => 1
		},
		{ name => 'field', type => 'text', required => 1, primary_key => 1, regex => '^[a-zA-Z][\w_]*$' },
		{ name => 'type',  type => 'text', required => 1, optlist     => 'text;integer' }
	];
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		push @$attributes,
		  (
			{
				name    => 'value_regex',
				type    => 'text',
				tooltip => 'value regex - Regular expression that constrains value of field'
			}
		  );
	}
	push @$attributes,
	  (
		{ name => 'description', type => 'text', required => 0, length         => 64, },
		{ name => 'field_order', type => 'int',  required => 0 },
		{ name => 'curator',     type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp',   type => 'date', required => 1 }
	  );
	return $attributes;
}

sub get_classification_group_field_values_table_attributes {
	my ($self) = @_;
	my $fields = $self->run_query( 'SELECT DISTINCT field FROM classification_group_fields ORDER BY field',
		undef, { fetch => 'col_arrayref' } );
	local $" = q(;);
	my $attributes = [
		{
			name           => 'cg_scheme_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'classification_schemes',
			labels         => '|$name|',
			dropdown_query => 1
		},
		{
			name           => 'field',
			type           => 'text',
			required       => 1,
			primary_key    => 1,
			optlist        => "@$fields",
			dropdown_query => 1
		},
		{
			name        => 'group_id',
			type        => 'int',
			required    => 1,
			primary_key => 1,
		},
		{ name => 'value',   type => 'text', },
		{ name => 'curator', type => 'int', required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_set_view_table_attributes {
	my ($self) = @_;
	my $divider = q(,);
	my @views = $self->{'system'}->{'views'} ? ( split /$divider/x, $self->{'system'}->{'views'} ) : ();
	local $" = ';';
	my $attributes = [
		{
			name           => 'set_id',
			type           => 'int',
			required       => 1,
			primary_key    => 1,
			foreign_key    => 'sets',
			labels         => '|$description|',
			dropdown_query => 1
		},
		{ name => 'view',      type => 'text', required => 1, optlist        => "@views", dropdown_query => 1 },
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_eav_fields_table_attributes {
	my ($self) = @_;
	my $divider = q(,);
	my @groups = $self->{'system'}->{'eav_groups'} ? ( split /$divider/x, $self->{'system'}->{'eav_groups'} ) : ();
	my $attributes = [
		{ name => 'field', type => 'text', required => 1, primary_key => 1, regex => '^[a-zA-Z0-9_\']*$' },
		{
			name           => 'value_format',
			type           => 'text',
			required       => 1,
			optlist        => 'integer;float;text;date;boolean',
			no_user_update => 1
		}
	];
	if (@groups) {
		local $" = q(;);
		push @$attributes, { name => 'category', type => 'text', optlist => "@groups", dropdown_query => 1 };
	}
	push @$attributes,
	  (
		{ name => 'description', type => 'text', length  => 128 },
		{ name => 'length',      type => 'int',  tooltip => 'length - Valid for text fields only' },
		{
			name    => 'option_list',
			type    => 'text',
			length  => 500,
			tooltip => 'option_list - Semi-colon (;)-separated list of allowed values'
		},
		{
			name    => 'value_regex',
			type    => 'text',
			tooltip => 'value_regex - Regular expression to constrain values - valid for text fields only'
		},
		{
			name    => 'conditional_formatting',
			type    => 'text',
			length  => 120,
			tooltip => 'conditional_formatting - Semi-colon (;)-separated list of values - each consisting of '
			  . 'the value, followed by a pipe character (|) and HTML to display instead of the value. If you need '
			  . 'to include a semi-colon within the HTML, use two semi-colons (;;) otherwise it will be treated '
			  . 'as the list separator.'
		},
		{
			name    => 'html_link_text',
			type    => 'text',
			length  => 20,
			defualt => 'info',
			tooltip => 'HTML_link_text - This defines the text that will appear on an information link that '
			  . 'will trigger the slide-in message (if defined below)'
		},
		{
			name    => 'html_message',
			type    => 'text',
			length  => 1000,
			tooltip => 'HTML_message - This message will slide-in on the isolate information '
			  . 'page when the field value is populated and the information link is clicked.'
		},
		{ name => 'min_value',   type => 'int', tooltip => 'min_value - Valid for number fields only' },
		{ name => 'max_value',   type => 'int', tooltip => 'max_value - Valid for number fields only' },
		{ name => 'field_order', type => 'int' },
		{
			name     => 'no_curate',
			type     => 'bool',
			required => 1,
			default  => 'false',
			tooltip  => 'no_curate - Set to true if field should not be directly modified'
		},
		{
			name     => 'no_submissions',
			type     => 'bool',
			required => 1,
			default  => 'false',
			tooltip  => 'no_submissions - Set to true to prevent field appearing in submission template table.'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	  );
	return $attributes;
}

sub get_validation_rules_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{
			name        => 'id',
			type        => 'int',
			required    => 1,
			primary_key => 1,
		},
		{
			name     => 'message',
			type     => 'text',
			required => 1,
			length   => 100,
			tooltip  => 'message - Message to display when validation fails.'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_validation_conditions_table_attributes {
	my ($self)     = @_;
	my $divider    = q(,);
	my $fields     = $self->{'xmlHandler'}->get_field_list;
	my $eav_fields = $self->get_eav_fieldnames;
	my @list;
	push @list, $_ foreach ( @$fields, @$eav_fields );
	@list = sort { lc($a) cmp lc($b) } @list;
	my @operators = OPERATORS;
	local $" = q(;);
	my $attributes = [
		{
			name        => 'id',
			type        => 'int',
			required    => 1,
			primary_key => 1,
		},
		{
			name           => 'field',
			type           => 'text',
			required       => 1,
			optlist        => qq(@list),
			dropdown_query => 1
		},
		{
			name           => 'operator',
			type           => 'text',
			required       => 1,
			optlist        => qq(@operators),
			dropdown_query => 1
		},
		{
			name     => 'value',
			type     => 'text',
			required => 1,
			tooltip  => 'Enter either absolute value or [fieldname]'
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}

sub get_validation_rule_conditions_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{
			name           => 'rule_id',
			type           => 'int',
			required       => 1,
			foreign_key    => 'validation_rules',
			labels         => '|$id|) |$message|',
			primary_key    => 1,
			dropdown_query => 1
		},
		{
			name           => 'condition_id',
			type           => 'int',
			required       => 1,
			foreign_key    => 'validation_conditions',
			labels         => '|$id|) |$field| |$operator| |$value|',
			primary_key    => 1,
			dropdown_query => 1
		},
		{ name => 'curator',   type => 'int',  required => 1, dropdown_query => 1 },
		{ name => 'datestamp', type => 'date', required => 1 }
	];
	return $attributes;
}
1;
