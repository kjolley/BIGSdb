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
package BIGSdb::Datastore;
use strict;
use Log::Log4perl qw(get_logger);
use Time::HiRes qw(gettimeofday);
use List::MoreUtils qw(any);
use Error qw(:try);
my $logger = get_logger('BIGSdb.Datastore');
use BIGSdb::Page qw(SEQ_METHODS DATABANKS);
use BIGSdb::Locus;
use BIGSdb::Scheme;

sub new {
	my $class = shift;
	my $self  = {@_};
	$self->{'sql'}    = {};
	$self->{'scheme'} = {};
	$self->{'locus'}  = {};
	$self->{'prefs'}  = {};
	bless( $self, $class );
	$logger->info("Datastore set up.");
	return $self;
}

sub update_prefs {
	my ( $self, $prefs ) = @_;
	$self->{'prefs'} = $prefs;
}

sub DESTROY {
	my ($self) = @_;
	foreach ( keys %{ $self->{'sql'} } ) {
		$self->{'sql'}->{$_}->finish() if $self->{'sql'}->{$_};
		$logger->info("Statement handle '$_' destroyed.");
	}
	foreach ( keys %{ $self->{'scheme'} } ) {
		undef $self->{'scheme'}->{$_};
		$logger->info("Scheme $_ destroyed.");
	}
	foreach ( keys %{ $self->{'locus'} } ) {
		undef $self->{'locus'}->{$_};
		$logger->info("locus $_ destroyed.");
	}
	$logger->info("Datastore destroyed.");
}

sub get_data_connector {
	my ($self) = @_;
	throw BIGSdb::DatabaseConnectionException("Data connector not set up.") if !$self->{'dataConnector'};
	return $self->{'dataConnector'};
}

sub get_user_info {
	my ( $self, $id ) = @_;
	if ( !$self->{'sql'}->{'user_info'} ) {
		$self->{'sql'}->{'user_info'} = $self->{'db'}->prepare("SELECT first_name,surname,affiliation,email FROM users WHERE id=?");
		$logger->info("Statement handle 'user_info' prepared.");
	}
	eval { $self->{'sql'}->{'user_info'}->execute($id); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'user_info' query");
	}
	return $self->{'sql'}->{'user_info'}->fetchrow_hashref();
}

sub get_user_info_from_username {
	my ( $self, $id ) = @_;
	if ( !$self->{'sql'}->{'user_info_from_username'} ) {
		$self->{'sql'}->{'user_info_from_username'} =
		  $self->{'db'}->prepare("SELECT first_name,surname,affiliation,email FROM users WHERE user_name=?");
		$logger->info("Statement handle 'user_info_from_username' prepared.");
	}
	eval { $self->{'sql'}->{'user_info_from_username'}->execute($id); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'user_info_from_username' query");
	}
	return $self->{'sql'}->{'user_info_from_username'}->fetchrow_hashref();
}

sub get_permissions {

	#don't bother caching query handle as this should only be called once
	my ( $self, $username ) = @_;
	my $sql =
	  $self->{'db'}
	  ->prepare("SELECT user_permissions.* FROM user_permissions LEFT JOIN users ON user_permissions.user_id = users.id WHERE user_name=?");
	eval { $sql->execute($username); };
	$logger->error("Can't execute $@") if $@;
	return $sql->fetchrow_hashref;
}

sub get_composite_value {
	my ( $self, $isolate_id, $composite_field, $isolate_fields_hashref ) = @_;
	my $value;
	if ( !$self->{'sql'}->{'composite_field_values'} ) {
		$self->{'sql'}->{'composite_field_values'} =
		  $self->{'db'}
		  ->prepare("SELECT field,empty_value,regex FROM composite_field_values WHERE composite_field_id=? ORDER BY field_order");
		$logger->info("Statement handle 'composite_field_values' prepared.");
	}
	eval { $self->{'sql'}->{'composite_field_values'}->execute($composite_field); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'composite_field_values' query");
	}
	my $allele_ids;
	my %scheme_fields;
	my %scheme_field_list;
	while ( my ( $field, $empty_value, $regex ) = $self->{'sql'}->{'composite_field_values'}->fetchrow_array() ) {
		if (
			$regex =~ /[^\w\d\-\.\\\/\(\)\+\* \$]/    #reject regex containing any character not in list
			|| $regex =~ /\$\D/                       #allow only $1, $2 etc. variables
		  )
		{
			$logger->warn(
"Regex for field '$field' in composite field '$composite_field' contains non-valid characters.  This is potentially dangerous as it may allow somebody to include a command that could be executed by the web server daemon.  The regex was '$regex'.  This regex has been disabled."
			);
			undef $regex;
		}
		if ( $field =~ /^f_(.+)/ ) {
			my $isolate_field = $1;
			my $text_value    = $isolate_fields_hashref->{$isolate_field};
			if ($regex) {
				my $expression = "\$text_value =~ $regex";
				eval "$expression";
			}
			$value .= $text_value || $empty_value;
		} elsif ( $field =~ /^l_(.+)/ ) {
			my $locus = $1;
			if ( ref $allele_ids ne 'HASH' ) {
				$allele_ids = $self->get_all_allele_ids($isolate_id);
			}
			my $allele = $allele_ids->{$locus};
			$allele = '&Delta;' if $allele =~ /^del/i;
			if ($regex) {
				my $expression = "\$allele =~ $regex";
				eval "$expression";
			}
			$value .= $allele || $empty_value;
		} elsif ( $field =~ /^s_(\d+)_(.+)/ ) {
			my $scheme_id    = $1;
			my $scheme_field = $2;
			if ( ref $scheme_fields{$scheme_id} ne 'ARRAY' ) {
				$scheme_fields{$scheme_id} = $self->get_scheme_field_values( $isolate_id, $scheme_id );
			}
			if ( ref $scheme_field_list{$scheme_id} ne 'ARRAY' ) {
				$scheme_field_list{$scheme_id} = $self->get_scheme_fields($scheme_id);
			}
			for ( my $i = 0 ; $i < scalar @{ $scheme_field_list{$scheme_id} } ; $i++ ) {
				if ( $scheme_field eq $scheme_field_list{$scheme_id}->[$i] ) {
					my $field_value;
					if ( ref $scheme_fields{$scheme_id} eq 'ARRAY' ) {
						undef $scheme_fields{$scheme_id}->[$i]
						  if $scheme_fields{$scheme_id}->[$i] eq
							  '-999';    #Needed because old style profile databases may use '-999' to denote null values
						$field_value = $scheme_fields{$scheme_id}->[$i];
					} else {
						$value .= "<span class=\"statusbad\">SCHEME_CONFIG_ERROR</span>";
						last;
					}
					if ($regex) {
						my $expression = "\$field_value =~ $regex";
						eval "$expression";
					}
					$value .=
					    $scheme_fields{$scheme_id}->[$i] ne ''
					  ? $field_value
					  : $empty_value;
					last;
				}
			}
		} elsif ( $field =~ /^t_(.+)/ ) {
			my $text = $1;
			$value .= $text;
		}
	}
	return $value;
}

sub get_scheme_field_values {

	#if $field is included, only return that field, otherwise return a reference to an array of all scheme fields
	my ( $self, $isolate_id, $scheme_id, $field ) = @_;
	my $value;
	my $scheme_fields = $self->get_scheme_fields($scheme_id);
	my $scheme_loci   = $self->get_scheme_loci($scheme_id);
	$" = "','";
	my @profile;
	my $allele_ids = $self->get_all_allele_ids($isolate_id);
	foreach (@$scheme_loci) {
		push @profile, $allele_ids->{$_};
	}
	try {
		my $values = $self->get_scheme($scheme_id)->get_field_values_by_profile( \@profile );
		if ($field) {
			for ( my $i = 0 ; $i < scalar @$scheme_fields ; $i++ ) {
				if ( $field eq $scheme_fields->[$i] ) {
					return [ $values->[$i] ];
				}
			}
			return [];
		}
		return $values;
	}
	catch BIGSdb::DatabaseConfigurationException with {
		$logger->warn("Can't retrieve scheme_field values for scheme $scheme_id - scheme configuration error.");
	};
}

sub get_samples {

	#return all sample fields except isolate_id
	my ( $self, $id ) = @_;
	if ( !$self->{'sql'}->{'get_samples'} ) {
		my $fields = $self->{'xmlHandler'}->get_sample_field_list;
		if ( !@$fields ) {
			return \%;;
		}
		$" = ',';
		$self->{'sql'}->{'get_samples'} = $self->{'db'}->prepare("SELECT @$fields FROM samples WHERE isolate_id=? ORDER BY sample_id");
		$logger->info("Statement handle 'get_samples' prepared.");
	}
	eval { $self->{'sql'}->{'get_samples'}->execute($id); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'get_samples' query $@");
	}
	return $self->{'sql'}->{'get_samples'}->fetchall_arrayref( {} );
}

sub profile_exists {

	#used for profile/sequence definitions databases
	my ( $self, $scheme_id, $profile_id ) = @_;
	if ( !$self->{'sql'}->{'profile_exists'} ) {
		$self->{'sql'}->{'profile_exists'} = $self->{'db'}->prepare("SELECT COUNT(*) FROM profiles WHERE scheme_id=? AND profile_id=?");
		$logger->info("Statement handle 'profile_exists' prepared.");
	}
	eval { $self->{'sql'}->{'profile_exists'}->execute( $scheme_id, $profile_id ); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'profile_exists' query $@");
	}
	my ($exists) = $self->{'sql'}->{'profile_exists'}->fetchrow_array();
	return $exists;
}
##############ISOLATE CLIENT DATABASE ACCESS FROM SEQUENCE DATABASE####################
sub get_client_db_info {
	my ( $self, $id ) = @_;
	if ( !$self->{'sql'}->{'client_db_info'} ) {
		$self->{'sql'}->{'client_db_info'} = $self->{'db'}->prepare("SELECT * FROM client_dbases WHERE id=?");
		$logger->info("Statement handle 'client_db_info' prepared.");
	}
	eval { $self->{'sql'}->{'client_db_info'}->execute($id); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'scheme_info' query");
	}
	return $self->{'sql'}->{'client_db_info'}->fetchrow_hashref();
}

