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
package BIGSdb::CurateAddPage;
use strict;
use warnings;
use parent qw(BIGSdb::CuratePage BIGSdb::BlastPage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use List::MoreUtils qw(any none);
use BIGSdb::Page qw(DATABANKS LOCUS_PATTERN ALLELE_FLAGS);
use constant SUCCESS => 1;

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery noCache);
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $table = $q->param('table') || '';
	my $record_name = $self->get_record_name($table);
	if ( !$self->{'datastore'}->is_table($table) && !( $table eq 'samples' && @{ $self->{'xmlHandler'}->get_sample_field_list } ) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Table $table does not exist!</p></div>\n";
		return;
	}
	print "<h1>Add new $record_name</h1>\n";
	if ( !$self->can_modify_table($table) ) {
		if ( $table eq 'sequences' && $q->param('locus') || $table eq 'locus_descriptions' ) {
			my $record_type = $self->get_record_name($table);
			my $locus       = $q->param('locus');
			print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to add $locus $record_type"
			  . "s to the database.</p></div>\n";
		} else {
			print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to add records to the $table table.</p></div>\n";
		}
		return;
	} elsif ( ( $table eq 'sequence_refs' || $table eq 'accession' ) && $q->param('locus') ) {
		my $locus = $q->param('locus');
		if ( !$self->is_admin && !$self->{'datastore'}->is_allowed_to_modify_locus_sequences( $locus, $self->get_curator_id ) ) {
			print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to add "
			  . ( $table eq 'sequence_refs' ? 'references' : 'accession numbers' )
			  . " for this locus.</p></div>\n";
			return;
		}
	} elsif ( $table eq 'pending_allele_designations' || $table eq 'allele_designations' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Please add allele designations using the isolate update interface.</p></div>\n";
		return;
	} elsif ( $table eq 'allele_sequences' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Tag allele sequences using the scan interface.</p></div>\n";
		return;
	}
	if ( ( $table eq 'scheme_fields' || $table eq 'scheme_members' ) && $self->{'system'}->{'dbtype'} eq 'sequences' && !$q->param('sent') )
	{
		print "<div class=\"box\" id=\"warning\"><p>Please be aware that any modifications to the structure of this scheme "
		 . "will result in the removal of all data from it. This is done to ensure data integrity.  This does not affect "
		 . "allele designations, but any profiles will have to be reloaded.</p></div>\n";
	}
	my $buffer;
	my %newdata;
	my @missing;
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	foreach (@$attributes) {
		$newdata{ $_->{'name'} } = $q->param( $_->{'name'} );
		if (  !$newdata{ $_->{'name'} }
			&& $_->{'name'} eq 'id'
			&& $_->{'type'} eq 'int' )
		{
			$newdata{'id'} = $self->next_id($table);
		} elsif ( $table eq 'samples' && $_->{'name'} eq 'sample_id' && !$newdata{'sample_id'} && $newdata{'isolate_id'} ) {
			$newdata{'sample_id'} = $self->_next_sample_id( $newdata{'isolate_id'} );
		}
		if ( !$newdata{ $_->{'name'} } && $_->{'default'} ) {
			$newdata{ $_->{'name'} } = $_->{'default'};
		}
	}
	if ( $table eq 'loci' && $q->param('Copy') ) {
		$self->_copy_locus_config( \%newdata );
	}
	$buffer .= $self->create_record_table( $table, \%newdata );
	$newdata{'datestamp'} = $newdata{'date_entered'} = $self->get_datestamp;
	$newdata{'curator'} = $self->get_curator_id;
	my $retval;
	if ( $q->param('sent') ) {
		$retval = $self->_insert( $table, \%newdata );
	}
	if ( ( $retval // 0 ) != SUCCESS ) {
		print $buffer ;
		$self->_print_copy_locus_record_form if $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'loci';
	}
	return;
}

