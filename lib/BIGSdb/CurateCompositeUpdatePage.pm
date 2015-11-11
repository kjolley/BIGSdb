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
package BIGSdb::CurateCompositeUpdatePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use BIGSdb::Utils;
use BIGSdb::Constants qw(:interface);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return qq(Update composite field - $desc);
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $q->param('id');
	say qq(<h1>Update composite field - $id</h1>);
	if ( !$self->can_modify_table('composite_fields') ) {
		say q(<div class="box" id="statusbad"><p>Your user account is not )
		  . q(allowed to update composite fields.</p></div>);
		return;
	}
	my $exists = $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM composite_fields WHERE id=?)', $id );
	if ( !$exists ) {
		say qq(<div class="box" id="statusbad">Composite field '$id' has not been defined.</div>);
		return;
	}
	say q(<div class="box" id="resultstable">);
	$self->_update_position($id) if $q->param('update');
	$self->_print_position_form($id);
	say $q->start_form;
	say q(<table class="resultstable">);
	my $td = 1;
	say qq(<tr class="td$td"><th>field</th><th>empty value</th><th>regex</th><th>curator</th>)
	  . q(<th>datestamp</th><th>delete</th><th>edit</th><th>move</th></tr>);
	my $data_arrayref = $self->_get_field_data($id);
	my $highest =
	  $self->{'datastore'}
	  ->run_query( 'SELECT max(field_order) FROM composite_field_values WHERE composite_field_id=?', $id );
	my ( $edit_buffer, $add_buffer );

	foreach my $data (@$data_arrayref) {
		my $field       = $data->{'field'};
		my $field_order = $data->{'field_order'};
		if ( $q->param("${field_order}_up") || $q->param("${field_order}_down") ) {
			$self->_swap_positions( $id, $field_order, $highest );
		} elsif ( $q->param("${field_order}_delete") ) {
			$self->_delete_field( $id, $field_order );
		} elsif ( $q->param("${field_order}_edit") ) {
			$edit_buffer = $self->_edit_field( $id, $data, $field, $field_order );
		}
	}
	if ( $q->param('update_field') ) {
		$self->_update_field($id);
	} elsif (
		any {
			$q->param("new_$_");
		}
		qw (text locus scheme_field isolate_field)
	  )
	{
		$self->_new_field($id);
	}
	$data_arrayref = $self->_get_field_data($id);
	foreach my $data (@$data_arrayref) {
		my ( $field, $missing );
		if ( $data->{'field'} =~ /^f_(.+)/x ) {
			$field = qq(<span class="field">$1</span> <span class="comment">[isolate field]</span>);
			$missing = defined $data->{'empty_value'} ? qq(<span class="field">$data->{'empty_value'}</span>) : q();
		} elsif ( $data->{'field'} =~ /^l_(.+)/x ) {
			my $locus = $1;
			$field = qq(<span class="locus">$locus</span> <span class="comment">[locus]</span>);
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			$missing = defined $data->{'empty_value'} ? qq(<span class="locus">$data->{'empty_value'}</span>) : q();
			if ( !$locus_info ) {
				$field .= qq( <span class="statusbad">(INVALID LOCUS)</span>\n);
			}
		} elsif ( $data->{'field'} =~ /^s_(\d+)_(.+)/x ) {
			my $scheme_id         = $1;
			my $field_value       = $2;
			my $scheme_info       = $self->{'datastore'}->get_scheme_info($scheme_id);
			my $desc              = $scheme_info->{'description'};
			my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field_value );
			$field = qq(<span class="scheme">$field_value</span>);
			$field .= qq( <span class="comment">[$desc field]</span>) if $desc;
			if ( !$scheme_field_info ) {
				$field .= qq( <span class="statusbad">(INVALID SCHEME FIELD)</span>\n);
			}
			$missing = defined $data->{'empty_value'} ? qq(<span class="scheme">$data->{'empty_value'}</span>) : q();
		} elsif ( $data->{'field'} =~ /^t_(.+)/x ) {
			$field   = qq(<span class="text">$1</span>);
			$missing = qq(<span class="text">$1</span>);
		}
		my $curator = $self->{'datastore'}->get_user_info( $data->{'curator'} );
		say qq(<tr class="td$td">);
		say qq(<td>$field</td>);
		say defined $data->{'empty_value'} ? qq(<td>$data->{'empty_value'}</td>)        : q(<td></td>);
		say defined $data->{'regex'}       ? qq(<td class="code">$data->{'regex'}</td>) : q(<td></td>);
		say qq(<td>$curator->{'first_name'} $curator->{'surname'}</td><td>$data->{'datestamp'}</td><td>);
		my ( $UP, $DOWN, $EDIT, $DELETE ) = ( UP, DOWN, EDIT, DELETE );
		say qq(<button type="submit" name="$data->{'field_order'}_delete" )
		  . qq(value="delete" class="smallbutton">$DELETE</button>);
		say q(</td><td>);
		say qq(<button type="submit" name="$data->{'field_order'}_edit" )
		  . qq(value="edit" class="smallbutton">$EDIT</button>);
		say q(</td><td>);
		say qq(<button type="submit" name="$data->{'field_order'}_up" )
		  . qq(value="up" class="smallbutton">$UP</button>);
		say qq(<button type="submit" name="$data->{'field_order'}_down" )
		  . qq(value="down" class="smallbutton">$DOWN</button>);
		say q(</td></tr>);
		$td = $td == 1 ? 2 : 1;    #row stripes
	}
	say q(</table>);
	say $q->hidden($_) foreach qw (db page id);
	say $q->end_form;
	if ( !$edit_buffer ) {
		$add_buffer = $self->_print_add_field_form;
	}
	say $edit_buffer || $add_buffer;
	say q(</div>);
	return;
}

