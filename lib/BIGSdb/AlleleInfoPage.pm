#Written by Keith Jolley
#Copyright (c) 2010, University of Oxford
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
use base qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $locus     = $q->param('locus');
	$locus =~ s/%27/'/g; #Web-escaped locus
	my $allele_id = $q->param('allele_id');
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		print "<h1>Allele information</h1>\n";
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid locus selected.</p></div>\n";
		return;
	}
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $cleaned_locus = $self->clean_locus($locus);
	print "<h1>Allele information - $cleaned_locus: $allele_id</h1>\n";
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>This function is not available from an isolate database.</p></div>\n";
		return;
	}
	if ( !$allele_id ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No allele id selected.</p></div>\n";
		return;
	}
	my $sql = $self->{'db'}->prepare("SELECT * FROM sequences WHERE locus=? AND allele_id=?");
	eval { $sql->execute( $locus, $allele_id ); };
	if ($@) {
		$logger->error("Can't execute $@");
	}
	my $seq_ref = $sql->fetchrow_hashref;
	if ( !$seq_ref->{'allele_id'} ) {
		print "<div class=\"box\" id=\"statusbad\"><p>This sequence does not exist.</p></div>\n";
		return;
	}
	my $length       = length( $seq_ref->{'sequence'} );
	my $seq          = BIGSdb::Utils::split_line( $seq_ref->{'sequence'} );
	my $sender_info  = $self->{'datastore'}->get_user_info( $seq_ref->{'sender'} );
	$sender_info->{'affiliation'} =~ s/\&/\&amp;/g;
	my $sender_email = "<a href=\"mailto:$sender_info->{'email'}\">$sender_info->{'email'}</a>" if !$self->{'system'}->{'privacy'};
	my $curator_info = $self->{'datastore'}->get_user_info( $seq_ref->{'curator'} );
	my $desc_exists = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM locus_descriptions WHERE locus=?",$locus)->[0];
	my $desc_link;
	if ($desc_exists){
		$desc_link = "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=locusInfo&amp;locus=$locus\" class=\"info_tooltip\">&nbsp;i&nbsp;</a>";
	}
	print << "HTML";
