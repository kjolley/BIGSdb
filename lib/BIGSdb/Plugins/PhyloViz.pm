#PhyloViz.pm - phylogenetic inference and data visualization for sequence based typing methods for BIGSdb
#Written by Emmanuel Quevillon
#Copyright (c) 2016, Institut Pasteur, Paris
#E-mail: tuco@pasteur.fr
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
package BIGSdb::Plugins::PhyloViz;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use List::MoreUtils qw(uniq);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Apache2::Connection ();
use constant DEBUG => 0;

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'PhyloViz',
		author      => 'Emmanuel Quevillon',
		affiliation => 'Institut Pasteur, Paris',
		email       => 'tuco@pasteur.fr',
		description => 'Creates phylogenetic inference and data visualization for sequence based typing methods',
		category    => 'Analysis',
		buttontext  => 'PhyloViz',

		# Set menutext to empty string to not display it on index page (See BIGSdb::IndexPage line 329)
		menutext    => '',
		module      => 'PhyloViz',
		version     => '0.0.1',
		dbtype      => 'isolates',
		section     => 'analysis,postquery',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#phyloviz",
		input       => 'query',
		system_flag => 'PhyloViz',
		requires    => 'ref_db,js_tree',
		help        => 'tooltips',
		order       => 33,
	);
	return \%att;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>PhyloViz: phylogenetic tree vizualisation</h1>);

	# Get the list of isolates from query
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	if ( ref $qry_ref ne 'SCALAR' ) {
		say q(<div class="box" id="statusbad"><p>Can not retrieve id list. Please repeat your query</p></div>);
		return;
	}
	$self->rewrite_query_ref_order_by($qry_ref);
	my $isolates_ids = $self->get_ids_from_query($qry_ref);
	if ( $q->param('submit') ) {

		# Get Isolates selected fields
		my $isolates_fields          = $self->{'xmlHandler'}->get_field_list();
		my $selected_isolates_fields = [];

		# Check if user checked another list of Isolates from 'Isolates' list
		#####################################################################
		if ( $q->param('isolate_id') ) {
			my @ids = $q->param('isolate_id');
			$isolates_ids = \@ids;
		}

		# Get the selected isolates field(s)
		####################################
		foreach my $field (@$isolates_fields) {
			if ( $q->param("f_$field") ) {
				push( @$selected_isolates_fields, "$field" );
				$q->delete("f_$field");
			}
		}
		if ( !@$selected_isolates_fields ) {
			say
q(<div class="box" id="statusbad"><p>You must at least select <strong>one isolate field!</strong></p></div>);
			return;
		}

		# Get selected schemes
		######################
		my $schemes_id =
		  $self->{'datastore'}
		  ->run_query( "SELECT id, description FROM schemes ORDER BY id ASC", undef, { 'fetch' => 'all_arrayref' } );
		my $selected_schemes = {};
		my $selected_loci    = [];
		if ( scalar(@$schemes_id) ) {
			foreach my $scheme (@$schemes_id) {
				my ( $scheme_id, $scheme_name ) = @$scheme;
				if ( $q->param("s_${scheme_id}") and $q->param("s_${scheme_id}") == 1 ) {

					# We automatically include all loci
					push @$selected_loci, @{ $self->{'datastore'}->get_scheme_loci($scheme_id) };

					# Include all field from selected scheme
					$selected_schemes->{$scheme_id}->{'scheme_fields'} =
					  $self->{'datastore'}->get_scheme_fields($scheme_id);
				}
			}
		}

		# Get selected loci from the list
		#################################
		if ( !scalar(@$selected_loci) ) {
			$selected_loci = $self->get_selected_loci();
		}
		if ( !@$selected_loci ) {
			say q(<div class="box" id="statusbad"><p>You must at least select <strong>one locus!</strong></p></div>);
			return;
		} else {
			        # From here, with parameters retrieved, we need to build the 2 files needed for PhyloViz:
			        # - Profile data
			        # - Auxiliary data
			$| = 1;
			say q(<div class="box" id="resultstable">);
			say q(<p>Please wait for processing to finish (do not refresh page).</p>);
			say q(<p class="hideonload"><span class="main_icon fa fa-refresh fa-spin fa-4x"></span></p>);
			say q(<p>Data are being processed and sent to PhyloViz Online.</p>);
			my $uuid           = BIGSdb::Utils::get_random();
			my $profile_file   = join( "/", $self->{'config'}->{'tmp_dir'}, "profile_data_$uuid.txt" );
			my $auxiliary_file = join( "/", $self->{'config'}->{'tmp_dir'}, "auxiliary_data_$uuid.txt" );

			if (
				$self->generate_profile_file(
					{
						'file'     => $profile_file,
						'schemes'  => $selected_schemes,
						'isolates' => $isolates_ids,
						'loci'     => $selected_loci
					}
				)
			  )
			{
				say q(<div class="box" id="statusbad"><p>Nothing found in the database for your isolates!</p></div>);
				return;
			}
			$self->generate_auxiliary_file(
				{
					'file'     => $auxiliary_file,
					'schemes'  => $selected_schemes,
					'isolates' => $isolates_ids,
					'fields'   => $selected_isolates_fields
				}
			);

			# Upload data files to phyloviz online using python script
			my ( $phylo_id, $msg ) =
			  $self->upload_data_to_phyloviz( { 'profile' => $profile_file, 'auxiliary' => $auxiliary_file } );
			if ( !$phylo_id ) {
				say "\n<div class=\"box\" id=\"statusbad\"><p>Something went wrong: $msg</p></div>";
				return;
			}
			say qq(<p>Click this <a href="$phylo_id" target="_blank">link</a> to view your tree</p>);
			say q(</div>);
			return;
		}
	}
	say q[<div class="box" id="queryform"><p>PhyloViz: This plugin allows the analysis of sequence-based ]
	  . q[typing methods that generate allelic profiles and their associated epidemiological data.</p>   ];
	say $q->start_form();

	# Selected isolates
	if ( $self->{'config'}->{'phyloviz_show_isolates_ids'} eq 'yes' ) {
		$self->print_selected_isolates( { 'selected_ids' => $isolates_ids, 'size' => 11 } );
	}

	# Isolates fields
	$self->print_isolates_fieldset(1);

	# Loci fieldset
	$self->print_isolates_locus_fieldset();

	# Schemes Tree
	$self->print_scheme_fieldset( { 'fields_or_loci' => 0 } );

	# Action button (Submit only due to 'no_reset => 1')
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (db page name query_file scheme_id set_id list_file datatype);
	say $q->end_form();
	say q(</div>);
	return;
}

