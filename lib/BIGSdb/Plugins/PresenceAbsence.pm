#PresenceAbsence.pm - Presence/Absence export plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2010-2014, University of Oxford
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
package BIGSdb::Plugins::PresenceAbsence;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use List::MoreUtils qw(none uniq);
use Log::Log4perl qw(get_logger);
use constant MAX_SPLITS_TAXA => 200;
use constant MAX_DISMAT_TAXA => 1000;
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'Presence/Absence',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Analyse presence/absence status of loci for dataset generated from query results',
		category    => 'Analysis',
		buttontext  => 'Presence/Absence',
		menutext    => 'Presence/absence status of loci',
		module      => 'PresenceAbsence',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#presence-absence",
		version     => '1.1.4',
		dbtype      => 'isolates',
		section     => 'analysis,postquery',
		input       => 'query',
		requires    => 'js_tree,offline_jobs',
		help        => 'tooltips',
		order       => 16
	);
	return \%att;
}

sub run {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $desc   = $self->get_db_description;
	say "<h1>Export presence/absence status of loci - $desc</h1>";
	if ( $q->param('submit') ) {
		my $loci_selected = $self->get_selected_loci;
		my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list;
		$q->delete('locus');
		push @$loci_selected, @$pasted_cleaned_loci;
		@$loci_selected = uniq @$loci_selected;
		$self->add_scheme_loci($loci_selected);
		if (@$invalid_loci) {
			local $" = ', ';
			say "<div class=\"box\" id=\"statusbad\"><p>The following loci in your pasted list are invalid: @$invalid_loci.</p></div>";
		} elsif ( !@$loci_selected ) {
			say "<div class=\"box\" id=\"statusbad\"><p>You must select one or more loci or schemes.</p></div>";
		} else {
			my $params = $q->Vars;
			my @list = split /[\r\n]+/, $q->param('list');
			@list = uniq @list;
			if ( !@list ) {
				my $qry = "SELECT id FROM $self->{'system'}->{'view'} ORDER BY id";
				my $id_list = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
				@list = @$id_list;
			}
			$q->delete('list');
			$params->{'set_id'} = $self->get_set_id;
			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			my $job_id    = $self->{'jobManager'}->add_job(
				{
					dbase_config => $self->{'instance'},
					ip_address   => $q->remote_host,
					module       => 'PresenceAbsence',
					parameters   => $params,
					username     => $self->{'username'},
					email        => $user_info->{'email'},
					isolates     => \@list,
					loci         => $loci_selected
				}
			);
			print <<"HTML";
<div class="box" id="resultstable">
<p>This analysis has been submitted to the job queue.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;id=$job_id">
Follow the progress of this job and view the output.</a></p> 	
</div>	
HTML
			return;
		}
	}
	print <<"HTML";
<div class="box" id="queryform">
<p>This script will export data showing whether a locus has had an allele designated, a sequence tagged, or both. 
Please check the loci that you would like to include.  Alternatively select one or more schemes to include all loci 
that are members of the scheme.</p>
HTML
	my $query_file = $q->param('query_file');
	my $list = $self->get_id_list( 'id', $query_file );
	$self->print_sequence_export_form( 'id', $list, undef, { no_options => 1 } );
	say "</div>";
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $ids = $self->{'jobManager'}->get_job_isolates($job_id);
	if ( !@$ids ) {
		$self->{'jobManager'}->update_job_status( $job_id,
			{ status => 'failed', message_html => "<p class=\"statusbad\">You must include one or more isolates.</p>" } );
		return;
	}
	my $loci          = $self->{'jobManager'}->get_job_loci($job_id);
	my $selected_loci = $self->order_loci($loci);
	if ( !@$loci ) {
		$self->{'jobManager'}->update_job_status( $job_id,
			{ status => 'failed', message_html => "<p class=\"statusbad\">You must either select one or more loci or schemes.</p>" } );
		return;
	}
	my $full_path = "$self->{'config'}->{'tmp_dir'}/$job_id.txt";
	my ( $problem_ids, $values ) = $self->_write_output( $job_id, $params, $ids, $selected_loci, $full_path );
	$self->{'jobManager'}->update_job_output( $job_id, { filename => "$job_id.txt", description => '01_Main output file' } );
	if (@$problem_ids) {
		local $" = '; ';
		$self->{'jobManager'}->update_job_status( $job_id,
			{ message_html => "<p>The following ids could not be processed (they do not exist): @$problem_ids.</p>" } );
	}
	return if !$params->{'dismat'};
	if ( keys %$values <= MAX_DISMAT_TAXA ) {
		$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => 50, stage => "Generating distance matrix" } );
		my $dismat     = $self->_generate_distance_matrix($values);
		my $nexus_file = $self->_make_nexus_file($dismat);
		if ( -e "$self->{'config'}->{'tmp_dir'}/$nexus_file" ) {
			$self->{'jobManager'}->update_job_output(
				$job_id,
				{
					filename    => "$nexus_file",
					description => '20_Distance matrix (Nexus format)|Suitable for loading in to <a href="http://www.splitstree.org">'
					  . 'SplitsTree</a>. Distances between taxa are calculated as the number of loci that are differentially present'
				}
			);
		}
		if ( keys %$values <= MAX_SPLITS_TAXA ) {
			$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => 75, stage => "Generating NeighborNet" } );
			my $splits_img = "$job_id.png";
			$self->_run_splitstree( "$self->{'config'}->{'tmp_dir'}/$nexus_file", "$self->{'config'}->{'tmp_dir'}/$splits_img", 'PNG' );
			if ( -e "$self->{'config'}->{'tmp_dir'}/$splits_img" ) {
				$self->{'jobManager'}
				  ->update_job_output( $job_id, { filename => $splits_img, description => '25_Splits graph (Neighbour-net; PNG format)' } );
			}
			$splits_img = "$job_id.svg";
			$self->_run_splitstree( "$self->{'config'}->{'tmp_dir'}/$nexus_file", "$self->{'config'}->{'tmp_dir'}/$splits_img", 'SVG' );
			if ( -e "$self->{'config'}->{'tmp_dir'}/$splits_img" ) {
				$self->{'jobManager'}->update_job_output(
					$job_id,
					{
						filename    => $splits_img,
						description => '26_Splits graph (Neighbour-net; SVG format)|This can be edited in <a href="http://inkscape.org">'
						  . 'Inkscape</a> or other vector graphics editors'
					}
				);
			}
		}
	}
	return;
}