sub _insert {
	my ( $self, $table, $newdata ) = @_;
	my $q          = $self->{'cgi'};
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my @problems;
	$self->_format_data( $table, $newdata );
	@problems = $self->check_record( $table, $newdata );
	my @extra_inserts;
	if ( $table eq 'sequences' ) {
		$self->_check_allele_data( $newdata, \@problems, \@extra_inserts );
	} elsif ( $table eq 'locus_descriptions' ) {
		( my $cleaned_locus = $newdata->{'locus'} ) =~ s/'/\\'/g;
		my @new_aliases = split /\r?\n/, $q->param('aliases');
		foreach my $new (@new_aliases) {
			chomp $new;
			next if $new eq '';
			push @extra_inserts,
			  "INSERT INTO locus_aliases (locus,alias,curator,datestamp) VALUES ('$cleaned_locus','$new',$newdata->{'curator'},'today')";
		}
		my @new_pubmeds = split /\r?\n/, $q->param('pubmed');
		foreach my $new (@new_pubmeds) {
			chomp $new;
			next if $new eq '';
			if ( !BIGSdb::Utils::is_int($new) ) {
				push @problems, "PubMed ids must be integers.";
			} else {
				push @extra_inserts,
				  "INSERT INTO locus_refs (locus,pubmed_id,curator,datestamp) VALUES ('$cleaned_locus',$new,$newdata->{'curator'},'today')";
			}
		}
		my @new_links = split /\r?\n/, $q->param('links');
		my $i = 1;
		foreach my $new (@new_links) {
			chomp $new;
			next if $new eq '';
			if ( $new !~ /^(.+?)\|(.+)$/ ) {
				push @problems, "Links must have an associated description separated from the URL by a '|'.";
			} else {
				my ( $url, $desc ) = ( $1, $2 );
				$url  =~ s/'/\\'/g;
				$desc =~ s/'/\\'/g;
				push @extra_inserts,
"INSERT INTO locus_links (locus,url,description,link_order,curator,datestamp) VALUES ('$cleaned_locus','$url','$desc',$i,$newdata->{'curator'},'today')";
			}
			$i++;
		}
	} elsif ( $table eq 'sequence_bin' ) {
		$newdata->{'sequence'} =~ s/[\W]//g;
		push @problems, "Sequence data invalid." if !length $newdata->{'sequence'};
		if ( $q->param('experiment') ) {
			my $experiment = $q->param('experiment');
			my $insert =
"INSERT INTO experiment_sequences (experiment_id,seqbin_id,curator,datestamp) VALUES ($experiment,$newdata->{'id'},$newdata->{'curator'},'now')";
			push @extra_inserts, $insert;
		}
	}
	if ( $table eq 'sequences' ) {
		my $locus_info = $self->{'datastore'}->get_locus_info( $newdata->{'locus'} );
		if (   defined $newdata->{'allele_id'}
			&& $newdata->{'allele_id'} ne ''
			&& !BIGSdb::Utils::is_int( $newdata->{'allele_id'} )
			&& $locus_info->{'allele_id_format'} eq 'integer' )
		{
			push @problems, "The allele id must be an integer for this locus.<br />";
		} elsif ( $locus_info->{'allele_id_regex'} ) {
			my $regex = $locus_info->{'allele_id_regex'};
			if ( $regex && $newdata->{'allele_id'} !~ /$regex/ ) {
				push @problems, "Allele id value is invalid - it must match the regular expression /$regex/<br />";
			}
		}

		#Make sure sequence bin data marked as DNA is valid
	} elsif ( $table eq 'sequence_bin' && !BIGSdb::Utils::is_valid_DNA( \( $newdata->{'sequence'} ), { allow_ambiguous => 1 } ) ) {
		push @problems, "Sequence contains non nucleotide (G|A|T|C + ambiguity code R|Y|W|S|M|K|V|H|D|B|X|N) characters.<br />";

		#special case to check that start_pos is less than end_pos for allele_sequence
	} elsif ( $table eq 'allele_sequences' && $newdata->{'end_pos'} < $newdata->{'start_pos'} ) {
		push @problems,
		  "Sequence end position must be greater than the start position - set reverse = 'true' if sequence is reverse complemented.";
	}

	#special case to check that sequence exists when adding accession or PubMed number
	elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' && ( $table eq 'accession' || $table eq 'sequence_refs' ) ) {
		if ( !$self->{'datastore'}->sequence_exists( $newdata->{'locus'}, $newdata->{'allele_id'} ) ) {
			push @problems, "Sequence $newdata->{'locus'}-$newdata->{'allele_id'} does not exist.";
		}

		#special case to check that profile exists when adding PubMed number
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' && $table eq 'profile_refs' ) {
		if ( !$self->{'datastore'}->profile_exists( $newdata->{'scheme_id'}, $newdata->{'profile_id'} ) ) {
			push @problems, "Profile $newdata->{'profile_id'} does not exist.";
		}

		#special case to ensure that a locus length is set is it is not marked as variable length
	} elsif ( $table eq 'loci' ) {
		if ( $newdata->{'length_varies'} ne 'true' && !$newdata->{'length'} ) {
			push @problems,
			  "Locus set as non variable length but no length is set. Either set 'length_varies' to false, or enter a length.";
		}
		if ( $newdata->{'id'} =~ /^\d/ ) {
			push @problems,
			  "Locus names can not start with a digit.  Try prepending an underscore (_) which will get hidden in the query interface.";
		}
		if ( $newdata->{'id'} =~ /[^\w_']/ ) {
			push @problems,
			  "Locus names can only contain alphanumeric, underscore (_) and prime (') characters (no spaces or other symbols).";
		}
	}

	#special case to ensure that a locus alias is not the same as the locus name
	elsif ( $table eq 'locus_aliases' && $newdata->{'locus'} eq $newdata->{'alias'} ) {
		push @problems, "Locus alias can not be set the same as the locus name.";
	}

	#special case to check that only one primary key field is set for a scheme field
	elsif ( $table eq 'scheme_fields' && $newdata->{'primary_key'} eq 'true' && !@problems ) {
		my $primary_key;
		my $primary_key_ref =
		  $self->{'datastore'}
		  ->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $newdata->{'scheme_id'} );
		if ( ref $primary_key_ref eq 'ARRAY' ) {
			$primary_key = $primary_key_ref->[0];
		}
		if ($primary_key) {
			push @problems, "This scheme already has a primary key field set ($primary_key).";
		}
	} elsif ( $table eq 'scheme_group_group_members' && $newdata->{'parent_group_id'} == $newdata->{'group_id'} ) {
		push @problems, "A scheme group can't be a member of itself.";
	} elsif (
		!@problems
		&& ( $self->{'system'}->{'read_access'} eq 'acl'
			|| ( $self->{'system'}->{'write_access'} && $self->{'system'}->{'write_access'} eq 'acl' ) )
		&& $self->{'username'}
		&& !$self->is_admin
		&& $table eq 'accession'
		&& $self->{'system'}->{'dbtype'} eq 'isolates'
	  )
	{
		my $isolate_id =
		  $self->{'datastore'}->run_simple_query( "SELECT isolate_id FROM sequence_bin WHERE id=?", $newdata->{'seqbin_id'} )->[0];
		if ( !$self->is_allowed_to_view_isolate($isolate_id) ) {
			push @problems,
"The sequence you are trying to add an accession to belongs to an isolate to which your user account is not allowed to access.";
		}
	} elsif (
		!@problems
		&& ( $self->{'system'}->{'read_access'} eq 'acl'
			|| ( $self->{'system'}->{'write_access'} && $self->{'system'}->{'write_access'} eq 'acl' ) )
		&& $self->{'username'}
		&& !$self->is_admin
		&& $q->param('isolate_id')
		&& !$self->is_allowed_to_view_isolate( $q->param('isolate_id') )
	  )
	{
		push @problems, "Your user account is not allowed to modify this isolate.\n";
	}
	if (@problems) {
		local $" = "<br />\n";
		print "<div class=\"box\" id=\"statusbad\"><p>@problems</p></div>\n";
	} else {
		my ( @table_fields, @values );
		foreach (@$attributes) {
			push @table_fields, $_->{'name'};
			$newdata->{ $_->{'name'} } //= '';
			$newdata->{ $_->{'name'} } =~ s/\\/\\\\/g;
			$newdata->{ $_->{'name'} } =~ s/'/\\'/g;
			if ( $_->{'name'} =~ /sequence$/ ) {
				$newdata->{ $_->{'name'} } = uc( $newdata->{ $_->{'name'} } );
				$newdata->{ $_->{'name'} } =~ s/\s//g;
			}
			push @values, $newdata->{ $_->{'name'} };
		}
		my $valuestring;
		my $first = 1;
		foreach (@values) {
			$valuestring .= ',' if !$first;
			$valuestring .= $_ ne '' ? "E'$_'" : "null";
			$first = 0;
		}
		local $" = ',';
		my $qry = "INSERT INTO $table (@table_fields) VALUES ($valuestring)";
		if ( $table eq 'users' ) {
			$qry .=
";INSERT INTO user_group_members (user_id,user_group,curator,datestamp) VALUES ($newdata->{'id'},0,$newdata->{'curator'},'today')";
		}
		eval {
			$self->{'db'}->do($qry);
			foreach (@extra_inserts) {
				$self->{'db'}->do($_);
			}
			if ( $table eq 'schemes' && $self->{'system'}->{'dbtype'} eq 'sequences' ) {
				$self->create_scheme_view( $newdata->{'id'} );
			} elsif (
				(
					any {
						$table eq $_;
					}
					qw (scheme_members scheme_fields)
				)
				&& $self->{'system'}->{'dbtype'} eq 'sequences'
			  )
			{
				$self->remove_profile_data( $newdata->{'scheme_id'} );
				$self->drop_scheme_view( $newdata->{'scheme_id'} );
				$self->create_scheme_view( $newdata->{'scheme_id'} );
			} elsif ( $table eq 'sequences' ) {
				$self->mark_cache_stale;
			}
		};
		if ($@) {
			print "<div class=\"box\" id=\"statusbad\"><p>Insert failed - transaction cancelled - no records have been touched.</p>\n";
			if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
				print
"<p>Data entry would have resulted in records with either duplicate ids or another unique field with duplicate values.</p>\n";
			} else {
				print "<p>Error message: $@</p>\n";
				$logger->error("Insert failed: $@");
			}
			print "</div>\n";
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
			if ( $table eq 'sequences' ) {
				my $cleaned_locus = $self->clean_locus( $newdata->{'locus'} );
				$cleaned_locus =~ s/\\'/'/g;
				print "<div class=\"box\" id=\"resultsheader\"><p>Sequence $cleaned_locus: $newdata->{'allele_id'} added!</p>";
			} else {
				my $record_name = $self->get_record_name($table);
				print "<div class=\"box\" id=\"resultsheader\"><p>$record_name added!</p>";
			}
			if ( $table eq 'composite_fields' ) {
				print "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=compositeUpdate&amp;"
				. "id=$newdata->{'id'}\">Add values and fully customize this composite field</a>.</p>";
			}
			print "<p>";
			if ( $table eq 'samples' ) {
				print "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;"
				. "table=samples&isolate_id=$newdata->{'isolate_id'}\">Add another</a>";
				print " | <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=isolateUpdate&amp;"
				. "id=$newdata->{'isolate_id'}\">Back to isolate update</a>";
			} else {
				my $locus_clause = '';
				if ( $table eq 'sequences' ) {
					$newdata->{'locus'} =~ s/\\//g;
					$locus_clause = "&amp;locus=$newdata->{'locus'}&amp;status=$newdata->{'status'}&amp;sender=$newdata->{'sender'}";
				}
				print "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=add&amp;"
				. "table=$table$locus_clause\">Add another</a>";
			}
			print " | <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
			return SUCCESS;
		}
	}
	return;
}