sub print_selected_isolates {
	my ( $self, $options ) = @_;
	if ( !scalar( $options->{'selected_ids'} ) ) {
		say q(No isolates selected found);
	} else {

		# Always search in table isolates, not the VIEW allowing to use this plugin with freshly created isolates
		my $query = "SELECT isolates.id, isolates.isolate FROM isolates WHERE isolates.id IN (";
		$query .= join( ",", @{ $options->{'selected_ids'} } );
		$query .= ") ORDER BY isolates.id ASC";
		my $data = $self->{'datastore'}->run_query( $query, undef, { 'fetch' => 'all_arrayref' } );
		say q(<fieldset style="float:left"><legend>Isolates</legend>);
		say q(<div style="float:left">);
		my @ids;
		my $labels = {};

		foreach (@$data) {
			my ( $id, $isolate ) = @$_;
			push @ids, $id;
			$labels->{$id} = "$id) $isolate";
		}
		say $self->popup_menu(
			-name     => 'isolate_id',
			-id       => 'isolate_id',
			-values   => \@ids,
			-labels   => $labels,
			-size     => $options->{'size'} // 8,
			-multiple => 'true',
			-default  => $options->{'selected_ids'},
			-required => $options->{'isolate_paste_list'} ? undef : 'required'
		);
		say q(</div>);
		say q(<div style="text-align:center"><input type="button" onclick='listbox_selectall("isolate_id",true)' )
		  . q(value="All" style="margin-top:1em" class="smallbutton" />)
		  . q(<input type="button" onclick='listbox_selectall("isolate_id",false)' value="None" )
		  . q(style="margin-top:1em" class="smallbutton" />);
		say q(</fieldset>);
	}
	return;
}

