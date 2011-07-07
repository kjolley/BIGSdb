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

package BIGSdb::Locus;
use strict;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Locus');

sub new {
	my $class = shift;
	my $self  = {@_};
	$self->{'sql'} = {};
	if (!$self->{'id'}){
		throw BIGSdb::DataException("Invalid locus");
	}
	$self->{'dbase_id_field'}  = 'id'       if !$self->{'dbase_id_field'};
	$self->{'dbase_seq_field'} = 'sequence' if !$self->{'dbase_seq_field'};
	bless( $self, $class );
	$logger->info("Locus $self->{'id'} set up.");
	return $self;
}

sub DESTROY {
	my ($self) = @_;
	foreach ( keys %{ $self->{'sql'} } ) {
		if ( $self->{'sql'}->{$_} ) {
			$self->{'sql'}->{$_}->finish();
			$logger->debug("Locus $self->{'id'} statement handle '$_' finished.");
		}
	}
	$logger->info("Locus $self->{'id'} destroyed.");
}

sub get_allele_sequence {
	my ( $self, $id ) = @_;
	if ( !$self->{'db'} ) {
		throw BIGSdb::DatabaseConnectionException("No connection to locus $self->{'id'} database");
	}
	if ( !$self->{'sql'}->{'sequence'} ) {
		my $qry;
		if ( $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'} ) {
			$self->{'dbase_id2_value'} =~ s/'/\\'/g if $self->{'dbase_id2_value'} !~ /\\'/; #only escape if not already escaped
			$qry =
"SELECT $self->{'dbase_seq_field'} FROM $self->{'dbase_table'} WHERE $self->{'dbase_id_field'}=? AND $self->{'dbase_id2_field'}=E'$self->{'dbase_id2_value'}'";
		} else {
			$qry = "SELECT $self->{'dbase_seq_field'} FROM $self->{'dbase_table'} WHERE $self->{'dbase_id_field'} = ?";
		}
		$self->{'sql'}->{'sequence'} = $self->{'db'}->prepare($qry);
		$logger->debug("Locus $self->{'id'} statement handle 'sequence' prepared ($qry).");
	}
	eval { $self->{'sql'}->{'sequence'}->execute($id); };	
	if ($@) {
		$logger->error(
"Can't execute 'sequence' query handle. Check database attributes in the locus table for locus '$self->{'id'}'! Statement was '$self->{'sql'}->{sequence}->{Statement}'. id='$id'  $@ "
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException("Locus configuration error");
	} else {
		my ($sequence) = $self->{'sql'}->{'sequence'}->fetchrow_array();
		return \$sequence;
	}
}

sub get_all_sequences {
	my ($self) = @_;
	if ( !$self->{'db'} ) {
		$logger->info("No connection to locus $self->{'id'} database");
		return;
	}
	if ( !$self->{'sql'}->{'all_sequences'} ) {
		my $qry;
		if ( $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'} ) {
			$self->{'dbase_id2_value'} =~ s/'/\\'/g if $self->{'dbase_id2_value'} !~ /\\'/; #only escape if not already escaped
			$qry =
"SELECT $self->{'dbase_id_field'},$self->{'dbase_seq_field'} FROM $self->{'dbase_table'} WHERE $self->{'dbase_id2_field'}=E'$self->{'dbase_id2_value'}'";
		} else {
			$qry = "SELECT $self->{'dbase_id_field'},$self->{'dbase_seq_field'} FROM $self->{'dbase_table'}";
		}
		$self->{'sql'}->{'all_sequences'} = $self->{'db'}->prepare($qry);
		$logger->debug("Locus $self->{'id'} statement handle 'all_sequences' prepared ($qry).");
	}
	eval { $self->{'sql'}->{'all_sequences'}->execute; };
	if ($@) {
		$logger->error(
"Can't execute 'sequence' query handle. Check database attributes in the locus table for locus '$self->{'id'}'! Statement was '$self->{'sql'}->{sequence}->{Statement}'. "
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException("Locus configuration error");
		return;
	}
	my %seqs;
	while ( my ( $id, $seq ) = $self->{'sql'}->{'all_sequences'}->fetchrow_array ) {
		$seqs{$id} = $seq;
	}
	return \%seqs;
}

sub get_all_sequence_lengths {
	my ($self) = @_;
	if ( !$self->{'db'} ) {
		$logger->info("No connection to locus $self->{'id'} database");
		return;
	}
	if ( !$self->{'sql'}->{'all_sequence_lengths'} ) {
		my $qry;
		if ( $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'} ) {
			$qry =
"SELECT $self->{'dbase_id_field'},length($self->{'dbase_seq_field'}) FROM $self->{'dbase_table'} WHERE $self->{'dbase_id2_field'}=E'$self->{'dbase_id2_value'}'";
		} else {
			$qry = "SELECT $self->{'dbase_id_field'},length($self->{'dbase_seq_field'}) FROM $self->{'dbase_table'}";
		}
		$self->{'sql'}->{'all_sequence_lengths'} = $self->{'db'}->prepare($qry);
		$logger->debug("Locus $self->{'id'} statement handle 'all_sequences' prepared ($qry).");
	}
	eval { $self->{'sql'}->{'all_sequence_lengths'}->execute; };
	if ($@) {
		$logger->error(
"Can't execute 'all_sequence_lengths' query handle. Check database attributes in the locus table for locus '$self->{'id'}'! Statement was '$self->{'sql'}->{sequence}->{Statement}'. "
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException("Locus configuration error");
		return;
	}
	my %lengths;
	while ( my ( $id, $length ) = $self->{'sql'}->{'all_sequence_lengths'}->fetchrow_array ) {
		$lengths{$id} = $length;
	}
	return \%lengths;
}
1;


