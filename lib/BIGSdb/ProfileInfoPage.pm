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
package BIGSdb::ProfileInfoPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::IsolateInfoPage);
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
use Try::Tiny;
my $logger = get_logger('BIGSdb.Page');
use constant MAX_LOCI_SHOW => 100;

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_records.html#profile-records";
}

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $scheme_id  = $q->param('scheme_id');
	my $profile_id = $q->param('profile_id');
	if ( !$scheme_id ) {
		$self->print_bad_status( { message => q(No scheme id passed.), navbar => 1 } );
		return;
	} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
		$self->print_bad_status( { message => q(Scheme id must be an integer.), navbar => 1 } );
		return;
	} elsif ( !$profile_id ) {
		$self->print_bad_status( { message => q(No profile id passed.), navbar => 1 } );
		return;
	}
	my $set_id = $self->get_set_id;
	if ($set_id) {
		if ( !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
			$self->print_bad_status( { message => q(The selected scheme is unavailable.), navbar => 1 } );
			return;
		}
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	if ( !$scheme_info ) {
		$self->print_bad_status( { message => qq(Scheme $scheme_id does not exist.), navbar => 1 } );
		return;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->print_bad_status(
			{
				message => q(This function is not available within an isolate database.),
				navbar  => 1
			}
		);
		return;
	}
	my $primary_key = $scheme_info->{'primary_key'};
	if ( !$primary_key ) {
		$self->print_bad_status( { message => q(There is no primary key defined for this scheme.), navbar => 1 } );
		return;
	}
	say qq(<h1>Profile information for $primary_key-$profile_id ($scheme_info->{'name'})</h1>);
	my $data =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM mv_scheme_$scheme_id WHERE $primary_key=?", $profile_id, { fetch => 'row_hashref' } );
	if ( !$data ) {
		say q(<div class="box statusbad"><p>This profile does not exist!</p></div>);
		return;
	}
	if ( $q->param('history') ) {
		say q(<div class="box" id="resultstable">);
		say q(<h2>Update history</h2>);
		say $self->_get_update_history( $scheme_id, $profile_id ) // '';
		$self->print_navigation_bar(
			{
				back_url => qq($self->{'system'}->{'script_name'}?page=profileInfo&amp;db=$self->{'instance'}&amp;)
				  . qq(scheme_id=$scheme_id&amp;profile_id=$profile_id)
			}
		);
	} else {
		say q(<div class="box" id="resultspanel">);
		say q(<div class="scrollable">);
		$self->_print_profile( $scheme_id, $profile_id );
		say $self->_get_ref_links( $scheme_id, $profile_id );
		$self->_print_client_db_links( $scheme_id, $profile_id );
		$self->_print_classification_groups( $scheme_id, $profile_id );
		say q(</div>);
	}
	say q(</div>);
	return;
}

