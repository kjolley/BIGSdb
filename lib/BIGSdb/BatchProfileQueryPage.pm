#Written by Keith Jolley
#Copyright (c) 2010-2018, University of Oxford
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
use BIGSdb::Constants qw(:interface);
use JSON;
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
	if ( $self->{'cgi'}->param('function') ) {
		$self->{'type'} = 'text';
	} else {
		$self->{'jQuery'} = 1;
	}
	return;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_query.html#batch-profile-queries";
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( ( $q->param('function') // q() ) eq 'examples' ) {
		$self->_print_examples;
		return;
	} elsif ( ( $q->param('function') // q() ) eq 'col_order' ) {
		$self->_print_col_order;
		return;
	}
	my $scheme_id = $q->param('scheme_id');
	my $desc      = $self->get_db_description;
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		say qq(<h1>Batch profile query - $desc</h1>);
		$self->print_bad_status(
			{
				message => q(This function is only available for sequence definition databases.),
				navbar  => 1
			}
		);
		return;
	}
	say qq(<h1>Batch profile query - $desc</h1>);
	if ( $q->param('profiles') ) {
		$self->_run_query($scheme_id);
		return;
	} else {
		return if defined $scheme_id && $self->is_scheme_invalid( $scheme_id, { with_pk => 1 } );
		$self->print_scheme_section( { with_pk => 1 } );
		$scheme_id = $q->param('scheme_id');    #Will be set by scheme section method
	}
	say q(<div class="box" id="queryform">);
	say $q->start_form;
	say $q->hidden($_) foreach qw (db page scheme_id);
	local $" = ', ';
	say q[<p>Enter allelic profiles below in tab-delimited text format using copy and paste ]
	  . q[(for example directly from a spreadsheet). Columns can be separated by any amount of whitespace. ]
	  . q[The first column should be an isolate identifier and the remaining ]
	  . qq[columns should comprise the allele numbers (<a href="$self->{'system'}->{'script_name'}?]
	  . qq[db=$self->{'instance'}&amp;page=batchProfiles&amp;function=col_order&amp;scheme_id=$scheme_id">]
	  . q[show column order</a>). Click here for ]
	  . qq[<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=batchProfiles&amp;]
	  . qq[function=examples&amp;scheme_id=$scheme_id">example data</a>. Non-numerical characters will be ]
	  . q[stripped out of the query.</p>];
	say q(<fieldset style="float:left"><legend>Paste in profiles</legend>);
	say $q->textarea( -name => 'profiles', -rows => 10, -columns => 80, -override => 1 );
	say q(</fieldset>);
	$self->print_action_fieldset( { scheme_id => $scheme_id } );
	say $q->end_form;
	say q(</div>);
	return;
}

sub _run_query {
	my ( $self, $scheme_id ) = @_;
	my $q        = $self->{'cgi'};
	my $loci     = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $profiles = $q->param('profiles');
	$profiles =~ s/[^A-z0-9\s\-\|\,\.]/_/gx;
	my @rows = split /\n/x, $profiles;
	my @cleaned_loci;
	push @cleaned_loci, $self->clean_locus($_) foreach @$loci;
	local $" = q(</th><th>);
	say q(<div class="box" id="resultstable">);
	say q(<div class="scrollable">);
	say qq(<table class="resultstable"><tr><th>Isolate</th><th>@cleaned_loci</th>);
	local $" = qq(\t);
	my $text_buffer   = qq(Isolate\t@cleaned_loci);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);

	foreach my $field (@$scheme_fields) {
		my $cleaned = $field;
		$cleaned =~ tr/_/ /;
		print qq(<th>$cleaned</th>);
		$text_buffer .= qq(\t$cleaned);
	}
	local $" = ',';
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $qry              = "SELECT @$scheme_fields FROM $scheme_warehouse WHERE ";
	my @cleaned_loci_db;
	foreach my $locus (@$loci) {
		push @cleaned_loci_db, $self->{'datastore'}->get_scheme_warehouse_locus_name( $scheme_id, $locus );
	}
	my $set_id = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
	local $" = $scheme_info->{'allow_missing_loci'} ? q[ IN (?, 'N')) AND (] : q[=?) AND (];
	$qry .= $scheme_info->{'allow_missing_loci'} ? qq[(@cleaned_loci_db IN (?, 'N'))] : qq[(@cleaned_loci_db=?)];
	say q(<th>Query</th></tr>);
	$text_buffer .= qq(\n);
	my $td = 1;
	local $| = 1;
	my $row_id   = 0;
	my $query_id = BIGSdb::Utils::get_random();
	my $query    = QUERY;
	my $data     = {};

	foreach my $row (@rows) {
		$row_id++;
		my @profile = split /\t/x, $row;
		my $isolate = shift @profile;
		foreach my $allele (@profile) {
			$allele =~ s/^\s+//gx;
			$allele =~ s/\s+$//gx;
		}
		say qq(<tr class="td$td"><td>$isolate</td>);
		$text_buffer .= $isolate;
		for my $i ( 0 .. @$loci - 1 ) {
			if ( defined $profile[$i] ) {
				$data->{$row_id}->{ $loci->[$i] } = $profile[$i];
				print qq(<td>$profile[$i]</td>);
				$text_buffer .= qq(\t$profile[$i]);
			} else {
				print q(<td class="statusbad" style="font-size:2em">-</td>);
				$text_buffer .= qq(\t-);
			}
		}
		my $incomplete;
		my @field_data;
		if ( @profile >= @$loci ) {
			while ( @profile > @$loci ) {
				pop @profile;
			}
			@field_data =
			  $self->{'datastore'}->run_query( $qry, \@profile, { cache => 'BatchProfileQueryPage::run_query' } );
		} else {
			$incomplete = 1;
		}
		my $i = 0;
		foreach (@$scheme_fields) {
			if ( exists $field_data[$i] ) {
				if ( defined $field_data[$i] ) {
					print qq(<td>$field_data[$i]</td>);
					$text_buffer .= qq(\t$field_data[$i]);
				} else {
					print q(<td></td>);
					$text_buffer .= qq(\t);
				}
			} else {
				print q(<td class="statusbad" style="font-size:2em">-</td>);
				$text_buffer .= qq(\t);
			}
			$i++;
		}
		say qq(<td><a href="$self->{'system'}->{'query_script'}?db=$self->{'instance'}&amp;page=profiles&amp;)
		  . qq(scheme_id=$scheme_id&amp;query_id=$query_id&amp;populate_profiles=1&amp;)
		  . qq(index=$row_id" target="_blank">$query</a></td></tr>);
		$text_buffer .= qq(\n);
		$td = $td == 1 ? 2 : 1;
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
	}
	say q(</table>);
	my $prefix     = BIGSdb::Utils::get_random();
	my $out_file   = qq($prefix.txt);
	my $excel_file = qq($prefix.xlsx);
	my $full_path  = "$self->{'config'}->{'tmp_dir'}/$out_file";
	open( my $fh, '>', $full_path ) || $logger->error("Cannot open $full_path for writing");
	say $fh $text_buffer;
	close $fh;
	$self->_write_query_file( $query_id, $data );
	my ( $text_icon, $excel_icon ) = ( TEXT_FILE, EXCEL_FILE );

	if ( -e $full_path ) {
		say qq(<p style="margin-top:1em">Download: <a href="/tmp/$out_file" title="Tab-delimited text">)
		  . qq($text_icon</a>);
		my $excel = BIGSdb::Utils::text2excel($full_path);
		if ( -e $excel ) {
			say qq( <a href="/tmp/$excel_file" title="Excel format">$excel_icon</a>);
		}
		say q(</p>);
	}
	$self->print_navigation_bar( { back_page => 'batchProfiles' } );
	say q(</div></div>);
	return;
}

sub _write_query_file {
	my ( $self, $query_id, $data ) = @_;
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$query_id.json";
	open( my $fh, '>:raw', $full_path ) || $logger->error("Cannot open $full_path for writing");
	say $fh encode_json($data);
	close $fh;
	return;
}

#Generate example data file for batch profile query
#Get up to 15 random profiles from the database
sub _print_examples {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		$scheme_id = -1;
	}
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		say q(This function is only available for sequence definition databases.);
		return;
	}
	my $scheme_info = $scheme_id > 0 ? $self->{'datastore'}->get_scheme_info($scheme_id) : undef;
	if ( ( !$scheme_info->{'id'} || !$scheme_id ) ) {
		print "Invalid scheme selected.\n";
		return;
	}
	my $loci             = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $data = $self->{'datastore'}->run_query( "SELECT profile FROM $scheme_warehouse ORDER BY random() LIMIT 15",
		undef, { fetch => 'col_arrayref' } );
	if ( !@$data ) {
		say q(No profiles have yet been defined for this scheme.);
		return;
	}
	my $i       = 1;
	my $indices = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
	local $" = "\t";
	foreach my $profile (@$data) {
		my @alleles;
		foreach my $locus (@$loci) {
			push @alleles, $profile->[ $indices->{$locus} ];
		}
		say qq(isolate_$i\t@alleles);
		$i++;
	}
	return;
}

sub _print_col_order {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		$scheme_id = -1;
	}
	if ( $self->{'system'}->{'dbtype'} ne 'sequences' ) {
		say q(This function is only available for sequence definition databases.);
		return;
	}
	my @cleaned_loci;
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	push @cleaned_loci, $self->clean_locus( $_, { text_output => 1 } ) foreach @$loci;
	local $" = qq(\t);
	say qq(id\t@cleaned_loci);
	return;
}
1;
