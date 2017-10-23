#Written by Keith Jolley
#Copyright (c) 2010-2017, University of Oxford
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
use List::Util qw(min max sum);
use Error qw(:try);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Datastore');
use Unicode::Collate;
use File::Path qw(make_path);
use Fcntl qw(:flock);
use BIGSdb::ClientDB;
use BIGSdb::Locus;
use BIGSdb::Scheme;
use BIGSdb::TableAttributes;
use BIGSdb::Constants qw(:login_requirements);
use IO::Handle;
use Digest::MD5;
use POSIX qw(ceil);
use constant INF => 9**99;

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

sub change_db {
	my ( $self, $db ) = @_;
	$self->{'db'}  = $db;
	$self->{'sql'} = {};    #Clear statement hash which may be for wrong database
	return;
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
	my $user_info =
	  $self->run_query( 'SELECT id,user_name,first_name,surname,affiliation,email,status,user_db FROM users WHERE id=?',
		$id, { fetch => 'row_hashref', cache => 'get_user_info' } );
	if ( $user_info && $user_info->{'user_name'} && $user_info->{'user_db'} ) {
		my $remote_user = $self->get_remote_user_info( $user_info->{'user_name'}, $user_info->{'user_db'} );
		if ( $remote_user->{'user_name'} ) {
			$user_info->{$_} = $remote_user->{$_} foreach qw(first_name surname email affiliation);
		}
	}
	return $user_info;
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

	if ( $options->{'affiliation'} && $info->{'affiliation'} ) {
		$info->{'affiliation'} =~ s/^\s*//x;
		$user .= ", $info->{'affiliation'}";
	}
	return $user;
}

sub get_remote_user_info {
	my ( $self, $user_name, $user_db_id ) = @_;
	my $user_db = $self->get_user_db($user_db_id);
	return $self->run_query( 'SELECT user_name,first_name,surname,email,affiliation FROM users WHERE user_name=?',
		$user_name, { db => $user_db, fetch => 'row_hashref', cache => "get_remote_user_info:$user_db_id" } );
}

sub get_user_info_from_username {
	my ( $self, $user_name ) = @_;
	return if !defined $user_name;
	my $user_info = $self->run_query( 'SELECT * FROM users WHERE user_name=?',
		$user_name, { fetch => 'row_hashref', cache => 'get_user_info_from_username' } );
	if ( $user_info && $user_info->{'user_db'} ) {
		my $remote_user = $self->get_remote_user_info( $user_name, $user_info->{'user_db'} );
		if ( $remote_user->{'user_name'} ) {
			$user_info->{$_} = $remote_user->{$_} foreach qw(first_name surname email affiliation);
		}
	}
	return $user_info;
}

