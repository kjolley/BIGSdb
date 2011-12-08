#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
use base qw(BIGSdb::IsolateInfoPage);
use Log::Log4perl qw(get_logger);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $scheme_id  = $q->param('scheme_id');
	my $profile_id = $q->param('profile_id');
	if ( !$scheme_id ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No scheme id passed.</p></div>\n";
		return;
	} elsif ( !BIGSdb::Utils::is_int($scheme_id) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Scheme id must be an integer.</p></div>\n";
		return;
	} elsif ( !$profile_id ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No profile id passed.</p></div>\n";
		return;
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	if ( !$scheme_info ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Scheme $scheme_id does not exist.</p></div>\n";
		return;
	} elsif ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>This function is not available within an isolate database.</p></div>\n";
		return;
	}
	my $primary_key =
	  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )->[0];
	if ( !$primary_key ) {
		print "<div class=\"box\" id=\"statusbad\"><p>There is no primary key defined for this scheme.</p></div>\n";
		return;
	}
	print "<h1>Profile information for $primary_key-$profile_id ($scheme_info->{'description'})</h1>\n";
	my $sql = $self->{'db'}->prepare("SELECT * FROM scheme_$scheme_id WHERE $primary_key=?");
	eval { $sql->execute($profile_id) };
	if ($@) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid query.</p></div>\n";
		$logger->error($@);
		return;
	}
	my $data = $sql->fetchrow_hashref;
	if (!defined $data){
		print "<div class=\"box statusbad\"><p>This profile does not exist!</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"resultstable\">\n";
	if ( $q->param('history') ) {
		print "<h2>Update history</h2>\n";
		print
"<p><a href=\"$self->{'system'}->{'script_name'}?page=profileInfo&amp;db=$self->{'instance'}&amp;scheme_id=$scheme_id&amp;profile_id=$profile_id\">Back to profile information</a></p>\n";
		print $self->_get_update_history( $scheme_id, $profile_id );
	} else {
		print "<table class=\"resultstable\">\n";
		print "<tr class=\"td1\"><th>$primary_key</th><td style=\"text-align:left\" colspan=\"5\">$profile_id</td></tr>\n";
		my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		my $td            = 2;
		foreach (@$loci) {
			my $cleaned    = $self->clean_locus($_);
			print "<tr class=\"td$td\"><th>$cleaned</th>";
			( my $cleaned2 = $_ ) =~ s/'/_PRIME_/g;
			print
"<td style=\"text-align:left\" colspan=\"5\"><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=alleleInfo&amp;locus=$_&amp;allele_id=$data->{lc($cleaned2)}\">$data->{lc($cleaned2)}</a></td></tr>\n";
			$td = $td == 1 ? 2 : 1;
		}
		foreach ( @$scheme_fields, qw (sender curator date_entered datestamp) ) {
			next if $_ eq $primary_key;
			my $cleaned = $_;
			$cleaned =~ tr/_/ /;
			print "<tr class=\"td$td\"><th>$cleaned</th>";
			if ( $_ eq 'sender' || $_ eq 'curator' ) {
				my $userdata = $self->{'datastore'}->get_user_info( $data->{$_} );
				print
"<td style=\"text-align:left\" colspan=\"2\">$userdata->{'first_name'} $userdata->{'surname'}</td><td colspan=\"2\" style=\"text-align:left\">$userdata->{'affiliation'}</td>";
				if ( $_ eq 'curator' || !$self->{'system'}->{'privacy'} ) {
					if ( $userdata->{'email'} =~ /\@/ ) {
						print "<td><a href=\"mailto:$userdata->{'email'}\">$userdata->{'email'}</a></td></tr>";
					} else {
						print "<td>$userdata->{'email'}</td></tr>";
					}
				} else {
					print "<td></td></tr>\n";
				}
				if ( $_ eq 'curator' ) {
					my $history = $self->_get_history( $scheme_id, $profile_id );
					my $num_changes = scalar @$history;
					if ($num_changes) {
						$td = $td == 1 ? 2 : 1;
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
						print "<tr class=\"td$td\"><th>update history</th><td style=\"text-align:left\" colspan=\"5\">";
						print "<a title=\"$title\" class=\"pending_tooltip\">";
						print "$num_changes update$plural</a>";
						my $refer_page = $self->{'cgi'}->param('page');
						print
" <a href=\"$self->{'system'}->{'script_name'}?page=profileInfo&amp;db=$self->{'instance'}&amp;scheme_id=$scheme_id&amp;profile_id=$profile_id&amp;history=1&amp;refer=$refer_page\">show details</a></td></tr>";
						$td = $td == 1 ? 2 : 1;
					}
				}
			} else {
				$data->{lc($_)} ||= '';
				print "<td style=\"text-align:left\" colspan=\"5\">$data->{lc($_)}</td></tr>\n";
			}
			$td = $td == 1 ? 2 : 1;
		}
		my $refs =
		  $self->{'datastore'}
		  ->run_list_query( "SELECT profile_refs.pubmed_id FROM profile_refs WHERE scheme_id=? AND profile_id=? ORDER BY pubmed_id",
			$scheme_id, $profile_id );
		foreach (@$refs) {
			print $self->get_main_table_reference( 'reference', $_, $td );
			$td = $td == 1 ? 2 : 1;    #row stripes
		}
		my $qry = "SELECT client_dbase_id,id FROM client_dbase_schemes LEFT JOIN schemes ON schemes.id=scheme_id WHERE scheme_id=?";
		$sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute($scheme_id) };
		$logger->error($@) if $@;
		while ( my ( $client_dbase_id, $scheme_id ) = $sql->fetchrow_array ) {
			my $client_info = $self->{'datastore'}->get_client_db_info($client_dbase_id);
			my $loci        = $self->{'datastore'}->run_list_query( "SELECT locus FROM scheme_members WHERE scheme_id=?", $scheme_id );
			my $sql2        = $self->{'db'}->prepare("SELECT locus,locus_alias FROM client_dbase_loci WHERE client_dbase_id=? AND locus=?");
			my %alleles;
			foreach (@$loci) {
				eval { $sql2->execute( $client_dbase_id, $_ ) };
				$logger->error($@) if $@;
				while ( my ( $c_locus, $c_alias ) = $sql2->fetchrow_array ) {
					$alleles{ $c_alias || $c_locus } = $data->{ lc($_) };
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
				print
"<tr class=\"td$td\"><th>client database</th><td>$client_info->{'name'}</td><td style=\"text-align:left\" colspan=\"3\">$client_info->{'description'}</td>";
				print "<td style=\"text-align:center\">$count isolate$plural<br />";
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
					my %params = (
						'db'     => $client_info->{'dbase_config_name'},
						'page'   => 'query',
						'ls1'    => "s_$scheme_id\_$primary_key",
						'ly1'    => '=',
						'lt1'    => $profile_id,
						'order'  => 'id',
						'submit' => 1
					);
					my @action_params;
					foreach ( keys %params ) {
						$q->param( $_, $params{$_} );
						push @action_params, "$_=$params{$_}";
					}
					local $" = '&';
					print $q->start_form( -action => "$client_info->{'url'}?@action_params", -method => 'post' );
					print $q->hidden($_) foreach qw (db page ls1 ly1 lt1 order submit);
					print $q->submit( -label => 'Display', -class => 'submit' );
					print $q->end_form;
				}
				print "</td></tr>\n";
				$td = $td == 1 ? 2 : 1;
			}
		}
		print "</table>\n";
	}
	print "</div>\n";
	return;
}