sub _check_allele_data {

	#Check for sequence length in sequences table, that sequence doesn't already exist and is similar to existing etc.
	#Prepare extra inserts for PubMed/Genbank records and sequence flags.
	my ( $self, $newdata, $problems, $extra_inserts ) = @_;
	my $q = $self->{'cgi'};
	$newdata->{'sequence'} = uc $newdata->{'sequence'};
	$newdata->{'sequence'} =~ s/[\W]//g;
	my $locus_info = $self->{'datastore'}->get_locus_info( $newdata->{'locus'} );
	my $length     = length( $newdata->{'sequence'} );
	my $units      = $locus_info->{'data_type'} && $locus_info->{'data_type'} eq 'DNA' ? 'bp' : 'residues';
	if ( !$length ) {
		push @$problems, "Sequence is a required field and can not be left blank.<br />";
	} elsif ( !$locus_info->{'length_varies'} && defined $locus_info->{'length'} && $locus_info->{'length'} != $length ) {
		push @$problems,
		  "Sequence is $length $units long but this locus is set as a standard length of $locus_info->{'length'} $units.<br />";
	} elsif ( $locus_info->{'min_length'} && $length < $locus_info->{'min_length'} ) {
		push @$problems,
		  "Sequence is $length $units long but this locus is set with a minimum length of $locus_info->{'min_length'} $units.<br />";
	} elsif ( $locus_info->{'max_length'} && $length > $locus_info->{'max_length'} ) {
		push @$problems,
		  "Sequence is $length $units long but this locus is set with a maximum length of $locus_info->{'max_length'} $units.<br />";
	} elsif ( $newdata->{'allele_id'} =~ /\s/ ) {
		push @$problems, "Allele id must not contain spaces - try substituting with underscores (_).<br />";
	} else {
		$newdata->{'sequence'} =~ s/\s//g;
		my $exist_ref =
		  $self->{'datastore'}
		  ->run_simple_query( "SELECT allele_id FROM sequences WHERE locus=? AND sequence=?", $newdata->{'locus'}, $newdata->{'sequence'} );
		my $exists = ref $exist_ref eq 'ARRAY' ? $exist_ref->[0] : undef;
		if ($exists) {
			my $cleaned_locus = $self->clean_locus( $newdata->{'locus'} );
			push @$problems, "Sequence already exists in the database ($cleaned_locus: $exists).<br />";
		}
	}
	if ( $locus_info->{'data_type'} && $locus_info->{'data_type'} eq 'DNA' && !BIGSdb::Utils::is_valid_DNA( $newdata->{'sequence'} ) ) {
		push @$problems, "Sequence contains non nucleotide (G|A|T|C) characters.<br />";
	} elsif ( !@$problems
		&& $locus_info->{'data_type'}
		&& $locus_info->{'data_type'} eq 'DNA'
		&& !$q->param('ignore_similarity')
		&& $self->{'datastore'}->sequences_exist( $newdata->{'locus'} )
		&& !$self->sequence_similar_to_others( $newdata->{'locus'}, \( $newdata->{'sequence'} ) ) )
	{
		push @$problems,
		    "Sequence is too dissimilar to existing alleles (less than 70% identical or an alignment of less "
		  . "than 90% its length).  Similarity is determined by the output of the best match from the BLAST algorithm - this "
		  . "may be conservative.  If you're sure you want to add this sequence then make sure that the 'Override sequence "
		  . "similarity check' box is ticked.<br />";
	}

	#check extended attributes if they exist
	my $sql =
	  $self->{'db'}->prepare("SELECT field,required,value_format,value_regex,option_list FROM locus_extended_attributes WHERE locus=?");
	eval { $sql->execute( $newdata->{'locus'} ) };
	$logger->error($@) if $@;
	my @missing_field;
	( my $cleaned_locus = $newdata->{'locus'} ) =~ s/'/\\'/g;
	while ( my ( $field, $required, $format, $regex, $option_list ) = $sql->fetchrow_array ) {
		my @optlist;
		my %options;
		if ($option_list) {
			@optlist = split /\|/, $option_list;
			$options{$_} = 1 foreach @optlist;
		}
		$newdata->{$field} = $q->param($field);
		if ( $required && $newdata->{$field} eq '' ) {
			push @missing_field, $field;
		} elsif ( $option_list && $newdata->{$field} ne '' && !$options{ $newdata->{$field} } ) {
			local $" = ', ';
			push @$problems, "$field value is not on the allowed list (@optlist).<br />";
		} elsif ( $format eq 'integer' && $newdata->{$field} ne '' && !BIGSdb::Utils::is_int( $newdata->{$field} ) ) {
			push @$problems, "$field must be an integer.<br />";
		} elsif ( $newdata->{$field} ne '' && $regex && $newdata->{$field} !~ /$regex/ ) {
			push @$problems, "Field '$field' does not conform to specified format.\n";
		} else {
			$field =~ s/'/\\'/g;
			if ( $newdata->{$field} ne '' ) {
				my $insert = "INSERT INTO sequence_extended_attributes(locus,field,allele_id,value,datestamp,curator) "
				  . "VALUES (E'$cleaned_locus','$field','$newdata->{'allele_id'}','$newdata->{$field}','now',$newdata->{'curator'})";
				push @$extra_inserts, $insert;
			}
		}
	}
	if (@missing_field) {
		local $" = ', ';
		push @$problems,
		  "Please fill in all extended attribute fields.  The following extended attribute fields are " . "missing: @missing_field";
	}
	my @flags = $q->param('flags');
	foreach my $flag (@flags) {
		next if none { $flag eq $_ } ALLELE_FLAGS;
		push @$extra_inserts, "INSERT INTO allele_flags (locus,allele_id,flag,curator,datestamp) VALUES (E'$cleaned_locus',"
		  . "'$newdata->{'allele_id'}','$flag',$newdata->{'curator'},'today')";
	}
	my @new_pubmeds = split /\r?\n/, $q->param('pubmed');
	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !BIGSdb::Utils::is_int($new) ) {
			push @$problems, "PubMed ids must be integers";
		} else {
			push @$extra_inserts, "INSERT INTO sequence_refs (locus,allele_id,pubmed_id,curator,datestamp) VALUES "
			  . "(E'$cleaned_locus','$newdata->{'allele_id'}',$new,$newdata->{'curator'},'today')";
		}
	}
	my @databanks = DATABANKS;
	foreach my $databank (@databanks) {
		my @new_accessions = split /\r?\n/, $q->param("databank_$databank");
		foreach my $new (@new_accessions) {
			chomp $new;
			next if $new eq '';
			( my $clean_new = $new ) =~ s/'/\\'/g;
			push @$extra_inserts,
			  "INSERT INTO accession (locus,allele_id,databank,databank_id,curator,datestamp) VALUES (E'$cleaned_locus',"
			  . "'$newdata->{'allele_id'}','$databank','$clean_new',$newdata->{'curator'},'today')";
		}
	}
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if !defined $q->param('table') || $q->param('table') ne 'sequences';
	my $buffer = << "END";
