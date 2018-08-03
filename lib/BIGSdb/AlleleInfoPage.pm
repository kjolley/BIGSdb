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
package BIGSdb::AlleleInfoPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(any uniq);
use Log::Log4perl qw(get_logger);
use BIGSdb::Constants qw(:interface);
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
	if ( !defined $locus ) {
		say q(<h1>Allele information</h1>);
		$self->print_bad_status( { message => q(No locus selected.), navbar => 1 } );
		return;
	}
	$locus =~ s/%27/'/gx;    #Web-escaped locus
	my $allele_id = $q->param('allele_id');
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		say q(<h1>Allele information</h1>);
		$self->print_bad_status( { message => q(Invalid locus selected.), navbar => 1 } );
		return;
	}
	my $cleaned_locus = $self->clean_locus($locus);
	say q(<h1>Allele information) . ( defined $allele_id ? qq( - $cleaned_locus: $allele_id) : '' ) . q(</h1>);
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->print_bad_status(
			{ message => q(This function is not available from an isolate database.), navbar => 1 } );
		return;
	}
	if ( !defined $allele_id ) {
		$self->print_bad_status( { message => q(No allele id selected.), navbar => 1 } );
		return;
	}
	my $seq_ref = $self->{'datastore'}->run_query(
		'SELECT * FROM sequences WHERE (locus,allele_id)=(?,?)',
		[ $locus, $allele_id ],
		{ fetch => 'row_hashref' }
	);
	if ( !$seq_ref ) {
		$self->print_bad_status( { message => q(This sequence does not exist.), navbar => 1 } );
		return;
	}
	my $length = length( $seq_ref->{'sequence'} );
	my $seq    = BIGSdb::Utils::split_line( $seq_ref->{'sequence'} );
	my $data   = [];
	say q(<div class="box" id="resultspanel">);
	say q(<div class="scrollable">);
	say q(<div><span class="info_icon fas fa-2x fa-fw fa-globe fa-pull-left" style="margin-top:-0.2em"></span>);
	say q(<h2>Provenance/meta data</h2>);
	push @$data,
	  {
		title => 'locus',
		data  => $cleaned_locus,
		href  => qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=locusInfo&amp;locus=$locus)
	  };
	push @$data, { title => 'allele', data => $allele_id };

	if ( $allele_id eq '0' ) {
		push @$data,
		  {
			title => 'description',
			data  => q(This is a null allele. When included in a profile it means that this locus is missing.)
		  };
	} elsif ( $allele_id eq 'N' ) {
		push @$data,
		  {
			title => 'description',
			data  => q(This is an arbitrary allele.  When included in a profile it means that this locus is ignored.)
		  };
	} else {
		push @$data,
		  (
			{ title => 'sequence',     data => $seq, class => 'seq' },
			{ title => 'length',       data => $length },
			{ title => 'status',       data => $seq_ref->{'status'} },
			{ title => 'date entered', data => $seq_ref->{'date_entered'} },
			{ title => 'datestamp',    data => $seq_ref->{'datestamp'} }
		  );
		my $sender = $self->{'datastore'}->get_user_string(
			$seq_ref->{'sender'},
			{
				affiliation => ( $seq_ref->{'sender'} != $seq_ref->{'curator'} ),
				email       => !$self->{'system'}->{'privacy'}
			}
		);
		push @$data, { title => 'sender', data => $sender };
		my $curator = $self->{'datastore'}->get_user_string( $seq_ref->{'curator'}, { affiliation => 1, email => 1 } );
		push @$data, { title => 'curator', data => $curator };
	}
	push @$data, { title => 'comments', data => $seq_ref->{'comments'} } if $seq_ref->{'comments'};
	my $flags = $self->_get_flags( $locus, $allele_id );
	push @$data, { title => 'flags', data => $flags } if $flags;
	my $extended_attributes = $self->{'datastore'}->get_allele_extended_attributes( $locus, $allele_id );
	my $extended_att_urls =
	  $self->{'datastore'}->run_query( 'SELECT field,url FROM locus_extended_attributes WHERE locus=?',
		$locus, { fetch => 'all_hashref', key => 'field' } );
	foreach my $ext (@$extended_attributes) {
		my $cleaned_field = $ext->{'field'};
		$cleaned_field =~ tr/_/ /;
		if ( $cleaned_field =~ /sequence$/x ) {
			my $ext_seq = BIGSdb::Utils::split_line( $ext->{'value'} );
			push @$data, { title => $cleaned_field, data => $ext_seq, class => 'seq' };
		} else {
			my $url = $extended_att_urls->{ $ext->{'field'} }->{'url'};
			if ($url) {
				$url =~ s/\[\?\]/$ext->{'value'}/gx;
			}
			push @$data, { title => $cleaned_field, data => $ext->{'value'}, href => $url };
		}
	}
	say $self->get_list_block($data);
	say q(</div>);
	$self->_print_accessions( $locus, $allele_id );
	$self->_print_ref_links( $locus, $allele_id );
	my $qry         = 'SELECT schemes.* FROM schemes LEFT JOIN scheme_members ON schemes.id=scheme_id WHERE locus=?';
	my $scheme_list = $self->{'datastore'}->run_query( $qry, $locus, { fetch => 'all_arrayref', slice => {} } );
	my $set_id      = $self->get_set_id;

	if (@$scheme_list) {
		my $profiles_list = [];
		foreach my $scheme (@$scheme_list) {
			my $scheme_info =
			  $self->{'datastore'}->get_scheme_info( $scheme->{'id'}, { set_id => $set_id, get_pk => 1 } );
			next if !$scheme_info->{'primary_key'};
			my $profiles =
			  $self->{'datastore'}
			  ->run_query( 'SELECT COUNT(*) FROM profile_members WHERE (scheme_id,locus,allele_id)=(?,?,?)',
				[ $scheme->{'id'}, $locus, $allele_id ] );
			next if !$profiles;
			my $plural  = $profiles == 1 ? ''         : 's';
			my $contain = $profiles == 1 ? 'contains' : 'contain';
			$q->param( page      => 'query' );
			$q->param( scheme_id => $scheme->{'id'} );
			$q->param( s1        => $locus );
			$q->param( y1        => '=' );
			$q->param( t1        => $allele_id );
			$q->param( order     => $scheme_info->{'primary_key'} );
			$q->param( submit    => 1 );
			my $profile_buffer = $q->start_form;
			$profile_buffer .= $q->hidden($_) foreach qw (db page scheme_id s1 y1 t1 order submit);
			$profile_buffer .= $q->submit( -label => "$profiles profile$plural", -class => 'smallbutton' );
			$profile_buffer .= $q->end_form;
			push @$profiles_list, { title => $scheme_info->{'name'}, data => $profile_buffer };
		}
		if (@$profiles_list) {
			say q(<div>);
			say q(<span class="info_icon fas fa-2x fa-fw fa-table fa-pull-left" style="margin-top:-0.1em"></span>);
			say q(<h2>Profiles containing this allele</h2>);
			say $self->get_list_block($profiles_list);
			say q(</div>);
		}
	}
	$self->_print_client_database_data( $locus, $allele_id );
	my $client_buffer = $self->{'datastore'}->get_client_data_linked_to_allele( $locus, $allele_id );
	if ($client_buffer->{'formatted'}){
		say q(<span class="info_icon fas fa-2x fa-fw fa-link fa-pull-left" style="margin-top:-0.2em"></span>);
		say qq(<h2>Linked data</h2>\n$client_buffer->{'formatted'}) 
	}
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
		my $clients = [];
		foreach my $client (@$client_list) {
			my $isolate_count =
			  $self->{'datastore'}->get_client_db( $client->{'id'} )
			  ->count_isolates_with_allele( $client->{'locus_alias'} || $locus, $allele_id );
			next if !$isolate_count;
			my $buffer = qq($client->{'description'} );
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
			push @$clients, { title => $client->{'name'}, data => $buffer };
		}
		if (@$clients) {
			say q(<div>);
			say q(<span class="info_icon fas fa-2x fa-fw fa-database fa-pull-left" style="margin-top:-0.2em"></span>);
			say q(<h2>Isolate databases</h2>);
			say $self->get_list_block($clients);
			say q(</div>);
		}
	}
	return;
}

