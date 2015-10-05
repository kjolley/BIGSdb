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
package BIGSdb::Datastore;
use strict;
use warnings;
use 5.010;
use List::MoreUtils qw(any uniq);
use Error qw(:try);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Datastore');
use Unicode::Collate;
use File::Path qw(make_path remove_tree);
use BIGSdb::ClientDB;
use BIGSdb::Locus;
use BIGSdb::Scheme;
use BIGSdb::TableAttributes;
use IO::Handle;
use Bio::SeqIO;
use Memoize;
memoize('get_locus_info');

sub new {
	my ( $class, @atr ) = @_;
	my $self = {@atr};
	$self->{'sql'}    = {};
	$self->{'scheme'} = {};
	$self->{'locus'}  = {};
	$self->{'prefs'}  = {};
	bless( $self, $class );
	$logger->info('Datastore set up.');
	return $self;
}

sub update_prefs {
	my ( $self, $prefs ) = @_;
	$self->{'prefs'} = $prefs;
	return;
}

sub DESTROY {
	my ($self) = @_;
	foreach ( keys %{ $self->{'sql'} } ) {
		$self->{'sql'}->{$_}->finish if $self->{'sql'}->{$_};
	}
	foreach ( keys %{ $self->{'scheme'} } ) {
		undef $self->{'scheme'}->{$_};
	}
	foreach ( keys %{ $self->{'locus'} } ) {
		undef $self->{'locus'}->{$_};
	}
	return;
}

sub get_data_connector {
	my ($self) = @_;
	throw BIGSdb::DatabaseConnectionException('Data connector not set up.') if !$self->{'dataConnector'};
	return $self->{'dataConnector'};
}

sub get_user_info {
	my ( $self, $id ) = @_;
	return $self->run_query( 'SELECT first_name,surname,affiliation,email FROM users WHERE id=?',
		$id, { fetch => 'row_hashref', cache => 'get_user_info' } );
}

sub get_user_string {
	my ( $self, $id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $info = $self->get_user_info($id);
	return 'Undefined user' if !$info;
	my $user = '';
	my $use_email =
	  ( $options->{'email'} && $info->{'email'} =~ /@/x )
	  ? 1
	  : 0;    #Not intended to be foolproof check of valid Email but will differentiate 'N/A', ' ', etc.
	$user .= qq(<a href="mailto:$info->{'email'}">) if $use_email;
	$user .= "$info->{'first_name'} "               if $info->{'first_name'};
	$user .= $info->{'surname'}                     if $info->{'surname'};
	$user .= '</a>'                                 if $use_email;
	$info->{'affiliation'} =~ s/^\s*//x;

	if ( $options->{'affiliation'} && $info->{'affiliation'} ) {
		$user .= ", $info->{'affiliation'}";
	}
	return $user;
}

sub get_user_info_from_username {
	my ( $self, $user_name ) = @_;
	return if !defined $user_name;
	return $self->run_query( 'SELECT * FROM users WHERE user_name=?',
		$user_name, { fetch => 'row_hashref', cache => 'get_user_info_from_username' } );
}

sub get_permissions {
	my ( $self, $user_name ) = @_;
	my $permission_list = $self->run_query(
		'SELECT permission FROM curator_permissions LEFT JOIN users ON '
		  . 'curator_permissions.user_id = users.id WHERE user_name=?',
		$user_name,
		{ fetch => 'col_arrayref', cache => 'get_permissions' }
	);
	my %permission_hash = map { $_ => 1 } @$permission_list;
	return \%permission_hash;
}

sub get_isolate_field_values {
	my ( $self, $isolate_id ) = @_;
	return $self->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?",
		$isolate_id, { fetch => 'row_hashref', cache => 'get_isolate_field_values' } );
}

sub get_isolate_aliases {
	my ( $self, $isolate_id ) = @_;
	return $self->run_query( 'SELECT alias FROM isolate_aliases WHERE isolate_id=? ORDER BY alias',
		$isolate_id, { fetch => 'col_arrayref', cache => 'get_isolate_aliases' } );
}

sub get_isolate_refs {
	my ( $self, $isolate_id ) = @_;
	return $self->run_query( 'SELECT pubmed_id FROM refs WHERE isolate_id=? ORDER BY pubmed_id',
		$isolate_id, { fetch => 'col_arrayref', cache => 'get_isolate_refs' } );
}