\$(function () {
 \$("#locus").change(function(){
 	var locus_name = \$("#locus").val();
 	var url = '$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=add&table=sequences&locus=' + locus_name;
 	location.href=url;
  });
});
END
	return $buffer;
}

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $table = $self->{'cgi'}->param('table');
	my $type  = $self->get_record_name($table);
	return $type ? "Add new $type - $desc" : "Add new record - $desc";
}

sub _next_sample_id {
	my ( $self, $isolate_id ) = @_;
	my $qry = "SELECT sample_id FROM samples WHERE isolate_id=? ORDER BY sample_id";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($isolate_id) };
	$logger->error($@) if $@;
	my $test = 0;
	my $next = 0;
	my $id   = 0;
	while ( my ($sample_id) = $sql->fetchrow_array ) {

		if ( $sample_id != 0 ) {
			$test++;
			$id = $sample_id;
			if ( $test != $id ) {
				$next = $test;
				$sql->finish;
				$logger->debug("Next id: $next");
				return $next;
			}
		}
	}
	if ( $next == 0 ) {
		$next = $id + 1;
	}
	$sql->finish;
	$logger->debug("Next id: $next");
	return $next;
}

sub next_id {
	my ( $self, $table, $scheme_id, $last_id ) = @_;
	if ( $table eq 'profiles' ) {
		return $self->_next_id_profiles($scheme_id);
	}
	if ( $last_id && !$self->{'sql'}->{'id_unused'}->{$table} ) {
		my $qry = "SELECT COUNT(id) FROM $table WHERE id=?";
		$self->{'sql'}->{'id_unused'}->{$table} = $self->{'db'}->prepare($qry);
	}
	if ($last_id) {
		my $next = $last_id + 1;
		eval { $self->{'sql'}->{'id_unused'}->{$table}->execute($next) };
		$logger->error($@) if $@;
		my ($used) = $self->{'sql'}->{'id_unused'}->{$table}->fetchrow_array;
		return $next if !$used;
	}
	if ( !$self->{'sql'}->{'next_id'}->{$table} ) {

		#this will find next id except when id 1 is missing
		my $qry =
		  "SELECT l.id + 1 AS start FROM $table AS l left outer join $table AS r on l.id+1=r.id where r.id is null AND l.id>0 ORDER BY l.id LIMIT 1";
		$self->{'sql'}->{'next_id'}->{$table} = $self->{'db'}->prepare($qry);
	}
	eval { $self->{'sql'}->{'next_id'}->{$table}->execute };
	if ($@) {
		$logger->error($@);
		return;
	}
	my ($next) = $self->{'sql'}->{'next_id'}->{$table}->fetchrow_array;
	$next = 1 if !$next;
	return $next;
}