sub get_client_db {
	my ( $self, $id ) = @_;
	if ( !$self->{'client_db'}->{$id} ) {
		my $attributes = $self->get_client_db_info($id);
		if ( $attributes->{'dbase_name'} ) {
			my %att = (
				'dbase_name' => $attributes->{'dbase_name'},
				'host'       => $attributes->{'dbase_host'},
				'port'       => $attributes->{'dbase_port'},
				'user'       => $attributes->{'dbase_user'},
				'password'   => $attributes->{'dbase_password'}
			);
			try {
				$attributes->{'db'} = $self->{'dataConnector'}->get_connection( \%att );
			}
			catch BIGSdb::DatabaseConnectionException with {
				$logger->warn("Can not connect to database '$attributes->{'dbase_name'}'");
			};
		}
		$self->{'client_db'}->{$id} = BIGSdb::ClientDB->new(%$attributes);
	}
	return $self->{'client_db'}->{$id};
}
##############SCHEMES##################################################################
sub scheme_exists {
	my ( $self, $id ) = @_;
	return 0 if !BIGSdb::Utils::is_int($id);
	if ( !$self->{'sql'}->{'scheme_exists'} ) {
		$self->{'sql'}->{'scheme_exists'} = $self->{'db'}->prepare("SELECT COUNT(*) FROM schemes WHERE id=?");
		$logger->info("Statement handle 'scheme_exists' prepared.");
	}
	eval { $self->{'sql'}->{'scheme_exists'}->execute($id); };
	my ($exists) = $self->{'sql'}->{'scheme_exists'}->fetchrow_array();
	return $exists;
}

sub get_scheme_info {
	my ( $self, $id ) = @_;
	if ( !$self->{'sql'}->{'scheme_info'} ) {
		$self->{'sql'}->{'scheme_info'} = $self->{'db'}->prepare("SELECT * FROM schemes WHERE id=?");
		$logger->info("Statement handle 'scheme_info' prepared.");
	}
	eval { $self->{'sql'}->{'scheme_info'}->execute($id); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'scheme_info' query");
	}
	return $self->{'sql'}->{'scheme_info'}->fetchrow_hashref();
}

sub get_all_scheme_info {
	#No need to cache as only called once
	my ( $self ) = @_;
	my $sql = $self->{'db'}->prepare("SELECT * FROM schemes");
	eval { $sql->execute; };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error($@);
	}
	return $sql->fetchall_hashref('id');
}

sub get_scheme_loci {

	#if $analyse_pref flag is passed, only the loci for which the user has a analysis preference selected
	#will be returned
	#set $profile_name =1 to substitute profile field value in query
	my ( $self, $id, $use_profile_name, $analyse_pref ) = @_;
	my @field_names = 'locus';
	push @field_names, 'profile_name' if $self->{'system'}->{'dbtype'} eq 'isolates';
	if ( !$self->{'sql'}->{'scheme_loci'} ) {
		$" = ',';
		$self->{'sql'}->{'scheme_loci'} =
		  $self->{'db'}->prepare("SELECT @field_names FROM scheme_members WHERE scheme_id=? ORDER BY field_order,locus");
		$logger->info("Statement handle 'scheme_loci' prepared.");
	}
	eval { $self->{'sql'}->{'scheme_loci'}->execute($id); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'scheme_loci' query $@");
	}
	my @loci;
	while ( my ( $locus, $profile_name ) = $self->{'sql'}->{'scheme_loci'}->fetchrow_array() ) {
		if ($analyse_pref) {
			if (   $self->{'prefs'}->{'analysis_loci'}->{$locus}
				&& $self->{'prefs'}->{'analysis_schemes'}->{$id} )
			{
				if ($use_profile_name) {
					push @loci, $profile_name || $locus;
				} else {
					push @loci, $locus;
				}
			}
		} else {
			if ($use_profile_name) {
				push @loci, $profile_name || $locus;
			} else {
				push @loci, $locus;
			}
		}
	}
	return \@loci;
}

sub get_loci_in_no_scheme {

	#if $analyse_pref flag is passed, only the loci for which the user has an analysis preference selected
	#will be returned
	my ( $self, $analyse_pref ) = @_;
	if ( !$self->{'sql'}->{'no_scheme_loci'} ) {
		$self->{'sql'}->{'no_scheme_loci'} =
		  $self->{'db'}
		  ->prepare("SELECT id FROM loci LEFT JOIN scheme_members ON loci.id = scheme_members.locus where scheme_id is null ORDER BY id");
		$logger->info("Statement handle 'no_scheme_loci' prepared.");
	}
	eval { $self->{'sql'}->{'no_scheme_loci'}->execute(); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'no_scheme_loci' query");
	}
	my @loci;
	while ( my ($locus) = $self->{'sql'}->{'no_scheme_loci'}->fetchrow_array() ) {
		if ($analyse_pref) {
			if ( $self->{'prefs'}->{'analysis_loci'}->{$locus} ) {
				push @loci, $locus;
			}
		} else {
			push @loci, $locus;
		}
	}
	return \@loci;
}

sub are_sequences_displayed_in_scheme {
	my ( $self, $id ) = @_;
	if ( !$self->{'sql'}->{'seq_display'} ) {
		$self->{'sql'}->{'seq_display'} =
		  $self->{'db'}->prepare("SELECT id FROM loci LEFT JOIN scheme_members ON scheme_members.locus = loci.id WHERE scheme_id=?");
		$logger->info("Statement handle 'seq_display' prepared.");
	}
	eval { $self->{'sql'}->{'seq_display'}->execute($id); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'seq_display' query");
	}
	my $value;
	while ( my ($locus) = $self->{'sql'}->{'seq_display'}->fetchrow_array() ) {
		$value++
		  if $self->{'prefs'}->{'isolate_display_loci'}->{$locus} eq 'sequence';
	}
	return $value ? 1 : 0;
}

sub get_scheme_fields {
	my ( $self, $id ) = @_;
	if ( !$self->{'sql'}->{'scheme_fields'} ) {
		$self->{'sql'}->{'scheme_fields'} =
		  $self->{'db'}->prepare("SELECT field FROM scheme_fields WHERE scheme_id=? ORDER BY field_order");
		$logger->info("Statement handle 'scheme_fields' prepared.");
	}
	eval { $self->{'sql'}->{'scheme_fields'}->execute($id); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'scheme_fields' query");
	}
	my @fields;
	while ( my ($field) = $self->{'sql'}->{'scheme_fields'}->fetchrow_array() ) {
		push @fields, $field;
	}
	return \@fields;
}

sub get_all_scheme_fields {
	#No need to cache since this will only be called once.
	my ( $self ) = @_;
	my $sql	 =  $self->{'db'}->prepare("SELECT scheme_id,field FROM scheme_fields");
	eval { $sql->execute; };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error($@);
	}
	my $fields;
	while ( my ($scheme_id,$field) = $sql->fetchrow_array) {
		push @{$fields->{$scheme_id}}, $field;
	}
	return $fields;	
}

sub get_scheme_field_info {
	my ( $self, $id, $field ) = @_;
	if ( !$self->{'sql'}->{'scheme_field_info'} ) {
		$self->{'sql'}->{'scheme_field_info'} = $self->{'db'}->prepare("SELECT * FROM scheme_fields WHERE scheme_id=? AND field=?");
		$logger->info("Statement handle 'scheme_field_info' prepared.");
	}
	eval { $self->{'sql'}->{'scheme_field_info'}->execute( $id, $field ); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'scheme_field_info' query");
	}
	return $self->{'sql'}->{'scheme_field_info'}->fetchrow_hashref();
}

sub get_all_scheme_field_default_prefs {
	#No need to cache since this will only be called once.
	my ( $self ) = @_;
	my $sql = $self->{'db'}->prepare("SELECT scheme_id,field,main_display,isolate_display,query_field,dropdown FROM scheme_fields");
	eval { $sql->execute; };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error($@);
	}
	my $prefs;
	my $data_ref = $sql->fetchall_arrayref;
	my @fields = qw(main_display isolate_display query_field dropdown);
	foreach (@{$data_ref}){
		for my $i (0 .. 3){
			$prefs->{$_->[0]}->{$_->[1]}->{$fields[$i]} = $_->[$i+2];
		}
	}
	return $prefs;
}

sub get_scheme {
	my ( $self, $id ) = @_;
	if ( !$self->{'scheme'}->{$id} ) {
		my $attributes = $self->get_scheme_info($id);
		if ( $attributes->{'dbase_name'} ) {
			my %att = (
				'dbase_name' => $attributes->{'dbase_name'},
				'host'       => $attributes->{'dbase_host'},
				'port'       => $attributes->{'dbase_port'},
				'user'       => $attributes->{'dbase_user'},
				'password'   => $attributes->{'dbase_password'}
			);
			try {
				$attributes->{'db'} = $self->{'dataConnector'}->get_connection( \%att );
			}
			catch BIGSdb::DatabaseConnectionException with {
				$logger->warn("Can not connect to database '$attributes->{'dbase_name'}'");
			};
		}
		$attributes->{'fields'} = $self->get_scheme_fields($id);
		$attributes->{'loci'} = $self->get_scheme_loci( $id, 1 );
		$attributes->{'primary_keys'} =
		  $self->run_list_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key ORDER BY field_order", $id );
		$self->{'scheme'}->{$id} = BIGSdb::Scheme->new(%$attributes);
	}
	return $self->{'scheme'}->{$id};
}

sub is_scheme_field {
	my ( $self, $scheme_id, $field ) = @_;
	my $fields = $self->get_scheme_fields($scheme_id);
	return any { $_ eq $field } @$fields;
}

