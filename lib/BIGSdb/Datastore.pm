#Written by Keith Jolley
#Copyright (c) 2010-2025, University of Oxford
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
package BIGSdb::Datastore;
use strict;
use warnings;
use 5.010;
use List::MoreUtils qw(any uniq);
use List::Util qw(min max sum);
use Try::Tiny;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Datastore');
use Unicode::Collate;
use JSON;
use File::Path qw(make_path);
use Fcntl qw(:flock);
use Memoize;
memoize('get_geography_coordinates');
memoize('convert_coordinates_to_geography');
use BIGSdb::Exceptions;
use BIGSdb::ClassificationScheme;
use BIGSdb::ClientDB;
use BIGSdb::Locus;
use BIGSdb::Scheme;
use BIGSdb::TableAttributes;
use BIGSdb::Constants qw(:login_requirements :embargo DEFAULT_CODON_TABLE COUNTRIES NULL_TERMS);
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
	BIGSdb::Exception::Database::Connection->throw('Data connector not set up.') if !$self->{'dataConnector'};
	return $self->{'dataConnector'};
}

sub get_isolate_extended_field_attributes {
	my ( $self, $isolate_field, $attribute ) = @_;
	return $self->run_query(
		'SELECT * FROM isolate_field_extended_attributes WHERE (isolate_field,attribute)=(?,?)',
		[ $isolate_field, $attribute ],
		{ fetch => 'row_hashref' }
	);
}

sub get_user_info {
	my ( $self, $id ) = @_;
	my $user_info =
	  $self->run_query( 'SELECT * FROM users WHERE id=?', $id, { fetch => 'row_hashref', cache => 'get_user_info' } );
	if ( $user_info && $user_info->{'user_name'} ) {
		if ( $user_info->{'user_db'} ) {
			my $remote_user = $self->get_remote_user_info( $user_info->{'user_name'}, $user_info->{'user_db'} );
			if ( $remote_user->{'user_name'} ) {
				$user_info->{$_} = $remote_user->{$_} foreach qw(first_name surname email affiliation country sector
				  submission_digests submission_email_cc absent_until);
			}
		} else {
			$user_info->{'submission_email_cc'} = $self->{'config'}->{'submission_email_cc'};
		}
	}
	return $user_info;
}