<div class="box" id="resultstable">
<table class="resultstable">
<tr class="td1"><th>locus</th><td style="text-align:left" colspan="3">$cleaned_locus $desc_link</td></tr>
<tr class="td2"><th>allele</th><td style="text-align:left" colspan="3">$allele_id</td></tr>
<tr class="td1"><th>sequence</th><td style="text-align:left" class="seq" colspan="3">$seq</td></tr>
<tr class="td2"><th>length</th><td style="text-align:left" colspan="3">$length</td></tr>
<tr class="td1"><th>status</th><td style="text-align:left" colspan="3">$seq_ref->{'status'}</td></tr>
<tr class="td2"><th>date entered</th><td style="text-align:left" colspan="3">$seq_ref->{'date_entered'}</td></tr>
<tr class="td1"><th>datestamp</th><td style="text-align:left" colspan="3">$seq_ref->{'datestamp'}</td></tr>
<tr class="td2"><th>sender</th><td style="text-align:left">$sender_info->{'first_name'} $sender_info->{'surname'}</td><td style="text-align:left">$sender_info->{'affiliation'}</td><td>$sender_email</td></tr>
<tr class="td1"><th>curator</th><td style="text-align:left">$curator_info->{'first_name'} $curator_info->{'surname'}</td><td style="text-align:left">$curator_info->{'affiliation'}</td><td style="text-align:left"><a href="mailto:$curator_info->{'email'}">$curator_info->{'email'}</a></td></tr>
HTML
	my $td = 2;
	my $extended_attributes =
	  $self->{'datastore'}->run_list_query( "SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order", $locus );

	if ( ref $extended_attributes eq 'ARRAY' ) {
		my $sql2 = $self->{'db'}->prepare("SELECT value FROM sequence_extended_attributes WHERE locus=? AND field=? AND allele_id=?");
		foreach (@$extended_attributes) {
			eval { $sql2->execute( $locus, $_, $allele_id ); };
			if ($@) {
				$logger->error("Can't execute $@");
			}
			my ($value) = $sql2->fetchrow_array;
			if ($value) {
				my $cleaned = $_;
				$cleaned =~ tr/_/ /;
				if ( $cleaned =~ /sequence$/ ) {
					my $seq = BIGSdb::Utils::split_line($value);
					print "<tr class=\"td$td\"><th>$cleaned</th><td style=\"text-align:left\" colspan=\"3\" class=\"seq\">$seq</td></tr>\n";
				} else {
					print "<tr class=\"td$td\"><th>$cleaned</th><td style=\"text-align:left\" colspan=\"3\">$value</td></tr>\n";
				}
				$td = $td == 1 ? 2 : 1;
			}
		}
	}
	my $qry = "SELECT databank, databank_id FROM accession WHERE locus=? and allele_id=? ORDER BY databank,databank_id";
	$sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute( $locus, $allele_id ); };
	if ($@) {
		$logger->error("Can't execute $@");
	}
	while ( my $accession = $sql->fetchrow_hashref ) {
		print "<tr class=\"td$td\"><th>$accession->{'databank'} #</th><td style=\"text-align:left\" colspan=\"3\">";
		if ( $accession->{'databank'} eq 'Genbank' ) {
			print "<a href=\"http://www.ncbi.nlm.nih.gov/nuccore/$accession->{'databank_id'}\">";
		}
		print "$accession->{'databank_id'}";
		print "</a>" if $accession->{'databank'} eq 'Genbank';
		print "</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	$qry = "SELECT pubmed_id FROM sequence_refs WHERE locus=? and allele_id=? ORDER BY pubmed_id";
	$sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute( $locus, $allele_id ); };
	if ($@) {
		$logger->error("Can't execute $@");
	}
	while ( my ($pmid) = $sql->fetchrow_array ) {
		print $self->_get_reference( $pmid, $td );
		$td = $td == 1 ? 2 : 1;
	}
	$qry = "SELECT schemes.* FROM schemes LEFT JOIN scheme_members ON schemes.id=scheme_id WHERE locus=?";
	$sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($locus); };
	if ($@) {
		$logger->error("Can't execute $@");
	}
	while ( my $scheme = $sql->fetchrow_hashref ) {
		my $pk_ref =
		  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key", $scheme->{'id'} );
		next if ref $pk_ref ne 'ARRAY';
		my $pk = $pk_ref->[0];
		print "<tr class=\"td$td\"><th>$scheme->{'description'}</th>";
		my $profiles =
		  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM profile_members WHERE scheme_id=? AND locus=? AND allele_id=?",
			$scheme->{'id'}, $locus, $allele_id )->[0];
		my $plural = $profiles == 1 ? '' : 's'; 
		my $contain = $profiles == 1 ? 'contains' : 'contain';
		print "<td style=\"text-align:left\" colspan=\"2\">$profiles profile$plural $contain this allele</td><td>";
		print $q->start_form;
		$q->param( 'page',      'query' );
		$q->param( 'scheme_id', $scheme->{'id'} );
		$q->param( 's1',        $locus );
		$q->param( 'y1',        '=' );
		$q->param( 't1',        $allele_id );
		$q->param( 'order',     $pk );
		$q->param( 'submit',    1 );

		foreach (qw (db page scheme_id s1 y1 t1 order submit)) {
			print $q->hidden($_);
		}
		print $q->submit( -label => 'Display', -class => 'submit' );
		print $q->end_form;
		print "</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	$qry =
	  "SELECT client_dbases.*,locus_alias FROM client_dbases LEFT JOIN client_dbase_loci ON client_dbases.id=client_dbase_id WHERE locus=?";
	$sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($locus); };
	if ($@) {
		$logger->error("Can't execute $@");
	}
	my $data_type = $locus_info->{'data_type'} eq 'DNA' ? 'allele' : 'peptide';
	while ( my $client = $sql->fetchrow_hashref ) {
		my $isolate_count =
		  $self->{'datastore'}->get_client_db( $client->{'id'} )
		  ->count_isolates_with_allele( $client->{'locus_alias'} || $locus, $allele_id );
		next if !$isolate_count;
		my $plural = $isolate_count == 1 ? '' : 's';
		print
"<tr class=\"td$td\"><th>client database</th><td>$client->{'name'}</td><td style=\"text-align:left\">$client->{'description'}</td><td colspan=\"2\">$isolate_count isolate$plural<br />";
		if ( $client->{'url'} ) {

			#it seems we have to pass the parameters in the action clause for mod_perl2
			#but separately for stand-alone CGI.
			my %params = (
				'db'    => $client->{'dbase_config_name'},
				'page'  => 'query',
				'ls1'   => 'l_' . ( $client->{'locus_alias'} || $locus ),
				'ly1'   => '=',
				'lt1'   => $allele_id,
				'order' => 'id',
				'submit'  => 1
			);
			my @action_params;
			foreach ( keys %params ) {
				$q->param( $_, $params{$_} );
				push @action_params, "$_=$params{$_}";
			}
			$" = '&';
			print $q->start_form( -action => "$client->{'url'}?@action_params", -method => 'post' );
			foreach (qw (db page ls1 ly1 lt1 order submit)) {
				print $q->hidden($_);
			}
			print $q->submit( -label => 'Display', -class => 'submit' );
			print $q->end_form;
		}
		print "</td></tr>\n";
		$td = $td == 1 ? 2 : 1;
	}
	print "</table>\n</div>\n";
}

