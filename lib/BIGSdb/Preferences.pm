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
	$logger->info('Prefstore set up.');
	return $self;
}

sub DESTROY {
	$logger->info('Prefstore destroyed');
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
		$self->{'sql'}->{'guid_exists'} = $self->{'db'}->prepare('SELECT EXISTS(SELECT * FROM guid WHERE guid=?)');
	}
	my $exists;
	eval {
		$self->{'sql'}->{'guid_exists'}->execute($guid);
		$exists = $self->{'sql'}->{'guid_exists'}->fetchrow_array;
	};
	if ($@) {
		throw BIGSdb::PrefstoreConfigurationException('Cannot execute guid check');
		$logger->error($@);
	}
	return $exists;
}

sub _add_existing_guid {
	my ( $self, $guid ) = @_;
	eval { $self->{'db'}->do( 'INSERT INTO guid (guid,last_accessed) VALUES (?,?)', undef, $guid, 'now' ) };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		throw BIGSdb::PrefstoreConfigurationException('Cannot insert guid');
	}
	$self->{'db'}->commit;
	return;
}

sub get_new_guid {
	my ($self) = @_;
	my $ug     = Data::UUID->new;
	my $guid   = $ug->create_str;
	$self->_add_existing_guid($guid);
	return $guid;
}

sub _general_attribute_exists {
	my ( $self, @values ) = @_;
	if ( !$self->{'sql'}->{'general_attribute_exists'} ) {
		$self->{'sql'}->{'general_attribute_exists'} =
		  $self->{'db'}->prepare('SELECT EXISTS(SELECT * FROM general WHERE (guid,dbase,attribute)=(?,?,?))');
	}
	my $exists;
	eval {
		$self->{'sql'}->{'general_attribute_exists'}->execute(@values);
		$exists = $self->{'sql'}->{'general_attribute_exists'}->fetchrow_array;
	};
	if ($@) {
		$logger->error($@);
		throw BIGSdb::PrefstoreConfigurationException('Cannot execute attribute check');
	}
	return $exists;
}

sub _field_attribute_exists {
	my ( $self, @values ) = @_;
	if ( !$self->{'sql'}->{'field_attribute_exists'} ) {
		$self->{'sql'}->{'field_attribute_exists'} =
		  $self->{'db'}->prepare('SELECT EXISTS(SELECT * FROM field WHERE (guid,dbase,field,action)=(?,?,?,?))');
	}
	my $exists;
	eval {
		$self->{'sql'}->{'field_attribute_exists'}->execute(@values);
		$exists = $self->{'sql'}->{'field_attribute_exists'}->fetchrow_array();
	};
	if ($@) {
		$logger->error($@);
		throw BIGSdb::PrefstoreConfigurationException('Cannot execute attribute check');
	}
	return $exists;
}

sub _locus_attribute_exists {
	my ( $self, @values ) = @_;
	if ( !$self->{'sql'}->{'locus_attribute_exists'} ) {
		$self->{'sql'}->{'locus_attribute_exists'} =
		  $self->{'db'}->prepare('SELECT EXISTS(SELECT * FROM locus WHERE (guid,dbase,locus,action)=(?,?,?,?))');
	}
	my $exists;
	eval {
		$self->{'sql'}->{'locus_attribute_exists'}->execute(@values);
		$exists = $self->{'sql'}->{'locus_attribute_exists'}->fetchrow_array;
	};
	if ($@) {
		$logger->error($@);
		throw BIGSdb::PrefstoreConfigurationException('Cannot execute attribute check');
	}
	return $exists;
}

sub _scheme_field_attribute_exists {
	my ( $self, @values ) = @_;
	if ( !$self->{'sql'}->{'scheme_field_attribute_exists'} ) {
		$self->{'sql'}->{'scheme_field_attribute_exists'} =
		  $self->{'db'}
		  ->prepare('SELECT EXISTS(SELECT * FROM scheme_field WHERE (guid,dbase,scheme_id,field,action)=(?,?,?,?,?))');
	}
	my $exists;
	eval {
		$self->{'sql'}->{'scheme_field_attribute_exists'}->execute(@values);
		$exists = $self->{'sql'}->{'scheme_field_attribute_exists'}->fetchrow_array;
	};
	if ($@) {
		$logger->error($@);
		throw BIGSdb::PrefstoreConfigurationException('Cannot execute attribute check');
	}
	return $exists;
}

