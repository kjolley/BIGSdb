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
package BIGSdb::AlleleInfoPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(any uniq);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $locus  = $q->param('locus');
	$locus =~ s/%27/'/g;    #Web-escaped locus
	my $allele_id = $q->param('allele_id');
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		say "<h1>Allele information</h1>";
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid locus selected.</p></div>";
		return;
	}
	my $cleaned_locus = $self->clean_locus($locus);
	say "<h1>Allele information" . ( defined $allele_id ? " - $cleaned_locus: $allele_id\n" : '' ) . "</h1>";
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say "<div class=\"box\" id=\"statusbad\"><p>This function is not available from an isolate database.</p></div>";
		return;
	}
	if ( !$allele_id ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No allele id selected.</p></div>";
		return;
	}
	my $seq_ref =
	  $self->{'datastore'}->run_simple_query_hashref( "SELECT * FROM sequences WHERE locus=? AND allele_id=?", $locus, $allele_id );
	if ( !$seq_ref->{'allele_id'} ) {
		say "<div class=\"box\" id=\"statusbad\"><p>This sequence does not exist.</p></div>";
		return;
	}
	my $length      = length( $seq_ref->{'sequence'} );
	my $seq         = BIGSdb::Utils::split_line( $seq_ref->{'sequence'} );
	my $sender_info = $self->{'datastore'}->get_user_info( $seq_ref->{'sender'} );
	$sender_info->{'affiliation'} =~ s/\&/\&amp;/g;
	my $sender_email = !$self->{'system'}->{'privacy'} ? "<a href=\"mailto:$sender_info->{'email'}\">$sender_info->{'email'}</a>" : '';
	my $curator_info = $self->{'datastore'}->get_user_info( $seq_ref->{'curator'} );
	my $desc_exists  = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM locus_descriptions WHERE locus=?", $locus )->[0];
	my $desc_link =
	  $desc_exists
	  ? "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=locusInfo&amp;locus=$locus\" class=\"info_tooltip\">&nbsp;i&nbsp;</a>"
	  : '';
	print << "HTML";
