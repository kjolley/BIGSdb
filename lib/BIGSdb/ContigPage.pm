#Written by Keith Jolley
#Copyright (c) 2025, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
package BIGSdb::ContigPage;
use strict;
use warnings;
use 5.010;
use parent        qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $q->param('id');
	if ( !defined $id ) {
		say q(<h1>Contig record</h1>);
		$self->print_bad_status( { message => q(Contig id not specified.) } );
		return;
	}
	if ( !BIGSdb::Utils::is_int($id) ) {
		say q(<h1>Contig record</h1>);
		$self->print_bad_status( { message => q(Contig id must be an integer.) } );
		return;
	}

	my $contig = $self->{'datastore'}->run_query(
		'SELECT isolate_id,method,original_designation,comments,sender,curator,date_entered,'
		  . 'datestamp FROM sequence_bin WHERE id=?',
		$id,
		{ fetch => 'row_hashref' }
	);
	if ( !defined $contig ) {
		say q(<h1>Contig record</h1>);
		$self->print_bad_status( { message => qq(Contig id: $id does not exist.) } );
		return;
	}
	say qq(<h1>Contig record - id: $id</h1>);
	my $date_restriction = $self->{'datastore'}->get_date_restriction;
	my $restricted;
		if ( $date_restriction && $date_restriction lt $contig->{'date_entered'} && !$self->{'username'} ) {
		$restricted = 1;
		my $date_restriction_message = $self->get_date_restriction_message;
		if ($date_restriction_message) {
			say qq(<div class="box banner">$date_restriction_message</div>);
		}
	}
	say q(<div class="box resultspanel">);
	my $labelfield = $self->{'system'}->{'labelfield'} // 'isolate';
	my $seq_ref    = $self->{'contigManager'}->get_contig($id);
	my $seq        = BIGSdb::Utils::split_line($$seq_ref);
	my $list       = $self->get_list_block(
		[
			{
				title => "$labelfield id",
				data  => $contig->{'isolate_id'},
				href  => "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;"
				  . "page=info&amp;id=$contig->{'isolate_id'}"
			},
			{
				title => "$labelfield name",
				data  => $self->get_isolate_name_from_id( $contig->{'isolate_id'} ) || q(-)
			},
			{
				title => 'method',
				data  => $contig->{'method'} // 'unknown'
			},
			{
				title => 'original designation',
				data  => $contig->{'original_designation'} // q(-)
			},
			{
				title => 'length',
				data  => BIGSdb::Utils::commify( length($$seq_ref) ) . ' bp'
			},
			{
				title => 'comments',
				data  => $contig->{'comments'} // q(-)
			},
			{
				title => 'sender',
				data  => $self->{'datastore'}->get_user_string(
					$contig->{'sender'}, { affiliation => 1, email => !$self->{'system'}->{'privacy'} }
				)
			},
			{
				title => 'curator',
				data  => $self->{'datastore'}->get_user_string( $contig->{'curator'}, { affiliation => 1, email => 1 } )
			},
			{
				title => 'date entered',
				data  => $contig->{'date_entered'}

			},
			{
				title => 'datestamp',
				data  => $contig->{'datestamp'}

			},
			{
				title => 'sequence',
				data  => $restricted ? 'UNAVAILABLE' : $seq,
				class => 'seq'
			}
		]
	);
	say $list;

	say q(</div>);
	return;
}

sub get_title {
	my ($self)    = @_;
	my $desc      = $self->{'system'}->{'description'} || 'BIGSdb';
	my $contig_id = $self->{'cgi'}->param('contig_id');
	if ($contig_id) {
		return qq(Contig record: id-$contig_id - $desc);
	}
	return qq(Contig record - $desc);
}

1;
