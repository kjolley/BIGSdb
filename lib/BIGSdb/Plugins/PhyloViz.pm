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
#
#Modifications to initial code made by Keith Jolley.
#https://github.com/kjolley/BIGSdb/commits/develop/lib/BIGSdb/Plugins/PhyloViz.pm
package BIGSdb::Plugins::PhyloViz;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use List::MoreUtils qw(uniq);
use BIGSdb::Constants qw(GOOD);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

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
		module      => 'PhyloViz',
		version     => '0.0.1',
		dbtype      => 'isolates',
		section     => 'postquery',
		input       => 'query',
		system_flag => 'PhyloViz',
		requires    => 'js_tree',
		help        => 'tooltips',
		order       => 33,
		min         => 2,
		max         => 5000
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
	return if !$qry_ref;
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
			say q(<div class="box" id="statusbad"><p>You must at least select )
			  . q(<strong>one isolate field!</strong></p></div>);
			return;
		}
		my $selected_loci = $self->get_selected_loci;
		my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list( { dont_clear => 1 } );
		$q->delete('locus');
		push @$selected_loci, @$pasted_cleaned_loci;
		@$selected_loci = uniq @$selected_loci;
		if (@$invalid_loci) {
			local $" = ', ';
			say q(<div class="box" id="statusbad"><p>The following loci in your )
			  . qq(pasted list are invalid: @$invalid_loci.</p></div>);
		}
		$self->add_scheme_loci($selected_loci);
		if ( !@$selected_loci ) {
			say q(<div class="box" id="statusbad"><p>You must at least select <strong>one locus!</strong></p></div>);
			return;
		} else {

			# From here, with parameters retrieved, we need to build the 2 files needed for PhyloViz:
			# - Profile data
			# - Auxiliary data
			local $| = 1;
			say q(<div class="box" id="resultstable">);
			say q(<p>Please wait for processing to finish (do not refresh page).</p>);
			say q(<p class="hideonload"><span class="main_icon fa fa-refresh fa-spin fa-4x"></span></p>);
			say q(<p>Data are being processed and sent to PhyloViz Online.</p>);
			my $uuid           = BIGSdb::Utils::get_random();
			my $profile_file   = "$self->{'config'}->{'secure_tmp_dir'}/${uuid}_profile_data.txt";
			my $auxiliary_file = "$self->{'config'}->{'secure_tmp_dir'}/${uuid}_auxiliary_data.txt";

			if (
				$self->_generate_profile_file(
					{ file => $profile_file, isolates => $isolates_ids, loci => $selected_loci }
				)
			  )
			{
				say q(</div><div class="box" id="statusbad"><p>Nothing found )
				  . q(in the database for your isolates!</p></div>);
				return;
			}
			$self->_generate_auxiliary_file(
				{ file => $auxiliary_file, isolates => $isolates_ids, fields => $selected_isolates_fields } );

			# Upload data files to phyloviz online using python script
			my ( $phylo_id, $msg ) =
			  $self->_upload_data_to_phyloviz( { profile => $profile_file, auxiliary => $auxiliary_file } );
			if ( !$phylo_id ) {
				say qq(</div><div class="box" id="statusbad"><p>Something went wrong: $msg</p></div>);

				#Delete cookie file as it may be the username/password that is wrong.
				#This will stop it being used again.
				unlink "$self->{'config'}->{'secure_tmp_dir'}/jarfile";
				return;
			}
			say qq(<p>Click this <a href="$phylo_id" target="_blank">link</a> to view your tree</p>);
			say q(</div>);
			unlink $profile_file, $auxiliary_file;
			return;
		}
	}
	say q(<div class="box" id="queryform"><p>PhyloViz: This plugin allows the analysis of sequence-based )
	  . q(typing methods that generate allelic profiles and their associated epidemiological data.</p>);
	say $q->start_form;

	# Selected isolates
	if ( $self->{'config'}->{'phyloviz_show_isolates_ids'} eq 'yes' ) {
		$self->_print_selected_isolates( { selected_ids => $isolates_ids, size => 11 } );
	}

	# Isolates fields
	$self->print_isolates_fieldset(1);

	# Loci fieldset
	$self->print_isolates_locus_fieldset( { locus_paste_list => 1 } );

	# Schemes Tree
	$self->print_scheme_fieldset( { fields_or_loci => 0 } );

	# Action button (Submit only due to 'no_reset => 1')
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw (db page name query_file scheme_id set_id list_file datatype);
	say $q->end_form();
	say q(</div>);
	return;
}

