#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
use warnings;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Locus');

sub new {    ## no critic (RequireArgUnpacking)
	my $class = shift;
	my $self  = {@_};
	$self->{'sql'} = {};
	if ( !$self->{'id'} ) {
		throw BIGSdb::DataException('Invalid locus');
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
		eval {
			if ( $self->{'sql'}->{$_} && $self->{'sql'}->{$_}->isa('UNIVERSAL') )
			{
				$self->{'sql'}->{$_}->finish;
				$logger->info("Locus $self->{'id'} statement handle '$_' finished.");
			}
		};
	}
	$logger->info("Locus $self->{'id'} destroyed.");
	return;
}

sub get_allele_sequence {
	my ( $self, $id ) = @_;
	if ( !$self->{'db'} ) {
		throw BIGSdb::DatabaseConnectionException("No connection to locus $self->{'id'} database");
	}
	if ( !$self->{'sql'}->{'sequence'} ) {
		my $qry;
		if ( $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'} ) {
			$qry =
			    "SELECT $self->{'dbase_seq_field'} FROM $self->{'dbase_table'} WHERE "
			  . "($self->{'dbase_id_field'},$self->{'dbase_id2_field'})=(?,?)";
		} else {
			$qry = "SELECT $self->{'dbase_seq_field'} FROM $self->{'dbase_table'} WHERE $self->{'dbase_id_field'}=?";
		}
		$self->{'sql'}->{'sequence'} = $self->{'db'}->prepare($qry);
		$logger->debug("Locus $self->{'id'} statement handle 'sequence' prepared ($qry).");
	}
	my @args = ($id);
	push @args, $self->{'dbase_id2_value'} if $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'};
	eval { $self->{'sql'}->{'sequence'}->execute(@args) };
	if ($@) {
		$logger->error( q(Cannot execute 'sequence' query handle. Check database attributes in the locus table for )
			  . qq(locus '$self->{'id'}'! Statement was '$self->{'sql'}->{sequence}->{Statement}'. id='$id'  $@ )
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException('Locus configuration error');
	} else {
		my ($sequence) = $self->{'sql'}->{'sequence'}->fetchrow_array;
		$self->{'db'}->rollback;    #Prevent table lock on long offline jobs
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
			$qry = "SELECT $self->{'dbase_id_field'},$self->{'dbase_seq_field'} FROM $self->{'dbase_table'} WHERE "
			  . "$self->{'dbase_id2_field'}=?";
		} else {
			$qry = "SELECT $self->{'dbase_id_field'},$self->{'dbase_seq_field'} FROM $self->{'dbase_table'}";
		}
		$self->{'sql'}->{'all_sequences'} = $self->{'db'}->prepare($qry);
		$logger->debug("Locus $self->{'id'} statement handle 'all_sequences' prepared ($qry).");
	}
	my @args;
	push @args, $self->{'dbase_id2_value'} if $self->{'dbase_id2_field'} && $self->{'dbase_id2_value'};
	eval { $self->{'sql'}->{'all_sequences'}->execute(@args) };
	if ($@) {
		$logger->error( q(Cannot execute 'all_sequences' query handle. Check database attributes in the )
			  . qq(locus table for locus '$self->{'id'}'!.)
			  . $self->{'db'}->errstr );
		throw BIGSdb::DatabaseConfigurationException('Locus configuration error');
	}
	my %seqs;
	while ( my ( $id, $seq ) = $self->{'sql'}->{'all_sequences'}->fetchrow_array ) {
		$seqs{$id} = $seq;
	}
	return \%seqs;
}

sub get_flags {
	my ( $self, $allele_id ) = @_;
	if ( !$self->{'db'} ) {
		$logger->info("No connection to locus $self->{'id'} database");
		return [];
	}
	if ( !$self->{'dbase_id2_value'} ) {
		$logger->error('You can only get flags from a BIGSdb seqdef database.');
		return [];
	}
	if ( !$self->{'sql'}->{'flags'} ) {
		$self->{'sql'}->{'flags'} =
		  $self->{'db'}->prepare('SELECT flag FROM allele_flags WHERE (locus,allele_id)=(?,?)');
	}
	eval { $self->{'sql'}->{'flags'}->execute( $self->{'dbase_id2_value'}, $allele_id ) };
	if ($@) {
		$logger->error($@) if $@;
		throw BIGSdb::DatabaseConfigurationException('Locus configuration error');
	}
	my @flags;
	while ( my ($flag) = $self->{'sql'}->{'flags'}->fetchrow_array ) {
		push @flags, $flag;
	}
	return \@flags;
}

sub get_description {
	my ($self) = @_;
	if ( !$self->{'db'} ) {
		$logger->info("No connection to locus $self->{'id'} database");
		return \%;;
	}
	my $sql = $self->{'db'}->prepare('SELECT * FROM locus_descriptions WHERE locus=?');
	eval { $sql->execute( $self->{'id'} ) };
	if ($@) {
		$logger->info("Can't access locus_description table for locus $self->{'id'}") if $@;

		#Not all locus databases have to have a locus_descriptions table.
		return {};
	}
	return $sql->fetchrow_hashref;
}
1;