sub get_extra_form_elements {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say "<fieldset style=\"float:left\">\n<legend>Options</legend>";
	say "<ul><li style=\"padding-bottom:1em\">Mark present if :<br />";
	my %labels =
	  ( both => 'either designations or tags set', designations => 'allele designations defined', tags => 'sequence tags defined' );
	say $q->radio_group( -name => 'presence', -value => [qw(both designations tags)], -labels => \%labels, -linebreak => 'true' );
	say "</li><li><label for=\"present\" class=\"parameter\">Symbol for present: </label>";
	say $q->popup_menu( -name => 'present', -id => 'present', -value => [qw (O Y *)] );
	say "</li><li><label for=\"absent\" class=\"parameter\">Symbol for absent: </label>";
	say $q->popup_menu( -name => 'absent', -id => 'absent', -value => [ qw (X N -), ' ' ], );
	say "</li><li>";
	say $q->checkbox( -name => 'dismat', -id => 'dismat', -label => 'Generate distance matrix' );
	my $max = MAX_DISMAT_TAXA;
	say " <a class=\"tooltip\" title=\"Distance matrix - This is limited to $max isolates and is disabled if more are selected\">"
	  . "&nbsp;<i>i</i>&nbsp;</a>";
	say "</li></ul></fieldset>";
	return;
}