sub _next_id_profiles {
	my ( $self, $scheme_id ) = @_;
	if ( !$self->{'sql'}->{'next_id_profiles'} ) {
		my $qry =
"SELECT DISTINCT CAST(profile_id AS int) FROM profiles WHERE scheme_id = ? AND CAST(profile_id AS int)>0 ORDER BY CAST(profile_id AS int)";
		$self->{'sql'}->{'next_id_profiles'} = $self->{'db'}->prepare($qry);
	}
	eval { $self->{'sql'}->{'next_id_profiles'}->execute($scheme_id) };
	if ($@) {
		$logger->error($@);
		return;
	}
	my $test = 0;
	my $next = 0;
	my $id   = 0;
	while ( my @data = $self->{'sql'}->{'next_id_profiles'}->fetchrow_array ) {
		if ( $data[0] != 0 ) {
			$test++;
			$id = $data[0];
			if ( $test != $id ) {
				$next = $test;
				$self->{'sql'}->{'next_id_profiles'}->finish;
				$logger->debug("Next id: $next");
				return $next;
			}
		}
	}
	if ( $next == 0 ) {
		$next = $id + 1;
	}
	$self->{'sql'}->{'next_id_profiles'}->finish;
	$logger->debug("Next id: $next");
	return $next;
}

