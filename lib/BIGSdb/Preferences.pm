#Written by Keith Jolley
#Copyright (c) 2010-2013, University of Oxford
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
package BIGSdb::Preferences;
use strict;
use warnings;
use 5.010;
use Log::Log4perl qw(get_logger);
use Data::UUID;
my $logger = get_logger('BIGSdb.Prefs');

sub new {    ## no critic (RequireArgUnpacking)
	my $class = shift;
	my $self  = {@_};
	$self->{'sql'} = {};
	return if !$self->{'db'};
	bless( $self, $class );
	$logger->info("Prefstore set up.");
	return $self;
}

sub DESTROY {
	$logger->info("Prefstore destroyed");
	return;
}

sub finish_statement_handles {
	my ($self) = @_;
	foreach ( keys %{ $self->{'sql'} } ) {
		$self->{'sql'}->{$_}->finish() if $self->{'sql'}->{$_};
		$logger->info("Statement handle '$_' destroyed.");
	}
	return;
}

sub _guid_exists {
	my ( $self, $guid ) = @_;
	if ( !$self->{'sql'}->{'guid_exists'} ) {
		$self->{'sql'}->{'guid_exists'} = $self->{'db'}->prepare("SELECT guid FROM guid WHERE guid=?");
	}
	my $exists;
	eval {
		$self->{'sql'}->{'guid_exists'}->execute($guid);
		($exists) = $self->{'sql'}->{'guid_exists'}->fetchrow_array();
	};
	if ($@) {
		throw BIGSdb::PrefstoreConfigurationException("Can't execute guid check");
		$logger->error("Can't execute guid check");
	}
	return $exists;
}

sub _add_existing_guid {
	my ( $self, $guid ) = @_;
	if ( !$self->{'sql'}->{'add_existing_guid'} ) {
		$self->{'sql'}->{'add_existing_guid'} = $self->{'db'}->prepare("INSERT INTO guid (guid,last_accessed) VALUES (?,?)");
	}
	eval {
		$self->{'sql'}->{'add_existing_guid'}->execute( $guid, 'today' );
		$self->{'db'}->commit;
	};
	if ($@) {
		throw BIGSdb::PrefstoreConfigurationException("Can't insert existing guid");
		$logger->error("Can't insert existing guid");
	}
	return;
}

sub get_new_guid {
	my ($self) = @_;
	my $ug = Data::UUID->new;
	if ( !$self->{'sql'}->{'new_guid'} ) {
		$self->{'sql'}->{'new_guid'} = $self->{'db'}->prepare("INSERT INTO guid (guid,last_accessed) VALUES (?,?)");
		$logger->debug("Statement handle 'new_guid' prepared.");
	}
	my $guid = $ug->create_str();
	eval {
		$self->{'sql'}->{'new_guid'}->execute( $guid, 'today' );
		$self->{'db'}->commit;
	};
	if ($@) {
		$logger->error($@);
		throw BIGSdb::PrefstoreConfigurationException("Can't create new guid. $@");
	}
	return $guid;
}

sub _general_attribute_exists {
	my ( $self, @values ) = @_;
	if ( !$self->{'sql'}->{'general_attribute_exists'} ) {
		$self->{'sql'}->{'general_attribute_exists'} =
		  $self->{'db'}->prepare("SELECT count(*) FROM general WHERE guid=? AND dbase=? and attribute=?");
	}
	my $exists;
	eval {
		$self->{'sql'}->{'general_attribute_exists'}->execute(@values);
		($exists) = $self->{'sql'}->{'general_attribute_exists'}->fetchrow_array();
	};
	if ($@) {
		$logger->error("Can't execute attribute check");
		throw BIGSdb::PrefstoreConfigurationException("Can't execute attribute check");
	}
	return $exists;
}

sub _field_attribute_exists {
	my ( $self, @values ) = @_;
	if ( !$self->{'sql'}->{'field_attribute_exists'} ) {
		$self->{'sql'}->{'field_attribute_exists'} =
		  $self->{'db'}->prepare("SELECT count(*) FROM field WHERE guid=? AND dbase=? AND field=? AND action=?");
	}
	my $exists;
	eval {
		$self->{'sql'}->{'field_attribute_exists'}->execute(@values);
		($exists) = $self->{'sql'}->{'field_attribute_exists'}->fetchrow_array();
	};
	if ($@) {
		$logger->error("Can't execute attribute check");
		throw BIGSdb::PrefstoreConfigurationException("Can't execute attribute check");
	}
	return $exists;
}