<div class="box" id="resultstable">
<div class="scrollable">
<table class="resultstable">
<tr class="td1"><th>locus</th><td style="text-align:left" colspan="3">$cleaned_locus $desc_link</td></tr>
<tr class="td2"><th>allele</th><td style="text-align:left" colspan="3">$allele_id</td></tr>
<tr class="td1"><th>sequence</th><td style="text-align:left" class="seq" colspan="3">$seq</td></tr>
<tr class="td2"><th>length</th><td style="text-align:left" colspan="3">$length</td></tr>
<tr class="td1"><th>status</th><td style="text-align:left" colspan="3">$seq_ref->{'status'}</td></tr>
<tr class="td2"><th>date entered</th><td style="text-align:left" colspan="3">$seq_ref->{'date_entered'}</td></tr>
<tr class="td1"><th>datestamp</th><td style="text-align:left" colspan="3">$seq_ref->{'datestamp'}</td></tr>
<tr class="td2"><th>sender</th><td style="text-align:left">$sender_info->{'first_name'} $sender_info->{'surname'}</td>
<td style="text-align:left">$sender_info->{'affiliation'}</td><td>$sender_email</td></tr>
<tr class="td1"><th>curator</th><td style="text-align:left">$curator_info->{'first_name'} $curator_info->{'surname'}</td>
<td style="text-align:left">$curator_info->{'affiliation'}</td><td style="text-align:left">
<a href="mailto:$curator_info->{'email'}">$curator_info->{'email'}</a></td></tr>
HTML
	my $td = 2;
	$self->_process_flags( $locus, $allele_id, \$td );
	my $extended_attributes = $self->{'datastore'}->get_allele_extended_attributes( $locus, $allele_id );

	foreach my $ext (@$extended_attributes) {
		my $cleaned_field = $ext->{'field'};
		$cleaned_field =~ tr/_/ /;
		if ( $cleaned_field =~ /sequence$/ ) {
			my $seq = BIGSdb::Utils::split_line( $ext->{'value'} );
			say "<tr class=\"td$td\"><th>$cleaned_field</th><td style=\"text-align:left\" colspan=\"3\" class=\"seq\">$seq</td></tr>";
		} else {
			say "<tr class=\"td$td\"><th>$cleaned_field</th><td style=\"text-align:left\" colspan=\"3\">$ext->{'value'}</td></tr>";
		}
		$td = $td == 1 ? 2 : 1;
	}
	my $qry = "SELECT databank, databank_id FROM accession WHERE locus=? and allele_id=? ORDER BY databank,databank_id";
	my $accession_list = $self->{'datastore'}->run_list_query_hashref( $qry, $locus, $allele_id );
	foreach my $accession (@$accession_list) {
		print "<tr class=\"td$td\"><th>$accession->{'databank'} #</th><td style=\"text-align:left\" colspan=\"3\">";
		if ( $accession->{'databank'} eq 'Genbank' ) {
			print "<a href=\"http://www.ncbi.nlm.nih.gov/nuccore/$accession->{'databank_id'}\">$accession->{'databank_id'}</a>";
		} else {
			print "$accession->{'databank_id'}";
		}
		say "</td></tr>";
		$td = $td == 1 ? 2 : 1;
	}
	$qry = "SELECT pubmed_id FROM sequence_refs WHERE locus=? and allele_id=? ORDER BY pubmed_id";
	my $pmid_list = $self->{'datastore'}->run_list_query( $qry, $locus, $allele_id );
	foreach my $pmid (@$pmid_list) {
		print $self->_get_reference( $pmid, $td );
		$td = $td == 1 ? 2 : 1;
	}
	$qry = "SELECT schemes.* FROM schemes LEFT JOIN scheme_members ON schemes.id=scheme_id WHERE locus=?";
	my $scheme_list = $self->{'datastore'}->run_list_query_hashref( $qry, $locus );
	foreach my $scheme (@$scheme_list) {
		my $pk_ref =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key", $scheme->{'id'} );
		next if ref $pk_ref ne 'ARRAY';
		my $pk = $pk_ref->[0];
		print "<tr class=\"td$td\"><th>$scheme->{'description'}</th>";
		my $profiles =
		  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM profile_members WHERE scheme_id=? AND locus=? AND allele_id=?",
			$scheme->{'id'}, $locus, $allele_id )->[0];
		my $plural  = $profiles == 1 ? ''         : 's';
		my $contain = $profiles == 1 ? 'contains' : 'contain';
		say "<td style=\"text-align:left\" colspan=\"2\">$profiles profile$plural $contain this allele</td><td>";
		say $q->start_form;
		$q->param( 'page',      'query' );
		$q->param( 'scheme_id', $scheme->{'id'} );
		$q->param( 's1',        $locus );
		$q->param( 'y1',        '=' );
		$q->param( 't1',        $allele_id );
		$q->param( 'order',     $pk );
		$q->param( 'submit',    1 );

		foreach (qw (db page scheme_id s1 y1 t1 order submit)) {
			say $q->hidden($_);
		}
		say $q->submit( -label => 'Display', -class => 'submit' );
		say $q->end_form;
		say "</td></tr>";
		$td = $td == 1 ? 2 : 1;
	}
	$td = $self->_print_client_database_data( $locus, $allele_id, $td );
	$self->_print_linked_data($locus, $allele_id, $td );
	say "</table>\n</div></div>";
	return;
}

