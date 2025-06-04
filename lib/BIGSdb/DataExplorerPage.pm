#Written by Keith Jolley
#Copyright (c) 2021-2025, University of Oxford
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
#along with BIGSdb.  If not, see <https://www.gnu.org/licenses/>.
package BIGSdb::DataExplorerPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::DashboardPage);
use JSON;
use BIGSdb::Constants qw(RECORD_AGE);
use Data::Dumper;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant DEFAULT_ROWS => 15;

sub _ajax_table {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $field  = $q->param('field');
	my $params = {
		include_old_versions => scalar $q->param('include_old_versions'),
		record_age           => scalar $q->param('record_age'),
		project_id           => scalar $q->param('project_id')
	};
	my $values = $self->_get_values( $field, $params );
	my $table  = $self->_get_table( $field, $values, $params );
	my $json   = JSON->new->allow_nonref;
	say $json->encode($table);
	return;
}

sub _ajax_analyse {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $json   = JSON->new->allow_nonref;
	my $params;
	eval { $params = $json->decode( scalar $q->param('params') ); };
	if (@$) {
		$logger->error('Cannot decode AJAX JSON.');
	}
	if ( !$params->{'fields'} || !@{ $params->{'fields'} } ) {
		$logger->error('No fields passed');
		return;
	}
	if ( !$params->{'values'} || !@{ $params->{'values'} } ) {
		$logger->error('No values passed');
		return;
	}
	my $fields    = $self->_get_field_names( $params->{'fields'} );
	my $freq      = $self->_create_freq_table($params);
	my $hierarchy = $self->_create_hierarchy( $params, $fields, $freq );
	my $data      = {
		fields      => $fields,
		frequencies => $freq,
		hierarchy   => $hierarchy
	};
	eval { say $json->encode($data); };
	if (@$) {
		$logger->error('Cannot JSON encode dataset.');
	}
	return;
}

sub _create_hierarchy {
	my ( $self, $params, $fields, $freq ) = @_;
	my $data = { children => {} };
	$data->{'count'} = 0;
	$data->{'count'} += $_->{'count'} foreach @$freq;
	$data->{'children'} = [];
	my $url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=query";
	foreach my $record (@$freq) {
		$self->_populate_node(
			{
				data   => $data->{'children'},
				fields => $fields->{'cleaned'},
				record => $record,
				url    => $url,
				level  => 0,
				params => $params,
				total  => $data->{'count'}
			}
		);
	}
	return $data;
}

sub _populate_node {
	my ( $self, $args ) = @_;
	my ( $data, $fields, $record, $url, $level, $params ) = @{$args}{qw(data fields record url level params)};
	return if $level == @$fields;
	my $this_node = {};
	$this_node->{'count'} += $record->{'count'};
	my $field = $fields->[$level];
	my $value = $record->{ $fields->[$level] };
	foreach my $term ( @{ $record->{'search_terms'}->{$field} } ) {
		$url .= "&$term->{'form'}=$term->{'value'}";
	}
	$url .= '&submit=1';
	my $node_exists = 0;
	foreach my $node (@$data) {
		if ( $node->{'field'} eq $field && $node->{'value'} eq $value ) {    #Existing node
			$node->{'count'} += $record->{'count'};
			$node_exists = 1;
			if ( $level < @$fields - 1 ) {
				$self->_populate_node(
					{
						data   => $node->{'children'},
						fields => $fields,
						record => $record,
						url    => $url,
						level  => $level + 1,
						params => $params,
						total  => $node->{'count'}
					}
				);
			}
			last;
		}
	}
	if ( !$node_exists ) {
		$this_node->{'field'} = $fields->[$level];
		$this_node->{'value'} = $record->{ $fields->[$level] };
		$this_node->{'url'}   = $self->_add_url_filters( $url, $params );
		$this_node->{'count'} = $record->{'count'};
		if ( $level < @$fields - 1 ) {
			$this_node->{'children'} = [];
			$self->_populate_node(
				{
					data   => $this_node->{'children'},
					fields => $fields,
					record => $record,
					url    => $url,
					level  => $level + 1,
					params => $params,
				}
			);
		}
		push @$data, $this_node;
	}
	return;
}