sub _print_client_db_links {
	my ( $self, $scheme_id, $profile_id ) = @_;
	my $clients =
	  $self->{'datastore'}
	  ->run_query( 'SELECT client_dbase_id, client_scheme_id FROM client_dbase_schemes WHERE scheme_id=?',
		$scheme_id, { fetch => 'all_arrayref' } );
	my $loci    = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $indices = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
	return if !@$clients;
	my $q           = $self->{'cgi'};
	my $set_id      = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	my $data        = $self->{'datastore'}
	  ->run_query( "SELECT * FROM mv_scheme_$scheme_id WHERE $primary_key=?", $profile_id, { fetch => 'row_hashref' } );
	my $buffer;

	foreach my $client (@$clients) {
		my ( $client_dbase_id, $client_scheme_id ) = @$client;
		my $client_info = $self->{'datastore'}->get_client_db_info($client_dbase_id);
		my %alleles;
		foreach my $locus (@$loci) {
			my ( $c_locus, $c_alias ) = $self->{'datastore'}->run_query(
				'SELECT locus,locus_alias FROM client_dbase_loci WHERE (client_dbase_id,locus)=(?,?)',
				[ $client_dbase_id, $locus ],
				{ cache => 'ProfileInfoPage::client_dbase_loci' }
			);
			if ($c_locus) {
				$alleles{ $c_alias || $c_locus } = $data->{'profile'}->[ $indices->{$locus} ]
				  if $data->{'profile'}->[ $indices->{$locus} ] ne 'N';
			}
		}
		my $count;
		if ( !( scalar keys %alleles ) ) {
			$logger->error('No client database loci have been set.');
			$count = 0;
		} else {
			$count =
			  $self->{'datastore'}->get_client_db($client_dbase_id)->count_matching_profiles( \%alleles );
		}
		if ($count) {
			my $plural = $count == 1 ? q() : q(s);
			$buffer .= qq(<dt>$client_info->{'name'}</dt>\n);
			$buffer .= qq(<dd>$client_info->{'description'} );
			if ( $client_info->{'url'} ) {
				my $c_scheme_id = $client_scheme_id // $scheme_id;
				my %params = (
					db                    => $client_info->{'dbase_config_name'},
					page                  => 'query',
					designation_field1    => "s_$c_scheme_id\_$primary_key",
					designation_operator1 => '=',
					designation_value1    => $profile_id,
					order                 => 'id',
					submit                => 1
				);
				my @action_params;
				foreach my $param ( keys %params ) {
					$q->param( $param, $params{$param} );
					push @action_params, "$param=$params{$param}";
				}
				local $" = '&';

				#We have to pass the parameters in the action clause as
				#mod_rewrite can strip out post params.
				$buffer .= $q->start_form(
					-action => "$client_info->{'url'}?@action_params",
					-method => 'post',
					-style  => 'display:inline'
				);
				$buffer .= $q->hidden($_)
				  foreach qw (db page designation_field1 designation_operator1 designation_value1 order submit);
				$buffer .= $q->submit( -label => "$count isolate$plural", -class => 'smallbutton' );
				$buffer .= $q->end_form;
			}
			$buffer .= qq(</dd>\n);
		}
	}
	if ($buffer) {
		my $plural = @$clients > 1 ? q(s) : q();
		say q(<span class="info_icon fas fa-2x fa-fw fa-database fa-pull-left" style="margin-top:-0.2em"></span>);
		say qq(<h2>Client database$plural</h2>);
		say q(<dl class="data">);
		say $buffer;
		say q(</dl>);
	}
	return;
}