sub _get_reference {
	my ( $self, $pmid, $td ) = @_;
	my $buffer;
	if ( $self->{'config'}->{'refdb'} ) {
		my %att = (
			dbase_name => $self->{'config'}->{'refdb'},
			host       => $self->{'system'}->{'host'},
			port       => $self->{'system'}->{'port'},
			user       => $self->{'system'}->{'user'},
			password   => $self->{'system'}->{'pass'}
		);
		my $dbr = $self->{'datastore'}->get_data_connector->get_connection( \%att );
		if ($dbr) {
			my $sqlr  = $dbr->prepare("SELECT year,journal,volume,pages,title FROM refs WHERE pmid=?");
			my $sqlr2 = $dbr->prepare("SELECT surname,initials FROM authors WHERE id=?");
			$sqlr->execute($pmid) or $logger->error("Can't execute query");
			my $sqlr3 = $dbr->prepare("SELECT author FROM refauthors WHERE pmid=? ORDER BY position");
			$sqlr3->execute($pmid) or $logger->error("Can't execute query");
			my @authors;
			while ( my ($authorid) = $sqlr3->fetchrow_array ) {
				push @authors, $authorid;
			}
			my ( $year, $journal, $volume, $pages, $title ) = $sqlr->fetchrow_array();
			undef my $temp;
			foreach (@authors) {
				$sqlr2->execute($_) or $logger->error("Can't execute query");
				my ( $surname, $initials ) = $sqlr2->fetchrow_array();
				$temp .= "$surname $initials, ";
			}
			$temp =~ s/, $// if $temp;
			if ($title) {
				$buffer .=
"<tr class=\"td$td\"><th>reference</th><td align=\"left\"><a href='http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&amp;db=PubMed&amp;list_uids=$pmid&amp;dopt=Abstract'>$pmid</a></td><td colspan=\"3\" style=\"text-align:left; width:75%\">$temp ($year) <i>$journal</i> <b>$volume:</b>$pages<br />$title";
				$buffer .= "</td></tr>\n";
			} else {
				$buffer .=
"<tr class=\"td$td\"><th>reference</th><td align=\"left\"><a href='http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&amp;db=PubMed&amp;list_uids=$pmid&amp;dopt=Abstract'>$pmid</a></td><td colspan=\"3\" style=\"text-align:left; width:75%\">No details available.";
				$buffer .= "</td></tr>\n";
			}
			$sqlr->finish;
			$sqlr2->finish;
		} else {
			$logger->error("No connection to reference database '$self->{'config'}->{'refdb'}' - check configuration.\n");
			$buffer .=
"<tr class=\"td$td\"><th>reference</th><td align=\"left\"><a href='http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&amp;db=PubMed&amp;list_uids=$pmid&amp;dopt=Abstract'>$pmid</a></td><td colspan=\"3\" style=\"text-align:left; width:75%\">No details available.";
			$buffer .= "</td></tr>\n";
		}
	} else {
		$buffer .=
"<tr class=\"td$td\"><th>reference</th><td align=\"left\"><a href='http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&amp;db=PubMed&amp;list_uids=$pmid&amp;dopt=Abstract'>$pmid</a></td><td colspan=\"3\" style=\"text-align:left; width:75%\">No details available.";
		$buffer .= "</td></tr>\n";
	}
	return $buffer;
}

sub get_title {
	my ($self)    = @_;
	my $locus     = $self->{'cgi'}->param('locus');
	$locus =~ s/%27/'/g; #Web-escaped locus
	my $allele_id = $self->{'cgi'}->param('allele_id');
	return "Invalid locus" if !$self->{'datastore'}->is_locus($locus);
	$locus =~ tr/_/ /;
	return "Allele information - $locus: $allele_id";
}
1;