sub _add_url_filters {
	my ( $self, $url, $params ) = @_;
	if ( $params->{'include_old_versions'} ) {
		$url .= '&include_old=on';
	}
	if ( $params->{'record_age'} ) {
		my $highest_prov_field = () = $url =~ /prov_field/gx;
		my $n                  = $highest_prov_field + 1;
		my $datestamp          = $self->get_record_age_datestamp( $params->{'record_age'} );
		$url .= "&prov_field$n=f_date_entered&prov_operator$n=>=&prov_value$n=$datestamp";
	}
	if ( $params->{'project_id'} ) {
		$url .= "&project_list=$params->{'project_id'}";
	}
	return $url;
}

sub _get_field_names {
	my ( $self, $prefixed_names ) = @_;
	my $cleaned        = [];
	my $mapped         = {};
	my $reverse_mapped = {};
	foreach my $field (@$prefixed_names) {
		if ( $field =~ /^f_(\w+)$/x ) {
			push @$cleaned, $1;
			$mapped->{$1}             = $field;
			$reverse_mapped->{$field} = $1;
		}
		if ( $field =~ /^e_(.*)\|\|(.*)/x ) {
			push @$cleaned, $2;
			$mapped->{$2}             = $field;
			$reverse_mapped->{$field} = $2;
		}
		if ( $field =~ /^eav_(.*)/x ) {
			push @$cleaned, $1;
			$mapped->{$1}             = $field;
			$reverse_mapped->{$field} = $1;
		}
		if ( $field =~ /^s_(\d+)_(.*)/x ) {
			my ( $scheme_id, $field_name ) = ( $1, $2 );
			my $cleaned_field_name = $self->_get_scheme_field_name( { scheme_id => $scheme_id, field => $field_name } );
			push @$cleaned, $cleaned_field_name;
			$mapped->{$cleaned_field_name} = $field;
			$reverse_mapped->{$field}      = $cleaned_field_name;
		}
	}
	return {
		cleaned        => $cleaned,
		mapped         => $mapped,
		reverse_mapped => $reverse_mapped
	};
}

sub _create_freq_table {
	my ( $self, $params ) = @_;
	my $list_table = $self->{'datastore'}->create_temp_list_table_from_array( 'text', $params->{'values'} );
	my $check      = $self->_check_fields($params);
	my (
		$list_field,    $includes_null, $primary_fields, $extended_fields, $eav_fields,
		$scheme_fields, $group_fields,  $multi_values,   $user_fields
	  )
	  = @{$check}{
		qw(list_field includes_null primary_fields extended_fields eav_fields scheme_fields group_fields
		  multi_values user_fields)
	  };
	my @tables;
	my @fields;
	my $qry = q(CREATE TEMP TABLE freqs AS SELECT );
	if (@$primary_fields) {
		my $processed = $self->_process_primary_fields($primary_fields);
		push @fields, @{ $processed->{'fields'} };
		push @tables, $processed->{'table'};
	}
	if (@$extended_fields) {
		my $processed = $self->_process_extended_fields($extended_fields);
		local $" = q(,);
		push @fields, @{ $processed->{'fields'} };
		push @tables, @{ $processed->{'tables'} };
	}
	if (@$eav_fields) {
		my $processed = $self->_process_eav_fields($eav_fields);
		local $" = q(,);
		push @fields, @{ $processed->{'fields'} };
		push @tables, @{ $processed->{'tables'} };
	}
	if (@$scheme_fields) {
		my $processed = $self->_process_scheme_fields($scheme_fields);
		local $" = q(,);
		push @fields, @{ $processed->{'fields'} };
		push @tables, @{ $processed->{'tables'} };
	}
	local $" = q(,);
	$qry .= qq(@fields,COUNT(*) AS count );
	local $" = q( LEFT JOIN );
	unshift @tables, "$self->{'system'}->{'view'} v" if $tables[0] ne "$self->{'system'}->{'view'} v";
	$qry .= qq(FROM @tables );
	my $filters = $self->_get_filters($params);
	if (@$filters) {
		local $" = q( AND );
		$qry .= $qry =~ /WHERE/x ? 'AND ' : 'WHERE ';
		$qry .= qq(@$filters );
	}
	$qry .= $qry =~ /WHERE/x ? 'AND ' : 'WHERE ';
	if ($multi_values) {
		$qry .= q[(];
		$qry .= qq($list_field && ARRAY(SELECT value FROM $list_table));
		$qry .= qq( OR $list_field IS NULL) if $includes_null;
		$qry .= q[) ];
	} else {
		$qry .= q[(];
		$qry .= qq($list_field IN (SELECT value FROM $list_table));
		$qry .= qq( OR $list_field IS NULL) if $includes_null;
		$qry .= q[) ];
	}
	local $" = q(","_);
	$qry .= qq(GROUP BY "_@$group_fields");
	eval { $self->{'db'}->do($qry); };
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}

	#We prefix output fieldnames with underscores to ensure they are unambiguous with scheme field names.
	#Now we rewrite them without the prefix for output.
	my @group_field_aliases;
	my @aliases;
	foreach my $field (@$group_fields) {
		push @group_field_aliases, qq("_$field" AS "$field");
		push @aliases,             qq("$field");
	}
	local $" = q(,);
	my $data =
	  $self->{'datastore'}->run_query( qq(SELECT @group_field_aliases,count FROM freqs ORDER BY count DESC,@aliases),
		undef, { fetch => 'all_arrayref', slice => {} } );
	my $field_names = $self->_get_field_names( $params->{'fields'} );
	foreach my $record (@$data) {
		my $search_terms = {};
		my $prov         = 1;
		my $eav          = 1;
		my $scheme_field = 1;
		foreach my $key ( @{ $field_names->{'cleaned'} } ) {
			if ( $field_names->{'mapped'}->{$key} ) {
				my $field = $field_names->{'mapped'}->{$key};
				my $value = $record->{$key};
				$value = 'null' if $value eq 'No value';
				$value =~ s/\ /%20/gx;
				if ( $field =~ /^[f|e]_/x ) {
					$field = 'f_sender%20(id)'  if $field eq 'f_sender';
					$field = 'f_curator%20(id)' if $field eq 'f_curator';
					$search_terms->{$key} =
					  [ { form => "prov_field$prov", value => $field },
						{ form => "prov_value$prov", value => $value } ];
					$prov++;
				}
				if ( $field =~ /^eav_/x ) {
					$search_terms->{$key} = [
						{ form => "phenotypic_field$eav", value => $field },
						{ form => "phenotypic_value$eav", value => $value }
					];
					$eav++;
				}
				if ( $field =~ /^s_(\d+)_(.*)/x ) {
					$search_terms->{$key} = [
						{ form => "designation_field$scheme_field", value => $field },
						{ form => "designation_value$scheme_field", value => $value }
					];
					$scheme_field++;
				}
			}
		}
		$record->{'search_terms'} = $search_terms;
	}
	$data = $self->_rewrite_user_field_values( $data, $user_fields ) if @$user_fields;
	return $data;
}

