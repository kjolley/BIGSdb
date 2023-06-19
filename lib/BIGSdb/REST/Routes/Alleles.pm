#Written by Keith Jolley
#Copyright (c) 2014-2023, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
package BIGSdb::REST::Routes::Alleles;
use strict;
use warnings;
use 5.010;
use JSON;
use Dancer2 appname => 'BIGSdb::REST::Interface';

#Allele routes
sub setup_routes {
	my $self = setting('self');
	foreach my $dir ( @{ setting('api_dirs') } ) {
		get "$dir/db/:db/loci/:locus/alleles"            => sub { _get_alleles() };
		get "$dir/db/:db/loci/:locus/alleles/:allele_id" => sub { _get_allele() };
		get "$dir/db/:db/loci/:locus/alleles_fasta"      => sub { _get_alleles_fasta() };
	}
	return;
}

sub _get_alleles {
	my $self = setting('self');
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $locus ) = @{$params}{qw(db locus)};
	my $subdir          = setting('subdir');
	my $allowed_filters = [qw(added_after added_reldate added_on updated_after updated_reldate updated_on)];
	my $set_id          = $self->get_set_id;
	my $locus_name      = $locus;
	my $set_name        = $locus;

	if ($set_id) {
		$locus_name = $self->{'datastore'}->get_set_locus_real_id( $locus, $set_id );
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
	if ( !$locus_info ) {
		send_error( "Locus $locus does not exist.", 404 );
	}
	my $qry = $self->add_filters( 'SELECT COUNT(*),max(datestamp) FROM sequences WHERE locus=?', $allowed_filters );
	my ( $allele_count, $last_updated ) = $self->{'datastore'}->run_query( $qry, $locus_name );
	my $page_values = $self->get_page_values($allele_count);
	my ( $page, $pages, $offset ) = @{$page_values}{qw(page total_pages offset)};
	my $values = { records => int($allele_count) };
	$values->{'last_updated'} = $last_updated if defined $last_updated;
	my $path   = $self->get_full_path( "$subdir/db/$db/loci/$locus_name/alleles", $allowed_filters );
	my $paging = $self->get_paging( $path, $pages, $page, $offset );
	$values->{'paging'} = $paging if %$paging;
	my $ext_attributes = [];

	if ( $params->{'extended'} ) {
		$ext_attributes = $self->{'datastore'}->run_query(
			'SELECT field,value_format FROM locus_extended_attributes WHERE locus=?',
			$locus_name,
			{
				fetch => 'all_arrayref',
				slice => {},
				cache => 'Alleles::get_alleles::locus_extended_attributes'
			}
		);
	}
	my $dna_mutations_exist;
	my $peptide_mutations_exist;
	if ( $params->{'variation'} ) {
		$dna_mutations_exist =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM dna_mutations WHERE locus=?)',
			$locus_name, { cache => 'Alleles::get_alleles::dna_mutations_exist' } );
		$peptide_mutations_exist =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM peptide_mutations WHERE locus=?)',
			$locus_name, { cache => 'Alleles::get_alleles::peptide_mutations_exist' } );
	}
	my $records = [];
	my $fields =
	  $params->{'include_records'}
	  ? 'allele_id,sequence,status,comments,date_entered,datestamp,sender,curator'
	  : 'allele_id';
	$qry = $self->add_filters( qq(SELECT $fields FROM sequences WHERE locus=? AND allele_id NOT IN ('0', 'N', 'P')),
		$allowed_filters );
	$qry .= q( ORDER BY ) . ( $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST(allele_id AS int)' : 'allele_id' );
	$qry .= qq( LIMIT $self->{'page_size'} OFFSET $offset) if !param('return_all');
	if ( $params->{'include_records'} ) {
		my $alleles = $self->{'datastore'}->run_query( $qry, $locus_name, { fetch => 'all_arrayref', slice => {} } );
		foreach my $allele (@$alleles) {
			my $record = {
				allele_id => $locus_info->{'allele_id_format'} eq 'integer'
				? int( $allele->{'allele_id'} )
				: $allele->{'allele_id'},
			};
			$record->{'sender'}  = request->uri_for("$subdir/db/$db/users/$allele->{'sender'}") if $allele->{'sender'};
			$record->{'curator'} = request->uri_for("$subdir/db/$db/users/$allele->{'curator'}")
			  if $allele->{'curator'};
			foreach my $field (qw(sequence status comments date_entered datestamp)) {
				$record->{$field} = $allele->{$field} if defined $allele->{$field};
			}
			if (@$ext_attributes) {
				my $attributes = _get_allele_extended_attributes( $ext_attributes, $locus_name, $allele );
				$record->{$_} = $attributes->{$_} foreach keys %$attributes;
			}
			if ( $params->{'variation'} ) {
				if ($peptide_mutations_exist) {
					my $peptide_mutations = _get_peptide_mutations( $locus_name, $allele->{'allele_id'} );
					if (@$peptide_mutations) {
						$record->{'SAVs'} = $peptide_mutations;
					}
				}
				if ($dna_mutations_exist) {
					my $dna_mutations = _get_nucleotide_mutations( $locus_name, $allele->{'allele_id'} );
					if (@$dna_mutations) {
						$record->{'SNPs'} = $dna_mutations;
					}
				}
			}
			push @$records, $record;
		}
	} else {
		my $allele_ids = $self->{'datastore'}->run_query( $qry, $locus_name, { fetch => 'col_arrayref' } );
		foreach my $allele_id (@$allele_ids) {
			push @$records, request->uri_for("$subdir/db/$db/loci/$set_name/alleles/$allele_id");
		}
	}
	$values->{'alleles'} = $records;
	return $values;
}