sub _write_output {
	my ( $self, $job_id, $params, $ids, $loci, $filename, ) = @_;
	my @problem_ids;
	my $isolate_sql;
	my @includes;
	@includes = split /\|\|/, $params->{'includes'} if $params->{'includes'};
	if (@includes) {
		$isolate_sql = $self->{'db'}->prepare("SELECT * FROM $self->{'system'}->{'view'} WHERE id=?");
	}
	open( my $fh, '>', $filename )
	  or $logger->error("Can't open temp file $filename for writing");
	print $fh 'id';
	foreach my $field (@includes) {
		my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
		print $fh "\t" . ( $metafield // $field );
	}
	foreach my $locus (@$loci) {
		my $locus_name = $self->clean_locus( $locus, { text_output => 1 } );
		print $fh "\t$locus_name";
	}
	print $fh "\n";
	my $values;
	my $progress    = 0;
	my $i           = 0;
	my $max_percent = ( $params->{'dismat'} && @$ids <= MAX_DISMAT_TAXA ) ? 50 : 100;
	foreach my $id (@$ids) {
		$self->{'jobManager'}->update_job_status( $job_id, { stage => "Analysing id: $id" } );
		$id =~ s/[\r\n]//g;
		if ( !BIGSdb::Utils::is_int($id) ) {
			push @problem_ids, $id;
			next;
		} else {
			my $id_exists = $self->isolate_exists($id);
			if ( !$id_exists ) {
				push @problem_ids, $id;
				next;
			}
		}
		my $allele_ids = $self->{'datastore'}->get_all_allele_ids($id);
		my $tags       = $self->{'datastore'}->get_all_allele_sequences($id);
		print $fh $id;
		if (@includes) {
			eval { $isolate_sql->execute($id) };
			$logger->error($@) if $@;
			my $include_data = $isolate_sql->fetchrow_hashref;
			foreach my $field (@includes) {
				my ( $metaset, $metafield ) = $self->get_metaset_and_fieldname($field);
				my $value;
				if ( defined $metaset ) {
					$value = $self->{'datastore'}->get_metadata_value( $id, $metaset, $metafield );
				} else {
					$value = $include_data->{$field} // '';
				}
				print $fh defined $value ? "\t$value" : "\t";
			}
		}
		my $present = $params->{'present'} || 'O';
		my $absent  = $params->{'absent'}  || 'X';
		foreach my $locus (@$loci) {
			my $value = '';
			my $designations_set =
			  ( $allele_ids->{$locus} && !( @{ $allele_ids->{$locus} } == 1 && $allele_ids->{$locus}->[0] eq '0' ) ) ? 1 : 0;
			if ( $params->{'presence'} eq 'designations' ) {
				$value = $designations_set ? $present : $absent;
			} elsif ( $params->{'presence'} eq 'tags' ) {
				$value = $tags->{$locus} ? $present : $absent;
			} else {
				$value =
				  ( $designations_set || $tags->{$locus} )
				  ? $present
				  : $absent;
			}
			print $fh "\t$value";
			$values->{$id}->{$locus} = $value;
		}
		print $fh "\n";
		$i++;
		$progress = int( $i * $max_percent / @$ids );
		$self->{'jobManager'}->update_job_status( $job_id, { percent_complete => $progress } );
	}
	close $fh;
	return ( \@problem_ids, $values );
}

sub _generate_distance_matrix {
	my ( $self, $values ) = @_;
	my @ids = sort { $a <=> $b } keys %$values;
	my $dismat;
	foreach my $i ( 0 .. @ids - 1 ) {
		foreach my $j ( 0 .. $i ) {
			$dismat->{ $ids[$i] }->{ $ids[$j] } = 0;
			foreach my $locus ( keys %{ $values->{ $ids[$i] } } ) {
				if ( $values->{ $ids[$i] }->{$locus} ne $values->{ $ids[$j] }->{$locus} ) {
					$dismat->{ $ids[$i] }->{ $ids[$j] }++;
				}
			}
		}
	}
	return $dismat;
}

sub _make_nexus_file {
	my ( $self, $dismat ) = @_;
	my $timestamp = scalar localtime;
	my @ids = sort { $a <=> $b } keys %$dismat;
	my %labels;
	my $sql = $self->{'db'}->prepare("SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?");
	foreach (@ids) {
		eval { $sql->execute($_) };
		$logger->error($@) if $@;
		my ($name) = $sql->fetchrow_array;
		$name =~ tr/[\(\):, ]/_/;
		$labels{$_} = "$_|$name";
	}
	my $num_taxa = @ids;
	my $header   = <<"NEXUS";
#NEXUS
[Distance matrix calculated by BIGSdb Presence/Absence plugin ($timestamp)]
[Jolley & Maiden 2010 BMC Bioinformatics 11:595]

BEGIN taxa;
   DIMENSIONS ntax = $num_taxa;	

END;

BEGIN distances;
   DIMENSIONS ntax = $num_taxa;
   FORMAT
      triangle=LOWER
      diagonal
      labels
      missing=?
   ;
MATRIX
NEXUS
	my $prefix = BIGSdb::Utils::get_random();
	open( my $nexus_fh, '>', "$self->{'config'}->{'tmp_dir'}/$prefix.nex" ) || $logger->error("Can't open $prefix.nex for writing");
	print $nexus_fh $header;
	foreach my $i ( 0 .. @ids - 1 ) {
		print $nexus_fh $labels{ $ids[$i] };
		print $nexus_fh "\t" . $dismat->{ $ids[$i] }->{ $ids[$_] } foreach ( 0 .. $i );
		print $nexus_fh "\n";
	}
	print $nexus_fh "   ;\nEND;\n";
	close $nexus_fh;
	return "$prefix.nex";
}

sub _run_splitstree {
	my ( $self, $nexus_file, $output_file, $format ) = @_;
	if ( $self->{'config'}->{'splitstree_path'} && -x $self->{'config'}->{'splitstree_path'} ) {
		system( $self->{'config'}->{'splitstree_path'},
			'+g', 'false', '-S', 'true', '-x',
			"EXECUTE FILE=$nexus_file;EXPORTGRAPHICS format=$format file=$output_file REPLACE=yes;QUIT" );
	}
	return;
}
1;
