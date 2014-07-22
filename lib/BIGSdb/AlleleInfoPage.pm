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
package BIGSdb::AlleleInfoPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(any uniq);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_records.html#allele-definition-records";
}

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
	if ( !defined $allele_id ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No allele id selected.</p></div>";
		return;
	}
	my $seq_ref =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM sequences WHERE locus=? AND allele_id=?", [ $locus, $allele_id ], { fetch => 'row_hashref' } );
	if ( !$seq_ref ) {
		say "<div class=\"box\" id=\"statusbad\"><p>This sequence does not exist.</p></div>";
		return;
	}
	my $length      = length( $seq_ref->{'sequence'} );
	my $seq         = BIGSdb::Utils::split_line( $seq_ref->{'sequence'} );
	my $sender_info = $self->{'datastore'}->get_user_info( $seq_ref->{'sender'} );
	$sender_info->{'affiliation'} =~ s/\&/\&amp;/g;
	my $sender_email =
	  ( !$self->{'system'}->{'privacy'} && $seq_ref->{'sender'} > 0 )
	  ? "(E-mail: <a href=\"mailto:$sender_info->{'email'}\">$sender_info->{'email'}</a>)"
	  : '';
	my $curator_info = $self->{'datastore'}->get_user_info( $seq_ref->{'curator'} );
	my $desc_exists = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM locus_descriptions WHERE locus=?", $locus )->[0];
	my $desc_link =
	  $desc_exists
	  ? "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=locusInfo&amp;locus=$locus\" class=\"info_tooltip\">&nbsp;i&nbsp;</a>"
	  : '';
	say "<div class=\"box\" id=\"resultspanel\">";
	say "<div class=\"scrollable\">";
	say "<h2>Provenance/meta data</h2>";
	say "<dl class=\"data\">";
	say "<dt>locus</dt><dd>$cleaned_locus $desc_link</dd>";
	say "<dt>allele</dt><dd>$allele_id</dd>";

	if ( $allele_id eq '0' ) {
		say "<dt>description</dt><dd>This is a null allele. When included in a profile it means that this locus is missing.</dd>";
	} elsif ( $allele_id eq 'N' ) {
		say "<dt>description</dt><dd>This is an arbitrary allele.  When included in a profile it means that this locus is ignored.</dd>";
	} else {
		print << "HTML";
<dt>sequences</dt><dd style="text-align:left" class="seq">$seq</dd>
<dt>length</dt><dd>$length</dd>			
<dt>status</dt><dd>$seq_ref->{'status'}</dd>
<dt>date entered</dt><dd>$seq_ref->{'date_entered'}</dd>
<dt>datestamp</dt><dd>$seq_ref->{'datestamp'}</dd>
HTML
		if ( $sender_info->{'first_name'} || $sender_info->{'surname'} ) {
			print "<dt>sender</dt><dd>$sender_info->{'first_name'} $sender_info->{'surname'}";
			print ", $sender_info->{'affiliation'}$sender_email" if $seq_ref->{'sender'} != $seq_ref->{'curator'};
			say "</dd>";
		}
		if ( $curator_info->{'first_name'} || $curator_info->{'surname'} ) {
			print "<dt>curator</dt><dd>$curator_info->{'first_name'} $curator_info->{'surname'}";
			say ", $curator_info->{'affiliation'} " if $curator_info->{'affiliation'} && $curator_info->{'affiliation'} ne ' ';
			say "(E-mail: <a href=\"mailto:$curator_info->{'email'}\">$curator_info->{'email'}</a>)"
			  if $curator_info->{'email'} && $seq_ref->{'curator'} > 0;
			say "</dd>";
		}
	}
	say "<dt>comments</dt><dd>$seq_ref->{'comments'}</dd>" if $seq_ref->{'comments'};
	$self->_process_flags( $locus, $allele_id );
	my $extended_attributes = $self->{'datastore'}->get_allele_extended_attributes( $locus, $allele_id );
	foreach my $ext (@$extended_attributes) {
		my $cleaned_field = $ext->{'field'};
		$cleaned_field =~ tr/_/ /;
		if ( $cleaned_field =~ /sequence$/ ) {
			my $ext_seq = BIGSdb::Utils::split_line( $ext->{'value'} );
			say "<dt>$cleaned_field</dt><dd class=\"seq\">$ext_seq</dd>";
		} else {
			say "<dt>$cleaned_field</dt><dd>$ext->{'value'}</dd>";
		}
	}
	say "</dl>";
	$self->_print_accessions( $locus, $allele_id );
	$self->_print_ref_links( $locus, $allele_id );
	my $qry         = "SELECT schemes.* FROM schemes LEFT JOIN scheme_members ON schemes.id=scheme_id WHERE locus=?";
	my $scheme_list = $self->{'datastore'}->run_query( $qry, $locus, { fetch => 'all_arrayref', slice => {} } );
	my $set_id      = $self->get_set_id;
	if (@$scheme_list) {
		my $profile_buffer;
		foreach my $scheme (@$scheme_list) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme->{'id'}, { set_id => $set_id } );
			my $pk_ref =
			  $self->{'datastore'}
			  ->run_simple_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key", $scheme->{'id'} );
			next if ref $pk_ref ne 'ARRAY';
			my $pk = $pk_ref->[0];
			my $profiles =
			  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM profile_members WHERE scheme_id=? AND locus=? AND allele_id=?",
				$scheme->{'id'}, $locus, $allele_id )->[0];
			next if !$profiles;
			$profile_buffer .= "<dt>$scheme_info->{'description'}</dt>";
			my $plural  = $profiles == 1 ? ''         : 's';
			my $contain = $profiles == 1 ? 'contains' : 'contain';
			$profile_buffer .= "<dd>";
			$profile_buffer .= $q->start_form;
			$q->param( page      => 'query' );
			$q->param( scheme_id => $scheme->{'id'} );
			$q->param( s1        => $locus );
			$q->param( y1        => '=' );
			$q->param( t1        => $allele_id );
			$q->param( 'order',  $pk );
			$q->param( 'submit', 1 );
			$profile_buffer .= $q->hidden($_) foreach qw (db page scheme_id s1 y1 t1 order submit);
			$profile_buffer .= $q->submit( -label => "$profiles profile$plural", -class => 'smallbutton' );
			$profile_buffer .= $q->end_form;
			$profile_buffer .= "</dd>";
		}
		if ($profile_buffer) {
			say "<h2>Profiles containing this allele</h2>\n<dl class=\"data\">\n$profile_buffer</dl>";
		}
	}
	$self->_print_client_database_data( $locus, $allele_id );
	my $client_buffer = $self->{'datastore'}->get_client_data_linked_to_allele( $locus, $allele_id );
	say "<h2>Linked data</h2>\n$client_buffer" if $client_buffer;
	say "</div></div>";
	return;
}

