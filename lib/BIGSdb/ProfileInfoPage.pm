#Written by Keith Jolley
#Copyright (c) 2010-2013, University of Oxford
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
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $scheme_id  = $q->param('scheme_id');
	my $profile_id = $q->param('profile_id');
	if ( !$scheme_id ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No scheme id passed.</p></div>";
		return;
	} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Scheme id must be an integer.</p></div>";
		return;
	} elsif ( !$profile_id ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No profile id passed.</p></div>";
		return;
	}
	my $set_id = $self->get_set_id;
	if ($set_id) {
		if ( !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
			say "<div class=\"box\" id=\"statusbad\"><p>The selected scheme is unavailable.</p></div>";
			return;
		}
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
	if ( !$scheme_info ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Scheme $scheme_id does not exist.</p></div>";
		return;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say "<div class=\"box\" id=\"statusbad\"><p>This function is not available within an isolate database.</p></div>";
		return;
	}
	my $primary_key =
	  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
	if ( !$primary_key ) {
		say "<div class=\"box\" id=\"statusbad\"><p>There is no primary key defined for this scheme.</p></div>";
		return;
	}
	say "<h1>Profile information for $primary_key-$profile_id ($scheme_info->{'description'})</h1>";
	my $sql = $self->{'db'}->prepare("SELECT * FROM scheme_$scheme_id WHERE $primary_key=?");
	eval { $sql->execute($profile_id) };
	if ($@) {
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid query.</p></div>";
		$logger->error($@);
		return;
	}
	my $data = $sql->fetchrow_hashref;
	if ( !defined $data ) {
		say "<div class=\"box statusbad\"><p>This profile does not exist!</p></div>";
		return;
	}
	if ( $q->param('history') ) {
		say "<div class=\"box\" id=\"resultstable\">";
		say "<h2>Update history</h2>";
		say "<p><a href=\"$self->{'system'}->{'script_name'}?page=profileInfo&amp;db=$self->{'instance'}&amp;scheme_id=$scheme_id&amp;"
		  . "profile_id=$profile_id\">Back to profile information</a></p>";
		say $self->_get_update_history( $scheme_id, $profile_id ) // '';
	} else {
		say "<div class=\"box\" id=\"resultspanel\">";
		say "<div class=\"scrollable\">";
		say "<dl class=\"profile\">";
		say "<dt>$primary_key</dt><dd>$profile_id</dd>";
		say "</dl>";
		my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		foreach my $locus (@$loci) {
			my $cleaned = $self->clean_locus($locus);
			( my $cleaned2 = $locus ) =~ s/'/_PRIME_/g;
			say "<dl class=\"profile\"><dt>$cleaned</dt><dd><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;"
			  . "page=alleleInfo&amp;locus=$locus&amp;allele_id=$data->{lc($cleaned2)}\">$data->{lc($cleaned2)}</a></dd></dl>";
		}
		foreach my $field (@$scheme_fields) {
			my $cleaned = $field;
			next if $field eq $primary_key;
			$cleaned =~ tr/_/ /;
			say "<dl class=\"profile\"><dt>$cleaned</dt>";
			$data->{ lc($field) } //= '&nbsp;';
			say "<dd>$data->{lc($field)}</dd></dl>";
		}
		say "<dl class=\"data\">";
		foreach my $field (qw (sender curator date_entered datestamp)) {
			my $cleaned = $field;
			$cleaned =~ tr/_/ /;
			say "<dt>$cleaned</dt>";
			if ( $field eq 'sender' || $field eq 'curator' ) {
				my $userdata = $self->{'datastore'}->get_user_info( $data->{$field} );
				my $person   = "$userdata->{'first_name'} $userdata->{'surname'}";
				$person .= ", $userdata->{'affiliation'}" if !( $field eq 'sender' && $data->{'sender'} == $data->{'curator'} );
				if ( $field eq 'curator' || !$self->{'system'}->{'privacy'} ) {
					if ( $userdata->{'email'} =~ /\@/ ) {
						$person .= " (E-mail: <a href=\"mailto:$userdata->{'email'}\">$userdata->{'email'}</a>)";
					} else {
						$person .= " (E-mail: $userdata->{'email'})";
					}
				}
				say "<dd>$person</dd>";
				if ( $field eq 'curator' ) {
					my ( $history, $num_changes ) = $self->_get_history( $scheme_id, $profile_id, 10 );
					if ($num_changes) {
						my $plural = $num_changes == 1 ? '' : 's';
						my $title;
						$title = "Update history - ";
						foreach (@$history) {
							my $time = $_->{'timestamp'};
							$time =~ s/ \d\d:\d\d:\d\d\.\d+//;
							my $action = $_->{'action'};
							$action =~ s/:.*//g;
							$title .= "$time: $action<br />";
						}
						if ( $num_changes > 10 ) {
							$title .= "more ...";
						}
						say "<dt>update history</dt>";
						my $refer_page = $self->{'cgi'}->param('page');
						say "<dd><a title=\"$title\" class=\"pending_tooltip\">$num_changes update$plural</a>";
						say " <a href=\"$self->{'system'}->{'script_name'}?page=profileInfo&amp;db=$self->{'instance'}&amp;"
						  . "scheme_id=$scheme_id&amp;profile_id=$profile_id&amp;history=1&amp;refer=$refer_page\">show details</a>"
						  . "</dd>";
					}
				}
			} else {
				$data->{ lc($field) } ||= '';
				say "<dd>$data->{lc($field)}</dd>";
			}
		}
		say "</dl>";
		say $self->_get_ref_links( $scheme_id, $profile_id );
		my $qry = "SELECT client_dbase_id, client_scheme_id FROM client_dbase_schemes WHERE scheme_id=?";
		$sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute($scheme_id) };
		$logger->error($@) if $@;
		my $clients = $sql->fetchall_arrayref;

		if (@$clients) {
			my $plural = @$clients > 1 ? 's' : '';
			my $buffer;
			foreach my $client (@$clients) {
				my ( $client_dbase_id, $client_scheme_id ) = @$client;
				my $client_info = $self->{'datastore'}->get_client_db_info($client_dbase_id);
				my $loci = $self->{'datastore'}->run_list_query( "SELECT locus FROM scheme_members WHERE scheme_id=?", $scheme_id );
				my $sql2 = $self->{'db'}->prepare("SELECT locus,locus_alias FROM client_dbase_loci WHERE client_dbase_id=? AND locus=?");
				my %alleles;
				foreach (@$loci) {
					eval { $sql2->execute( $client_dbase_id, $_ ) };
					$logger->error($@) if $@;
					while ( my ( $c_locus, $c_alias ) = $sql2->fetchrow_array ) {
						$alleles{ $c_alias || $c_locus } = $data->{ lc($_) } if $data->{ lc($_) } ne 'N';
					}
				}
				my $count;
				if ( !( scalar keys %alleles ) ) {
					$logger->error("No client database loci have been set.");
					$count = 0;
				} else {
					$count = $self->{'datastore'}->get_client_db($client_dbase_id)->count_matching_profiles( \%alleles );
				}
				if ($count) {
					my $plural = $count == 1 ? '' : 's';
					$buffer .= "<dt>$client_info->{'name'}</dt>\n";
					$buffer .= "<dd>$client_info->{'description'} ";
					my $primary_key;
					eval {
						$primary_key =
						  $self->{'datastore'}
						  ->run_list_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
					};
					$logger->error($@) if $@;
					if ( $client_info->{'url'} ) {

						#it seems we have to pass the parameters in the action clause for mod_perl2
						#but separately for stand-alone CGI.
						my $c_scheme_id = $client_scheme_id // $scheme_id;
						my %params = (
							db     => $client_info->{'dbase_config_name'},
							page   => 'query',
							ls1    => "s_$c_scheme_id\_$primary_key",
							ly1    => '=',
							lt1    => $profile_id,
							order  => 'id',
							submit => 1
						);
						my @action_params;
						foreach ( keys %params ) {
							$q->param( $_, $params{$_} );
							push @action_params, "$_=$params{$_}";
						}
						local $" = '&';
						$buffer .= $q->start_form(
							-action => "$client_info->{'url'}?@action_params",
							-method => 'post',
							-style  => 'display:inline'
						);
						$buffer .= $q->hidden($_) foreach qw (db page ls1 ly1 lt1 order submit);
						$buffer .= $q->submit( -label => "$count isolate$plural", -class => 'smallbutton' );
						$buffer .= $q->end_form;
					}
					$buffer .= "</dd>\n";
				}
			}
			if ($buffer) {
				say "<h2>Client database$plural</h2>";
				say "<dl class=\"data\">";
				say $buffer;
				say "</dl>";
			}
		}
		say "</div>";
	}
	say "</div>";
	return;
}