sub _locus_attribute_exists {
	my ( $self, @values ) = @_;
	if ( !$self->{'sql'}->{'locus_attribute_exists'} ) {
		$self->{'sql'}->{'locus_attribute_exists'} =
		  $self->{'db'}->prepare("SELECT count(*) FROM locus WHERE guid=? AND dbase=? AND locus=? AND action=?");
	}
	my $exists;
	eval {
		$self->{'sql'}->{'locus_attribute_exists'}->execute(@values);
		($exists) = $self->{'sql'}->{'locus_attribute_exists'}->fetchrow_array();
	};
	if ($@) {
		$logger->error("Can't execute attribute check");
		throw BIGSdb::PrefstoreConfigurationException("Can't execute attribute check");
	}
	return $exists;
}

sub _scheme_field_attribute_exists {
	my ( $self, @values ) = @_;
	if ( !$self->{'sql'}->{'scheme_field_attribute_exists'} ) {
		$self->{'sql'}->{'scheme_field_attribute_exists'} =
		  $self->{'db'}->prepare("SELECT count(*) FROM scheme_field WHERE guid=? AND dbase=? AND scheme_id=? AND field=? AND action=?");
	}
	my $exists;
	eval {
		$self->{'sql'}->{'scheme_field_attribute_exists'}->execute(@values);
		($exists) = $self->{'sql'}->{'scheme_field_attribute_exists'}->fetchrow_array();
	};
	if ($@) {
		$logger->error("Can't execute attribute check $@");
		throw BIGSdb::PrefstoreConfigurationException("Can't execute attribute check");
	}
	return $exists;
}

sub _scheme_attribute_exists {
	my ( $self, @values ) = @_;
	if ( !$self->{'sql'}->{'scheme_attribute_exists'} ) {
		$self->{'sql'}->{'scheme_attribute_exists'} =
		  $self->{'db'}->prepare("SELECT count(*) FROM scheme WHERE guid=? AND dbase=? AND scheme_id=? AND action=?");
	}
	my $exists;
	eval {
		$self->{'sql'}->{'scheme_attribute_exists'}->execute(@values);
		($exists) = $self->{'sql'}->{'scheme_attribute_exists'}->fetchrow_array();
	};
	if ($@) {
		$logger->error("Can't execute attribute check $@");
		throw BIGSdb::PrefstoreConfigurationException("Can't execute attribute check");
	}
	return $exists;
}

sub _plugin_attribute_exists {
	my ( $self, @values ) = @_;
	if ( !$self->{'sql'}->{'plugin_attribute_exists'} ) {
		$self->{'sql'}->{'plugin_attribute_exists'} =
		  $self->{'db'}->prepare("SELECT count(*) FROM plugin WHERE guid=? AND dbase=? AND plugin=? AND attribute=?");
	}
	my $exists;
	eval {
		$self->{'sql'}->{'plugin_attribute_exists'}->execute(@values);
		($exists) = $self->{'sql'}->{'plugin_attribute_exists'}->fetchrow_array();
	};
	if ($@) {
		$logger->error("Can't execute plugin attribute check $@");
		throw BIGSdb::PrefstoreConfigurationException("Can't execute plugin attribute check");
	}
	return $exists;
}

sub set_general {
	my ( $self, $guid, $dbase, $attribute, $value ) = @_;
	if ( !$self->_guid_exists($guid) ) {
		$self->_add_existing_guid($guid);
	}
	if ( $self->_general_attribute_exists( $guid, $dbase, $attribute ) ) {
		if ( !$self->{'sql'}->{'update_general'} ) {
			$self->{'sql'}->{'update_general'} =
			  $self->{'db'}->prepare("UPDATE general SET value=? where guid=? AND dbase=? AND attribute=?");
		}
		eval {
			$self->{'sql'}->{'update_general'}->execute( $value, $guid, $dbase, $attribute );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not insert prefs values $@");
			throw BIGSdb::PrefstoreConfigurationException("Could not insert prefs values");
		}
	} else {
		if ( !$self->{'sql'}->{'set_general'} ) {
			$self->{'sql'}->{'set_general'} = $self->{'db'}->prepare("INSERT INTO general (guid,dbase,attribute,value) VALUES (?,?,?,?)");
		}
		eval {
			$self->{'sql'}->{'set_general'}->execute( $guid, $dbase, $attribute, $value );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not insert prefs values $@");
			throw BIGSdb::PrefstoreConfigurationException("Could not insert prefs values");
		}
	}
	$logger->debug("Set pref: $attribute => $value");
	return;
}

