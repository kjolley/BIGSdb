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
	if (!defined $locus){
		say q(<h1>Allele information</h1>);
		say q(<div class="box" id="statusbad"><p>No locus selected.</p></div>);
		return;
	}
	$locus =~ s/%27/'/gx;    #Web-escaped locus
	my $allele_id = $q->param('allele_id');
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		say q(<h1>Allele information</h1>);
		say q(<div class="box" id="statusbad"><p>Invalid locus selected.</p></div>);
		return;
	}
	my $cleaned_locus = $self->clean_locus($locus);
	say q(<h1>Allele information) . ( defined $allele_id ? qq( - $cleaned_locus: $allele_id) : '' ) . q(</h1>);
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say q(<div class="box" id="statusbad"><p>This function is not available from an isolate database.</p></div>);
		return;
	}
	if ( !defined $allele_id ) {
		say q(<div class="box" id="statusbad"><p>No allele id selected.</p></div>);
		return;
	}
	my $seq_ref = $self->{'datastore'}->run_query(
		'SELECT * FROM sequences WHERE (locus,allele_id)=(?,?)',
		[ $locus, $allele_id ],
		{ fetch => 'row_hashref' }
	);
	if ( !$seq_ref ) {
		say q(<div class="box" id="statusbad"><p>This sequence does not exist.</p></div>);
		return;
	}
	my $length = length( $seq_ref->{'sequence'} );
	my $seq    = BIGSdb::Utils::split_line( $seq_ref->{'sequence'} );
	my $desc_exists =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM locus_descriptions WHERE locus=?)', $locus );
	my $desc_link =
	  $desc_exists
	  ? qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=locusInfo&amp;locus=$locus" )
	  . q(class="tooltip"><span class="fa fa-info-circle"></span></a>)
	  : q();
	say q(<div class="box" id="resultspanel">);
	say q(<div class="scrollable">);
	say q(<h2>Provenance/meta data</h2>);
	say q(<dl class="data">);
	say qq(<dt>locus</dt><dd>$cleaned_locus $desc_link</dd>);
	say qq(<dt>allele</dt><dd>$allele_id</dd>);

	if ( $allele_id eq '0' ) {
		say q(<dt>description</dt><dd>This is a null allele. When included in a )
		  . q(profile it means that this locus is missing.</dd>);
	} elsif ( $allele_id eq 'N' ) {
		say q(<dt>description</dt><dd>This is an arbitrary allele.  When included )
		  . q(in a profile it means that this locus is ignored.</dd>);
	} else {
		say qq(<dt>sequences</dt><dd style="text-align:left" class="seq">$seq</dd>)
		  . qq(<dt>length</dt><dd>$length</dd>)
		  . qq(<dt>status</dt><dd>$seq_ref->{'status'}</dd>)
		  . qq(<dt>date entered</dt><dd>$seq_ref->{'date_entered'}</dd>)
		  . qq(<dt>datestamp</dt><dd>$seq_ref->{'datestamp'}</dd>);
		my $sender =
		  $self->{'datastore'}->get_user_string( $seq_ref->{'sender'},
			{ affiliation => 1, email => ( $self->{'system'}->{'privacy'} ? 0 : 1 ) } );
		say qq(<dt>sender</dt><dd>$sender</dd>);
		my $curator = $self->{'datastore'}->get_user_string( $seq_ref->{'curator'}, { affiliation => 1, email => 1 } );
		say qq(<dt>curator</dt><dd>$curator</dd>);
	}
	say "<dt>comments</dt><dd>$seq_ref->{'comments'}</dd>" if $seq_ref->{'comments'};
	$self->_process_flags( $locus, $allele_id );
	my $extended_attributes = $self->{'datastore'}->get_allele_extended_attributes( $locus, $allele_id );
	foreach my $ext (@$extended_attributes) {
		my $cleaned_field = $ext->{'field'};
		$cleaned_field =~ tr/_/ /;
		if ( $cleaned_field =~ /sequence$/x ) {
			my $ext_seq = BIGSdb::Utils::split_line( $ext->{'value'} );
			say qq(<dt>$cleaned_field</dt><dd class="seq">$ext_seq</dd>);
		} else {
			say qq(<dt>$cleaned_field</dt><dd>$ext->{'value'}</dd>);
		}
	}
	say q(</dl>);
	$self->_print_accessions( $locus, $allele_id );
	$self->_print_ref_links( $locus, $allele_id );
	my $qry         = 'SELECT schemes.* FROM schemes LEFT JOIN scheme_members ON schemes.id=scheme_id WHERE locus=?';
	my $scheme_list = $self->{'datastore'}->run_query( $qry, $locus, { fetch => 'all_arrayref', slice => {} } );
	my $set_id      = $self->get_set_id;
	if (@$scheme_list) {
		my $profile_buffer;
		foreach my $scheme (@$scheme_list) {
			my $scheme_info =
			  $self->{'datastore'}->get_scheme_info( $scheme->{'id'}, { set_id => $set_id, get_pk => 1 } );
			next if !$scheme_info->{'primary_key'};
			my $profiles =
			  $self->{'datastore'}
			  ->run_query( 'SELECT COUNT(*) FROM profile_members WHERE (scheme_id,locus,allele_id)=(?,?,?)',
				[ $scheme->{'id'}, $locus, $allele_id ] );
			next if !$profiles;
			$profile_buffer .= "<dt>$scheme_info->{'description'}</dt>";
			my $plural  = $profiles == 1 ? ''         : 's';
			my $contain = $profiles == 1 ? 'contains' : 'contain';
			$profile_buffer .= q(<dd>);
			$profile_buffer .= $q->start_form;
			$q->param( page      => 'query' );
			$q->param( scheme_id => $scheme->{'id'} );
			$q->param( s1        => $locus );
			$q->param( y1        => '=' );
			$q->param( t1        => $allele_id );
			$q->param( order     => $scheme_info->{'primary_key'} );
			$q->param( submit    => 1 );
			$profile_buffer .= $q->hidden($_) foreach qw (db page scheme_id s1 y1 t1 order submit);
			$profile_buffer .= $q->submit( -label => "$profiles profile$plural", -class => 'smallbutton' );
			$profile_buffer .= $q->end_form;
			$profile_buffer .= q(</dd>);
		}
		if ($profile_buffer) {
			say qq(<h2>Profiles containing this allele</h2>\n<dl class="data">\n$profile_buffer</dl>);
		}
	}
	$self->_print_client_database_data( $locus, $allele_id );
	my $client_buffer = $self->{'datastore'}->get_client_data_linked_to_allele( $locus, $allele_id );
	say qq(<h2>Linked data</h2>\n$client_buffer) if $client_buffer;
	say q(</div></div>);
	return;
}

