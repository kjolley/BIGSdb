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

package BIGSdb::DownloadProfilesPage;
use strict;
use base qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{'type'} = 'text';
	$self->{'jQuery'} = 1;    #Use JQuery javascript library
}

sub print_content {
	my ($self) = @_;
	my $q    = $self->{'cgi'};
	my $scheme_id = $q->param('scheme_id');
	if (!$scheme_id){
		print "No scheme id passed.\n";
		return;
	} elsif (!BIGSdb::Utils::is_int($scheme_id)){
		print "Scheme id must be an integer.\n";
		return;
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	if ( !$scheme_info ) {
		print "Scheme does not exist.\n";
		return;
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $primary_key;
	eval {
	$primary_key = $self->{'datastore'}
		  ->run_simple_query( "SELECT field FROM scheme_fields WHERE primary_key AND scheme_id=?", $q->param('scheme_id') )->[0];
	};
	my $pk_info = $self->{'datastore'}->get_scheme_field_info($scheme_id,$primary_key);
	if (!$primary_key){
		print "This scheme has no primary key set.\n";
		return;
	}
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	print "$primary_key";
	my @fields;
	push @fields,$primary_key ;
	foreach (@$loci){
		print "\t";
		my $locus_info = $self->{'datastore'}->get_locus_info($_);
		my $header_value = $_;
		$header_value .= " ($locus_info->{'common_name'})" if $locus_info->{'common_name'};
		$header_value =~ tr/_/ /;			
		print $header_value;
		(my $cleaned = $_) =~ s/'/_PRIME_/g;
		push @fields,$cleaned;
	}
	foreach (@$scheme_fields){
		next if $_ eq $primary_key;
		print "\t$_";
		push @fields,$_;
	}
	print "\n";
	my $sql = $self->{'db'}->prepare("SELECT @fields FROM scheme_$scheme_id ORDER BY " . ($pk_info->{'type'} eq 'integer' ? "CAST($primary_key AS int)" : $primary_key));
	eval {
		$sql->execute();
	};
	if ($@){
		$logger->error("Can't execute $@");
		print "Can't retrieve data.\n";
		return;
	}
	$"="\t";
	while (my @data = $sql->fetchrow_array()){
		print "@data\n";
	}
}


1;