sub _print_client_database_data {
	my ( $self, $locus, $allele_id ) = @_;
	my $q   = $self->{'cgi'};
	my $qry = "SELECT client_dbases.*,locus_alias FROM client_dbases LEFT JOIN client_dbase_loci ON "
	  . "client_dbases.id=client_dbase_id WHERE locus=?";
	my $client_list = $self->{'datastore'}->run_query( $qry, $locus, { fetch => 'all_arrayref', slice => {} } );
	if (@$client_list) {
		my $buffer;
		foreach my $client (@$client_list) {
			my $isolate_count =
			  $self->{'datastore'}->get_client_db( $client->{'id'} )
			  ->count_isolates_with_allele( $client->{'locus_alias'} || $locus, $allele_id );
			next if !$isolate_count;
			$buffer .= "<dt>$client->{'name'}</dt>";
			$buffer .= "<dd>$client->{'description'} ";
			my $plural = $isolate_count == 1 ? '' : 's';
			if ( $client->{'url'} ) {

				#it seems we have to pass the parameters in the action clause for mod_perl2
				#but separately for stand-alone CGI.
				my %params = (
					db                    => $client->{'dbase_config_name'},
					page                  => 'query',
					designation_field1    => 'l_' . ( $client->{'locus_alias'} || $locus ),
					designation_operator1 => '=',
					designation_value1    => $allele_id,
					order                 => 'id',
					submit                => 1
				);
				my @action_params;
				foreach ( keys %params ) {
					$q->param( $_, $params{$_} );
					push @action_params, "$_=$params{$_}";
				}
				local $" = '&';
				$buffer .= $q->start_form( -action => "$client->{'url'}?@action_params", -method => 'post', -style => 'display:inline' );
				local $" = ' ';
				$buffer .= $q->hidden($_) foreach qw (db page designation_field1 designation_operator1 designation_value1 order submit);
				$buffer .= $q->submit( -label => "$isolate_count isolate$plural", -class => 'smallbutton' );
				$buffer .= $q->end_form;
			}
			$buffer .= "</dd>";
		}
		if ($buffer) {
			say "<h2>Isolate databases</h2>\n<dl class=\"data\">";
			say $buffer;
			say "</dl>";
		}
	}
	return;
}