sub create_temp_scheme_table {
	my ( $self, $id ) = @_;
	my $scheme_db = $self->get_scheme($id)->get_db();
	if ( !$scheme_db ) {
		throw BIGSdb::DatabaseConnectionException("Database does not exist");
	}

	#Test if table already exists
	my ($exists) = $self->run_simple_query( "SELECT COUNT(*) FROM pg_tables WHERE tablename=?", "temp_scheme_$id" );
	if ( $exists->[0] ) {
		$logger->debug("Table already exists");
		return;
	}
	my $start  = gettimeofday();
	my $fields = $self->get_scheme_fields($id);
	my $loci   = $self->get_scheme_loci($id);
	my $create = "CREATE TEMP TABLE temp_scheme_$id (";
	my @table_fields;
	foreach (@$fields) {
		my $type = $self->get_scheme_field_info( $id, $_ )->{'type'};
		push @table_fields, "$_ $type";
	}
	my $qry = "SELECT profile_name FROM scheme_members WHERE locus=? AND scheme_id=?";
	my $sql = $self->{'db'}->prepare($qry);
	my @query_loci;
	foreach (@$loci) {
		my $type = $self->get_locus_info($_)->{'allele_id_format'};
		eval { $sql->execute( $_, $id ); };
		if ($@) {
			$logger->error("Can't execute $qry value: $_");
		}
		my ($profile_name) = $sql->fetchrow_array;
		push @table_fields, "$_ $type";
		push @query_loci, $profile_name || $_;
	}
	$" = ',';
	$create .= "@table_fields";
	$create .= ")";
	$self->{'db'}->do($create);
	my $table = $self->get_scheme_info($id)->{'dbase_table'};
	$qry = "SELECT @$fields,@query_loci FROM $table";
	my $scheme_sql = $scheme_db->prepare($qry);
	eval { $scheme_sql->execute(); };

	if ($@) {
		$logger->warn("Can't execute $qry $@");
		return;
	}
	$" = ",";
	eval { $self->{'db'}->do("COPY temp_scheme_$id(@$fields,@$loci) FROM STDIN"); };
	if ($@) {
		$logger->error("Can't start copying data into temp table");
	}
	$" = "\t";
	my $data = $scheme_sql->fetchall_arrayref;
	foreach (@$data) {
		eval { $self->{'db'}->pg_putcopydata("@$_\n"); };
		if ($@) {
			$logger->warn("Can't put data into temp table @$_");
		}
	}
	eval { $self->{'db'}->pg_putcopyend; };
	if ($@) {
		$logger->error("Can't put data into temp table: $@");
		$self->{'db'}->rollback;
		return -1;
	}
	$" = ',';
	eval { $self->{'db'}->do("CREATE INDEX i_$id ON temp_scheme_$id (@$loci)"); };
	if ($@) {
		$logger->warn("Can't create index");
	}
	foreach (@$fields) {
		$self->{'db'}->do("CREATE INDEX i_$id\_$_ ON temp_scheme_$id ($_)");
		$self->{'db'}->do("UPDATE temp_scheme_$id SET $_ = null WHERE $_='-999'")
		  ;    #Needed as old style profiles database stored null values as '-999'.
	}
	my $end     = gettimeofday();
	my $elapsed = $end - $start;
	$elapsed =~ s/(^\d{1,}\.\d{4}).*$/$1/;
	my $logger_benchmark = get_logger('BIGSdb.Application_Benchmark');
	$logger_benchmark->debug("Time to create temp table for scheme $id: $elapsed seconds");
	return "temp_scheme_$id";
}

sub get_scheme_group_info {
	my ( $self, $locus ) = @_;
	if ( !$self->{'sql'}->{'scheme_group_info'} ) {
		$self->{'sql'}->{'scheme_group_info'} = $self->{'db'}->prepare("SELECT * FROM scheme_groups WHERE id=?");
		$logger->info("Statement handle 'scheme_group_info' prepared.");
	}
	eval { $self->{'sql'}->{'scheme_group_info'}->execute($locus); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'scheme_group_info' query");
	}
	return $self->{'sql'}->{'scheme_group_info'}->fetchrow_hashref();
}
##############LOCI#####################################################################
sub get_loci {
	#options passed as hashref:
	#query_pref: only the loci for which the user has a query field preference selected will be returned
	#seq_defined: only the loci for which a database or a reference sequence has been defined will be returned
	#do_not_order: don't order
	
	#{ 'query_pref' => 1, 'seq_defined' => 1, 'do_not_order' => 1 }

	my ($self, $options) = @_;
	my $defined_clause = $options->{'seq_defined'} ? 'WHERE dbase_name IS NOT NULL OR reference_sequence IS NOT NULL' : '';
	my $order_clause = $options->{'do_not_order'} ? '' : 'order by scheme_members.scheme_id,id';
	my $qry =
"SELECT id,scheme_id from loci left join scheme_members on loci.id = scheme_members.locus $defined_clause $order_clause";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(); };
	if ($@) {
		$logger->error("Can't execute $qry $@");
	}
	my @query_loci;
	my $array_ref = $sql->fetchall_arrayref;
	foreach (@$array_ref) {
		if ($options->{'query_pref'}) {
			if ( $self->{'prefs'}->{'query_field_loci'}->{ $_->[0] }
				&& ( $self->{'prefs'}->{'query_field_schemes'}->{ $_->[1] } or !$_->[1] ) )
			{
				push @query_loci, $_->[0];
			}
		} else {
			push @query_loci, $_->[0];
		}
	}
	return \@query_loci;
}

sub get_locus_list {

	#return sorted list of loci, with labels.  Includes common names.
	my ($self) = @_;
	my $loci = $self->run_list_query_hashref("SELECT id,common_name FROM loci");
	my $cleaned;
	my $display_loci;
	foreach (@$loci) {
		push @$display_loci, $_->{'id'};
		$cleaned->{ $_->{'id'} } = $_->{'id'};
		if ( $_->{'common_name'} ) {
			$cleaned->{ $_->{'id'} } .= " ($_->{'common_name'})";
			push @$display_loci, "cn_$_->{'id'}";
			$cleaned->{"cn_$_->{'id'}"} = "$_->{'common_name'} ($_->{'id'})";
			$cleaned->{"cn_$_->{'id'}"} =~ tr/_/ /;
		}
		$cleaned->{ $_->{'id'} } =~ tr/_/ /;
	}

	#dictionary sort
	@$display_loci = map { $_->[0] }
	  sort { $a->[1] cmp $b->[1] }
	  map {
		my $d = lc( $cleaned->{$_} );
		$d =~ s/[\W_]+//g;
		[ $_, $d ]
	  } @$display_loci;
	return ( $display_loci, $cleaned );
}

sub get_locus_info {
	my ( $self, $locus ) = @_;
	if ( !$self->{'sql'}->{'locus_info'} ) {
		$self->{'sql'}->{'locus_info'} = $self->{'db'}->prepare("SELECT * FROM loci WHERE id=?");
		$logger->info("Statement handle 'locus_info' prepared.");
	}
	eval { $self->{'sql'}->{'locus_info'}->execute($locus); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'locus_info' query");
	}
	return $self->{'sql'}->{'locus_info'}->fetchrow_hashref();
}

sub get_locus {
	my ( $self, $id ) = @_;
	if ( !$self->{'locus'}->{$id} ) {
		my $attributes = $self->get_locus_info($id);
		if ( $attributes->{'dbase_name'} ) {
			my %att = (
				'dbase_name' => $attributes->{'dbase_name'},
				'host'       => $attributes->{'dbase_host'},
				'port'       => $attributes->{'dbase_port'},
				'user'       => $attributes->{'dbase_user'},
				'password'   => $attributes->{'dbase_password'}
			);
			try {
				$attributes->{'db'} = $self->{'dataConnector'}->get_connection( \%att );
			}
			catch BIGSdb::DatabaseConnectionException with {
				$logger->warn("Can not connect to database '$attributes->{'dbase_name'}'");
			};
		}
		$self->{'locus'}->{$id} = BIGSdb::Locus->new(%$attributes);
	}
	return $self->{'locus'}->{$id};
}

sub is_locus {
	my ( $self, $id ) = @_;
	my $loci = $self->get_loci({ 'do_not_order' => 1 });
	return any { $_ eq $id } @$loci;
}
##############ALLELES##################################################################
sub get_allele_designation {
	my ( $self, $isolate_id, $locus ) = @_;
	if ( !$self->{'sql'}->{'allele_designation'} ) {
		$self->{'sql'}->{'allele_designation'} = $self->{'db'}->prepare("SELECT * FROM allele_designations WHERE isolate_id=? AND locus=?");
		$logger->info("Statement handle 'allele_designation' prepared.");
	}
	eval { $self->{'sql'}->{'allele_designation'}->execute( $isolate_id, $locus ); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'allele_designation' query, $@");
	}
	my $allele = $self->{'sql'}->{'allele_designation'}->fetchrow_hashref();
	return $allele;
}

sub get_all_allele_designations {
	my ( $self, $isolate_id ) = @_;
	if ( !$self->{'sql'}->{'all_allele_designation'} ) {
		$self->{'sql'}->{'all_allele_designation'} = $self->{'db'}->prepare("SELECT * FROM allele_designations WHERE isolate_id=?");
		$logger->info("Statement handle 'all_allele_designation' prepared.");
	}
	eval { $self->{'sql'}->{'all_allele_designation'}->execute($isolate_id); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'all_allele_designation' query, $@");
	}
	my $alleles = $self->{'sql'}->{'all_allele_designation'}->fetchall_hashref('locus');
	return $alleles;
}

sub get_all_allele_sequences {
	my ( $self, $isolate_id ) = @_;
	if ( !$self->{'sql'}->{'all_allele_sequences'} ) {
		$self->{'sql'}->{'all_allele_sequences'} =
		  $self->{'db'}->prepare(
"SELECT allele_sequences.* FROM allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id = sequence_bin.id WHERE isolate_id=?"
		  );
		$logger->info("Statement handle 'all_allele_sequences' prepared.");
	}
	eval { $self->{'sql'}->{'all_allele_sequences'}->execute($isolate_id); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'all_allele_sequences' query, $@");
	}
	my $sequences = $self->{'sql'}->{'all_allele_sequences'}->fetchall_hashref( [qw(locus seqbin_id start_pos)] );
	return $sequences;
}

sub get_all_sequence_flags {
	my ( $self, $isolate_id ) = @_;
	if ( !$self->{'sql'}->{'all_sequence_flags'} ) {
		$self->{'sql'}->{'all_sequence_flags'} =
		  $self->{'db'}->prepare(
"SELECT sequence_flags.* FROM sequence_flags LEFT JOIN sequence_bin ON sequence_flags.seqbin_id = sequence_bin.id WHERE isolate_id=?"
		  );
		$logger->info("Statement handle 'all_sequence_flags' prepared.");
	}
	eval { $self->{'sql'}->{'all_sequence_flags'}->execute($isolate_id); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'all_sequence_flags' query, $@");
	}
	my $flags = $self->{'sql'}->{'all_sequence_flags'}->fetchall_hashref( [qw(locus seqbin_id start_pos flag)] );
	return $flags;
}

sub get_allele_id {

	#quicker than get_allele_designation if you only want the allele_id field
	my ( $self, $isolate_id, $locus ) = @_;
	if ( !$self->{'sql'}->{'allele_id'} ) {
		$self->{'sql'}->{'allele_id'} = $self->{'db'}->prepare("SELECT allele_id FROM allele_designations WHERE isolate_id=? AND locus=?");
		$logger->info("Statement handle 'allele_designation' prepared.");
	}
	eval { $self->{'sql'}->{'allele_id'}->execute( $isolate_id, $locus ); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'allele_id' query, $@");
	}
	my ($allele_id) = $self->{'sql'}->{'allele_id'}->fetchrow_array();
	return $allele_id;
}

