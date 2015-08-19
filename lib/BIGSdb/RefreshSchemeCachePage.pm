#Written by Keith Jolley
#Copyright (c) 2015, University of Oxford
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
package BIGSdb::RefreshSchemeCachePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Refresh scheme caches - $desc";
}

sub _print_interface {
	my ( $self, $schemes ) = @_;
	my $q      = $self->{'cgi'};
	my $set_id = $self->get_set_id;
	my %desc;
	foreach my $scheme_id (@$schemes) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		$desc{$scheme_id} = "$scheme_id ) $scheme_info->{'description'}";
	}
	say q(<div class="box" id="queryform">);
	say $q->start_form;
	say q(<fieldset style="float:left"><legend>Select scheme</legend>);
	
	$desc{0} = 'All schemes';
	say $q->popup_menu( -name => 'scheme', -values => [0,@$schemes], -labels => \%desc );
	say q(</fieldset>);
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Refresh cache' } );
	say $q->hidden($_) foreach qw(db page);
	say $q->end_form;
	say q(</div>);
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	say "<h1>Refresh scheme caches - $desc</h1>";
	if ( $self->{'system'}->{'dbtype'} ne 'isolates' ) {
		say q(<div class="box" id="statusbad"><p>This function is only for use on isolate databases.</p></div>);
		return;
	}
	my $schemes =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id FROM schemes WHERE dbase_name IS NOT NULL AND dbase_table IS NOT NULL ORDER BY id',
		undef, { fetch => 'col_arrayref' } );
	my @filtered_schemes;
	my $set_id = $self->get_set_id;
	if ($set_id) {
		foreach my $scheme_id (@$schemes) {
			push @filtered_schemes, $scheme_id if $self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id );
		}
	} else {
		@filtered_schemes = @$schemes;
	}
	if ( !@filtered_schemes ) {
		say q(<div class="box" id="statusbad"><p>There are no schemes that can be cached.<p></div>);
		return;
	}
	$self->_print_interface( \@filtered_schemes );
	if ( $q->param('submit') ) {
		$self->_refresh_caches( \@filtered_schemes );
	}
	return;
}

sub _refresh_caches {
	my ( $self, $schemes ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box" id="resultsheader"><p>);
	
	my @selected_schemes;
	if ( $q->param('scheme') && BIGSdb::Utils::is_int( $q->param('scheme') ) ) {
		push @selected_schemes, $q->param('scheme');
	} else {
		@selected_schemes = @$schemes;
	}
	my $set_id = $self->get_set_id;
	local $| = 1;
	foreach my $scheme_id (@selected_schemes) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
		if ( !defined $scheme_info->{'primary_key'} ) {
			say "Scheme $scheme_id ($scheme_info->{'description'}) does not have a primary key - skipping.<br />";
		} else {
			say qq(Updating scheme $scheme_id cache ($scheme_info->{'description'}) ...);
			$self->{'datastore'}->create_temp_isolate_scheme_fields_view( $scheme_id, { cache => 1 } );
			$self->{'datastore'}->create_temp_scheme_status_table( $scheme_id, { cache => 1 } );
			if ( $ENV{'MOD_PERL'} ) {
				$self->{'mod_perl_request'}->rflush;
				return if $self->{'mod_perl_request'}->connection->aborted;
			}
			say q(done.<br />);
		}
	}
	say q(</p></div>);
	return;
}
1;