sub _check_fields {
	my ( $self, $params ) = @_;
	my %used;
	my $primary_fields  = [];
	my $extended_fields = [];
	my $eav_fields      = [];
	my $scheme_fields   = [];
	my $group_fields    = [];
	my $multi_values;
	my %user_fields;
	my $list_field;
	my $includes_null;

	foreach my $value ( @{ $params->{'values'} } ) {
		$includes_null = 1 if $value eq 'No value';
	}
	foreach my $field ( @{ $params->{'fields'} } ) {
		if ( $field =~ /^f_(\w+)$/x ) {
			my $this_field = $1;
			next if $used{$this_field};
			next if !$self->{'xmlHandler'}->is_field($this_field);
			my $att = $self->{'xmlHandler'}->get_field_attributes($this_field);
			push @$primary_fields, $this_field;
			if ( $field eq $params->{'fields'}->[0] ) {
				$list_field   = lc( $att->{'type'} ) ne 'text' ? "CAST(v.$this_field AS text)" : "v.$this_field";
				$multi_values = 1 if ( $att->{'multiple'} // q() ) eq 'yes';
			}
			$user_fields{$this_field} = 1
			  if $this_field eq 'sender' || $this_field eq 'curator' || ( $att->{'userfield'} // q() ) eq 'yes';
			push @$group_fields, $this_field;
			$used{$this_field} = 1;
		}
		if ( $field =~ /^e_(.*)\|\|(.*)/x ) {
			my ( $isolate_field, $attribute ) = ( $1, $2 );
			next if $used{$attribute};
			my $att = $self->{'datastore'}->get_isolate_extended_field_attributes( $isolate_field, $attribute );
			if ( $field eq $params->{'fields'}->[0] ) {
				$list_field = $att->{'value_format'} ne 'text' ? 'CAST(e1.value AS text)' : 'e1.value';
			}
			push @$extended_fields,
			  {
				isolate_field => $isolate_field,
				attribute     => $attribute
			  };
			push @$group_fields, $attribute;
			$used{$attribute} = 1;
		}
		if ( $field =~ /^eav_(.*)/x ) {
			my $this_field = $1;
			next if $used{$this_field};
			my $att = $self->{'datastore'}->get_eav_field($this_field);
			next if !$att;
			push @$eav_fields, $this_field;
			if ( $field eq $params->{'fields'}->[0] ) {
				$list_field = $att->{'value_format'} ne 'text' ? 'CAST(eav1.value AS text)' : 'eav1.value';
			}
			push @$group_fields, $this_field;
			$used{$this_field} = 1;
		}
		if ( $field =~ /^s_(\d+)_(.*)/x ) {
			my ( $scheme_id, $field_name ) = ( $1, $2 );
			next if $used{$field};
			my $att = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field_name );
			next if !$att;
			push @$scheme_fields,
			  {
				scheme_id => $scheme_id,
				field     => $field_name
			  };
			my $cleaned_field_name = $self->_get_scheme_field_name( { scheme_id => $scheme_id, field => $field_name } );
			my $table              = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);
			if ( $field eq $params->{'fields'}->[0] ) {
				$list_field = $att->{'type'} ne 'text' ? qq(CAST($table.$field_name AS text)) : qq($table.$field_name);
			}
			push @$group_fields, $cleaned_field_name;
			$used{$field} = 1;
		}
	}
	return {
		list_field      => $list_field,
		includes_null   => $includes_null,
		primary_fields  => $primary_fields,
		extended_fields => $extended_fields,
		eav_fields      => $eav_fields,
		scheme_fields   => $scheme_fields,
		group_fields    => $group_fields,
		multi_values    => $multi_values,
		user_fields     => [ keys %user_fields ]
	};
}

