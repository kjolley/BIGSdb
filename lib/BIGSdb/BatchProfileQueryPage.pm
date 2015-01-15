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
package BIGSdb::BatchProfileQueryPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Batch profile query - $desc";
}

sub initiate {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('function') && $self->{'cgi'}->param('function') eq 'examples' ) {
		$self->{'type'} = 'text';
	} else {
		$self->{'jQuery'} = 1;
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('function') && $q->param('function') eq 'examples' ) {
		$self->_print_examples;
		return;
	}
	my $scheme_id = $q->param('scheme_id');
	my $desc      = $self->get_db_description;
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		say "<h1>Batch profile query - $desc</h1>";
		say qq(<div class="box" id="statusbad"><p>This function is only available for sequence definition databases.</p></div>);
		return;
	}
	say "<h1>Batch profile query - $desc</h1>";
	if ( !$q->param('profiles') ) {
		return if defined $scheme_id && $self->is_scheme_invalid( $scheme_id, { with_pk => 1 } );
		$self->print_scheme_section( { with_pk => 1 } );
		$scheme_id = $q->param('scheme_id');    #Will be set by scheme section method
	}
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my @cleaned_loci;
	push @cleaned_loci, $self->clean_locus($_) foreach @$loci;
	if ( $q->param('profiles') ) {
		my $profiles = $q->param('profiles');
		my @rows = split /\n/, $profiles;
		local $" = '</th><th>';
		say qq(<div class="box" id="resultstable">);
		say qq(<div class="scrollable">);
		say qq(<table class="resultstable"><tr><th>Isolate</th><th>@cleaned_loci</th>);
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		foreach my $field (@$scheme_fields) {
			my $cleaned = $field;
			$cleaned =~ tr/_/ /;
			print "<th>$cleaned</th>";
		}
		local $" = ',';
		my $scheme_view     = $self->{'datastore'}->materialized_view_exists($scheme_id) ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
		my $qry             = "SELECT @$scheme_fields FROM $scheme_view WHERE ";
		my @cleaned_loci_db = @$loci;
		$_ =~ s/'/_PRIME_/g foreach @cleaned_loci_db;
		my $set_id = $self->get_set_id;
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		local $" = $scheme_info->{'allow_missing_loci'} ? " IN (?, 'N')) AND (" : '=?) AND (';
		$qry .= $scheme_info->{'allow_missing_loci'} ? "(@cleaned_loci_db IN (?, 'N'))" : "(@cleaned_loci_db=?)";
		say "</tr>";
		my $td = 1;
		local $| = 1;

		foreach my $row (@rows) {
			my @profile = split /\t/, $row;
			my $isolate = shift @profile;
			foreach my $allele (@profile) {
				$allele =~ s/^\s+//g;
				$allele =~ s/\s+$//g;
			}
			say qq(<tr class="td$td"><td>$isolate</td>);
			for my $i ( 0 .. @$loci - 1 ) {
				if ( $profile[$i] ) {
					print "<td>$profile[$i]</td>";
				} else {
					print qq(<td class="statusbad" style="font-size:2em">-</td>);
				}
			}
			my $incomplete;
			my @field_data;
			if ( @profile >= @$loci ) {
				while ( @profile > @$loci ) {
					pop @profile;
				}
				@field_data = $self->{'datastore'}->run_query( $qry, \@profile, { catch => 'BatchProfileQueryPage::print_content' } );
			} else {
				$incomplete = 1;
			}
			my $i = 0;
			foreach (@$scheme_fields) {
				if ( exists $field_data[$i] ) {
					print defined $field_data[$i] ? "<td>$field_data[$i]</td>" : '<td></td>';
				} else {
					print qq(<td class="statusbad" style="font-size:2em">-</td>);
				}
				$i++;
			}
			say "</tr>";
			$td = $td == 1 ? 2 : 1;
			if ( $ENV{'MOD_PERL'} ) {
				$self->{'mod_perl_request'}->rflush;
				return if $self->{'mod_perl_request'}->connection->aborted;
			}
		}
		say "</table>\n</div></div>";
		return;
	}
	say qq(<div class="box" id="queryform">);
	say $q->start_form;
	say $q->hidden($_) foreach qw (db page scheme_id);
	local $" = ', ';
	say qq[<p>Enter allelic profiles below in tab-delimited text format using copy and paste (for example directly from a spreadsheet).]
	  . qq[Columns can be separated by any amount of whitespace.  The first column should be an isolate identifier and the remaining ]
	  . qq[columns should comprise the allele numbers (order: @cleaned_loci). Click here for ]
	  . qq[<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchProfiles&amp;function=examples&amp;]
	  . qq[scheme_id=$scheme_id">example data</a>.  Non-numerical characters will be stripped out of the query.</p>];
	say qq(<fieldset style="float:left"><legend>Paste in profiles</legend>);
	say $q->textarea( -name => 'profiles', -rows => 10, -columns => 80, -override => 1 );
	say "</fieldset>";
	$self->print_action_fieldset( { scheme_id => $scheme_id } );
	say $q->endform;
	say "</div>";
	return;
}

sub _print_examples {

	#Generate example data file for batch profile query
	#Get up to 15 random profiles from the database
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		$scheme_id = -1;
	}
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		print "This function is only available for sequence definition databases.\n";
		return;
	}
	my $scheme_info = $scheme_id > 0 ? $self->{'datastore'}->get_scheme_info($scheme_id) : undef;
	if ( ( !$scheme_info->{'id'} || !$scheme_id ) ) {
		print "Invalid scheme selected.\n";
		return;
	}
	my $loci         = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my @cleaned_loci = @$loci;
	$_ =~ s/'/_PRIME_/g foreach @cleaned_loci;
	local $" = ',';
	my $scheme_view = $self->{'datastore'}->materialized_view_exists($scheme_id) ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
	my $data =
	  $self->{'datastore'}
	  ->run_query( "SELECT @cleaned_loci FROM $scheme_view ORDER BY random() LIMIT 15", undef, { fetch => 'all_arrayref' } );
	local $" = "\t";
	my $i = 1;

	foreach my $profile (@$data) {
		say "isolate_$i\t@$profile";
		$i++;
	}
	return;
}
1;