sub _print_client_database_data {
	my ( $self, $locus, $allele_id ) = @_;
	my $q   = $self->{'cgi'};
	my $qry = 'SELECT client_dbases.*,locus_alias FROM client_dbases LEFT JOIN client_dbase_loci ON '
	  . 'client_dbases.id=client_dbase_id WHERE locus=?';
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
				$buffer .= $q->start_form(
					-action => "$client->{'url'}?@action_params",
					-method => 'post',
					-style  => 'display:inline'
				);
				local $" = ' ';
				$buffer .= $q->hidden($_)
				  foreach qw (db page designation_field1 designation_operator1 designation_value1 order submit);
				$buffer .= $q->submit( -label => "$isolate_count isolate$plural", -class => 'smallbutton' );
				$buffer .= $q->end_form;
			}
			$buffer .= q(</dd>);
		}
		if ($buffer) {
			say qq(<h2>Isolate databases</h2>\n<dl class="data">);
			say $buffer;
			say q(</dl>);
		}
	}
	return;
}

sub _process_flags {
	my ( $self, $locus, $allele_id ) = @_;
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		my $flags = $self->{'datastore'}->get_allele_flags( $locus, $allele_id );
		if (@$flags) {
			local $" = q(</span> <span class="seqflag">);
			say qq(<dt>flags</dt><dd><span class="seqflag">@$flags</span></dd>);
		}
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $locus = $self->{'cgi'}->param('locus') // q();
	$locus =~ s/%27/'/gx;                                    #Web-escaped locus
	my $allele_id = $self->{'cgi'}->param('allele_id');
	return 'Invalid locus' if !$self->{'datastore'}->is_locus($locus);
	$locus =~ tr/_/ /;
	return 'Allele information' . ( defined $allele_id ? " - $locus: $allele_id" : '' );
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery);
	return;
}