sub get_composite_value {
	my ( $self, $isolate_id, $composite_field, $isolate_fields_hashref, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $value        = q();
	my $field_values = $self->run_query(
		'SELECT field,empty_value,regex FROM composite_field_values '
		  . 'WHERE composite_field_id=? ORDER BY field_order',
		$composite_field,
		{ fetch => 'all_arrayref', cache => 'get_composite_value' }
	);
	foreach my $field_value_arrayref (@$field_values) {
		my ( $field, $empty_value, $regex ) = @$field_value_arrayref;
		$empty_value //= q();
		if (
			defined $regex
			&& (
				$regex =~ /[^\w\d\-\.\\\/\(\)\+\*\ \$]/x    #reject regex containing any character not in list
				|| $regex =~ /\$\D/x                        #allow only $1, $2 etc. variables
			)
		  )
		{
			$logger->warn(
				    qq(Regex for field '$field' in composite field '$composite_field' contains non-valid characters. )
				  . q(This is potentially dangerous as it may allow somebody to include a command that could be )
				  . qq(executed by the web server daemon.  The regex was '$regex'.  This regex has been disabled.) );
			undef $regex;
		}
		if ( $field =~ /^f_(.+)/x ) {
			my $isolate_field = $1;
			my $text_value    = $isolate_fields_hashref->{ lc($isolate_field) };
			if ($regex) {
				my $expression = "\$text_value =~ $regex";
				eval "$expression";    ## no critic (ProhibitStringyEval)
			}
			$value .= $text_value || $empty_value;
			next;
		}
		if ( $field =~ /^l_(.+)/x ) {
			my $locus = $1;
			my $designations = $self->get_allele_designations( $isolate_id, $locus );
			my @allele_values;
			foreach my $designation (@$designations) {
				my $allele_id = $designation->{'allele_id'};
				$allele_id = '&Delta;' if $allele_id =~ /^del/ix;
				if ($regex) {
					my $expression = "\$allele_id =~ $regex";
					eval "$expression";    ## no critic (ProhibitStringyEval)
				}
				$allele_id = qq(<span class="provisional">$allele_id</span>)
				  if $designation->{'status'} eq 'provisional' && !$options->{'no_format'};
				push @allele_values, $allele_id;
			}
			local $" = ',';
			$value .= "@allele_values" || $empty_value;
			next;
		}
		if ( $field =~ /^s_(\d+)_(.+)/x ) {
			my $scheme_id    = $1;
			my $scheme_field = $2;
			my $scheme_fields->{$scheme_id} = $self->get_scheme_field_values_by_isolate_id( $isolate_id, $scheme_id );
			my @field_values;
			$scheme_field = lc($scheme_field);    # hashref keys returned as lower case from db.
			if ( defined $scheme_fields->{$scheme_id}->{$scheme_field} ) {
				my @unprocessed_values = keys %{ $scheme_fields->{$scheme_id}->{$scheme_field} };
				no warnings 'numeric';
				foreach my $value (
					sort {
						$scheme_fields->{$scheme_id}->{$scheme_field}->{$a}
						  cmp $scheme_fields->{$scheme_id}->{$scheme_field}->{$b}
						  || $a <=> $b
						  || $a cmp $b
					} @unprocessed_values
				  )
				{
					my $provisional = $scheme_fields->{$scheme_id}->{$scheme_field}->{$value} eq 'provisional' ? 1 : 0;
					if ($regex) {
						my $expression = "\$value =~ $regex";
						eval "$expression";    ## no critic (ProhibitStringyEval)
					}
					$value = qq(<span class="provisional">$value</span>)
					  if $provisional && !$options->{'no_format'};
					push @field_values, $value;
				}
			}
			local $" = ',';
			my $field_value = "@field_values";
			$value .=
			  ( $scheme_fields->{$scheme_id}->{$scheme_field} // '' ) ne ''
			  ? $field_value
			  : $empty_value;
			next;
		}
		if ( $field =~ /^t_(.+)/x ) {
			my $text = $1;
			$value .= $text;
		}
	}
	return $value;
}

sub get_ambiguous_loci {
	my ( $self, $scheme_id, $profile_id ) = @_;
	my $profile = $self->get_profile_by_primary_key( $scheme_id, $profile_id, { hashref => 1 } );
	my %ambiguous;
	foreach my $locus ( keys %$profile ) {
		$ambiguous{$locus} = 1 if $profile->{$locus} eq 'N';
	}
	return \%ambiguous;
}

#For use only with isolate databases
sub get_profile_by_primary_key {
	my ( $self, $scheme_id, $profile_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $loci_values;
	try {
		$loci_values = $self->get_scheme($scheme_id)->get_profile_by_primary_keys( [$profile_id] );
	}
	catch BIGSdb::DatabaseConfigurationException with {
		$logger->error('Error retrieving information from remote database - check configuration.');
	};
	return if !defined $loci_values;
	if ( $options->{'hashref'} ) {
		my $loci = $self->get_scheme_loci($scheme_id);
		my %values;
		my $i = 0;
		foreach my $locus (@$loci) {
			$values{$locus} = $loci_values->[$i];
			$i++;
		}
		return \%values;
	} else {
		return $loci_values;
	}
	return;
}

sub get_scheme_field_values_by_designations {

	#$designations is a hashref containing arrayref of allele_designations for each locus
	my ( $self, $scheme_id, $designations, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $values     = {};
	my $loci       = $self->get_scheme_loci($scheme_id);
	my $fields     = $self->get_scheme_fields($scheme_id);
	my $field_data = [];
	if ( ( $self->{'system'}->{'use_temp_scheme_table'} // '' ) eq 'yes' ) {

		#TODO This almost identical to code in Scheme.pm - look at refactoring
		#Import all profiles from seqdef database into indexed scheme table.  Under some circumstances
		#this can be considerably quicker than querying the seqdef scheme view (a few ms compared to
		#>10s if the seqdef database contains multiple schemes with an uneven distribution of a large
		#number of profiles so that the Postgres query planner picks a sequential rather than index scan).
		#
		#This scheme table can also be generated periodically using the update_scheme_cache.pl
		#script to create a persistent cache.  This is particularly useful for large schemes (>10000
		#profiles) but data will only be as fresh as the cache so ensure that the update script
		#is run periodically.
		if ( !$self->{'cache'}->{'scheme_cache'}->{$scheme_id} ) {
			try {
				$self->create_temp_scheme_table($scheme_id);
				$self->{'cache'}->{'scheme_cache'}->{$scheme_id} = 1;
			}
			catch BIGSdb::DatabaseConnectionException with {
				$logger->error('Cannot create temporary table');
			};
		}
		my ( @allele_count, @allele_ids );
		foreach my $locus (@$loci) {
			if ( !defined $designations->{$locus} ) {

				#Define a null designation if one doesn't exist for the purposes of looking up profile.
				#We can't just abort the query because some schemes allow missing loci, but we don't want to match based
				#on an incomplete set of designations.
				push @allele_ids,   '-999';
				push @allele_count, 1;
			} else {
				push @allele_count,
				  scalar
				  @{ $designations->{$locus} };  #We need a different query depending on number of designations at loci.
				foreach my $designation ( @{ $designations->{$locus} } ) {
					push @allele_ids, $designation->{'status'} eq 'ignore' ? '-999' : $designation->{'allele_id'};
				}
			}
		}
		local $" = ',';
		my $query_key = "@allele_count";
		my $qry;
		my $cache_key = "field_values_$scheme_id\_$query_key";
		if ( !$self->{'sql'}->{$cache_key} ) {    #Will be defined by Datastore::run_query
			my $scheme_info = $self->get_scheme_info($scheme_id);
			my @locus_terms;
			my $i = 0;
			foreach my $locus (@$loci) {
				$locus =~ s/'/_PRIME_/gx;
				my @temp_terms;
				push @temp_terms, ("$locus=?") x $allele_count[$i];
				push @temp_terms, "$locus='N'" if $scheme_info->{'allow_missing_loci'};
				local $" = ' OR ';
				push @locus_terms, "(@temp_terms)";
				$i++;
			}
			local $" = ' AND ';
			my $locus_term_string = "@locus_terms";
			local $" = ',';
			$qry = "SELECT @$loci,@$fields FROM temp_scheme_$scheme_id WHERE $locus_term_string";
		}
		$field_data =
		  $self->run_query( $qry, \@allele_ids, { fetch => 'all_arrayref', slice => {}, cache => $cache_key } );
	} else {
		my $scheme = $self->get_scheme($scheme_id);
		$self->_convert_designations_to_profile_names( $scheme_id, $designations );
		{
			try {
				$field_data = $scheme->get_field_values_by_designations($designations);
			}
			catch BIGSdb::DatabaseConfigurationException with {
				$logger->warn("Scheme $scheme_id database is not configured correctly");
			};
		}
	}
	foreach my $data (@$field_data) {
		my $status = 'confirmed';
	  LOCUS: foreach my $locus (@$loci) {
			next if !defined $data->{ lc $locus } || $data->{ lc $locus } eq 'N';
			my $locus_status;
		  DESIGNATION: foreach my $designation ( @{ $designations->{$locus} } ) {
				next DESIGNATION if $designation->{'allele_id'} ne $data->{ lc $locus };
				if ( $designation->{'status'} eq 'confirmed' ) {
					$locus_status = 'confirmed';
					next LOCUS;
				}
			}
			$status = 'provisional';    #Locus is provisional
			last LOCUS;
		}
		foreach my $field (@$fields) {
			$data->{ lc $field } //= '';

			#Allow status to change from provisional -> confirmed but not vice versa
			$values->{ lc $field }->{ $data->{ lc $field } } = $status
			  if ( $values->{ lc $field }->{ $data->{ lc $field } } // '' ) ne 'confirmed';
		}
	}
	return $values;
}

sub _convert_designations_to_profile_names {
	my ( $self, $scheme_id, $designations ) = @_;
	my $data = $self->run_query( 'SELECT locus, profile_name FROM scheme_members WHERE scheme_id=?',
		$scheme_id, { fetch => 'all_arrayref', cache => 'convert_designations_to_profile_names' } );
	foreach (@$data) {
		my ( $locus, $profile_name ) = @$_;
		next if !defined $profile_name;
		next if $locus eq $profile_name;
		$designations->{$profile_name} = delete $designations->{$locus};
	}
	return;
}

sub get_scheme_field_values_by_isolate_id {
	my ( $self, $isolate_id, $scheme_id ) = @_;
	my $designations = $self->get_scheme_allele_designations( $isolate_id, $scheme_id );
	return $self->get_scheme_field_values_by_designations( $scheme_id, $designations );
}

#Return all sample fields except isolate_id
sub get_samples {
	my ( $self, $id ) = @_;
	my $fields = $self->{'xmlHandler'}->get_sample_field_list;
	return [] if !@$fields;
	local $" = ',';
	return $self->run_query( "SELECT @$fields FROM samples WHERE isolate_id=? ORDER BY sample_id",
		$id, { fetch => 'all_arrayref', slice => {} } );
}

#Used for profile/sequence definitions databases
sub profile_exists {
	my ( $self, $scheme_id, $profile_id ) = @_;
	return $self->run_query(
		'SELECT EXISTS (SELECT * FROM profiles WHERE scheme_id=? AND profile_id=?)',
		[ $scheme_id, $profile_id ],
		{ fetch => 'row_array' }
	);
}

#pk_value is optional and can be used to check if updating an existing profile matches another definition.
sub check_new_profile {
	my ( $self, $scheme_id, $designations, $pk_value ) = @_;
	my ( $profile_exists, $msg );
	my $scheme_view = $self->materialized_view_exists($scheme_id) ? "mv_scheme_$scheme_id" : "scheme_$scheme_id";
	my $scheme_info = $self->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $pk          = $scheme_info->{'primary_key'};
	my $qry         = "SELECT $pk FROM $scheme_view WHERE ";
	my $loci        = $self->get_scheme_loci($scheme_id);
	my ( @locus_temp, @values );

	foreach my $locus (@$loci) {
		next
		  if ( $designations->{$locus} // '' ) eq 'N'; #N can be any allele so can not be used to differentiate profiles
		( my $cleaned = $locus ) =~ s/'/_PRIME_/gx;
		push @locus_temp, "($cleaned=? OR $cleaned='N')";
		push @values,     $designations->{$locus};
	}
	local $" = ' AND ';
	$qry .= "(@locus_temp)";
	my $matching_profiles = [];
	if (@locus_temp) {
		my $locus_count = @locus_temp;
		$matching_profiles =
		  $self->run_query( $qry, \@values,
			{ fetch => 'col_arrayref', cache => "check_new_profile::${scheme_id}::$locus_count" } );
		$pk_value //= '';
		if ( @$matching_profiles && !( @$matching_profiles == 1 && $matching_profiles->[0] eq $pk_value ) ) {
			if ( @locus_temp < @$loci ) {
				my $first_match;
				foreach (@$matching_profiles) {
					if ( $_ ne $pk_value ) {
						$first_match = $_;
						last;
					}
				}
				$msg .=
				    q(Profiles containing an arbitrary allele (N) at a particular locus may match profiles )
				  . q(with actual values at that locus and cannot therefore be defined.  This profile matches )
				  . qq($pk-$first_match);
				my $other_matches = @$matching_profiles - 1;
				$other_matches-- if ( any { $pk_value eq $_ } @$matching_profiles );    #if updating don't match to self
				if ($other_matches) {
					$msg .= " and $other_matches other" . ( $other_matches > 1 ? 's' : '' );
				}
				$msg .= q(.);
			} else {
				$msg .= qq(Profile has already been defined as $pk-$matching_profiles->[0].);
			}
			$profile_exists = 1;
		}
	} else {
		$msg .= 'You cannot define a profile with every locus set to be an arbitrary value (N).';
		$profile_exists = 1;
	}
	return { exists => $profile_exists, assigned => $matching_profiles, msg => $msg };
}
##############ISOLATE CLIENT DATABASE ACCESS FROM SEQUENCE DATABASE####################
sub get_client_db_info {
	my ( $self, $id ) = @_;
	return $self->run_query( 'SELECT * FROM client_dbases WHERE id=?',
		$id, { fetch => 'row_hashref', cache => 'get_client_db_info' } );
}

sub get_client_db {
	my ( $self, $id ) = @_;
	if ( !$self->{'client_db'}->{$id} ) {
		my $attributes = $self->get_client_db_info($id);
		if ( $attributes->{'dbase_name'} ) {
			my %att = (
				dbase_name => $attributes->{'dbase_name'},
				host       => $attributes->{'dbase_host'},
				port       => $attributes->{'dbase_port'},
				user       => $attributes->{'dbase_user'},
				password   => $attributes->{'dbase_password'},
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
	return $self->run_query( 'SELECT EXISTS(SELECT * FROM schemes WHERE id=?)', $id, { fetch => 'row_array' } );
}

sub get_scheme_info {
	my ( $self, $scheme_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $scheme_info = $self->run_query( 'SELECT * FROM schemes WHERE id=?',
		$scheme_id, { fetch => 'row_hashref', cache => 'get_scheme_info' } );
	if ( $options->{'set_id'} ) {
		my ($desc) = $self->run_query(
			'SELECT set_name FROM set_schemes WHERE set_id=? AND scheme_id=?',
			[ $options->{'set_id'}, $scheme_id ],
			{ fetch => 'row_array', cache => 'get_scheme_info_set_name' }
		);
		$scheme_info->{'description'} = $desc if defined $desc;
	}
	if ( $options->{'get_pk'} ) {
		my ($pk) = $self->run_query( 'SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key',
			$scheme_id, { fetch => 'row_array', cache => 'get_scheme_info_pk' } );
		$scheme_info->{'primary_key'} = $pk if $pk;
	}
	return $scheme_info;
}

sub get_all_scheme_info {
	my ($self) = @_;
	return $self->run_query( 'SELECT * FROM schemes',
		undef, { fetch => 'all_hashref', key => 'id', cache => 'get_all_scheme_info' } );
}

sub get_scheme_loci {

	#options passed as hashref:
	#analyse_pref: only the loci for which the user has a analysis preference selected will be returned
	#profile_name: to substitute profile field value in query
	#	({profile_name => 1, analysis_pref => 1})
	my ( $self, $scheme_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	if ( !$self->{'cache'}->{'scheme_loci'}->{$scheme_id} ) {
		my $qry =
		    'SELECT locus'
		  . ( $self->{'system'}->{'dbtype'} eq 'isolates' ? ',profile_name' : '' )
		  . ' FROM scheme_members WHERE scheme_id=? ORDER BY field_order,locus';
		$self->{'cache'}->{'scheme_loci'}->{$scheme_id} =
		  $self->run_query( $qry, $scheme_id, { fetch => 'all_arrayref', cache => 'get_scheme_loci' } );
	}
	my @loci;
	foreach ( @{ $self->{'cache'}->{'scheme_loci'}->{$scheme_id} } ) {
		my ( $locus, $profile_name ) = @$_;
		if ( $options->{'analysis_pref'} ) {
			if (   $self->{'prefs'}->{'analysis_loci'}->{$locus}
				&& $self->{'prefs'}->{'analysis_schemes'}->{$scheme_id} )
			{
				if ( $options->{'profile_name'} ) {
					push @loci, $profile_name || $locus;
				} else {
					push @loci, $locus;
				}
			}
		} else {
			if ( $options->{'profile_name'} ) {
				push @loci, $profile_name || $locus;
			} else {
				push @loci, $locus;
			}
		}
	}
	return \@loci;
}

sub get_locus_aliases {
	my ( $self, $locus ) = @_;
	return $self->run_query( 'SELECT alias FROM locus_aliases WHERE use_alias AND locus=? ORDER BY alias',
		$locus, { fetch => 'col_arrayref', cache => 'get_locus_aliases' } );
}

sub get_loci_in_no_scheme {

	#if 'analyse_pref' option is passed, only the loci for which the user has an analysis preference selected
	#will be returned
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $qry;
	if ( $options->{'set_id'} ) {
		$qry =
		    "SELECT locus FROM set_loci WHERE set_id=$options->{'set_id'} AND locus NOT IN (SELECT locus FROM "
		  . "scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$options->{'set_id'})) "
		  . 'ORDER BY locus';
	} else {
		$qry = 'SELECT id FROM loci LEFT JOIN scheme_members ON loci.id='
		  . 'scheme_members.locus where scheme_id is null ORDER BY id';
	}
	my $data = $self->run_query( $qry, undef, { fetch => 'col_arrayref', cache => 'get_loci_in_no_scheme' } );
	return $data if !$options->{'analyse_pref'};
	my @loci;
	foreach my $locus (@$data) {
		push @loci, $locus if $self->{'prefs'}->{'analysis_loci'}->{$locus};
	}
	return \@loci;
}

#NOTE: Data are returned in a cached reference that may be needed more than once.  If calling code needs to
#modify returned values then you MUST make a local copy.
sub get_scheme_fields {
	my ( $self, $scheme_id ) = @_;
	if ( !$self->{'cache'}->{'scheme_fields'}->{$scheme_id} ) {
		$self->{'cache'}->{'scheme_fields'}->{$scheme_id} =
		  $self->run_query( 'SELECT field FROM scheme_fields WHERE scheme_id=? ORDER BY field_order',
			$scheme_id, { fetch => 'col_arrayref', cache => 'get_scheme_fields' } );
	}
	return $self->{'cache'}->{'scheme_fields'}->{$scheme_id};
}

#NOTE: Data are returned in a cached reference that may be needed more than once.  If calling code needs to
#modify returned values then you MUST make a local copy.
sub get_all_scheme_fields {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'all_scheme_fields'} ) {
		my $data = $self->run_query( 'SELECT scheme_id,field FROM scheme_fields ORDER BY field_order',
			undef, { fetch => 'all_arrayref' } );
		foreach (@$data) {
			push @{ $self->{'cache'}->{'all_scheme_fields'}->{ $_->[0] } }, $_->[1];
		}
	}
	return $self->{'cache'}->{'all_scheme_fields'};
}

sub get_scheme_field_info {
	my ( $self, $id, $field ) = @_;
	return $self->run_query(
		'SELECT * FROM scheme_fields WHERE scheme_id=? AND field=?',
		[ $id, $field ],
		{ fetch => 'row_hashref', cache => 'get_scheme_field_info' }
	);
}

#NOTE: Data are returned in a cached reference that may be needed more than once.  If calling code needs to
#modify returned values then you MUST make a local copy.
sub get_all_scheme_field_info {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'all_scheme_field_info'} ) {
		my @fields =
		  $self->{'system'}->{'dbtype'} eq 'isolates'
		  ? qw(main_display isolate_display query_field dropdown url)
		  : 'dropdown';
		local $" = ',';
		my $data =
		  $self->run_query( "SELECT scheme_id,field,@fields FROM scheme_fields", undef, { fetch => 'all_arrayref' } );
		foreach (@$data) {
			for my $i ( 0 .. ( @fields - 1 ) ) {
				$self->{'cache'}->{'all_scheme_field_info'}->{ $_->[0] }->{ $_->[1] }->{ $fields[$i] } = $_->[ $i + 2 ];
			}
		}
	}
	return $self->{'cache'}->{'all_scheme_field_info'};
}

sub get_scheme_list {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $qry;
	if ( $options->{'set_id'} ) {
		if ( $options->{'with_pk'} ) {
			$qry =
			    q(SELECT DISTINCT schemes.id,set_schemes.set_name,schemes.description,schemes.display_order FROM )
			  . q(set_schemes LEFT JOIN schemes ON set_schemes.scheme_id=schemes.id RIGHT JOIN scheme_members ON )
			  . q(schemes.id=scheme_members.scheme_id JOIN scheme_fields ON schemes.id=scheme_fields.scheme_id WHERE )
			  . qq(primary_key AND set_schemes.set_id=$options->{'set_id'} ORDER BY schemes.display_order,)
			  . q(schemes.description);
		} else {
			$qry =
			    q(SELECT DISTINCT schemes.id,set_schemes.set_name,schemes.description,schemes.display_order FROM )
			  . q(set_schemes LEFT JOIN schemes ON set_schemes.scheme_id=schemes.id AND set_schemes.set_id=)
			  . qq($options->{'set_id'} WHERE schemes.id IS NOT NULL ORDER BY schemes.display_order,)
			  . q(schemes.description);
		}
	} else {
		if ( $options->{'with_pk'} ) {
			$qry =
			    q(SELECT DISTINCT schemes.id,schemes.description,schemes.display_order FROM schemes RIGHT JOIN )
			  . q(scheme_members ON schemes.id=scheme_members.scheme_id JOIN scheme_fields ON schemes.id=)
			  . q(scheme_fields.scheme_id WHERE primary_key ORDER BY schemes.display_order,schemes.description);
		} else {
			$qry = q[SELECT id,description,display_order FROM schemes WHERE id IN (SELECT scheme_id FROM ]
			  . q[scheme_members) ORDER BY display_order,description];
		}
	}
	my $list = $self->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	foreach (@$list) {
		$_->{'description'} = $_->{'set_name'} if $_->{'set_name'};
	}
	return $list;
}

sub get_group_list {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $query_clause = $options->{'seq_query'} ? ' WHERE seq_query' : '';
	return $self->run_query( "SELECT id,name,display_order FROM scheme_groups$query_clause ORDER BY display_order,name",
		undef, { fetch => 'all_arrayref', slice => {} } );
}

sub _get_groups_in_group {
	my ( $self, $group_id, $level ) = @_;
	$level //= 0;
	$self->{'groups_in_group_list'} //= [];
	my $child_groups = $self->run_query( 'SELECT group_id FROM scheme_group_group_members WHERE parent_group_id=?',
		$group_id, { fetch => 'col_arrayref', cache => 'get_groups_in_group' } );
	foreach my $child_group (@$child_groups) {
		push @{ $self->{'groups_in_group_list'} }, $child_group;
		my $new_level = $level;
		last if $new_level == 10;    #prevent runaway if child is set as the parent of a parental group
		my $grandchild_groups = $self->_get_groups_in_group( $child_group, ++$new_level );
		push @{ $self->{'groups_in_group_list'} }, @$grandchild_groups;
	}
	my @group_list = @{ $self->{'groups_in_group_list'} };
	undef $self->{'groups_in_group_list'};
	return \@group_list;
}

sub get_schemes_in_group {
	my ( $self, $group_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $set_clause = $options->{'set_id'} ? ' AND scheme_id IN (SELECT scheme_id FROM set_schemes WHERE set_id=?)' : '';
	my @args = ($group_id);
	push @args, $options->{'set_id'} if $options->{'set_id'};
	my $qry = "SELECT scheme_id FROM scheme_group_scheme_members WHERE group_id=?$set_clause "
	  . 'AND scheme_id IN (SELECT scheme_id FROM scheme_members)';
	my $schemes = $self->run_query( $qry, \@args, { fetch => 'col_arrayref', cache => 'get_schemes_in_group' } );
	my $child_groups = $self->_get_groups_in_group($group_id);

	foreach my $child_group (@$child_groups) {
		my @child_args = ($child_group);
		push @child_args, $options->{'set_id'} if $options->{'set_id'};
		my $group_schemes =
		  $self->run_query( $qry, \@child_args, { fetch => 'col_arrayref', cache => 'get_schemes_in_group' } );
		push @$schemes, @$group_schemes;
	}
	return $schemes;
}

sub is_scheme_in_set {
	my ( $self, $scheme_id, $set_id ) = @_;
	return $self->run_query(
		'SELECT EXISTS(SELECT * FROM set_schemes WHERE scheme_id=? AND set_id=?)',
		[ $scheme_id, $set_id ],
		{ fetch => 'row_array', cache => 'is_scheme_in_set' }
	);
}

sub get_set_locus_real_id {
	my ( $self, $locus, $set_id ) = @_;
	my $real_id = $self->run_query(
		'SELECT locus FROM set_loci WHERE set_name=? AND set_id=?',
		[ $locus, $set_id ],
		{ fetch => 'row_array', cache => 'get_set_locus_real_id' }
	);
	return $real_id // $locus;
}

sub is_locus_in_set {
	my ( $self, $locus, $set_id ) = @_;
	return 1
	  if $self->run_query(
		'SELECT EXISTS(SELECT * FROM set_loci WHERE locus=? AND set_id=?)',
		[ $locus, $set_id ],
		{ fetch => 'row_array', cache => 'is_locus_in_set' }
	  );

	#Also check if locus is in schemes within set
	my $schemes = $self->get_scheme_list( { set_id => $set_id } );
	foreach my $scheme (@$schemes) {
		my $locus_list = $self->get_scheme_loci( $scheme->{'id'} );
		return 1 if any { $locus eq $_ } @$locus_list;
	}
	return;
}

sub get_scheme {
	my ( $self, $scheme_id ) = @_;
	if ( !$self->{'scheme'}->{$scheme_id} ) {
		my $attributes = $self->get_scheme_info($scheme_id);
		if ( $attributes->{'dbase_name'} ) {
			my %att = (
				dbase_name         => $attributes->{'dbase_name'},
				host               => $attributes->{'dbase_host'},
				port               => $attributes->{'dbase_port'},
				user               => $attributes->{'dbase_user'},
				password           => $attributes->{'dbase_password'},
				allow_missing_loci => $attributes->{'allow_missing_loci'}
			);
			try {
				$attributes->{'db'} = $self->{'dataConnector'}->get_connection( \%att );
			}
			catch BIGSdb::DatabaseConnectionException with {
				$logger->warn("Can not connect to database '$attributes->{'dbase_name'}'");
			};
		}
		$attributes->{'fields'} = $self->get_scheme_fields($scheme_id);
		$attributes->{'loci'} = $self->get_scheme_loci( $scheme_id, ( { profile_name => 1, analysis_pref => 0 } ) );
		$attributes->{'primary_keys'} =
		  $self->run_query( 'SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key ORDER BY field_order',
			$scheme_id, { fetch => 'col_arrayref', cache => 'get_scheme_primary_keys' } );
		$self->{'scheme'}->{$scheme_id} = BIGSdb::Scheme->new(%$attributes);
	}
	return $self->{'scheme'}->{$scheme_id};
}

sub is_scheme_field {
	my ( $self, $scheme_id, $field ) = @_;
	my $fields = $self->get_scheme_fields($scheme_id);
	return any { $_ eq $field } @$fields;
}

sub create_temp_isolate_scheme_loci_view {
	my ( $self, $scheme_id ) = @_;
	my $view  = $self->{'system'}->{'view'};
	my $table = "temp_$view\_scheme_loci_$scheme_id";

	#Test if view already exists
	return $table
	  if $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );
	my $scheme_info  = $self->get_scheme_info($scheme_id);
	my $loci         = $self->get_scheme_loci($scheme_id);
	my $joined_query = "SELECT $view.id";
	my ( %cleaned, @cleaned, %named );
	foreach my $locus (@$loci) {
		( $cleaned{$locus} = $locus ) =~ s/'/\\'/gx;
		push @cleaned, $cleaned{$locus};
		( $named{$locus} = $locus ) =~ s/'/_PRIME_/gx;
		$joined_query .= ",ARRAY_AGG(DISTINCT(CASE WHEN allele_designations.locus=E'$cleaned{$locus}' "
		  . "THEN allele_designations.allele_id ELSE NULL END)) AS $named{$locus}";
	}

	#Listing scheme loci rather than testing for scheme membership within query is quicker!
	local $" = q(',E');
	$joined_query .= " FROM $view INNER JOIN allele_designations ON $view.id = allele_designations.isolate_id "
	  . "AND status != 'ignore' AND locus IN (E'@cleaned') GROUP BY $view.id";
	eval { $self->{'db'}->do("CREATE TEMP VIEW $table AS $joined_query") };    #View seems quicker than temp table.
	$logger->error($@) if $@;
	return $table;
}

sub create_temp_isolate_scheme_fields_view {
	my ( $self, $scheme_id, $options ) = @_;

	#Create view containing isolate_id and scheme_fields.
	#This view can instead be created as a persistent indexed table using the update_scheme_cache.pl script.
	#This should be done once the scheme size/number of isolates results in a slowdown of queries.
	$options = {} if ref $options ne 'HASH';
	my $view  = $self->{'system'}->{'view'};
	my $table = "temp_$view\_scheme_fields_$scheme_id";
	if ( !$options->{'cache'} ) {
		return $table
		  if $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );

		#Check if cache of whole isolate table exists
		if ( $view ne 'isolates' ) {
			my $full_table = "temp_isolates\_scheme_fields_$scheme_id";
			return $full_table
			  if $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
				$full_table );
		}
	}
	my $scheme_table  = $self->create_temp_scheme_table( $scheme_id, $options );
	my $loci_table    = $self->create_temp_isolate_scheme_loci_view($scheme_id);
	my $scheme_loci   = $self->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->get_scheme_fields($scheme_id);
	my $scheme_info   = $self->get_scheme_info($scheme_id);
	my @temp;
	foreach my $locus (@$scheme_loci) {
		( my $cleaned = $locus ) =~ s/'/\\'/gx;
		( my $named   = $locus ) =~ s/'/_PRIME_/gx;

		#Use correct cast to ensure that database indexes are used.
		my $locus_info = $self->get_locus_info($locus);
		if ( $scheme_info->{'allow_missing_loci'} ) {
			push @temp, "$scheme_table.$named=ANY($loci_table.$named || 'N'::text)";
		} else {
			if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
				push @temp, "$scheme_table.$named=ANY(CAST($loci_table.$named AS int[]))";
			} else {
				push @temp, "$scheme_table.$named=ANY($loci_table.$named)";
			}
		}
	}
	local $" = ",$scheme_table.";
	s/'/\\'/gx foreach @$scheme_fields;
	my $table_type = 'TEMP VIEW';
	my $rename_table;
	if ( $options->{'cache'} ) {
		$table_type   = 'TABLE';
		$rename_table = $table;
		$table        = $table . '_' . int( rand(99999) );
	}
	my $qry = "CREATE $table_type $table AS SELECT $loci_table.id,$scheme_table.@$scheme_fields "
	  . "FROM $loci_table LEFT JOIN $scheme_table ON ";
	local $" = ' AND ';
	$qry .= "@temp";
	eval { $self->{'db'}->do($qry) };
	$logger->error($@) if $@;
	if ( $options->{'cache'} ) {
		foreach my $field (@$scheme_fields) {
			my $scheme_field_info = $self->get_scheme_field_info( $scheme_id, $field );
			if ( $scheme_field_info->{'type'} eq 'text' ) {
				$self->{'db'}->do("CREATE INDEX i_$table\_$field ON $table (UPPER($field))");
			} else {
				$self->{'db'}->do("CREATE INDEX i_$table\_$field ON $table ($field)");
			}
		}
		$self->{'db'}->do("CREATE INDEX i_$table\_id ON $table (id)");

		#Create new temp table, then drop old and rename the new - this
		#should minimize the time that the table is unavailable.
		eval { $self->{'db'}->do("DROP TABLE IF EXISTS $rename_table; ALTER TABLE $table RENAME TO $rename_table") };
		$logger->error($@) if $@;
		$self->{'db'}->commit;
		$table = $rename_table;
	} else {
		$self->{'scheme_not_cached'} = 1;
	}
	return $table;
}

sub create_temp_scheme_table {
	my ( $self, $id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $scheme_info = $self->get_scheme_info($id);
	my $scheme_db   = $self->get_scheme($id)->get_db;
	if ( !$scheme_db ) {
		$logger->error("No scheme database for scheme $id");
		throw BIGSdb::DatabaseConnectionException('Database does not exist');
	}
	my $table = "temp_scheme_$id";

	#Test if table already exists
	if ( !$options->{'cache'} ) {
		return $table
		  if $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );
	}
	my $fields     = $self->get_scheme_fields($id);
	my $loci       = $self->get_scheme_loci($id);
	my $table_type = 'TEMP TABLE';
	my $rename_table;
	if ( $options->{'cache'} ) {
		$table_type   = 'TABLE';
		$rename_table = $table;
		$table        = $table . '_' . int( rand(99999) );
	}
	my $create = "CREATE $table_type $table (";
	my @table_fields;
	foreach (@$fields) {
		my $type = $self->get_scheme_field_info( $id, $_ )->{'type'};
		push @table_fields, "$_ $type";
	}
	my @query_loci;
	foreach my $locus (@$loci) {
		my $type = $scheme_info->{'allow_missing_loci'} ? 'text' : $self->get_locus_info($locus)->{'allele_id_format'};
		my $profile_name = $self->run_query(
			'SELECT profile_name FROM scheme_members WHERE locus=? AND scheme_id=?',
			[ $locus, $id ],
			{ cache => 'create_temp_scheme_table_profile_name' }
		);
		$locus =~ s/'/_PRIME_/gx;
		$profile_name =~ s/'/_PRIME_/gx if defined $profile_name;
		push @table_fields, "$locus $type";
		push @query_loci, $profile_name || $locus;
	}
	local $" = ',';
	$create .= "@table_fields";
	$create .= ')';
	$self->{'db'}->do($create);
	my $seqdef_table = $self->get_scheme_info($id)->{'dbase_table'};
	my $data         = $self->run_query( "SELECT @$fields,@query_loci FROM $seqdef_table",
		undef, { db => $scheme_db, fetch => 'all_arrayref' } );
	eval { $self->{'db'}->do("COPY $table(@$fields,@$loci) FROM STDIN"); };

	if ($@) {
		$logger->error('Cannot start copying data into temp table');
	}
	local $" = "\t";
	foreach (@$data) {
		foreach (@$_) {
			$_ = '\N' if !defined $_ || $_ eq '';
		}
		eval { $self->{'db'}->pg_putcopydata("@$_\n"); };
		if ($@) {
			$logger->warn("Can't put data into temp table @$_");
		}
	}
	eval { $self->{'db'}->pg_putcopyend; };
	if ($@) {
		$logger->error("Can't put data into temp table: $@");
		$self->{'db'}->rollback;
		throw BIGSdb::DatabaseConnectionException('Cannot put data into temp table');
	}
	$self->_create_profile_indices( $table, $id );
	foreach my $field (@$fields) {
		my $field_info = $self->get_scheme_field_info( $id, $field );
		if ( $field_info->{'type'} eq 'integer' ) {
			$self->{'db'}->do("CREATE INDEX i_$table\_$field ON $table ($field)");
		} else {
			$self->{'db'}->do("CREATE INDEX i_$table\_$field ON $table (UPPER($field))");
		}
	}

	#Create new temp table, then drop old and rename the new - this
	#should minimize the time that the table is unavailable.
	if ( $options->{'cache'} ) {
		eval { $self->{'db'}->do("DROP TABLE IF EXISTS $rename_table; ALTER TABLE $table RENAME TO $rename_table") };
		$logger->error($@) if $@;
		$self->{'db'}->commit;
		$table = $rename_table;
	}
	return $table;
}

#Create table containing isolate_id and count of distinct loci
#This can be used to rapidly search by profile completion
#This table can instead be created as a persistent indexed table using the update_scheme_cache.pl script.
#This should be done once the scheme size/number of isolates results in a slowdown of queries.
sub create_temp_scheme_status_table {
	my ( $self, $scheme_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $view  = $self->{'system'}->{'view'};
	my $table = "temp_$view\_scheme_completion_$scheme_id";
	if ( !$options->{'cache'} ) {
		return $table
		  if $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );

		#Check if cache of whole isolate table exists
		if ( $view ne 'isolates' ) {
			my $full_table = "temp_isolates\_scheme_completion_$scheme_id";
			return $full_table
			  if $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
				$full_table );
		}
	}
	my $table_type = 'TEMP TABLE';
	my $rename_table;
	if ( $options->{'cache'} ) {
		$table_type   = 'TABLE';
		$rename_table = $table;
		$table        = $table . '_' . int( rand(99999) );
	}
	my $create_table =
	    qq[CREATE $table_type $table (id INTEGER,locus_count INTEGER NOT NULL,PRIMARY KEY(id));]
	  . qq[INSERT INTO $table SELECT $view.id, COUNT(DISTINCT locus) FROM ]
	  . qq[$view LEFT JOIN allele_designations ON $view.id=allele_designations.isolate_id AND ]
	  . q[locus IN (SELECT locus FROM scheme_members WHERE scheme_id=]
	  . qq[$scheme_id) GROUP BY $view.id;]
	  . qq[CREATE INDEX ON $table (locus_count);];
	eval { $self->{'db'}->do($create_table) };
	$logger->error($@) if $@;

	#If run from cache script, create new temp table, then drop old and rename the new -
	#this should minimize the time that the table is unavailable.
	if ( $options->{'cache'} ) {
		eval { $self->{'db'}->do("DROP TABLE IF EXISTS $rename_table; ALTER TABLE $table RENAME TO $rename_table") };
		$logger->error($@) if $@;
		$self->{'db'}->commit;
		$table = $rename_table;
	}
	return $table;
}

#This should only be used to create a table of user entered values.
#The table name is hard-coded.
sub create_temp_list_table {
	my ( $self, $datatype, $list_file ) = @_;
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$list_file";
	open( my $fh, '<:encoding(utf8)', $full_path ) || $logger->error("Can't open $full_path for reading");
	eval {
		$self->{'db'}->do("CREATE TEMP TABLE temp_list (value $datatype)");
		$self->{'db'}->do('COPY temp_list FROM STDIN');
		while ( my $value = <$fh> ) {
			chomp $value;
			$self->{'db'}->pg_putcopydata("$value\n");
		}
		$self->{'db'}->pg_putcopyend;
	};
	if ($@) {
		$logger->error("Can't put data into temp table: $@");
		$self->{'db'}->rollback;
		throw BIGSdb::DatabaseConnectionException('Cannot put data into temp table');
	}
	close $fh;
	return;
}

sub create_temp_list_table_from_array {
	my ( $self, $datatype, $list, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $table = $options->{'table'} // ( 'temp_list' . int( rand(99999999) ) );
	eval {
		$self->{'db'}->do("CREATE TEMP TABLE $table (value $datatype)");
		$self->{'db'}->do("COPY $table FROM STDIN");
		foreach (@$list) {
			$self->{'db'}->pg_putcopydata("$_\n");
		}
		$self->{'db'}->pg_putcopyend;
	};
	if ($@) {
		$logger->error("Can't put data into temp table: $@");
		$self->{'db'}->rollback;
		throw BIGSdb::DatabaseConnectionException('Cannot put data into temp table');
	}
	return $table;
}

sub _create_profile_indices {
	my ( $self, $table, $scheme_id ) = @_;
	my $loci = $self->get_scheme_loci($scheme_id);

	#We don't need to index every field.  The first three will do.
	my $i = 0;
	foreach my $locus (@$loci) {
		$i++;
		$locus =~ s/'/_PRIME_/gx;
		eval { $self->{'db'}->do("CREATE INDEX i_$table\_$locus ON $table ($locus)"); };
		$logger->warn("Can't create index $@") if $@;
		last if $i == 3;
	}
	return;
}

sub get_scheme_group_info {
	my ( $self, $group_id ) = @_;
	return $self->run_query( 'SELECT * FROM scheme_groups WHERE id=?',
		$group_id, { fetch => 'row_hashref', cache => 'get_scheme_group_info' } );
}
##############LOCI#####################################################################
#options passed as hashref:
#query_pref: only the loci for which the user has a query field preference selected will be returned
#analysis_pref: only the loci for which the user has an analysis preference selected will be returned
#seq_defined: only the loci for which a database or a reference sequence has been defined will be returned
#do_not_order: don't order
#{ query_pref => 1, analysis_pref => 1, seq_defined => 1, do_not_order => 1 }
sub get_loci {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $defined_clause =
	  $options->{'seq_defined'} ? 'WHERE dbase_name IS NOT NULL OR reference_sequence IS NOT NULL' : '';

	#Need to sort if pref settings are to be checked as we need scheme information
	$options->{'do_not_order'} = 0 if any { $options->{$_} } qw (query_pref analysis_pref);
	my $set_clause = '';
	if ( $options->{'set_id'} ) {
		$set_clause = $defined_clause ? 'AND' : 'WHERE';
		$set_clause .=
		    ' (id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE '
		  . "set_id=$options->{'set_id'})) OR id IN (SELECT locus FROM set_loci WHERE set_id=$options->{'set_id'}))";
	}
	my $qry;
	if ( $options->{'do_not_order'} ) {
		$qry = "SELECT id FROM loci $defined_clause $set_clause";
	} else {
		$qry = 'SELECT id,scheme_id FROM loci LEFT JOIN scheme_members ON loci.id = scheme_members.locus '
		  . "$defined_clause $set_clause ORDER BY scheme_members.scheme_id,scheme_members.field_order,id";
	}
	my @query_loci;
	my $data = $self->run_query( $qry, undef, { fetch => 'all_arrayref' } );
	foreach (@$data) {
		next
		  if $options->{'query_pref'}
		  && ( !$self->{'prefs'}->{'query_field_loci'}->{ $_->[0] }
			|| ( defined $_->[1] && !$self->{'prefs'}->{'query_field_schemes'}->{ $_->[1] } ) );
		next
		  if $options->{'analysis_pref'}
		  && ( !$self->{'prefs'}->{'analysis_loci'}->{ $_->[0] }
			|| ( defined $_->[1] && !$self->{'prefs'}->{'analysis_schemes'}->{ $_->[1] } ) );
		push @query_loci, $_->[0];
	}
	@query_loci = uniq(@query_loci);
	return \@query_loci;
}

sub get_locus_list {

	#return sorted list of loci, with labels.  Includes common names.
	#options passed as hashref:
	#analysis_pref: only the loci for which the user has an analysis preference selected will be returned
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my %only_include;
	if ( $options->{'only_include'} ) {
		%only_include = map { $_ => 1 } @{ $options->{'only_include'} };
	}
	my $qry;
	if ( $options->{'set_id'} ) {
		$qry =
		    'SELECT loci.id,common_name,set_id,set_name,set_common_name FROM loci LEFT JOIN set_loci ON loci.id='
		  . 'set_loci.locus WHERE id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id '
		  . "FROM set_schemes WHERE set_id=$options->{'set_id'})) OR id IN (SELECT locus FROM set_loci WHERE "
		  . "set_id=$options->{'set_id'})";
	} else {
		$qry = 'SELECT id,common_name FROM loci';
	}
	if ( $options->{'locus_curator'} && BIGSdb::Utils::is_int( $options->{'locus_curator'} ) ) {
		$qry .= ( $qry =~ /loci$/x ) ? ' WHERE ' : ' AND ';
		$qry .= "loci.id IN (SELECT locus from locus_curators WHERE curator_id = $options->{'locus_curator'})";
	}
	if ( $options->{'no_extended_attributes'} ) {
		$qry .= ( $qry =~ /loci$/x ) ? ' WHERE ' : ' AND ';
		$qry .= 'loci.id NOT IN (SELECT locus from locus_extended_attributes)';
	}
	my $loci = $self->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	my $cleaned;
	my $display_loci;
	foreach my $locus (@$loci) {
		next if $options->{'analysis_pref'} && !$self->{'prefs'}->{'analysis_loci'}->{ $locus->{'id'} };
		next if $options->{'set_id'}        && $locus->{'set_id'} && $locus->{'set_id'} != $options->{'set_id'};
		next if $options->{'only_include'}  && !$only_include{ $locus->{'id'} };
		push @$display_loci, $locus->{'id'};
		if ( $locus->{'set_name'} ) {
			$cleaned->{ $locus->{'id'} } = $locus->{'set_name'};
			if ( $locus->{'set_common_name'} ) {
				$cleaned->{ $locus->{'id'} } .= " ($locus->{'set_common_name'})";
				if ( !$options->{'no_list_by_common_name'} ) {
					push @$display_loci, "cn_$locus->{'id'}";
					$cleaned->{"cn_$locus->{'id'}"} = "$locus->{'set_common_name'} ($locus->{'set_name'})";
					$cleaned->{"cn_$locus->{'id'}"} =~ tr/_/ /;
				}
			}
		} else {
			$cleaned->{ $locus->{'id'} } = $locus->{'id'};
			if ( $locus->{'common_name'} ) {
				$cleaned->{ $locus->{'id'} } .= " ($locus->{'common_name'})";
				if ( !$options->{'no_list_by_common_name'} ) {
					push @$display_loci, "cn_$locus->{'id'}";
					$cleaned->{"cn_$locus->{'id'}"} = "$locus->{'common_name'} ($locus->{'id'})";
					$cleaned->{"cn_$locus->{'id'}"} =~ tr/_/ /;
				}
			}
		}
	}
	@$display_loci = uniq @$display_loci;

	#dictionary sort http://www.perl.com/pub/2011/08/whats-wrong-with-sort-and-how-to-fix-it.html
	my $collator = Unicode::Collate::->new;
	my $sort_key = {};
	for my $locus (@$display_loci) {
		$sort_key->{$locus} = $collator->getSortKey( $cleaned->{$locus} );
	}
	@$display_loci = sort { $sort_key->{$a} cmp $sort_key->{$b} } @$display_loci;
	return ( $display_loci, $cleaned );
}

sub get_locus_info {
	my ( $self, $locus, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $locus_info =
	  $self->run_query( 'SELECT * FROM loci WHERE id=?', $locus,
		{ fetch => 'row_hashref', cache => 'get_locus_info' } );
	if ( $options->{'set_id'} ) {
		my $set_locus = $self->run_query(
			'SELECT * FROM set_loci WHERE set_id=? AND locus=?',
			[ $options->{'set_id'}, $locus ],
			{ fetch => 'row_hashref', cache => 'get_locus_info_set_loci' }
		);
		foreach (qw(set_name set_common_name formatted_set_name formatted_set_common_name)) {
			$locus_info->{$_} = $set_locus->{$_};
		}
	}
	return $locus_info;
}

sub get_locus {
	my ( $self, $id ) = @_;
	if ( !$self->{'locus'}->{$id} ) {
		my $attributes = $self->get_locus_info($id);
		if ( $attributes->{'dbase_name'} ) {
			my %att = (
				dbase_name => $attributes->{'dbase_name'},
				host       => $attributes->{'dbase_host'},
				port       => $attributes->{'dbase_port'},
				user       => $attributes->{'dbase_user'},
				password   => $attributes->{'dbase_password'}
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

sub finish_with_locus {

	#Free up memory associated with Locus object if we no longer need it.
	my ( $self, $id ) = @_;
	delete $self->{'locus'}->{$id};
	return;
}

sub is_locus {
	my ( $self, $id, $options ) = @_;
	return if !defined $id;
	$options = {} if ref $options ne 'HASH';
	my $key = $options->{'set_id'} // 'All';
	if ( !$self->{'cache'}->{'locus_hash'}->{$key} ) {
		my $loci = $self->get_loci( { do_not_order => 1, set_id => $options->{'set_id'} } );
		$self->{'cache'}->{'locus_hash'}->{$key} = { map { $_ => 1 } @$loci };
	}
	return 1 if $self->{'cache'}->{'locus_hash'}->{$key}->{$id};
	return;
}
##############ALLELES##################################################################
sub get_allele_designations {
	my ( $self, $isolate_id, $locus ) = @_;
	return $self->run_query(
		q{SELECT * FROM allele_designations WHERE (isolate_id,locus)=(?,?) ORDER BY status,}
		  . q{(substring (allele_id, '^[0-9]+'))::int,allele_id},
		[ $isolate_id, $locus ],
		{ fetch => 'all_arrayref', slice => {}, cache => 'get_allele_designations' }
	);
}

sub get_allele_extended_attributes {
	my ( $self, $locus, $allele_id ) = @_;
	my $ext_att = $self->run_query( 'SELECT field FROM locus_extended_attributes WHERE locus=? ORDER BY field_order',
		$locus, { fetch => 'col_arrayref', cache => 'get_allele_extended_attributes_field' } );
	my @values;
	foreach my $field (@$ext_att) {
		my $data = $self->run_query(
			'SELECT field,value FROM sequence_extended_attributes WHERE (locus,field,allele_id)=(?,?,?)',
			[ $locus, $field, $allele_id ],
			{ fetch => 'row_hashref', cache => 'get_allele_extended_attributes_value' }
		);
		push @values, $data if $data;
	}
	return \@values;
}

sub get_all_allele_designations {
	my ( $self, $isolate_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $ignore_clause = $options->{'show_ignored'} ? '' : q( AND status != 'ignore');
	my $data =
	  $self->run_query( "SELECT locus,allele_id,status FROM allele_designations WHERE isolate_id=?$ignore_clause",
		$isolate_id, { fetch => 'all_arrayref', cache => 'get_all_allele_designations' } );
	my $alleles = {};
	foreach my $designation (@$data) {
		$alleles->{ $designation->[0] }->{ $designation->[1] } = $designation->[2];
	}
	return $alleles;
}

sub get_scheme_allele_designations {
	my ( $self, $isolate_id, $scheme_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $ignore_clause = $options->{'show_ignored'} ? q() : q( AND status != 'ignore');
	my $designations;
	if ($scheme_id) {
		my $data = $self->run_query(
			'SELECT * FROM allele_designations WHERE isolate_id=? AND locus IN (SELECT locus FROM scheme_members '
			  . "WHERE scheme_id=?)$ignore_clause ORDER BY status,(substring (allele_id, '^[0-9]+'))::int,allele_id",
			[ $isolate_id, $scheme_id ],
			{ fetch => 'all_arrayref', slice => {}, cache => 'get_scheme_allele_designations_scheme' }
		);
		foreach my $designation (@$data) {
			push @{ $designations->{ $designation->{'locus'} } }, $designation;
		}
	} else {
		my $set_clause =
		  $options->{'set_id'}
		  ? 'SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes '
		  . "WHERE set_id=$options->{'set_id'})"
		  : 'SELECT locus FROM scheme_members';
		my $data = $self->run_query(
			"SELECT * FROM allele_designations WHERE isolate_id=? AND locus NOT IN ($set_clause) "
			  . 'ORDER BY status,date_entered,allele_id',
			$isolate_id,
			{ fetch => 'all_arrayref', slice => {}, cache => 'get_scheme_allele_designations_noscheme' }
		);
		foreach my $designation (@$data) {
			push @{ $designations->{ $designation->{'locus'} } }, $designation;
		}
	}
	return $designations;
}

sub get_all_allele_sequences {
	my ( $self, $isolate_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $keys = $options->{'keys'} // [qw (locus seqbin_id start_pos end_pos)];
	return $self->run_query( 'SELECT allele_sequences.* FROM allele_sequences WHERE isolate_id=?',
		$isolate_id, { fetch => 'all_hashref', key => $keys, cache => 'get_all_allele_sequences' } );
}

sub get_sequence_flags {
	my ( $self, $id ) = @_;
	return $self->run_query( 'SELECT flag FROM sequence_flags WHERE id=?',
		$id, { fetch => 'col_arrayref', cache => 'get_sequence_flags' } );
}

sub get_all_sequence_flags {
	my ( $self, $isolate_id ) = @_;
	return $self->run_query(
		'SELECT sequence_flags.id,sequence_flags.flag FROM sequence_flags RIGHT JOIN allele_sequences '
		  . 'ON sequence_flags.id=allele_sequences.id WHERE isolate_id=?',
		$isolate_id,
		{ fetch => 'all_hashref', key => [qw(id flag)], cache => 'get_all_sequence_flags' }
	);
}

sub get_allele_flags {
	my ( $self, $locus, $allele_id ) = @_;
	return $self->run_query(
		'SELECT flag FROM allele_flags WHERE (locus,allele_id)=(?,?) ORDER BY flag',
		[ $locus, $allele_id ],
		{ fetch => 'col_arrayref', cache => 'get_allele_flags' }
	);
}

sub get_allele_ids {
	my ( $self, $isolate_id, $locus, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $ignore_clause = $options->{'show_ignored'} ? '' : q( AND status != 'ignore');
	my $allele_ids = $self->run_query(
		"SELECT allele_id FROM allele_designations WHERE isolate_id=? AND locus=?$ignore_clause",
		[ $isolate_id, $locus ],
		{ fetch => 'col_arrayref', cache => 'get_allele_ids' }
	);
	$self->{'db'}->commit;    #Stop idle in transaction table lock.
	return $allele_ids;
}

sub get_all_allele_ids {
	my ( $self, $isolate_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $allele_ids = {};
	my $ignore_clause = $options->{'show_ignored'} ? '' : q( AND status != 'ignore');
	my $set_clause =
	  $options->{'set_id'}
	  ? q[AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes ]
	  . qq[WHERE set_id=$options->{'set_id'})) OR locus IN (SELECT locus FROM set_loci WHERE ]
	  . qq[set_id=$options->{'set_id'}))]
	  : q[];
	my $data = $self->run_query(
		qq(SELECT locus,allele_id FROM allele_designations WHERE isolate_id=? $set_clause$ignore_clause),
		$isolate_id, { fetch => 'all_arrayref', cache => 'get_all_allele_ids' } );
	foreach (@$data) {
		my ( $locus, $allele_id ) = @$_;
		push @{ $allele_ids->{$locus} }, $allele_id;
	}
	return $allele_ids;
}

sub get_allele_sequence {
	my ( $self, $isolate_id, $locus ) = @_;
	return $self->run_query(
		'SELECT * FROM allele_sequences WHERE (isolate_id,locus)=(?,?) ORDER BY complete desc',
		[ $isolate_id, $locus ],
		{ fetch => 'all_arrayref', slice => {}, cache => 'get_allele_sequence' }
	);
}

#Marginally quicker than get_allele_sequence if you just want to check presence of tag.
sub allele_sequence_exists {
	my ( $self, $isolate_id, $locus ) = @_;
	return $self->run_query(
		'SELECT EXISTS(SELECT allele_sequences.seqbin_id FROM allele_sequences WHERE (isolate_id,locus)=(?,?))',
		[ $isolate_id, $locus ],
		{ fetch => 'row_array', cache => 'allele_sequence_exists' }
	);
}

#used for profile/sequence definitions databases
sub sequences_exist {
	my ( $self, $locus ) = @_;
	return $self->run_query( 'SELECT EXISTS(SELECT * FROM sequences WHERE locus=?)',
		$locus, { fetch => 'row_array', cache => 'sequences_exist' } );
}

#used for profile/sequence definitions databases
sub sequence_exists {
	my ( $self, $locus, $allele_id ) = @_;
	return $self->run_query(
		'SELECT EXISTS(SELECT * FROM sequences WHERE (locus,allele_id)=(?,?))',
		[ $locus, $allele_id ],
		{ fetch => 'row_array', cache => 'sequence_exists' }
	);
}

sub get_profile_allele_designation {
	my ( $self, $scheme_id, $profile_id, $locus ) = @_;
	return $self->run_query(
		'SELECT * FROM profile_members WHERE (scheme_id,profile_id,locus)=(?,?,?)',
		[ $scheme_id, $profile_id, $locus ],
		{ fetch => 'row_hashref', cache => 'get_profile_allele_designation' }
	);
}

#used for profile/sequence definitions databases
sub get_sequence {
	my ( $self, $locus, $allele_id ) = @_;
	my $seq = $self->run_query(
		'SELECT sequence FROM sequences WHERE (locus,allele_id)=(?,?)',
		[ $locus, $allele_id ],
		{ fetch => 'row_array', cache => 'get_sequence' }
	);
	return \$seq;
}

#used for profile/sequence definitions databases
sub is_allowed_to_modify_locus_sequences {
	my ( $self, $locus, $curator_id ) = @_;
	return $self->run_query(
		'SELECT EXISTS(SELECT * FROM locus_curators WHERE (locus,curator_id)=(?,?))',
		[ $locus, $curator_id ],
		{ fetch => 'row_array', cache => 'is_allowed_to_modify_locus_sequences' }
	);
}

sub is_scheme_curator {
	my ( $self, $scheme_id, $curator_id ) = @_;
	return $self->run_query(
		'SELECT EXISTS(SELECT * FROM scheme_curators WHERE (scheme_id,curator_id)=(?,?))',
		[ $scheme_id, $curator_id ],
		{ cache => 'is_scheme_curator' }
	);
}

#used for profile/sequence definitions databases
#finds the lowest unused id.
sub get_next_allele_id {
	my ( $self, $locus ) = @_;
	my $existing_alleles = $self->run_query(
		q[SELECT CAST(allele_id AS int) FROM sequences WHERE locus=? AND ]
		  . q[allele_id !='N' ORDER BY CAST(allele_id AS int)],
		$locus,
		{ fetch => 'col_arrayref', cache => 'get_next_allele_id' }
	);
	my $test = 0;
	my $next = 0;
	my $id   = 0;
	foreach my $allele_id (@$existing_alleles) {
		if ( $allele_id != 0 ) {
			$test++;
			$id = $allele_id;
			if ( $test != $id ) {
				$next = $test;
				return $next;
			}
		}
	}
	if ( $next == 0 ) {
		$next = $id + 1;
	}
	return $next;
}

sub get_client_data_linked_to_allele {
	my ( $self, $locus, $allele_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $client_field_data = $self->run_query(
		'SELECT client_dbase_id,isolate_field FROM client_dbase_loci_fields WHERE allele_query '
		  . 'AND locus=? ORDER BY client_dbase_id,isolate_field',
		$locus,
		{ fetch => 'all_arrayref' }
	);
	my ( $dl_buffer, $td_buffer );
	my $i = 0;
	foreach my $client_field (@$client_field_data) {
		my $field          = $client_field->[1];
		my $client         = $self->get_client_db( $client_field->[0] );
		my $client_db_desc = $self->get_client_db_info( $client_field->[0] )->{'name'};
		my $proceed        = 1;
		my $field_data;
		try {
			$field_data = $client->get_fields( $field, $locus, $allele_id );
		}
		catch BIGSdb::DatabaseConfigurationException with {
			$logger->error( "Can't extract isolate field '$field' FROM client database, make sure the "
				  . "client_dbase_loci_fields table is correctly configured.  $@" );
			$proceed = 0;
		};
		next if !$proceed;
		next if !@$field_data;
		$dl_buffer .= "<dt>$field</dt>";
		my @values;
		foreach my $data (@$field_data) {
			my $value = $data->{$field};
			if ( any { $field eq $_ } qw (species genus) ) {
				$value = "<i>$value</i>";
			}
			$value .= " [n=$data->{'frequency'}]";
			push @values, $value;
		}
		local $" = @values > 10 ? "<br />\n" : '; ';
		$dl_buffer .= qq(<dd>@values <span class="source">$client_db_desc</span></dd>);
		$td_buffer .= qq(<br />\n) if $i;
		$td_buffer .= qq(<span class="source">$client_db_desc</span> <b>$field:</b> @values);
		$i++;
	}
	$dl_buffer = qq(<dl class="data">\n$dl_buffer\n</dl>) if $dl_buffer;
	if ( $options->{'table_format'} ) {
		return $td_buffer;
	}
	return $dl_buffer;
}

sub _format_list_values {
	my ( $self, $hash_ref ) = @_;
	my $buffer = '';
	if ( keys %$hash_ref ) {
		my $first = 1;
		foreach ( sort keys %$hash_ref ) {
			local $" = ', ';
			$buffer .= '; ' if !$first;
			$buffer .= "$_: @{$hash_ref->{$_}}";
			$first = 0;
		}
	}
	return $buffer;
}

sub get_allele_attributes {
	my ( $self, $locus, $allele_ids ) = @_;
	return [] if ref $allele_ids ne 'ARRAY';
	my $fields = $self->run_query( 'SELECT field FROM locus_extended_attributes WHERE locus=?',
		$locus, { fetch => 'col_arrayref' } );
	my $values;
	return if !@$fields;
	foreach my $field (@$fields) {
		foreach my $allele_id (@$allele_ids) {
			my $value = $self->run_query(
				'SELECT value FROM sequence_extended_attributes WHERE (locus,field,allele_id)=(?,?,?)',
				[ $locus, $field, $allele_id ],
				{ cache => 'get_allele_attributes_value' }
			);
			next if !defined $value || $value eq '';
			push @{ $values->{$field} }, $value;
		}
		if ( ref $values->{$field} eq 'ARRAY' && @{ $values->{$field} } ) {
			my @list = @{ $values->{$field} };
			@list = uniq sort @list;
			@{ $values->{$field} } = @list;
		}
	}
	return $self->_format_list_values($values);
}

#Validate new allele submissions
sub check_new_alleles_fasta {
	my ( $self, $locus, $fasta_ref ) = @_;
	my $locus_info = $self->get_locus_info($locus);
	if ( !$locus_info ) {
		$logger->error("Locus $locus is not defined");
		return;
	}
	open( my $stringfh_in, '<:encoding(utf8)', $fasta_ref ) || $logger->error("Could not open string for reading: $!");
	$stringfh_in->untaint;
	my $seqin = Bio::SeqIO->new( -fh => $stringfh_in, -format => 'fasta' );
	my ( @err, @info, @seqs, %used_ids );
	while ( my $seq_object = $seqin->next_seq ) {
		push @seqs, { seq_id => $seq_object->id, sequence => $seq_object->seq };
		my $seq_id = $seq_object->id;
		if ( $used_ids{$seq_id} ) {
			push @err, qq(Sequence identifier "$seq_id" is used more than once in submission.);
		}
		$used_ids{$seq_id} = 1;
		my $sequence = $seq_object->seq;
		if ( !defined $sequence ) {
			push @err, qq(Sequence identifier "$seq_id" does not have a valid sequence.);
			next;
		}
		$sequence =~ s/[\-\.\s]//gx;
		if ( $locus_info->{'data_type'} eq 'DNA' ) {
			my $diploid = ( $self->{'system'}->{'diploid'} // '' ) eq 'yes' ? 1 : 0;
			if ( !BIGSdb::Utils::is_valid_DNA( $sequence, { diploid => $diploid } ) ) {
				push @err, qq(Sequence "$seq_id" is not a valid unambiguous DNA sequence.);
			}
		} else {
			if ( !BIGSdb::Utils::is_valid_peptide($sequence) ) {
				push @err, qq(Sequence "$seq_id" is not a valid unambiguous peptide sequence.);
			}
		}
		my $seq_length = length $sequence;
		my $units = $locus_info->{'data_type'} eq 'DNA' ? 'bp' : 'residues';
		if ( !$locus_info->{'length_varies'} && $seq_length != $locus_info->{'length'} ) {
			push @err,
			  qq(Sequence "$seq_id" has a length of $seq_length $units while this locus has a )
			  . qq(non-variable length of $locus_info->{'length'} $units.);
		} elsif ( $locus_info->{'min_length'} && $seq_length < $locus_info->{'min_length'} ) {
			push @err, qq(Sequence "$seq_id" has a length of $seq_length $units while this locus )
			  . qq(has a minimum length of $locus_info->{'min_length'} $units.);
		} elsif ( $locus_info->{'max_length'} && $seq_length > $locus_info->{'max_length'} ) {
			push @err, qq(Sequence "$seq_id" has a length of $seq_length $units while this locus )
			  . qq(has a maximum length of $locus_info->{'max_length'} $units.);
		}
		my $existing_allele = $self->run_query(
			'SELECT allele_id FROM sequences WHERE (locus,UPPER(sequence))=(?,UPPER(?))',
			[ $locus, $sequence ],
			{ cache => 'check_new_alleles_fasta' }
		);
		if ($existing_allele) {
			push @err, qq(Sequence "$seq_id" has already been defined as $locus-$existing_allele.);
		}
		if ( $locus_info->{'complete_cds'} && $locus_info->{'data_type'} eq 'DNA' ) {
			my $check = BIGSdb::Utils::is_complete_cds( \$sequence );
			if ( !$check->{'cds'} ) {
				push @info, qq(Sequence "$seq_id" is $check->{'err'});
			}
		}
		if ( !$self->is_sequence_similar_to_others( $locus, \$sequence ) ) {
			push @info,
			  qq(Sequence "$seq_id" is dissimilar (or in reverse orientation compared) to other $locus sequences.);
		}
	}
	close $stringfh_in;
	my $ret = {};
	$ret->{'err'}  = \@err  if @err;
	$ret->{'info'} = \@info if @info;
	$ret->{'seqs'} = \@seqs if @seqs;
	return $ret;
}

#Options are locus, seq_ref, qry_type, num_results, alignment, cache, job
#if parameter cache=1, the previously generated FASTA database will be used.
#The calling function should clean up the temporary files.
sub run_blast {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $locus_info = $self->get_locus_info( $options->{'locus'} );
	my $already_generated = $options->{'job'} ? 1 : 0;
	$options->{'job'} = BIGSdb::Utils::get_random() if !$options->{'job'};
	my $temp_infile  = "$self->{'config'}->{'secure_tmp_dir'}/$options->{'job'}.txt";
	my $temp_outfile = "$self->{'config'}->{'secure_tmp_dir'}/$options->{'job'}\_outfile.txt";
	my $outfile_url  = "$options->{'job'}\_outfile.txt";

	#create fasta index
	my @runs;
	if ( $options->{'locus'} && $options->{'locus'} !~ /SCHEME_\d+/x && $options->{'locus'} !~ /GROUP_\d+/x ) {
		if ( $options->{'locus'} =~ /^((?:(?!\.\.).)*)$/x ) {    #untaint - check for directory traversal
			$options->{'locus'} = $1;
		}
		@runs = ( $options->{'locus'} );
	} else {
		@runs = qw (DNA peptide);
	}
	foreach my $run (@runs) {
		( my $cleaned_run = $run ) =~ s/'/_prime_/gx;
		my $temp_fastafile;
		if ( !$options->{'locus'} ) {
			my $set_id = $options->{'set_id'} // 'all';
			$set_id = 'all' if ( $self->{'system'}->{'sets'} // '' ) ne 'yes';    # 'All loci'
			if ( $run eq 'DNA' && defined $self->{'config'}->{'cache_days'} ) {
				my $cache_age = $self->_get_cache_age($set_id);
				if ( $cache_age > $self->{'config'}->{'cache_days'} ) {
					$self->mark_cache_stale;
				}
			}

			#Create file and BLAST db of all sequences in a cache directory so can be reused.
			$temp_fastafile =
			  "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}/$set_id/$cleaned_run\_fastafile.txt";
			my $stale_flag_file = "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}/$set_id/stale";
			if ( -e $temp_fastafile && !-e $stale_flag_file ) {
				$already_generated = 1;
			} else {
				my $new_path = "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}/$set_id";
				if ( -f $new_path ) {
					$logger->error(
						"Can't create directory $new_path for cache files - a filename exists with this name.");
				} else {
					eval { make_path($new_path) };
					$logger->error($@) if $@;
					unlink $stale_flag_file
					  if $run eq $runs[-1];    #only remove stale flag when creating last BLAST databases
				}
			}
		} else {
			$temp_fastafile = "$self->{'config'}->{'secure_tmp_dir'}/$options->{'job'}\_$cleaned_run\_fastafile.txt";
		}
		if ( !$already_generated ) {
			my ( $qry, $sql );
			if ( $options->{'locus'} && $options->{'locus'} !~ /SCHEME_\d+/x && $options->{'locus'} !~ /GROUP_\d+/x ) {
				$qry = 'SELECT locus,allele_id,sequence from sequences WHERE locus=?';
			} else {
				my $set_id = $options->{'set_id'};
				if ( $options->{'locus'} =~ /SCHEME_(\d+)/x ) {
					my $scheme_id = $1;
					$qry =
					    q[SELECT locus,allele_id,sequence FROM sequences WHERE locus IN (SELECT locus FROM ]
					  . qq[scheme_members WHERE scheme_id=$scheme_id) AND locus IN (SELECT id FROM loci WHERE ]
					  . q[data_type=?) AND allele_id != 'N'];
				} elsif ( $options->{'locus'} =~ /GROUP_(\d+)/x ) {
					my $group_id = $1;
					my $group_schemes = $self->get_schemes_in_group( $group_id, { set_id => $set_id } );
					local $" = ',';
					$qry =
					    q[SELECT locus,allele_id,sequence FROM sequences WHERE locus IN (SELECT locus FROM ]
					  . qq[scheme_members WHERE scheme_id IN (@$group_schemes)) AND locus IN (SELECT id FROM loci ]
					  . q[WHERE data_type=?) AND allele_id != 'N'];
				} else {
					$qry = q[SELECT locus,allele_id,sequence FROM sequences WHERE locus IN (SELECT id FROM loci ]
					  . q[WHERE data_type=?)];
					if ($set_id) {
						$qry .=
						    q[ AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT ]
						  . qq[scheme_id FROM set_schemes WHERE set_id=$set_id)) OR locus IN (SELECT locus FROM ]
						  . qq[set_loci WHERE set_id=$set_id)) AND allele_id != 'N'];
					}
				}
			}
			$sql = $self->{'db'}->prepare($qry);
			eval { $sql->execute($run) };
			$logger->error($@) if $@;
			open( my $fasta_fh, '>', $temp_fastafile ) || $logger->error("Can't open $temp_fastafile for writing");
			my $seqs_ref = $sql->fetchall_arrayref;
			foreach (@$seqs_ref) {
				my ( $returned_locus, $id, $seq ) = @$_;
				next if !length $seq;
				print $fasta_fh ( $options->{'locus'}
					  && $options->{'locus'} !~ /SCHEME_\d+/x
					  && $options->{'locus'} !~ /GROUP_\d+/x )
				  ? ">$id\n$seq\n"
				  : ">$returned_locus:$id\n$seq\n";
			}
			close $fasta_fh;
			if ( !-z $temp_fastafile ) {
				my $dbtype;
				if (   $options->{'locus'}
					&& $options->{'locus'} !~ /SCHEME_\d+/x
					&& $options->{'locus'} !~ /GROUP_\d+/x )
				{
					$dbtype = $locus_info->{'data_type'} eq 'DNA' ? 'nucl' : 'prot';
				} else {
					$dbtype = $run eq 'DNA' ? 'nucl' : 'prot';
				}
				system( "$self->{'config'}->{'blast+_path'}/makeblastdb",
					( -in => $temp_fastafile, -logfile => '/dev/null', -dbtype => $dbtype ) );
			}
		}
		if ( !-z $temp_fastafile ) {

			#create query fasta file
			open( my $infile_fh, '>', $temp_infile ) || $logger->error("Can't open $temp_infile for writing");
			print $infile_fh ">Query\n";
			print $infile_fh "${$options->{'seq_ref'}}\n";
			close $infile_fh;
			my $program;
			if ( $options->{'locus'} && $options->{'locus'} !~ /SCHEME_\d+/x && $options->{'locus'} !~ /GROUP_\d+/x ) {
				if ( $options->{'qry_type'} eq 'DNA' ) {
					$program = $locus_info->{'data_type'} eq 'DNA' ? 'blastn' : 'blastx';
				} else {
					$program = $locus_info->{'data_type'} eq 'DNA' ? 'tblastn' : 'blastp';
				}
			} else {
				if ( $run eq 'DNA' ) {
					$program = $options->{'qry_type'} eq 'DNA' ? 'blastn' : 'tblastn';
				} else {
					$program = $options->{'qry_type'} eq 'DNA' ? 'blastx' : 'blastp';
				}
			}
			my $blast_threads = $self->{'config'}->{'blast_threads'} || 1;
			my $filter = $program eq 'blastn' ? 'dust' : 'seg';
			my $word_size = $program eq 'blastn' ? ( $options->{'word_size'} // 15 ) : 3;
			my $format = $options->{'alignment'} ? 0 : 6;
			$options->{'num_results'} //= 1000000;    #effectively return all results
			my %params = (
				-num_threads => $blast_threads,
				-word_size   => $word_size,
				-db          => $temp_fastafile,
				-query       => $temp_infile,
				-out         => $temp_outfile,
				-outfmt      => $format,
				-$filter     => 'no'
			);
			if ( $options->{'alignment'} ) {
				$params{'-num_alignments'} = $options->{'num_results'};
			} else {
				$params{'-max_target_seqs'} = $options->{'num_results'};
			}
			$params{'-comp_based_stats'} = 0
			  if $program ne 'blastn'
			  && $program ne 'tblastx';    #Will not return some matches with low-complexity regions otherwise.
			system( "$self->{'config'}->{'blast+_path'}/$program", %params );
			if ( $run eq 'DNA' ) {
				rename( $temp_outfile, "$temp_outfile\.1" );
			}
		}
	}
	if ( !$options->{'locus'} || $options->{'locus'} =~ /SCHEME_\d+/x || $options->{'locus'} =~ /GROUP_\d+/x ) {
		my $outfile1 = "$temp_outfile\.1";
		BIGSdb::Utils::append( $outfile1, $temp_outfile ) if -e $outfile1;
		unlink $outfile1 if -e $outfile1;
	}

	#delete all working files
	if ( !$options->{'cache'} ) {
		unlink $temp_infile;
		my @files = glob("$self->{'config'}->{'secure_tmp_dir'}/$options->{'job'}*");
		foreach (@files) { unlink $1 if /^(.*BIGSdb.*)$/x && !/outfile.txt/x }
	}
	return ( $outfile_url, $options->{'job'} );
}

sub mark_cache_stale {

	#Mark all cache subdirectories as stale (each locus set will use a different directory)
	my ($self) = @_;
	my $dir = "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}";
	if ( -d $dir ) {
		foreach my $subdir ( glob "$dir/*" ) {
			next if !-d $subdir;    #skip if not a dirctory
			if ( $subdir =~ /\/(all|\d+)$/x ) {
				$subdir = $1;
				my $stale_flag_file = "$dir/$subdir/stale";
				open( my $fh, '>', $stale_flag_file ) || $logger->error('Cannot mark BLAST db stale.');
				close $fh;
			}
		}
	}
	return;
}

sub _get_cache_age {
	my ( $self, $set_id ) = @_;
	$set_id //= 'all';
	$set_id = 'all' if ( $self->{'system'}->{'sets'} // '' ) ne 'yes';
	my $temp_fastafile = "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}/$set_id/DNA_fastafile.txt";
	return 0 if !-e $temp_fastafile;
	return -M $temp_fastafile;
}

sub is_sequence_similar_to_others {

	#returns true if sequence is at least 70% identical over an alignment length of 90% or more.
	my ( $self, $locus, $seq_ref ) = @_;
	my $locus_info = $self->get_locus_info($locus);
	my ( $blast_file, undef ) =
	  $self->run_blast(
		{ locus => $locus, seq_ref => $seq_ref, qry_type => $locus_info->{'data_type'}, num_results => 1 } );
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$blast_file";
	my $length    = length $$seq_ref;
	return if !-s $full_path;
	open( my $blast_fh, '<', $full_path )
	  || ( $logger->error("Can't open BLAST output file $full_path. $!"), return 0 );
	my ( $identity, $reversed, $alignment );

	while ( my $line = <$blast_fh> ) {
		next if !$line || $line =~ /^\#/x;
		my @record = split /\s+/x, $line;
		$identity  = $record[2];
		$alignment = $record[3];
		if (   ( $record[8] > $record[9] && $record[7] > $record[6] )
			|| ( $record[8] < $record[9] && $record[7] < $record[6] ) )
		{
			$reversed = 1;
		}
		last;
	}
	close $blast_fh;
	unlink $full_path;
	return if $reversed;
	if ( defined $identity && $identity >= 70 && $alignment >= 0.9 * $length ) {
		return 1;
	}
	return;
}
##############REFERENCES###############################################################
sub get_citation_hash {
	my ( $self, $pmids, $options ) = @_;
	my $citation_ref = {};
	my %att          = (
		dbase_name => $self->{'config'}->{'ref_db'},
		host       => $self->{'system'}->{'host'},
		port       => $self->{'system'}->{'port'},
		user       => $self->{'system'}->{'user'},
		password   => $self->{'system'}->{'pass'}
	);
	my $dbr;
	try {
		$dbr = $self->{'dataConnector'}->get_connection( \%att );
	}
	catch BIGSdb::DatabaseConnectionException with {
		$logger->error('Cannot connect to reference database');
	};
	return $citation_ref if !$self->{'config'}->{'ref_db'} || !$dbr;
	foreach my $pmid (@$pmids) {
		my ( $year, $journal, $title, $volume, $pages ) =
		  $self->run_query( 'SELECT year,journal,title,volume,pages FROM refs WHERE pmid=?',
			$pmid, { db => $dbr, fetch => 'row_array', cache => 'get_citation_hash_paper' } );
		if ( !defined $year && !defined $journal ) {
			$citation_ref->{$pmid} .= "<a href=\"http://www.ncbi.nlm.nih.gov/pubmed/$pmid\">"
			  if $options->{'link_pubmed'};
			$citation_ref->{$pmid} .= "Pubmed id#$pmid";
			$citation_ref->{$pmid} .= '</a>' if $options->{'link_pubmed'};
			$citation_ref->{$pmid} .= ': No details available.' if $options->{'state_if_unavailable'};
			next;
		}
		my $authors = $self->run_query(
			'SELECT author FROM refauthors WHERE pmid=? ORDER BY position',
			$pmid,
			{ db => $dbr, fetch => 'col_arrayref' },
			cache => 'get_citation_hash_author_id'
		);
		my ( $author, @author_list );
		if ( $options->{'all_authors'} ) {
			foreach my $author_id (@$authors) {
				my ( $surname, $initials ) = $self->run_query( 'SELECT surname,initials FROM authors WHERE id=?',
					$author_id, { db => $dbr, cache => 'get_citation_hash_paper_author_name' } );
				$author = "$surname $initials";
				push @author_list, $author;
			}
			local $" = ', ';
			$author = "@author_list";
		} else {
			if (@$authors) {
				my ( $surname, undef ) = $self->run_query( 'SELECT surname,initials FROM authors WHERE id=?',
					$authors->[0], { db => $dbr, cache => 'get_citation_hash_paper_author_name' } );
				$author .= ( $surname || 'Unknown' );
				if ( @$authors > 1 ) {
					$author .= ' et al.';
				}
			}
		}
		$author ||= 'No authors listed';
		$volume .= ':' if $volume;
		my $citation;
		{
			no warnings 'uninitialized';
			if ( $options->{'formatted'} ) {
				$citation = "$author ($year). ";
				$citation .= "$title "                                               if !$options->{'no_title'};
				$citation .= "<a href=\"http://www.ncbi.nlm.nih.gov/pubmed/$pmid\">" if $options->{'link_pubmed'};
				$citation .= "<i>$journal</i> <b>$volume</b>$pages";
				$citation .= '</a>'                                                  if $options->{'link_pubmed'};
			} else {
				$citation = "$author $year ";
				$citation .= "<a href=\"http://www.ncbi.nlm.nih.gov/pubmed/$pmid\">" if $options->{'link_pubmed'};
				$citation .= "$journal $volume$pages";
				$citation .= '</a>'                                                  if $options->{'link_pubmed'};
			}
		}
		if ($citation) {
			$citation_ref->{$pmid} = $citation;
		} else {
			if ( $options->{'state_if_unavailable'} ) {
				$citation_ref->{$pmid} .= 'No details available.';
			} else {
				$citation_ref->{$pmid} .= 'Pubmed id#';
				$citation_ref->{$pmid} .=
				  $options->{'link_pubmed'} ? "<a href=\"http://www.ncbi.nlm.nih.gov/pubmed/$pmid\">$pmid</a>" : $pmid;
			}
		}
	}
	return $citation_ref;
}

sub create_temp_ref_table {
	my ( $self, $list, $qry_ref ) = @_;
	my %att = (
		dbase_name => $self->{'config'}->{'ref_db'},
		host       => $self->{'system'}->{'host'},
		port       => $self->{'system'}->{'port'},
		user       => $self->{'system'}->{'user'},
		password   => $self->{'system'}->{'pass'}
	);
	my $dbr;
	my $continue = 1;
	try {
		$dbr = $self->{'dataConnector'}->get_connection( \%att );
	}
	catch BIGSdb::DatabaseConnectionException with {
		$continue = 0;
		say q(<div class="box" id="statusbad"><p>Can not connect to reference database!</p></div>);
		$logger->error->('Cannot connect to reference database');
	};
	return if !$continue;
	my $create = 'CREATE TEMP TABLE temp_refs (pmid int, year int, journal text, volume text, pages text, title text, '
	  . 'abstract text, authors text, isolates int)';
	eval { $self->{'db'}->do($create); };
	if ($@) {
		$logger->error("Can't create temporary reference table. $@");
		return;
	}
	my $all_authors = $self->run_query( 'SELECT id,surname,initials FROM authors',
		undef, { db => $dbr, fetch => 'all_hashref', key => 'id' } );
	my $count_qry;
	if ($qry_ref) {
		my $isolate_qry = $$qry_ref;
		$isolate_qry =~ s/\*/id/x;
		$count_qry = "SELECT COUNT(*) FROM refs WHERE isolate_id IN ($isolate_qry) AND refs.pubmed_id=?";
	} else {
		$count_qry = 'SELECT COUNT(*) FROM refs WHERE refs.pubmed_id=?';
	}
	foreach my $pmid (@$list) {
		my $paper = $self->run_query( 'SELECT pmid,year,journal,volume,pages,title,abstract FROM refs WHERE pmid=?',
			$pmid, { db => $dbr, fetch => 'row_arrayref', cache => 'create_temp_ref_table_paper' } );
		my @authors;
		my $author_list = $self->run_query( 'SELECT author FROM refauthors WHERE pmid=? ORDER BY position',
			$pmid, { db => $dbr, fetch => 'all_arrayref', cache => 'create_temp_ref_table_author_list' } );
		foreach (@$author_list) {
			push @authors, "$all_authors->{$_->[0]}->{'surname'} $all_authors->{$_->[0]}->{'initials'}";
		}
		local $" = ', ';
		my $author_string = "@authors";
		my $isolates = $self->run_query( $count_qry, $pmid, { cache => 'create_temp_ref_table_count' } );
		eval {
			my $qry = 'INSERT INTO temp_refs VALUES (?,?,?,?,?,?,?,?,?)';
			if ($paper) {
				$self->{'db'}->do( $qry, undef, @$paper, $author_string, $isolates );
			} else {
				$self->{'db'}->do( $qry, undef, $pmid, undef, undef, undef, undef, undef, undef, undef, $isolates );
			}
		};
		$logger->error($@) if $@;
	}
	eval { $self->{'db'}->do('CREATE INDEX i_tr1 ON temp_refs(pmid)') };
	$logger->error($@) if $@;
	return 1;
}
##############SQL######################################################################
sub run_query {

   #$options->{'fetch'}: row_arrayref, row_array, row_hashref, col_arrayref, all_arrayref, all_hashref
   #$options->{'cache'}: Name to cache the statement handle under.  Statement not cached if absent.
   #$options->{'key'}:   Key field(s) to use for returning all as hashrefs.  Should be an arrayref if more than one key.
   #$options->{'slice'}: Slice to return for all_arrayrefs.
   #$options->{'db}:     Database handle.  Only pass if not accessing the database defined in config.xml (e.g. refs)
	my ( $self, $qry, $values, $options ) = @_;
	if ( defined $values ) {
		$values = [$values] if ref $values ne 'ARRAY';
	} else {
		$values = [];
	}
	$options = {} if ref $options ne 'HASH';
	my $db = $options->{'db'} // $self->{'db'};
	my $sql;
	if ( $options->{'cache'} ) {
		if ( !$self->{'sql'}->{ $options->{'cache'} } ) {
			$self->{'sql'}->{ $options->{'cache'} } = $db->prepare($qry);
		}
		$sql = $self->{'sql'}->{ $options->{'cache'} };
	} else {
		$sql = $db->prepare($qry);
	}
	$options->{'fetch'} //= 'row_array';
	if ( $options->{'fetch'} eq 'col_arrayref' ) {
		my $data;
		eval { $data = $db->selectcol_arrayref( $sql, undef, @$values ) };
		$logger->logcarp($@) if $@;
		return $data;
	}
	eval { $sql->execute(@$values) };
	$logger->logcarp($@) if $@;
	if ( $options->{'fetch'} eq 'row_arrayref' ) {    #returns undef when no rows
		return $sql->fetchrow_arrayref;
	}
	if ( $options->{'fetch'} eq 'row_array' ) {       #returns () when no rows, (undef-scalar context)
		return $sql->fetchrow_array;
	}
	if ( $options->{'fetch'} eq 'row_hashref' ) {     #returns undef when no rows
		return $sql->fetchrow_hashref;
	}
	if ( $options->{'fetch'} eq 'all_hashref' ) {     #returns {} when no rows
		if ( !defined $options->{'key'} ) {
			$logger->logcarp('Key field(s) needs to be passed.');
		}
		return $sql->fetchall_hashref( $options->{'key'} );
	}
	if ( $options->{'fetch'} eq 'all_arrayref' ) {    #returns [] when no rows
		return $sql->fetchall_arrayref( $options->{'slice'} );
	}
	$logger->logcarp('Query failed - invalid fetch method specified.');
	return;
}

#Returns array ref of attributes for a specific table provided by table-specific
#helper functions in BIGSdb::TableAttributes.
sub get_table_field_attributes {
	my ( $self, $table ) = @_;
	my $function = "BIGSdb::TableAttributes::get_$table\_table_attributes";
	my $attributes;
	eval { $attributes = $self->$function() };
	$logger->logcarp($@) if $@;
	return if ref $attributes ne 'ARRAY';
	foreach my $att (@$attributes) {
		foreach (qw(tooltip optlist required default hide hide_public hide_query main_display)) {
			$att->{$_} = '' if !defined( $att->{$_} );
		}
	}
	return $attributes;
}

sub get_table_pks {
	my ( $self, $table ) = @_;
	my @pk_fields;
	return ['id'] if $table eq 'isolates';
	my $attributes = $self->get_table_field_attributes($table);
	foreach (@$attributes) {
		if ( $_->{'primary_key'} ) {
			push @pk_fields, $_->{'name'};
		}
	}
	return \@pk_fields;
}

sub is_table {
	my ( $self, $qry ) = @_;
	$qry ||= '';
	my @tables = $self->get_tables;
	return 1 if any { $_ eq $qry } @tables;
	return 0;
}

sub get_tables {
	my ($self) = @_;
	my @tables;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		@tables =
		  qw(users user_groups user_group_members allele_sequences sequence_bin accession refs allele_designations
		  loci locus_aliases schemes scheme_members scheme_fields composite_fields composite_field_values
		  isolate_aliases curator_permissions projects project_members experiments experiment_sequences
		  isolate_field_extended_attributes isolate_value_extended_attributes scheme_groups scheme_group_scheme_members
		  scheme_group_group_members pcr pcr_locus probes probe_locus sets set_loci set_schemes set_metadata set_view
		  samples isolates history sequence_attributes);
		push @tables, $self->{'system'}->{'view'}
		  ? $self->{'system'}->{'view'}
		  : 'isolates';
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		@tables = qw(users user_groups user_group_members sequences sequence_refs accession loci schemes scheme_members
		  scheme_fields profiles profile_refs curator_permissions client_dbases client_dbase_loci client_dbase_schemes
		  locus_extended_attributes scheme_curators locus_curators locus_descriptions scheme_groups
		  scheme_group_scheme_members scheme_group_group_members client_dbase_loci_fields sets set_loci set_schemes
		  profile_history locus_aliases);
	}
	return @tables;
}

sub get_tables_with_curator {
	my ($self) = @_;
	my @tables;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		@tables =
		  qw(users user_groups user_group_members allele_sequences sequence_bin refs allele_designations loci schemes
		  scheme_members locus_aliases scheme_fields composite_fields composite_field_values isolate_aliases
		  projects project_members experiments experiment_sequences isolate_field_extended_attributes
		  isolate_value_extended_attributes scheme_groups scheme_group_scheme_members scheme_group_group_members
		  pcr pcr_locus probes probe_locus accession sequence_flags sequence_attributes history);
		push @tables, $self->{'system'}->{'view'}
		  ? $self->{'system'}->{'view'}
		  : 'isolates';
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		@tables = qw(users user_groups sequences profile_refs sequence_refs accession loci schemes
		  scheme_members scheme_fields scheme_groups scheme_group_scheme_members scheme_group_group_members
		  client_dbases client_dbase_loci client_dbase_schemes locus_links locus_descriptions locus_aliases
		  locus_extended_attributes sequence_extended_attributes locus_refs profile_history);
	}
	return @tables;
}

sub get_primary_keys {
	my ( $self, $table ) = @_;
	return 'id' if $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates';
	my @keys;
	my $attributes = $self->get_table_field_attributes($table);
	foreach (@$attributes) {
		push @keys, $_->{'name'} if $_->{'primary_key'};
	}
	return @keys;
}

sub get_set_metadata {
	my ( $self, $set_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	if ($set_id) {
		return $self->run_query( 'SELECT metadata_id FROM set_metadata WHERE set_id=?',
			$set_id, { fetch => 'col_arrayref' } );
	} elsif ( $options->{'curate'} ) {
		return $self->{'xmlHandler'}->get_metadata_list;
	}
}

sub get_metadata_value {
	my ( $self, $isolate_id, $metaset, $metafield ) = @_;
	my $data = $self->run_query( "SELECT * FROM meta_$metaset WHERE isolate_id=?",
		$isolate_id, { fetch => 'row_hashref', cache => "get_metadata_value_$metaset" } );
	return $data->{ lc($metafield) } // '';
}

sub materialized_view_exists {
	my ( $self, $scheme_id ) = @_;
	return 0 if ( ( $self->{'system'}->{'materialized_views'} // '' ) ne 'yes' );
	return $self->run_query( 'SELECT EXISTS(SELECT * FROM matviews WHERE mv_name=?)',
		"mv_scheme_$scheme_id", { cache => 'materialized_view_exists' } );
}

sub get_submission {
	my ( $self, $submission_id ) = @_;
	$logger->logcarp('No submission_id passed') if !$submission_id;
	return $self->run_query( 'SELECT * FROM submissions WHERE id=?',
		$submission_id, { fetch => 'row_hashref', cache => 'get_submission' } );
}

sub get_allele_submission {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	$logger->logcarp('No submission_id passed') if !$submission_id;
	my $submission = $self->run_query( 'SELECT * FROM allele_submissions WHERE submission_id=?',
		$submission_id, { fetch => 'row_hashref', cache => 'get_allele_submission' } );
	return if !$submission;
	my $fields = $options->{'fields'} // '*';
	my $seq_data =
	  $self->run_query( "SELECT $fields FROM allele_submission_sequences WHERE submission_id=? ORDER BY index",
		$submission_id, { fetch => 'all_arrayref', slice => {}, cache => 'get_allele_submission::sequences' } );
	$submission->{'seqs'} = $seq_data;
	return $submission;
}

sub get_profile_submission {
	my ( $self, $submission_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	$logger->logcarp('No submission_id passed') if !$submission_id;
	my $submission = $self->run_query( 'SELECT * FROM profile_submissions WHERE submission_id=?',
		$submission_id, { fetch => 'row_hashref', cache => 'get_profile_submission' } );
	return if !$submission;
	my $fields = $options->{'fields'} // '*';
	my $profiles =
	  $self->run_query( "SELECT $fields FROM profile_submission_profiles WHERE submission_id=? ORDER BY index",
		$submission_id, { fetch => 'all_arrayref', slice => {}, cache => 'get_profile_submission::profiles' } );
	$submission->{'profiles'} = [];

	foreach my $profile (@$profiles) {
		my $designations = $self->run_query(
			'SELECT locus,allele_id FROM '
			  . 'profile_submission_designations WHERE (submission_id,profile_id)=(?,?) ORDER BY locus',
			[ $submission_id, $profile->{'profile_id'} ],
			{ fetch => 'all_arrayref', slice => {}, cache => 'get_profile_submission::designations' }
		);
		$profile->{'designations'}->{ $_->{'locus'} } = $_->{'allele_id'} foreach @$designations;
		push @{ $submission->{'profiles'} }, $profile;
	}
	return $submission;
}

sub get_isolate_submission {
	my ( $self, $submission_id ) = @_;
	$logger->logcarp('No submission_id passed') if !$submission_id;
	my $positions = $self->run_query( 'SELECT field,index FROM isolate_submission_field_order WHERE submission_id=?',
		$submission_id, { fetch => 'all_arrayref', cache => 'get_isolate_submission::positions' } );
	return if !$positions;
	my $order = {};
	$order->{ $_->[0] } = $_->[1] foreach @$positions;
	my $indexes =
	  $self->run_query( 'SELECT DISTINCT(index) FROM isolate_submission_isolates WHERE submission_id=? ORDER BY index',
		$submission_id, { fetch => 'col_arrayref', cache => 'get_isolate_submission:index' } );
	my @isolates;

	foreach my $index (@$indexes) {
		my $values = $self->run_query(
			'SELECT field,value FROM isolate_submission_isolates WHERE (submission_id,index)=(?,?)',
			[ $submission_id, $index ],
			{ fetch => 'all_arrayref', cache => 'get_isolate_submission::isolates' }
		);
		my $isolate_values = {};
		$isolate_values->{ $_->[0] } = $_->[1] foreach @$values;
		push @isolates, $isolate_values;
	}
	my $submission = { order => $order, isolates => \@isolates };
	return $submission;
}

sub get_submission_dir {
	my ( $self, $submission_id ) = @_;
	return "$self->{'config'}->{'submission_dir'}/$submission_id";
}

sub delete_submission {
	my ( $self, $submission_id ) = @_;
	eval { $self->{'db'}->do( 'DELETE FROM submissions WHERE id=?', undef, $submission_id ) };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->_delete_submission_files($submission_id);
	}
	return;
}

sub _delete_submission_files {
	my ( $self, $submission_id ) = @_;
	my $dir = $self->get_submission_dir($submission_id);
	if ( $dir =~ /^($self->{'config'}->{'submission_dir'}\/BIGSdb[^\/]+$)/x ) {
		remove_tree( $1, { error => \my $err } );
		if (@$err) {
			for my $diag (@$err) {
				my ( $file, $message ) = %$diag;
				if ( $file eq '' ) {
					$logger->error("general error: $message");
				} else {
					$logger->error("problem unlinking $file: $message");
				}
			}
		}
	}
	return;
}

sub mkpath {
	my ( $self, $dir ) = @_;
	my $save_u = umask();
	umask(0);
	##no critic (ProhibitLeadingZeros)
	make_path( $dir, { mode => 0775, error => \my $err } );
	if (@$err) {
		for my $diag (@$err) {
			my ( $path, $message ) = %$diag;
			if ( $path eq '' ) {
				$logger->error("general error: $message");
			} else {
				$logger->error("problem with $path: $message");
			}
		}
	}
	umask($save_u);
	return;
}

sub write_submission_allele_FASTA {
	my ( $self, $submission_id ) = @_;
	my $allele_submission = $self->get_allele_submission($submission_id);
	my $seqs              = $allele_submission->{'seqs'};
	return if !@$seqs;
	my $dir = $self->get_submission_dir($submission_id);
	$dir = $dir =~ /^($self->{'config'}->{'submission_dir'}\/BIGSdb[^\/]+$)/x ? $1 : undef;    #Untaint
	$self->mkpath($dir);
	my $filename = 'sequences.fas';
	open( my $fh, '>', "$dir/$filename" ) || $logger->error("Can't open $dir/$filename for writing");

	foreach my $seq (@$seqs) {
		say $fh ">$seq->{'seq_id'}";
		say $fh $seq->{'sequence'};
	}
	close $fh;
	return $filename;
}
1;
