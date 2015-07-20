#BURST.pm - BURST plugin for BIGSdb
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
#
#BURST code is adapted from original C++ version by Man-Suen Chan.
package BIGSdb::Plugins::BURST;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use constant PI => 3.141592654;

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 0, query_field => 0 };
	return;
}

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name        => 'BURST',
		author      => 'Keith Jolley',
		affiliation => 'University of Oxford, UK',
		email       => 'keith.jolley@zoo.ox.ac.uk',
		description => 'Perform BURST cluster analysis on query results query results',
		category    => 'Analysis',
		buttontext  => 'BURST',
		menutext    => 'BURST',
		module      => 'BURST',
		version     => '1.1.2',
		dbtype      => 'isolates,sequences',
		seqdb_type  => 'schemes',
		section     => 'postquery',
		order       => 12,
		system_flag => 'BURST',
		input       => 'query',
		requires    => 'mogrify,pk_scheme',
		url         => "$self->{'config'}->{'doclink'}/data_analysis.html#burst",
		min         => 2,
		max         => 1000
	);
	return \%att;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $scheme_id  = $q->param('scheme_id');
	say q(<h1>BURST analysis</h1>);
	my $list;
	my $pk;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {

		if ( !$scheme_id ) {
			say q(<div class="box" id="statusbad"><p>No scheme id passed.</p></div>);
			return;
		} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
			say q(<div class="box" id="statusbad"><p>Scheme id must be an integer.</p></div>);
			return;
		} else {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
			if ( !$scheme_info ) {
				say q(<div class="box" id="statusbad">Scheme does not exist.</p></div>);
				return;
			}
		}
	}
	if ( $scheme_id && BIGSdb::Utils::is_int($scheme_id) ) {
		$pk =
		  $self->{'datastore'}
		  ->run_query( 'SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key', $scheme_id );
		if ( !$pk ) {
			say q(<div class="box" id="statusbad"><p>No primary key field has been set for this scheme. )
			  . q(Profile concatenation cannot be done until this has been set.</p></div>);
			return;
		}
	}
	if ($query_file) {
		my $qry_ref = $self->get_query($query_file);
		return if ref $qry_ref ne 'SCALAR';
		my $view = $self->{'system'}->{'view'};
		return if !$self->create_temp_tables($qry_ref);
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			$self->rewrite_query_ref_order_by($qry_ref);
		}
		$list = $self->{'datastore'}->run_query( $$qry_ref, undef, { fetch => 'col_arrayref' } );
	} else {
		say q(<div class="box" id="statusbad"><p>No query has been passed.</p></div>);
	}
	if ( $q->param('submit') ) {
		$self->_run_burst( $scheme_id, $pk, $list );
		return;
	}
	say q(<div class="box" id="queryform">)
	  . q(<p>This is the original BURST algorithm, developed by Ed Feil, first implemented by Man-Suen )
	  . q(Chan.  This version has been adapted for use as a plugin for the BIGSdb database software )
	  . q(by Keith Jolley.</p>);
	say q(<p>BURST analysis can be used to:</p><ul>);
	say q(<li>Divide strains into groups according to their allelic profiles.</li>);
	say q(<li>Count the number of Single Locus Variants (SLV), Double Locus Variants (DLV) )
	  . q(and Satellites (SAT) for each sequence type (ST).</li>);
	say q(<li>Identify the potential Ancestral Type (AT). These are shown with an asterisk next to their )
	  . q(names in the results table.</li></ul>);
	say q(<p>Graphic representations of BURST groups can be saved in SVG format.  This is a vector )
	  . q(image format that can be manipulated and scaled in drawing packages, including the freely )
	  . q(available <a href="http://www.inkscape.org">Inkscape</a>.</p>);
	say $q->start_form;
	say $q->hidden($_) foreach qw (db page name query_file list_file datatype);
	my $locus_count;
	say q(<fieldset style="float:left"><legend>Options</legend>);

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $set_id = $self->get_set_id;
		my $scheme_data = $self->{'datastore'}->get_scheme_list( { set_id => $set_id, with_pk => 1 } );
		if ( !@$scheme_data ) {
			say $q->end_form;
			say q(<p class="statusbad">No schemes available.</p></div>);
			return;
		}
		my ( $scheme_ids_ref, $desc_ref ) = $self->extract_scheme_desc($scheme_data);
		if ( @$scheme_ids_ref > 1 ) {
			say q(<p>Select scheme: );
			say $q->popup_menu( -name => 'scheme_id', -values => $scheme_ids_ref, -labels => $desc_ref );
			say q(</p>);
		} else {
			say qq(<p>Scheme: $desc_ref->{$scheme_ids_ref->[0]}</p>);
			$q->param( 'scheme_id', $scheme_ids_ref->[0] );
			say $q->hidden('scheme_id');
		}
		$locus_count =
		  $self->{'datastore'}
		  ->run_query( 'SELECT COUNT(*) FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM '
			  . 'scheme_fields WHERE primary_key) GROUP BY scheme_id ORDER BY COUNT(*) desc LIMIT 1' );
	} else {
		$locus_count =
		  $self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM scheme_members WHERE scheme_id=?', $scheme_id );
		$q->param( scheme_id => $scheme_id );
		say $q->hidden('scheme_id');
	}
	say q(<p>Group definition: profiles match at );
	my @values;
	for my $i ( 1 .. $locus_count - 1 ) {
		push @values, "n-$i";
	}
	say $q->popup_menu( -name => 'grpdef', -value => [@values], -default => 'n-2' );
	say q( loci to any other member of the group <span class="comment">)
	  . q([n = number of loci in scheme]</span>.</p><p>);
	say $q->checkbox( -name => 'shade', -label => 'Shade variant rings', -checked => 1 );
	say q(<br />);
	say $q->checkbox(
		-name    => 'hide',
		-label   => 'Hide variant names (useful for overview if names start to overlap)',
		-checked => 0
	);
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1 } );
	say $q->end_form;
	say q(</div>);
	return;
}