sub _get_flags {
	my ( $self, $locus, $allele_id ) = @_;
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		my $flags = $self->{'datastore'}->get_allele_flags( $locus, $allele_id );
		if (@$flags) {
			local $" = q(</span> <span class="seqflag">);
			return qq(<span class="seqflag">@$flags</span>);
		}
	}
	return;
}

sub get_title {
	my ($self) = @_;
	my $locus = $self->{'cgi'}->param('locus') // q();
	$locus =~ s/%27/'/gx;    #Web-escaped locus
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
	if (@$accession_list) {
		my $plural = @$accession_list > 1 ? q(s) : q();
		my $count = @$accession_list;
		say q(<div>);
		my ( $display, $offset );
		if ( @$accession_list > 4 ) {
			$display = 'none';
			$offset  = 0.1;
		} else {
			$display = 'block';
			$offset  = -0.1;
		}
		say q(<span class="info_icon fas fa-2x fa-fw fa-external-link-square-alt fa-pull-left" )
		  . qq(style="margin-top:${offset}em"></span>);
		say qq(<h2 style="display:inline">Accession$plural ($count)</h2>);
		my ( $show, $hide ) = ( EYE_SHOW, EYE_HIDE );
		say q(<span class="navigation_button" style="margin-left:1em;vertical-align:middle;margin-bottom:0.5em">)
		  . q(<a id="show_accessions" )
		  . qq(style="cursor:pointer"><span id="show_accessions_text" title="Show accessions" style="display:inline">$show</span>)
		  . qq(<span id="hide_accessions_text" title="Hide accessions" style="display:none">$hide</span></a></span>)
		  if $display eq 'none';
		my $id = $display eq 'none' ? 'hidden_accessions' : 'accessions';
		my $accessions = [];

		foreach my $accession (@$accession_list) {
			my $href;
			if ( $accession->{'databank'} eq 'Genbank' ) {
				$href = qq(https://www.ncbi.nlm.nih.gov/nuccore/$accession->{'databank_id'});
			} elsif ( $accession->{'databank'} eq 'ENA' ) {
				$href = qq(http://www.ebi.ac.uk/ena/data/view/$accession->{'databank_id'});
				say qq(<dd><a href="http://www.ebi.ac.uk/ena/data/view/$accession->{'databank_id'}">)
				  . qq($accession->{'databank_id'}</a></dd>);
			}
			push @$accessions,
			  { title => $accession->{'databank'}, data => $accession->{'databank_id'}, href => $href };
		}
		say qq(<div id="$id">);
		say $self->get_list_block($accessions);
		say q(</div></div>);
	}
	return;
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
		my ( $display, $class, $icon_offset );
		if ( @$pmids > 4 ) {
			$display     = q(none);
			$class       = q(infopanel);
			$icon_offset = 0;
		} else {
			$display     = q(block);
			$class       = q();
			$icon_offset = -0.2;
		}
		say q(<div><span class="info_icon far fa-2x fa-fw fa-newspaper fa-pull-left" )
		  . qq(style="margin-top:${icon_offset}em"></span>);
		say qq(<h2 style="display:inline">Publication$plural ($count)</h2>);
		my ( $show, $hide ) = ( EYE_SHOW, EYE_HIDE );
		say q(<span class="navigation_button" style="margin-left:1em;vertical-align:middle"><a id="show_refs" )
		  . qq(style="cursor:pointer"><span id="show_refs_text" title="Show references" style="display:inline">$show</span>)
		  . qq(<span id="hide_refs_text" title="Hide references" style="display:none">$hide</span></a></span>)
		  if $display eq 'none';
		my $id = $display eq 'none' ? 'hidden_references' : 'references';
		say qq(<ul id="$id" class="$class" style="display:$display">);
		my $citations =
		  $self->{'datastore'}->get_citation_hash( $pmids,
			{ formatted => 1, all_authors => 1, state_if_unavailable => 1, link_pubmed => 1 } );

		foreach my $pmid ( sort { $citations->{$a} cmp $citations->{$b} } @$pmids ) {
			say qq(<li style="padding-bottom:1em">$citations->{$pmid}</li>);
		}
		say q(</ul></div>);
	}
	return;
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {

	\$("#hidden_accessions").css('display', 'none');
	\$("#show_accessions").click(function() {
		if (\$("span#show_accessions_text").css('display') == 'none'){
			\$("span#show_accessions_text").css('display', 'inline');
			\$("span#hide_accessions_text").css('display', 'none');
		} else {
			\$("span#show_accessions_text").css('display', 'none');
			\$("span#hide_accessions_text").css('display', 'inline');
		}
		\$("#hidden_accessions").toggle( 'blind', {} , 500 );
	});
	\$( "#hidden_references" ).css('display', 'none');
	\$( "#show_refs" ).click(function() {
		if (\$("span#show_refs_text").css('display') == 'none'){
			\$("span#show_refs_text").css('display', 'inline');
			\$("span#hide_refs_text").css('display', 'none');
		} else {
			\$("span#show_refs_text").css('display', 'none');
			\$("span#hide_refs_text").css('display', 'inline');
		}
		\$( "#hidden_references" ).toggle( 'blind', {} , 500 );
	});

});

END
	return $buffer;
}
1;
