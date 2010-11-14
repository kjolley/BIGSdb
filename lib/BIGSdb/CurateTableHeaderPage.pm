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
package BIGSdb::CurateTableHeaderPage;
use strict;
use base qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{'type'} = 'text';
}

sub print_content {
	my ($self) = @_;
	my @headers;
	my $table = $self->{'cgi'}->param('table');
	if ( !$self->{'datastore'}->is_table($table) ) {
		print "Table $table does not exist!\n";
		return;
	}
	if ( $table eq $self->{'system'}->{'view'} ) {
		foreach ( @{ $self->{'xmlHandler'}->get_field_list } ) {
			push @headers, $_
			  if $_ ne 'id'
			  && $_ ne 'curator'
			  && $_ ne 'sender'
			  && $_ ne 'date_entered'
			  && $_ ne 'datestamp';
			  if ($_ eq $self->{'system'}->{'labelfield'}){
			  	push @headers,'aliases';
			  	push @headers,'references';
			  }
		}
		
	} elsif ( $table eq 'profiles' ) {
		my $scheme_id = $self->{'cgi'}->param('scheme') || 0;
		my $primary_key;
		eval {
			$primary_key =
			  $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $scheme_id )
			  ->[0];
		};
		$logger->error($@) if $@;
		push @headers, $primary_key;
		my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
		push @headers, @$loci;
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);

		foreach (@$scheme_fields) {
			my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $_ );
			push @headers, $_ if !$scheme_field_info->{'primary_key'};
		}
	} else {
		my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
		foreach (@$attributes) {
			
			if ( !( $_->{'name'} eq 'id' && $_->{'type'} eq 'int' ) ) {
				push @headers, $_->{'name'}
				  if $_->{'name'} ne 'curator'
				  && $_->{'name'} ne 'sender'
				  && $_->{'name'} ne 'date_entered'
				  && $_->{'name'} ne 'datestamp';
			}
			if ($table eq 'loci' && $self->{'system'}->{'dbtype'} eq 'isolates' && $_->{'name'} eq 'id'){
				push @headers,'aliases';
			}
		}
		if ($table eq 'sequences' && $self->{'cgi'}->param('locus')){
			shift @headers; #don't include 'locus'
			my $extended_attributes = $self->{'datastore'}->run_list_query("SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order",$self->{'cgi'}->param('locus'));
			if (ref $extended_attributes eq 'ARRAY'){
				push @headers,@$extended_attributes;
			}
		}
	}
	$" = "\t";
	print "@headers";
}
1;    