sub get_all_allele_ids {
	my ( $self, $isolate_id ) = @_;
	my %allele_ids;
	if ( !$self->{'sql'}->{'all_allele_ids'} ) {
		$self->{'sql'}->{'all_allele_ids'} = $self->{'db'}->prepare("SELECT locus,allele_id FROM allele_designations WHERE isolate_id=?");
		$logger->info("Statement handle 'all_allele_ids' prepared.");
	}
	eval { $self->{'sql'}->{'all_allele_ids'}->execute($isolate_id); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'all_allele_ids' query");
	}
	while ( my ( $locus, $allele_id ) = $self->{'sql'}->{'all_allele_ids'}->fetchrow_array() ) {
		$allele_ids{$locus} = $allele_id;
	}
	return \%allele_ids;
}

sub get_pending_allele_designations {
	my ( $self, $isolate_id, $locus ) = @_;
	if ( !$self->{'sql'}->{'pending_allele_designation'} ) {
		$self->{'sql'}->{'pending_allele_designation'} =
		  $self->{'db'}->prepare("SELECT * FROM pending_allele_designations WHERE isolate_id=? AND locus=? ORDER BY datestamp");
		$logger->info("Statement handle 'pending_allele_designation' prepared.");
	}
	eval { $self->{'sql'}->{'pending_allele_designation'}->execute( $isolate_id, $locus ); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'pending_allele_designation' query");
	}
	my @designations;
	while ( my $allele = $self->{'sql'}->{'pending_allele_designation'}->fetchrow_hashref() ) {
		push @designations, $allele;
	}
	return \@designations;
}

sub get_allele_sequence {
	my ( $self, $isolate_id, $locus ) = @_;
	if ( !$self->{'sql'}->{'allele_sequence'} ) {
		$self->{'sql'}->{'allele_sequence'} =
		  $self->{'db'}->prepare(
"SELECT allele_sequences.* FROM allele_sequences LEFT JOIN sequence_bin ON allele_sequences.seqbin_id = sequence_bin.id WHERE isolate_id=? AND locus=? ORDER BY complete desc"
		  );
		$logger->info("Statement handle 'allele_sequence' prepared.");
	}
	eval { $self->{'sql'}->{'allele_sequence'}->execute( $isolate_id, $locus ); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'allele_sequence' query");
	}
	my @allele_sequences;
	while ( my $allele_sequence = $self->{'sql'}->{'allele_sequence'}->fetchrow_hashref() ) {
		push @allele_sequences, $allele_sequence;
	}
	return \@allele_sequences;
}

sub sequences_exist {

	#used for profile/sequence definitions databases
	my ( $self, $locus ) = @_;
	if ( !$self->{'sql'}->{'sequences_exist'} ) {
		$self->{'sql'}->{'sequences_exist'} = $self->{'db'}->prepare("SELECT COUNT(*) FROM sequences WHERE locus=?");
		$logger->info("Statement handle 'sequences_exist' prepared.");
	}
	eval { $self->{'sql'}->{'sequences_exist'}->execute($locus); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'sequences_exist' query");
	}
	my ($exists) = $self->{'sql'}->{'sequences_exist'}->fetchrow_array();
	return $exists;
}

sub sequence_exists {

	#used for profile/sequence definitions databases
	my ( $self, $locus, $allele_id ) = @_;
	if ( !$self->{'sql'}->{'sequence_exists'} ) {
		$self->{'sql'}->{'sequence_exists'} = $self->{'db'}->prepare("SELECT COUNT(*) FROM sequences WHERE locus=? AND allele_id=?");
		$logger->info("Statement handle 'sequence_exists' prepared.");
	}
	eval { $self->{'sql'}->{'sequence_exists'}->execute( $locus, $allele_id ); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'sequence_exists' query $@");
	}
	my ($exists) = $self->{'sql'}->{'sequence_exists'}->fetchrow_array();
	return $exists;
}

sub get_profile_allele_designation {
	my ( $self, $scheme_id, $profile_id, $locus ) = @_;
	if ( !$self->{'sql'}->{'profile_allele_designation'} ) {
		$self->{'sql'}->{'profile_allele_designation'} =
		  $self->{'db'}->prepare("SELECT * FROM profile_members WHERE scheme_id=? AND profile_id=? AND locus=?");
		$logger->info("Statement handle 'profile_allele_designation' prepared.");
	}
	eval { $self->{'sql'}->{'profile_allele_designation'}->execute( $scheme_id, $profile_id, $locus ); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'profile_allele_designation' query");
	}
	my $allele = $self->{'sql'}->{'profile_allele_designation'}->fetchrow_hashref();
	return $allele;
}

sub get_sequence {

	#used for profile/sequence definitions databases
	my ( $self, $locus, $allele_id ) = @_;
	if ( !$self->{'sql'}->{'sequence'} ) {
		$self->{'sql'}->{'sequence'} = $self->{'db'}->prepare("SELECT sequence FROM sequences WHERE locus=? AND allele_id=?");
		$logger->info("Statement handle 'sequence' prepared.");
	}
	eval { $self->{'sql'}->{'sequence'}->execute( $locus, $allele_id ); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'sequence' query");
	}
	my ($seq) = $self->{'sql'}->{'sequence'}->fetchrow_array;
	return \$seq;
}

sub is_allowed_to_modify_locus_sequences {

	#used for profile/sequence definitions databases
	my ( $self, $locus, $curator_id ) = @_;
	if ( !$self->{'sql'}->{'allow_locus'} ) {
		$self->{'sql'}->{'allow_locus'} = $self->{'db'}->prepare("SELECT COUNT(*) FROM locus_curators WHERE locus=? AND curator_id=?");
		$logger->info("Statement handle 'allow_locus' prepared.");
	}
	eval { $self->{'sql'}->{'allow_locus'}->execute( $locus, $curator_id ); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Can't execute 'allow_locus' query");
	}
	my ($allowed) = $self->{'sql'}->{'allow_locus'}->fetchrow_array;
	return $allowed;
}

sub get_next_allele_id {

	#used for profile/sequence definitions databases
	#finds the lowest unused id.
	my ( $self, $locus ) = @_;
	if ( !$self->{'sql'}->{'next_allele_id'} ) {
		$self->{'sql'}->{'next_allele_id'} =
		  $self->{'db'}->prepare("SELECT DISTINCT CAST(allele_id AS int) FROM sequences WHERE locus = ? ORDER BY CAST(allele_id AS int)");
		$logger->info("Statement handle 'next_allele_id' prepared.");
	}
	eval { $self->{'sql'}->{'next_allele_id'}->execute($locus) };
	if ($@) {
		$logger->error("Can't execute 'next_allele_id' query $@");
		return;
	}
	my $test = 0;
	my $next = 0;
	my $id   = 0;
	while ( my @data = $self->{'sql'}->{'next_allele_id'}->fetchrow_array() ) {
		if ( $data[0] != 0 ) {
			$test++;
			$id = $data[0];
			if ( $test != $id ) {
				$next = $test;
				$logger->debug("Next id: $next");
				return $next;
			}
		}
	}
	if ( $next == 0 ) {
		$next = $id + 1;
	}
	$logger->debug("Next id: $next");
	return $next;
}
##############REFERENCES###############################################################
sub get_citation_hash {
	my ( $self, $pmid_ref, $options ) = @_;
	my $citation_ref;
	my %att = (
		'dbase_name' => $self->{'config'}->{'refdb'},
		'host'       => $self->{'system'}->{'host'},
		'port'       => $self->{'system'}->{'port'},
		'user'       => $self->{'system'}->{'user'},
		'password'   => $self->{'system'}->{'pass'}
	);
	my $dbr = $self->{'dataConnector'}->get_connection( \%att );
	return $citation_ref if !$self->{'config'}->{'refdb'} || !$dbr;
	my $sqlr  = $dbr->prepare("SELECT year,journal,title,volume,pages FROM refs WHERE pmid=?");
	my $sqlr2 = $dbr->prepare("SELECT surname,initials FROM authors WHERE id=?");
	my $sqlr3 = $dbr->prepare("SELECT author FROM refauthors WHERE pmid=? ORDER BY position");

	foreach (@$pmid_ref) {
		eval { $sqlr->execute($_); };
		if ($@) {
			$logger->error("Can't execute $@");
		}
		eval { $sqlr3->execute($_); };
		if ($@) {
			$logger->error("Can't execute $@");
		}
		my ( $year, $journal, $title, $volume, $pages ) = $sqlr->fetchrow_array();
		my @authors;
		while ( my ($authorid) = $sqlr3->fetchrow_array() ) {
			push @authors, $authorid;
		}
		my ( $author, @author_list );
		if ( $options->{'all_authors'} ) {
			foreach (@authors) {
				eval { $sqlr2->execute($_); };
				if ($@) {
					$logger->error("Can't execute query");
				}
				my ( $surname, $initials ) = $sqlr2->fetchrow_array;
				$author = "$surname $initials";
				push @author_list, $author;
			}
			$"      = ', ';
			$author = "@author_list";
		} else {
			eval { $sqlr2->execute( $authors[0] ); };
			if ($@) {
				$logger->error("Can't execute query");
			}
			my ( $surname, $initials ) = $sqlr2->fetchrow_array();
			$author .= $surname;
			if ( scalar @authors > 1 ) {
				$author .= ' et al.';
			}
		}
		$volume .= ':' if $volume;
		my $citation;
		{
			no warnings 'uninitialized';
			if ( $options->{'formatted'} ) {
				$citation = "$author ($year). $title ";
				if ( $options->{'link_pubmed'} ) {
					$citation .= "<a href=\"http://www.ncbi.nlm.nih.gov/pubmed/$_\">";
				}
				$citation .= "<i>$journal</i> <b>$volume</b>$pages";
				if ( $options->{'link_pubmed'} ) {
					$citation .= "</a>";
				}
			} else {
				$citation = "$author $year $journal $volume$pages";
			}
		}
		if ($author) {
			$citation_ref->{$_} = $citation;
		} else {
			$citation_ref->{$_} .= "Pubmed id#";
			if ( $options->{'link_pubmed'} ) {
				$citation_ref->{$_} .= "<a href=\"http://www.ncbi.nlm.nih.gov/pubmed/$_\">";
			}
			$citation_ref->{$_} .= $_;
			if ( $options->{'link_pubmed'} ) {
				$citation_ref->{$_} .= "</a>";
			}
		}
	}
	$sqlr->finish  if $sqlr;
	$sqlr2->finish if $sqlr2;
	$sqlr3->finish if $sqlr3;
	return $citation_ref;
}
##############SQL######################################################################
sub run_simple_query {

	#runs simple query (single row returned) against current database
	my ( $self, $qry, @values ) = @_;
	$logger->debug("Query: $qry");
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(@values); };
	if ($@) {
		$self->{'db'}->rollback();
		$" = ', ';
		$logger->error("Couldn't execute: $qry values: @values $@");
	} else {
		my $data = $sql->fetchrow_arrayref;
		return $data;
	}
}