sub get_all_general_prefs {
	my ( $self, $guid, $dbase ) = @_;
	throw BIGSdb::DatabaseNoRecordException("No guid passed")
	  if !$guid;
	my $sql = $self->{'db'}->prepare("SELECT attribute,value FROM general WHERE guid=? AND dbase=?");
	my $values;
	eval {
		$sql->execute( $guid, $dbase );
		while ( my ( $attribute, $value ) = $sql->fetchrow_array ) {
			$values->{$attribute} = $value;
		}
	};
	if ($@) {
		$logger->error($@);
		throw BIGSdb::DatabaseNoRecordException("Can't execute get_all_general attribute query");
	}
	return $values;
}

sub get_general_pref {
	my ( $self, $guid, $dbase, $attribute ) = @_;
	throw BIGSdb::DatabaseNoRecordException("No guid passed")
	  if !$guid;
	my $sql = $self->{'db'}->prepare("SELECT value FROM general WHERE guid=? AND dbase=? AND attribute=?");
	eval { $sql->execute( $guid, $dbase, $attribute ) };
	$logger->error($@) if $@;
	my ($value) = $sql->fetchrow_array;
	return $value;
}

sub get_all_field_prefs {
	my ( $self, $guid, $dbase ) = @_;
	throw BIGSdb::DatabaseNoRecordException("No guid passed")
	  if !$guid;
	my $sql = $self->{'db'}->prepare("SELECT field,action,value FROM field WHERE guid=? AND dbase=?");
	my $values;
	eval {
		$sql->execute( $guid, $dbase );
		while ( my ( $field, $action, $value ) = $sql->fetchrow_array() ) {
			$values->{$field}->{$action} = $value ? 1 : 0;
		}
	};
	if ($@) {
		$logger->error("Can't execute get_all_field attribute query");
		throw BIGSdb::DatabaseNoRecordException("Can't execute get_all_field attribute query");
	}
	return $values;
}

sub get_all_locus_prefs {
	my ( $self, $guid, $dbname ) = @_;
	throw BIGSdb::DatabaseNoRecordException("No guid passed")
	  if !$guid;
	my $prefs;
	my $sql = $self->{'db'}->prepare("SELECT locus,action,value FROM locus WHERE guid=? AND dbase=?");
	eval { $sql->execute( $guid, $dbname ); };
	if ($@) {
		$logger->error("Can't execute pref query $@");
	}
	while ( my ( $locus, $action, $value ) = $sql->fetchrow_array ) {
		$prefs->{$locus}->{$action} = $value;
	}
	return $prefs;
}

sub set_field {
	my ( $self, $guid, $dbase, $field, $action, $value ) = @_;
	if ( !$self->_guid_exists($guid) ) {
		$self->_add_existing_guid($guid);
	}
	if ( $self->_field_attribute_exists( $guid, $dbase, $field, $action ) ) {
		if ( !$self->{'sql'}->{'update_field'} ) {
			$self->{'sql'}->{'update_field'} =
			  $self->{'db'}->prepare("UPDATE field SET value=? where guid=? AND dbase=? AND field=? AND action=?");
		}
		eval {
			$self->{'sql'}->{'update_field'}->execute( $value, $guid, $dbase, $field, $action );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not insert prefs values");
			throw BIGSdb::PrefstoreConfigurationException("Can't execute set field attribute query");
		}
	} else {
		if ( !$self->{'sql'}->{'set_field'} ) {
			$self->{'sql'}->{'set_field'} = $self->{'db'}->prepare("INSERT INTO field (guid,dbase,field,action,value) VALUES (?,?,?,?,?)");
		}
		eval {
			$self->{'sql'}->{'set_field'}->execute( $guid, $dbase, $field, $action, $value );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not insert prefs values");
			throw BIGSdb::PrefstoreConfigurationException("Could not insert prefs values");
		}
	}
	$logger->debug("Set pref: $field $action => $value");
	return;
}

