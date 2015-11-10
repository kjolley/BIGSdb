#TagStatus.pm - Tag status plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2011-2015, University of Oxford
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
package BIGSdb::Plugins::TagStatus;
use strict;
use warnings;
use parent qw(BIGSdb::Plugin);
use 5.010;
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use Apache2::Connection ();
use constant COLOURS => qw(eee c22 22c c4c 000);    #none; designations only; tags only; both; flags

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'Tag Status',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Breakdown status of sequence tagging and designation by locus',
		category    => 'Breakdown',
		buttontext  => 'Tag status',
		menutext    => 'Tag status',
		module      => 'TagStatus',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#tag-status",
		version     => '1.2.1',
		dbtype      => 'isolates',
		section     => 'breakdown,postquery',
		requires    => 'mogrify',
		system_flag => 'TagStatus',
		input       => 'query',
		help        => 'tooltips',
		requires    => 'js_tree',
		order       => 95,
		max         => 1000
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 0 };
	return;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	my $ids        = $self->get_ids_from_query($qry_ref);
	if ( ref $ids ne 'ARRAY' || !@$ids ) {
		say q(<div class="box statusbad"><p>No isolates to analyse.</p></div>);
		return;
	}
	if ( $q->param('isolate_id') && BIGSdb::Utils::is_int( $q->param('isolate_id') ) ) {
		$self->_breakdown_isolate( $q->param('isolate_id') );
		return;
	} else {
		say q(<h1>Tag status</h1>);
		return if $self->has_set_changed;
		say q(<div class="box" id="queryform" style="display:none"><div class="scrollable">);
		$self->_print_tree;
		say q(</div></div>);
		my $schemes =
		  $self->{'datastore'}->run_query( 'SELECT id FROM schemes ORDER BY display_order,description', undef,
			{ fetch => 'col_arrayref' } );
		my @selected_schemes;
		foreach my $scheme_id ( @$schemes, 0 ) {
			push @selected_schemes, $scheme_id if $q->param("s_$scheme_id");
		}
		return if !@selected_schemes;
		$self->_print_schematic( $ids, \@selected_schemes );
	}
	return;
}