sub _scheme_attribute_exists {
	my ( $self, @values ) = @_;
	if ( !$self->{'sql'}->{'scheme_attribute_exists'} ) {
		$self->{'sql'}->{'scheme_attribute_exists'} =
		  $self->{'db'}->prepare('SELECT EXISTS(SELECT * FROM scheme WHERE (guid,dbase,scheme_id,action)=(?,?,?,?))');
	}
	my $exists;
	eval {
		$self->{'sql'}->{'scheme_attribute_exists'}->execute(@values);
		$exists = $self->{'sql'}->{'scheme_attribute_exists'}->fetchrow_array();
	};
	if ($@) {
		$logger->error($@);
		throw BIGSdb::PrefstoreConfigurationException('Cannot execute attribute check');
	}
	return $exists;
}

sub _plugin_attribute_exists {
	my ( $self, @values ) = @_;
	if ( !$self->{'sql'}->{'plugin_attribute_exists'} ) {
		$self->{'sql'}->{'plugin_attribute_exists'} =
		  $self->{'db'}->prepare('SELECT EXISTS(SELECT * FROM plugin WHERE (guid,dbase,plugin,attribute)=(?,?,?,?))');
	}
	my $exists;
	eval {
		$self->{'sql'}->{'plugin_attribute_exists'}->execute(@values);
		$exists = $self->{'sql'}->{'plugin_attribute_exists'}->fetchrow_array;
	};
	if ($@) {
		$logger->error($@);
		throw BIGSdb::PrefstoreConfigurationException('Cannot execute plugin attribute check');
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
			  $self->{'db'}->prepare('UPDATE general SET value=? WHERE (guid,dbase,attribute)=(?,?,?)');
		}
		eval { $self->{'sql'}->{'update_general'}->execute( $value, $guid, $dbase, $attribute ); };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Could not insert prefs values');
		}
		$self->{'db'}->commit;
	} else {
		if ( !$self->{'sql'}->{'set_general'} ) {
			$self->{'sql'}->{'set_general'} =
			  $self->{'db'}->prepare('INSERT INTO general (guid,dbase,attribute,value) VALUES (?,?,?,?)');
		}
		eval { $self->{'sql'}->{'set_general'}->execute( $guid, $dbase, $attribute, $value ); };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Could not insert prefs values');
		}
		$self->{'db'}->commit;
	}
	return;
}

sub get_all_general_prefs {
	my ( $self, $guid, $dbase ) = @_;
	throw BIGSdb::DatabaseNoRecordException('No guid passed') if !$guid;
	my $sql = $self->{'db'}->prepare('SELECT attribute,value FROM general WHERE (guid,dbase)=(?,?)');
	my $values;
	eval { $sql->execute( $guid, $dbase ) };
	if ($@) {
		$logger->error($@);
		throw BIGSdb::DatabaseNoRecordException('Cannot execute get_all_general attribute query');
	}
	my $data = $sql->fetchall_arrayref( {} );
	foreach my $prefs (@$data) {
		$values->{ $prefs->{'attribute'} } = $prefs->{'value'};
	}
	return $values;
}

sub get_general_pref {
	my ( $self, $guid, $dbase, $attribute ) = @_;
	throw BIGSdb::DatabaseNoRecordException('No guid passed') if !$guid;
	my $sql = $self->{'db'}->prepare('SELECT value FROM general WHERE (guid,dbase,attribute)=(?,?,?)');
	eval { $sql->execute( $guid, $dbase, $attribute ) };
	$logger->error($@) if $@;
	my $value = $sql->fetchrow_array;
	return $value;
}

sub get_all_field_prefs {
	my ( $self, $guid, $dbase ) = @_;
	throw BIGSdb::DatabaseNoRecordException('No guid passed') if !$guid;
	my $sql = $self->{'db'}->prepare('SELECT field,action,value FROM field WHERE (guid,dbase)=(?,?)');
	my $values;
	eval { $sql->execute( $guid, $dbase ) };
	if ($@) {
		$logger->error($@);
		throw BIGSdb::DatabaseNoRecordException('Cannot execute get_all_field attribute query');
	}
	my $data = $sql->fetchall_arrayref( {} );
	foreach my $pref (@$data) {
		$values->{ $pref->{'field'} }->{ $pref->{'action'} } = $pref->{'value'} ? 1 : 0;
	}
	return $values;
}