sub set_locus {
	my ( $self, $guid, $dbase, $locus, $action, $value ) = @_;
	if ( !$self->_guid_exists($guid) ) {
		$self->_add_existing_guid($guid);
	}
	if ( $self->_locus_attribute_exists( $guid, $dbase, $locus, $action ) ) {
		if ( !$self->{'sql'}->{'update_locus'} ) {
			$self->{'sql'}->{'update_locus'} =
			  $self->{'db'}->prepare("UPDATE locus SET value=? where guid=? AND dbase=? AND locus=? AND action=?");
		}
		eval {
			$self->{'sql'}->{'update_locus'}->execute( $value, $guid, $dbase, $locus, $action );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not insert prefs values");
			throw BIGSdb::PrefstoreConfigurationException("Can't insert prefs values");
		}
	} else {
		if ( !$self->{'sql'}->{'set_locus'} ) {
			$self->{'sql'}->{'set_locus'} = $self->{'db'}->prepare("INSERT INTO locus (guid,dbase,locus,action,value) VALUES (?,?,?,?,?)");
		}
		eval {
			$self->{'sql'}->{'set_locus'}->execute( $guid, $dbase, $locus, $action, $value );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not insert prefs values: $@");
			throw BIGSdb::PrefstoreConfigurationException("Could not insert prefs values");
		}
	}
	$logger->debug("Set pref: $locus $action => $value");
	return;
}

sub set_scheme {
	my ( $self, $guid, $dbase, $scheme_id, $action, $value ) = @_;
	local $" = ', ';
	if ( !$self->_guid_exists($guid) ) {
		$self->_add_existing_guid($guid);
	}
	if ( $self->_scheme_attribute_exists( $guid, $dbase, $scheme_id, $action ) ) {
		if ( !$self->{'sql'}->{'update_scheme'} ) {
			$self->{'sql'}->{'update_scheme'} =
			  $self->{'db'}->prepare("UPDATE scheme SET value=? where guid=? AND dbase=? AND scheme_id=? AND action=?");
		}
		eval {
			$self->{'sql'}->{'update_scheme'}->execute( $value, $guid, $dbase, $scheme_id, $action );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not insert prefs values");
			throw BIGSdb::PrefstoreConfigurationException("Can't insert prefs values");
		}
	} else {
		if ( !$self->{'sql'}->{'set_scheme'} ) {
			$self->{'sql'}->{'set_scheme'} =
			  $self->{'db'}->prepare("INSERT INTO scheme (guid,dbase,scheme_id,action,value) VALUES (?,?,?,?,?)");
		}
		eval {
			$self->{'sql'}->{'set_scheme'}->execute( $guid, $dbase, $scheme_id, $action, $value );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not insert prefs values: $@");
			throw BIGSdb::PrefstoreConfigurationException("Could not insert prefs values");
		}
	}
	$logger->debug("Set pref: scheme_id $action => $value");
	return;
}

sub set_scheme_field {
	my ( $self, $args ) = @_;
	my ( $guid, $dbase, $scheme_id, $field, $action, $value ) = @{$args}{qw(guid dbase scheme_id field action value)};
	local $" = ', ';
	if ( !$self->_guid_exists($guid) ) {
		$self->_add_existing_guid($guid);
	}
	if ( $self->_scheme_field_attribute_exists( $guid, $dbase, $scheme_id, $field, $action ) ) {
		if ( !$self->{'sql'}->{'update_scheme_field'} ) {
			$self->{'sql'}->{'update_scheme_field'} =
			  $self->{'db'}->prepare("UPDATE scheme_field SET value=? where guid=? AND dbase=? AND scheme_id=? AND field=? AND action=?");
		}
		eval {
			$self->{'sql'}->{'update_scheme_field'}->execute( $value, $guid, $dbase, $scheme_id, $field, $action );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not insert prefs values");
			throw BIGSdb::PrefstoreConfigurationException("Can't insert prefs values");
		}
	} else {
		if ( !$self->{'sql'}->{'set_scheme_field'} ) {
			$self->{'sql'}->{'set_scheme_field'} =
			  $self->{'db'}->prepare("INSERT INTO scheme_field (guid,dbase,scheme_id,field,action,value) VALUES (?,?,?,?,?,?)");
		}
		eval {
			$self->{'sql'}->{'set_scheme_field'}->execute( $guid, $dbase, $scheme_id, $field, $action, $value );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not insert prefs values: $@");
			throw BIGSdb::PrefstoreConfigurationException("Could not insert prefs values");
		}
	}
	$logger->debug("Set pref: scheme_id $field $action => $value");
	return;
}