sub _run_burst {
	my ( $self, $scheme_id, $pk, $list ) = @_;
	local $| = 1;
	say q(<div class="hideonload"><p>Please wait - calculating (do not refresh) ...</p>)
	  . q(<p><span class="main_icon fa fa-refresh fa-spin fa-4x"></span></p></div>);
	$self->{'mod_perl_request'}->rflush if $ENV{'MOD_PERL'};
	my ( $loci, $profiles_ref, $profile_freq_ref, $num_profiles ) = $self->_get_profile_array( $scheme_id, $pk, $list );
	my ( $matrix_ref, $error ) = $self->_generate_distance_matrix( $loci, $num_profiles, $profiles_ref );
	if ($error) {
		say qq(<div class="box" id="statusbad"><p>$error</p></div>);
		return;
	}
	if ( !$num_profiles ) {
		say q(<div class="box" id="statusbad"><p>No complete profiles were )
		  . q(returned for the selected scheme.</p></div>);
		return;
	}
	$self->_recursive_search(
		{
			loci             => $loci,
			num_profiles     => $num_profiles,
			profiles_ref     => $profiles_ref,
			matrix_ref       => $matrix_ref,
			profile_freq_ref => $profile_freq_ref,
			primary_key      => $pk
		}
	);
	return;
}

sub _get_profile_array {
	my ( $self, $scheme_id, $pk, $list ) = @_;
	my @profiles;
	my %st_frequency;
	my $num_profiles = 0;
	my $loci         = $self->{'datastore'}->get_scheme_loci($scheme_id);
	foreach (@$loci) {
		$_ =~ s/'/_PRIME_/gx;
	}
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $i = 0;
		foreach my $st (@$list) {
			local $" = ',';
			my @profile = $self->{'datastore'}->run_query( "SELECT $pk,@$loci FROM scheme_$scheme_id WHERE $pk=?",
				$st, { cache => 'BURST::get_profile_array' } );
			my $j = 0;
			if ( $st_frequency{ $profile[0] } ) {
				$st_frequency{ $profile[0] }++;
			} else {
				foreach (@profile) {
					$profiles[$i][$j] = $profile[$j];
					$j++;
				}
				$st_frequency{ $profile[0] } = 1;
				$num_profiles++;
				$i++;
			}
		}
	} else {    #isolate db
		my $scheme        = $self->{'datastore'}->get_scheme($scheme_id);
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		my $i             = 0;
		my $field_pos;
		foreach ($scheme_fields) {
			if ( $scheme_fields->[$i] eq $pk ) {
				$field_pos = $i;
			}
			$i++;
		}
		$i = 0;
		foreach my $id (@$list) {
			my $scheme_field_values =
			  $self->get_scheme_field_values( { isolate_id => $id, field => $pk, scheme_id => $scheme_id } );
			foreach my $st (@$scheme_field_values) {
				my $profile = $self->{'datastore'}->get_profile_by_primary_key( $scheme_id, $st );
				unshift @$profile, $st;
				my $j = 0;
				if ( $st_frequency{$st} ) {
					$st_frequency{$st}++;
				} else {
					foreach (@$profile) {
						$profiles[$i][$j] = $profile->[$j];
						$j++;
					}
					$st_frequency{$st} = 1;
					$num_profiles++;
					$i++;
				}
			}
		}
		@profiles = sort { @{$a}[0] <=> @{$b}[0] } @profiles;
	}
	return ( $loci, \@profiles, \%st_frequency, $num_profiles );
}

sub _generate_distance_matrix {
	my ( $self, $loci, $num_profiles, $profiles_ref ) = @_;
	my @profiles = @{$profiles_ref};
	my @matrix;
	my $error;
	for ( my $i = 0 ; $i < $num_profiles ; $i++ ) {
		for ( my $j = 0 ; $j < $num_profiles ; $j++ ) {
			my $same = 0;
			for ( my $k = 1 ; $k < @$loci + 1 ; $k++ ) {
				if ( defined $profiles[$i][$k] && defined $profiles[$j][$k] && $profiles[$i][$k] eq $profiles[$j][$k] )
				{
					$same++;
				}
				$matrix[$i][$j] = $same;
				if ( $same == @$loci ) {
					if ( $profiles[$i][0] != $profiles[$j][0] ) {
						$error = "STs $profiles[$i][0] and $profiles[$j][0] have the same profile.";
						last;
					}
				}
			}
		}
	}
	return ( \@matrix, $error );
}