sub _get_history {
	my ( $self, $scheme_id, $profile_id ) = @_;
	my $qry = "SELECT timestamp,action,curator FROM profile_history where scheme_id=? AND profile_id=? ORDER BY timestamp desc";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute( $scheme_id, $profile_id ) };
	$logger->error($@) if $@;
	my @history;
	while ( my $data = $sql->fetchrow_hashref ) {
		push @history, $data;
	}
	return \@history;
}

sub _get_update_history {
	my ( $self, $scheme_id, $profile_id ) = @_;
	my $history = $self->_get_history( $scheme_id, $profile_id );
	my $buffer;
	if ( scalar @$history ) {
		$buffer .= "<table class=\"resultstable\"><tr><th>Timestamp</th><th>Curator</th><th>Action</th></tr>\n";
		my $td = 1;
		foreach (@$history) {
			my $curator_info = $self->{'datastore'}->get_user_info( $_->{'curator'} );
			my $time         = $_->{'timestamp'};
			$time =~ s/:\d\d\.\d+//;
			my $action = $_->{'action'};
			$action =~ s/->/\&rarr;/g;
			$buffer .=
"<tr class=\"td$td\"><td>$time</td><td>$curator_info->{'first_name'} $curator_info->{'surname'}</td><td style=\"text-align:left\">$action</td></tr>\n";
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
		$scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
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
	my $qry =
"SELECT COUNT(profile_refs.profile_id) FROM profile_refs RIGHT JOIN profiles on profile_refs.profile_id=profiles.profile_id AND profile_refs.scheme_id=profiles.scheme_id WHERE pubmed_id=?";
	$count = $self->{'datastore'}->run_simple_query( $qry, $ref )->[0];
	$buffer .= $count == 1 ? "1 profile" : "$count profiles";
	my $q = $self->{'cgi'};
	$buffer .= $q->start_form;
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
"SELECT * FROM profile_refs LEFT JOIN scheme_$scheme_id on profile_refs.profile_id=scheme_$scheme_id\.$primary_key WHERE pubmed_id='$ref' AND profile_refs.scheme_id='$scheme_id' ORDER BY $order_by;"
	);
	$q->param( 'pmid', $ref );
	$q->param( 'page', 'pubquery' );

	$buffer .= $q->hidden($_) foreach qw (db query pmid page curate scheme_id);
	$buffer .= $q->submit( -value => 'Display', -class => 'submit' );
	$buffer .= $q->end_form;
	return $buffer;
}
1;