sub print_isolates_fieldset {
	my ( $self, $default_select ) = @_;
	my $q             = $self->{'cgi'};
	my $set_id        = $self->get_set_id;
	my $schemes       = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my $loci          = $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
	my $metadata_list = $self->{'datastore'}->get_set_metadata($set_id);
	my $fields        = $self->{'xmlHandler'}->get_field_list($metadata_list);
	my @display_fields;
	my ( @js, @js2, @isolate_js, @isolate_js2 );

	foreach my $field (@$fields) {
		push @display_fields, $field;
		push @display_fields, 'aliases' if $field eq $self->{'system'}->{'labelfield'};
	}
	push @isolate_js,  @js;
	push @isolate_js2, @js2;
	foreach my $field (@display_fields) {
		( my $id = "f_$field" ) =~ tr/:/_/;
		push @js,          qq(\$("#$id").prop("checked",true));
		push @js2,         qq(\$("#$id").prop("checked",false));
		push @isolate_js,  qq(\$("#$id").prop("checked",true));
		push @isolate_js2, qq(\$("#$id").prop("checked",false));
	}
	say q(<fieldset style="float:left"><legend>Isolate fields</legend>);
	$self->_print_fields(
		{
			fields         => \@display_fields,
			prefix         => 'f',
			num_columns    => 3,
			labels         => {},
			default_select => $default_select
		}
	);
	$self->_print_all_none_buttons( \@isolate_js, \@isolate_js2, 'smallbutton' );
	say q(</fieldset>);
	return;
}

sub upload_data_to_phyloviz {
	my $self = shift;
	my $args = shift;
	my $uuid = 0;
	my $msg  = "No message";
	my ($data_set) = ( $args->{'profile'} =~ /.+\/([^\/]+)\.txt/ );
	my $user       = $self->{'config'}->{'phyloviz_user'};
	my $pass       = $self->{'config'}->{'phyloviz_passwd'};
	my $script     = $self->{'config'}->{'phyloviz_upload_script'};
	if ( !$user || !$pass || !$script ) {
		return ( 0, "Missing PhyloViz connection parameters!" );
	}
	my $cmd =
	  "python $script -u $user -p $pass -sdt profile -sd $args->{'profile'} -m $args->{'auxiliary'} -d $data_set 2>&1";
	$logger->error($cmd);
	print q(<p>Sending data to PhyloViz online ... );
	if ( $ENV{'MOD_PERL'} ) {
		$self->{'mod_perl_request'}->rflush();
		return 1 if $self->{'mod_perl_request'}->connection()->aborted();
	}
	open( CMD, "$cmd |" ) or $logger->error("Can't upload data to PhyloViz");
	while (<CMD>) {
		if (/(Incorrect username or password)/) {
			$logger->error("[PhyloViz] remoteUpload: $1");
			$msg = $1;
			last;
		}
		if (/access the tree at: (.+)/i) {
			$uuid = $1;
		}
		if (/(dataset name already exists)/) {
			$logger->error("[PhyloViz] $1: $data_set");
			$msg = $1;
			last;
		}
	}
	close(CMD);
	say q(<span class="statusgood fa fa-check"></span></p>);
	return ( $uuid, $msg );
}