sub _recursive_search {
	my ( $self, $args ) = @_;
	my ( $loci, $num_profiles, $profiles_ref, $matrix_ref, $profile_freq_ref, $pk ) =
	  @{$args}{qw (loci num_profiles profiles_ref matrix_ref profile_freq_ref primary_key)};
	$pk //= 'ST';
	my @profiles = @{$profiles_ref};
	my @matrix   = @{$matrix_ref};
	my %st_freq  = %$profile_freq_ref;
	my @result;
	my $grpdef = $self->{'cgi'}->param('grpdef') || 'n-2';

	if ( $grpdef =~ /n\-(\d+)/x ) {
		$grpdef = @$loci - $1;
	}
	if (   !BIGSdb::Utils::is_int($grpdef)
		|| $grpdef < 1
		|| $grpdef > @$loci - 1 )
	{
		say q(<div class="box" id="statusbad"><p>Invalid group definition selected.</p></div>);
		return;
	}
	my $g = 0;
	my @grp;
	for ( my $search = 0 ; $search < $num_profiles ; $search++ ) {
		if ( !defined $grp[$search] || $grp[$search] == 0 ) {
			$g++;
			$self->_dfs(
				{
					profile_count => $num_profiles,
					x             => $search,
					matrix_ref    => $matrix_ref,
					grp_ref       => \@grp,
					grpdef        => $grpdef,
					g             => $g
				}
			);
		}
	}
	my $ng = $g + 1;

	#calculate group details
	my $h = 0;
	say q(<div class="box" id="resultstable">);
	local $| = 1;
	say q(<h2>Groups:</h2>);
	say qq(<strong>Group definition: $grpdef or more matches</strong>);
	if ( $self->{'config'}->{'mogrify_path'} ) {
		say qq(<p>Groups with central $pk will be displayed as an image.</p>);
	}
	my $td = 1;
	my @groupSize;
	for ( my $group = 0 ; $group < $ng ; $group++ ) {
		my $thisGroupSize = 0;
		my $maxslv        = 0;
		my $noancestor    = 0;
		my $ancestor      = 0;
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			if ( $self->{'mod_perl_request'}->connection->aborted ) {
				return;
			}
		}
		for ( my $i = 0 ; $i < $num_profiles ; $i++ ) {
			$grp[$i] ||= 0;
			for ( my $j = 0 ; $j < $num_profiles ; $j++ ) {
				if ( ( $grp[$i] == $group ) && ( $grp[$j] == $group ) ) {
					if ( $matrix[$i][$j] == @$loci ) {
						next;
					} elsif ( $matrix[$i][$j] == ( @$loci - 1 ) ) {
						$result[0][$i]++;
					} elsif ( $matrix[$i][$j] == ( @$loci - 2 ) ) {
						$result[1][$i]++;
					} else {
						$result[2][$i]++;

						# result[0][i]=slvs,[1][i]=dlvs,[2][i]=sats
					}
				}
			}
			if ( ( $grp[$i] == $group ) && ( defined $result[0][$i] && $result[0][$i] > $maxslv ) ) {
				$maxslv = $result[0][$i];

				#maxdlv=result[1][$i];
				$ancestor = $i;
			}
			if ( $grp[$i] == $group ) {
				$thisGroupSize++;
				$groupSize[$i] = $thisGroupSize;
			}
		}
		my @grpDisMat;
		my @st;
		my $at = 0;
		if ( $thisGroupSize > 1 ) {
			$h++;
			say q(<div class="scrollable" style="margin-bottom:1em">);
			say qq(<table class="resultstable"><tr><th colspan="5">group: $h</th></tr>);
			say qq(<tr><th>$pk</th><th>Frequency</th><th>SLV</th><th>DLV</th><th>SAT</th></tr>);
			if ( $maxslv < 2 ) {
				$noancestor = 1;
			} else {
				for ( my $i = 1 ; $i < $num_profiles + 1 ; $i++ ) {
					$grp[$i] ||= 0;
					$result[0][$i] ||= 0;

					#check for equal slv
					if (   ( $grp[$i] == $group )
						&& ( $result[0][$i] == $maxslv )
						&& ( $i != $ancestor ) )
					{
						for ( my $j = 0 ; $j < $num_profiles ; $j++ ) {
							$grp[$j]       ||= 0;
							$result[0][$j] ||= 0;
							$result[1][$j] ||= 0;
							$result[1][$i] ||= 0;
							if (   ( $grp[$j] == $group )
								&& ( $result[0][$j] == $maxslv )
								&& ( $result[1][$j] > $result[1][$i] ) )
							{
								$ancestor = $j;
							} elsif ( ( $grp[$j] == $group )
								&& ( $i != $j )
								&& ( $result[0][$j] == $maxslv )
								&& ( $result[1][$j] == $result[1][$i] ) )
							{
								$st_freq{$i} ||= 0;
								$st_freq{$j} ||= 0;
								if ( $st_freq{$j} > $st_freq{$i} ) {
									$ancestor = $j;
								} elsif ( $st_freq{$j} == $st_freq{$i} ) {
									$noancestor = 1;
								} else {
									$ancestor = $i;
								}
							} else {
								next;
							}
						}
					}
				}
			}
			my $stCount = 0;
			for ( my $i = 0 ; $i < $num_profiles ; $i++ ) {
				if ( $grp[$i] == $group ) {
					$groupSize[$i] = $thisGroupSize;
					my $anc;
					if ( $i == $ancestor ) {
						$anc = '*';
					} else {
						$anc = ' ';
					}
					if ($noancestor) {
						$anc = ' ';
					}
					say qq(<tr class="td$td">);
					say qq(<td>$profiles[$i][0]$anc</td>);
					say qq(<td>$st_freq{$profiles[$i][0]}</td>);
					say defined $result[0][$i] ? "<td>$result[0][$i]</td>" : '<td></td>';
					say defined $result[1][$i] ? "<td>$result[1][$i]</td>" : '<td></td>';
					say defined $result[2][$i] ? "<td>$result[2][$i]</td>" : '<td></td>';
					say q(</tr>);
					$td = $td == 1 ? 2 : 1;    #row stripes
					$st[$stCount] = $profiles[$i][0];
					my $stCount2 = 0;

					for ( my $j = 0 ; $j < $i ; $j++ ) {
						if ( $grp[$j] == $group ) {
							$grpDisMat[$stCount][$stCount2] = ( @$loci - $matrix[$i][$j] );
							$st[$stCount] = $profiles[$i][0];
							$stCount2++;
						}
					}
					$stCount++;
				}
			}
			if ($noancestor) {
				$at = 0;
			} else {
				$at = $profiles[$ancestor][0];
			}
		}
		if ( $thisGroupSize > 2 && !$noancestor ) {

			# Fill in other diagonal of group distance matrix
			for ( my $i = 0 ; $i < $thisGroupSize ; $i++ ) {
				for ( my $j = $i ; $j < $thisGroupSize ; $j++ ) {
					if ( $i == $j ) {
						$grpDisMat[$i][$j] = 0;
					} else {
						$grpDisMat[$i][$j] = $grpDisMat[$j][$i];
					}
				}
			}
			if ( $self->{'config'}->{'mogrify_path'} ) {
				my $imageFile = $self->_create_group_graphic( \@st, \@grpDisMat, $at );
				say q(<tr class="td2"><td colspan="5" style="border:1px dashed black">)
				  . qq(<img src="/tmp/$imageFile.png" alt="BURST group" /></td></tr>);
				say qq(<tr class="td1"><td colspan="5"><a href="/tmp/$imageFile.svg">)
				  . q(SVG file</a> (right click to save)</td></tr>);
			}
		}
		say q(</table></div>) if ( $thisGroupSize > 1 );
	}

	# print singles
	say q(<h2>Singletons:</h2>);
	my $buffer = qq(<div class="scrollable"><table class="resultstable"><tr><th>$pk</th><th>Frequency</th></tr>);
	$td = 1;
	my $count;
	for ( my $i = 0 ; $i < $num_profiles ; $i++ ) {
		if ( $groupSize[$i] == 1 ) {
			$buffer .= qq(<tr class="td$td"><td>$profiles[$i][0]</td><td>);
			$buffer .= qq($st_freq{$profiles[$i][0]}</td></tr>\n);
			$td = $td == 1 ? 2 : 1;    #row stripes
			$count++;
		}
	}
	$buffer .= q(</table></div>);
	say $count ? $buffer : q(<p>None</p>);
	say q(</div>);
	return;
}