sub get_all_locus_prefs {
	my ( $self, $guid, $dbname ) = @_;
	throw BIGSdb::DatabaseNoRecordException('No guid passed') if !$guid;
	my $prefs;
	my $sql = $self->{'db'}->prepare('SELECT locus,action,value FROM locus WHERE (guid,dbase)=(?,?)');
	eval { $sql->execute( $guid, $dbname ) };
	$logger->error($@) if $@;
	my $data = $sql->fetchall_arrayref( {} );
	foreach my $pref (@$data) {
		$prefs->{ $pref->{'locus'} }->{ $pref->{'action'} } = $pref->{'value'};
	}
	$self->{'db'}->commit;    #Prevent idle in transaction table locks
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
			  $self->{'db'}->prepare('UPDATE field SET value=? WHERE (guid,dbase,field,action)=(?,?,?,?)');
		}
		eval { $self->{'sql'}->{'update_field'}->execute( $value, $guid, $dbase, $field, $action ) };
		if ($@) {
			$logger->error($@);
			throw BIGSdb::PrefstoreConfigurationException('Cannot execute set field attribute query');
		}
		$self->{'db'}->commit;
	} else {
		if ( !$self->{'sql'}->{'set_field'} ) {
			$self->{'sql'}->{'set_field'} =
			  $self->{'db'}->prepare('INSERT INTO field (guid,dbase,field,action,value) VALUES (?,?,?,?,?)');
		}
		eval { $self->{'sql'}->{'set_field'}->execute( $guid, $dbase, $field, $action, $value ) };
		if ($@) {
			$logger->error($@);
			throw BIGSdb::PrefstoreConfigurationException('Could not insert prefs values');
		}
		$self->{'db'}->commit;
	}
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
			  $self->{'db'}->prepare('UPDATE locus SET value=? WHERE (guid,dbase,locus,action)=(?,?,?,?)');
		}
		eval { $self->{'sql'}->{'update_locus'}->execute( $value, $guid, $dbase, $locus, $action ) };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Cannot insert prefs values');
		}
		$self->{'db'}->commit;
	} else {
		if ( !$self->{'sql'}->{'set_locus'} ) {
			$self->{'sql'}->{'set_locus'} =
			  $self->{'db'}->prepare('INSERT INTO locus (guid,dbase,locus,action,value) VALUES (?,?,?,?,?)');
		}
		eval { $self->{'sql'}->{'set_locus'}->execute( $guid, $dbase, $locus, $action, $value ); };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Could not insert prefs values');
		}
		$self->{'db'}->commit;
	}
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
			  $self->{'db'}->prepare('UPDATE scheme SET value=? WHERE (guid,dbase,scheme_id,action)=(?,?,?,?)');
		}
		eval { $self->{'sql'}->{'update_scheme'}->execute( $value, $guid, $dbase, $scheme_id, $action ) };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Cannot insert prefs values');
		}
		$self->{'db'}->commit;
	} else {
		if ( !$self->{'sql'}->{'set_scheme'} ) {
			$self->{'sql'}->{'set_scheme'} =
			  $self->{'db'}->prepare('INSERT INTO scheme (guid,dbase,scheme_id,action,value) VALUES (?,?,?,?,?)');
		}
		eval { $self->{'sql'}->{'set_scheme'}->execute( $guid, $dbase, $scheme_id, $action, $value ); };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Could not insert prefs values');
		}
		$self->{'db'}->commit;
	}
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
			  $self->{'db'}
			  ->prepare('UPDATE scheme_field SET value=? WHERE (guid,dbase,scheme_id,field,action)=(?,?,?,?,?)');
		}
		eval { $self->{'sql'}->{'update_scheme_field'}->execute( $value, $guid, $dbase, $scheme_id, $field, $action ) };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Cannot insert prefs values');
		}
		$self->{'db'}->commit;
	} else {
		if ( !$self->{'sql'}->{'set_scheme_field'} ) {
			$self->{'sql'}->{'set_scheme_field'} =
			  $self->{'db'}
			  ->prepare('INSERT INTO scheme_field (guid,dbase,scheme_id,field,action,value) VALUES (?,?,?,?,?,?)');
		}
		eval { $self->{'sql'}->{'set_scheme_field'}->execute( $guid, $dbase, $scheme_id, $field, $action, $value ) };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Could not insert prefs values');
		}
		$self->{'db'}->commit;
	}
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
			  $self->{'db'}->prepare('UPDATE plugin SET value=? WHERE (guid,dbase,plugin,attribute)=(?,?,?,?)');
		}
		eval { $self->{'sql'}->{'update_plugin_attribute'}->execute( $value, $guid, $dbase, $plugin, $attribute ) };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Cannot insert prefs values');
		}
		$self->{'db'}->commit;
	} else {
		if ( !$self->{'sql'}->{'set_plugin_attribute'} ) {
			$self->{'sql'}->{'set_plugin_attribute'} =
			  $self->{'db'}->prepare('INSERT INTO plugin (guid,dbase,plugin,attribute,value) VALUES (?,?,?,?,?)');
		}
		eval { $self->{'sql'}->{'set_plugin_attribute'}->execute( $guid, $dbase, $plugin, $attribute, $value ) };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Could not insert prefs values');
		}
		$self->{'db'}->commit;
	}
	return;
}