sub _update_position {
	my ( $self, $id ) = @_;
	my $q              = $self->{'cgi'};
	my $position_after = $q->param('position_after');
	if ( !$self->{'xmlHandler'}->is_field($position_after) ) {
		say q(<p><span class="statusbad">'Position after' field '$position_after' is invalid.</span></p>);
		$q->param( 'position_after', '' );
	} else {
		my $main_display = $q->param('main_display');
		my $curator_id   = $self->get_curator_id;
		eval {
			$self->{'db'}
			  ->do( 'UPDATE composite_fields SET (position_after,main_display,curator,datestamp)=(?,?,?,?) WHERE id=?',
				undef, $position_after, $main_display, $curator_id, 'now', $id );
		};
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
		}
	}
	return;
}

sub _print_position_form {
	my ( $self, $id ) = @_;
	my $q = $self->{'cgi'};
	say $q->start_form;
	my $field_info =
	  $self->{'datastore'}
	  ->run_query( 'SELECT position_after,main_display,curator,datestamp FROM composite_fields WHERE id=?',
		$id, { fetch => 'row_arrayref' } );
	say q(<fieldset><legend>Position/display</legend>);
	say q(<ul><li>);
	say q(<label for="position_after">position after: <label>);
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	print $q->popup_menu(
		-name    => 'position_after',
		-id      => 'position_after',
		-values  => $field_list,
		-default => $field_info->[0]
	);

	if ( !$self->{'xmlHandler'}->is_field( $field_info->[0] ) ) {
		say qq(</td><td class="statusbad">Current value '$field_info->[0]' is INVALID!</td></tr>);
	}
	say q(</li><li>);
	say q(<label for="main_display">main display: </label>);
	say $q->radio_group(
		-name    => 'main_display',
		-id      => 'main_display',
		-values  => [qw (true false)],
		-default => $field_info->[1] ? 'true' : 'false'
	);
	say q(</li></ul>);
	say $q->submit( -name => 'update', -label => 'Update', -class => BUTTON_CLASS );
	say $q->hidden($_) foreach qw (db page id);
	say $q->end_form;
	say q(</fieldset>);
	return;
}