sub set_plugin_attribute {
	my ( $self, $guid, $dbase, $plugin, $attribute, $value ) = @_;
	local $" = ', ';
	if ( !$self->_guid_exists($guid) ) {
		$self->_add_existing_guid($guid);
	}
	if ( $self->_plugin_attribute_exists( $guid, $dbase, $plugin, $attribute ) ) {
		if ( !$self->{'sql'}->{'update_plugin_attribute'} ) {
			$self->{'sql'}->{'update_plugin_attribute'} =
			  $self->{'db'}->prepare("UPDATE plugin SET value=? where guid=? AND dbase=? AND plugin=? AND attribute=?");
		}
		eval {
			$self->{'sql'}->{'update_plugin_attribute'}->execute( $value, $guid, $dbase, $plugin, $attribute );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not insert prefs values");
			throw BIGSdb::PrefstoreConfigurationException("Can't insert prefs values");
		}
	} else {
		if ( !$self->{'sql'}->{'set_plugin_attribute'} ) {
			$self->{'sql'}->{'set_plugin_attribute'} =
			  $self->{'db'}->prepare("INSERT INTO plugin (guid,dbase,plugin,attribute,value) VALUES (?,?,?,?,?)");
		}
		eval {
			$self->{'sql'}->{'set_plugin_attribute'}->execute( $guid, $dbase, $plugin, $attribute, $value );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not insert prefs values: $@");
			throw BIGSdb::PrefstoreConfigurationException("Could not insert prefs values");
		}
	}
	$logger->debug("Set pref: plugin $plugin $attribute => $value");
	return;
}

sub get_all_scheme_prefs {
	my ( $self, $guid, $dbase ) = @_;
	my $sql = $self->{'db'}->prepare("SELECT scheme_id,action,value FROM scheme WHERE guid=? AND dbase=?");
	eval { $sql->execute( $guid, $dbase ); };
	if ($@) {
		$logger->error("Can't execute $@");
		throw BIGSdb::PrefstoreConfigurationException("Can't execute get scheme all attribute query");
	}
	my $values;
	while ( my ( $scheme_id, $action, $value ) = $sql->fetchrow_array ) {
		$values->{$scheme_id}->{$action} = $value;
	}
	return $values;
}

sub get_all_scheme_field_prefs {
	my ( $self, $guid, $dbase ) = @_;
	my $sql = $self->{'db'}->prepare("SELECT scheme_id,field,action,value FROM scheme_field WHERE guid=? AND dbase=?");
	eval { $sql->execute( $guid, $dbase ); };
	if ($@) {
		$logger->error("Can't execute $@");
		throw BIGSdb::PrefstoreConfigurationException("Can't execute get all scheme fields attribute query");
	}
	my $values;
	while ( my ( $scheme_id, $field, $action, $value ) = $sql->fetchrow_array ) {
		$values->{$scheme_id}->{$field}->{$action} = $value;
	}
	return $values;
}

sub get_plugin_attribute {
	my ( $self, $guid, $dbase, $plugin, $attribute ) = @_;
	throw BIGSdb::DatabaseNoRecordException("No guid passed")
	  if !$guid;
	if ( !$self->{'sql'}->{'get_plugin_attribute'} ) {
		$self->{'sql'}->{'get_plugin_attribute'} =
		  $self->{'db'}->prepare("SELECT value FROM plugin WHERE guid=? AND dbase=? AND plugin=? AND attribute=?");
	}
	my $value;
	eval {
		$self->{'sql'}->{'get_plugin_attribute'}->execute( $guid, $dbase, $plugin, $attribute );
		($value) = $self->{'sql'}->{'get_plugin_attribute'}->fetchrow_array;
	};
	if ($@) {
		$logger->error("Can't execute get scheme field attribute query $@");
		throw BIGSdb::PrefstoreConfigurationException("Can't execute get scheme field attribute query");
	}
	throw BIGSdb::DatabaseNoRecordException("No value for plugin $plugin attribute $attribute")
	  if !defined $value;
	$logger->debug("Returning $plugin $attribute => $value");
	return $value;
}

sub delete_locus {
	my ( $self, $guid, $dbase, $locus, $action ) = @_;
	if ( !$self->_guid_exists($guid) ) {
		$self->_add_existing_guid($guid);
	}
	if ( $self->_locus_attribute_exists( $guid, $dbase, $locus, $action ) ) {
		if ( !$self->{'sql'}->{'delete_locus'} ) {
			$self->{'sql'}->{'delete_locus'} =
			  $self->{'db'}->prepare("DELETE FROM locus WHERE guid=? AND dbase=? AND locus=? AND action=?");
		}
		eval {
			$self->{'sql'}->{'delete_locus'}->execute( $guid, $dbase, $locus, $action );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not delete prefs values");
			throw BIGSdb::PrefstoreConfigurationException("Can't execute delete locus");
		}
	}
	$logger->debug("Delete pref: $locus $action");
	return;
}

