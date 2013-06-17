#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
use parent qw(BIGSdb::CuratePage);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Update composite field - $desc";
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $id     = $q->param('id');
	print "<h1>Update composite field - $id</h1>\n";
	if ( !$self->can_modify_table('composite_fields') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update composite fields.</p></div>\n";
		return;
	}
	my $exists = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM composite_fields WHERE id=?", $id )->[0];
	if ( !$exists ) {
		print "<div class=\"box\" id=\"statusbad\">Composite field '$id' has not been defined.</div>\n";
		return;
	}
	print "<div class=\"box\" id=\"resultstable\">\n";
	$self->_update_position($id) if $q->param('update');
	$self->_print_position_form($id);
	print $q->start_form;
	print "<table class=\"resultstable\">\n";
	my $td = 1;
	print "<tr class=\"td$td\"><th>field</th><th>empty value</th><th>regex</th><th>curator</th>"
	  . "<th>datestamp</th><th>delete</th><th>edit</th><th>move</th></tr>\n";
	my $data_arrayref = $self->_get_field_data($id);
	my $highest =
	  $self->{'datastore'}->run_simple_query( "SELECT max(field_order) FROM composite_field_values WHERE composite_field_id=?", $id )->[0];
	my ( $edit_buffer, $add_buffer );

	foreach my $data (@$data_arrayref) {
		my $field       = $data->{'field'};
		my $field_order = $data->{'field_order'};
		if ( $q->param("$field_order\_up") || $q->param("$field_order\_down") ) {
			$self->_swap_positions( $id, $field_order, $highest );
		} elsif ( $q->param("$field_order\_delete") ) {
			$self->_delete_field( $id, $field_order );
		} elsif ( $q->param("$field_order\_edit") ) {
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
		if ( $data->{'field'} =~ /^f_(.+)/ ) {
			$field = "<span class=\"field\">$1</span> <span class=\"comment\">[isolate field]</span>";
			$missing = defined $data->{'empty_value'} ? "<span class=\"field\">$data->{'empty_value'}</span>" : '';
		} elsif ( $data->{'field'} =~ /^l_(.+)/ ) {
			my $locus = $1;
			$field = "<span class=\"locus\">$locus</span> <span class=\"comment\">[locus]</span>";
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			$missing = defined $data->{'empty_value'} ? "<span class=\"locus\">$data->{'empty_value'}</span>" : '';
			if ( ref $locus_info ne 'HASH' ) {
				$field .= " <span class=\"statusbad\">(INVALID LOCUS)</span>\n";
			}
		} elsif ( $data->{'field'} =~ /^s_(\d+)_(.+)/ ) {
			my $scheme_id         = $1;
			my $field_value       = $2;
			my $scheme_info       = $self->{'datastore'}->get_scheme_info($scheme_id);
			my $desc              = $scheme_info->{'description'};
			my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field_value );
			$field = "<span class=\"scheme\">$field_value</span>";
			$field .= " <span class=\"comment\">[$desc field]</span>" if $desc;
			if ( ref $scheme_field_info ne 'HASH' ) {
				$field .= " <span class=\"statusbad\">(INVALID SCHEME FIELD)</span>\n";
			}
			$missing = defined $data->{'empty_value'} ? "<span class=\"scheme\">$data->{'empty_value'}</span>" : '';
		} elsif ( $data->{'field'} =~ /^t_(.+)/ ) {
			$field   = "<span class=\"text\">$1</span>";
			$missing = "<span class=\"text\">$1</span>";
		}
		my $curator = $self->{'datastore'}->get_user_info( $data->{'curator'} );
		print "<tr class=\"td$td\">";
		print "<td>$field</td>";
		print defined $data->{'empty_value'} ? "<td>$data->{'empty_value'}</td>"          : '<td></td>';
		print defined $data->{'regex'}       ? "<td class=\"code\">$data->{'regex'}</td>" : '<td></td>';
		print "<td>$curator->{'first_name'} $curator->{'surname'}</td><td>$data->{'datestamp'}</td><td>";
		print $q->submit( -name => "$data->{'field_order'}_delete", -label => 'delete', -class => 'smallbutton' );
		print "</td><td>";
		print $q->submit( -name => "$data->{'field_order'}_edit", -label => 'edit', -class => 'smallbutton' );
		print "</td><td>";
		print $q->submit( -name => "$data->{'field_order'}_up",   -label => 'up',   -class => 'smallbutton' );
		print $q->submit( -name => "$data->{'field_order'}_down", -label => 'down', -class => 'smallbutton' );
		print "</td>";
		print "</tr>\n";
		$td = $td == 1 ? 2 : 1;    #row stripes
	}
	print "</table>\n";
	print $q->hidden($_) foreach qw (db page id);
	print $q->end_form;
	if ( !$edit_buffer ) {
		$add_buffer = "<h2>Add new field:</h2>\n";
		$add_buffer .= $q->start_form;
		$add_buffer .= "<table><tr><td style=\"text-align:right\">";
		$q->param( 'new_isolate_field_value', '' );
		$q->param( 'new_text_value',          '' );
		$q->param( 'new_locus_value',         '' );
		$q->param( 'new_scheme_field_value',  '' );
		$add_buffer .= $q->textfield( -name => 'new_text_value' );
		$add_buffer .= "</td><td>";
		$add_buffer .= $q->submit( -name => 'new_text', -label => 'Add new text field', -class => 'smallbutton' );
		$add_buffer .= "</td></tr>\n<tr><td style=\"text-align:right\">";
		my $field_list = $self->{'xmlHandler'}->get_field_list;
		unshift @$field_list, '';
		$add_buffer .= $q->popup_menu( -name => 'new_isolate_field_value', -values => $field_list );
		$add_buffer .= "</td><td>";
		$add_buffer .= $q->submit( -name => 'new_isolate_field', -label => 'Add new isolate field', -class => 'smallbutton' );
		$add_buffer .= "</td></tr>\n<tr><td style=\"text-align:right\">";
		my $locus_list = $self->{'datastore'}->get_loci;
		unshift @$locus_list, '';
		$add_buffer .= $q->popup_menu( -name => 'new_locus_value', -values => $locus_list );
		$add_buffer .= "</td><td>";
		$add_buffer .= $q->submit( -name => 'new_locus', -label => 'Add new locus field', -class => 'smallbutton' );
		$add_buffer .= "</td></tr>\n<tr><td style=\"text-align:right\">";
		my @scheme_field_list = '';
		my %cleaned;
		my $scheme_list = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");

		foreach my $scheme_id (@$scheme_list) {
			my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
			foreach (@$scheme_fields) {
				push @scheme_field_list, "$scheme_id\_$_";
				my $scheme_info   = $self->{'datastore'}->get_scheme_info($scheme_id);
				my $cleaned_field = $_;
				$cleaned_field =~ tr/_/ /;
				$cleaned{"$scheme_id\_$_"} = "$cleaned_field ($scheme_info->{'description'})";
			}
		}
		$add_buffer .= $q->popup_menu( -name => 'new_scheme_field_value', -values => [@scheme_field_list], -labels => \%cleaned );
		$add_buffer .= "</td><td>";
		$add_buffer .= $q->submit( -name => 'new_scheme_field', -label => 'Add new scheme field', -class => 'smallbutton' );
		my $curator_name = $self->get_curator_name;
		$add_buffer .= "</td></tr>\n<tr><td style=\"text-align:right\"><b>curator: </b></td><td><b>$curator_name</b></td></tr>\n";
		$add_buffer .= "<tr><td style=\"text-align:right\"><b>datestamp: </b></td><td><b>" . ( $self->get_datestamp ) . "</b></td></tr>\n";
		$add_buffer .= "</table>\n";
		$add_buffer .= $q->hidden($_) foreach qw (db page id);
		$add_buffer .= $q->end_form;
	}
	print $edit_buffer || $add_buffer;
	print "</div>\n";
	return;
}