sub _print_accessions {
	my ( $self, $locus, $allele_id ) = @_;
	my $qry = 'SELECT databank,databank_id FROM accession WHERE (locus,allele_id)=(?,?) ORDER BY databank,databank_id';
	my $accession_list =
	  $self->{'datastore'}->run_query( $qry, [ $locus, $allele_id ], { fetch => 'all_arrayref', slice => {} } );
	my $buffer = q();
	if (@$accession_list) {
		say '<h2>Accession' . ( @$accession_list > 1 ? 's' : '' ) . ' (' . @$accession_list . ')';
		my $display = @$accession_list > 4 ? 'none' : 'block';
		say q(<span style="margin-left:1em"><a id="show_accessions" class="smallbutton" style="cursor:pointer">&nbsp;)
		  . q(show/hide&nbsp;</a></span>)
		  if $display eq 'none';
		say "</h2>\n";
		my $id = $display eq 'none' ? 'hidden_accessions' : 'accessions';
		say qq(<div id="$id">);
		say $buffer .= qq(<dl class="data">\n);
		foreach my $accession (@$accession_list) {
			say "<dt>$accession->{'databank'}</dt>";
			if ( $accession->{'databank'} eq 'Genbank' ) {
				say qq(<dd><a href="http://www.ncbi.nlm.nih.gov/nuccore/$accession->{'databank_id'}">)
				  . qq($accession->{'databank_id'}</a></dd>);
			} elsif ( $accession->{'databank'} eq 'ENA' ) {
				say qq(<dd><a href="http://www.ebi.ac.uk/ena/data/view/$accession->{'databank_id'}">)
				  . qq($accession->{'databank_id'}</a></dd>);
			} else {
				say "<dd>$accession->{'databank_id'}</dd>";
			}
		}
		say q(</dl></div>);
	}
	return $buffer;
}

sub _print_ref_links {
	my ( $self, $locus, $allele_id ) = @_;
	my $pmids = $self->{'datastore'}->run_query(
		'SELECT pubmed_id FROM sequence_refs WHERE (locus,allele_id)=(?,?) ORDER BY pubmed_id',
		[ $locus, $allele_id ],
		{ fetch => 'col_arrayref' }
	);
	if (@$pmids) {
		my $count = @$pmids;
		my $plural = $count > 1 ? q(s) : q();
		say qq(<h2>Publication$plural ($count));
		my $display = @$pmids > 4 ? 'none' : 'block';
		say q(<span style="margin-left:1em"><a id="show_refs" class="smallbutton" style="cursor:pointer">)
		  . q(&nbsp;show/hide&nbsp;</a></span>)
		  if $display eq 'none';
		say q(</h2>);
		my $id = $display eq 'none' ? 'hidden_references' : 'references';
		say qq(<ul id="$id">\n);
		my $citations =
		  $self->{'datastore'}->get_citation_hash( $pmids,
			{ formatted => 1, all_authors => 1, state_if_unavailable => 1, link_pubmed => 1 } );
		foreach my $pmid ( sort { $citations->{$a} cmp $citations->{$b} } @$pmids ) {
			say qq(<li style="padding-bottom:1em">$citations->{$pmid}</li>);
		}
		say q(</ul>);
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