sub id_exists {
	my ( $self, $id ) = @_;
	my $num = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM $self->{'system'}->{'view'} WHERE id=?", $id )->[0];
	return $num;
}

sub sequence_similar_to_others {

	#returns true if sequence is at least 70% identical over an alignment length of 90% or more.
	my ( $self, $locus, $seq_ref ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my ( $blast_file, undef ) =
	  $self->run_blast( { 'locus' => $locus, 'seq_ref' => $seq_ref, 'qry_type' => $locus_info->{'data_type'}, 'num_results' => 1 } );
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	my $length    = length $$seq_ref;
	open( my $blast_fh, '<', $full_path ) || ( $logger->error("Can't open BLAST output file $full_path. $!"), return 0 );
	my ( $identity, $alignment );

	while ( my $line = <$blast_fh> ) {
		next if !$line || $line =~ /^#/;
		my @record = split /\s+/, $line;
		$identity  = $record[2];
		$alignment = $record[3];
		last;
	}
	close $blast_fh;
	if ( defined $identity && $identity >= 70 && $alignment >= 0.9 * $length ) {
		return 1;
	}
	return;
}

sub _print_copy_locus_record_form {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $locus_list, $locus_labels ) = $self->get_field_selection_list( { 'loci' => 1, 'sort_labels' => 1 } );
	return if !@$locus_list;
	print "<div class=\"floatmenu\"><a id=\"toggle1\" class=\"showhide\">Show tools</a>\n";
	print "<a id=\"toggle2\" class=\"hideshow\">Hide tools</a></div>\n";
	print "<div class=\"hideshow\">";
	print "<div id=\"curatetools\">\n";
	print $q->start_form;
	print "Copy configuration from ";
	print $q->popup_menu( -name => 'locus', values => $locus_list, labels => $locus_labels );
	print $q->submit( -name => 'Copy', -class => 'submit' );
	print $q->hidden($_) foreach qw(db page table);
	print $q->end_form;
	print "<p class=\"comment\">All parameters will be copied except id, common name, reference sequence, "
	  . "genome<br />position and length. The copied locus id will be substituted for 'LOCUS' in fields that "
	  . "include it.</p>";
	print "</div></div>";
	return;
}

sub _copy_locus_config {
	my ( $self, $newdata_ref ) = @_;
	my $q        = $self->{'cgi'};
	my $pattern = LOCUS_PATTERN;
	my $locus    = $q->param('locus') =~ /$pattern/ ? $1 : undef;
	return if !defined $locus;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	foreach my $field ( keys %$locus_info ) {
		next if any { $field eq $_ } qw (id reference_sequence genome_position length orf common_name);
		my $value = $locus_info->{$field} || '';
		$value =~ s/$locus/LOCUS/
		  if any { $field eq $_ } qw(dbase_table dbase_id_field dbase_id2_field dbase_id2_value description_url url);
		if ( any { $field eq $_ } qw (length_varies coding_sequence main_display query_field analysis flag_table) ) {
			$value = $locus_info->{$field} ? 'true' : 'false';
		}
		$newdata_ref->{$field} = $value;
	}
	return;
}

sub _format_data {
	my ( $self, $table, $data_ref ) = @_;
	if ( $table eq 'pcr' ) {
		$data_ref->{$_} =~ s/[\r\n]//g foreach qw (primer1 primer2);
	}
	return;
}
1;