#TODO The query to mark selected will not scale well on very large databases.
#Should create a generic method in Plugin.pm.
sub _print_selected_isolates {
	my ( $self, $options ) = @_;
	if ( !scalar( $options->{'selected_ids'} ) ) {
		say q(No isolates selected found);
	} else {
		my $view = $self->{'system'}->{'view'};
		local $" = q(,);
		my $query = "SELECT $view.id, $view.$self->{'system'}->{'labelfield'} FROM $view WHERE "
		  . "$view.id IN (@{$options->{'selected_ids'}}) ORDER BY $view.id ASC";
		my $data = $self->{'datastore'}->run_query( $query, undef, { fetch => 'all_arrayref' } );
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

sub _upload_data_to_phyloviz {
	my $self = shift;
	my $args = shift;
	my $uuid = 0;
	my $msg  = 'No message';
	my ($data_set) = ( $args->{'profile'} =~ /.+\/([^\/]+)\.txt/x );
	my $user       = $self->{'config'}->{'phyloviz_user'};
	my $pass       = $self->{'config'}->{'phyloviz_passwd'};
	my $script     = $self->{'config'}->{'phyloviz_upload_script'};
	if ( !$user || !$pass || !$script ) {
		return ( 0, 'Missing PhyloViz connection parameters!' );
	}
	my $cmd =
	    "cd $self->{'config'}->{'secure_tmp_dir'};"
	  . "python $script -u $user -p $pass -sdt profile -sd $args->{'profile'} "
	  . "-m $args->{'auxiliary'} -d $data_set -e true 2>&1";
	print q(<p>Sending data to PhyloViz online ... );
	if ( $ENV{'MOD_PERL'} ) {
		$self->{'mod_perl_request'}->rflush();
		return 1 if $self->{'mod_perl_request'}->connection()->aborted();
	}
	open( my $handle, '-|', $cmd ) or $logger->error('Cannot upload data to PhyloViz');
	while (<$handle>) {
		if (/(Incorrect\ username\ or\ password)/x) {
			$logger->error("[PhyloViz] remoteUpload: $1");
			$msg = $1;
			last;
		}
		if (/access\ the\ tree\ at:\ (.+)/ix) {
			$uuid = $1;
		}
		if (/(dataset\ name\ already\ exists)/x) {
			$logger->error("[PhyloViz] $1: $data_set");
			$msg = $1;
			last;
		}
	}
	close $handle;
	say GOOD . q(</p>);
	return ( $uuid, $msg );
}

sub _generate_profile_file {
	my ( $self, $args ) = @_;
	my ( $filename, $isolates, $loci ) = @{$args}{qw(file isolates loci)};
	print q(<p>Generating profile data file ... );
	if ( $ENV{'MOD_PERL'} ) {
		$self->{'mod_perl_request'}->rflush;
		return 1 if $self->{'mod_perl_request'}->connection->aborted;
	}
	if (@$isolates) {
		open( my $fh, '>:encoding(utf8)', $filename )
		  or $logger->error("Can't open temp file $filename for writing");
		local $" = qq(\t);
		say $fh qq(id\t@$loci);
		foreach my $isolate_id (@$isolates) {
			my @profile;
			push @profile, $isolate_id;
			my $ad = $self->{'datastore'}->get_all_allele_designations($isolate_id);
			foreach my $locus (@$loci) {
				my @values = sort keys %{ $ad->{$locus} };

				#Just pick lowest value
				push @profile, $values[0] // q();
			}
			say $fh qq(@profile);
		}
		close $fh;
	} else {
		return 1;
	}
	say GOOD . q(</p>);
	return 0;
}

sub _generate_auxiliary_file {
	my ( $self, $args ) = @_;
	my ( $filename, $isolates, $fields ) = @{$args}{qw(file isolates fields)};

	# We ensure 'id' is in the list
	unshift @$fields, 'id';

	# And we rearrange by removing the one already there if it was.
	@$fields = uniq @$fields;
	print q(<p>Generating auxiliary file ... );
	if ( $ENV{'MOD_PERL'} ) {
		$self->{'mod_perl_request'}->rflush;
		return 1 if $self->{'mod_perl_request'}->connection->aborted;
	}
	local $" = q(,);
	my $query = "SELECT @$fields FROM isolates WHERE id IN (@$isolates) ORDER BY id;";
	open( my $fh, '>:encoding(utf8)', $filename )
	  or $logger->error("Can't open temp file $filename for writing");
	my $data = $self->{'datastore'}->run_query( $query, undef, { fetch => 'all_arrayref' } );
	local $" = qq(\t);
	say $fh qq(@$fields);
	no warnings 'uninitialized';

	foreach my $field_values (@$data) {
		say $fh qq(@$field_values);
	}
	close $fh;
	say GOOD . q(</p>);
	return 0;
}
1;
