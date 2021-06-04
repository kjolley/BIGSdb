#Written by Keith Jolley
#Copyright (c) 2021, University of Oxford
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
package BIGSdb::RefreshBlastCachePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
use BIGSdb::Offline::Blast;
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	return 'BLAST caches';
}

sub print_content {
	my ($self) = @_;
	say q(<h1>BLAST caches</h1>);
	my $q = $self->{'cgi'};
	if ( $q->param('submit') ) {
		$self->_mark_caches_stale;
		$self->print_good_status( { message => q(All caches marked stale.) } );
	}
	say q(<div class="box queryform">);
	say q(<p>BLAST databases used for sequence queries are cached. These are usually marked stale and re-created )
	  . q(the next time they are needed if new alleles are added, but this process can fail if they are being queried )
	  . q(at the time. Multiple caches are used depending on which loci or schemes are queried, or whether exemplar )
	  . q(alleles are being used. Click the button below to mark all caches as stale, so that they will be )
	  . q(recreated on next use.</p>);
	$self->_print_interface;
	say q(</div>);
	return;
}

sub _mark_caches_stale {
	my ($self) = @_;
	my $blast_obj = BIGSdb::Offline::Blast->new(
		{
			config_dir       => $self->{'config_dir'},
			lib_dir          => $self->{'lib_dir'},
			dbase_config_dir => $self->{'dbase_config_dir'},
			host             => $self->{'system'}->{'host'},
			port             => $self->{'system'}->{'port'},
			user             => $self->{'system'}->{'user'},
			password         => $self->{'system'}->{'password'},
			instance         => $self->{'instance'},
			logger           => $logger
		}
	);
	$blast_obj->mark_all_caches_stale;
	return;
}

sub _print_interface {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say $q->start_form;
	$self->print_action_fieldset( { no_reset => 1, submit_label => 'Mark all caches stale' } );
	say $q->hidden($_) foreach qw(db page);
	say $q->end_form;
	return;
}
1;