sub _get_allele_extended_attributes {
	my ( $ext_attributes, $locus_name, $allele ) = @_;
	my $self       = setting('self');
	my $attributes = {};
	my $att_values = $self->{'datastore'}->run_query(
		'SELECT field,value FROM sequence_extended_attributes WHERE (locus,allele_id)=(?,?)',
		[ $locus_name, $allele->{'allele_id'} ],
		{
			fetch => 'all_arrayref',
			slice => {},
			cache => 'Alleles::get_alleles::sequence_extended_attributes'
		}
	);
	my %values = map { $_->{'field'} => $_->{'value'} } @$att_values;
	foreach my $att (@$ext_attributes) {
		if ( defined $values{ $att->{'field'} } ) {
			$attributes->{ $att->{'field'} } =
			  $att->{'value_format'} eq 'integer'
			  ? int( $values{ $att->{'field'} } )
			  : $values{ $att->{'field'} };
		}
	}
	return $attributes;
}

sub _get_allele {
	my $self = setting('self');
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $locus, $allele_id ) = @{$params}{qw(db locus allele_id)};
	my $set_id     = $self->get_set_id;
	my $subdir     = setting('subdir');
	my $locus_name = $locus;
	if ($set_id) {
		$locus_name = $self->{'datastore'}->get_set_locus_real_id( $locus, $set_id );
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
	if ( !$locus_info ) {
		send_error( "Locus $locus does not exist.", 404 );
	}
	my $allele = $self->{'datastore'}->run_query(
		'SELECT * FROM sequences WHERE (locus,allele_id)=(?,?)',
		[ $locus_name, $allele_id ],
		{ fetch => 'row_hashref' }
	);
	if ( !$allele ) {
		send_error( "Allele $locus-$allele_id does not exist.", 404 );
	}
	my $values = {};
	foreach my $attribute (qw(locus allele_id sequence status comments date_entered datestamp sender curator)) {
		if ( $attribute eq 'locus' ) {
			$values->{$attribute} = request->uri_for("$subdir/db/$db/loci/$locus");
		} elsif ( $attribute eq 'sender' || $attribute eq 'curator' ) {

			#Don't link to user 0 (setup user)
			$values->{$attribute} = request->uri_for("$subdir/db/$db/users/$allele->{$attribute}")
			  if $allele->{$attribute};
		} else {
			$values->{$attribute} = $allele->{$attribute}
			  if defined $allele->{$attribute} && $allele->{$attribute} ne '';
		}
	}
	my $extended_attributes =
	  $self->{'datastore'}->run_query( 'SELECT field FROM locus_extended_attributes WHERE locus=?',
		$locus_name, { fetch => 'col_arrayref' } );
	foreach my $attribute (@$extended_attributes) {
		my $extended_value = $self->{'datastore'}->run_query(
			'SELECT value FROM sequence_extended_attributes WHERE (locus,field,allele_id)=(?,?,?)',
			[ $locus_name, $attribute, $allele_id ],
			{ cache => 'Alleles:extended_attributes' }
		);
		$values->{$attribute} = $extended_value if defined $extended_value && $extended_value ne '';
	}
	my $flags = $self->{'datastore'}->get_allele_flags( $locus_name, $allele_id );
	$values->{'flags'} = $flags if @$flags;
	my $client_data = $self->{'datastore'}->get_client_data_linked_to_allele( $locus, $allele_id );
	$values->{'linked_data'} = $client_data->{'detailed_values'}
	  if defined $client_data->{'detailed_values'};
	my $savs = _get_peptide_mutations( $locus, $allele_id );
	$values->{'SAVs'} = $savs if @$savs;
	my $snps = _get_nucleotide_mutations( $locus, $allele_id );
	$values->{'SNPs'} = $snps if @$snps;

	#TODO scheme members
	return $values;
}