sub _update_position {
	my ( $self, $id ) = @_;
	my $q              = $self->{'cgi'};
	my $position_after = $q->param('position_after');
	if ( !$self->{'xmlHandler'}->is_field($position_after) ) {
		print "<p><span class=\"statusbad\">'Position after' field '$position_after' is invalid.</span></p>\n";
		$q->param( 'position_after', '' );
	} else {
		my $main_display = $q->param('main_display');
		my $curator_id   = $self->get_curator_id;
		my $sql = $self->{'db'}->prepare("UPDATE composite_fields SET position_after=?,main_display=?,curator=?,datestamp=? WHERE id=?");
		eval { $sql->execute( $position_after, $main_display, $curator_id, 'now', $id ) };
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
	print $q->start_form;
	my $field_info =
	  $self->{'datastore'}
	  ->run_simple_query( "SELECT position_after,main_display,curator,datestamp FROM composite_fields WHERE id=?", $id );
	print "<table><tr><td style=\"text-align:right\">position after: </td><td>";
	my $field_list = $self->{'xmlHandler'}->get_field_list;
	print $q->popup_menu( -name => 'position_after', -values => $field_list, -default => $field_info->[0] );
	if ( !$self->{'xmlHandler'}->is_field( $field_info->[0] ) ) {
		print "</td><td class=\"statusbad\">Current value '$field_info->[0]' is INVALID!</td></tr>\n";
	}
	print "</td></tr>\n";
	print "<tr><td style=\"text-align:right\">main display: </td><td>";
	print $q->popup_menu( -name => 'main_display', -values => [qw (true false)], -default => $field_info->[1] ? 'true' : 'false' );
	print "</td></tr>\n";
	my $curator_info = $self->{'datastore'}->get_user_info( $field_info->[2] );
	print "<tr><td style=\"text-align:right\">curator: </td><td>$curator_info->{'first_name'} $curator_info->{'surname'}</td></tr>\n";
	print "<tr><td style=\"text-align:right\">datestamp: </td><td>$field_info->[3]</td><td>";
	print $q->submit( -name => 'update', -label => 'Update', -class => 'submit' );
	print "</td></tr></table>\n";
	print $q->hidden($_) foreach qw (db page id);
	print $q->end_form;
	return;
}

sub _get_field_data {
	my ( $self, $id ) = @_;
	return $self->{'datastore'}
	  ->run_list_query_hashref( "SELECT * FROM composite_field_values WHERE composite_field_id=? ORDER BY field_order", $id );
}

sub _swap_positions {
	my ( $self, $id, $field_order, $highest ) = @_;
	my $q   = $self->{'cgi'};
	my $sql = $self->{'db'}->prepare("UPDATE composite_field_values SET field_order=? WHERE field_order=? AND composite_field_id=?");
	if ( $q->param("$field_order\_up") ) {
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
	} elsif ( $q->param("$field_order\_down") ) {
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
	my $sql  = $self->{'db'}->prepare("DELETE FROM composite_field_values WHERE field_order=? AND composite_field_id=?");
	my $sql2 = $self->{'db'}->prepare("SELECT COUNT(*) FROM composite_field_values WHERE composite_field_id=? AND field_order=?");
	my $sql3 =
	  $self->{'db'}
	  ->prepare("SELECT field_order FROM composite_field_values WHERE composite_field_id=? AND field_order>? ORDER BY field_order");
	my $sql4 = $self->{'db'}->prepare("UPDATE composite_field_values SET field_order=? WHERE composite_field_id=? AND field_order=?");
	eval {
		$sql->execute( $field_order, $id );

		#close up gaps in field_order numbers
		my $max =
		  $self->{'datastore'}->run_simple_query( "SELECT MAX(field_order) FROM composite_field_values WHERE composite_field_id=?", $id )
		  ->[0];
		for my $i ( 1 .. $max ) {
			$sql2->execute( $id, $i );
			my ($count) = $sql2->fetchrow_array;
			if ( !$count ) {
				$sql3->execute( $id, $i );
				my $next = $i;
				while ( my ($old_order) = $sql3->fetchrow_array ) {
					$sql4->execute( $next, $id, $old_order );
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
	$buffer .= $q->start_form;
	my $text_field;
	$buffer .= "<h2>Edit:</h2><table><tr><td style=\"text-align:right\">Field: </td><td>";
	if ( $field =~ /^f_(.+)/ ) {
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
			$buffer .=
			  $q->popup_menu( -name => 'field_value', -values => [@field_list], -default => "f_$field_value", -labels => \%cleaned );
		} else {
			$buffer .= "<span class=\"statusbad\">$field_value (INVALID FIELD)</span>\n";
			$invalid = 1;
		}
	} elsif ( $field =~ /^t_(.+)/ ) {
		my $field_value = $1;
		$buffer .= $q->textfield( -name => 'field_value', -default => $field_value );
		$text_field = 1;
	} elsif ( $field =~ /^l_(.+)/ ) {
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
			$buffer .=
			  $q->popup_menu( -name => 'field_value', -values => [@locus_list], -default => "l_$field_value", -labels => \%cleaned );
		} else {
			$buffer .= "<span class=\"statusbad\">$field_value (INVALID LOCUS)</span>\n";
			$invalid = 1;
		}
	} elsif ( $field =~ /^s_(\d+)_(.+)/ ) {
		my $scheme_id       = $1;
		my $field_value     = $2;
		my $is_scheme_field = 0;
		my @scheme_field_list;
		my %cleaned;
		my $scheme_list = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");
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
			$buffer .= "<span class=\"statusbad\">$field_value (INVALID SCHEME FIELD)</span>\n";
			$invalid = 1;
		}
	}
	if ( !$invalid ) {
		$buffer .= "</td></tr>\n<tr><td style=\"text-align:right\">Empty value: </td><td>";
		if ($text_field) {
			$buffer .= $q->textfield( -name => 'empty_value', -default => $data->{'empty_value'}, -disabled => 'disabled' );
		} else {
			$buffer .= $q->textfield( -name => 'empty_value', -default => $data->{'empty_value'}, );
		}
		$buffer .= "</td></tr>\n";
		$buffer .= "<tr><td style=\"text-align:right\">Regex: </td><td class=\"code\" colspan=\"2\">";
		if ($text_field) {
			$buffer .= $q->textfield( -name => 'regex', -size => 50, -disabled => 'disabled' );
		} else {
			$buffer .= $q->textfield( -name => 'regex', -default => $data->{'regex'}, -size => 50, -class => 'code' );
		}
		$buffer .= "</td></tr>\n";
		my $curator = $self->{'datastore'}->get_user_info( $data->{'curator'} );
		$buffer .= "<tr><td style=\"text-align:right\"><b>Curator: </b></td><td><b>" . ( $self->get_curator_name() ) . "</b></td></tr>\n";
		$buffer .=
		    "<tr><td style=\"text-align:right\"><b>Datestamp: </b></td><td><b>"
		  . ( $self->get_datestamp() )
		  . "</b></td><td style=\"text-align:right\">\n";
		$buffer .= $q->submit( -name => 'update_field', -label => 'Update', -class => 'submit' );
	}
	$buffer .= "</td></tr></table>\n";
	$buffer .= $q->hidden($_) foreach qw (db page id);
	$buffer .= $q->hidden( 'field_order', $field_order );
	$buffer .= $q->end_form;
	return $buffer;
}

sub _update_field {
	my ( $self, $id ) = @_;
	my $q           = $self->{'cgi'};
	my $field_value = $q->param('field_value');
	$field_value = "t_$field_value" if $field_value !~ /^[flst]_/;
	my $field_order = $q->param('field_order');
	my $empty_value = $q->param('empty_value');
	my $curator_id  = $self->get_curator_id;
	my $regex       = $q->param('regex');
	if ( BIGSdb::Utils::is_int($field_order) ) {
		my $sql =
		  $self->{'db'}->prepare( "UPDATE composite_field_values SET field=?,empty_value=?,regex=?,curator=?,"
			  . "datestamp=? WHERE field_order=? AND composite_field_id=?" );
		eval { $sql->execute( $field_value, $empty_value, $regex, $curator_id, 'now', $field_order, $id ) };
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
	my $next_ref =
	  $self->{'datastore'}->run_simple_query( "SELECT MAX(field_order) FROM composite_field_values WHERE composite_field_id=?", $id );
	my $next = ref $next_ref eq 'ARRAY' ? $next_ref->[0] : 0;
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
		my $sql =
		  $self->{'db'}->prepare( "INSERT INTO composite_field_values (composite_field_id,field_order,"
			  . "field,empty_value,regex,curator,datestamp) VALUES (?,?,?,?,?,?,?)" );
		eval { $sql->execute( $id, $next, $field_value, undef, undef, $curator, 'now' ) };
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