sub _get_history {
	my ( $self, $scheme_id, $profile_id, $limit ) = @_;
	my $limit_clause = $limit ? " LIMIT $limit" : '';
	my $qry =
	  "SELECT timestamp,action,curator FROM profile_history where scheme_id=? AND profile_id=? ORDER BY timestamp desc$limit_clause";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute( $scheme_id, $profile_id ) };
	$logger->error($@) if $@;
	my @history;
	while ( my $data = $sql->fetchrow_hashref ) {
		push @history, $data;
	}
	my $count;
	if ($limit) {

		#need to count total
		$count =
		  $self->{'datastore'}
		  ->run_simple_query( "SELECT COUNT(*) FROM profile_history WHERE scheme_id=? AND profile_id=?", $scheme_id, $profile_id )->[0];
	} else {
		$count = @history;
	}
	return \@history, $count;
}

sub _get_ref_links {
	my ( $self, $scheme_id, $profile_id ) = @_;
	my $pmids =
	  $self->{'datastore'}
	  ->run_list_query( "SELECT profile_refs.pubmed_id FROM profile_refs WHERE scheme_id=? AND profile_id=? ORDER BY pubmed_id",
		$scheme_id, $profile_id );
	return $self->get_refs($pmids);
}

sub _get_update_history {
	my ( $self, $scheme_id, $profile_id ) = @_;
	my ( $history, undef ) = $self->_get_history( $scheme_id, $profile_id );
	my $buffer;
	if (@$history) {
		$buffer .= "<table class=\"resultstable\"><tr><th>Timestamp</th><th>Curator</th><th>Action</th></tr>\n";
		my $td = 1;
		foreach (@$history) {
			my $curator_info = $self->{'datastore'}->get_user_info( $_->{'curator'} );
			my $time         = $_->{'timestamp'};
			$time =~ s/:\d\d\.\d+//;
			my $action = $_->{'action'};
			$action =~ s/->/\&rarr;/g;
			$buffer .= "<tr class=\"td$td\"><td>$time</td><td>$curator_info->{'first_name'} $curator_info->{'surname'}</td>"
			  . "<td style=\"text-align:left\">$action</td></tr>\n";
			$td = $td == 1 ? 2 : 1;
		}
		$buffer .= "</table>\n";
	}
	return $buffer;
}