sub run_simple_query_hashref {

	#runs simple query (single row returned) against current database
	my ( $self, $qry, @values ) = @_;
	$logger->debug("Query: $qry");
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(@values); };
	if ($@) {
		$self->{'db'}->rollback();
		$" = ', ';
		$logger->error("Couldn't execute: $qry values: @values $@");
	} else {
		my $data = $sql->fetchrow_hashref;
		return $data;
	}
}

sub run_list_query_hashref {

	#runs query against current database (arrayref of hashrefs returned)
	my ( $self, $qry, @values ) = @_;
	$logger->debug("Query: $qry");
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(@values); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Couldn't execute: $qry values: @values $@");
	}
	my @list;
	while ( my $data = $sql->fetchrow_hashref ) {
		push @list, $data;
	}
	return \@list;
}

sub run_list_query {

	#runs query against current database (multiple row of single value returned)
	my ( $self, $qry, @values ) = @_;
	$logger->debug("Query: $qry");
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute(@values); };
	if ($@) {
		$self->{'db'}->rollback();
		$logger->error("Couldn't execute: $qry values: @values $@");
	}
	my @list;
	while ( ( my $data ) = $sql->fetchrow_array() ) {
		if ( defined $data && $data ne '-999' && $data ne '0001-01-01' ) {
			push @list, $data;
		}
	}
	return \@list;
}

sub run_simple_ref_query {

	#runs simple query (single row returned) against ref database
	my ( $self, $qry, @values ) = @_;
	my %att = (
		'dbase_name' => $self->{'config'}->{'refdb'},
		'host'       => $self->{'system'}->{'host'},
		'port'       => $self->{'system'}->{'port'},
		'user'       => $self->{'system'}->{'user'},
		'password'   => $self->{'system'}->{'pass'}
	);
	my $dbr = $self->{'dataConnector'}->get_connection( \%att );
	$logger->debug("Ref query: $qry");
	my $sql = $dbr->prepare($qry);
	eval { $sql->execute(@values); };
	if ($@) {
		$logger->error("Couldn't execute: $qry values: @values $@");
	}
	my $data = $sql->fetchrow_arrayref;
	return $data;
}
##############DATABASE TABLES##########################################################
sub get_table_field_attributes {

	#Returns array ref of attributes for a specific table provided by table-specific helper functions.
	my ( $self, $table ) = @_;
	my $function = "_get_$table\_table_attributes";
	return $self->$function();
}

sub _get_isolate_aliases_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int',  required => 'yes', primary_key => 'yes', foreign_key => 'isolates' },
		{ name => 'alias',      type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'datestamp',  type => 'date', required => 'yes' },
		{ name => 'curator', type => 'int', required => 'yes', dropdown_query => 'yes' }
	];
	return $attributes;
}

sub _get_users_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 'yes', length => 6,  unique         => 'yes', primary_key    => 'yes' },
		{ name => 'user_name',   type => 'text', required => 'yes', length => 10, unique         => 'yes', dropdown_query => 'yes', },
		{ name => 'surname',     type => 'text', required => 'yes', length => 40, dropdown_query => 'yes' },
		{ name => 'first_name',  type => 'text', required => 'yes', length => 40, dropdown_query => 'yes' },
		{ name => 'email',       type => 'text', required => 'yes', length => 50 },
		{ name => 'affiliation', type => 'text', required => 'yes', length => 120 },
		{ name => 'status',       type => 'text', required => 'yes', optlist => 'user;curator;admin', default => 'user' },
		{ name => 'date_entered', type => 'date', required => 'yes' },
		{ name => 'datestamp',    type => 'date', required => 'yes' },
		{ name => 'curator', type => 'int', required => 'yes', dropdown_query => 'yes' }
	];
	return $attributes;
}

sub _get_user_groups_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 'yes', length => 6,  unique => 'yes', primary_key    => 'yes', },
		{ name => 'description', type => 'text', required => 'yes', length => 60, unique => 'yes', dropdown_query => 'yes', },
		{ name => 'datestamp',   type => 'date', required => 'yes' },
		{ name => 'curator', type => 'int', required => 'yes', dropdown_query => 'yes' }
	];
	return $attributes;
}

sub _get_user_group_members_table_attributes {
	my $attributes = [
		{
			name           => 'user_id',
			type           => 'int',
			required       => 'yes',
			foreign_key    => 'users',
			primary_key    => 'yes',
			dropdown_query => 'yes',
			labels         => '|$surname|, |$first_name|'
		},
		{
			name           => 'user_group',
			type           => 'int',
			required       => 'yes',
			foreign_key    => 'user_groups',
			dropdown_query => 'yes',
			labels         => '|$id|) |$description|'
		},
		{ name => 'datestamp', type => 'date', required => 'yes' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' }
	];
	return $attributes;
}

sub _get_user_permissions_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{
			name           => 'user_id',
			type           => 'int',
			required       => 'yes',
			foreign_key    => 'users',
			primary_key    => 'yes',
			dropdown_query => 'yes',
			labels         => '|$surname|, |$first_name|'
		},
		{ name => 'disable_access', type => 'bool', required => 'no', comments => 'disable all access to this user.' },
		{ name => 'modify_users',   type => 'bool', required => 'no', comments => 'allow user to add or modify users.' },
		{
			name     => 'modify_usergroups',
			type     => 'bool',
			required => 'no',
			comments => 'allow user to create or modify user groups and add users to these groups.'
		},
		{ name => 'set_user_passwords', type => 'bool', required => 'no', comments => 'allow user to modify other users\' password.' },
		{
			name     => 'set_user_permissions',
			type     => 'bool',
			required => 'no',
			comments => 'allow user to modify other curators\' permissions.'
		},
		{ name => 'modify_loci',    type => 'bool', required => 'no', comments => 'allow user to add or modify loci.' },
		{ name => 'modify_schemes', type => 'bool', required => 'no', comments => 'allow user to add or modify schemes.' },
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  (
			{ name => 'modify_sequences', type => 'bool', required => 'no', comments => 'allow user to add sequences to the database.' },
			{ name => 'modify_isolates',  type => 'bool', required => 'no', comments => 'allow user to add or modify isolate records.' },
			{
				name     => 'modify_isolates_acl',
				type     => 'bool',
				required => 'no',
				comments => 'allow user to control who accesses isolate records.'
			},
			{ name => 'modify_projects', type => 'bool', required => 'no', comments => 'allow user to add isolates to project groups.' },
			{
				name     => 'modify_composites',
				type     => 'bool',
				required => 'no',
				comments => 'allow user to add or modify composite fields (fields made up of other fields, including scheme fields).'
			},
			{
				name     => 'modify_field_attributes',
				type     => 'bool',
				required => 'no',
				comments => 'allow user to setup or modify secondary attributes for isolate record fields.'
			},
			{
				name     => 'modify_value_attributes',
				type     => 'bool',
				required => 'no',
				comments => 'allow user to add or modify secondary attribute values for isolate record fields.'
			},
			{
				name     => 'modify_probes',
				type     => 'bool',
				required => 'no',
				comments => 'allow user to define PCR or hybridization reactions to filter tag scanning.'
			},			
			{
				name     => 'tag_sequences',
				type     => 'bool',
				required => 'no',
				comments => 'allow user to tag sequences with locus information.'
			},
			{ name => 'designate_alleles', type => 'bool', required => 'no', comments => 'allow user to designate locus allele numbers.' },
			{
				name     => 'sample_management',
				type     => 'bool',
				required => 'no',
				comments => 'allow user to add or modify sample storage location records.'
			}
		  );
	}
	return $attributes;
}

sub _get_loci_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'id', type => 'text', required => 'yes', unique => 'yes', primary_key => 'yes' },
		{ name => 'common_name', type => 'text', tooltip  => 'common name - Name that the locus is commonly known as.' },
		{ name => 'data_type',   type => 'text', required => 'yes', optlist => 'DNA;peptide', default => 'DNA' },
		{
			name     => 'allele_id_format',
			type     => 'text',
			required => 'yes',
			optlist  => 'integer;text',
			default  => 'integer',
			tooltip  => 'allele id format - Format for allele identifiers'
		},
		{ name => 'allele_id_regex', type => 'text', tooltip => 'allele id regex - Regular expression that constrains allele id values.' },
		{ name => 'length',          type => 'int',  tooltip => 'length - Standard or most common length of sequences at this locus.' },
		{
			name     => 'length_varies',
			type     => 'bool',
			required => 'yes',
			default  => 'false',
			tooltip  => 'length varies - Set to true if this locus can have variable length sequences.'
		}
	];
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		push @$attributes,
		  (
			{ name => 'min_length', type => 'int', tooltip => 'minimum length - Shortest length that sequences at this locus can be.' },
			{ name => 'max_length', type => 'int', tooltip => 'maximum length - Longest length that sequences at this locus can be.' }
		  );
	}
	push @$attributes,
	  (
		{ name => 'coding_sequence', type => 'bool', required => 'yes', default => 'true' },
		{
			name    => 'orf',
			type    => 'int',
			optlist => '1;2;3;4;5;6',
			tooltip => 'open reading frame - This is used for certain analyses that require translation.'
		},
		{
			name    => 'genome_position',
			type    => 'int',
			length  => 10,
			tooltip => 'genome position - starting position in reference genome.  This is used to order concatenated output functions.'
		}
	  );
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  (
			{
				name   => 'reference_sequence',
				type   => 'text',
				length => 30000,
				tooltip =>
				  'reference_sequence - Used by the automated sequence comparison algorithms to identify sequences matching this locus.'
			},
			{
				name => 'pcr_filter',
				type => 'bool',
				tooltip =>
'pcr filter - Set to true to specify that sequences used for tagging are filtered to only include regions that are amplified by in silico PCR reaction.'
			},
			{
				name => 'probe_filter',
				type => 'bool',
				tooltip =>
'probe filter - Set to true to specify that sequences used for tagging are filtered to only include regions within a specified distance of a hybdridization probe.'
			},
			{
				name     => 'dbase_name',
				type     => 'text',
				hide     => 'yes',
				length   => 60,
				comments => 'Name of the database holding allele sequences'
			},
			{
				name     => 'dbase_host',
				type     => 'text',
				hide     => 'yes',
				comments => 'IP address of database host',
				tooltip => 'dbase host - Leave this blank if your database engine is running on the same machine as the webserver software.'
			},
			{
				name     => 'dbase_port',
				type     => 'int',
				hide     => 'yes',
				comments => 'Network port accepting database connections',
				tooltip  => 'dbase port - This can be left blank unless the database engine is listening on a non-standard port.'
			},
			{
				name    => 'dbase_user',
				type    => 'text',
				hide    => 'yes',
				tooltip => 'dbase user - Depending on configuration of the database engine you may be able to leave this blank.'
			},
			{
				name    => 'dbase_password',
				type    => 'text',
				hide    => 'yes',
				tooltip => 'dbase password - Depending on configuration of the database engine you may be able to leave this blank.'
			},
			{
				name     => 'dbase_table',
				type     => 'text',
				hide     => 'yes',
				comments => 'Database table that holds sequence information for this locus'
			},
			{
				name     => 'dbase_id_field',
				type     => 'text',
				hide     => 'yes',
				comments => 'Primary field in sequence database that defines allele, e.g. \'id\''
			},
			{
				name     => 'dbase_id2_field',
				type     => 'text',
				hide     => 'yes',
				comments => 'Secondary field that defines allele, e.g. \'locus\'',
				tooltip =>
'dbase id2 field - Use where the sequence database table requires more than the id to define the allele. This could, for example, be something like \'locus\' where the database table holds the sequences for multiple loci and therefore has a \'locus\' field.  Leave blank if a secondary id field is not used.'
			},
			{
				name     => 'dbase_id2_value',
				type     => 'text',
				hide     => 'yes',
				comments => 'Secondary field value, e.g. locus name',
				tooltip =>
'dbase id2 value - Set the value that the secondary id field must include to select this locus.  This will probably be the name of the locus.  Leave blank if a secondary id field is not used.'
			},
			{
				name     => 'dbase_seq_field',
				type     => 'text',
				hide     => 'yes',
				comments => 'Field in sequence database containing allele sequence'
			},
			{
				name    => 'description_url',
				type    => 'text',
				length  => 120,
				hide    => 'yes',
				tooltip => 'description url - The URL used to hyperlink to locus information in the isolate information page.'
			},
			{
				name   => 'url',
				type   => 'text',
				length => 120,
				hide   => 'yes',
				tooltip =>
'url - The URL used to hyperlink allele numbers in the isolate information page.  Instances of [?] within the URL will be substituted with the allele id.'
			},
			{
				name     => 'isolate_display',
				type     => 'text',
				required => 'yes',
				optlist  => 'allele only;sequence;hide',
				default  => 'allele only',
				tooltip =>
				  'isolate display - Sets how to display the locus in the isolate info page (can be overridden by user preference).'
			},
			{
				name     => 'main_display',
				type     => 'bool',
				required => 'yes',
				default  => 'false',
				tooltip =>
				  'main display - Sets whether to display locus in isolate query results table (can be overridden by user preference).'
			},
			{
				name     => 'query_field',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip  => 'query field - Sets whether this locus can be used in isolate queries (can be overridden by user preference).'
			},
			{
				name     => 'analysis',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip  => 'analysis - Sets whether to include this locus in analysis functions (can be overridden by user preference).'
			}
		  );
	}
	push @$attributes,
	  (
		{ name => 'curator',      type => 'int',  required => 'yes', dropdown_query => 'yes', hide => 'yes' },
		{ name => 'date_entered', type => 'date', required => 'yes', hide           => 'yes' },
		{ name => 'datestamp',    type => 'date', required => 'yes', hide           => 'yes' }
	  );
	return $attributes;
}