sub _breakdown_isolate {
	my ( $self, $id ) = @_;
	my $isolate =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?", $id, { fetch => 'row_hashref' } );
	if ( !$isolate ) {
		say q(<h1>Tag status</h1>);
		say q(<div class="box statusbad"><p>Invalid isolate passed.</p></div>);
		return;
	}
	say qq(<h1>Tag status: Isolate id#$id ($isolate->{$self->{'system'}->{'labelfield'}})</h1>);
	say q(<div class="box" id="resultstable">);
	my $allele_ids      = $self->{'datastore'}->get_all_allele_ids($id);
	my $tags            = $self->{'datastore'}->get_all_allele_sequences($id);
	my $flags           = $self->_get_loci_with_sequence_flags($id);
	my $loci_with_flags = $self->_get_loci_with_sequence_flags($id);
	my $set_id          = $self->get_set_id;
	my $scheme_data     = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my ( $scheme_ids_ref, $desc_ref ) = $self->extract_scheme_desc($scheme_data);
	say q(<table class="resultstable"><tr>);
	say qq(<th>$_</th>) foreach ( 'Scheme', 'Locus', 'Allele designation(s)', 'Sequence tag' );
	say q(</tr>);
	my $td       = 1;
	my $tagged   = q(background:#aaf; color:white);
	my $untagged = q(background:red);

	foreach my $scheme_id (@$scheme_ids_ref) {
		my $first = 1;
		my $scheme_loci =
		  $self->{'datastore'}->get_scheme_loci( $scheme_id, { profile_name => 0, analysis_pref => 1 } );
		my $locus_count = @$scheme_loci;
		say qq(<tr class="td$td"><th rowspan="$locus_count">$desc_ref->{$scheme_id}</th>);
		foreach my $locus (@$scheme_loci) {
			say qq(<tr class="td$td">) if !$first;
			my $cleaned = $self->clean_locus($locus);
			say qq(<td>$cleaned</td>);
			local $" = q(,);
			say defined $allele_ids->{$locus}
			  ? qq(<td style="$tagged">@{$allele_ids->{$locus}}</td>)
			  : qq(<td style="$untagged" />);
			say defined $tags->{$locus} ? qq(<td style="$tagged">) : qq(<td style="$untagged">);
			$self->_get_flags( $id, $locus ) if any { $locus eq $_ } @$loci_with_flags;
			say q(</td></tr>);
			$first = 0;
		}
		$td = $td == 1 ? 2 : 1;
	}
	my $no_scheme_loci = $self->{'datastore'}->get_loci_in_no_scheme( { analyse_pref => 1, set_id => $set_id } );
	if (@$no_scheme_loci) {
		my $first       = 1;
		my $locus_count = @$no_scheme_loci;
		say qq(<tr class="td$td"><th rowspan="$locus_count">Loci</th>);
		foreach my $locus (@$no_scheme_loci) {
			say qq(<tr class="td$td">) if !$first;
			my $cleaned = $self->clean_locus($locus);
			say qq(<td>$cleaned</td>);
			local $" = q(,);
			say defined $allele_ids->{$locus}
			  ? qq(<td style="$tagged">@{$allele_ids->{$locus}}</td>)
			  : qq(<td style="$untagged" />);
			say defined $tags->{$locus} ? qq(<td style="$tagged">) : qq(<td style="$untagged">);
			$self->_get_flags( $id, $locus ) if any { $locus eq $_ } @$loci_with_flags;
			say q(</td></tr>);
			$first = 0;
		}
	}
	say q(</table></div>);
	return;
}

sub _get_loci_with_sequence_flags {
	my ( $self, $isolate_id ) = @_;
	return $self->{'datastore'}->run_query(
		'SELECT allele_sequences.locus FROM sequence_flags LEFT JOIN '
		  . 'allele_sequences ON sequence_flags.id = allele_sequences.id WHERE isolate_id=?',
		$isolate_id,
		{ fetch => 'col_arrayref' }
	);
}

sub _get_flags {
	my ( $self, $isolate_id, $locus ) = @_;
	my $flags = $self->{'datastore'}->run_query(
		'SELECT flag FROM sequence_flags LEFT JOIN allele_sequences ON '
		  . 'sequence_flags.id=allele_sequences.id WHERE (isolate_id,locus)=(?,?) ORDER BY flag',
		[ $isolate_id, $locus ],
		{ fetch => 'col_arrayref' }
	);
	print qq(<a class="seqflag_tooltip">$_</a>) foreach @$flags;
	return;
}

sub _print_schematic {
	my ( $self, $ids, $schemes ) = @_;
	my $locus_count = $self->_get_locus_count($schemes);
	return if !$locus_count;
	my $bar_width = $self->_get_bar_width($locus_count);
	my %selected_schemes = map { $_ => 1 } @$schemes;
	my @loci;
	my $set_id = $self->get_set_id;
	my $scheme_data = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my ( $scheme_ids_ref, $desc_ref ) = $self->extract_scheme_desc($scheme_data);
	my %scheme_loci;
	my @image_map;
	my $i = 0;

	foreach my $scheme_id (@$scheme_ids_ref) {
		next if !$selected_schemes{$scheme_id};
		my $scheme_loci =
		  $self->{'datastore'}->get_scheme_loci( $scheme_id, { profile_name => 0, analysis_pref => 1 } );
		push @loci, @$scheme_loci;
		$scheme_loci{$scheme_id} = $scheme_loci;
		my $j = $i + ( @$scheme_loci * $bar_width ) - 1;
		push @image_map, qq(<area shape="rect" coords="I=$i,0,J=$j,20" )
		  . qq(title="$desc_ref->{$scheme_id}" alt="$desc_ref->{$scheme_id}" />\n);
		$i = $j + 1;
	}
	my $no_scheme_loci = $self->{'datastore'}->get_loci_in_no_scheme( { analyse_pref => 1, set_id => $set_id } );
	my $j = $i + ( @$no_scheme_loci * $bar_width ) - 1;
	push @image_map,
	  qq(<area shape="rect" coords="I=$i,0,J=$j,20" ) . qq(title="Loci not in scheme" alt="Loci not in scheme" />\n);
	foreach (@image_map) {
		if ( $_ =~ /I=(\d+)/x ) {
			my $new_value = int($1);
			$_ =~ s/I=\d+/$new_value/x;
		}
		if ( $_ =~ /J=(\d+)/x ) {
			my $new_value = int($1);
			$_ =~ s/J=\d+/$new_value/x;
		}
	}
	push @loci, @$no_scheme_loci;
	say q(<div class="box" id="resultstable">);
	say q(<p>Bars represent loci by schemes arranged in alphabetical order. If a locus appears in )
	  . q(more than one scheme it will appear more than once in this graphic. Click on the id hyperlink )
	  . q(for a detailed breakdown for an isolate.</p>);
	my @colours = COLOURS;
	say q(<h2>Key</h2>);
	say qq(<p><span style="color: #$colours[1]; font-weight:600">Allele designated only</span> | )
	  . qq(<span style="color: #$colours[2]; font-weight:600">Sequence tagged only</span> | )
	  . qq(<span style="color: #$colours[3]; font-weight:600">Allele designated + sequence tagged</span> | )
	  . qq(<span style="color: #$colours[4]; font-weight:600\">Flagged</span> )
	  . q(<a class="tooltip" title="Flags - Sequences may be flagged to indicate problems, e.g. ambiguous )
	  . q(reads, internal stop codons etc."><span class="fa fa-info-circle"></span></a></p>);
	my $plural = $locus_count == 1 ? q(us) : q(i);
	say qq(<p><b>$locus_count loc$plural selected:</b></p>);
	say qq(<map id="schemes" name="schemes">\n@image_map</map>);
	say q(<div class="scrollable">);
	say q(<table class="resultstable"><tr><th>Id</th><th>Isolate</th><th>Designation status</th></tr>);
	my $td     = 1;
	my $prefix = BIGSdb::Utils::get_random();
	local $| = 1;

	foreach my $id (@$ids) {
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
		my @designations;
		my $isolate =
		  $self->{'datastore'}
		  ->run_query( "SELECT $self->{'system'}->{'labelfield'} FROM $self->{'system'}->{'view'} WHERE id=?",
			$id, { cache => 'TagStatus::print_schematic::get_isolate_name' } );
		my $allele_ids      = $self->{'datastore'}->get_all_allele_ids($id);
		my $tags            = $self->{'datastore'}->get_all_allele_sequences($id);
		my $loci_with_flags = $self->_get_loci_with_sequence_flags($id);
		my %loci_with_flags = map { $_ => 1 } @$loci_with_flags;
		my $url             = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;)
		  . qq(name=TagStatus&amp;isolate_id=$id);
		say qq(<tr class="td$td"><td><a href="$url">$id</a></td><td>$isolate</td>);

		foreach my $scheme_id (@$scheme_ids_ref) {
			next if !$selected_schemes{$scheme_id};
			foreach my $locus ( @{ $scheme_loci{$scheme_id} } ) {
				my $value = defined $allele_ids->{$locus} ? 1 : 0;
				$value += defined $tags->{$locus} ? 2 : 0;
				$value = $loci_with_flags{$locus} ? 4 : $value;
				push @designations, $value;
			}
		}
		foreach my $locus (@$no_scheme_loci) {
			next if !$selected_schemes{0};
			my $value = defined $allele_ids->{$locus} ? 1 : 0;
			$value += defined $tags->{$locus} ? 2 : 0;
			$value = $loci_with_flags{$locus} ? 4 : $value;
			push @designations, $value;
		}
		my $designation_filename = "$self->{'config'}->{'tmp_dir'}/$prefix\_$id\_designation.svg";
		$self->_make_svg( $designation_filename, $bar_width, \@designations );
		say qq(<td><img src="/tmp/${prefix}_${id}_designation.svg" alt="" usemap="#schemes" )
		  . q(style="border:1px solid #ddd" /></td></tr>);
		$td = $td == 1 ? 2 : 1;
	}
	say q(</table></div></div>);
	return;
}

sub _get_bar_width {
	my ( $self, $locus_count ) = @_;
	return 1  if $locus_count > 600;
	return 2  if $locus_count > 300;
	return 4  if $locus_count > 150;
	return 6  if $locus_count > 100;
	return 12 if $locus_count > 50;
	return 20;
}

sub _get_locus_count {
	my ( $self, $scheme_list ) = @_;
	my %selected_schemes = map { $_ => 1 } @$scheme_list;
	my $set_id           = $self->get_set_id;
	my $scheme_data      = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	my ( $scheme_ids_ref, $desc_ref ) = $self->extract_scheme_desc($scheme_data);
	my $count = 0;
	foreach my $scheme_id (@$scheme_ids_ref) {
		next if !$selected_schemes{$scheme_id};
		my $scheme_loci =
		  $self->{'datastore'}->get_scheme_loci( $scheme_id, { profile_name => 0, analysis_pref => 1 } );
		$count += @$scheme_loci;
	}
	return $count if !$selected_schemes{0};
	my $no_scheme_loci = $self->{'datastore'}->get_loci_in_no_scheme( { analyse_pref => 1, set_id => $set_id } );
	$count += @$no_scheme_loci;
	return $count;
}

sub _make_svg {
	my ( $self, $filename, $bar_width, $values ) = @_;
	open( my $fh, '>', $filename ) or $logger->error("could not open $filename for writing.");
	my $width = @$values * $bar_width;
	print $fh <<"SVG";
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 20001102//EN"
   "http://www.w3.org/TR/2000/CR-SVG-20001102/DTD/svg-20001102.dtd">
   <svg xmlns="http://www.w3.org/2000/svg"
     xmlns:xlink="http://www.w3.org/1999/xlink" width="$width" height="20" viewBox="0 0 $width 10">
SVG
	my $pos     = int( 0.5 * $bar_width );
	my @colours = COLOURS;
	foreach (@$values) {
		say $fh qq(<line x1="$pos" y1="0" x2="$pos" y2="20" )
		  . qq(style="stroke-width: $bar_width; stroke: #$colours[$_];" />);
		$pos += $bar_width;
	}
	say $fh q(</svg>);
	close $fh;
	return;
}

sub _print_tree {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say $q->start_form;
	say q(<p>Select schemes or groups of schemes within the tree. A breakdown of the individual )
	  . q(loci belonging to these schemes will then be performed.</p>);
	say q(<noscript><p class="highlight">You need to enable Javascript in order to select schemes )
	  . q(for analysis.</p></noscript>);
	say q(<fieldset style="float:left"><legend>Select schemes</legend>);
	say q(<div id="tree" class="tree" style="width:30em">);
	say $self->get_tree( undef, { no_link_out => 1, select_schemes => 1, analysis_pref => 1 } );
	say q(</div></fieldset>);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->hidden($_) foreach qw(db page name query_file set_id list_file datatype);
	say $q->end_form;
	return;
}

sub get_plugin_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	\$('#queryform').show();
});
	
END
	return $buffer;
}
1;