sub get_title {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $scheme_id  = $q->param('scheme_id');
	my $profile_id = $q->param('profile_id');
	my $scheme_info;
	my $primary_key;
	if ( $scheme_id && BIGSdb::Utils::is_int($scheme_id) ) {
		my $set_id = $self->get_set_id;
		$scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		eval {
			$primary_key =
			  $self->{'datastore'}->run_list_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
		};
	}
	my $title = "Profile information";
	$title .= ": $primary_key-$profile_id" if $primary_key && defined $profile_id;
	$title .= " ($scheme_info->{'description'})" if defined $scheme_info;
	$title .= ' - ';
	$title .= "$self->{'system'}->{'description'}";
	return $title;
}

sub get_link_button_to_ref {
	my ( $self, $ref ) = @_;
	my $count;
	my @reffields;
	my $buffer;
	my $qry = "SELECT COUNT(profile_refs.profile_id) FROM profile_refs RIGHT JOIN profiles on profile_refs.profile_id=profiles.profile_id "
	  . "AND profile_refs.scheme_id=profiles.scheme_id WHERE pubmed_id=?";
	$count = $self->{'datastore'}->run_simple_query( $qry, $ref )->[0];
	my $q = $self->{'cgi'};
	$buffer .= $q->start_form( -style => "display:inline" );
	$q->param( 'curate', 1 ) if $self->{'curate'};
	my $scheme_id = $q->param('scheme_id');
	my $primary_key;
	eval {
		$primary_key =
		  $self->{'datastore'}->run_list_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
	};
	$logger->error($@) if $@;
	my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $order_by = $pk_info->{'type'} eq 'integer' ? "lpad($primary_key,20,'0')" : $primary_key;
	$q->param( 'query',
		    "SELECT * FROM profile_refs LEFT JOIN scheme_$scheme_id on profile_refs.profile_id=scheme_$scheme_id\.$primary_key "
		  . "WHERE pubmed_id='$ref' AND profile_refs.scheme_id='$scheme_id' ORDER BY $order_by" );
	$q->param( 'pmid', $ref );
	$q->param( 'page', 'pubquery' );
	$buffer .= $q->hidden($_) foreach qw (db query pmid page curate scheme_id);
	my $plural = $count == 1 ? '' : 's';
	$buffer .= $q->submit( -value => "$count profile$plural", -class => 'smallbutton' );
	$buffer .= $q->end_form;
	return $buffer;
}
1;