sub _print_add_field_form {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = qq(<fieldset><legend>Add new field:</legend>\n);
	$buffer .= $q->start_form;
	$q->param( new_isolate_field_value => q() );
	$q->param( new_text_value          => q() );
	$q->param( new_locus_value         => q() );
	$q->param( new_scheme_field_value  => q() );
	my $ADD = ADD;
	$buffer .= q(<ul><li>);
	$buffer .= q(<label for="new_text_value" class="parameter">text field: </label>);
	$buffer .= $q->textfield( -name => 'new_text_value', -id => 'new_text_value' );
	$buffer .= qq(<button type="submit" name="new_text" value="add" class="smallbutton">$ADD</button>);
	$buffer .= q(</li><li>);
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	$buffer .= q(<label for="new_isolate_field_value" class="parameter">isolate field: </label>);
	unshift @$field_list, '';
	$buffer .=
	  $q->popup_menu( -name => 'new_isolate_field_value', -id => 'new_isolate_field_value', -values => $field_list );
	$buffer .= qq(<button type="submit" name="new_isolate_field" value="add" class="smallbutton">$ADD</button>);
	$buffer .= q(</li><li>);
	my $locus_list = $self->{'datastore'}->get_loci;
	unshift @$locus_list, '';
	$buffer .= q(<label for="new_locus_value" class="parameter">locus field: </label>);
	$buffer .= $q->popup_menu( -name => 'new_locus_value', -id => 'new_locus_value', -values => $locus_list );
	$buffer .= qq(<button type="submit" name="new_locus" value="add" class="smallbutton">$ADD</button>);
	$buffer .= q(</li><li>);
	my @scheme_field_list = '';
	my %cleaned;
	my $scheme_list =
	  $self->{'datastore'}
	  ->run_query( 'SELECT id FROM schemes ORDER BY display_order,id', undef, { fetch => 'col_arrayref' } );

	foreach my $scheme_id (@$scheme_list) {
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		foreach my $field (@$scheme_fields) {
			push @scheme_field_list, "$scheme_id\_$field";
			my $scheme_info   = $self->{'datastore'}->get_scheme_info($scheme_id);
			my $cleaned_field = $field;
			$cleaned_field =~ tr/_/ /;
			$cleaned{"$scheme_id\_$field"} = "$cleaned_field ($scheme_info->{'description'})";
		}
	}
	$buffer .= q(<label for="new_scheme_field_value" class="parameter">scheme field: </label>);
	$buffer .= $q->popup_menu(
		-name   => 'new_scheme_field_value',
		-id     => 'new_scheme_field_value',
		-values => \@scheme_field_list,
		-labels => \%cleaned
	);
	$buffer .= qq(<button type="submit" name="new_scheme_field" value="add" class="smallbutton">$ADD</button>);
	$buffer .= qq(</li></ul>\n);
	$buffer .= $q->hidden($_) foreach qw (db page id);
	$buffer .= $q->end_form;
	$buffer .= qq(</fieldset>\n);
	return $buffer;
}

sub _get_field_data {
	my ( $self, $id ) = @_;
	return $self->{'datastore'}
	  ->run_query( 'SELECT * FROM composite_field_values WHERE composite_field_id=? ORDER BY field_order',
		$id, { fetch => 'all_arrayref', slice => {} } );
}

sub _swap_positions {
	my ( $self, $id, $field_order, $highest ) = @_;
	my $q = $self->{'cgi'};
	my $sql =
	  $self->{'db'}
	  ->prepare('UPDATE composite_field_values SET field_order=? WHERE (field_order,composite_field_id)=(?,?)');
	if ( $q->param("${field_order}_up") ) {
		if ( $field_order > 1 ) {

			#swap position with field above
			eval {
				$sql->execute( 0,                $field_order,     $id );
				$sql->execute( $field_order,     $field_order - 1, $id );
				$sql->execute( $field_order - 1, 0,                $id );
			};
			if ($@) {
				$logger->error("Can't update composite_field_values order $@");
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
			}
		}
	} elsif ( $q->param("${field_order}_down") ) {
		if ( $field_order < $highest ) {
			eval {
				$sql->execute( 0,                $field_order,     $id );
				$sql->execute( $field_order,     $field_order + 1, $id );
				$sql->execute( $field_order + 1, 0,                $id );
			};
			if ($@) {
				$logger->error("Can't update composite_field_values order $@");
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
			}
		}
	}
	return;
}