sub _get_peptide_mutations {
	my ( $locus, $allele_id ) = @_;
	my $self = setting('self');
	my $list = [];

	#Using $self->{'cache'} would be persistent between calls even when calling another database.
	#Datastore is destroyed after call so $self->{'datastore'}->{'peptide_mutation_cache'} is safe to
	#cache only for duration of call.
	if ( !defined $self->{'datastore'}->{'peptide_mutation_cache'} ) {
		$self->{'datastore'}->{'peptide_mutation_cache'} =
		  $self->{'datastore'}
		  ->run_query( 'SELECT * FROM peptide_mutations WHERE locus=? ORDER BY reported_position,id',
			$locus, { fetch => 'all_arrayref', slice => {}, cache => 'Alleles::get_peptide_mutations' } );
	}
	my $peptide_mutations = $self->{'datastore'}->{'peptide_mutation_cache'};
	return $list if !@$peptide_mutations;
	foreach my $mutation (@$peptide_mutations) {
		my $data = $self->{'datastore'}->run_query(
			'SELECT * FROM sequences_peptide_mutations WHERE (locus,allele_id,mutation_id)=(?,?,?)',
			[ $locus, $allele_id, $mutation->{'id'} ],
			{ fetch => 'row_hashref', cache => 'Alleles::get_sequence_peptide_mutation' }
		);
		if ($data) {
			push @$list,
			  {
				position   => int( $mutation->{'reported_position'} ),
				amino_acid => $data->{'amino_acid'},
				wild_type  => $data->{'is_wild_type'} ? JSON::true : JSON::false
			  };
		}
	}
	return $list;
}

sub _get_nucleotide_mutations {
	my ( $locus, $allele_id ) = @_;
	my $self = setting('self');
	my $list = [];

	#Using $self->{'cache'} would be persistent between calls even when calling another database.
	#Datastore is destroyed after call so $self->{'datastore'}->{'dna_mutation_cache'} is safe to
	#cache only for duration of call.
	if ( !defined $self->{'datastore'}->{'dna_mutation_cache'} ) {
		$self->{'datastore'}->{'dna_mutation_cache'} =
		  $self->{'datastore'}->run_query( 'SELECT * FROM dna_mutations WHERE locus=? ORDER BY reported_position,id',
			$locus, { fetch => 'all_arrayref', slice => {}, cache => 'Alleles::get_dna_mutations' } );
	}
	my $dna_mutations = $self->{'datastore'}->{'dna_mutation_cache'};
	return $list if !@$dna_mutations;
	foreach my $mutation (@$dna_mutations) {
		my $data = $self->{'datastore'}->run_query(
			'SELECT * FROM sequences_dna_mutations WHERE (locus,allele_id,mutation_id)=(?,?,?)',
			[ $locus, $allele_id, $mutation->{'id'} ],
			{ fetch => 'row_hashref', cache => 'Alleles::get_sequence_dna_mutation' }
		);
		if ($data) {
			push @$list,
			  {
				position   => int( $mutation->{'reported_position'} ),
				nucleotide => $data->{'nucleotide'},
				wild_type  => $data->{'is_wild_type'} ? JSON::true : JSON::false
			  };
		}
	}
	return $list;
}

sub _get_alleles_fasta {
	my $self = setting('self');
	$self->check_seqdef_database;
	my $params = params;
	my ( $db, $locus ) = @{$params}{qw(db locus)};
	my $allowed_filters = [qw(added_after added_reldate added_on updated_after updated_reldate updated_on)];
	my $set_id          = $self->get_set_id;
	my $locus_name      = $locus;
	my $set_name        = $locus;

	if ($set_id) {
		$locus_name = $self->{'datastore'}->get_set_locus_real_id( $locus, $set_id );
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus_name);
	if ( !$locus_info ) {
		send_error( "Locus $locus does not exist.", 404 );
	}
	my $qry =
	  $self->add_filters(
		q(SELECT allele_id,sequence FROM sequences WHERE locus=? AND allele_id NOT IN ('0', 'N', 'P')),
		$allowed_filters );
	$qry .= q( ORDER BY ) . ( $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST(allele_id AS int)' : 'allele_id' );
	my $alleles = $self->{'datastore'}->run_query( $qry, $locus_name, { fetch => 'all_arrayref', slice => {} } );
	if ( !@$alleles ) {
		send_error( "No alleles for locus $locus are defined.", 404 );
	}
	my $buffer = '';
	foreach my $allele (@$alleles) {
		$buffer .= ">$locus\_$allele->{'allele_id'}\n$allele->{'sequence'}\n";
	}
	send_file( \$buffer, content_type => 'text/plain; charset=UTF-8' );
	return;
}
1;