sub _rewrite_user_field_values {
	my ( $self, $data, $user_fields ) = @_;
	my %cache;
	foreach my $record (@$data) {
		foreach my $field (@$user_fields) {
			next if $record->{$field} eq 'No value';
			if ( !defined $cache{ $record->{$field} } ) {
				$cache{ $record->{$field} } =
				  $self->{'datastore'}->get_user_string( $record->{$field}, { affiliation => 1 } );
			}
			$record->{$field} = $cache{ $record->{$field} };
		}
	}
	return $data;
}

sub _process_primary_fields {
	my ( $self, $primary_fields ) = @_;
	my $temp_fields = [];
	foreach my $field (@$primary_fields) {
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		if ( ( $att->{'multiple'} // q() ) eq 'yes' ) {
			push @$temp_fields,
			  qq(COALESCE(NULLIF(ARRAY_TO_STRING(array_sort(v.$field),'; '),''),'No value') AS "_$field");
		} else {
			if ( lc( $att->{'type'} ) eq 'text' ) {
				push @$temp_fields, qq(COALESCE(v.$field,'No value') AS "_$field");
			} else {
				push @$temp_fields, qq(COALESCE(CAST(v.$field AS text),'No value') AS "_$field");
			}
		}
	}
	return {
		fields => $temp_fields,
		table  => "$self->{'system'}->{'view'} v"
	};
}

sub _process_extended_fields {
	my ( $self, $extended_fields ) = @_;
	my $i           = 1;
	my $tables      = [];
	my $temp_fields = [];
	foreach my $field (@$extended_fields) {
		my $att = $self->{'datastore'}
		  ->get_isolate_extended_field_attributes( $field->{'isolate_field'}, $field->{'attribute'} );
		if ( $att->{'value_format'} eq 'text' ) {
			push @$temp_fields, qq(COALESCE(e$i.value,'No value') AS "_$field->{'attribute'}");
		} else {
			push @$temp_fields, qq(COALESCE(CAST(e$i.value AS text),'No value') AS "_$field->{'attribute'}");
		}
		push @$tables,
			"isolate_value_extended_attributes e$i ON "
		  . "(e$i.isolate_field,e$i.attribute,e$i.field_value)="
		  . "('$field->{'isolate_field'}','$field->{'attribute'}',v.$field->{'isolate_field'})";
		$i++;
	}
	return {
		fields => $temp_fields,
		tables => $tables
	};
}

sub _process_eav_fields {
	my ( $self, $eav_fields ) = @_;
	my $tables      = [];
	my $temp_fields = [];
	my $i           = 1;
	foreach my $field (@$eav_fields) {
		my $table = $self->{'datastore'}->get_eav_field_table($field);
		my $att   = $self->{'datastore'}->get_eav_field($field);
		if ( $att->{'value_format'} eq 'text' ) {
			push @$temp_fields, qq(COALESCE(eav$i.value,'No value') AS "_$field");
		} else {
			push @$temp_fields, qq(COALESCE(CAST(eav$i.value AS text),'No value') AS "_$field");
		}
		push @$tables, "$table eav$i ON (eav$i.isolate_id,eav$i.field)=(v.id,'$field')";
		$i++;
	}
	return {
		fields => $temp_fields,
		tables => $tables
	};
}

sub _process_scheme_fields {
	my ( $self, $scheme_fields ) = @_;
	my $tables      = [];
	my $temp_fields = [];
	my %used;
	foreach my $field (@$scheme_fields) {
		my $field_name = $self->_get_scheme_field_name($field);
		my $table =
		  $self->{'datastore'}->create_temp_isolate_scheme_fields_view( $field->{'scheme_id'} );
		my $att = $self->{'datastore'}->get_scheme_field_info( $field->{'scheme_id'}, $field->{'field'} );
		if ( $att->{'type'} eq 'text' ) {
			push @$temp_fields, qq(COALESCE($table.$field->{'field'},'No value') AS "_$field_name");
		} else {
			push @$temp_fields, qq(COALESCE(CAST($table.$field->{'field'} AS text),'No value') AS "_$field_name");
		}
		push @$tables, "$table ON $table.id=v.id" if !$used{$table};
		$used{$table} = 1;
	}
	return {
		fields => $temp_fields,
		tables => $tables
	};
}

sub _get_scheme_field_name {
	my ( $self, $field ) = @_;
	my $set_id = $self->get_set_id;
	my $scheme_info =
	  $self->{'datastore'}->get_scheme_info( $field->{'scheme_id'}, { set_id => $set_id } );
	my $field_name = "$field->{'field'} ($scheme_info->{'name'})";
	return $field_name;
}

sub print_content {
	my ($self)       = @_;
	my $title        = $self->get_title;
	my $q            = $self->{'cgi'};
	my %ajax_methods = ( updateTable => '_ajax_table', analyse => '_ajax_analyse' );
	foreach my $method ( sort keys %ajax_methods ) {
		my $sub = $ajax_methods{$method};
		if ( $q->param($method) ) {
			$self->$sub( scalar $q->param($method) );
			return;
		}
	}
	say qq(<h1>$title</h1>);
	my $field = $q->param('field');
	if ( !defined $field ) {
		$self->print_bad_status(
			{
				message => q(No field specified.),
			}
		);
		return;
	}
	my $display_field = $self->get_display_field($field);
	say q(<div class="box resultstable" id="data_explorer">);
	$self->_print_filters;
	say qq(<div style="float:left"><h2>Field: $display_field</h2>);
	my $params = {
		include_old_versions => $q->param('include_old_versions') eq 'true' ? 1 : 0,
		record_age           => scalar $q->param('record_age'),
		project_id           => scalar $q->param('project_id')
	};
	if ( $q->param('specific_values') ) {
		my $json = JSON->new->allow_nonref;
		my $values;
		eval { $values = $json->decode( scalar $q->param('specific_values') ); };
		if ($@) {
			$logger->error('Invalid JSON encoding of specific values.');
		}
		$params->{'checked_values'} = $values;
	}
	my $values  = $self->_get_values( $field, $params );
	my $count   = keys %$values;
	my $records = 0;
	$records += $_ foreach values %$values;
	my $nice_count   = BIGSdb::Utils::commify($count);
	my $nice_records = BIGSdb::Utils::commify($records);
	say qq(<p>Total records: <span id="total_records" style="font-weight:600">$nice_records</span>; )
	  . qq(Unique values: <span id="unique_values" style="font-weight:600">$nice_count</span></p>);

	if ( $self->_is_multi_field($field) ) {
		say q(<p>Field allows multiple values - totals may be >100%</p>);
	}
	say q(</div><div style="clear:both"></div>);
	say q(<div id="waiting" style="position:absolute;top:7em;left:1em;display:none">)
	  . q(<span class="wait_icon fas fa-sync-alt fa-spin fa-2x"></span></div>);
	say q(<div style="margin-left:-50px">);
	say q(<div id="table_div" class="scrollable" )
	  . q(style="float:left;margin-left:50px;margin-top:2em;max-width:calc(100vw - 50px)">);
	my $table = $self->_get_table( $field, $values, $params );
	say $table->{'html'};
	say q(</div>);
	say q(<div style="float:left;margin-left:50px;margin-top:2em">);
	$self->_print_field_controls;
	say q(</div>);
	say q(</div>);
	say q(<div style="clear:both"></div>);
	say q(<p id="notes" style="display:none">Click nodes to expand or contract the tree, )
	  . q(click labels to query the database and return filtered dataset.</p>);
	say q(<div id="tooltip"></div>);
	say q(<div id="field_labels"></div>);
	say q(<div id="tree"></div>);
	say q(</div>);
	my $json  = JSON->new->allow_nonref;
	my $index = $json->encode( $table->{'index'} );
	say qq(<script>var dataIndex=$index</script>);
	return;
}

sub _is_multi_field {
	my ( $self, $field ) = @_;
	return if $field !~ /^f_/x;
	$field =~ s/^f_//x;
	my $att = $self->{'xmlHandler'}->get_field_attributes($field);
	return ( $att->{'multiple'} // q() ) eq 'yes';
}

sub _print_field_controls {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset><legend>Drill down</legend>);
	say q(<p>Select one or more field values in table,<br />then select one or more fields below to drill-down.</p>);
	say q(<ul>);
	for my $i ( 1 .. 3 ) {
		say q(<li>);
		$self->print_field_selector(
			{
				ignore_prefs        => 1,
				isolate_fields      => 1,
				scheme_fields       => 1,
				extended_attributes => 1,
				eav_fields          => 1,
			},
			{
				no_special    => 1,
				no_default    => 1,
				id            => "field$i",
				name          => "field$i",
				label         => "Field#$i",
				exclude_field => scalar $q->param('field')
			}
		);
		say q(</li>);
	}
	say q(</ul>);
	say $q->submit(
		-id    => 'analyse',
		-name  => 'analyse',
		-label => 'Analyse',
		-class => 'submit disabled',
		-style => 'margin-top:1em'
	);
	say q(</fieldset>);
	return;
}

sub _get_table {
	my ( $self, $field, $values, $params ) = @_;
	my $total = 0;
	$total += $values->{$_} foreach keys %$values;
	if ( !$total ) {
		return { html => q(<p>No values to display</p>) };
	}
	my %checked;
	if ( $params->{'checked_values'} && ref $params->{'checked_values'} ) {
		%checked = map { $_ => 1 } @{ $params->{'checked_values'} };
	}
	my $q             = $self->{'cgi'};
	my $i             = 1;
	my $index         = {};
	my $is_user_field = $self->_is_user_field($field);
	my $hide          = keys %$values > DEFAULT_ROWS;
	my $class         = $hide ? q(expandable_retracted data_explorer) : q();
	my $table         = qq(<div id="table" class="scrollable $class">);
	$table .= q(<table class="tablesorter"><thead><tr><th>Value</th><th>Frequency</th><th>%</th>)
	  . q(<th class="sorter-false">Select);
	$table .= $q->checkbox( -id => 'select_all', -name => 'select_all', -label => '' );
	$table .= q(</th></tr></thead><tbody>);

	foreach my $value ( sort { $values->{$b} <=> $values->{$a} } keys %$values ) {
		my $url     = $self->_get_url( $field, $value, $params );
		my $percent = BIGSdb::Utils::decimal_place( 100 * $values->{$value} / $total, 2 );
		my $label;
		if ($is_user_field) {
			$label = $self->{'datastore'}->get_user_string( $value, { affiliation => 1 } );
			$label =~ s/\r?\n/ /gx;
		}
		$label //= $value;
		my $count = BIGSdb::Utils::commify( $values->{$value} );
		$table .= qq(<tr class="value_row"><td style="text-align:left"><a href="$url">$label</a></td>)
		  . qq(<td class="value_count">$count</td><td>$percent</td><td>);
		$table .= $q->checkbox(
			-id      => "v$i",
			-name    => "v$i",
			-class   => 'option_check',
			-label   => '',
			-checked => $checked{$label} ? 1 : 0
		);
		$table .= q(</td></tr>);
		if ($is_user_field) {
			$index->{$i} = $value;
		} else {
			$index->{$i} = $label;
		}
		$i++;
	}
	$table .= q(</tbody></table></div>);
	if ($hide) {
		$table .= q(<div class="expand_link" id="expand_table"><span class="fas fa-chevron-down"></span></div>);
	}
	return { html => $table, index => $index };
}

sub _is_user_field {
	my ( $self, $field ) = @_;
	if ( $field =~ /^f_/x ) {
		$field =~ s/^f_//x;
		return if !$self->{'xmlHandler'}->is_field($field);
		my $att = $self->{'xmlHandler'}->get_field_attributes($field);
		return 1 if ( $att->{'userfield'} // q() ) eq 'yes';
		return 1 if $field eq 'sender' || $field eq 'curator';
	}
	return;
}

sub _get_url {
	my ( $self, $field, $value, $params ) = @_;
	my $url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&page=query";
	$value = 'null' if $value eq 'No value';
	if ( $field =~ /^[f|e]_/x ) {
		$field = 'f_sender%20(id)'  if $field eq 'f_sender';
		$field = 'f_curator%20(id)' if $field eq 'f_curator';
		$url .= "&prov_field1=$field&prov_value1=$value";
	}
	if ( $field =~ /^eav_/x ) {
		$url .= "&phenotypic_field1=$field&phenotypic_value1=$value";
	}
	if ( $field =~ /^s_\d+_/x ) {
		$url .= "&designation_field1=$field&designation_value1=$value";
	}
	if ( $params->{'include_old_versions'} ) {
		$url .= '&include_old=on';
	}
	if ( $params->{'record_age'} ) {
		my $row       = $url =~ /prov_field1/x ? 2 : 1;
		my $datestamp = $self->get_record_age_datestamp( $params->{'record_age'} );
		$url .= "&prov_field$row=f_date_entered&prov_operator$row=>=&prov_value$row=$datestamp";
	}
	if ( $params->{'project_id'} ) {
		$url .= "&project_list=$params->{'project_id'}";
	}
	$url .= '&submit=1';
	return $url;
}

sub _get_values {
	my ( $self, $field, $params ) = @_;
	if ( $field =~ /^f_/x ) {
		$field =~ s/^f_//x;
		return $self->_get_primary_metadata_values( $field, $params );
	}
	if ( $field =~ /^e_(.*)\|\|(.*)/x ) {
		my ( $isolate_field, $attribute ) = ( $1, $2 );
		return $self->_get_extended_field_values( $isolate_field, $attribute, $params );
	}
	if ( $field =~ /^eav_(.*)/x ) {
		$field = $1;
		return $self->_get_eav_field_values( $field, $params );
	}
	if ( $field =~ /^s_(\d+)_(.*)/x ) {
		( my $scheme_id, $field ) = ( $1, $2 );
		return $self->_get_scheme_field_values( $scheme_id, $field, $params );
	}
	return {};
}

sub _get_primary_metadata_values {
	my ( $self, $field, $params ) = @_;
	my $filters = $self->_get_filters($params);
	my $qry     = "SELECT $field AS label,COUNT(*) AS count FROM $self->{'system'}->{'view'} v";
	local $" = ' AND ';
	$qry .= " WHERE @$filters" if @$filters;
	$qry .= ' GROUP BY label';
	my $values =
	  $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	my $freqs = {};
	my $att   = $self->{'xmlHandler'}->get_field_attributes($field);

	if ( ( $att->{'multiple'} // q() ) eq 'yes' ) {
		foreach my $value (@$values) {
			if ( !defined $value->{'label'} ) {
				$value->{'label'} = ['No value'];
			}
			foreach my $label ( @{ $value->{'label'} } ) {
				$freqs->{$label} += $value->{'count'};
			}
		}
	} else {
		foreach my $value (@$values) {
			my $label = $value->{'label'} // 'No value';
			$freqs->{$label} = $value->{'count'};
		}
	}
	return $freqs;
}

sub _get_extended_field_values {
	my ( $self, $field, $attribute, $params ) = @_;
	my $qry =
		"SELECT COALESCE(e.value,'No value') AS label,COUNT(*) AS count FROM $self->{'system'}->{'view'} v "
	  . "LEFT JOIN isolate_value_extended_attributes e ON (v.$field,e.isolate_field,e.attribute)=(e.field_value,?,?) ";
	my $filters = $self->_get_filters($params);
	local $" = ' AND ';
	$qry .= "WHERE @$filters" if @$filters;
	$qry .= ' GROUP BY label';
	my $values =
	  $self->{'datastore'}->run_query( $qry, [ $field, $attribute ], { fetch => 'all_arrayref', slice => {} } );
	my $freqs = {};

	foreach my $value (@$values) {
		$freqs->{ $value->{'label'} } = $value->{'count'};
	}
	return $freqs;
}

sub _get_eav_field_values {
	my ( $self, $field, $params ) = @_;
	my $att   = $self->{'datastore'}->get_eav_field($field);
	my $table = $self->{'datastore'}->get_eav_field_table($field);
	my $qry   = "SELECT COALESCE(t.value,'No value') AS label,COUNT(*) AS count FROM $table t RIGHT JOIN "
	  . "$self->{'system'}->{'view'} v ON t.isolate_id = v.id AND t.field=?";
	my $filters = $self->_get_filters($params);
	local $" = ' AND ';
	$qry .= " WHERE @$filters" if @$filters;
	$qry .= ' GROUP BY label';
	my $values = $self->{'datastore'}->run_query( $qry, $field, { fetch => 'all_arrayref', slice => {} } );
	my $freqs  = {};

	foreach my $value (@$values) {
		$freqs->{ $value->{'label'} } = $value->{'count'};
	}
	return $freqs;
}

sub _get_scheme_field_values {
	my ( $self, $scheme_id, $field, $params ) = @_;
	my $scheme_table = $self->{'datastore'}->create_temp_isolate_scheme_fields_view($scheme_id);

	#We include the DISTINCT clause below because an isolate may have more than 1 row in the scheme
	#cache table. This happens if the isolate has multiple STs (due to multiple allele hits).
	my $qry =
		"SELECT COALESCE(CAST(s.$field AS text),'No value') AS label,COUNT(DISTINCT (v.id)) AS count FROM "
	  . "$self->{'system'}->{'view'} v LEFT JOIN $scheme_table s ON v.id=s.id";
	my $filters = $self->_get_filters($params);
	local $" = ' AND ';
	$qry .= " WHERE @$filters" if @$filters;
	$qry .= ' GROUP BY label';
	my $values =
	  $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	my $freqs = {};

	foreach my $value (@$values) {
		$freqs->{ $value->{'label'} } = $value->{'count'};
	}
	return $freqs;
}

sub _get_filters {
	my ( $self, $params ) = @_;
	my $filters = [];
	push @$filters, 'v.new_version IS NULL' if !$params->{'include_old_versions'};
	if ( $params->{'record_age'} ) {
		my $datestamp = $self->get_record_age_datestamp( $params->{'record_age'} );
		push @$filters, "v.id IN (SELECT id FROM $self->{'system'}->{'view'} WHERE date_entered>='$datestamp')";
	}
	if ( $params->{'project_id'} ) {
		if ( BIGSdb::Utils::is_int( $params->{'project_id'} ) ) {
			push @$filters, "v.id IN (SELECT isolate_id FROM project_members WHERE project_id=$params->{'project_id'})";
		}
	}
	return $filters;
}

sub _print_filters {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset style="float:right"><legend>Filters</legend>);
	say q(<ul><li>);
	say $q->checkbox(
		-name  => 'include_old_versions',
		-id    => 'include_old_versions',
		-value => 'true',
		-label => 'Include old record versions'
	);
	my $record_age        = $q->param('record_age') // 0;
	my $record_age_labels = RECORD_AGE;
	say qq(</li><li>Record age: <span id="record_age">$record_age_labels->{$record_age}</span>);
	say q(<div id="record_age_slider" style="width:150px;margin-top:5px"></div>);
	say q(</li></ul>);
	say q(</fieldset>);
	return;
}

sub get_title {
	my ($self) = @_;
	return 'Data explorer';
}

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery noCache bigsdb.dataexplorer jQuery.tablesort);
	$self->set_level1_breadcrumbs;
	my $q = $self->{'cgi'};
	foreach my $ajax_param (qw(updateTable analyse)) {
		if ( $q->param($ajax_param) ) {
			$self->{'type'} = 'no_header';
			last;
		}
	}
	return;
}

sub get_javascript {
	my ($self) = @_;
	return if ( $self->{'system'}->{'dbtype'} // q() ) ne 'isolates';
	my $json              = JSON->new->allow_nonref;
	my $record_age_labels = $json->encode(RECORD_AGE);
	my $q                 = $self->{'cgi'};
	my $field             = $q->param('field')      // q();
	my $record_age        = $q->param('record_age') // 0;
	my $buffer            = << "END";
	var url = "$self->{'system'}->{'script_name'}?db=$self->{'instance'}";
	var instance = "$self->{'instance'}";
	var recordAgeLabels = $record_age_labels;
	var recordAge = $record_age;
	var field = "$field";
END
	my $project_id = $q->param('project_id');

	if ($project_id) {
		$buffer .= qq(    var projectId=$project_id;\n);
	}
	return $buffer;
}

#Override Dashboard::print_panel_buttons.
sub print_panel_buttons {
}
1;