sub _delete_field {
	my ( $self, $id, $field_order ) = @_;

	#delete and close up gaps in field_order numbers
	eval {
		$self->{'db'}->do( 'DELETE FROM composite_field_values WHERE (field_order,composite_field_id)=(?,?)',
			undef, $field_order, $id );
		my $max =
		  $self->{'datastore'}
		  ->run_query( 'SELECT MAX(field_order) FROM composite_field_values WHERE composite_field_id=?', $id );
		for my $i ( 1 .. $max ) {
			my $count = $self->{'datastore'}->run_query(
				'SELECT COUNT(*) FROM composite_field_values WHERE (composite_field_id,field_order)=(?,?)',
				[ $id, $i ],
				{ cache => 'CurateCompositeUpdatePage::delete_field::count_values' }
			);
			if ( !$count ) {
				my $field_orders = $self->{'datastore'}->run_query(
					'SELECT field_order FROM composite_field_values WHERE composite_field_id=? '
					  . 'AND field_order>? ORDER BY field_order',
					[ $id, $i ],
					{ fetch => 'col_arrayref', cache => 'CurateCompositeUpdatePage::delete_field::order' }
				);
				my $next = $i;
				foreach my $old_order (@$field_orders) {
					$self->{'db'}->do(
						'UPDATE composite_field_values SET field_order=? WHERE (composite_field_id,field_order)=(?,?)',
						undef, $next, $id, $old_order
					);
					$next++;
				}
			}
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

sub _edit_field {
	my ( $self, $id, $data, $field, $field_order ) = @_;
	my $q = $self->{'cgi'};
	my $buffer;
	my $invalid = 0;
	$buffer .= qq(<fieldset><legend>Edit field</legend>\n);
	$buffer .= $q->start_form;
	my $text_field;
	$buffer .= q(<ul><li>);
	$buffer .= q(<label for="field_value" class="parameter">Field: </label>);

	if ( $field =~ /^f_(.+)/x ) {
		my $field_value      = $1;
		my $is_isolate_field = 0;
		my @field_list;
		my %cleaned;
		foreach ( @{ $self->{'xmlHandler'}->get_field_list() } ) {
			if ( $_ eq $field_value ) {
				$is_isolate_field = 1;
			}
			push @field_list, "f_$_";
			$cleaned{"f_$_"} = $_;
		}
		if ($is_isolate_field) {
			$buffer .= $q->popup_menu(
				-name    => 'field_value',
				-id      => 'field_value',
				-values  => [@field_list],
				-default => "f_$field_value",
				-labels  => \%cleaned
			);
		} else {
			$buffer .= qq(<span class="statusbad">$field_value (INVALID FIELD)</span>\n);
			$invalid = 1;
		}
	} elsif ( $field =~ /^t_(.+)/x ) {
		my $field_value = $1;
		$buffer .= $q->textfield( -name => 'field_value', -default => $field_value );
		$text_field = 1;
	} elsif ( $field =~ /^l_(.+)/x ) {
		my $field_value = $1;
		my $is_locus    = 0;
		my @locus_list;
		my %cleaned;
		foreach ( @{ $self->{'datastore'}->get_loci } ) {
			if ( $_ eq $field_value ) {
				$is_locus = 1;
			}
			push @locus_list, "l_$_";
			$cleaned{"l_$_"} = $_;
		}
		if ($is_locus) {
			$buffer .= $q->popup_menu(
				-name    => 'field_value',
				-values  => [@locus_list],
				-default => "l_$field_value",
				-labels  => \%cleaned
			);
		} else {
			$buffer .= qq(<span class="statusbad">$field_value (INVALID LOCUS)</span>\n);
			$invalid = 1;
		}
	} elsif ( $field =~ /^s_(\d+)_(.+)/x ) {
		my $scheme_id       = $1;
		my $field_value     = $2;
		my $is_scheme_field = 0;
		my @scheme_field_list;
		my %cleaned;
		my $scheme_list =
		  $self->{'datastore'}
		  ->run_query( 'SELECT id FROM schemes ORDER BY display_order,id', undef, { fetch => 'col_arrayref' } );
		foreach my $s_id (@$scheme_list) {
			foreach ( @{ $self->{'datastore'}->get_scheme_fields($s_id) } ) {
				if ( $_ eq $field_value && $s_id eq $scheme_id ) {
					$is_scheme_field = 1;
				}
				push @scheme_field_list, "s_$s_id\_$_";
				my $scheme_info   = $self->{'datastore'}->get_scheme_info($s_id);
				my $cleaned_field = $_;
				$cleaned_field =~ tr/_/ /;
				$cleaned{"s_$s_id\_$_"} = "$cleaned_field ($scheme_info->{'description'})";
			}
		}
		if ($is_scheme_field) {
			$buffer .= $q->popup_menu(
				-name    => 'field_value',
				-values  => [@scheme_field_list],
				-default => "s_$scheme_id\_$field_value",
				-labels  => \%cleaned
			);
		} else {
			$buffer .= qq(<span class="statusbad">$field_value (INVALID SCHEME FIELD)</span>\n);
			$invalid = 1;
		}
	}
	if ( !$invalid ) {
		$buffer .= q(</li><li>);
		$buffer .= q(<label for="empty_value" class="parameter">Empty value: </label>);
		if ($text_field) {
			$buffer .= $q->textfield(
				-name     => 'empty_value',
				-id       => 'empty_value',
				-default  => $data->{'empty_value'},
				-disabled => 'disabled'
			);
		} else {
			$buffer .=
			  $q->textfield( -name => 'empty_value', -id => 'empty_value', -default => $data->{'empty_value'}, );
		}
		$buffer .= q(</li><li>);
		$buffer .= q(<label for="regex" class="parameter">Regex: </label>);
		if ($text_field) {
			$buffer .= $q->textfield( -name => 'regex', -id => 'regex', -size => 50, -disabled => 'disabled' );
		} else {
			$buffer .= $q->textfield(
				-name    => 'regex',
				-id      => 'regex',
				-default => $data->{'regex'},
				-size    => 50,
				-class   => 'code'
			);
		}
		$buffer .= q(</li>);
	}
	$buffer .= q(</ul>);
	$buffer .= $q->submit( -name => 'update_field', -label => 'Update', -class => BUTTON_CLASS );
	$buffer .= $q->hidden($_) foreach qw (db page id);
	$buffer .= $q->hidden( field_order => $field_order );
	$buffer .= $q->end_form;
	$buffer .= qq(</fieldset>\n);
	return $buffer;
}

sub _update_field {
	my ( $self, $id ) = @_;
	my $q           = $self->{'cgi'};
	my $field_value = $q->param('field_value');
	$field_value = "t_$field_value" if $field_value !~ /^[flst]_/x;
	my $field_order = $q->param('field_order');
	my $empty_value = $q->param('empty_value');
	my $curator_id  = $self->get_curator_id;
	my $regex       = $q->param('regex');
	if ( BIGSdb::Utils::is_int($field_order) ) {
		eval {
			$self->{'db'}->do(
				'UPDATE composite_field_values SET (field,empty_value,regex,curator,datestamp)=(?,?,?,?,?) '
				  . 'WHERE (field_order,composite_field_id)=(?,?)',
				undef, $field_value, $empty_value, $regex, $curator_id, 'now', $field_order, $id
			);
		};
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
		}
	}
	return;
}

sub _new_field {
	my ( $self, $id ) = @_;
	my $q = $self->{'cgi'};
	my $next =
	  $self->{'datastore'}
	  ->run_query( 'SELECT MAX(field_order) FROM composite_field_values WHERE composite_field_id=?', $id );
	$next //= 0;
	$next++;
	my $field_value;
	my $prefix;
	if ( $q->param('new_text') ) {
		$field_value = $q->param('new_text_value');
		$prefix      = 't_';
	} elsif ( $q->param('new_locus') ) {
		$field_value = $q->param('new_locus_value');
		$prefix      = 'l_';
	} elsif ( $q->param('new_scheme_field') ) {
		$field_value = $q->param('new_scheme_field_value');
		$prefix      = 's_';
	} elsif ( $q->param('new_isolate_field') ) {
		$field_value = $q->param('new_isolate_field_value');
		$prefix      = 'f_';
	}
	my $curator = $self->get_curator_id;
	if ($field_value) {
		$field_value = "$prefix$field_value";
		eval {
			$self->{'db'}->do(
				'INSERT INTO composite_field_values (composite_field_id,field_order,'
				  . 'field,empty_value,regex,curator,datestamp) VALUES (?,?,?,?,?,?,?)',
				undef, $id, $next, $field_value, undef, undef, $curator, 'now'
			);
		};
		if ($@) {
			$logger->error($@);
			$self->{'db'}->rollback;
		} else {
			$self->{'db'}->commit;
		}
	}
	return;
}
1;