sub _process_flags {
	my ( $self, $locus, $allele_id ) = @_;
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		my $flags = $self->{'datastore'}->get_allele_flags( $locus, $allele_id );
		if (@$flags) {
			local $" = "</span> <span class=\"seqflag\">";
			say "<dt>flags</dt><dd><span class=\"seqflag\">@$flags</span></dd>";
		}
	}
	return;
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

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery);
	return;
}

sub _print_accessions {
	my ( $self, $locus, $allele_id ) = @_;
	my $qry = "SELECT databank, databank_id FROM accession WHERE locus=? and allele_id=? ORDER BY databank,databank_id";
	my $accession_list =
	  $self->{'datastore'}->run_query( $qry, [ $locus, $allele_id ], { fetch => 'all_arrayref', slice => {} } );
	my $buffer = '';
	if (@$accession_list) {
		say "<h2>Accession" . ( @$accession_list > 1 ? 's' : '' ) . " (" . @$accession_list . ")";
		my $display = @$accession_list > 4 ? 'none' : 'block';
		say "<span style=\"margin-left:1em\"><a id=\"show_accessions\" class=\"smallbutton\" style=\"cursor:pointer\">&nbsp;"
		  . "show/hide&nbsp;</a></span>"
		  if $display eq 'none';
		say "</h2>\n";
		my $id = $display eq 'none' ? 'hidden_accessions' : 'accessions';
		say "<div id=\"$id\">";
		say $buffer .= "<dl class=\"data\">\n";
		foreach my $accession (@$accession_list) {
			say "<dt>$accession->{'databank'}</dt>";
			if ( $accession->{'databank'} eq 'Genbank' ) {
				say "<dd><a href=\"http://www.ncbi.nlm.nih.gov/nuccore/$accession->{'databank_id'}\">"
				  . "$accession->{'databank_id'}</a></dd>";
			} elsif ( $accession->{'databank'} eq 'ENA' ) {
				say "<dd><a href=\"http://www.ebi.ac.uk/ena/data/view/$accession->{'databank_id'}\">"
				  . "$accession->{'databank_id'}</a></dd>";
			} else {
				say "<dd>$accession->{'databank_id'}</dd>";
			}
		}
		say "</dl></div>\n";
	}
	return $buffer;
}

sub _print_ref_links {
	my ( $self, $locus, $allele_id ) = @_;
	my $pmids =
	  $self->{'datastore'}
	  ->run_list_query( "SELECT pubmed_id FROM sequence_refs WHERE locus=? and allele_id=? ORDER BY pubmed_id", $locus, $allele_id );
	if (@$pmids) {
		say "<h2>Publication" . ( @$pmids > 1 ? 's' : '' ) . " (" . @$pmids . ")";
		my $display = @$pmids > 4 ? 'none' : 'block';
		say
"<span style=\"margin-left:1em\"><a id=\"show_refs\" class=\"smallbutton\" style=\"cursor:pointer\">&nbsp;show/hide&nbsp;</a></span>"
		  if $display eq 'none';
		say "</h2>\n";
		my $id = $display eq 'none' ? 'hidden_references' : 'references';
		say "<ul id=\"$id\">\n";
		my $citations =
		  $self->{'datastore'}
		  ->get_citation_hash( $pmids, { formatted => 1, all_authors => 1, state_if_unavailable => 1, link_pubmed => 1 } );
		foreach my $pmid ( sort { $citations->{$a} cmp $citations->{$b} } @$pmids ) {
			say "<li style=\"padding-bottom:1em\">$citations->{$pmid}</li>";
		}
		say "</ul>";
	}
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	\$( "#hidden_accessions" ).css('display', 'none');
	\$( "#show_accessions" ).click(function() {
		\$( "#hidden_accessions" ).toggle( 'blind', {} , 500 );
		return false;
	});
	\$( "#hidden_references" ).css('display', 'none');
	\$( "#show_refs" ).click(function() {
		\$( "#hidden_references" ).toggle( 'blind', {} , 500 );
		return false;
	});
});

END
	return $buffer;
}
1;