sub _print_classification_groups {
	my ( $self, $scheme_id, $profile_id ) = @_;
	my $buffer = q();
	my $cschemes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT * FROM classification_schemes WHERE scheme_id=? ORDER BY display_order,name',
		$scheme_id, { fetch => 'all_arrayref', slice => {} } );
	return if !@$cschemes;
	my $client_dbs = $self->{'datastore'}->run_query(
		'SELECT * FROM client_dbase_cschemes cdc JOIN classification_schemes c ON cdc.cscheme_id=c.id JOIN '
		  . 'client_dbases cd ON cdc.client_dbase_id=cd.id WHERE c.scheme_id=? ORDER BY cd.name',
		$scheme_id,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $td = 1;
	foreach my $cscheme (@$cschemes) {
		my $cgroup = $self->{'datastore'}->run_query(
			'SELECT group_id FROM classification_group_profiles WHERE (cg_scheme_id,profile_id)=(?,?)',
			[ $cscheme->{'id'}, $profile_id ],
			{ cache => 'ProfileInfoPage::print_classification_groups::groups' }
		);
		next if !defined $cgroup;
		my $desc = $cscheme->{'description'};
		my $tooltip =
		    $desc
		  ? $self->get_tooltip(qq($cscheme->{'name'} - $desc))
		  : q();
		my $profile_count =
		  $self->{'datastore'}
		  ->run_query( 'SELECT COUNT(*) FROM classification_group_profiles WHERE (cg_scheme_id,group_id)=(?,?)',
			[ $cscheme->{'id'}, $cgroup ] );
		next if $profile_count == 1;
		my $url = qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=query&amp;)
		  . qq(scheme_id=$scheme_id&amp;s1=$cscheme->{'name'}&amp;y1==&amp;t1=$cgroup&amp;submit=1);
		$buffer .=
		    qq(<tr class="td$td"><td>$cscheme->{'name'}$tooltip</td><td>Single-linkage</td>)
		  . qq(<td>$cscheme->{'inclusion_threshold'}</td><td>$cscheme->{'status'}</td>)
		  . qq(<td>$cgroup</a></td><td><a href="$url">$profile_count</a></td>);
		if (@$client_dbs) {
			my @client_links = ();
			foreach my $client_db (@$client_dbs) {
				next if $client_db->{'cscheme_id'} != $cscheme->{'id'};
				my $client = $self->{'datastore'}->get_client_db( $client_db->{'id'} );
				my $client_cscheme = $client_db->{'client_cscheme_id'} // $cscheme->{'id'};
				try {
					my $isolates =
					  $client->count_isolates_belonging_to_classification_group( $client_cscheme, $cgroup );
					my $client_db_url = $client_db->{'url'} // $self->{'system'}->{'script_name'};
					if ($isolates) {
						push @client_links,
						    qq(<span class="source">$client_db->{'name'}</span> )
						  . qq(<a href="$client_db_url?db=$client_db->{'dbase_config_name'}&amp;page=query&amp;)
						  . qq(designation_field1=cg_${client_cscheme}_group&amp;designation_value1=$cgroup&amp;submit=1">)
						  . qq($isolates</a>);
					}
				}
				catch {
					if ( $_->isa('BIGSdb::Exception::Database::Configuration') ) {
						$logger->error( "Client database for classification scheme $cscheme->{'name'} "
							  . 'is not configured correctly.' );
					} else {
						$logger->logdie($_);
					}
				};
			}
			local $" = q(<br />);
			$buffer .= qq(<td style="text-align:left">@client_links</td>);
		}
		$buffer .= q(</tr>);
		$td = $td == 1 ? 2 : 1;
	}
	if ($buffer) {
		say q(<div><span class="info_icon fas fa-2x fa-fw fa-sitemap fa-pull-left" )
		  . q(style="margin-top:-0.2em"></span>)
		  . q(<h2>Similar profiles (determined by classification schemes)</h2>)
		  . q(<p>Experimental schemes are subject to change and are not a stable part of the nomenclature.</p>)
		  . q(<div class="scrollable">)
		  . q(<div class="resultstable" style="float:left"><table class="resultstable"><tr>)
		  . q(<th>Classification scheme</th><th>Clustering method</th>)
		  . q(<th>Mismatch threshold</th><th>Status</th><th>Group</th><th>Profiles</th>);
		say q(<th>Isolates</th>) if @$client_dbs;
		say q(</tr>);
		say $buffer;
		say q(</table></div></div></div>);
	}
	return;
}

sub _print_profile {
	my ( $self, $scheme_id, $profile_id ) = @_;
	my $set_id      = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	my $data =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM mv_scheme_$scheme_id WHERE $primary_key=?", $profile_id, { fetch => 'row_hashref' } );
	say qq(<dl class="profile"><dt>$primary_key);
	my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	if ( $scheme_field_info->{'description'} ) {
		say $self->get_tooltip( qq($primary_key - $scheme_field_info->{'description'}), { style => 'color:white' } );
	}
	say qq(</dt><dd>$profile_id</dd></dl>);
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $indices       = $self->{'datastore'}->get_scheme_locus_indices( $scheme_info->{'id'} );
	my $count         = 0;
	foreach my $locus (@$loci) {
		$count++;
		my $cleaned = $self->clean_locus($locus);
		my $value   = $data->{'profile'}->[ $indices->{$locus} ];
		my ( $style, $class );
		if ( $count > MAX_LOCI_SHOW ) {
			$style = q( style="display:none");
			$class = q( extra_locus);
		} else {
			$style = q();
			$class = q();
		}
		say qq(<dl class="profile$class"$style><dt>$cleaned</dt><dd><a href="$self->{'system'}->{'script_name'}?)
		  . qq(db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$locus&amp;allele_id=$value">)
		  . qq($value</a></dd></dl>);
	}
	foreach my $field (@$scheme_fields) {
		my $cleaned = $field;
		next if $field eq $primary_key;
		$cleaned =~ tr/_/ /;
		$scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		if ( $scheme_field_info->{'description'} ) {
			$cleaned .=
			  $self->get_tooltip( qq($cleaned - $scheme_field_info->{'description'}), { style => 'color:white' } );
		}
		say qq(<dl class="profile"><dt>$cleaned</dt>);
		$data->{ lc($field) } //= q(&nbsp;);
		say qq(<dd>$data->{lc($field)}</dd></dl>);
	}
	if ( $count > MAX_LOCI_SHOW ) {
		my ( $show, $hide ) = ( EYE_SHOW, EYE_HIDE );
		say q(<span class="navigation_button" style="margin-left:1em;vertical-align:middle"><a id="show_more" )
		  . qq(style="cursor:pointer"><span id="show_extra_loci" title="Show extra loci" style="display:inline">$show</span>)
		  . qq(<span id="hide_extra_loci" title="Hide extra loci" style="display:none">$hide</span></a></span>);
	}
	say q(<dl class="data">);
	foreach my $field (qw (sender curator date_entered datestamp)) {
		my $cleaned = $field;
		$cleaned =~ tr/_/ /;
		if ( $field eq 'sender' ) {
			my $sender = $self->{'datastore'}->get_user_string(
				$data->{'sender'},
				{
					affiliation => ( $data->{'sender'} != $data->{'curator'} ),
					email       => !$self->{'system'}->{'privacy'}
				}
			);
			say qq(<dt>sender</dt><dd>$sender</dd>);
		} elsif ( $field eq 'curator' ) {
			my $curator = $self->{'datastore'}->get_user_string( $data->{'curator'}, { affiliation => 1, email => 1 } );
			say qq(<dt>curator</dt><dd>$curator</dd>);
			my ( $history, $num_changes ) = $self->_get_history( $scheme_id, $profile_id, 10 );
			if ($num_changes) {
				my $plural = $num_changes == 1 ? '' : 's';
				my $title;
				$title = q(Update history - );
				foreach (@$history) {
					my $time = $_->{'timestamp'};
					$time =~ s/\ \d\d:\d\d:\d\d\.\d+//x;
					my $action = $_->{'action'};
					$action =~ s/:.*//gx;
					$title .= qq($time: $action<br />);
				}
				if ( $num_changes > 10 ) {
					$title .= q(more ...);
				}
				say q(<dt>update history</dt>);
				my $refer_page = $self->{'cgi'}->param('page');
				say qq(<dd><a title="$title" class="update_tooltip">$num_changes update$plural</a>)
				  . qq( <a href="$self->{'system'}->{'script_name'}?page=profileInfo&amp;)
				  . qq(db=$self->{'instance'}&amp;scheme_id=$scheme_id&amp;profile_id=$profile_id&amp;)
				  . qq(history=1&amp;refer=$refer_page">show details</a></dd>);
			}
		} else {
			say qq(<dt>$cleaned</dt>);
			$data->{ lc($field) } ||= '';
			say qq(<dd>$data->{lc($field)}</dd>);
		}
	}
	say q(</dl>);
	return;
}

sub _get_history {
	my ( $self, $scheme_id, $profile_id, $limit ) = @_;
	my $limit_clause = $limit ? " LIMIT $limit" : '';
	my $data = $self->{'datastore'}->run_query(
		'SELECT timestamp,action,curator FROM profile_history where '
		  . "(scheme_id,profile_id)=(?,?) ORDER BY timestamp desc$limit_clause",
		[ $scheme_id, $profile_id ],
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $count;
	if ($limit) {

		#need to count total
		$count =
		  $self->{'datastore'}->run_query( 'SELECT COUNT(*) FROM profile_history WHERE (scheme_id,profile_id)=(?,?)',
			[ $scheme_id, $profile_id ] );
	} else {
		$count = @$data;
	}
	return $data, $count;
}

sub _get_ref_links {
	my ( $self, $scheme_id, $profile_id ) = @_;
	my $pmids = $self->{'datastore'}->run_query(
		'SELECT profile_refs.pubmed_id FROM profile_refs WHERE (scheme_id,profile_id)=(?,?) ORDER BY pubmed_id',
		[ $scheme_id, $profile_id ],
		{ fetch => 'col_arrayref' }
	);
	return $self->get_refs($pmids);
}

sub _get_update_history {
	my ( $self, $scheme_id, $profile_id ) = @_;
	my ( $history, undef ) = $self->_get_history( $scheme_id, $profile_id );
	my $buffer;
	if (@$history) {
		$buffer .= qq(<table class=\"resultstable\"><tr><th>Timestamp</th><th>Curator</th><th>Action</th></tr>\n);
		my $td = 1;
		foreach (@$history) {
			my $curator_info = $self->{'datastore'}->get_user_info( $_->{'curator'} );
			my $time         = $_->{'timestamp'};
			$time =~ s/:\d\d\.\d+//x;
			my $action = $_->{'action'};
			$action =~ s/->/\&rarr;/gx;
			$buffer .= qq(<tr class="td$td"><td>$time</td><td>$curator_info->{'first_name'} )
			  . qq($curator_info->{'surname'}</td><td style="text-align:left">$action</td></tr>\n);
			$td = $td == 1 ? 2 : 1;
		}
		$buffer .= "</table>\n";
	}
	return $buffer;
}

sub get_javascript {
	my ($self) = @_;
	my $buffer = << "END";
\$(function () {
	\$( "#show_more" ).click(function() {
		if (\$("span#show_extra_loci").css('display') == 'none'){
			\$("span#show_extra_loci").css('display', 'inline');
			\$("span#hide_extra_loci").css('display', 'none');
		} else {
			\$("span#show_extra_loci").css('display', 'none');
			\$("span#hide_extra_loci").css('display', 'inline');
		}
		\$( ".extra_locus" ).toggle();
		return false;
	});
});

END
	return $buffer;
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (tooltips jQuery);
	return;
}

sub get_title {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $scheme_id  = $q->param('scheme_id');
	my $profile_id = $q->param('profile_id');
	my $scheme_info;
	if ( $scheme_id && BIGSdb::Utils::is_int($scheme_id) ) {
		my $set_id = $self->get_set_id;
		$scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	}
	my $title = q(Profile information);
	$title .= qq(: $scheme_info->{'primary_key'}-$profile_id) if $scheme_info->{'primary_key'} && defined $profile_id;
	$title .= qq( ($scheme_info->{'name'}))                   if $scheme_info->{'name'};
	$title .= qq( - $self->{'system'}->{'description'});
	return $title;
}

sub get_link_button_to_ref {
	my ( $self, $ref ) = @_;
	my $count;
	my $buffer;
	my $qry =
	    'SELECT COUNT(profile_refs.profile_id) FROM profile_refs RIGHT JOIN profiles on '
	  . 'profile_refs.profile_id=profiles.profile_id AND profile_refs.scheme_id=profiles.scheme_id '
	  . 'WHERE pubmed_id=?';
	$count = $self->{'datastore'}->run_query( $qry, $ref );
	my $q = $self->{'cgi'};
	$buffer .= $q->start_form( -style => 'display:inline' );
	$q->param( curate => 1 ) if $self->{'curate'};
	$q->param( pmid   => $ref );
	$q->param( page   => 'pubquery' );
	$buffer .= $q->hidden($_) foreach qw (db pmid page curate scheme_id);
	my $plural = $count == 1 ? '' : 's';
	$buffer .= $q->submit( -value => "$count profile$plural", -class => 'smallbutton' );
	$buffer .= $q->end_form;
	return $buffer;
}
1;