sub get_user_string {
	my ( $self, $id, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $info = $self->get_user_info($id);
	return 'Undefined user' if !$info;
	my $user = q();
	$info->{'email'} //= q();
	my $use_email =
	  ( $options->{'email'} && $info->{'email'} =~ /@/x )
	  ? 1
	  : 0;    #Not intended to be foolproof check of valid Email but will differentiate 'N/A', ' ', etc.
	$user .= qq(<a href="mailto:$info->{'email'}">) if $use_email && !$options->{'text_email'};
	$user .= qq($info->{'first_name'} )             if $info->{'first_name'};
	$user .= $info->{'surname'}                     if $info->{'surname'};
	$user .= qq( ($info->{'email'}))                if $use_email && $options->{'text_email'};
	$user .= q(</a>)                                if $use_email && !$options->{'text_email'};

	if ( $options->{'affiliation'} && $info->{'affiliation'} ) {
		$info->{'affiliation'} =~ s/^\s*//x;
		$user .= qq(, $info->{'affiliation'});
		if (   $self->{'config'}->{'site_user_country'}
			&& $info->{'country'} )
		{
			( my $stripped_user_country = $info->{'country'} ) =~ s/\s+\[.*?\]$//x;
			if ( $info->{'affiliation'} !~ /$stripped_user_country$/ix ) {
				$user .= qq(, $info->{'country'});
			}
		}
	}
	return $user;
}

sub get_remote_user_info {
	my ( $self, $user_name, $user_db_id, $options ) = @_;
	if ( $options->{'single_lookup'} ) {
		my $user_db   = $self->get_user_db($user_db_id);
		my $user_data = $self->run_query(
			'SELECT user_name,first_name,surname,email,affiliation,country,sector FROM users WHERE user_name=?',
			$user_name, { db => $user_db, fetch => 'row_hashref', cache => "get_remote_user_info:$user_db_id" } );
		my $user_prefs = $self->run_query( 'SELECT * FROM curator_prefs WHERE user_name=?',
			$user_name, { db => $user_db, fetch => 'row_hashref' } );
		foreach my $key ( keys %$user_prefs ) {
			$user_data->{$key} = $user_prefs->{$key};
		}
		return $user_data;
	}
	if ( !$self->{'cache'}->{'remote_user_info'}->{$user_db_id} ) {
		my $user_db = $self->get_user_db($user_db_id);
		my $all_user_data =
		  $self->run_query( 'SELECT user_name,first_name,surname,email,affiliation,country,sector FROM users',
			undef, { db => $user_db, fetch => 'all_arrayref', slice => {} } );
		my $all_user_prefs = $self->run_query( 'SELECT * FROM curator_prefs',
			undef, { db => $user_db, fetch => 'all_arrayref', slice => {} } );
		my $user_prefs = {};
		foreach my $user_pref (@$all_user_prefs) {
			$user_prefs->{ $user_pref->{'user_name'} } = $user_pref;
		}
		my $user_data = {};
		foreach my $user (@$all_user_data) {
			$user_data->{ $user->{'user_name'} } = $user;
			if ( defined $user_prefs->{ $user->{'user_name'} } ) {
				my $this_user_prefs = $user_prefs->{ $user->{'user_name'} };
				foreach my $key ( keys %$this_user_prefs ) {
					$user_data->{ $user->{'user_name'} }->{$key} = $this_user_prefs->{$key};
				}
			}
		}
		$self->{'cache'}->{'remote_user_info'}->{$user_db_id} = $user_data;
	}
	return $self->{'cache'}->{'remote_user_info'}->{$user_db_id}->{$user_name};
}

sub get_user_info_from_username {
	my ( $self, $user_name ) = @_;
	return if !defined $user_name;
	if ( !defined $self->{'cache'}->{'user_name'}->{$user_name} ) {
		my $user_info = $self->run_query( 'SELECT * FROM users WHERE user_name=?',
			$user_name, { fetch => 'row_hashref', cache => 'get_user_info_from_username' } );
		if ( $user_info && $user_info->{'user_db'} ) {
			my $remote_user =
			  $self->get_remote_user_info( $user_name, $user_info->{'user_db'}, { single_lookup => 1 } );
			if ( $remote_user->{'user_name'} ) {
				$user_info->{$_} = $remote_user->{$_} foreach qw(first_name surname email affiliation country sector
				  submission_digests submission_email_cc absent_until);
			}
		}
		$self->{'cache'}->{'user_name'}->{$user_name} = $user_info;
	}
	return $self->{'cache'}->{'user_name'}->{$user_name};
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
	return {} if ( $user_info->{'status'} // q() ) eq 'user';
	if ( $user_info->{'user_db'} ) {
		my $user_db          = $self->get_user_db( $user_info->{'user_db'} );
		my $site_permissions = $self->run_query(
			'SELECT permission FROM permissions WHERE user_name=? AND permission !=?',
			[ $user_name, 'modify_users' ],
			{ db => $user_db, fetch => 'col_arrayref' }
		);
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
				$regex =~ /[^\w\d\-\.\\\/\(\)\+\*\ \$]/x       #reject regex containing any character not in list
				|| $regex =~ /\$\D/x                           #allow only $1, $2 etc. variables
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
			my $locus        = $1;
			my $designations = $self->get_allele_designations( $isolate_id, $locus );
			my @allele_values;
			foreach my $designation (@$designations) {
				my $allele_id = $designation->{'allele_id'};
				$allele_id = $options->{'no_format'} ? 'deleted' : '&Delta;'
				  if ( $allele_id =~ /^del/ix || $allele_id eq '0' );
				if ($regex) {
					my $expression = "\$allele_id =~ $regex";
					eval "$expression";    ## no critic (ProhibitStringyEval)
				}
				$allele_id = qq(<span class="provisional">$allele_id</span>)
				  if $designation->{'status'} eq 'provisional' && !$options->{'no_format'};
				push @allele_values, $allele_id;
			}
			local $" = ',';
			$value .= @allele_values ? "@allele_values" : $empty_value;
			next;
		}
		if ( $field =~ /^s_(\d+)_(.+)/x ) {
			my $scheme_id                   = $1;
			my $scheme_field                = $2;
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
	my $loci_values;
	try {
		$loci_values = $self->get_scheme($scheme_id)->get_profile_by_primary_keys( [$profile_id] );
	} catch {
		if ( $_->isa('BIGSdb::Exception::Database::Configuration') ) {
			$logger->error('Error retrieving information from remote database - check configuration.');
		} else {
			$logger->logdie($_);
		}
	};
	if ( !defined $loci_values ) {
		return $options->{'hashref'} ? {} : [];
	}
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
	my $field_data = [];
	my $scheme;
	try {
		$scheme = $self->get_scheme($scheme_id);
	} catch {
		if ( $_->isa('BIGSdb::Exception::Database::Configuration') ) {
			$logger->warn("Scheme $scheme_id database is not configured correctly");
		} else {
			$logger->logdie($_);
		}
	};
	return                                                                     if !defined $scheme;
	$self->_convert_designations_to_profile_names( $scheme_id, $designations ) if !$options->{'no_convert'};
	{
		try {
			$field_data = $scheme->get_field_values_by_designations($designations);
		} catch {
			if ( $_->isa('BIGSdb::Exception::Database::Configuration') ) {
				$logger->warn("Scheme $scheme_id database is not configured correctly");
			} else {
				$logger->logdie($_);
			}
		};
	}
	return $field_data if $options->{'no_status'};
	my $values = {};
	my $loci   = $self->get_scheme_loci($scheme_id);
	my $fields = $self->get_scheme_fields($scheme_id);
	foreach my $data (@$field_data) {
		my $status = 'confirmed';
	  LOCUS: foreach my $locus (@$loci) {
			next if !defined $designations->{$locus};
		  DESIGNATION: foreach my $designation ( @{ $designations->{$locus} } ) {
				next LOCUS if $designation->{'allele_id'} eq 'N' || $designation->{'allele_id'} eq '0';
				next LOCUS if $designation->{'status'} eq 'confirmed';
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
	my ( $self, $isolate_id, $scheme_id, $options ) = @_;
	if ( $options->{'use_cache'} ) {
		my $table = "temp_isolates_scheme_fields_$scheme_id";
		if ( !defined $self->{'cache'}->{'scheme_table_exists'}->{$scheme_id} ) {
			$self->{'cache'}->{'scheme_table_exists'}->{$scheme_id} =
			  $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );
		}
		if ( $self->{'cache'}->{'scheme_table_exists'}->{$scheme_id} ) {
			my $scheme_values = $self->run_query(
				"SELECT * FROM $table WHERE id=?",
				$isolate_id,
				{
					fetch => 'all_arrayref',
					slice => {},
					cache => 'Datastore::get_scheme_field_values_by_isolate_id::cache_table'
				}
			);
			my $fields      = $self->get_scheme_fields($scheme_id);
			my $return_data = {};
			foreach my $value (@$scheme_values) {
				foreach my $field (@$fields) {
					if ( defined $value->{ lc($field) } ) {

						#Currently no check if any of the alleles are provisional.
						$return_data->{ lc($field) }->{ $value->{ lc($field) } } = 'confirmed';
					}
				}
			}
			return $return_data;
		} else {
			$logger->error("$self->{'instance'}: Cache table for scheme $scheme_id does not exist.");
			return {};
		}
	}
	my $designations = $self->get_scheme_allele_designations( $isolate_id, $scheme_id );
	if ( $options->{'allow_presence'} ) {
		my $present = $self->run_query(
			'SELECT a.locus FROM allele_sequences a JOIN scheme_members s ON a.locus=s.locus '
			  . 'WHERE (a.isolate_id,s.scheme_id)=(?,?)',
			[ $isolate_id, $scheme_id ],
			{ fetch => 'col_arrayref', cache => 'Datastore::get_scheme_field_values_by_isolate_id' }
		);
		foreach my $locus (@$present) {
			next if defined $designations->{$locus};
			$designations->{$locus} = [
				{
					allele_id => 'P',
					status    => 'confirmed'
				}
			];
		}
	}
	return {} if !$designations;
	my $field_values = $self->get_scheme_field_values_by_designations( $scheme_id, $designations, $options );
	return $field_values;
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

sub is_isolate_in_view {
	my ( $self, $view, $isolate_id ) = @_;
	my $result;
	eval {
		$result = $self->run_query( "SELECT EXISTS(SELECT id FROM $view WHERE id=?)",
			$isolate_id, { cache => "is_isolate_in_view::$view" } );
	};
	if ($@) {
		$logger->error($@);
		return;
	}
	return $result;
}

sub provenance_metrics_exist {
	my ($self) = @_;
	my $provenance_metrics_exist;
	my $att    = $self->{'xmlHandler'}->get_all_field_attributes;
	my $fields = $self->{'xmlHandler'}->get_field_list( { show_hidden => 1 } );
	foreach my $field (@$fields) {
		if ( ( $att->{$field}->{'annotation_metric'} // q() ) eq 'yes' ) {
			$provenance_metrics_exist = 1;
			last;
		}
	}
	return $provenance_metrics_exist;
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
	my ( $self, $scheme_id, $designations, $pk_value, $options ) = @_;
	$pk_value //= q();
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $scheme_info      = $self->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $pk               = $scheme_info->{'primary_key'};
	my $loci = $self->run_query( 'SELECT locus FROM scheme_warehouse_indices WHERE scheme_id=? ORDER BY index',
		$scheme_id, { fetch => 'col_arrayref' } );
	my @profile;
	my $empty_profile = 1;
	my $missing_loci  = 0;
	my %missing       = map { $_ => 1 } qw(N 0);

	foreach my $locus (@$loci) {
		push @profile, $designations->{$locus};
		if ( $missing{ ( $designations->{$locus} // 'N' ) } ) {
			$missing_loci++;
		} else {
			$empty_profile = 0;
		}
	}
	if ($empty_profile) {
		return {
			exists => 1,
			msg    => q(You cannot define a profile with every locus set to be an arbitrary value (N).)
		};
	}
	if (   $scheme_info->{'allow_missing_loci'}
		&& defined $scheme_info->{'max_missing'}
		&& $missing_loci > $scheme_info->{'max_missing'} )
	{
		my $plural = $scheme_info->{'max_missing'} == 1 ? 'us' : 'i';
		return { err => 1, msg => qq(This scheme can only have $scheme_info->{'max_missing'} loc$plural missing.) };
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
		next if ( $designations->{$locus} // '' ) eq 'N' && !$options->{'match_missing'};
		my $term = "(profile[$i]=?";
		$term .= " OR profile[$i]='N'" if !$options->{'match_missing'};
		$term .= ')';
		push @locus_temp, $term;
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
			} catch {
				if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
					$logger->warn( $_->error );
				} else {
					$logger->logdie($_);
				}
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
			$self->{'user_dbs'}->{ $config->{'id'} } = {
				db => $self->{'dataConnector'}->get_connection(
					{
						dbase_name => $config->{'dbase_name'},
						host => $config->{'dbase_host'} // $self->{'config'}->{'dbhost'} // $self->{'system'}->{'host'},
						port => $config->{'dbase_port'} // $self->{'config'}->{'dbport'} // $self->{'system'}->{'port'},
						user => $config->{'dbase_user'} // $self->{'config'}->{'dbuser'} // $self->{'system'}->{'user'},
						password => $config->{'dbase_password'} // $self->{'config'}->{'dbpassword'}
						  // $self->{'system'}->{'password'}
					}
				),
				name => $config->{'dbase_name'}
			};
		} catch {
			if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
				$logger->warn( $_->error );
				$self->{'error'} = 'noConnect';
			} else {
				$logger->logdie($_);
			}
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
	return $self->run_query( 'SELECT EXISTS(SELECT * FROM schemes WHERE id=?)',
		$id, { fetch => 'row_array', cache => 'scheme_exists' } );
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
	if ( !defined $self->{'cache'}->{'all_scheme_info'} ) {
		$self->{'cache'}->{'all_scheme_info'} =
		  $self->run_query( 'SELECT * FROM schemes', undef, { fetch => 'all_hashref', key => 'id' } );
	}
	return $self->{'cache'}->{'all_scheme_info'};
}

sub get_scheme_loci {

	#options passed as hashref:
	#analyse_pref: only the loci for which the user has a analysis preference selected will be returned
	#profile_name: to substitute profile field value in query
	#	({profile_name => 1, analysis_pref => 1})
	my ( $self, $scheme_id, $options ) = @_;
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
	my $fields = $self->get_all_scheme_fields;
	return $fields->{$scheme_id} // [];
}

#NOTE: Data are returned in a cached reference that may be needed more than once.  If calling code needs to
#modify returned values then you MUST make a local copy.
sub get_all_scheme_fields {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'all_scheme_fields'} ) {
		my $data = $self->run_query( 'SELECT scheme_id,field FROM scheme_fields ORDER BY field_order,field',
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
		  ? qw(placeholder main_display isolate_display query_field dropdown url)
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
	my $qry_fingerprint = Digest::MD5::md5_hex($qry);
	if ( !defined $self->{'cache'}->{'scheme_list'}->{$qry_fingerprint} ) {
		$self->{'cache'}->{'scheme_list'}->{$qry_fingerprint} =
		  $self->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	}
	my $list          = $self->{'cache'}->{'scheme_list'}->{$qry_fingerprint};
	my $filtered_list = [];
	foreach my $scheme (@$list) {
		$scheme->{'name'} = $scheme->{'set_name'} if $scheme->{'set_name'};
		next if $options->{'analysis_pref'} && !$self->{'prefs'}->{'analysis_schemes'}->{ $scheme->{'id'} };
		push @$filtered_list, $scheme;
	}
	return $filtered_list;
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
	my @args       = ($group_id);
	push @args, $options->{'set_id'} if $options->{'set_id'};
	my $qry = "SELECT scheme_id FROM scheme_group_scheme_members WHERE group_id=?$set_clause "
	  . 'AND scheme_id IN (SELECT scheme_id FROM scheme_members)';
	my $schemes      = $self->run_query( $qry, \@args, { fetch => 'col_arrayref', cache => 'get_schemes_in_group' } );
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
				allow_missing_loci => $attributes->{'allow_missing_loci'},
				allow_presence     => $attributes->{'allow_presence'}
			);
			try {
				$attributes->{'db'} = $self->{'dataConnector'}->get_connection( \%att );
			} catch {
				if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
					$logger->warn( $_->error );
				} else {
					$logger->logdie($_);
				}
			};
		}
		$attributes->{'fields'} = $self->get_scheme_fields($scheme_id);
		$attributes->{'loci'}   = $self->get_scheme_loci( $scheme_id, ( { profile_name => 1, analysis_pref => 0 } ) );
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

sub _write_status_file {
	my ( $self, $status_file, $data ) = @_;
	return if !$status_file;
	my $json = encode_json($data);
	my $file_path;
	if ( $status_file =~ /($self->{'config'}->{'tmp_dir'}\/BIGSdb_\d+_\d+_\d+\.json)/x ) {
		$file_path = $1;    #Untaint.
	} else {
		$logger->error("Invalid status file $status_file");
	}
	open( my $fh, '>', $file_path )
	  || $logger->error("Cannot open $file_path for writing");
	say $fh $json;
	close $fh;
	return;
}

sub _check_isolate_scheme_field_cache_structure {
	my ( $self, $scheme_id ) = @_;
	my $table = "temp_isolates_scheme_fields_$scheme_id";
	return if !$self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );
	my $data = $self->run_query(
		'SELECT column_name, data_type FROM information_schema.columns WHERE (table_schema,table_name)=(?,?)',
		[ 'public', $table ],
		{ fetch => 'all_arrayref', slice => {} }
	);
	my %cols          = map { $_->{'column_name'} => $_->{'data_type'} } @$data;
	my $scheme_fields = $self->get_scheme_fields($scheme_id);
	if ( @$scheme_fields + 1 != keys %cols ) {
		$logger->error("Cache table $table has a different number of fields than the defined scheme.");
		return 1;
	}
	foreach my $field (@$scheme_fields) {
		my $scheme_field_info = $self->get_scheme_field_info( $scheme_id, $field );
		if ( !$cols{ lc $field } ) {
			$logger->error("Scheme field $field does not exist in $table.");
			return 1;
		}
		if ( $cols{ lc $field } ne $scheme_field_info->{'type'} ) {
			my $type = $cols{ lc $field };
			$logger->error("Column $field in $table is $type but in scheme is $scheme_field_info->{'type'}.");
			return 1;
		}
	}
	return;
}

sub create_temp_isolate_scheme_fields_view {
	my ( $self, $scheme_id, $options ) = @_;

	#Create view containing isolate_id and scheme_fields.
	#This view can instead be created as a persistent indexed table using the update_scheme_cache.pl script.
	#This should be done once the scheme size/number of isolates results in a slowdown of queries.
	my $table = "temp_isolates_scheme_fields_$scheme_id";
	my $table_exists =
	  $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );
	if ( !$options->{'cache'} ) {
		return $table if $table_exists;
		my $scheme_info = $self->get_scheme_info($scheme_id);
		if ( $scheme_info->{'allow_presence'} ) {
			$logger->error( "scheme:$scheme_id uses locus presence/absence. Scheme caching must "
				  . 'be enabled for this scheme to return reliable results.' );
		}

		#Using the embedded database function is much quicker for small schemes but does not
		#scale well for large schemes.
		$self->create_temp_scheme_table( $scheme_id, $options );
		eval { $self->{'db'}->do("SELECT create_isolate_scheme_cache($scheme_id,'isolates','true','full')"); };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		}
		$self->{'scheme_not_cached'} = 1;
		return $table;
	}
	if ( $self->_check_isolate_scheme_field_cache_structure($scheme_id) ) {
		$logger->error("Removing and recreating $table.");
		eval { $self->{'db'}->do("DROP TABLE $table") };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			return;
		}
		$table_exists = 0;
	}
	my $scheme_info = $self->get_scheme_info($scheme_id);
	$options->{'status'}->{'stage'} = "Scheme $scheme_id ($scheme_info->{'name'}): importing definitions";
	$self->_write_status_file( $options->{'status_file'}, $options->{'status'} );
	my $scheme_table = $self->create_temp_scheme_table( $scheme_id, $options );
	my $method       = $options->{'method'} // 'full';
	my $isolates     = $self->_get_isolate_ids_for_cache( $scheme_id,
		{ method => $method, cache_type => 'fields', reldate => $options->{'reldate'} } );
	my $scheme_fields = $self->get_scheme_fields($scheme_id);

	if ( !$table_exists ) {
		$options->{'method'} = 'full';
		my @fields;
		foreach my $field (@$scheme_fields) {
			my $field_info = $self->get_scheme_field_info( $scheme_id, $field );
			push @fields, qq($field $field_info->{'type'});
		}
		local $" = q(,);
		eval { $self->{'db'}->do("CREATE TABLE $table (id int,@fields)"); };
		if ($@) {
			$logger->error("Cannot create table $table. $@");
			$self->{'db'}->rollback;
			return;
		}
	}
	local $" = q(,);
	my @placeholders  = ('?') x ( @$scheme_fields + 1 );
	my $last_progress = 0;
	my $i             = 0;
	$options->{'status'}->{'stage'} = "Scheme $scheme_id ($scheme_info->{'name'}): looking up profiles";
	$self->_write_status_file( $options->{'status_file'}, $options->{'status'} );
	eval {
		if ( $options->{'method'} eq 'full' ) {
			$self->{'db'}->do("DELETE FROM $table");
		}
		my $insert_sql = $self->{'db'}->prepare("INSERT INTO $table (id,@$scheme_fields) VALUES (@placeholders)");
		my $delete_sql = $self->{'db'}->prepare("DELETE FROM $table WHERE id=?");
		my @f_values;
		foreach my $scheme_field (@$scheme_fields) {
			my $scheme_field_info = $self->get_scheme_field_info( $scheme_id, $scheme_field );
			push @f_values, "$scheme_field $scheme_field_info->{'type'}";
		}
		foreach my $isolate_id (@$isolates) {
			local $" = q(,);
			my $field_values;
			if ( $scheme_info->{'allow_presence'} ) {
				$field_values = $self->_get_field_values_from_presence_scheme( $isolate_id, $scheme_id );
			} else {

				#We know that the scheme_cache table exists and is up-to-date because we have just
				#created it. We can therefore use an embedded plpgsql function to lookup values
				#directly in the database, which will be quicker and use less memory.
				$field_values = $self->run_query(
					"SELECT @$scheme_fields FROM get_isolate_scheme_fields(?,?) f(@f_values)",
					[ $isolate_id, $scheme_id ],
					{ fetch => 'all_arrayref', slice => {}, cache => "Pg::get_isolate_scheme_fields::$scheme_id" }
				);
			}
			$i++;
			if ( $options->{'method'} =~ /^daily/x ) {
				$delete_sql->execute($isolate_id);
			}
			foreach my $field_value (@$field_values) {
				my @values;
				foreach my $field (@$scheme_fields) {
					push @values, $field_value->{ lc($field) };
				}
				$insert_sql->execute( $isolate_id, @values );
			}
			my $progress = int( $i * 100 / @$isolates );
			if ( $progress > $last_progress ) {
				$options->{'status'}->{'stage_progress'} = $progress;
				$self->_write_status_file( $options->{'status_file'}, $options->{'status'} );
				$last_progress = $progress;
			}
		}
		if ( !$table_exists ) {
			$self->{'db'}->do("GRANT SELECT ON $table TO apache");
		}

		#Check if all indexes are in place - create them if not.
		foreach my $field ( 'id', @$scheme_fields ) {
			if ( !$table_exists || !$self->_index_exists( $table, $field ) ) {
				$self->{'db'}->do("CREATE INDEX ON $table($field)");
			}
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	}
	$self->{'db'}->commit;
	delete $options->{'status'}->{'stage_progress'};
	return $table;
}

sub _get_field_values_from_presence_scheme {
	my ( $self, $isolate_id, $scheme_id ) = @_;
	my $designations = $self->get_scheme_allele_designations( $isolate_id, $scheme_id );
	my $present      = $self->run_query(
		'SELECT a.locus FROM allele_sequences a JOIN scheme_members s ON a.locus=s.locus '
		  . 'WHERE (a.isolate_id,s.scheme_id)=(?,?)',
		[ $isolate_id, $scheme_id ],
		{ fetch => 'col_arrayref', cache => 'Datastore::_get_field_values_from_presence_scheme::presence' }
	);
	foreach my $locus (@$present) {
		next if defined $designations->{$locus};
		$designations->{$locus} = [
			{
				allele_id => 'P',
				status    => 'confirmed'
			}
		];
	}
	return $self->get_scheme_field_values_by_designations( $scheme_id, $designations,
		{ no_status => 1, dont_match_missing_loci => 1 } );
}

#https://stackoverflow.com/questions/45983169/checking-for-existence-of-index-in-postgresql
sub _index_exists {
	my ( $self, $table, $column ) = @_;
	my $qry =
		q[SELECT EXISTS(SELECT a.attname FROM pg_class t,pg_class i,pg_index ix,pg_attribute a WHERE ]
	  . q[t.oid = ix.indrelid AND i.oid = ix.indexrelid AND a.attrelid = t.oid AND a.attnum = ANY(ix.indkey) ]
	  . q[AND t.relkind = 'r' AND t.relname=? AND a.attname=?)];
	return $self->run_query( $qry, [ $table, lc($column) ] );
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
		my $timestamp = BIGSdb::Utils::get_timestamp();
		$table = "${table}_$timestamp";
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
		$self->{'db'}->do("CREATE INDEX ON $table(profile_id)");
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
		if ($@) {
			$logger->error($@);
			$logger->error("Dropping temp table $table.");
			eval { $self->{'db'}->do("DROP TABLE IF EXISTS $table") };
			$logger->error($@) if $@;
		} else {

			#Drop any old temp tables for this scheme that may have persisted due to a lock timeout.
			$self->_delete_temp_tables("temp_cscheme_${cscheme_id}_");
		}
		$self->{'db'}->commit;
		$table = $rename_table;
	}
	return $table;
}

sub create_temp_lincodes_table {
	my ( $self, $scheme_id, $options ) = @_;
	return if !$self->are_lincodes_defined($scheme_id);
	my $table = "temp_lincodes_$scheme_id";
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
		my $timestamp = BIGSdb::Utils::get_timestamp();
		$table = "${table}_$timestamp";
	}
	my $seqdef_scheme_id = $self->get_scheme_info($scheme_id)->{'dbase_id'};
	my $scheme           = $self->get_scheme($scheme_id);
	my $db               = $scheme->get_db;
	my $lincodes         = $self->run_query( 'SELECT profile_id,lincode FROM lincodes WHERE scheme_id=?',
		$seqdef_scheme_id, { db => $db, fetch => 'all_arrayref' } );
	eval {
		$self->{'db'}->do("CREATE $table_type $table (profile_id text, lincode int[])");
		$self->{'db'}->do("COPY $table(profile_id,lincode) FROM STDIN");
		local $" = "\t";
		foreach my $values (@$lincodes) {
			my ( $profile_id, $lincode ) = @$values;
			local $" = q(,);
			$self->{'db'}->pg_putcopydata("$profile_id\t{@$lincode}\n");
		}
		$self->{'db'}->pg_putcopyend;
		$self->{'db'}->do("CREATE INDEX ON $table(profile_id)");
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
		if ($@) {
			$logger->error($@);
			$logger->error("Dropping temp table $table.");
			eval { $self->{'db'}->do("DROP TABLE IF EXISTS $table") };
			$logger->error($@) if $@;
		} else {

			#Drop any old temp tables for this scheme that may have persisted due to a lock timeout.
			$self->_delete_temp_tables("temp_lincodes_${scheme_id}_");
		}
		$self->{'db'}->commit;
		$table = $rename_table;
	}
	return $table;
}

sub get_lincode_value {
	my ( $self, $isolate_id, $scheme_id ) = @_;
	if ( !$self->{'lincode_table'}->{$scheme_id} ) {
		$self->{'lincode_table'}->{$scheme_id} = $self->create_temp_lincodes_table($scheme_id);
	}
	if ( !$self->{'scheme_table'}->{$scheme_id} ) {
		$self->{'scheme_table'}->{$scheme_id} = $self->create_temp_scheme_table($scheme_id);
	}
	if ( !$self->{'scheme_field_table'}->{$scheme_id} ) {
		$self->{'scheme_field_table'}->{$scheme_id} =
		  $self->create_temp_isolate_scheme_fields_view($scheme_id);
	}
	if ( !$self->{'pk'}->{$scheme_id} ) {
		my $scheme_info = $self->get_scheme_info( $scheme_id, { get_pk => 1 } );
		$self->{'pk'}->{$scheme_id} = $scheme_info->{'primary_key'};
		my $scheme_field_info = $self->get_scheme_field_info( $scheme_id, $scheme_info->{'primary_key'} );
		$self->{'pk_type'}->{$scheme_id} = $scheme_field_info->{'type'};
	}
	my $pk_cast =
	  $self->{'pk_type'}->{$scheme_id} eq 'integer'
	  ? "CAST(s.$self->{'pk'}->{$scheme_id} AS text)"
	  : "s.$self->{'pk'}->{$scheme_id}";
	my ($lincode) = $self->run_query(
		"SELECT l.lincode FROM $self->{'lincode_table'}->{$scheme_id} l JOIN "
		  . "$self->{'scheme_field_table'}->{$scheme_id} s ON "
		  . "l.profile_id=$pk_cast JOIN $self->{'scheme_table'}->{$scheme_id} t ON "
		  . "s.$self->{'pk'}->{$scheme_id}=t.$self->{'pk'}->{$scheme_id} WHERE id=? ORDER BY "
		  . 't.missing_loci,l.lincode LIMIT 1',
		$isolate_id,
		{ fetch => 'row_array', cache => "Datastore::get_lincode_value::$scheme_id" }
	);
	return $lincode;
}

sub create_temp_lincode_prefix_values_table {
	my ( $self, $scheme_id, $options ) = @_;
	my $table = "temp_lincode_${scheme_id}_field_values";
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
		my $timestamp = BIGSdb::Utils::get_timestamp();
		$table = "${table}_$timestamp";
	}
	my $scheme_info  = $self->get_scheme_info($scheme_id);
	my $scheme       = $self->get_scheme($scheme_id);
	my $db           = $scheme->get_db;
	my $group_values = $self->run_query(
		'SELECT prefix,field,value FROM lincode_prefixes WHERE scheme_id=?',
		$scheme_info->{'dbase_id'},
		{ db => $db, fetch => 'all_arrayref' }
	);
	eval {
		$self->{'db'}->do("CREATE $table_type $table (prefix text, field text, value text)");
		$self->{'db'}->do("COPY $table(prefix,field,value) FROM STDIN");
		local $" = "\t";
		foreach my $values (@$group_values) {
			$self->{'db'}->pg_putcopydata("@$values\n");
		}
		$self->{'db'}->pg_putcopyend;
		$self->{'db'}->do("CREATE INDEX ON $table(prefix)");
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
		if ($@) {
			$logger->error($@);
			$logger->error("Dropping temp table $table.");
			eval { $self->{'db'}->do("DROP TABLE IF EXISTS $table") };
			$logger->error($@) if $@;
		} else {

			#Drop any old temp tables for this scheme that may have persisted due to a lock timeout.
			$self->_delete_temp_tables("temp_lincode_${scheme_id}_field_values_");
		}
		$self->{'db'}->commit;
		$table = $rename_table;
	}
	return $table;
}

sub _delete_temp_tables {
	my ( $self, $prefix ) = @_;
	my $tables = $self->run_query( 'SELECT table_name FROM information_schema.tables where table_name LIKE ?',
		"$prefix%", { fetch => 'col_arrayref' } );
	eval {
		foreach my $table (@$tables) {
			next if $table !~ /^$prefix\d+$/x;
			$self->{'db'}->do("DROP TABLE $table");
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub create_temp_locus_sequence_variation_tables {
	my ( $self, $options ) = @_;
	my $peptide_variation_table = $self->_create_temp_locus_variation_table( 'peptide', $options );
	my $dna_variation_table     = $self->_create_temp_locus_variation_table( 'dna',     $options );
	return ( $peptide_variation_table, $dna_variation_table );
}

sub _create_temp_locus_variation_table {
	my ( $self, $type, $options ) = @_;
	my $table_type   = 'TEMP TABLE';
	my $table        = "temp_${type}_mutations";
	my $remote_table = "${type}_mutations";
	my $table_exists =
	  $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );
	if ( $options->{'cache'} ) {
		$table_type = 'TABLE';
	} elsif ($table_exists) {
		return $table;
	}
	my $distinct_locus_dbs = $self->run_query( 'SELECT DISTINCT dbase_name FROM loci WHERE dbase_name IS NOT NULL',
		undef, { fetch => 'col_arrayref', slice => {} } );
	my $fields = {
		peptide => [qw(locus reported_position wild_type_aa variant_aa)],
		dna     => [qw(locus reported_position wild_type_nuc variant_nuc)]
	};
	my $attributes = {};
	foreach my $db_name (@$distinct_locus_dbs) {
		my ($example_locus) = $self->run_query( 'SELECT id FROM loci WHERE dbase_name=? LIMIT 1', $db_name );
		my $locus_obj       = $self->get_locus($example_locus);
		my $db              = $locus_obj->{'db'};
		next if !defined $db;
		my $values;
		eval {
			local $" = q(,);
			$values = $self->run_query( "SELECT @{$fields->{$type}} FROM $remote_table",
				undef, { db => $db, fetch => 'all_arrayref' } );
		};
		if ($@) {
			$logger->error($@);
			next;
		}
		foreach my $value (@$values) {
			push @{ $attributes->{ $value->[0] } }, $value;
		}
	}
	my $loci = $self->run_query( 'SELECT id,dbase_id FROM loci WHERE dbase_id IS NOT NULL',
		undef, { fetch => 'all_arrayref', slice => {} } );
	eval {
		if ($table_exists) {
			$self->{'db'}->do("TRUNCATE $table");
		} else {
			$self->{'db'}->do( "CREATE $table_type $table (locus text NOT NULL,reported_position int "
				  . "NOT NULL,$fields->{$type}->[2] text NOT NULL, $fields->{$type}->[3] text NOT NULL)" );
		}
		local $" = q(,);
		$self->{'db'}->do("COPY $table(@{$fields->{$type}}) FROM STDIN");
		foreach my $locus (@$loci) {
			next if !defined $attributes->{ $locus->{'dbase_id'} };
			foreach my $attribute ( @{ $attributes->{ $locus->{'dbase_id'} } } ) {
				local $" = qq(\t);
				$self->{'db'}->pg_putcopydata("$locus->{'id'}\t@$attribute[1,2,3]\n");
			}
		}
		$self->{'db'}->pg_putcopyend;
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return $table;
}

sub create_temp_variation_table {
	my ( $self, $type, $locus, $position ) = @_;
	my $table = "temp_${type}_${locus}_p_${position}";
	$table =~ s/'/_PRIME_/gx;
	$table =~ s/\s/_DASH_/gx;
	my $table_exists =
	  $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=LOWER(?))', $table );
	return $table if $table_exists;
	my ( $char_field, $remote_table, $join_table ) =
	  $type eq 'pm'
	  ? ( 'amino_acid', 'sequences_peptide_mutations', 'peptide_mutations' )
	  : ( 'nucleotide', 'sequences_dna_mutations', 'dna_mutations' );
	my $locus_obj = $self->get_locus($locus);
	my $values    = $self->run_query(
		"SELECT allele_id,$char_field,is_wild_type,is_mutation FROM $remote_table JOIN $join_table ON "
		  . "$remote_table.mutation_id=$join_table.id WHERE ($remote_table.locus,$join_table.reported_position)=(?,?)",
		[ $locus, $position ],
		{ db => $locus_obj->{'db'}, fetch => 'all_arrayref' }
	);
	eval {
		$self->{'db'}
		  ->do( "CREATE TEMP TABLE $table (allele_id text NOT NULL,$char_field text NOT NULL,is_wild_type boolean "
			  . 'NOT NULL,is_mutation boolean NOT NULL,PRIMARY KEY(allele_id))' );
		$self->{'db'}->do("COPY $table(allele_id,$char_field,is_wild_type,is_mutation) FROM STDIN");
		local $" = qq(\t);
		foreach my $value (@$values) {
			$self->{'db'}->pg_putcopydata("@$value\n");
		}
		$self->{'db'}->pg_putcopyend;
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return $table;
}

sub create_temp_locus_extended_attribute_table {
	my ( $self, $options ) = @_;
	my $table_type = 'TEMP TABLE';
	my $table      = 'temp_locus_extended_attributes';
	my $table_exists =
	  $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );
	if ( $options->{'cache'} ) {
		$table_type = 'TABLE';
	} elsif ($table_exists) {
		return $table;
	}
	my $distinct_locus_dbs = $self->run_query( 'SELECT DISTINCT dbase_name FROM loci WHERE dbase_name IS NOT NULL',
		undef, { fetch => 'col_arrayref', slice => {} } );
	my $attributes = {};
	foreach my $db_name (@$distinct_locus_dbs) {
		my ($example_locus) = $self->run_query( 'SELECT id FROM loci WHERE dbase_name=? LIMIT 1', $db_name );
		my $locus_obj       = $self->get_locus($example_locus);
		my $db              = $locus_obj->{'db'};
		next if !defined $db;
		my $values;
		eval {
			$values =
			  $self->run_query(
				'SELECT locus,field,value_format FROM locus_extended_attributes ORDER BY locus,field_order',
				undef, { db => $db, fetch => 'all_arrayref', slice => {} } );
		};
		if ($@) {
			$logger->error($@);
			next;
		}
		foreach my $value (@$values) {
			push @{ $attributes->{ $value->{'locus'} } },
			  {
				field => $value->{'field'},
				type  => $value->{'value_format'}
			  };
		}
	}
	my $loci = $self->run_query( 'SELECT id,dbase_id FROM loci WHERE dbase_id IS NOT NULL',
		undef, { fetch => 'all_arrayref', slice => {} } );
	eval {
		if ($table_exists) {
			$self->{'db'}->do("TRUNCATE $table");
		} else {
			$self->{'db'}->do( "CREATE $table_type $table (locus text NOT NULL,field text "
				  . 'NOT NULL,type text NOT NULL,PRIMARY KEY(locus,field))' );
		}
		$self->{'db'}->do("COPY $table(locus,field,type) FROM STDIN");
		foreach my $locus (@$loci) {
			next if !defined $attributes->{ $locus->{'dbase_id'} };
			foreach my $attribute ( @{ $attributes->{ $locus->{'dbase_id'} } } ) {
				$self->{'db'}->pg_putcopydata("$locus->{'id'}\t$attribute->{'field'}\t$attribute->{'type'}\n");
			}
		}
		$self->{'db'}->pg_putcopyend;
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return $table;
}

sub _write_temp_file {
	my ( $self, $filename, $text ) = @_;
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
	if ( !-e $full_path ) {
		open( my $fh, '>:encoding(utf8)', $full_path ) || $logger->error("Cannot open $full_path for writing");
		say $fh $text;
		close $fh;
	}
	return;
}

sub create_temp_sequence_extended_attributes_table {
	my ( $self, $locus, $field ) = @_;
	my $table = "temp_seq_att_l_${locus}_f_${field}";
	$table =~ s/'/_PRIME_/gx;
	$table =~ s/-/_DASH_/gx;
	$table =~ s/\s/_SPACE_/gx;
	if ( length $table > 60 ) {    #Pg label limit is 63 bytes.
		$table = 'BIGSdb_temp_seq_att_' . Digest::MD5::md5_hex($table);
		$self->_write_temp_file( $table, "$locus:$field" );
	}
	my $table_exists =
	  $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=LOWER(?))', $table );
	return $table if $table_exists;
	my $att_table = $self->create_temp_locus_extended_attribute_table;
	my $type      = $self->run_query( "SELECT type FROM $att_table WHERE (locus,field)=(?,?)", [ $locus, $field ] );

	if ( !$type ) {
		$logger->error("Locus: $locus; Field: $field is not defined");
		return;
	}
	my $locus_obj = $self->get_locus($locus);
	my $values    = $self->run_query(
		'SELECT allele_id,value FROM sequence_extended_attributes WHERE (locus,field)=(?,?)',
		[ $locus, $field ],
		{ db => $locus_obj->{'db'}, fetch => 'all_arrayref' }
	);
	eval {
		$self->{'db'}
		  ->do("CREATE TEMP TABLE $table (allele_id text NOT NULL,value $type NOT NULL,PRIMARY KEY(allele_id))");
		$self->{'db'}->do("COPY $table(allele_id,value) FROM STDIN");
		local $" = qq(\t);
		foreach my $value (@$values) {
			$self->{'db'}->pg_putcopydata("@$value\n");
		}
		$self->{'db'}->pg_putcopyend;
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return $table;
}

sub create_temp_provenance_completion_table {
	my ( $self, $options ) = @_;
	my $att    = $self->{'xmlHandler'}->get_all_field_attributes;
	my $fields = $self->{'xmlHandler'}->get_field_list( { show_hidden => 1 } );
	my @metric_fields;
	foreach my $field (@$fields) {
		next if ( $att->{$field}->{'annotation_metric'} // q() ) ne 'yes';
		push @metric_fields, $field;
	}
	my %null_terms = map { lc($_) => 1 } NULL_TERMS;
	my $table_type = 'TEMP TABLE';
	my $table      = 'temp_provenance_completion';
	my $table_exists =
	  $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );
	if ( $options->{'cache'} ) {
		$table_type = 'TABLE';
	} elsif ($table_exists) {
		return $table;
	}
	my $create_index;
	eval {
		if ($table_exists) {
			$self->{'db'}->do("TRUNCATE $table");
		} else {
			$self->{'db'}->do( "CREATE $table_type $table (id int NOT NULL,field_count int "
				  . 'NOT NULL,score int NOT NULL,PRIMARY KEY(id));' );
			$create_index = 1;    #Do this after adding data otherwise as it will be quicker.
		}
		local $" = q(,);
		my $data = $self->run_query( "SELECT id,@metric_fields FROM $self->{'system'}->{'view'}",
			undef, { fetch => 'all_arrayref', slice => {} } );
		$self->{'db'}->do("COPY $table(id,field_count,score) FROM STDIN");
		foreach my $record (@$data) {
			my $count = 0;
			foreach my $field (@metric_fields) {
				if ( defined $record->{ lc($field) } && !$null_terms{ lc( $record->{ lc($field) } ) } ) {
					$count++;
				}
			}
			my $score = @metric_fields ? int( $count * 100 / @metric_fields ) : 0;
			$self->{'db'}->pg_putcopydata("$record->{'id'}\t$count\t$score\n");
		}
		$self->{'db'}->pg_putcopyend;
		if ($create_index) {
			$self->{'db'}->do("CREATE INDEX ON $table(score)");
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return $table;
}

sub create_temp_cscheme_field_values_table {
	my ( $self, $cscheme_id, $options ) = @_;
	my $table = "temp_cscheme_${cscheme_id}_field_values";
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
		my $timestamp = BIGSdb::Utils::get_timestamp();
		$table = "${table}_$timestamp";
	}
	my $cscheme_info = $self->get_classification_scheme_info($cscheme_id);
	my $cscheme      = $self->get_classification_scheme($cscheme_id);
	my $db           = $cscheme->get_db;
	my $group_values = $self->run_query(
		'SELECT group_id,field,value FROM classification_group_field_values WHERE cg_scheme_id=?',
		$cscheme_info->{'seqdef_cscheme_id'},
		{ db => $db, fetch => 'all_arrayref' }
	);
	eval {
		$self->{'db'}->do("CREATE $table_type $table (group_id int, field text, value text)");
		$self->{'db'}->do("COPY $table(group_id,field,value) FROM STDIN");
		local $" = "\t";
		foreach my $values (@$group_values) {
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
		if ($@) {
			$logger->error($@);
			$logger->error("Dropping temp table $table.");
			eval { $self->{'db'}->do("DROP TABLE IF EXISTS $table") };
			$logger->error($@) if $@;
		} else {

			#Drop any old temp tables for this scheme that may have persisted due to a lock timeout.
			$self->_delete_temp_tables("temp_cscheme_${cscheme_id}_field_values_");
		}
		$self->{'db'}->commit;
		$table = $rename_table;
	}
	return $table;
}

sub create_temp_scheme_table {
	my ( $self, $id, $options ) = @_;
	$self->_check_connection;
	$options = {} if ref $options ne 'HASH';
	my $scheme_info = $self->get_scheme_info($id);
	my $scheme      = $self->get_scheme($id);
	my $scheme_db   = $scheme->get_db;
	if ( !$scheme_db ) {
		$logger->error("No scheme database for scheme $id");
		BIGSdb::Exception::Database::Connection->throw('Database does not exist');
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
		my $timestamp = BIGSdb::Utils::get_timestamp();
		$table = "${table}_$timestamp";
	}
	my $create = "CREATE $table_type $table (";
	my @table_fields;
	foreach my $field (@$fields) {
		my $type = $self->get_scheme_field_info( $id, $field )->{'type'};
		push @table_fields, "$field $type";
	}
	push @table_fields, 'missing_loci int';
	push @table_fields, 'profile text[]';
	my $locus_indices = $scheme->get_locus_indices;
	eval {
		$self->{'db'}->do( 'LOCK TABLE scheme_warehouse_indices;DELETE FROM scheme_warehouse_indices WHERE scheme_id=?',
			undef, $id );
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
	my $data             = $self->run_query(
		"SELECT @$fields,cardinality(array_positions(profile, 'N')),array_to_string(profile,',') "
		  . "FROM mv_scheme_$seqdef_scheme_id",
		undef,
		{ db => $scheme_db, fetch => 'all_arrayref' }
	);
	eval { $self->{'db'}->do("COPY $table(@$fields,missing_loci,profile) FROM STDIN"); };

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
		BIGSdb::Exception::Database::Connection->throw('Cannot put data into temp table');
	}
	$self->_check_connection;
	foreach my $field (@$fields) {
		my $field_info = $self->get_scheme_field_info( $id, $field );
		if ( $field_info->{'type'} eq 'integer' ) {
			$self->{'db'}->do("CREATE INDEX ON $table ($field)");
		} else {
			$self->{'db'}->do("CREATE INDEX ON $table (UPPER($field))");
		}
	}
	$self->{'db'}->do("CREATE INDEX ON $table (missing_loci)");

	#Index up to 3 elements
	my $index_count = keys %$locus_indices >= 3 ? 3 : keys %$locus_indices;
	foreach my $element ( 1 .. $index_count ) {
		$self->{'db'}->do("CREATE INDEX ON $table ((profile[$element]))");
	}

	#Create new temp table, then drop old and rename the new - this
	#should minimize the time that the table is unavailable.
	$self->_check_connection;
	if ( $options->{'cache'} ) {
		eval { $self->{'db'}->do("DROP TABLE IF EXISTS $rename_table; ALTER TABLE $table RENAME TO $rename_table") };
		$logger->error("$self->{'system'}->{'db'}: dropping $rename_table $@") if $@;
		$self->{'db'}->commit;
		$table = $rename_table;
	}
	return $table;
}

sub _check_connection {
	my ($self) = @_;
	return if $self->{'db'} && $self->{'db'}->ping;
	my $db_attributes = $self->{'db_attributes'};
	$self->{'db'} = $self->{'dataConnector'}->get_connection($db_attributes);
	return;
}

#Create table containing isolate_id and count of distinct loci
#This can be used to rapidly search by profile completion
#This table can instead be created as a persistent indexed table using the update_scheme_cache.pl script.
#This should be done once the scheme size/number of isolates results in a slowdown of queries.
sub create_temp_scheme_status_table {
	my ( $self, $scheme_id, $options ) = @_;
	my $table = "temp_isolates_scheme_completion_$scheme_id";
	my $table_exists =
	  $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', $table );
	if ( !$options->{'cache'} ) {
		return $table if $table_exists;

		#Using the embedded database function is much quicker for small schemes but does not
		#scale well for large schemes.
		eval { $self->{'db'}->do("SELECT create_isolate_scheme_status_table($scheme_id,'isolates','true','full')"); };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		}
		return $table;
	}
	my $method   = $options->{'method'} // 'full';
	my $isolates = $self->_get_isolate_ids_for_cache( $scheme_id,
		{ method => $method, cache_type => 'completion', reldate => $options->{'reldate'} } );
	my $scheme_fields = $self->get_scheme_fields($scheme_id);
	if ( !$table_exists ) {
		eval { $self->{'db'}->do("CREATE TABLE $table (id int,locus_count bigint, PRIMARY KEY(id))"); };
		if ($@) {
			$logger->error("Cannot create table $table. $@");
			$self->{'db'}->rollback;
			return;
		}
	}
	my $scheme_info = $self->get_scheme_info($scheme_id);
	$options->{'status'}->{'stage'} = "Scheme $scheme_id ($scheme_info->{'name'}): checking profile completion status";
	$self->_write_status_file( $options->{'status_file'}, $options->{'status'} );
	my $i             = 0;
	my $last_progress = 0;
	my ( $existing, %existing );
	if ( $options->{'method'} =~ /^daily/x ) {
		$existing = $self->run_query( "SELECT id,locus_count FROM $table", undef, { fetch => 'all_arrayref' } );
		%existing = map { $_->[0] => $_->[1] } @$existing;
	}
	eval {
		if ( $options->{'method'} eq 'full' ) {
			$self->{'db'}->do("DELETE FROM $table");
		}
		my $insert_sql =
		  $self->{'db'}
		  ->prepare("INSERT INTO $table (id,locus_count) VALUES (?,?) ON CONFLICT (id) DO UPDATE SET locus_count=?");
		my $delete_sql = $self->{'db'}->prepare("DELETE FROM $table WHERE id=?");
		foreach my $isolate_id (@$isolates) {
			my $count_zero = $scheme_info->{'quality_metric_count_zero'} ? q() : q( AND ad.allele_id <> '0');
			my $count      = $self->run_query(
				q(SELECT COUNT(DISTINCT(ad.locus)) FROM allele_designations ad JOIN scheme_members sm )
				  . qq(ON ad.locus = sm.locus WHERE sm.scheme_id=? AND isolate_id=?$count_zero),
				[ $scheme_id, $isolate_id ],
				{
					cache => 'Datastore::create_temp_scheme_status_table::locus_count_'
					  . ( $scheme_info->{'quality_metric_count_zero'} ? 'zero' : 'nozero' )
				}
			);
			$i++;
			my $progress = int( $i * 100 / @$isolates );
			if ( $progress > $last_progress ) {
				$options->{'status'}->{'stage_progress'} = $progress;
				$self->_write_status_file( $options->{'status_file'}, $options->{'status'} );
				$last_progress = $progress;
			}
			if ( !$count ) {
				if ( $options->{'method'} =~ /^daily/x && $existing{$isolate_id} ) {
					$delete_sql->execute($isolate_id);
				}
				next;
			}
			if (   $options->{'method'} =~ /^daily/x
				&& defined $existing{$isolate_id}
				&& $existing{$isolate_id} == $count )
			{
				next;
			}
			$insert_sql->execute( $isolate_id, $count, $count );
		}
		if ( !$table_exists ) {
			$self->{'db'}->do("CREATE INDEX ON $table(locus_count)");
			$self->{'db'}->do("GRANT SELECT ON $table TO apache");
		}
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	}
	$self->{'db'}->commit;
	delete $options->{'status'}->{'stage_progress'};
	return $table;
}

sub _get_isolate_ids_for_cache {
	my ( $self, $scheme_id, $options ) = @_;
	$options->{'cache_type'} //= 'fields';
	$options->{'method'}     //= 'full';
	my $scheme_info    = $self->get_scheme_info($scheme_id);
	my $view           = $scheme_info->{'view'} // 'isolates';
	my %allowed_method = map { $_ => 1 } qw(full incremental daily daily_replace);
	if ( !$allowed_method{ $options->{'method'} } ) {
		$logger->error("Invalid method: $options->{'method'}.");
		return [];
	}
	my %allowed_cache_type = map { $_ => 1 } qw(fields completion);
	if ( !$allowed_cache_type{ $options->{'cache_type'} } ) {
		$logger->error("Invalid cache type: $options->{'cache_type'}.");
		return [];
	}
	if ( !defined $scheme_id ) {
		$logger->error('No scheme_id passed.');
		return [];
	}
	my %table = (
		fields     => "temp_isolates_scheme_fields_$scheme_id",
		completion => "temp_isolates_scheme_completion_$scheme_id"
	);
	if (
		!$self->run_query(
			'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
			$table{ $options->{'cache_type'} }
		)
	  )
	{
		$options->{'method'} = 'full';
	}
	my $qry = "SELECT t1.id FROM $view t1 ";
	if ( $options->{'method'} eq 'incremental' ) {
		$qry .= qq(LEFT JOIN $table{$options->{'cache_type'}} t2 ON t1.id=t2.id WHERE t2.id IS NULL );
		if ( $options->{'reldate'} && $options->{'reldate'} > 0 ) {
			$qry .= qq(AND datestamp > now()-interval '$options->{'reldate'} days');
		}
	} elsif ( $options->{'method'} eq 'daily' ) {
		$qry .=
			qq(LEFT JOIN $table{$options->{'cache_type'}} t2 ON t1.id=t2.id WHERE t2.id )
		  . q(IS NULL AND t1.datestamp='today' );
	} elsif ( $options->{'method'} eq 'daily_replace' ) {
		$qry .= q(WHERE datestamp = 'today' );
	}
	$qry .= 'ORDER BY t1.id';
	return $self->run_query( $qry, undef, { fetch => 'col_arrayref' } );
}

#This should only be used to create a table of user entered values.
#The table name is hard-coded.
sub create_temp_list_table {
	my ( $self, $data_type, $list_file ) = @_;
	my $pg_data_type = $data_type;
	$pg_data_type = 'geography(POINT, 4326)' if $data_type eq 'geography_point';
	my $table_exists =
	  $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', 'temp_list' );
	if ($table_exists) {
		$logger->info('Table temp_list already exists');
		return;
	}
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$list_file";
	open( my $fh, '<:encoding(utf8)', $full_path ) || $logger->logcarp("Can't open $full_path for reading");
	eval {
		$self->{'db'}->do("CREATE TEMP TABLE temp_list (value $pg_data_type)");
		$self->{'db'}->do('COPY temp_list FROM STDIN');
		while ( my $value = <$fh> ) {
			chomp $value;
			$self->{'db'}->pg_putcopydata("$value\n");
		}
		$self->{'db'}->pg_putcopyend;
	};
	if ($@) {
		$logger->logcarp("Can't put data into temp table: $@");
		$self->{'db'}->rollback;
		BIGSdb::Exception::Database::Connection->throw('Cannot put data into temp table');
	}
	close $fh;
	return;
}

sub create_temp_list_table_from_array {
	my ( $self, $data_type, $list, $options ) = @_;
	my $pg_data_type = $data_type;
	$pg_data_type = 'geography(POINT, 4326)' if $data_type eq 'geography_point';
	my $table = $options->{'table'} // ( 'temp_list' . int( rand(99999999) ) );
	my $db    = $options->{'db'}    // $self->{'db'};
	return
	  if !$options->{'no_check_exists'}
	  && $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)',
		$table, { db => $db } );
	eval {
		$db->do("CREATE TEMP TABLE $table (value $pg_data_type);COPY $table FROM STDIN");
		foreach (@$list) {
			s/\t/    /gx;
			$db->pg_putcopydata("$_\n");
		}
		$db->pg_putcopyend;
	};
	if ($@) {
		$logger->error("Can't put data into temp table: $@");
		$db->rollback;
		BIGSdb::Exception::Database::Connection->throw('Cannot put data into temp table');
	}
	return $table;
}

sub create_temp_combinations_table_from_file {
	my ( $self, $filename ) = @_;
	return
	  if $self->run_query( 'SELECT EXISTS(SELECT * FROM information_schema.tables WHERE table_name=?)', 'count_table' );
	my $full_path = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
	my $pk_type   = $self->{'system'}->{'dbtype'} eq 'isolates' ? 'int' : 'text';
	my $text;
	my $error;
	try {
		$text = BIGSdb::Utils::slurp($full_path);
	} catch {
		if ( $_->isa('BIGSdb::Exception::File::CannotOpen') ) {
			$logger->error("Cannot open $full_path for reading");
		} else {
			$logger->logdie($_);
		}
	};
	return if $error;
	eval {
		$self->{'db'}->do("CREATE TEMP TABLE count_table (id $pk_type,count int)");
		$self->{'db'}->do('COPY count_table(id,count) FROM STDIN');
		local $" = "\t";
		foreach my $row ( split /\n/x, $$text ) {
			my @values = split /\t/x, $row;
			$self->{'db'}->pg_putcopydata("@values\n");
		}
		$self->{'db'}->pg_putcopyend;
		$self->{'db'}->do('CREATE INDEX ON count_table(count)');
	};
	$logger->error($@) if $@;
	return;
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
	if ( ref $info ) {
		$info->{'seqdef_cscheme_id'} //= $cg_scheme_id;
	}
	return $info;
}

sub get_classification_group_fields {
	my ( $self, $cg_scheme_id, $group_id ) = @_;
	my $data = $self->run_query(
		'SELECT cgfv.* FROM classification_group_field_values cgfv JOIN classification_group_fields '
		  . 'cgf ON cgfv.cg_scheme_id=cgf.cg_scheme_id AND cgfv.field=cgf.field WHERE '
		  . '(cgf.cg_scheme_id,group_id)=(?,?) ORDER BY cgf.field_order,cgf.field',
		[ $cg_scheme_id, $group_id ],
		{ fetch => 'all_arrayref', slice => {} }
	);
	my @values;
	foreach my $field (@$data) {
		push @values, qq($field->{'field'}: $field->{'value'});
	}
	local $" = q(; );
	return qq(@values);
}
##############LOCI#####################################################################
#options passed as hashref:
#data_type: only the loci of the specified data_type (DNA or peptide) will be returned
#query_pref: only the loci for which the user has a query field preference selected will be returned
#analysis_pref: only the loci for which the user has an analysis preference selected will be returned
#seq_defined: only the loci for which a database or a reference sequence has been defined will be returned
#do_not_order: don't order
#{ query_pref => 1, analysis_pref => 1, seq_defined => 1, do_not_order => 1 }
sub get_loci {
	my ( $self, $options ) = @_;
	my @clauses;
	if ( $options->{'seq_defined'} ) {
		push @clauses, '(dbase_name IS NOT NULL OR reference_sequence IS NOT NULL)';
	}
	if ( $options->{'set_id'} ) {
		push @clauses,
		  '(id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE '
		  . "set_id=$options->{'set_id'})) OR id IN (SELECT locus FROM set_loci WHERE set_id=$options->{'set_id'}))";
	}
	if ( $options->{'data_type'} ) {
		push @clauses, "(data_type='$options->{'data_type'}')";
	}
	my $clause_string = q();
	if (@clauses) {
		local $" = ' AND ';
		$clause_string = " WHERE @clauses";
	}
	my $qry;
	if ( any { $options->{$_} } qw (query_pref analysis_pref) ) {
		$qry =
		  'SELECT id,scheme_id FROM loci LEFT JOIN scheme_members ON loci.id = scheme_members.locus' . $clause_string;
		if ( !$options->{'do_not_order'} ) {
			$qry .= ' ORDER BY scheme_members.scheme_id,scheme_members.field_order,id';
		}
	} else {
		$qry = "SELECT id FROM loci$clause_string";
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
	my %only_include;
	if ( $options->{'only_include'} ) {
		%only_include = map { $_ => 1 } @{ $options->{'only_include'} };
	}
	my $qry;
	if ( $options->{'set_id'} ) {
		$qry =
			'SELECT loci.id,common_name,set_id,set_name,set_common_name FROM loci LEFT JOIN set_loci ON loci.id='
		  . "set_loci.locus AND set_loci.set_id=$options->{'set_id'} WHERE (id IN (SELECT locus FROM scheme_members "
		  . "WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$options->{'set_id'})) OR id IN "
		  . "(SELECT locus FROM set_loci WHERE set_id=$options->{'set_id'}))";
	} else {
		$qry = 'SELECT id,common_name FROM loci';
	}
	if ( $options->{'locus_curator'} && BIGSdb::Utils::is_int( $options->{'locus_curator'} ) ) {
		$qry .= ( $qry =~ /loci$/x ) ? ' WHERE ' : ' AND ';
		$qry .= "loci.id IN (SELECT locus from locus_curators WHERE curator_id = $options->{'locus_curator'})";
	}
	if ( $options->{'no_required_extended_attributes'} ) {
		$qry .= ( $qry =~ /loci$/x ) ? ' WHERE ' : ' AND ';
		$qry .= 'loci.id NOT IN (SELECT locus from locus_extended_attributes WHERE required)';
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
		next if $options->{'set_id'} && $locus->{'set_id'} && $locus->{'set_id'} != $options->{'set_id'};
		next if $options->{'only_include'} && !$only_include{ $locus->{'id'} };
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
	if ( !defined $locus ) {    #Seeing some errors in the logs but this should not happen.
		$logger->logcarp('No locus passed.');
		return {};
	}
	$self->{'locus_count'}++;

	#Get information for all loci if we're being called multiple times.
	#Cache this information.
	if ( $self->{'locus_count'} > 10 && !$self->{'all_locus_info'} ) {
		$self->{'all_locus_info'} =
		  $self->run_query( 'SELECT * FROM loci', undef, { fetch => 'all_hashref', key => 'id' } );
	}
	my $locus_info;
	if ( $self->{'all_locus_info'} ) {
		$locus_info = $self->{'all_locus_info'}->{$locus};
	} else {
		$locus_info = $self->run_query( 'SELECT * FROM loci WHERE id=?',
			$locus, { fetch => 'row_hashref', cache => 'Datastore::get_locus_info' } );
	}
	if ( $options->{'set_id'} ) {
		my $set_locus = $self->run_query(
			'SELECT * FROM set_loci WHERE set_id=? AND locus=?',
			[ $options->{'set_id'}, $locus ],
			{ fetch => 'row_hashref', cache => 'Datastore::get_locus_info::set_loci' }
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
			} catch {
				if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
					$logger->warn( $_->error );
				} else {
					$logger->logdie($_);
				}
			};
		}
		if ( !defined $attributes->{'id'} ) {
			$logger->error("No locus info retrieved for locus $id");
		}
		eval { $self->{'locus'}->{$id} = BIGSdb::Locus->new(%$attributes); };
		if ($@) {
			$logger->error("Cannot initiate locus $id");
		}
	}
	return $self->{'locus'}->{$id};
}

sub finish_with_locus {

	#Free up memory associated with Locus object if we no longer need it.
	my ( $self, $id ) = @_;
	delete $self->{'locus'}->{$id};
	return;
}

sub finish_with_client_loci {
	my ($self) = @_;
	delete $self->{'locus'};
	return;
}

sub finish_with_client_schemes {
	my ($self) = @_;
	delete $self->{'scheme'};
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
	my $data = $self->run_query( 'SELECT locus,allele_id,status FROM allele_designations WHERE isolate_id=?',
		$isolate_id, { fetch => 'all_arrayref', cache => 'get_all_allele_designations' } );
	my $alleles = {};
	foreach my $designation (@$data) {
		$alleles->{ $designation->[0] }->{ $designation->[1] } = $designation->[2];
	}
	return $alleles;
}

sub get_scheme_allele_designations {
	my ( $self, $isolate_id, $scheme_id, $options ) = @_;
	my $designations;
	if ($scheme_id) {
		my $data = $self->run_query(
			q[SELECT * FROM allele_designations WHERE isolate_id=? AND locus IN (SELECT locus FROM scheme_members ]
			  . q[WHERE scheme_id=?) ORDER BY status,(substring (allele_id, '^[0-9]+'))::int,allele_id],
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
	$self->{'allele_flag_count'}++;
	if ( $self->{'allele_flag_count'} > 10 ) {
		if ( !defined $self->{'cache'}->{'allele_flags'} ) {
			my $flags = $self->run_query( 'SELECT locus,allele_id,flag FROM allele_flags ORDER BY flag',
				undef, { fetch => 'all_arrayref', slice => {} } );
			foreach my $flag (@$flags) {
				push @{ $self->{'cache'}->{'allele_flags'}->{ $flag->{'locus'} }->{ $flag->{'allele_id'} } },
				  $flag->{'flag'};
			}
		}
		return $self->{'cache'}->{'allele_flags'}->{$locus}->{$allele_id} // [];
	}
	return $self->run_query(
		'SELECT flag FROM allele_flags WHERE (locus,allele_id)=(?,?) ORDER BY flag',
		[ $locus, $allele_id ],
		{ fetch => 'col_arrayref', cache => 'get_allele_flags' }
	);
}

sub get_allele_ids {
	my ( $self, $isolate_id, $locus, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $allele_ids = $self->run_query(
		'SELECT allele_id FROM allele_designations WHERE isolate_id=? AND locus=?',
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
	my $set_clause =
	  $options->{'set_id'}
	  ? q[AND (locus IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes ]
	  . qq[WHERE set_id=$options->{'set_id'})) OR locus IN (SELECT locus FROM set_loci WHERE ]
	  . qq[set_id=$options->{'set_id'}))]
	  : q[];
	my $data = $self->run_query( qq(SELECT locus,allele_id FROM allele_designations WHERE isolate_id=? $set_clause),
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
		  . q[allele_id !='N' AND allele_id !='P' UNION SELECT CAST(allele_id AS int) FROM retired_allele_ids ]
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
	if ( !defined $self->{'cache'}->{'client_field_data'} ) {
		my $data = $self->run_query(
			'SELECT locus,client_dbase_id,isolate_field FROM client_dbase_loci_fields WHERE allele_query '
			  . 'ORDER BY client_dbase_id,isolate_field',
			undef,
			{ fetch => 'all_arrayref' }
		);
		foreach my $record (@$data) {
			push @{ $self->{'cache'}->{'client_field_data'}->{ $record->[0] } }, [ $record->[1], $record->[2] ];
		}
	}
	my $client_field_data = $self->{'cache'}->{'client_field_data'}->{$locus} // [];
	my $field_values;
	my $detailed_values;
	my $dl_buffer = q();
	my $td_buffer = q();
	my $i         = 0;
	foreach my $client_field (@$client_field_data) {
		my $field          = $client_field->[1];
		my $client         = $self->get_client_db( $client_field->[0] );
		my $client_db_desc = $self->get_client_db_info( $client_field->[0] )->{'name'};
		my $proceed        = 1;
		my $field_data;
		try {
			$field_data = $client->get_fields( $field, $locus, $allele_id );
		} catch {
			if ( $_->isa('BIGSdb::Exception::Database::Configuration') ) {
				$logger->error( "Can't extract isolate field '$field' FROM client database, make sure the "
					  . "client_dbase_loci_fields table is correctly configured. $@" );
				$proceed = 0;
			} else {
				$logger->logdie($_);
			}
		};
		next if !$proceed;
		next if !@$field_data;
		$dl_buffer .= "<dt>$field</dt>";
		my @values;
		foreach my $data (@$field_data) {
			push @{ $detailed_values->{$client_db_desc}->{$field} },
			  {
				value     => $data->{ lc($field) },
				frequency => $data->{'frequency'}
			  };
			my $value = $data->{ lc($field) };
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
		return { formatted => $td_buffer, values => $field_values, detailed_values => $detailed_values };
	}
	return { formatted => $dl_buffer, values => $field_values, detailed_values => $detailed_values };
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
	if ( !$self->{'cache'}->{'locus_attribute_fields'} ) {
		my $locus_attributes = $self->run_query( 'SELECT locus,field FROM locus_extended_attributes',
			undef, { fetch => 'all_arrayref', slice => {} } );
		foreach my $att (@$locus_attributes) {
			if ( !defined $self->{'cache'}->{'locus_attribute_fields'}->{ $att->{'locus'} } ) {
				$self->{'cache'}->{'locus_attribute_fields'}->{ $att->{'locus'} } = [ $att->{'field'} ];
			} else {
				push @{ $self->{'cache'}->{'locus_attribute_fields'}->{ $att->{'locus'} } }, $att->{'field'};
			}
		}
	}
	my $fields = $self->{'cache'}->{'locus_attribute_fields'}->{$locus} // [];
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
sub _get_ref_db {
	my ($self) = @_;
	my %att = (
		dbase_name => $self->{'config'}->{'ref_db'},
		host       => $self->{'config'}->{'dbhost'}     // $self->{'system'}->{'host'},
		port       => $self->{'config'}->{'dbport'}     // $self->{'system'}->{'port'},
		user       => $self->{'config'}->{'dbuser'}     // $self->{'system'}->{'user'},
		password   => $self->{'config'}->{'dbpassword'} // $self->{'system'}->{'password'},
	);
	my $dbr;
	try {
		$dbr = $self->{'dataConnector'}->get_connection( \%att );
	} catch {
		if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
			$logger->error( $_->error );
		} else {
			$logger->logdie($_);
		}
	};
	return $dbr;
}

sub get_available_refs {
	my ($self) = @_;
	my $dbr = $self->_get_ref_db;
	return [] if !$dbr;
	return $self->run_query( 'SELECT pmid FROM refs ORDER BY pmid', undef, { fetch => 'col_arrayref', db => $dbr } );
}

sub get_available_authors {
	my ($self) = @_;
	my $dbr = $self->_get_ref_db;
	return [] if !$dbr;
	return $self->run_query( 'SELECT surname,initials FROM authors',
		undef, { fetch => 'all_arrayref', slice => {}, db => $dbr } );
}

sub add_author {
	my ( $self, $surname, $initials ) = @_;
	my $dbr = $self->_get_ref_db;
	eval { $dbr->do( 'INSERT INTO authors (surname,initials) VALUES (?,?)', undef, $surname, $initials ); };
	if ($@) {
		$logger->error($@);
		$dbr->rollback;
	} else {
		$dbr->commit;
	}
	return;
}

sub get_author_id {
	my ( $self, $surname, $initials ) = @_;
	my $dbr = $self->_get_ref_db;
	return $self->run_query(
		'SELECT id FROM authors WHERE (surname,initials)=(?,?)',
		[ $surname, $initials ],
		{ cache => 'get_author_id', db => $dbr }
	);
}

sub add_reference {
	my ( $self, $args ) = @_;
	my ( $pmid, $year, $journal, $volume, $pages, $title, $abstract, $author_list ) =
	  @{$args}{qw(pmid year journal volume pages title abstract author_list)};
	my $dbr = $self->_get_ref_db;
	eval {
		$dbr->do( 'INSERT INTO refs (pmid,year,journal,volume,pages,title,abstract) VALUES (?,?,?,?,?,?,?)',
			undef, $pmid, $year, $journal, $volume, $pages, $title, $abstract )
		  or say "Failed to insert id: $pmid!";
		my $pos = 1;
		foreach my $author_id (@$author_list) {
			$dbr->do( 'INSERT INTO refauthors (pmid,author,position) VALUES (?,?,?)', undef, $pmid, $author_id, $pos );
			$pos++;
		}
	};
	if ($@) {
		$logger->error($@);
		$dbr->rollback;
	} else {
		$dbr->commit;
	}
	return;
}

sub get_citation_hash {
	my ( $self, $pmids, $options ) = @_;
	my $citation_ref = {};
	return $citation_ref if !$self->{'config'}->{'ref_db'};
	my $dbr = $self->_get_ref_db;
	return $citation_ref if !$dbr;
	my $list_table = $self->create_temp_list_table_from_array( 'int', $pmids, { db => $dbr, no_check_exists => 1 } );
	my $citation_info =
	  $self->run_query( "SELECT pmid,year,journal,title,volume,pages FROM refs JOIN $list_table l ON refs.pmid=l.value",
		undef, { db => $dbr, fetch => 'all_hashref', key => 'pmid' } );
	my $ref_authors = $self->run_query(
		'SELECT pmid,ARRAY_AGG(author ORDER BY position) AS authors FROM refauthors ra '
		  . "JOIN $list_table l ON ra.pmid=l.value GROUP BY pmid",
		undef,
		{ db => $dbr, fetch => 'all_hashref', key => 'pmid' }
	);
	my $author_info = $self->run_query(
		'SELECT id,surname,initials FROM authors a JOIN refauthors ra ON '
		  . "a.id=ra.author JOIN $list_table l ON ra.pmid=l.value",
		undef,
		{ db => $dbr, fetch => 'all_hashref', key => 'id' }
	);

	foreach my $pmid (@$pmids) {
		if ( !defined $citation_info->{$pmid}->{'year'} && !defined $citation_info->{$pmid}->{'journal'} ) {
			$citation_ref->{$pmid} .= "<a href=\"https://www.ncbi.nlm.nih.gov/pubmed/$pmid\">"
			  if $options->{'link_pubmed'};
			$citation_ref->{$pmid} .= "Pubmed id#$pmid";
			$citation_ref->{$pmid} .= '</a>'                    if $options->{'link_pubmed'};
			$citation_ref->{$pmid} .= ': No details available.' if $options->{'state_if_unavailable'};
			next;
		}
		my ( $author, @author_list );
		if ( $options->{'all_authors'} ) {
			foreach my $author_id ( @{ $ref_authors->{$pmid}->{'authors'} } ) {
				$author = "$author_info->{$author_id}->{'surname'} $author_info->{$author_id}->{'initials'}";
				push @author_list, $author;
			}
			local $" = ', ';
			$author = "@author_list";
		} else {
			if ( defined $ref_authors->{$pmid}->{'authors'} && @{ $ref_authors->{$pmid}->{'authors'} } ) {
				my $surname = $author_info->{ $ref_authors->{$pmid}->{'authors'}->[0] }->{'surname'};
				$author .= ( $surname || 'Unknown' );
				if ( @{ $ref_authors->{$pmid}->{'authors'} } > 1 ) {
					$author .= ' et al.';
				}
			}
		}
		$author ||= 'No authors listed';
		$citation_info->{$pmid}->{'volume'} .= ':' if $citation_info->{$pmid}->{'volume'};
		my $citation;
		{
			no warnings 'uninitialized';
			if ( $options->{'formatted'} ) {
				$citation = "$author ($citation_info->{$pmid}->{'year'}). ";
				$citation .= "$citation_info->{$pmid}->{'title'} "                    if !$options->{'no_title'};
				$citation .= "<a href=\"https://www.ncbi.nlm.nih.gov/pubmed/$pmid\">" if $options->{'link_pubmed'};
				$citation .= "<i>$citation_info->{$pmid}->{'journal'}</i> "
				  . "<b>$citation_info->{$pmid}->{'volume'}</b>$citation_info->{$pmid}->{'pages'}";
				$citation .= '</a>' if $options->{'link_pubmed'};
			} else {
				$citation = "$author $citation_info->{$pmid}->{'year'} ";
				$citation .= "<a href=\"https://www.ncbi.nlm.nih.gov/pubmed/$pmid\">" if $options->{'link_pubmed'};
				$citation .= "$citation_info->{$pmid}->{'journal'} "
				  . "$citation_info->{$pmid}->{'volume'}$citation_info->{$pmid}->{'pages'}";
				$citation .= '</a>' if $options->{'link_pubmed'};
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
				  $options->{'link_pubmed'}
				  ? "<a href=\"https://www.ncbi.nlm.nih.gov/pubmed/$pmid\">$pmid</a>"
				  : $pmid;
			}
		}
	}
	eval { $dbr->do("DROP TABLE $list_table"); };
	$logger->error($@) if $@;
	return $citation_ref;
}

sub create_temp_ref_table {
	my ( $self, $list, $qry_ref ) = @_;
	my %att = (
		dbase_name => $self->{'config'}->{'ref_db'},
		host       => $self->{'config'}->{'dbhost'}     // $self->{'system'}->{'host'},
		port       => $self->{'config'}->{'dbport'}     // $self->{'system'}->{'port'},
		user       => $self->{'config'}->{'dbuser'}     // $self->{'system'}->{'user'},
		password   => $self->{'config'}->{'dbpassword'} // $self->{'system'}->{'password'}
	);
	my $dbr;
	my $continue = 1;
	try {
		$dbr = $self->{'dataConnector'}->get_connection( \%att );
	} catch {
		if ( $_->isa('BIGSdb::Exception::Database::Connection') ) {
			$continue = 0;
			say q(<div class="box" id="statusbad"><p>Cannot connect to reference database!</p></div>);
			$logger->error( $_->error );
		} else {
			$logger->logdie($_);
		}
	};
	return if !$continue;
	my $create =
		'CREATE TEMP TABLE temp_refs (pmid int, year int, journal text, volume text, pages text, title text, '
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
		$count_qry = "SELECT COUNT(*) FROM refs WHERE refs.pubmed_id=? AND isolate_id IN ($isolate_qry)";
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
		my $isolates      = $self->run_query( $count_qry, $pmid, { cache => 'create_temp_ref_table_count' } );
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
	my $function = "BIGSdb::TableAttributes::get_${table}_table_attributes";
	my $attributes;
	eval { $attributes = $self->$function() };
	$logger->logcarp($@) if $@;
	return               if ref $attributes ne 'ARRAY';
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
		  isolate_aliases permissions projects project_members
		  isolate_field_extended_attributes isolate_value_extended_attributes scheme_groups scheme_group_scheme_members
		  scheme_group_group_members pcr pcr_locus probes probe_locus sets set_loci set_schemes set_view
		  isolates history sequence_attributes classification_schemes classification_group_fields
		  retired_isolates user_dbases oauth_credentials eav_fields validation_rules validation_conditions
		  validation_rule_conditions lincode_schemes lincode_fields codon_tables geography_point_lookup
		  curator_configs query_interfaces query_interface_fields embargo_history analysis_fields);
		push @tables, $self->{'system'}->{'view'}
		  ? $self->{'system'}->{'view'}
		  : 'isolates';
	} elsif ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		@tables = qw(users user_groups user_group_members sequences sequence_refs accession loci schemes scheme_members
		  scheme_fields profiles profile_refs permissions client_dbases client_dbase_loci client_dbase_schemes
		  locus_extended_attributes scheme_curators locus_curators locus_descriptions scheme_groups
		  scheme_group_scheme_members scheme_group_group_members client_dbase_loci_fields sets set_loci set_schemes
		  profile_history locus_aliases retired_allele_ids retired_profiles classification_schemes
		  classification_group_fields classification_group_field_values user_dbases locus_links client_dbase_cschemes
		  lincode_schemes lincodes lincode_fields lincode_prefixes sequence_extended_attributes curator_configs
		  peptide_mutations dna_mutations);
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
		  projects project_members isolate_field_extended_attributes
		  isolate_value_extended_attributes scheme_groups scheme_group_scheme_members scheme_group_group_members
		  pcr pcr_locus probes probe_locus accession sequence_flags sequence_attributes history classification_schemes
		  isolates eav_fields validation_rules validation_conditions validation_rule_conditions project_users
		  query_interfaces query_interface_fields);
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

sub get_eav_fields {
	my ($self) = @_;
	return $self->run_query( 'SELECT * FROM eav_fields ORDER BY field_order,field',
		undef, { fetch => 'all_arrayref', slice => {} } );
}

sub get_eav_table {
	my ( $self, $type ) = @_;
	my %table = (
		integer => 'eav_int',
		float   => 'eav_float',
		text    => 'eav_text',
		date    => 'eav_date',
		boolean => 'eav_boolean'
	);
	if ( !$table{$type} ) {
		$logger->error('Invalid EAV type');
		return;
	}
	return $table{$type};
}

sub get_eav_fieldnames {
	my ( $self, $options ) = @_;
	my $no_curate = $options->{'curate'} ? q( WHERE NOT no_curate) : q();
	return $self->run_query( "SELECT field FROM eav_fields$no_curate ORDER BY field_order,field",
		undef, { fetch => 'col_arrayref' } );
}

sub get_eav_field {
	my ( $self, $field ) = @_;
	return $self->run_query( 'SELECT * FROM eav_fields WHERE field=?',
		$field, { fetch => 'row_hashref', cache => 'get_eav_field' } );
}

sub is_eav_field {
	my ( $self, $field ) = @_;
	return $self->run_query( 'SELECT EXISTS(SELECT * FROM eav_fields WHERE field=?)', $field );
}

sub get_eav_field_table {
	my ( $self, $field ) = @_;
	if ( !$self->{'cache'}->{'eav_field_table'}->{$field} ) {
		my $eav_field = $self->get_eav_field($field);
		if ( !$eav_field ) {
			$logger->error("EAV field $field does not exist");
			return;
		}
		my $type  = $eav_field->{'value_format'};
		my $table = $self->get_eav_table($type);
		if ($table) {
			$self->{'cache'}->{'eav_field_table'}->{$field} = $table;
		} else {
			$logger->error("EAV field $field has invalid field type");
			return;
		}
	}
	return $self->{'cache'}->{'eav_field_table'}->{$field};
}

sub get_eav_field_value {
	my ( $self, $isolate_id, $field ) = @_;
	my $table = $self->get_eav_field_table($field);
	return $self->run_query(
		"SELECT value FROM $table WHERE (isolate_id,field)=(?,?)",
		[ $isolate_id, $field ],
		{ cache => "get_eav_field_value::$table" }
	);
}

sub get_analysis_fields {
	my ($self) = @_;
	return $self->run_query( 'SELECT * FROM analysis_fields ORDER BY analysis_name,field_name',
		undef, { fetch => 'all_arrayref', slice => {} } );
}

sub get_analysis_field {
	my ( $self, $analysis, $field ) = @_;
	return $self->run_query(
		'SELECT * FROM analysis_fields WHERE (analysis_name,field_name)=(?,?)',
		[ $analysis, $field ],
		{ fetch => 'row_hashref', cache => 'get_analysis_field' }
	);
}

sub get_login_requirement {
	my ($self) = @_;
	$self->{'system'}->{'dbtype'} //= q();
	if ( $self->{'system'}->{'dbtype'} eq 'job' || $self->{'system'}->{'dbtype'} eq 'rest' ) {
		return NOT_ALLOWED;
	}
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

sub get_embargoed_isolate_count {
	my ( $self, $user_id ) = @_;
	return $self->run_query( 'SELECT COUNT(*) FROM private_isolates pi WHERE user_id=? AND embargo  IS NOT NULL',
		$user_id );
}

#Don't count embargoed isolates
sub get_private_isolate_count {
	my ( $self, $user_id ) = @_;
	return $self->run_query(
		'SELECT COUNT(*) FROM private_isolates pi WHERE user_id=? AND embargo IS NULL AND NOT EXISTS'
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

sub get_username {
	my ($self) = @_;
	return $self->{'username'};
}

sub initiate_view {
	my ( $self, $args ) = @_;
	my ( $username, $curate, $set_id, $original_view ) = @{$args}{qw(username curate set_id original_view)};
	$self->{'username'} = $username;    #Store in datastore for delayed REST calls.
	my $user_info = $self->get_user_info_from_username($username);
	if ( ( $self->{'system'}->{'dbtype'} // '' ) eq 'sequences' ) {
		if ( !$user_info ) {            #Not logged in.
			my $restrict_date = $self->get_date_restriction;
			if ( defined $restrict_date ) {
				my $qry = 'CREATE TEMPORARY VIEW temp_sequences_view AS SELECT * FROM sequences WHERE date_entered<=?';
				eval { $self->{'db'}->do( $qry, undef, $restrict_date ) };
				$logger->error($@) if $@;
				$self->{'system'}->{'temp_sequences_view'} = 'temp_sequences_view';
			}
		}
		$self->{'system'}->{'temp_sequences_view'} //= 'sequences';
		return;
	}
	return                                       if ( $self->{'system'}->{'dbtype'} // '' ) ne 'isolates';
	$self->{'system'}->{'view'} = $original_view if defined $original_view;
	if ( defined $self->{'system'}->{'view'} && $set_id ) {
		if ( $self->{'system'}->{'views'} && BIGSdb::Utils::is_int($set_id) ) {
			my $set_view = $self->run_query( 'SELECT view FROM set_view WHERE set_id=?', $set_id );
			$self->{'system'}->{'view'} = $set_view if $set_view;
		}
	}
	my $qry = "CREATE TEMPORARY VIEW temp_view AS SELECT v.* FROM $self->{'system'}->{'view'} v LEFT JOIN "
	  . 'private_isolates p ON v.id=p.isolate_id WHERE ';
	my @args;
	use constant OWN_SUBMITTED_ISOLATES               => 'v.sender=?';
	use constant OWN_PRIVATE_ISOLATES                 => 'p.user_id=?';
	use constant PUBLIC_ISOLATES_FROM_SAME_USER_GROUP =>                  #(where co_curate option set)
	  '(EXISTS(SELECT 1 FROM user_group_members ugm JOIN user_groups ug ON ugm.user_group=ug.id '
	  . 'WHERE ug.co_curate AND ugm.user_id=v.sender AND EXISTS(SELECT 1 FROM user_group_members '
	  . 'WHERE (user_group,user_id)=(ug.id,?))) AND p.user_id IS NULL)';
	use constant PRIVATE_ISOLATES_FROM_SAME_USER_GROUP =>                 #(where co_curate_private option set)
	  '(EXISTS(SELECT 1 FROM user_group_members ugm JOIN user_groups ug ON ugm.user_group=ug.id '
	  . 'WHERE ug.co_curate_private AND ugm.user_id=v.sender AND EXISTS(SELECT 1 FROM user_group_members '
	  . 'WHERE (user_group,user_id)=(ug.id,?))) AND p.user_id IS NOT NULL)';
	use constant EMBARGOED_ISOLATES         => 'p.embargo IS NOT NULL';
	use constant PUBLIC_ISOLATES            => 'p.user_id IS NULL';
	use constant ISOLATES_FROM_USER_PROJECT =>
	  'EXISTS(SELECT 1 FROM project_members pm JOIN merged_project_users mpu ON '
	  . 'pm.project_id=mpu.project_id WHERE (mpu.user_id,pm.isolate_id)=(?,v.id))';
	use constant PUBLICATION_REQUESTED => 'p.request_publish';
	use constant ALL_ISOLATES          => 'EXISTS(SELECT 1)';

	if ( !$user_info ) {                                                  #Not logged in
		$qry .= PUBLIC_ISOLATES;

		#If login_to_show_after_date is set in bigsdb.conf or config.xml to a valid date, then only
		#include isolates prior to that date unless user is logged in.
		my $restrict_date = $self->get_date_restriction;
		if ( defined $restrict_date ) {
			$qry .= qq( AND v.date_entered<='$restrict_date');
		}
	} else {
		my @user_terms;
		my $has_user_project =
		  $self->run_query( 'SELECT EXISTS(SELECT * FROM merged_project_users WHERE user_id=?)', $user_info->{'id'} );
		if ($curate) {
			my $status = $user_info->{'status'};
			my $method = {
				admin => sub {
					@user_terms = (ALL_ISOLATES);
				},
				submitter => sub {
					@user_terms = (
						OWN_SUBMITTED_ISOLATES, OWN_PRIVATE_ISOLATES,
						PUBLIC_ISOLATES_FROM_SAME_USER_GROUP,
						PRIVATE_ISOLATES_FROM_SAME_USER_GROUP
					);
				},
				private_submitter => sub {
					@user_terms = ( OWN_PRIVATE_ISOLATES, PRIVATE_ISOLATES_FROM_SAME_USER_GROUP );
				},
				curator => sub {
					@user_terms = ( PUBLIC_ISOLATES, OWN_PRIVATE_ISOLATES, EMBARGOED_ISOLATES, PUBLICATION_REQUESTED );
					push @user_terms, ISOLATES_FROM_USER_PROJECT if $has_user_project;
				}
			};
			if ( $status eq 'submitter' ) {
				my $only_private =
				  $self->run_query( 'SELECT EXISTS(SELECT * FROM permissions WHERE (user_id,permission)=(?,?))',
					[ $user_info->{'id'}, 'only_private' ] );
				if ($only_private) {
					$status = 'private_submitter';
				}
			}
			if ( $method->{$status} ) {
				$method->{$status}->();
			} else {
				return;
			}
		} else {
			@user_terms = (PUBLIC_ISOLATES);

			#Simplify view definition by only looking for private/project isolates if the user has any.
			my $has_private_isolates =
			  $self->run_query( 'SELECT EXISTS(SELECT * FROM private_isolates WHERE user_id=?)', $user_info->{'id'} );
			if ($has_private_isolates) {
				push @user_terms, OWN_PRIVATE_ISOLATES;
				$self->{'ajax_load_counts'} = 1;
			}
			if ($has_user_project) {
				push @user_terms, ISOLATES_FROM_USER_PROJECT;
				$self->{'ajax_load_counts'} = 1;
			}
		}
		local $" = q( OR );
		$qry .= qq(@user_terms);
		my $user_term_count = () = $qry =~ /\?/gx;    #apply list context to capture
		@args = ( $user_info->{'id'} ) x $user_term_count;
	}
	eval { $self->{'db'}->do( $qry, undef, @args ) };
	$logger->error($@) if $@;
	$self->{'system'}->{'view'} = 'temp_view';
	return;
}

sub get_date_restriction {
	my ($self) = @_;
	my $date = $self->{'system'}->{'login_to_show_after_date'} // $self->{'config'}->{'login_to_show_after_date'};
	return if !$date;
	if ( !BIGSdb::Utils::is_date($date) ) {
		$logger->error( 'Invalid login_to_show_after_date set. Date can be set in bigsdb.conf or in the database '
			  . 'config.xml file. It must be in yyyy-mm-dd format.' );
		return;
	}
	return $date;
}

sub get_seqbin_stats {
	my ( $self, $isolate_id, $options ) = @_;
	$options = { general => 1 } if ref $options ne 'HASH';
	my $results = {};
	if ( $options->{'general'} ) {
		my ( $seqbin_count, $total_length, $n50, $l50 ) =
		  $self->run_query( 'SELECT contigs,total_length,n50,l50 FROM seqbin_stats WHERE isolate_id=?',
			$isolate_id, { cache => 'Datastore::get_seqbin_stats::general' } );
		$results->{'contigs'}      = $seqbin_count // 0;
		$results->{'total_length'} = $total_length // 0;
		$results->{'n50'}          = $n50          // 0;
		$results->{'l50'}          = $l50          // 0;
	}
	if ( $options->{'lengths'} ) {
		my $lengths = $self->run_query(
			'SELECT GREATEST(r.length,length(s.sequence)) FROM sequence_bin s LEFT JOIN '
			  . 'remote_contigs r ON s.id=r.seqbin_id WHERE s.isolate_id=?',
			$isolate_id,
			{ fetch => 'col_arrayref', cache => 'Datastore::get_seqbin_stats::length' }
		);
		if (@$lengths) {
			$results->{'lengths'}     = [ sort { $b <=> $a } @$lengths ];
			$results->{'min_length'}  = min @$lengths;
			$results->{'max_length'}  = max @$lengths;
			$results->{'mean_length'} = ceil( ( sum @$lengths ) / scalar @$lengths );
		}
	}
	return $results;
}

sub get_start_codons {
	my ( $self, $options ) = @_;
	my %stop_codons     = map { $_ => 1 } qw(TAG TAA TGA);
	my @possible_starts = qw(TTA TTG CTG ATT ATC ATA ATG GTG);
	my %possible        = map { $_ => 1 } @possible_starts;
	my $start_codons    = [];
	if ( $self->{'system'}->{'start_codons'} ) {
		my @codons = split /;/x, $self->{'system'}->{'start_codons'};
		foreach my $codon (@codons) {
			$codon =~ s/^\s+|\s+$//gx;
			if ( $possible{ uc $codon } ) {
				push @$start_codons, uc $codon;
			} else {
				$logger->error("Invalid start codon specified in config.xml - $codon");
			}
		}
	}
	if ( $options->{'isolate_id'} ) {
		my $isolate_codon_table = $self->run_query(
			'SELECT codon_table FROM codon_tables WHERE isolate_id=?',
			$options->{'isolate_id'},
			{ cache => 'Datastore::get_start_codons::get_codon_table' }
		);
		if ( defined $isolate_codon_table ) {
			my $ct = Bio::Tools::CodonTable->new( -id => $isolate_codon_table );
			foreach my $codon (@possible_starts) {
				push @$start_codons, $codon if $ct->is_start_codon($codon);
			}
		}
	}
	if ( !@$start_codons ) {
		$start_codons = [qw(ATG GTG TTG)];
	}
	my %start_codons = map { $_ => 1 } @$start_codons;
	if ( $options->{'locus'} ) {
		my $locus_info = $self->get_locus_info( $options->{'locus'} );
		if ( $locus_info->{'start_codons'} ) {
			my @additional = split /;/x, $locus_info->{'start_codons'};
			foreach my $codon (@additional) {
				$codon =~ s/^\s+|\s+$//gx;
				if ( !$start_codons{ uc $codon } ) {
					if ( $possible{ uc $codon } ) {
						push @$start_codons, uc $codon;
					} else {
						$logger->error(
							"Invalid start codon specified in locus table for locus $options->{'locus'} - $codon");
					}
				}
			}
		}
	}
	@$start_codons = uniq(@$start_codons);
	return $start_codons;
}

sub get_stop_codons {
	my ( $self, $options ) = @_;
	my $codon_table_id = $options->{'codon_table'} // $self->get_codon_table( $options->{'isolate_id'} );
	my $codon_table    = Bio::Tools::CodonTable->new( -id => $codon_table_id );
	my @stops          = $codon_table->revtranslate('*');
	$_ = uc($_) foreach @stops;
	return \@stops;
}

sub get_codon_table {
	my ( $self, $isolate_id ) = @_;
	if ( ( $self->{'system'}->{'alternative_codon_tables'} // q() ) eq 'yes' && $isolate_id ) {
		my $isolate_codon_table = $self->run_query( 'SELECT codon_table FROM codon_tables WHERE isolate_id=?',
			$isolate_id, { cache => 'Datastore::get_codon_table' } );
		if ( $self->{'system'}->{'codon_table'} ) {
			if ( !$self->is_codon_table_valid( $self->{'system'}->{'codon_table'} ) ) {
				$logger->error('Invalid codon table set. Using default table.');
				$self->{'system'}->{'codon_table'} = DEFAULT_CODON_TABLE;
			}
		}
		return $isolate_codon_table // $self->{'system'}->{'codon_table'} // DEFAULT_CODON_TABLE;
	} else {
		if ( defined $self->{'system'}->{'codon_table'} ) {
			if ( !$self->is_codon_table_valid( $self->{'system'}->{'codon_table'} ) ) {
				$logger->error('Invalid codon table set. Using default table.');
				return DEFAULT_CODON_TABLE;
			}
			return $self->{'system'}->{'codon_table'};
		}
		return DEFAULT_CODON_TABLE;
	}
}

sub is_codon_table_valid {
	my ( $self, $codon_table ) = @_;
	my $tables  = Bio::Tools::CodonTable->tables;
	my %allowed = map { $_ => 1 } keys %$tables;
	return $allowed{$codon_table};
}

sub are_lincodes_defined {
	my ( $self, $scheme_id ) = @_;
	if ( !$self->{'cache'}->{'lincodes_defined'} ) {
		my $schemes = $self->run_query( 'SELECT scheme_id FROM lincode_schemes', undef, { fetch => 'col_arrayref' } );
		$self->{'cache'}->{'lincodes_defined'}->{$_} = 1 foreach @$schemes;
	}
	return $self->{'cache'}->{'lincodes_defined'}->{$scheme_id};
}

sub get_geography_coordinates {
	my ( $self, $point ) = @_;
	my ( $long, $lat );
	eval { ( $long, $lat ) = $self->run_query( 'SELECT ST_X(?::geometry),ST_Y(?::geometry)', [ $point, $point ] ); };
	if ($@) {
		$logger->error('Invalid geography coordinate passed.');
		return {};
	}
	return { longitude => $long, latitude => $lat };
}

sub convert_coordinates_to_geography {
	my ( $self, $latitude, $longitude ) = @_;
	my $value;
	eval { $value = $self->run_query( 'SELECT ST_MakePoint(?,?)::geography', [ $longitude, $latitude ] ); };
	if ($@) {
		$logger->error($@);
		return;
	}
	return $value;
}

sub lookup_geography_point {
	my ( $self, $data, $field ) = @_;
	my $country_field = $self->{'system'}->{'country_field'} // 'country';
	if ( !defined $data->{$country_field} ) {
		$logger->error(
			"Field $field has geography_point_lookup set but this requires a field for $country_field to be defined.");
		return;
	}
	my $countries = COUNTRIES;
	if ( !defined $countries->{ $data->{$country_field} }->{'iso2'} ) {
		$logger->error("No iso2 country code defined for $data->{'country'}");
		return;
	}

	#Match using exact lookups as well as case-insensitive. We need to be careful using just the latter due
	#to potential issues with unicode characters.
	my ( $long, $lat ) = $self->run_query(
		'SELECT ST_X(location::geometry),ST_Y(location::geometry) FROM geography_point_lookup '
		  . 'WHERE (country_code,field,value)=(?,?,?) OR (country_code,field,UPPER(value))=(?,?,UPPER(?))',
		[
			$countries->{ $data->{$country_field} }->{'iso2'},
			$field, $data->{$field}, $countries->{ $data->{$country_field} }->{'iso2'},
			$field, $data->{$field}
		]
	);
	return { longitude => $long, latitude => $lat };
}

#Currently only for geography_point values.
sub field_needs_conversion {
	my ( $self, $field ) = @_;
	my %conversion_types = map { $_ => 1 } qw(geography_point);
	if ( !defined $self->{'cache'}->{'fields_needing_value_conversion'} ) {
		$self->{'cache'}->{'fields_needing_value_conversion'} = {};
		my $atts = $self->{'xmlHandler'}->get_all_field_attributes;
		foreach my $field ( keys %$atts ) {
			if ( $conversion_types{ $atts->{$field}->{'type'} } ) {
				$self->{'cache'}->{'fields_needing_value_conversion'}->{$field} = 1;
			}
		}
	}
	return $self->{'cache'}->{'fields_needing_value_conversion'}->{$field};
}

sub convert_field_value {
	my ( $self, $field, $value ) = @_;
	if ( !defined $self->{'cache'}->{'field_types'} ) {
		my $atts = $self->{'xmlHandler'}->get_all_field_attributes;
		foreach my $field ( keys %$atts ) {
			$self->{'cache'}->{'field_types'}->{$field} = $atts->{$field}->{'type'} // 'text';
		}
	}
	my %conversion = (
		geography_point => sub {
			return q() if !defined $value || $value eq q();
			my $coordinates = $self->get_geography_coordinates($value);
			return qq($coordinates->{'latitude'}, $coordinates->{'longitude'});
		}
	);
	if ( $conversion{ $self->{'cache'}->{'field_types'}->{$field} } ) {
		return $conversion{ $self->{'cache'}->{'field_types'}->{$field} }->();
	}
	return $value;
}

sub define_missing_allele {
	my ( $self, $locus, $allele ) = @_;
	my $seq;
	if    ( $allele eq '0' ) { $seq = 'null allele' }
	elsif ( $allele eq 'N' ) { $seq = 'arbitrary allele' }
	elsif ( $allele eq 'P' ) { $seq = 'locus is present' }
	else                     { return }
	my $sql =
	  $self->{'db'}
	  ->prepare( 'INSERT INTO sequences (locus, allele_id, sequence, sender, curator, date_entered, datestamp, '
		  . 'status) VALUES (?,?,?,?,?,?,?,?)' );
	eval { $sql->execute( $locus, $allele, $seq, 0, 0, 'now', 'now', '' ) };

	if ($@) {
		$logger->error($@) if $@;
		$self->{'db'}->rollback;
		return;
	}
	$self->{'db'}->commit;
	return;
}

sub get_seqbin_count {
	my ($self) = @_;
	if ( defined $self->{'cache'}->{'seqbin_count'} ) {
		return $self->{'cache'}->{'seqbin_count'};
	}
	$self->{'cache'}->{'seqbin_count'} =
	  $self->run_query("SELECT COUNT(*) FROM $self->{'system'}->{'view'} v JOIN seqbin_stats s ON v.id=s.isolate_id");
	return $self->{'cache'}->{'seqbin_count'};
}

sub get_embargo_attributes {
	my ($self) = @_;
	my $embargo_enabled;
	$embargo_enabled = 1 if ( $self->{'system'}->{'embargo_enabled'} // q() ) eq 'yes';
	$embargo_enabled = 0 if ( $self->{'system'}->{'embargo_enabled'} // q() ) eq 'no';
	$embargo_enabled //= $self->{'config'}->{'embargo_enabled'} // 0;
	my $default_embargo = $self->{'system'}->{'default_embargo'} // $self->{'config'}->{'default_embargo'}
	  // DEFAULT_EMBARGO;
	if ( !BIGSdb::Utils::is_int($default_embargo) || $default_embargo <= 0 ) {
		$logger->error("Invalid value set for default_embargo: $default_embargo (embargo disabled).");
		$embargo_enabled = 0;
		$default_embargo = 0;
	}
	my $max_embargo = $self->{'system'}->{'max_embargo'} // $self->{'config'}->{'max_embargo'} // MAX_EMBARGO;
	if ( !BIGSdb::Utils::is_int($max_embargo) || $max_embargo < 0 ) {
		$logger->error(
			'Invalid value set for max_embargo: ' . "$max_embargo (using default embargo value: $default_embargo)." );
		$max_embargo = $default_embargo;
	}
	if ( $default_embargo > $max_embargo ) {
		$logger->error( "default_embargo ($default_embargo) is larger than max_embargo "
			  . "($max_embargo). Setting to max_embargo ($max_embargo)." );
		$default_embargo = $max_embargo;
	}
	my $max_initial_embargo = $self->{'system'}->{'max_initial_embargo'} // $self->{'config'}->{'max_initial_embargo'}
	  // MAX_INITIAL_EMBARGO;
	if ( !BIGSdb::Utils::is_int($max_initial_embargo) || $max_initial_embargo < 0 ) {
		$logger->error(
			"Invalid value set for max_initial_embargo: $max_initial_embargo (using default embargo: $default_embargo)."
		);
		$max_initial_embargo = $default_embargo;
	}
	if ( $max_initial_embargo < $default_embargo ) {
		$logger->error( "max_initial_embargo ($max_initial_embargo) is smaller than default embargo "
			  . "($default_embargo). Setting to default embargo ($default_embargo)." );
		$max_initial_embargo = $default_embargo;
	}
	if ( $max_initial_embargo > $max_embargo ) {
		$logger->error( "max_initial_embargo ($max_initial_embargo) is larger than max embargo "
			  . "($max_embargo). Setting to max embargo ($max_embargo)." );
		$max_initial_embargo = $max_embargo;
	}
	return {
		embargo_enabled     => $embargo_enabled,
		default_embargo     => $default_embargo,
		max_initial_embargo => $max_initial_embargo,
		max_embargo         => $max_embargo
	};
}
1;