sub delete_scheme_field {
	my ( $self, $guid, $dbase, $scheme_id, $field, $action ) = @_;
	if ( !$self->_guid_exists($guid) ) {
		$self->_add_existing_guid($guid);
	}
	if ( $self->_scheme_field_attribute_exists( $guid, $dbase, $scheme_id, $field, $action ) ) {
		if ( !$self->{'sql'}->{'delete_scheme_field'} ) {
			$self->{'sql'}->{'delete_scheme_field'} =
			  $self->{'db'}->prepare("DELETE FROM scheme_field WHERE guid=? AND dbase=? AND scheme_id=? AND field=? AND action=?");
		}
		eval {
			$self->{'sql'}->{'delete_scheme_field'}->execute( $guid, $dbase, $scheme_id, $field, $action );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not delete prefs values");
			throw BIGSdb::PrefstoreConfigurationException("Can't execute delete scheme_field");
		}
	}
	$logger->debug("Delete pref: $scheme_id $field $action");
	return;
}

sub delete_plugin_attribute {
	my ( $self, $guid, $dbase, $plugin, $attribute ) = @_;
	if ( !$self->_guid_exists($guid) ) {
		$self->_add_existing_guid($guid);
	}
	if ( $self->_plugin_attribute_exists( $guid, $dbase, $plugin, $attribute ) ) {
		if ( !$self->{'sql'}->{'delete_plugin_attribute'} ) {
			$self->{'sql'}->{'delete_plugin_attribute'} =
			  $self->{'db'}->prepare("DELETE FROM plugin WHERE guid=? AND dbase=? AND plugin=? AND attribute=?");
		}
		eval {
			$self->{'sql'}->{'delete_plugin_attribute'}->execute( $guid, $dbase, $plugin, $attribute );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not delete prefs values");
			throw BIGSdb::PrefstoreConfigurationException("Can't execute delete scheme_field");
		}
	}
	$logger->debug("Delete pref: $plugin $attribute");
	return;
}

sub delete_scheme {
	my ( $self, $guid, $dbase, $scheme, $action ) = @_;
	if ( !$self->_guid_exists($guid) ) {
		$self->_add_existing_guid($guid);
	}
	if ( $self->_scheme_attribute_exists( $guid, $dbase, $scheme, $action ) ) {
		if ( !$self->{'sql'}->{'delete_scheme'} ) {
			$self->{'sql'}->{'delete_scheme'} =
			  $self->{'db'}->prepare("DELETE FROM scheme WHERE guid=? AND dbase=? AND scheme_id=? AND action=?");
		}
		eval {
			$self->{'sql'}->{'delete_scheme'}->execute( $guid, $dbase, $scheme, $action );
			$self->{'db'}->commit;
		};
		if ($@) {
			$logger->error("Could not delete prefs values $@ ");
			throw BIGSdb::PrefstoreConfigurationException("Can't execute delete scheme");
		}
	}
	$logger->debug("Delete pref: $scheme $action");
	return;
}

sub update_datestamp {
	my ( $self, $guid ) = @_;
	if ( !$self->{'sql'}->{'update_datestamp'} ) {
		$self->{'sql'}->{'update_datestamp'} = $self->{'db'}->prepare("UPDATE guid SET last_accessed = 'today' WHERE guid = ?");
	}
	eval {
		$self->{'sql'}->{'update_datestamp'}->execute($guid);
		$self->{'db'}->commit;
	};
	if ($@) {
		$logger->error("Could not update datestamp");
		throw BIGSdb::PrefstoreConfigurationException("Could not update datestamp");
	}
}

sub delete_guid {
	my ( $self, $guid ) = @_;
	my $sql = $self->{'db'}->prepare("DELETE FROM guid WHERE guid=?");
	eval { $sql->execute($guid); $self->{'db'}->commit; };
	if ($@) {
		$logger->error("Could not delete guid");
		throw BIGSdb::PrefstoreConfigurationException("Could not delete guid");
	} else {
		$logger->info("Guid deleted from prefstore");
	}
	return;
}
1;