sub get_permissions {
	my ( $self, $user_name ) = @_;
	my $permission_list;
	if ( $self->{'system'}->{'dbtype'} eq 'user' ) {
		$permission_list = $self->run_query( 'SELECT permission FROM permissions WHERE user_name=?',
			$user_name, { fetch => 'col_arrayref', cache => 'get_permissions' } );
	} else {
		$permission_list = $self->run_query(
			'SELECT permission FROM permissions LEFT JOIN users ON '
			  . 'permissions.user_id = users.id WHERE user_name=?',
			$user_name,
			{ fetch => 'col_arrayref', cache => 'get_permissions' }
		);
	}
	my %permission_hash = map { $_ => 1 } @$permission_list;

	#Site permissions
	my $user_info = $self->get_user_info_from_username($user_name);
	if ( $user_info->{'user_db'} ) {
		my $user_db          = $self->get_user_db( $user_info->{'user_db'} );
		my $site_permissions = $self->run_query( 'SELECT permission FROM permissions WHERE user_name=?',
			$user_name, { db => $user_db, fetch => 'col_arrayref' } );
		$permission_hash{$_} = 1 foreach @$site_permissions;
	}
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
	my $scheme     = $self->get_scheme($scheme_id);
	$self->_convert_designations_to_profile_names( $scheme_id, $designations );
	{
		try {
			$field_data = $scheme->get_field_values_by_designations($designations);
		}
		catch BIGSdb::DatabaseConfigurationException with {
			$logger->warn("Scheme $scheme_id database is not configured correctly");
		};
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

sub isolate_exists {
	my ( $self, $isolate_id ) = @_;
	return $self->run_query( 'SELECT EXISTS(SELECT * FROM isolates WHERE id=?)', $isolate_id );
}

sub get_scheme_locus_indices {
	my ( $self, $scheme_id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $data = $self->run_query( 'SELECT locus,index FROM scheme_warehouse_indices WHERE scheme_id=?',
		$scheme_id, { fetch => 'all_arrayref' } );

	#PostgreSQL numbers arrays from 1 - Perl numbers from 0.
	my %indices;
	if ( $options->{'pg_numbering'} ) {
		%indices = map { $_->[0] => $_->[1] } @$data;
	} else {
		%indices = map { $_->[0] => ( $_->[1] - 1 ) } @$data;
	}
	return \%indices;
}

sub get_scheme_warehouse_locus_name {
	my ( $self, $scheme_id, $locus ) = @_;
	if ( !$self->{'cache'}->{'scheme_warehouse_locus_indices'}->{$scheme_id} ) {
		$self->{'cache'}->{'scheme_warehouse_locus_indices'}->{$scheme_id} =
		  $self->get_scheme_locus_indices( $scheme_id, { pg_numbering => 1 } );
	}
	return "profile[$self->{'cache'}->{'scheme_warehouse_locus_indices'}->{$scheme_id}->{$locus}]";
}

#pk_value is optional and can be used to check if updating an existing profile matches another definition.
sub check_new_profile {
	my ( $self, $scheme_id, $designations, $pk_value ) = @_;
	$pk_value //= q();
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $scheme_info      = $self->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $pk               = $scheme_info->{'primary_key'};
	my $loci = $self->run_query( 'SELECT locus FROM scheme_warehouse_indices WHERE scheme_id=? ORDER BY index',
		$scheme_id, { fetch => 'col_arrayref' } );
	my @profile;
	my $empty_profile = 1;

	foreach my $locus (@$loci) {
		push @profile, $designations->{$locus};
		$empty_profile = 0 if !( ( $designations->{$locus} // 'N' ) eq 'N' );
	}
	if ($empty_profile) {
		return {
			exists => 1,
			msg    => q(You cannot define a profile with every locus set to be an arbitrary value (N).)
		};
	}
	my $pg_array = BIGSdb::Utils::get_pg_array( \@profile );
	if ( !$scheme_info->{'allow_missing_loci'} ) {
		my $exact_match = $self->run_query( "SELECT $pk FROM $scheme_warehouse WHERE profile=?", $pg_array );
		if ($exact_match) {
			return {
				exists   => 1,
				assigned => [$exact_match],
				msg      => qq(Profile has already been defined as $pk-$exact_match.)
			};
		}
		return { exists => 0 };
	}

	#Check for matches where N may be used in the profile
	my $i = 0;
	my ( @locus_temp, @values, $temp_cache_key );
	foreach my $locus (@$loci) {

		#N can be any allele so can not be used to differentiate profiles
		$i++;
		next if ( $designations->{$locus} // '' ) eq 'N';
		push @locus_temp, "(profile[$i]=? OR profile[$i]='N')";
		push @values,     $designations->{$locus};
		$temp_cache_key .= $locus;
	}
	my $qry       = "SELECT $pk FROM $scheme_warehouse WHERE ";
	my $cache_key = Digest::MD5::md5_hex($temp_cache_key);
	local $" = ' AND ';
	$qry .= "(@locus_temp)";
	my $matching_profiles =
	  $self->run_query( $qry, \@values,
		{ fetch => 'col_arrayref', cache => "check_new_profile::${scheme_id}::$cache_key" } );
	if ( @$matching_profiles && !( @$matching_profiles == 1 && $matching_profiles->[0] eq $pk_value ) ) {
		my $msg;
		if ( @locus_temp < @$loci ) {
			my $first_match;
			foreach my $profile_id (@$matching_profiles) {
				if ( $profile_id ne $pk_value ) {
					$first_match = $profile_id;
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
		return { exists => 1, assigned => $matching_profiles, msg => $msg };
	}
	return { exists => 0 };
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
##############USER DATABASES###########################################################
sub initiate_userdbs {
	my ($self) = @_;
	my $configs =
	  $self->run_query( 'SELECT * FROM user_dbases ORDER BY id', undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $config (@$configs) {
		try {
			$self->{'user_dbs'}->{ $config->{'id'} } =
			  { db => $self->{'dataConnector'}->get_connection($config), name => $config->{'dbase_name'} };
		}
		catch BIGSdb::DatabaseConnectionException with {
			$logger->warn("Cannot connect to database '$config->{'dbase_name'}'");
			$self->{'error'} = 'noConnect';
		};
	}
	return;
}

sub get_user_db {
	my ( $self, $id ) = @_;
	return $self->{'user_dbs'}->{$id}->{'db'};
}

sub get_user_dbs {
	my ($self) = @_;
	my $dbases = [];
	foreach my $config_id ( keys %{ $self->{'user_dbs'} } ) {
		$self->{'user_dbs'}->{$config_id}->{'id'} = $config_id;
		push @$dbases, $self->{'user_dbs'}->{$config_id};
	}
	return $dbases;
}

sub user_dbs_defined {
	my ($self) = @_;
	return 1 if keys %{ $self->{'user_dbs'} };
	return;
}

sub user_db_defined {
	my ( $self, $id ) = @_;
	return defined $self->{'user_dbs'}->{$id} ? 1 : undef;
}

sub get_configs_using_same_database {
	my ( $self, $user_db, $dbase_name ) = @_;
	return $self->run_query(
		'SELECT rr.dbase_config FROM available_resources ar JOIN registered_resources rr '
		  . 'ON ar.dbase_config=rr.dbase_config WHERE dbase_name=?',
		$dbase_name,
		{ db => $user_db, fetch => 'col_arrayref' }
	);
}

sub get_dbname_with_user_details {
	my ( $self, $username ) = @_;
	my $user_info = $self->get_user_info_from_username($username);
	return $self->{'system'}->{'db'} if !$user_info->{'user_db'};
	return $self->run_query(
		'SELECT dbase_name FROM user_dbases WHERE id=?',
		$user_info->{'user_db'},
		{ cache => 'get_dbname_with_user_details' }
	);
}

sub user_name_exists {
	my ( $self, $name ) = @_;
	return $self->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE user_name=?)', $name );
}

sub get_users {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $qry = 'SELECT id,first_name,surname,user_name,user_db FROM users WHERE ';
	if ( $options->{'curators'} ) {
		$qry .= q(status IN ('curator','admin','submitter') AND );
	}
	if ( $options->{'same_user_group'} && BIGSdb::Utils::is_int( $options->{'user_id'} ) ) {
		$qry .= qq[(id=$options->{'user_id'} OR id IN (SELECT user_id FROM user_group_members WHERE user_group ]
		  . qq[IN (SELECT user_group FROM user_group_members WHERE user_id=$options->{'user_id'}))) AND ];
	}
	$qry .= q(id > 0);
	my $data = $self->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $user (@$data) {

		#User details may be stored in site-wide users database
		if ( $user->{'user_db'} ) {
			my $remote_user = $self->get_remote_user_info( $user->{'user_name'}, $user->{'user_db'} );
			if ( $remote_user->{'user_name'} ) {
				$user->{$_} = $remote_user->{$_} foreach qw(first_name surname email affiliation);
			}
		}
	}
	my $ids    = [];
	my $labels = {};
	$options->{'format'}     //= 'sfu';
	$options->{'identifier'} //= 'id';
	foreach my $user (@$data) {
		next if $user->{'user_name'} =~ /^REMOVED_USER/x;
		push @$ids, $user->{ $options->{'identifier'} };
		my %format = (
			fs  => "$user->{'first_name'} $user->{'surname'}",
			sf  => "$user->{'surname'}, $user->{'first_name'}",
			sfu => "$user->{'surname'}, $user->{'first_name'} ($user->{'user_name'})"
		);
		if ( $format{ $options->{'format'} } ) {
			$labels->{ $user->{ $options->{'identifier'} } } = $format{ $options->{'format'} };
		}
	}
	$labels->{''} = $options->{'blank_message'} ? $options->{'blank_message'} : q( );
	@$ids = sort { uc( $labels->{$a} ) cmp uc( $labels->{$b} ) } @$ids;
	return ( $ids, $labels );
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
		$scheme_info->{'name'} = $desc if defined $desc;
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
	$self->{'locus_alias_count'}++;
	if ( $self->{'locus_alias_count'} > 10 && !$self->{'all_locus_aliases'} ) {
		my $all_data = $self->run_query( 'SELECT locus,alias FROM locus_aliases WHERE use_alias ORDER BY alias',
			undef, { fetch => 'all_arrayref' } );
		foreach my $record (@$all_data) {
			push @{ $self->{'all_locus_aliases'}->{ $record->[0] } }, $record->[1];
		}
	}
	if ( $self->{'all_locus_aliases'} ) {
		return $self->{'all_locus_aliases'}->{$locus} // [];
	}
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
	my $submission_clause =
	  $options->{'submissions'} ? q( AND (schemes.no_submissions IS NULL OR NOT schemes.no_submissions)) : q();
	if ( $options->{'set_id'} ) {
		if ( $options->{'with_pk'} ) {
			$qry =
			    q(SELECT DISTINCT schemes.id,set_schemes.set_name,schemes.name,schemes.display_order FROM )
			  . q(set_schemes LEFT JOIN schemes ON set_schemes.scheme_id=schemes.id RIGHT JOIN scheme_members ON )
			  . q(schemes.id=scheme_members.scheme_id JOIN scheme_fields ON schemes.id=scheme_fields.scheme_id WHERE )
			  . qq(primary_key AND set_schemes.set_id=$options->{'set_id'}$submission_clause ORDER BY schemes.display_order,)
			  . q(schemes.name);
		} else {
			$qry =
			    q(SELECT DISTINCT schemes.id,set_schemes.set_name,schemes.name,schemes.display_order FROM )
			  . q(set_schemes LEFT JOIN schemes ON set_schemes.scheme_id=schemes.id AND set_schemes.set_id=)
			  . qq($options->{'set_id'} WHERE schemes.id IS NOT NULL$submission_clause ORDER BY schemes.display_order,)
			  . q(schemes.name);
		}
	} else {
		if ( $options->{'with_pk'} ) {
			$qry =
			    q(SELECT DISTINCT schemes.id,schemes.name,schemes.display_order FROM schemes RIGHT JOIN )
			  . q(scheme_members ON schemes.id=scheme_members.scheme_id JOIN scheme_fields ON schemes.id=)
			  . qq(scheme_fields.scheme_id WHERE primary_key$submission_clause ORDER BY schemes.display_order,schemes.name);
		} else {
			$submission_clause =~ s/AND/WHERE/x;
			$qry = qq[SELECT id,name,display_order FROM schemes$submission_clause ORDER BY display_order,name];
		}
	}
	my $list = $self->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	foreach (@$list) {
		$_->{'name'} = $_->{'set_name'} if $_->{'set_name'};
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

sub create_temp_isolate_scheme_fields_view {
	my ( $self, $scheme_id, $options ) = @_;

	#Create view containing isolate_id and scheme_fields.
	#This view can instead be created as a persistent indexed table using the update_scheme_cache.pl script.
	#This should be done once the scheme size/number of isolates results in a slowdown of queries.
	$options = {} if ref $options ne 'HASH';
	my $view  = $self->{'system'}->{'view'};
	my $table = "temp_${view}_scheme_fields_$scheme_id";
	if ( !$options->{'cache'} ) {
		return $table
		  if $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );

		#Check if cache of whole isolate table exists
		if ( $view ne 'isolates' ) {
			my $full_table = "temp_isolates_scheme_fields_$scheme_id";
			return $full_table
			  if $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
				$full_table );
		}
	}
	local $| = 1;
	my $scheme_table = $self->create_temp_scheme_table( $scheme_id, $options );
	my $temp_table = $options->{'cache'} ? 'false' : 'true';
	my $method = $options->{'method'} // 'full';
	eval { $self->{'db'}->do("SELECT create_isolate_scheme_cache($scheme_id,'$view',$temp_table,'$method')") };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	}
	if ( $options->{'cache'} ) {
		$self->{'db'}->commit;
	} else {
		$self->{'scheme_not_cached'} = 1;
	}
	return $table;
}

sub create_temp_cscheme_table {
	my ( $self, $cscheme_id, $options ) = @_;
	my $table = "temp_cscheme_$cscheme_id";
	if ( !$options->{'cache'} ) {
		if ( $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table ) ) {
			return $table;
		}
	}
	my $table_type = 'TEMP TABLE';
	my $rename_table;
	if ( $options->{'cache'} ) {
		$table_type   = 'TABLE';
		$rename_table = $table;
		$table        = $table . '_' . int( rand(99999) );
	}
	my $cscheme_info   = $self->get_classification_scheme_info($cscheme_id);
	my $cscheme        = $self->get_classification_scheme($cscheme_id);
	my $db             = $cscheme->get_db;
	my $group_profiles = $self->run_query(
		'SELECT group_id,profile_id FROM classification_group_profiles WHERE cg_scheme_id=?',
		$cscheme_info->{'seqdef_cscheme_id'},
		{ db => $db, fetch => 'all_arrayref' }
	);
	eval {
		$self->{'db'}->do("CREATE $table_type $table (group_id int, profile_id int)");
		$self->{'db'}->do("COPY $table(group_id,profile_id) FROM STDIN");
		local $" = "\t";
		foreach my $values (@$group_profiles) {
			$self->{'db'}->pg_putcopydata("@$values\n");
		}
		$self->{'db'}->pg_putcopyend;
		$self->{'db'}->do("CREATE INDEX ON $table(group_id)");
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
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

sub create_temp_scheme_table {
	my ( $self, $id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $scheme_info = $self->get_scheme_info($id);
	my $scheme      = $self->get_scheme($id);
	my $scheme_db   = $scheme->get_db;
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
	push @table_fields, 'profile text[]';
	my $locus_indices = $scheme->get_locus_indices;
	eval {
		$self->{'db'}->do( 'DELETE FROM scheme_warehouse_indices WHERE scheme_id=?', undef, $id );
		foreach my $profile_locus ( keys %$locus_indices ) {
			my $locus_name = $self->run_query(
				'SELECT locus FROM scheme_members WHERE profile_name=? AND scheme_id=?',
				[ $profile_locus, $id ],
				{ cache => 'create_temp_scheme_table_profile_name' }
			);
			$locus_name //= $profile_locus;
			$self->{'db'}->do( 'INSERT INTO scheme_warehouse_indices (scheme_id,locus,index) VALUES (?,?,?)',
				undef, $id, $locus_name, $locus_indices->{$profile_locus} );
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	local $" = ',';
	$create .= "@table_fields";
	$create .= ')';
	$self->{'db'}->do($create);
	my $seqdef_scheme_id = $self->get_scheme_info($id)->{'dbase_id'};
	my $data = $self->run_query( "SELECT @$fields,array_to_string(profile,',') FROM mv_scheme_$seqdef_scheme_id",
		undef, { db => $scheme_db, fetch => 'all_arrayref' } );
	eval { $self->{'db'}->do("COPY $table(@$fields,profile) FROM STDIN"); };

	if ($@) {
		$logger->error('Cannot start copying data into temp table');
	}
	local $" = "\t";

	#TODO Test what happens if alleles can have commas in their ids.
	foreach my $values (@$data) {
		$values->[-1] = "{$values->[-1]}";
		foreach my $value (@$values) {
			$value = '\N' if !defined $value || $value eq '';
		}
		eval { $self->{'db'}->pg_putcopydata("@$values\n"); };
		if ($@) {
			$logger->warn("Can't put data into temp table @$values");
		}
	}
	eval { $self->{'db'}->pg_putcopyend; };
	if ($@) {
		$logger->error("Can't put data into temp table: $@");
		$self->{'db'}->rollback;
		throw BIGSdb::DatabaseConnectionException('Cannot put data into temp table');
	}
	foreach my $field (@$fields) {
		my $field_info = $self->get_scheme_field_info( $id, $field );
		if ( $field_info->{'type'} eq 'integer' ) {
			$self->{'db'}->do("CREATE INDEX i_${table}_$field ON $table ($field)");
		} else {
			$self->{'db'}->do("CREATE INDEX i_${table}_$field ON $table (UPPER($field))");
		}
	}

	#Index up to 3 elements
	my $index_count = keys %$locus_indices >= 3 ? 3 : keys %$locus_indices;
	foreach my $element ( 1 .. $index_count ) {
		$self->{'db'}->do("CREATE INDEX ON $table ((profile[$element]))");
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
	my $table = "temp_${view}_scheme_completion_$scheme_id";
	if ( !$options->{'cache'} ) {
		return $table
		  if $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );

		#Check if cache of whole isolate table exists
		if ( $view ne 'isolates' ) {
			my $full_table = "temp_isolates_scheme_completion_$scheme_id";
			return $full_table
			  if $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
				$full_table );
		}
	}
	my $temp_table = $options->{'cache'} ? 'false' : 'true';
	my $method = $options->{'method'} // 'full';
	eval { $self->{'db'}->do("SELECT create_isolate_scheme_status_table($scheme_id,'$view',$temp_table,'$method')") };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	}
	if ( $options->{'cache'} ) {
		$self->{'db'}->commit;
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
			s/\t/    /gx;
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

sub get_scheme_group_info {
	my ( $self, $group_id ) = @_;
	return $self->run_query( 'SELECT * FROM scheme_groups WHERE id=?',
		$group_id, { fetch => 'row_hashref', cache => 'get_scheme_group_info' } );
}

sub get_classification_scheme {
	my ( $self, $cscheme_id ) = @_;
	if ( !$self->{'cscheme'}->{$cscheme_id} ) {
		my $attributes = $self->get_classification_scheme_info($cscheme_id);
		$attributes->{'db'} = $self->get_scheme( $attributes->{'scheme_id'} )->get_db;
		$self->{'cscheme'}->{$cscheme_id} = BIGSdb::ClassificationScheme->new(%$attributes);
	}
	return $self->{'cscheme'}->{$cscheme_id};
}

sub get_classification_scheme_info {
	my ( $self, $cg_scheme_id ) = @_;
	my $info = $self->run_query( 'SELECT * FROM classification_schemes WHERE id=?',
		$cg_scheme_id, { fetch => 'row_hashref', cache => 'get_classification_scheme_info' } );
	$info->{'seqdef_cscheme_id'} //= $cg_scheme_id;
	return $info;
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
	my $set_clause = '';
	if ( $options->{'set_id'} ) {
		$set_clause = $defined_clause ? 'AND' : 'WHERE';
		$set_clause .=
		    ' (id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE '
		  . "set_id=$options->{'set_id'})) OR id IN (SELECT locus FROM set_loci WHERE set_id=$options->{'set_id'}))";
	}
	my $qry;
	if ( any { $options->{$_} } qw (query_pref analysis_pref) ) {
		$qry = 'SELECT id,scheme_id FROM loci LEFT JOIN scheme_members ON loci.id = scheme_members.locus '
		  . "$defined_clause $set_clause";
		if ( !$options->{'do_not_order'} ) {
			$qry .= ' ORDER BY scheme_members.scheme_id,scheme_members.field_order,id';
		}
	} else {
		$qry = "SELECT id FROM loci $defined_clause $set_clause";
		if ( !$options->{'do_not_order'} ) {
			$qry .= ' ORDER BY id';
		}
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
		  . "set_loci.locus AND set_loci.set_id=$options->{'set_id'} WHERE id IN (SELECT locus FROM scheme_members "
		  . "WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$options->{'set_id'})) OR id IN "
		  . "(SELECT locus FROM set_loci WHERE set_id=$options->{'set_id'})";
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
	if ( $options->{'submissions'} ) {
		$qry .= ( $qry =~ /loci$/x ) ? ' WHERE ' : ' AND ';
		$qry .= 'loci.no_submissions IS NULL OR NOT loci.no_submissions';
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
	$self->{'locus_count'}++;

	#Get information for all loci if we're being called multiple times.
	#Cache this information.
	if ( $self->{'locus_count'} > 10 && !$self->{'all_locus_info'} ) {
		$self->{'all_locus_info'} =
		  $self->run_query( 'SELECT * FROM loci', undef, { fetch => 'all_hashref', key => 'id' } );
	}
	$options = {} if ref $options ne 'HASH';
	my $locus_info;
	if ( $self->{'all_locus_info'} ) {
		$locus_info = $self->{'all_locus_info'}->{$locus};
	} else {
		$locus_info = $self->run_query( 'SELECT * FROM loci WHERE id=?',
			$locus, { fetch => 'row_hashref', cache => 'get_locus_info' } );
	}
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

sub clear_locus_info_cache {
	my ($self) = @_;
	undef $self->{'all_locus_info'};
	return;
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

sub is_sequence_retired {
	my ( $self, $locus, $allele_id ) = @_;
	return $self->run_query(
		'SELECT EXISTS(SELECT * FROM retired_allele_ids WHERE (locus,allele_id)=(?,?))',
		[ $locus, $allele_id ],
		cache => 'is_sequence_retired'
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

sub is_profile_retired {
	my ( $self, $scheme_id, $profile_id ) = @_;
	return $self->run_query(
		'SELECT EXISTS(SELECT * FROM retired_profiles WHERE (scheme_id,profile_id)=(?,?))',
		[ $scheme_id, $profile_id ],
		cache => 'is_profile_retired'
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
	my ( $self, $locus, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $existing_alleles = $self->run_query(
		q[SELECT CAST(allele_id AS int) FROM sequences WHERE locus=? AND ]
		  . q[allele_id !='N' UNION SELECT CAST(allele_id AS int) FROM retired_allele_ids ]
		  . q[WHERE locus=? ORDER BY allele_id],
		[ $locus, $locus ],
		{ db => $options->{'db'} // $self->{'db'}, fetch => 'col_arrayref', cache => 'get_next_allele_id' }
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
	my ( $dl_buffer, $td_buffer, $field_values );
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
				  . "client_dbase_loci_fields table is correctly configured. $@" );
			$proceed = 0;
		};
		next if !$proceed;
		next if !@$field_data;
		$dl_buffer .= "<dt>$field</dt>";
		my @values;
		foreach my $data (@$field_data) {
			my $value = $data->{$field};
			push @{ $field_values->{$field} }, $value;
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
		return { formatted => $td_buffer, values => $field_values };
	}
	return { formatted => $dl_buffer, values => $field_values };
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
			$citation_ref->{$pmid} .= "<a href=\"https://www.ncbi.nlm.nih.gov/pubmed/$pmid\">"
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
				$citation .= "$title "                                                if !$options->{'no_title'};
				$citation .= "<a href=\"https://www.ncbi.nlm.nih.gov/pubmed/$pmid\">" if $options->{'link_pubmed'};
				$citation .= "<i>$journal</i> <b>$volume</b>$pages";
				$citation .= '</a>'                                                   if $options->{'link_pubmed'};
			} else {
				$citation = "$author $year ";
				$citation .= "<a href=\"https://www.ncbi.nlm.nih.gov/pubmed/$pmid\">" if $options->{'link_pubmed'};
				$citation .= "$journal $volume$pages";
				$citation .= '</a>'                                                   if $options->{'link_pubmed'};
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
				  $options->{'link_pubmed'} ? "<a href=\"https://www.ncbi.nlm.nih.gov/pubmed/$pmid\">$pmid</a>" : $pmid;
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

#Table containing all sequences for a particular locus - this is more efficient for querying by sequence
#in large seqdef databases
sub create_temp_allele_table {
	my ( $self, $locus ) = @_;
	my $table = 'temp_seqs_' . int( rand(99999999) );
	eval {
		$self->{'db'}->do(
			"CREATE TEMP TABLE $table AS SELECT allele_id,UPPER(sequence) "
			  . 'AS sequence FROM sequences WHERE locus=?;'
			  . "CREATE INDEX i_${table}_seq ON $table(md5(sequence))",
			undef, $locus
		);
	};
	$logger->error($@) if $@;
	return $table;
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
		$logger->logcarp("$@ Query:$qry") if $@;
		return $data;
	}
	eval { $sql->execute(@$values) };
	$logger->logcarp("$@ Query:$qry") if $@;
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
		  isolate_aliases permissions projects project_members experiments experiment_sequences
		  isolate_field_extended_attributes isolate_value_extended_attributes scheme_groups scheme_group_scheme_members
		  scheme_group_group_members pcr pcr_locus probes probe_locus sets set_loci set_schemes set_metadata set_view
		  samples isolates history sequence_attributes classification_schemes classification_group_fields
		  retired_isolates user_dbases oauth_credentials);
		push @tables, $self->{'system'}->{'view'}
		  ? $self->{'system'}->{'view'}
		  : 'isolates';
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		@tables = qw(users user_groups user_group_members sequences sequence_refs accession loci schemes scheme_members
		  scheme_fields profiles profile_refs permissions client_dbases client_dbase_loci client_dbase_schemes
		  locus_extended_attributes scheme_curators locus_curators locus_descriptions scheme_groups
		  scheme_group_scheme_members scheme_group_group_members client_dbase_loci_fields sets set_loci set_schemes
		  profile_history locus_aliases retired_allele_ids retired_profiles classification_schemes
		  classification_group_fields user_dbases locus_links);
	}
	return @tables;
}

sub get_tables_with_curator {
	my ( $self, $options ) = @_;
	my $dbtype = $options->{'dbtype'} // $self->{'system'}->{'dbtype'};
	my @tables;
	if ( $dbtype eq 'isolates' ) {
		@tables =
		  qw(users user_groups user_group_members allele_sequences sequence_bin refs allele_designations loci schemes
		  scheme_members locus_aliases scheme_fields composite_fields composite_field_values isolate_aliases
		  projects project_members experiments experiment_sequences isolate_field_extended_attributes
		  isolate_value_extended_attributes scheme_groups scheme_group_scheme_members scheme_group_group_members
		  pcr pcr_locus probes probe_locus accession sequence_flags sequence_attributes history classification_schemes
		  isolates);
		push @tables, $self->{'system'}->{'view'}
		  if $self->{'system'}->{'view'} && $self->{'system'}->{'view'} ne 'isolates';
	} elsif ( $dbtype eq 'sequences' ) {
		@tables = qw(users user_groups sequences profile_refs sequence_refs accession loci schemes
		  scheme_members scheme_fields scheme_groups scheme_group_scheme_members scheme_group_group_members
		  client_dbases client_dbase_loci client_dbase_schemes locus_links locus_descriptions locus_aliases
		  locus_extended_attributes sequence_extended_attributes locus_refs profile_history classification_schemes
		  classification_group_fields profiles retired_profiles);
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

sub get_login_requirement {
	my ($self) = @_;
	if ( $self->{'system'}->{'dbtype'} eq 'user' && $self->{'config'}->{'site_user_dbs'} ) {
		return REQUIRED;
	}
	if ( ( ( $self->{'system'}->{'read_access'} // q() ) ne 'public' )
		|| $self->{'curate'} )
	{
		return REQUIRED;
	}
	if ( ( $self->{'system'}->{'public_login'} // q() ) ne 'no'
		&& $self->{'system'}->{'authentication'} eq 'builtin' )
	{
		return OPTIONAL;
	}
	return NOT_ALLOWED;
}

sub get_user_private_isolate_limit {
	my ( $self, $user_id ) = @_;
	return 0 if $self->{'system'}->{'dbtype'} ne 'isolates';
	my $default_limit = $self->{'system'}->{'default_private_records'} // 0;
	return if !BIGSdb::Utils::is_int($default_limit);
	my $user_limit = $self->run_query( 'SELECT value FROM user_limits WHERE (user_id,attribute)=(?,?)',
		[ $user_id, 'private_isolates' ] );
	my $limit = $user_limit // $default_limit;
	return $limit;
}

sub get_private_isolate_count {
	my ( $self, $user_id ) = @_;
	return $self->run_query(
		'SELECT COUNT(*) FROM private_isolates pi WHERE user_id=? AND NOT EXISTS'
		  . '(SELECT 1 FROM project_members pm JOIN projects p ON pm.project_id=p.id WHERE '
		  . 'pm.isolate_id=pi.isolate_id AND p.no_quota)',
		$user_id
	);
}

sub get_available_quota {
	my ( $self, $user_id ) = @_;
	my $private   = $self->get_private_isolate_count($user_id);
	my $limit     = $self->get_user_private_isolate_limit($user_id);
	my $available = $limit - $private;
	$available = 0 if $available < 0;
	return $available;
}

sub initiate_view {
	my ( $self, $args ) = @_;
	my ( $username, $curate, $set_id ) = @{$args}{qw(username curate set_id)};
	return if ( $self->{'system'}->{'dbtype'} // '' ) ne 'isolates';
	if ( defined $self->{'system'}->{'view'} && $set_id ) {
		if ( $self->{'system'}->{'views'} && BIGSdb::Utils::is_int($set_id) ) {
			my $set_view = $self->run_query( 'SELECT view FROM set_view WHERE set_id=?', $set_id );
			$self->{'system'}->{'view'} = $set_view if $set_view;
		}
	}
	my $qry = "CREATE TEMPORARY VIEW temp_view AS SELECT * FROM $self->{'system'}->{'view'} v WHERE ";
	my @args;
	use constant OWN_SUBMITTED_ISOLATES => 'v.sender=?';
	use constant OWN_PRIVATE_ISOLATES   => 'EXISTS(SELECT 1 FROM private_isolates WHERE (isolate_id,user_id)=(v.id,?))';
	use constant PUBLIC_ISOLATES_FROM_SAME_USER_GROUP =>    #(where co_curate option set)
	  '(EXISTS(SELECT 1 FROM user_group_members ugm JOIN user_groups ug ON ugm.user_group=ug.id '
	  . 'WHERE ug.co_curate AND ugm.user_id=v.sender AND EXISTS(SELECT 1 FROM user_group_members '
	  . 'WHERE (user_group,user_id)=(ug.id,?))) AND NOT EXISTS(SELECT 1 FROM private_isolates '
	  . 'WHERE isolate_id=v.id))';
	use constant PUBLIC_ISOLATES => 'NOT EXISTS(SELECT 1 FROM private_isolates WHERE isolate_id=v.id)';
	use constant ISOLATES_FROM_USER_PROJECT =>
	  'EXISTS(SELECT 1 FROM project_members pm JOIN merged_project_users mpu ON '
	  . 'pm.project_id=mpu.project_id WHERE (mpu.user_id,pm.isolate_id)=(?,v.id))';
	my $user_info = $self->get_user_info_from_username($username);

	if ( !$user_info ) {                                    #Not logged in
		$qry .= PUBLIC_ISOLATES;
	} else {
		my @user_terms;
		if ($curate) {
			return if $user_info->{'status'} eq 'admin';    #Admin can see everything.
			my $method = {
				submitter => sub {
					@user_terms =
					  ( OWN_SUBMITTED_ISOLATES, OWN_PRIVATE_ISOLATES, PUBLIC_ISOLATES_FROM_SAME_USER_GROUP );
				},
				curator => sub {
					@user_terms = ( PUBLIC_ISOLATES, OWN_PRIVATE_ISOLATES );
				  }
			};
			if ( $method->{ $user_info->{'status'} } ) {
				$method->{ $user_info->{'status'} }->();
			} else {
				return;
			}
		} else {
			@user_terms = (PUBLIC_ISOLATES);

			#Simplify view definition by only looking for private/project isolates if the user has any.
			my $has_private_isolates =
			  $self->run_query( 'SELECT EXISTS(SELECT * FROM private_isolates WHERE user_id=?)', $user_info->{'id'} );
			push @user_terms, OWN_PRIVATE_ISOLATES if $has_private_isolates;
			my $has_user_project =
			  $self->run_query( 'SELECT EXISTS(SELECT * FROM merged_project_users WHERE user_id=?)',
				$user_info->{'id'} );
			push @user_terms, ISOLATES_FROM_USER_PROJECT if $has_user_project;
		}
		local $" = q( OR );
		$qry .= qq(@user_terms);
		my $user_term_count = () = $qry =~ /\?/gx;    #apply list context to capture
		@args = ( $user_info->{'id'} ) x $user_term_count;
	}
	if ($qry) {
		eval { $self->{'db'}->do( $qry, undef, @args ) };
		$logger->error($@) if $@;
		$self->{'system'}->{'view'} = 'temp_view';
	}
	return;
}

sub get_seqbin_stats {
	my ( $self, $isolate_id, $options ) = @_;
	$options = { general => 1 } if ref $options ne 'HASH';
	my $results = {};
	if ( $options->{'general'} ) {
		my ( $seqbin_count, $total_length ) =
		  $self->run_query( 'SELECT contigs,total_length FROM seqbin_stats WHERE isolate_id=?',
			$isolate_id, { cache => 'Datastore::get_seqbin_stats::general' } );
		$results->{'contigs'}      = $seqbin_count // 0;
		$results->{'total_length'} = $total_length // 0;
	}
	if ( $options->{'lengths'} ) {
		my $lengths = $self->run_query(
			'SELECT GREATEST(r.length,length(s.sequence)) FROM sequence_bin s LEFT JOIN '
			  . 'remote_contigs r ON s.id=r.seqbin_id WHERE s.isolate_id=?',
			$isolate_id,
			{ fetch => 'col_arrayref', cache => 'Datastore::get_seqbin_stats::length' }
		);
		if (@$lengths) {
			$results->{'lengths'} = [ sort { $b <=> $a } @$lengths ];
			$results->{'min_length'}     = min @$lengths;
			$results->{'max_length'}     = max @$lengths;
			$results->{'mean_length'} = ceil((sum @$lengths) / scalar @$lengths);
		}
	}
	return $results;
}


1;