sub get_all_scheme_prefs {
	my ( $self, $guid, $dbase ) = @_;
	my $sql = $self->{'db'}->prepare('SELECT scheme_id,action,value FROM scheme WHERE (guid,dbase)=(?,?)');
	eval { $sql->execute( $guid, $dbase ) };
	if ($@) {
		$logger->error($@);
		throw BIGSdb::PrefstoreConfigurationException('Cannot execute get scheme all attribute query');
	}
	my $values;
	my $data = $sql->fetchall_arrayref( {} );
	foreach my $pref (@$data) {
		$values->{ $pref->{'scheme_id'} }->{ $pref->{'action'} } = $pref->{'value'};
	}
	return $values;
}

sub get_all_scheme_field_prefs {
	my ( $self, $guid, $dbase ) = @_;
	my $sql = $self->{'db'}->prepare('SELECT scheme_id,field,action,value FROM scheme_field WHERE (guid,dbase)=(?,?)');
	eval { $sql->execute( $guid, $dbase ) };
	if ($@) {
		$logger->error($@);
		throw BIGSdb::PrefstoreConfigurationException('Cannot execute get all scheme fields attribute query');
	}
	my $values;
	my $data = $sql->fetchall_arrayref( {} );
	foreach my $pref (@$data) {
		$values->{ $pref->{'scheme_id'} }->{ $pref->{'field'} }->{ $pref->{'action'} } = $pref->{'value'};
	}
	return $values;
}

sub get_plugin_attribute {
	my ( $self, $guid, $dbase, $plugin, $attribute ) = @_;
	throw BIGSdb::DatabaseNoRecordException('No guid passed') if !$guid;
	if ( !$self->{'sql'}->{'get_plugin_attribute'} ) {
		$self->{'sql'}->{'get_plugin_attribute'} =
		  $self->{'db'}->prepare('SELECT value FROM plugin WHERE (guid,dbase,plugin,attribute)=(?,?,?,?)');
	}
	my $value;
	eval {
		$self->{'sql'}->{'get_plugin_attribute'}->execute( $guid, $dbase, $plugin, $attribute );
		$value = $self->{'sql'}->{'get_plugin_attribute'}->fetchrow_array;
	};
	if ($@) {
		$logger->error($@);
		throw BIGSdb::PrefstoreConfigurationException('Cannot execute get scheme field attribute query');
	}
	throw BIGSdb::DatabaseNoRecordException("No value for plugin $plugin attribute $attribute") if !defined $value;
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
			  $self->{'db'}->prepare('DELETE FROM locus WHERE (guid,dbase,locus,action)=(?,?,?,?)');
		}
		eval { $self->{'sql'}->{'delete_locus'}->execute( $guid, $dbase, $locus, $action ) };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Cannot execute delete locus');
		}
		$self->{'db'}->commit;
	}
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
			  $self->{'db'}->prepare('DELETE FROM scheme_field WHERE (guid,dbase,scheme_id,field,action)=(?,?,?,?,?)');
		}
		eval { $self->{'sql'}->{'delete_scheme_field'}->execute( $guid, $dbase, $scheme_id, $field, $action ); };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Cannot execute delete scheme_field');
		}
		$self->{'db'}->commit;
	}
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
			  $self->{'db'}->prepare('DELETE FROM plugin WHERE (guid,dbase,plugin,attribute)=(?,?,?,?)');
		}
		eval { $self->{'sql'}->{'delete_plugin_attribute'}->execute( $guid, $dbase, $plugin, $attribute ) };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Cannot execute delete scheme_field');
		}
		$self->{'db'}->commit;
	}
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
			  $self->{'db'}->prepare('DELETE FROM scheme WHERE (guid,dbase,scheme_id,action)=(?,?,?,?)');
		}
		eval { $self->{'sql'}->{'delete_scheme'}->execute( $guid, $dbase, $scheme, $action ) };
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
			throw BIGSdb::PrefstoreConfigurationException('Cannot execute delete scheme');
		}
		$self->{'db'}->commit;
	}
	return;
}

sub update_datestamp {
	my ( $self, $guid ) = @_;
	if ( !$self->{'sql'}->{'update_datestamp'} ) {
		$self->{'sql'}->{'update_datestamp'} = $self->{'db'}->prepare('UPDATE guid SET last_accessed=? WHERE guid=?');
	}
	eval { $self->{'sql'}->{'update_datestamp'}->execute( 'now', $guid ) };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
		throw BIGSdb::PrefstoreConfigurationException('Could not update datestamp');
	}
	$self->{'db'}->commit;
	return;
}

sub delete_guid {
	my ( $self, $guid ) = @_;
	eval { $self->{'db'}->do( 'DELETE FROM guid WHERE guid=?', undef, $guid ) };
	if ($@) {
		$logger->error('Could not delete guid');
		$self->{'db'}->rollback;
		throw BIGSdb::PrefstoreConfigurationException('Could not delete guid');
	}
	$self->{'db'}->commit;
	return;
}
1;