sub generate_profile_file {
	my $self     = shift;
	my $args     = shift;
	my $filename = $args->{'file'};
	print q(<p>Generating profile data file ... );
	if ( $ENV{'MOD_PERL'} ) {
		$self->{'mod_perl_request'}->rflush();
		return 1 if $self->{'mod_perl_request'}->connection()->aborted();
	}

	# Get the list of loci from each Scheme
	# Can't use table pivot function:ERROR:  tables can have at most 1600 columns
	my @schemes_id = ();
	foreach my $scheme_id ( sort keys %{ $args->{'schemes'} } ) {
		push( @schemes_id, $scheme_id );
	}
	my $query = undef;
	$query .= "SELECT i.isolate, a.locus, a.allele_id, s.description ";
	$query .= "FROM scheme_members sm ";
	$query .= "JOIN schemes s ON s.id = sm.scheme_id ";
	$query .= "JOIN loci l ON l.id = sm.locus ";
	$query .= "JOIN allele_designations a ON a.locus = l.id ";
	$query .= "JOIN isolates i ON i.id = a.isolate_id ";
	$query .= "WHERE ";
	if ( scalar(@schemes_id) ) {
		$query .= " sm.scheme_id IN ";
		$query .= "(SELECT id FROM schemes WHERE id IN (" . join( ", ", @schemes_id ) . ")) AND ";
	}
	$query .= " i.id IN (" . join( ", ", @{ $args->{'isolates'} } ) . ") ";
	$query .= "AND l.id IN (" . join( ", ", map { "'$_'" } @{ $args->{'loci'} } ) . ") ";
	$query .= "GROUP BY i.isolate, a.locus, a.allele_id, s.description ";
	$query .= "ORDER BY i.isolate;";
	my $header_line = ["Isolate"];
	my $loci        = {};
	my $isolates    = {};
	my $rows        = $self->{'datastore'}->run_query( $query, undef, { 'fetch' => 'all_arrayref' } );

	if ( !$rows ) {
		return 1;
	}

	# SLCC2482 | abcZ  | 4   | MLST
	# SLCC2482 | bglA  | 4   | MLST
	foreach my $row (@$rows) {
		if ( !exists( $isolates->{ $row->[0] } ) ) {
			$isolates->{ $row->[0] } = [ $row->[0] ];
		}
		if ( !exists( $loci->{ $row->[1] } ) ) {
			$loci->{ $row->[1] } = 1;
			push( @$header_line, "$row->[1]($row->[3])" );
		}
		push( @{ $isolates->{ $row->[0] } }, $row->[2] );
	}
	if ( scalar( keys %$isolates ) ) {
		open( my $fh, '>:encoding(utf8)', $filename )
		  or $logger->error("Can't open temp file $filename for writing");
		print $fh join( "\t", @$header_line ), "\n";
		foreach my $isolate ( sort keys %$isolates ) {
			print $fh join( "\t", @{ $isolates->{$isolate} } ), "\n";
		}
		close($fh);
	} else {
		return 1;
	}
	say q(<span class="statusgood fa fa-check"></span></p>);
	return 0;
}

sub generate_auxiliary_file {
	my $self     = shift;
	my $args     = shift;
	my $filename = $args->{'file'};

	# We ensure 'Isolate' is in the array
	unshift( @{ $args->{'fields'} }, ucfirst('isolate') );

	# And we rearrange by removing the one already there if it was.
	@{ $args->{'fields'} } = uniq( @{ $args->{'fields'} } );
	print q(<p>Generating auxiliary file ... );
	if ( $ENV{'MOD_PERL'} ) {
		$self->{'mod_perl_request'}->rflush();
		return 1 if $self->{'mod_perl_request'}->connection()->aborted();
	}
	my $query = "SELECT " . join( ", ", @{ $args->{'fields'} } ) . " FROM isolates ";
	$query .= "WHERE id IN (" . join( ", ", @{ $args->{'isolates'} } ) . ") ORDER BY isolate;";
	open( my $fh, '>:encoding(utf8)', $filename )
	  or $logger->error("Can't open temp file $filename for writing");
	my $isolates = $self->{'datastore'}->run_query( $query, undef, { 'fetch' => 'all_arrayref' } );
	print $fh join( "\t", @{ $args->{'fields'} } ), "\n";
	no warnings;
	foreach my $isolate (@$isolates) {
		print $fh join( "\t", @$isolate ), "\n";
	}
	close($fh);
	say q(<span class="statusgood fa fa-check"></span></p>);
	return 0;
}
1;