sub _get_pcr_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 'yes', unique   => 'yes', primary_key => 'yes' },
		{ name => 'description', type => 'text', length   => '50',  required => 'yes' },
		{ name => 'primer1', type => 'text', length => '128', required => 'yes', regex => '^[ACGTURYSWKMBDHVNacgturyswkmbdhvn ]+$' },
		{ name => 'primer2', type => 'text', length => '128', required => 'yes', regex => '^[ACGTURYSWKMBDHVNacgturyswkmbdhvn ]+$' },
		{ name => 'min_length', type => 'int', comments => 'Minimum length of product to return' },
		{ name => 'max_length', type => 'int', comments => 'Maximum length of product to return' },
		{
			name     => 'max_primer_mismatch',
			type     => 'int',
			optlist  => '0;1;2;3;4;5',
			comments => 'Maximum sequence mismatch per primer',
			tooltip  => 'max primer mismatch - Do not set this too high or the reactions will run slowly.'
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_pcr_locus_table_attributes {
	my $attributes = [
		{
			name           => 'pcr_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'pcr',
			dropdown_query => 'yes',
			labels         => '|$id|) |$description|',
		},
		{ name => 'locus',     type => 'text', required => 'yes', primary_key    => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_probes_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 'yes', unique   => 'yes', primary_key => 'yes' },
		{ name => 'description', type => 'text', length   => '50',  required => 'yes' },
		{ name => 'sequence', type => 'text', length => '2048', required => 'yes', regex => '^[ACGTURYSWKMBDHVNacgturyswkmbdhvn ]+$' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_probe_locus_table_attributes {
	my $attributes = [
		{
			name           => 'probe_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'probes',
			dropdown_query => 'yes',
			labels         => '|$id|) |$description|',
		},
		{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'max_distance', type => 'int', required => 'yes', comments => 'Maximum distance of probe from end of locus' },
		{ name => 'min_alignment', type => 'int',  comments => 'Minimum length of alignment (default: length of probe)' },
		{ name => 'max_mismatch', type => 'int',  comments => 'Maximum sequence mismatch (default: 0)' },
		{ name => 'max_gaps',     type => 'int',  comments => 'Maximum gaps in alignment (default: 0)' },
		{ name => 'curator',      type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',    type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_locus_aliases_table_attributes {
	my $attributes = [
		{ name => 'locus',     type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'alias',     type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'use_alias', type => 'bool', required => 'yes', default     => 'true' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_locus_extended_attributes_table_attributes {
	my $attributes = [
		{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'field', type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'value_format', type => 'text', required => 'yes', optlist => 'integer;text;boolean', default => 'text' },
		{ name => 'value_regex', type => 'text', tooltip => 'value regex - Regular expression that constrains values.' },
		{ name => 'description', type => 'text', length  => 256 },
		{ name => 'option_list', type => 'text', length  => 128, tooltip => 'option list - \'|\' separated list of allowed values.' },
		{ name => 'length', type => 'integer' },
		{
			name     => 'required',
			required => 'yes',
			type     => 'bool',
			default  => 'false',
			tooltip  => 'required - Specifies whether value is required for each sequence.'
		},
		{ name => 'field_order', type => 'int',  length   => 4 },
		{ name => 'curator',     type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',   type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_locus_descriptions_table_attributes {
	my $attributes = [
		{ name => 'locus',       type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'full_name',   type => 'text', length   => 120 },
		{ name => 'product',     type => 'text', length   => 120 },
		{ name => 'description', type => 'text', length   => 2048 },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_client_dbases_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  required => 'yes', primary_key => 'yes' },
		{ name => 'name',        type => 'text', required => 'yes', length      => 30 },
		{ name => 'description', type => 'text', required => 'yes', length      => 256 },
		{
			name     => 'dbase_name',
			type     => 'text',
			required => 'yes',
			hide     => 'yes',
			length   => 60,
			comments => 'Name of the database holding isolate data'
		},
		{
			name     => 'dbase_config_name',
			type     => 'text',
			required => 'yes',
			hide     => 'yes',
			length   => 60,
			comments => 'Name of the database configuration'
		},
		{
			name     => 'dbase_host',
			type     => 'text',
			hide     => 'yes',
			comments => 'IP address of database host',
			tooltip  => 'dbase_host - Leave this blank if your database engine is running on the same machine as the webserver software.'
		},
		{
			name     => 'dbase_port',
			type     => 'int',
			hide     => 'yes',
			comments => 'Network port accepting database connections',
			tooltip  => 'dbase_port - This can be left blank unless the database engine is listening on a non-standard port.'
		},
		{
			name    => 'dbase_user',
			type    => 'text',
			hide    => 'yes',
			tooltip => 'dbase_user - Depending on configuration of the database engine you may be able to leave this blank.'
		},
		{
			name    => 'dbase_password',
			type    => 'text',
			hide    => 'yes',
			tooltip => 'dbase_password - Depending on configuration of the database engine you may be able to leave this blank.'
		},
		{ name => 'url',       type => 'text', length   => 80,    required       => 'no', comments => 'Web URL to database script' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_experiments_table_attributes {
	my $attributes = [
		{ name => 'id',          type => 'int',  length   => 10,    required       => 'yes', primary_key => 'yes' },
		{ name => 'description', type => 'text', required => 'yes', length         => 48,    unique      => 'yes' },
		{ name => 'curator',     type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',   type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_experiment_sequences_table_attributes {
	my $attributes = [
		{
			name           => 'experiment_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'experiments',
			labels         => '|$id|) |$description|',
			dropdown_query => 'yes'
		},
		{ name => 'seqbin_id', type => 'int',  required => 'yes', primary_key    => 'yes', foreign_key => 'sequence_bin' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_client_dbase_loci_table_attributes {
	my $attributes = [
		{
			name           => 'client_dbase_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'client_dbases',
			labels         => '|$id|) |$name|',
			dropdown_query => 'yes'
		},
		{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{
			name     => 'locus_alias',
			type     => 'text',
			required => 'no',
			comments => 'name that this locus is referred by in client database (if different)'
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_client_dbase_schemes_table_attributes {
	my $attributes = [
		{
			name           => 'client_dbase_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'client_dbases',
			labels         => '|$id|) |$name|',
			dropdown_query => 'yes'
		},
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$description|',
			dropdown_query => 'yes'
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_refs_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int',  required => 'yes', primary_key    => 'yes', foreign_key => 'isolates' },
		{ name => 'pubmed_id',  type => 'int',  required => 'yes', primary_key    => 'yes' },
		{ name => 'curator',    type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',  type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_sequence_refs_table_attributes {
	my $attributes = [
		{ name => 'locus',     type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'allele_id', type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'pubmed_id', type => 'int',  required => 'yes', primary_key => 'yes' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_profile_refs_table_attributes {
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$id|) |$description|',
			dropdown_query => 'yes'
		},
		{ name => 'profile_id', type => 'text', required => 'yes', primary_key    => 'yes' },
		{ name => 'pubmed_id',  type => 'int',  required => 'yes', primary_key    => 'yes' },
		{ name => 'curator',    type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',  type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_allele_designations_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int',  required => 'yes', primary_key => 'yes', foreign_key => 'isolates' },
		{ name => 'locus',      type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'allele_id', type => 'text', required => 'yes' },
		{ name => 'sender',    type => 'int',  required => 'yes', foreign_key => 'users', dropdown_query => 'yes' },
		{ name => 'status',    type => 'text', required => 'yes', optlist => 'confirmed;provisional', default => 'confirmed' },
		{ name => 'method',    type => 'text', required => 'yes', optlist => 'manual;automatic', default => 'manual' },
		{ name => 'curator',      type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',    type => 'date', required => 'yes' },
		{ name => 'date_entered', type => 'date', required => 'yes' },
		{ name => 'comments',     type => 'text', length   => 64 }
	];
	return $attributes;
}

sub _get_pending_allele_designations_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int',  required => 'yes', primary_key => 'yes', foreign_key => 'isolates' },
		{ name => 'locus',      type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'allele_id', type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'sender',    type => 'int',  required => 'yes', foreign_key => 'users', dropdown_query => 'yes', primary_key => 'yes' },
		{ name => 'method', type => 'text', required => 'yes', optlist => 'manual;automatic', default => 'manual', primary_key => 'yes' },
		{ name => 'curator',      type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',    type => 'date', required => 'yes' },
		{ name => 'date_entered', type => 'date', required => 'yes' },
		{ name => 'comments',     type => 'text', length   => 64 }
	];
	return $attributes;
}

sub _get_schemes_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{ name => 'id', type => 'int', required => 'yes', unique => 'yes', primary_key => 'yes' },
		{
			name           => 'description',
			type           => 'text',
			required       => 'yes',
			length         => 50,
			dropdown_query => 'yes',
			tooltip        => 'description - Ensure this is short since it is used in table headings and drop-down lists.'
		}
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  (
			{
				name    => 'dbase_name',
				type    => 'text',
				tooltip => 'dbase_name - Name of the database holding profile or field information for this scheme',
				length  => 60
			},
			{
				name    => 'dbase_host',
				type    => 'text',
				tooltip => 'dbase_host - Leave this blank if your database engine is running on the same machine as the webserver software.'
			},
			{
				name    => 'dbase_port',
				type    => 'int',
				tooltip => 'dbase_port - Leave this blank if your database engine is running on the same machine as the webserver software.'
			},
			{
				name    => 'dbase_user',
				type    => 'text',
				hide    => 'yes',
				tooltip => 'dbase_user - Depending on configuration of the database engine you may be able to leave this blank.'
			},
			{
				name    => 'dbase_password',
				type    => 'text',
				hide    => 'yes',
				tooltip => 'dbase_password - Depending on configuration of the database engine you may be able to leave this blank.'
			},
			{
				name    => 'dbase_table',
				type    => 'text',
				tooltip => 'dbase_table - Database table that holds profile or field information for this scheme.'
			},
			{
				name     => 'isolate_display',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip =>
'isolate_display - Sets whether to display the scheme in the isolate info page, setting to false overrides values for individual loci and scheme fields (can be overridden by user preference)'
			},
			{
				name     => 'main_display',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip =>
'main_display - Sets whether to display the scheme in isolate query results table, setting to false overrides values for individual loci and scheme fields (can be overridden by user preference).'
			},
			{
				name     => 'query_field',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip =>
'query_field - Sets whether this scheme can be used in isolate queries, setting to false overrides values for individual loci and scheme fields (can be overridden by user preference).'
			},
			{
				name     => 'query_status',
				type     => 'bool',
				required => 'yes',
				default  => 'false',
				tooltip =>
'query_status - Sets whether a drop-down list box should be used in query interface to select profile completion status for this scheme.'
			},
			{
				name     => 'analysis',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip  => 'analysis - Sets whether to include this scheme in analysis functions (can be overridden by user preference).'
			}
		  );
	}
	push @$attributes,
	  (
		{ name => 'display_order', type => 'int',  tooltip  => 'display_order - order of appearance in interface.' },
		{ name => 'curator',       type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',     type => 'date', required => 'yes' },
		{ name => 'date_entered',  type => 'date', required => 'yes' }
	  );
	return $attributes;
}

sub _get_scheme_members_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$id|) |$description|',
			dropdown_query => 'yes'
		},
		{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' }
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes, { name => 'profile_name', type => 'text', required => 'no' };
	}
	push @$attributes,
	  (
		{ name => 'field_order', type => 'int',  required => 'no' },
		{ name => 'curator',     type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',   type => 'date', required => 'yes' }
	  );
	return $attributes;
}

sub _get_scheme_fields_table_attributes {
	my ($self) = @_;
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$id|) |$description|',
			dropdown_query => 'yes'
		},
		{ name => 'field', type => 'text', required => 'yes', primary_key => 'yes', regex => '^[a-zA-Z][\w-_]*$' },
		{ name => 'type',  type => 'text', required => 'yes', optlist     => 'text;integer;date' },
		{
			name     => 'primary_key',
			type     => 'bool',
			required => 'yes',
			default  => 'false',
			tooltip  => 'primary key - Sets whether this field defines a profile (you can only have one primary key field).'
		},
		{ name => 'description', type => 'text', required => 'no', length => 30, },
		{ name => 'field_order', type => 'int',  required => 'no' }
	];
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  (
			{ name => 'url', type => 'text', required => 'no', length => 120, },
			{
				name     => 'isolate_display',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip =>
				  'isolate display - Sets how to display the locus in the isolate info page (can be overridden by user preference).'
			},
			{
				name     => 'main_display',
				type     => 'bool',
				required => 'yes',
				default  => 'false',
				tooltip =>
				  'main display - Sets whether to display locus in isolate query results table (can be overridden by user preference).'
			},
			{
				name     => 'query_field',
				type     => 'bool',
				required => 'yes',
				default  => 'true',
				tooltip  => 'query field - Sets whether this locus can be used in isolate queries (can be overridden by user preference).'
			},
			{
				name     => 'dropdown',
				type     => 'bool',
				required => 'yes',
				default  => 'false',
				tooltip =>
				  'dropdown - Sets whether to display a dropdown list box in the query interface (can be overridden by user preference).'
			}
		  );
	} else {
		push @$attributes,
		  (
			{
				name     => 'dropdown',
				type     => 'bool',
				required => 'yes',
				default  => 'false',
				tooltip =>
				  'dropdown - Sets whether to display a dropdown list box in the query interface (can be overridden by user preference).'
			}
		  );
		push @$attributes, ( { name => 'value_regex', type => 'text', comments => 'Regular expression that constrains value of field' } );
	}
	push @$attributes,
	  (
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	  );
	return $attributes;
}

sub _get_scheme_groups_table_attributes {
	my $attributes = [
		{ name => 'id', type => 'int', required => 'yes', unique => 'yes', primary_key => 'yes' },
		{
			name           => 'name',
			type           => 'text',
			required       => 'yes',
			length         => 50,
			dropdown_query => 'yes',
			tooltip        => 'name - Ensure this is short since it is used in table headings and drop-down lists.'
		},
		{ name => 'description',   type => 'text', length => 256 },
		{ name => 'display_order', type => 'int' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_scheme_group_scheme_members_table_attributes {
	my $attributes = [
		{
			name           => 'group_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'scheme_groups',
			labels         => '|$id|) |$name|',
			dropdown_query => 'yes'
		},
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$id|) |$description|',
			dropdown_query => 'yes'
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_scheme_group_group_members_table_attributes {
	my $attributes = [
		{
			name           => 'parent_group_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'scheme_groups',
			labels         => '|$id|) |$name|',
			dropdown_query => 'yes'
		},
		{
			name           => 'group_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'scheme_groups',
			labels         => '|$id|) |$name|',
			dropdown_query => 'yes'
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_composite_fields_table_attributes {
	my $attributes = [
		{
			name        => 'id',
			type        => 'text',
			required    => 'yes',
			primary_key => 'yes',
			comments    => 'name of the field as it will appear in the web interface'
		},
		{
			name           => 'position_after',
			type           => 'text',
			required       => 'yes',
			comments       => 'field present in the isolate table',
			dropdown_query => 'yes',
			optlist        => 'isolate_fields'
		},
		{
			name     => 'main_display',
			type     => 'bool',
			required => 'yes',
			default  => 'false',
			comments => 'Sets whether to display field in isolate query results table (can be overridden by user preference).'
		},
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_composite_field_values_table_attributes {
	my $attributes = [
		{
			name           => 'composite_field_id',
			type           => 'text',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'composite_fields',
			dropdown_query => 'yes'
		},
		{ name => 'field_order', type => 'int', required => 'yes', primary_key => 'yes' },
		{ name => 'empty_value', type => 'text' },
		{
			name   => 'regex',
			type   => 'text',
			length => 50,
			tooltip =>
'regex - You can use regular expressions here to do some complex text manipulations on the displayed value.  For example: <br /><br /><b>s/ST-(\S+) complex.*/cc$1/</b><br /><br />will convert something like \'ST-41/44 complex/lineage III\' to \'cc41/44\''
		},
		{ name => 'field',     type => 'text', length   => 40,    required       => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' },
		{ name => 'int',       type => 'text', required => 'yes', dropdown_query => 'yes' }
	];
	return $attributes;
}

sub _get_sequences_table_attributes {
	my $attributes = [
		{ name => 'locus',     type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{ name => 'allele_id', type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'sequence', type => 'text', required => 'yes', length => 32768, user_update => 'no' },
		{
			name        => 'status',
			type        => 'text',
			required    => 'yes',
			optlist     => 'trace checked;trace not checked',
			default     => 'trace checked',
			public_hide => 'yes'
		},
		{ name => 'sender',       type => 'int',  required => 'yes', dropdown_query => 'yes', public_hide => 'yes' },
		{ name => 'curator',      type => 'int',  required => 'yes', dropdown_query => 'yes', public_hide => 'yes' },
		{ name => 'date_entered', type => 'date', required => 'yes', public_hide    => 'yes' },
		{ name => 'datestamp',    type => 'date', required => 'yes', public_hide    => 'yes' }
	];
	return $attributes;
}

sub _get_accession_table_attributes {
	my ($self) = @_;
	my @databanks = DATABANKS;
	my $attributes;
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		push @$attributes,
		  (
			{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
			{ name => 'allele_id', type => 'text', required => 'yes', primary_key => 'yes' },
		  );
	} elsif ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		push @$attributes,
		  ( { name => 'seqbin_id', type => 'int', required => 'yes', primary_key => 'yes', foreign_key => 'sequence_bin' } );
	}
	$" = ';';
	push @$attributes,
	  (
		{ name => 'databank',    type => 'text', required => 'yes', primary_key    => 'yes', optlist => "@databanks" },
		{ name => 'databank_id', type => 'text', required => 'yes', primary_key    => 'yes' },
		{ name => 'curator',     type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',   type => 'date', required => 'yes' },
	  );
	return $attributes;
}

sub _get_allele_sequences_table_attributes {
	my $attributes = [
		{ name => 'seqbin_id', type => 'int',  required => 'yes', primary_key => 'yes', foreign_key => 'sequence_bin' },
		{ name => 'locus',     type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{
			name        => 'start_pos',
			type        => 'int',
			required    => 'yes',
			primary_key => 'yes',
			comments    => 'start position of locus within sequence'
		},
		{ name => 'end_pos', type => 'int', required => 'yes', comments => 'end position of locus within sequence' },
		{
			name     => 'reverse',
			type     => 'bool',
			required => 'yes',
			comments => 'true if sequence is reverse complemented',
			default  => 'false'
		},
		{ name => 'complete', type => 'bool', required => 'yes', comments => 'true if complete locus represented', default => 'true' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' },
	];
	return $attributes;
}

sub _get_profiles_table_attributes {
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$id|) |$description|',
			dropdown_query => 'yes'
		},
		{ name => 'profile_id',   type => 'text', required => 'yes', primary_key    => 'yes' },
		{ name => 'sender',       type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'curator',      type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'date_entered', type => 'date', required => 'yes' },
		{ name => 'datestamp',    type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_scheme_curators_table_attributes {
	my $attributes = [
		{
			name           => 'scheme_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'schemes',
			labels         => '|$id|) |$description|',
			dropdown_query => 'yes'
		},
		{
			name           => 'curator_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'users',
			labels         => '|$surname|, |$first_name| (|$user_name|)',
			dropdown_query => 'yes'
		}
	];
	return $attributes;
}

sub _get_locus_curators_table_attributes {
	my $attributes = [
		{ name => 'locus', type => 'text', required => 'yes', primary_key => 'yes', foreign_key => 'loci', dropdown_query => 'yes' },
		{
			name           => 'curator_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'users',
			labels         => '|$surname|, |$first_name| (|$user_name|)',
			dropdown_query => 'yes'
		},
		{ name => 'hide_public', type => 'bool', comments => 'set to true to not list curator in lists', default => 'false' },
	];
	return $attributes;
}

sub _get_sequence_bin_table_attributes {
	my @methods = SEQ_METHODS;
	my ($self) = @_;
	$" = ';';
	my $attributes = [
		{ name => 'id', type => 'int', required => 'yes', primary_key => 'yes' },
		{
			name           => 'isolate_id',
			type           => 'int',
			required       => 'yes',
			foreign_key    => 'isolates',
			dropdown_query => 'yes',
			labels         => '|$id|) |$' . $self->{'system'}->{'labelfield'} . '|'
		},
		{ name => 'sequence',             type => 'text', required => 'yes', length  => 2048, user_update => 'no' },
		{ name => 'method',               type => 'text', required => 'yes', optlist => "@methods" },
		{ name => 'original_designation', type => 'text', length   => 32 },
		{ name => 'comments',             type => 'text', length   => 64 },
		{ name => 'sender',       type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'curator',      type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'date_entered', type => 'date', required => 'yes' },
		{ name => 'datestamp',    type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_isolate_user_acl_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int', required => 'yes', primary_key => 'yes', foreign_key => 'isolates' },
		{
			name           => 'user_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'users',
			dropdown_query => 'yes',
			labels         => '|$surname|, |$first_name|'
		},
		{ name => 'read',  type => 'bool', required => 'yes', default => 'true' },
		{ name => 'write', type => 'bool', required => 'yes', default => 'false' }
	];
	return $attributes;
}

sub _get_isolate_field_extended_attributes_table_attributes {
	my ($self) = @_;
	my $fields = $self->{'xmlHandler'}->get_field_list;
	my @select_fields;
	foreach my $field (@$fields) {
		next if any { $field eq $_ } qw (id date_entered datestamp sender curator comments);
		push @select_fields, $field;
	}
	$" = ';';
	my $attributes = [
		{ name => 'isolate_field', type => 'text', required => 'yes', primary_key => 'yes', optlist => "@select_fields" },
		{ name => 'attribute',     type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'value_format', type => 'text', required => 'yes', optlist => 'integer;float;text;date', default => 'text' },
		{ name => 'value_regex', type => 'text', tooltip => 'value regex - Regular expression that constrains values.' },
		{ name => 'description', type => 'text', length  => 256 },
		{ name => 'option_list', type => 'text', length  => 128, tooltip => 'option list - \'|\' separated list of allowed values.' },
		{
			name   => 'url',
			type   => 'text',
			length => 120,
			hide   => 'yes',
			tooltip =>
'url - The URL used to hyperlink values in the isolate information page.  Instances of [?] within the URL will be substituted with the value.'
		},
		{ name => 'length',      type => 'integer' },
		{ name => 'field_order', type => 'int', length => 4 },
		{ name => 'curator',     type => 'int', required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_isolate_value_extended_attributes_table_attributes {
	my ($self) = @_;
	my $fields = $self->{'xmlHandler'}->get_field_list;
	my @select_fields;
	foreach my $field (@$fields) {
		next if any { $field eq $_ } qw (id date_entered datestamp sender curator comments);
		push @select_fields, $field;
	}
	my $attributes = $self->run_list_query("SELECT DISTINCT attribute FROM isolate_field_extended_attributes ORDER BY attribute");
	$"          = ';';
	$attributes = [
		{ name => 'isolate_field', type => 'text', required => 'yes', primary_key => 'yes', optlist => "@select_fields" },
		{ name => 'attribute',     type => 'text', required => 'yes', primary_key => 'yes', optlist => "@$attributes" },
		{ name => 'field_value',   type => 'text', required => 'yes', primary_key => 'yes' },
		{ name => 'value',         type => 'text', required => 'yes' },
		{ name => 'curator',   type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp', type => 'date', required => 'yes' }
	];
	return $attributes;
}

sub _get_isolate_usergroup_acl_table_attributes {
	my $attributes = [
		{ name => 'isolate_id', type => 'int', required => 'yes', primary_key => 'yes', foreign_key => 'isolates' },
		{
			name           => 'user_group_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'user_groups',
			dropdown_query => 'yes',
			labels         => '|$id|) |$description|'
		},
		{ name => 'read',  type => 'bool', required => 'yes', default => 'true' },
		{ name => 'write', type => 'bool', required => 'yes', default => 'false' }
	];
	return $attributes;
}

sub _get_projects_table_attributes {
	my $attributes = [
		{ name => 'id', type => 'int', required => 'yes', primary_key => 'yes' },
		{
			name           => 'short_description',
			type           => 'text',
			required       => 'yes',
			length         => 30,
			dropdown_query => 'yes',
			tooltip        => 'description - Ensure this is short since it is used in table headings and drop-down lists.'
		},
		{ name => 'full_description', type => 'text', length   => 256 },
		{ name => 'curator',          type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',        type => 'date', required => 'yes' },
	];
	return $attributes;
}

sub _get_project_members_table_attributes {
	my $attributes = [
		{
			name           => 'project_id',
			type           => 'int',
			required       => 'yes',
			primary_key    => 'yes',
			foreign_key    => 'projects',
			labels         => '|$id|) |$short_description|',
			dropdown_query => 'yes'
		},
		{ name => 'isolate_id', type => 'int',  required => 'yes', primary_key    => 'yes', foreign_key => 'isolates' },
		{ name => 'curator',    type => 'int',  required => 'yes', dropdown_query => 'yes' },
		{ name => 'datestamp',  type => 'date', required => 'yes' },
	];
	return $attributes;
}

sub _get_samples_table_attributes {
	my ($self) = @_;
	my $fields = $self->{'xmlHandler'}->get_sample_field_list;
	if ( !@$fields ) {
		return \%;;
	}
	my $attributes;
	foreach (@$fields) {
		my %field_attributes = $self->{'xmlHandler'}->get_sample_field_attributes($_);
		my @optlist;
		if ( $field_attributes{'optlist'} eq 'yes' ) {
			@optlist = $self->{'xmlHandler'}->get_field_option_list($_);
		}
		$" = ';';
		push @$attributes,
		  (
			{
				name        => $_,
				type        => $field_attributes{'type'},
				required    => $field_attributes{'required'},
				primary_key => ( $_ eq 'isolate_id' || $_ eq 'sample_id' ) ? 'yes' : '',
				foreign_key => $_ eq 'isolate_id' ? 'isolates' : '',
				optlist => "@optlist",
				main_display => $field_attributes{'maindisplay'},
				length       => $field_attributes{'length'} || ( $field_attributes{'type'} eq 'int' ? 6 : 12 )
			}
		  );
	}
	return $attributes;
}

sub is_table {
	my ( $self, $qry ) = @_;
	my @tables = $self->get_tables();
	return any { $_ eq $qry } @tables;
}

sub get_tables {
	my ($self) = @_;
	my @tables;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		@tables =
		  qw(users user_groups user_group_members allele_sequences sequence_bin accession refs allele_designations pending_allele_designations loci
		  locus_aliases schemes scheme_members scheme_fields composite_fields composite_field_values isolate_aliases user_permissions isolate_user_acl
		  isolate_usergroup_acl projects project_members samples experiments experiment_sequences isolate_field_extended_attributes
		  isolate_value_extended_attributes scheme_groups scheme_group_scheme_members scheme_group_group_members pcr pcr_locus probes probe_locus);
		push @tables, $self->{'system'}->{'view'}
		  ? $self->{'system'}->{'view'}
		  : 'isolates';
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		@tables =
		  qw(users user_groups user_group_members sequences sequence_refs accession loci schemes scheme_members scheme_fields profiles
		  profile_refs user_permissions client_dbases client_dbase_loci client_dbase_schemes locus_extended_attributes scheme_curators locus_curators
		  locus_descriptions scheme_groups scheme_group_scheme_members scheme_group_group_members);
	}
	return @tables;
}

sub get_tables_with_curator {

	#TODO update with all appropriate tables
	my ($self) = @_;
	my @tables;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		@tables =
		  qw(users user_groups user_group_members allele_sequences sequence_bin refs allele_designations pending_allele_designations loci schemes scheme_members
		  locus_aliases scheme_fields composite_fields composite_field_values isolate_aliases projects project_members samples experiments experiment_sequences isolate_field_extended_attributes);
		push @tables, $self->{'system'}->{'view'}
		  ? $self->{'system'}->{'view'}
		  : 'isolates';
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		@tables = qw(users user_groups sequences profile_refs sequence_refs accession loci schemes
		  scheme_members scheme_fields scheme_groups scheme_group_scheme_members scheme_group_group_members);
	}
	return @tables;
}

sub get_primary_keys {
	my ( $self, $table ) = @_;
	return 'id' if $table eq $self->{'system'}->{'view'};
	my @keys;
	my $attributes = $self->get_table_field_attributes($table);
	foreach (@$attributes) {
		if ( $_->{'primary_key'} eq 'yes' ) {
			push @keys, $_->{'name'};
		}
	}
	return @keys;
}
1;