sub _print_client_database_data {
	my ( $self, $locus, $allele_id, $td ) = @_;
	my $q   = $self->{'cgi'};
	my $qry = "SELECT client_dbases.*,locus_alias FROM client_dbases LEFT JOIN client_dbase_loci ON "
	  . "client_dbases.id=client_dbase_id WHERE locus=?";
	my $client_list = $self->{'datastore'}->run_list_query_hashref( $qry, $locus );
	my $locus_info  = $self->{'datastore'}->get_locus_info($locus);
	my $data_type   = $locus_info->{'data_type'} eq 'DNA' ? 'allele' : 'peptide';
	foreach my $client (@$client_list) {
		say "<tr class=\"td$td\"><th>client database</th><td style=\"text-align:left\">$client->{'name'}</td>"
		  . "<td style=\"text-align:left\">$client->{'description'}</td>";
		my $isolate_count =
		  $self->{'datastore'}->get_client_db( $client->{'id'} )
		  ->count_isolates_with_allele( $client->{'locus_alias'} || $locus, $allele_id );
		next if !$isolate_count;
		my $plural = $isolate_count == 1 ? '' : 's';
		say "<td colspan=\"2\">$isolate_count isolate$plural<br />";
		if ( $client->{'url'} ) {

			#it seems we have to pass the parameters in the action clause for mod_perl2
			#but separately for stand-alone CGI.
			my %params = (
				db     => $client->{'dbase_config_name'},
				page   => 'query',
				ls1    => 'l_' . ( $client->{'locus_alias'} || $locus ),
				ly1    => '=',
				lt1    => $allele_id,
				order  => 'id',
				submit => 1
			);
			my @action_params;
			foreach ( keys %params ) {
				$q->param( $_, $params{$_} );
				push @action_params, "$_=$params{$_}";
			}
			local $" = '&';
			say $q->start_form( -action => "$client->{'url'}?@action_params", -method => 'post' );
			say $q->hidden($_) foreach qw (db page ls1 ly1 lt1 order submit);
			say $q->submit( -label => 'Display', -class => 'submit' );
			say $q->end_form;
		}
		say "</td></tr>";
		$td = $td == 1 ? 2 : 1;
	}
	return $td;
}

sub _print_linked_data {
	my ( $self, $locus, $allele_id, $td ) = @_;
	my $field_values = $self->{'datastore'}->get_client_dbase_fields( $locus, [ $allele_id ] );
	return if !defined $field_values;
	say "<tr class=\"td$td\"><th>linked data</th><td colspan=\"3\" style=\"text-align:left\">$field_values</td></tr>";
	return;
}

sub _process_flags {
	my ( $self, $locus, $allele_id, $td_ref ) = @_;
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		my $flags = $self->{'datastore'}->get_allele_flags( $locus, $allele_id );
		if (@$flags) {
			local $" = "</a> <a class=\"seqflag_tooltip\">";
			say "<tr class=\"td$$td_ref\"><th>flags</th><td style=\"text-align:left\" colspan=\"3\">"
			  . "<a class=\"seqflag_tooltip\">@$flags</a></td></tr>";
			$$td_ref = $$td_ref == 1 ? 2 : 1;
		}
	}
	return;
}

sub _get_reference {
	my ( $self, $pmid, $td ) = @_;
	my $citation = $self->{'datastore'}->get_citation_hash( [$pmid], { formatted => 1, all_authors => 1 } );
	my $buffer =
	    "<tr class=\"td$td\"><th>reference</th><td align=\"left\">"
	  . "<a href='http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&amp;db=PubMed&amp;list_uids=$pmid&amp;dopt=Abstract'>"
	  . "$pmid</a></td><td colspan=\"3\" style=\"text-align:left; width:75%\">$citation->{$pmid}</td></tr>\n";
	return $buffer;
}

sub get_title {
	my ($self) = @_;
	my $locus = $self->{'cgi'}->param('locus');
	$locus =~ s/%27/'/g;    #Web-escaped locus
	my $allele_id = $self->{'cgi'}->param('allele_id');
	return "Invalid locus" if !$self->{'datastore'}->is_locus($locus);
	$locus =~ tr/_/ /;
	return "Allele information" . ( defined $allele_id ? " - $locus: $allele_id" : '' );
}
1;