sub _dfs {
	my ( $self, $args ) = @_;
	my ( $profile_count, $x, $matrix_ref, $grp_ref, $grpdef, $g ) =
	  @{$args}{qw(profile_count x matrix_ref grp_ref grpdef g)};
	for my $y ( 0 .. $profile_count - 1 ) {
		if (   ( !defined $$grp_ref[$y] || $$grp_ref[$y] == 0 )
			&& ( $$matrix_ref[$x][$y] > ( $grpdef - 1 ) ) )
		{
			$$grp_ref[$y] = $g;
			{
				no warnings 'recursion';
				$self->_dfs(
					{
						profile_count => $profile_count,
						x             => $y,
						matrix_ref    => $matrix_ref,
						grp_ref       => $grp_ref,
						grpdef        => $grpdef,
						g             => $g
					}
				);
			}
		}
	}
	return;
}

sub _create_group_graphic {
	my ( $self, $st_ref, $dismat_ref, $at ) = @_;
	my $q       = $self->{'cgi'};
	my $temp    = BIGSdb::Utils::get_random();
	my $scale   = 5;
	my $num_sts = @$dismat_ref;
	my ( @assigned, @posntaken, @atPosn, @radius, @atList, $atRow );
	my $filename = "$temp\_$at";
	my $noAT     = 0;

	#work out data row associated with AT
	for my $i ( 0 .. $num_sts - 1 ) {
		$radius[$i] = 0;
		$atRow = $i if $st_ref->[$i] == $at;
	}
	$atList[0] = $atRow;
	for my $j ( 0 .. $num_sts - 1 ) {
		$assigned[$j] ||= 0;
		$assigned[$j] = $dismat_ref->[$atRow]->[$j] == 1 && ( $assigned[$j] == 0 ) ? -1 : -9;
	}
	( $assigned[$atRow], $radius[$atRow] ) = ( $atRow, 0 );

	#find other ATs
	for my $at ( 1 .. 8 ) {
		my $maxslv = 0;
		$posntaken[$at] = 0;
		$atPosn[$at]    = 0;
		for my $i ( 0 .. $num_sts - 1 ) {
			my $SLVs = 0;
			for ( my $j = 0 ; $j < $num_sts ; $j++ ) {
				if ( $dismat_ref->[$i]->[$j] == 1 && ( $assigned[$j] == -9 ) ) {
					$SLVs++;
				}
			}
			if ( $SLVs > $maxslv ) {
				$atList[$at] = $i;
				$maxslv = $SLVs;
			}
		}
		my $i = $atList[$at] || 0;
		for my $j ( 0 .. $num_sts - 1 ) {
			if ( $dismat_ref->[$i]->[$j] == 1 && ( $assigned[$j] == -9 ) ) {
				$assigned[$j] = -1;    #temp assignment;
			}
		}
		last if $maxslv < 2;
		$noAT                     = $at;
		$assigned[ $atList[$at] ] = $atList[$at];
		$radius[ $atList[$at] ]   = 0;
	}
	my $unit = 6 * $scale;
	my $size;

	# You can get three ATs in a diagonal with a group defined as an SLV of a SLV.
	# We can only make the canvas medium sized therefore when there is one auxiliary AT.
	if    ( $noAT == 0 ) { $size = 11 * $unit }
	elsif ( $noAT == 1 ) { $size = 21 * $unit }
	else                 { $size = 29 * $unit }
	my $buffer = <<"SVG";
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN"
"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg width="$size" height="$size" version="1.1" xmlns="http://www.w3.org/2000/svg">
SVG

	#define positions for circles
	my ( $posnX, $posnY ) = $self->_define_circle_positions( $size, $unit );
	for my $i ( 0 .. $num_sts - 1 ) {
		$assigned[$i] = -9 if $assigned[$i] == -1;    #unassign temp assignments
	}
	my $count = 0;

	#connected directly to centre
	( $atPosn[0], $posntaken[0] ) = ( 0, 1 );
	my ( @conncentre, @angleValue );
	for my $at ( 1 .. $noAT ) {
		if ( $dismat_ref->[$atRow]->[ $atList[$at] ] == 1 ) {
			$conncentre[$at] = 1;
			$count++;
			$atPosn[$at]       = $count;
			$posntaken[$count] = 1;
			my $x1 = $posnX->[ $atPosn[0] ];
			my $y1 = $posnY->[ $atPosn[0] ];
			my $x2 = $posnX->[ $atPosn[$at] ];
			my $y2 = $posnY->[ $atPosn[$at] ];
			( $x1, $y1, $x2, $y2 ) = $self->_offset_line( $x1, $y1, $x2, $y2, $unit );
			$buffer .=
			  qq(<line x1="$x1" y1="$y1" x2="$x2" y2="$y2" ) . q(stroke="black" opacity="0.2" stroke-width="1"/>);
		} else {
			$conncentre[$at] = 0;
		}
	}

	#connect to inner circle
	for my $at ( 1 .. $noAT ) {
		if ( !$conncentre[$at] ) {
			for ( my $k = 1 ; $k < $noAT + 1 ; $k++ ) {
				if (   $conncentre[$k]
					&& $dismat_ref->[ $atList[$at] ]->[ $atList[$k] ] == 1 )
				{
					$atPosn[$at] = $atPosn[$k] + 4;
					$posntaken[ $atPosn[$k] + 4 ] = 1;
					my $x1 = $posnX->[ $atPosn[$k] ];
					my $y1 = $posnY->[ $atPosn[$k] ];
					my $x2 = $posnX->[ $atPosn[$at] ];
					my $y2 = $posnY->[ $atPosn[$at] ];
					( $x1, $y1, $x2, $y2 ) = $self->_offset_line( $x1, $y1, $x2, $y2, $unit );
					$buffer .= qq(<line x1="$x1" y1="$y1" x2="$x2" y2="$y2" ) . q(stroke="black" stroke-width="1"/>);
					$buffer .=
					    qq(<circle stroke="black" fill="none" cx="$posnX->[$atPosn[$at]]" )
					  . qq(cy="$posnY->[$atPosn[$at]]" r=")
					  . ( $unit / 2 ) . q("/>);
				}
			}
		}
	}
	for my $at ( 1 .. $noAT ) {
		my $k;
		if ( $atPosn[$at] == 0 ) {    #unpositioned
			                          #assign to lowest untaken posn
			$k = 0;
			while ( $posntaken[$k] ) {
				$k++;
			}
			$atPosn[$at]   = $k;
			$posntaken[$k] = 1;
		}
	}
	my $angleOffset = 0;
	$buffer .= $self->_draw_slv_rings(
		{
			noAT       => $noAT,
			unit       => $unit,
			posnX      => $posnX,
			posnY      => $posnY,
			atPosn_ref => \@atPosn,
			st_ref     => $st_ref,
			atList_ref => \@atList,
		}
	);
	$buffer .= $self->_draw_ring_sts(
		{
			noAT            => $noAT,
			num_sts         => $num_sts,
			dismat_ref      => $dismat_ref,
			atList_ref      => \@atList,
			assigned_ref    => \@assigned,
			radius_ref      => \@radius,
			angle_value_ref => \@angleValue,
			posnX           => $posnX,
			posnY           => $posnY,
			st_ref          => $st_ref,
			unit            => $unit,
			atPosn_ref      => \@atPosn,
			angle_offset    => $angleOffset
		}
	);
	$buffer .= $self->_draw_spokes(
		{
			noAT            => $noAT,
			num_sts         => $num_sts,
			dismat_ref      => $dismat_ref,
			atList_ref      => \@atList,
			assigned_ref    => \@assigned,
			radius_ref      => \@radius,
			angle_value_ref => \@angleValue,
			st_ref          => $st_ref,
			unit            => $unit,
			posnX           => $posnX,
			posnY           => $posnY,
			atPosn_ref      => \@atPosn,
		}
	);
	$buffer .= qq(</svg>\n);
	my $svg_filename = "$self->{'config'}->{'tmp_dir'}/$filename.svg";
	open( my $fh, '>', $svg_filename ) || $logger->error("Can't open $svg_filename for writing");
	print $fh $buffer;
	close $fh;
	system( $self->{'config'}->{'mogrify_path'},
		-format => 'png',
		"$self->{'config'}->{'tmp_dir'}/$filename.svg", "$self->{'config'}->{'tmp_dir'}/$filename.png"
	);
	return $filename;
}

sub _draw_slv_rings {
	my ( $self, $args ) = @_;
	my $noAT       = $args->{'noAT'};
	my $posnX      = $args->{'posnX'};
	my $posnY      = $args->{'posnY'};
	my $atPosn_ref = $args->{'atPosn_ref'};
	my $unit       = $args->{'unit'};
	my $st_ref     = $args->{'st_ref'};
	my $atList_ref = $args->{'atList_ref'};
	my $buffer     = '';
	for my $at ( 0 .. $noAT ) {

		#Draw SLV ring
		if ( $self->{'cgi'}->param('shade') ) {
			$buffer .=
			    qq(<circle stroke="black" fill="black" fill-opacity="0.1" cx="$posnX->[$atPosn_ref->[$at]]" )
			  . qq(cy="$posnY->[$atPosn_ref->[$at]]" r=")
			  . ( $unit / 2 )
			  . qq("/>\n);
		} else {
			$buffer .=
			    qq(<circle stroke="black" fill="none" cx="$posnX->[$atPosn_ref->[$at]]" )
			  . qq(cy="$posnY->[$atPosn_ref->[$at]]" r=")
			  . ( $unit / 2 )
			  . qq("/>\n);
		}
		if ( $self->{'cgi'}->param('shade') ) {
			$buffer .=
			    qq(<circle stroke="red" stroke-width="$unit" stroke-opacity="0.1" fill="none" )
			  . qq(cx="$posnX->[$atPosn_ref->[$at]]" cy="$posnY->[$atPosn_ref->[$at]]" r=")
			  . ($unit)
			  . qq("/>\n);
		}
		$buffer .=
		    qq(<circle stroke="red" fill="none" cx="$posnX->[$atPosn_ref->[$at]]" )
		  . qq(cy="$posnY->[$atPosn_ref->[$at]]" r=")
		  . ( 1.5 * $unit )
		  . qq("/>\n);
		my $x = $posnX->[ $atPosn_ref->[$at] ] - length( $st_ref->[ $atList_ref->[$at] ] ) * 2;
		my $y = $posnY->[ $atPosn_ref->[$at] ] + 4;
		$buffer .= qq(<text x="$x" y="$y" font-size="9">$st_ref->[$atList_ref->[$at]]</text>\n);
	}
	return $buffer;
}

sub _draw_ring_sts {
	my ( $self, $args ) = @_;
	my $noAT            = $args->{'noAT'};
	my $num_sts         = $args->{'num_sts'};
	my $dismat_ref      = $args->{'dismat_ref'};
	my $atList_ref      = $args->{'atList_ref'};
	my $assigned_ref    = $args->{'assigned_ref'};
	my $posnX           = $args->{'posnX'};
	my $posnY           = $args->{'posnY'};
	my $atPosn_ref      = $args->{'atPosn_ref'};
	my $st_ref          = $args->{'st_ref'};
	my $radius_ref      = $args->{'radius_ref'};
	my $angle_value_ref = $args->{'angle_value_ref'};
	my $unit            = $args->{'unit'};
	my $angle_offset    = $args->{'angle_offset'};
	my $buffer;

	for my $distance ( 1 .. 2 ) {
		for my $at ( 0 .. $noAT ) {
			my $circle = 0;
			for ( my $j = 0 ; $j < $num_sts ; $j++ ) {
				if ( $dismat_ref->[ $atList_ref->[$at] ]->[$j] == $distance
					&& ( $assigned_ref->[$j] == -9 ) )
				{
					$circle++;
				}
			}
			if ( $distance == 2 && $circle != 0 ) {

				#draw outer circle if there are DLVs
				if ( $self->{'cgi'}->param('shade') ) {
					$buffer .=
					    qq(<circle stroke="blue" stroke-width="$unit" stroke-opacity="0.1" fill="none" )
					  . qq(cx="$posnX->[$atPosn_ref->[$at]]" cy="$posnY->[$atPosn_ref->[$at]]" r=")
					  . ( 2 * $unit )
					  . qq("/>\n);
				}
				$buffer .=
				    qq(<circle stroke="blue" fill="none" cx="$posnX->[$atPosn_ref->[$at]]" )
				  . qq(cy="$posnY->[$atPosn_ref->[$at]]" r=")
				  . ( 2.5 * $unit )
				  . qq("/>\n);
				$angle_offset += 2 * PI * 10 / 360;
			}
			if ( $circle != 0 ) {
				my $angle = 2 * PI / $circle;
				my $k     = 0;
				for my $j ( 0 .. $num_sts - 1 ) {
					if ( $dismat_ref->[ $atList_ref->[$at] ]->[$j] == $distance
						&& ( $assigned_ref->[$j] == -9 ) )
					{
						$k++;
						my $x = int(
							$posnX->[ $atPosn_ref->[$at] ] + cos( $angle * $k + $angle_offset ) * $unit * $distance );
						my $y = int(
							$posnY->[ $atPosn_ref->[$at] ] + sin( $angle * $k + $angle_offset ) * $unit * $distance );
						if ( $self->{'cgi'}->param('hide') ) {
							my $colour;
							if    ( $distance == 1 ) { $colour = 'red' }
							elsif ( $distance == 2 ) { $colour = 'blue' }
							else                     { $colour = 'black' }
							$buffer .= "<circle fill=\"$colour\" stroke=\"$colour\" cx=\"$x\" cy=\"$y\" r=\"2\" \/>";
						} else {
							$x -= length( $st_ref->[$j] ) * 2;
							$y += 4;
							$buffer .= "<text x=\"$x\" y=\"$y\" font-size=\"9\">$st_ref->[$j]</text>\n";
						}
						( $assigned_ref->[$j], $radius_ref->[$j], $angle_value_ref->[$j] ) =
						  ( $atList_ref->[$at], $distance, $angle * $k + $angle_offset );
					}
				}
			}
		}
	}
	return $buffer;
}

sub _draw_spokes {
	my ( $self, $args ) = @_;
	my $noAT            = $args->{'noAT'};
	my $num_sts         = $args->{'num_sts'};
	my $dismat_ref      = $args->{'dismat_ref'};
	my $atList_ref      = $args->{'atList_ref'};
	my $assigned_ref    = $args->{'assigned_ref'};
	my $radius_ref      = $args->{'radius_ref'};
	my $angle_value_ref = $args->{'angle_value_ref'};
	my $st_ref          = $args->{'st_ref'};
	my $unit            = $args->{'unit'};
	my $posnX           = $args->{'posnX'};
	my $posnY           = $args->{'posnY'};
	my $atPosn_ref      = $args->{'atPosn_ref'};
	my $at              = $args->{'at'};
	my $buffer          = '';
	for my $at ( 0 .. $noAT ) {

		for my $run ( 0 .. 4 ) {
			my ( $anchor, $satellite );
			if    ( $run == 0 ) { $anchor = 2; $satellite = 1 }
			elsif ( $run == 1 ) { $anchor = 1; $satellite = 2 }
			elsif ( $run == 2 ) { $anchor = 2; $satellite = 2 }
			elsif ( $run == 3 ) { $anchor = 3; $satellite = 1 }
			else                { $anchor = 3; $satellite = 2 }
			my ( @thisgo, $distance );
			for my $k ( 0 .. $num_sts - 1 ) {
				my ( $textOffset, $xOffset, $yOffset ) = ( 0, 0, 0 );
				if ( $dismat_ref->[ $atList_ref->[$at] ]->[$k] == $anchor ) {    #anchor
					for ( my $j = 0 ; $j < $num_sts ; $j++ ) {
						if (   $dismat_ref->[ $atList_ref->[$at] ]->[$j] > 2
							&& ( $assigned_ref->[$j] == -9 )
							&& ( $assigned_ref->[$k] == $atList_ref->[$at] ) )
						{
							if ( $dismat_ref->[$j]->[$k] == $satellite && !$thisgo[$j] ) {

								#prevent proliferation of satellites
								my $colour;
								if ( $satellite == 2 ) {                         #DLVs only
									( $colour, $distance ) = ( 'blue', 2 );
								} else {

									# offset ensures that red line is not obscured by blue line
									( $colour, $distance, $xOffset, $yOffset ) = ( 'red', 1, 1, 2 );
								}
								my $posXAnchor =
								  int( $posnX->[ $atPosn_ref->[$at] ] +
									  $xOffset +
									  cos( $angle_value_ref->[$k] ) * $unit * $radius_ref->[$k] );
								my $posYAnchor =
								  int( $posnY->[ $atPosn_ref->[$at] ] +
									  $yOffset +
									  sin( $angle_value_ref->[$k] ) * $unit * $radius_ref->[$k] );
								my $posX =
								  int( $posnX->[ $atPosn_ref->[$at] ] +
									  $xOffset +
									  cos( $angle_value_ref->[$k] ) * $unit * ( $distance + $radius_ref->[$k] ) );
								my $posX_text = $posX;
								if ( $posX < $posXAnchor ) {
									$posX_text -= length( $st_ref->[$j] ) * 5;
								}
								my $posY =
								  int( $posnY->[ $atPosn_ref->[$at] ] +
									  $yOffset +
									  sin( $angle_value_ref->[$k] ) * $unit * ( $distance + $radius_ref->[$k] ) );
								my $posY_text = $posY;
								$posY_text += 4 if $posYAnchor < $posY;
								$buffer .= qq(<line x1="$posXAnchor" y1="$posYAnchor" x2="$posX" )
								  . qq(y2="$posY" stroke="$colour" opacity="0.2" stroke-width="1"/>\n);
								if ( $self->{'cgi'}->param('hide') ) {
									$posX -= $xOffset;
									$buffer .= qq(<circle fill="black" stroke="black" cx="$posX" cy="$posY" r="2" />);
								} else {
									if ( $textOffset == 0 ) {
										$buffer .= qq(<text x="$posX_text" y="$posY_text" )
										  . qq(font-size="9">$st_ref->[$j]</text>\n);
										$textOffset += 8;
									} else {
										$buffer .=
										    qq(<text x="$posX_text" y=")
										  . ( $posY_text + $textOffset )
										  . qq(" font-size="9">$st_ref->[$j]</text>\n);
									}
								}
								( $thisgo[$j], $assigned_ref->[$j], $angle_value_ref->[$j], $radius_ref->[$j] ) =
								  ( 1, $atList_ref->[$at], $angle_value_ref->[$k], $radius_ref->[$k] + $satellite );
							}
						}
					}
				}
			}
		}
	}
	return $buffer;
}

sub _offset_line {
	my ( $self, $x1, $y1, $x2, $y2, $unit ) = @_;
	my $line_offset = int( sin( 0.25 * PI ) * ( $unit / 2 ) );
	if ( $x2 > $x1 ) {
		$x2 = $x2 - $line_offset;
		$x1 = $x1 + $line_offset;
	} else {
		$x2 = $x2 + $line_offset;
		$x1 = $x1 - $line_offset;
	}
	if ( $y2 > $y1 ) {
		$y2 = $y2 - $line_offset;
		$y1 = $y1 + $line_offset;
	} else {
		$y2 = $y2 + $line_offset;
		$y1 = $y1 - $line_offset;
	}
	return ( $x1, $y1, $x2, $y2 );
}

sub _define_circle_positions {
	my ( $self, $size, $unit ) = @_;
	my ( @posnX, @posnY );
	$posnX[0] = $size / 2;
	$posnY[0] = $size / 2;
	$posnX[1] = $posnX[0] - 6 * $unit;
	$posnY[1] = $posnY[0] + 6 * $unit;
	$posnX[2] = $posnX[0] + 6 * $unit;
	$posnY[2] = $posnY[0] - 6 * $unit;
	$posnX[3] = $posnX[0] + 6 * $unit;
	$posnY[3] = $posnY[0] + 6 * $unit;
	$posnX[4] = $posnX[0] - 6 * $unit;
	$posnY[4] = $posnY[0] - 6 * $unit;
	$posnX[5] = $posnX[0] - 10 * $unit;
	$posnY[5] = $posnY[0] + 10 * $unit;
	$posnX[6] = $posnX[0] + 10 * $unit;
	$posnY[6] = $posnY[0] - 10 * $unit;
	$posnX[7] = $posnX[0] + 10 * $unit;
	$posnY[7] = $posnY[0] + 10 * $unit;
	$posnX[8] = $posnX[0] - 10 * $unit;
	$posnY[8] = $posnY[0] - 10 * $unit;
	return ( \@posnX, \@posnY );
}
1;
