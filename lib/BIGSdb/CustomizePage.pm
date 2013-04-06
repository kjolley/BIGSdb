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
package BIGSdb::CustomizePage;
use strict;
use warnings;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery tooltips noCache);
	return;
}

sub print_content {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my $table     = $q->param('table');
	my $record    = $self->get_record_name($table);
	my $filename  = $q->param('filename');
	my $prefstore = $self->{'prefstore'};
	my $guid      = $self->get_guid;
	$prefstore->update_datestamp($guid) if $guid;
	print "<h1>Customize $record display</h1>\n";

	if ( !$q->cookie('guid') ) {
		print <<"HTML";
<div class="box" id="statusbad">
<h2>Unable to proceed</h2>
<p class="statusbad">In order to store options, a cookie needs to be saved on your computer. Cookies appear to be disabled, however.  
Please enable them in your browser settings to proceed.</p>
</div>
HTML
		return;
	}
	if ( !$filename ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No $record data passed.</p></div>\n";
		return;
	}
	if ( !$table
		|| ( none { $table eq $_ } qw (loci scheme_fields schemes) ) )
	{
		print "<div class=\"box\" id=\"statusbad\"><p>Table '$table' is not a valid table customization.</p></div>\n";
		return;
	}
	my $file = $self->{'config'}->{'secure_tmp_dir'} . '/' . $filename;
	my $qry;
	if ( -e $file ) {
		if ( open( my $fh, '<', $file ) ) {
			$qry = <$fh>;
			close $fh;
		}
	} else {
		print "<div class=\"box\" id=\"statusbad\"><p>Can't open query.</p></div>\n";
		$logger->error("Can't open query file $file");
	}
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my ( @display, @cleaned_headers );
	my %type;
	foreach my $att (@$attributes) {
		next if $att->{'hide'} eq 'yes';
		if (   $att->{'primary_key'}
			|| $att->{'name'} =~ /display/
			|| ( any { $att->{'name'} eq $_ } qw (description query_field analysis) )
			|| ( $att->{'name'} eq 'dropdown' && $table eq 'scheme_fields' ) )
		{
			push @display, $att->{'name'};
			my $cleaned = $att->{'name'};
			$cleaned =~ tr/_/ /;
			push @cleaned_headers, $cleaned;
			$type{ $att->{'name'} } = $att->{'type'};
		}
	}
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my @retval = $sql->fetchrow_array;
	if ( !@retval ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No matches found!</p></div>\n";
		return;
	}
	$sql->finish;
	eval { $sql->execute };
	$logger->error($@) if $@;
	print $q->start_form;
	local $" = '</th><th>';
	print "<div class=\"box\" id=\"resultstable\">";
	print "<p>Here you can customize the display of $record records.  These settings will be remembered between sessions.  "
	  . "Click the checkboxes to select loci and select the required option for each attribute.</p>\n";
	print "<table class=\"resultstable\">\n";
	print "<tr><th>Select</th><th>@cleaned_headers</th></tr>\n";
	my $td = 1;
	local $" = "&amp;";
	my ( @js, @js2 );
	my ( $updated, $not_default ) = ( 0, 0 );

	while ( my $data = $sql->fetchrow_hashref ) {
		print "<tr class=\"td$td\"><td>";
		my $id;
		if ( $table eq 'loci' || $table eq 'schemes' ) {
			$id = "id_$data->{'id'}";
		} elsif ( $table eq 'scheme_fields' ) {
			$id = "field_$data->{'scheme_id'}_$data->{'field'}";
		}
		my $cleaned_id = $self->clean_checkbox_id($id);
		print $q->checkbox( -name => $id, -id => $cleaned_id, -label => '', -checked => 'checked' );
		push @js,  "\$(\"#$cleaned_id\").prop(\"checked\",true)";
		push @js2, "\$(\"#$cleaned_id\").prop(\"checked\",false)";
		print "</td>";
		my @args = ( \@display, $data, $prefstore, $guid, \$updated, \$not_default );
		if ( $table eq 'loci' ) {
			$self->_process_loci(@args);
		} elsif ( $table eq 'scheme_fields' ) {
			$self->_process_scheme_fields(@args);
		} elsif ( $table eq 'schemes' ) {
			$self->_process_schemes(@args);
		}
		print "</tr>\n";
		$td = $td == 2 ? 1 : 2;
	}
	print "</table><p />\n";
	print "<p>";
	print " <span class=\"highlight\">* Value updated</span>" if $updated;
	print " <span class=\"non-default\">&#134; Non-default value (overridden by user selection)</span>"
	  if $not_default;
	print "</p>\n";
	print "<input type=\"button\" value=\"Select all\" onclick='@js' class=\"button\" />\n";
	print "<input type=\"button\" value=\"Select none\" onclick='@js2' class=\"button\" />";
	print "<noscript><span class=\"comment\"> Enable javascript for select buttons to work!</span></noscript>\n";
	print "</div>\n";
	print "<div class=\"box\" id=\"resultsheader\">";
	print "<table>";

	foreach my $att (@$attributes) {
		next
		  if $att->{'hide'} eq 'yes'
			  || ( ( none { $att->{'name'} eq $_ } qw (main_display isolate_display query_field analysis) )
				  && !( $att->{'name'} eq 'dropdown' && $table eq 'scheme_fields' ) );
		print "<tr><td style=\"text-align:right\">";
		my $cleaned = $att->{'name'};
		$cleaned =~ tr/_/ /;
		print "$cleaned: ";
		my $tooltip = $self->_get_tooltip( $att->{'name'} );
		print " <a class=\"tooltip\" title=\"$tooltip\">&nbsp;<i>i</i>&nbsp;</a>";
		print "</td><td>";

		if ( $att->{'type'} eq 'bool' ) {
			print $q->popup_menu( -name => $att->{'name'}, -values => [qw(true false)] );
		} elsif ( $att->{'optlist'} ) {
			my @values = split /;/, $att->{'optlist'};
			print $q->popup_menu( -name => $att->{'name'}, -values => [@values] );
		}
		print "</td><td>";
		print $q->submit( -name => "$att->{'name'}_change",  -label => 'Change',           -class => 'submit' );
		print $q->submit( -name => "$att->{'name'}_default", -label => 'Restore defaults', -class => 'button' );
		print "</td></tr>";
	}
	print "</table>\n";
	print "</div>\n";
	print $q->hidden($_) foreach qw (db page filename table);
	print $q->hidden( 'set', 1 );
	print $q->end_form;
	return;
}

sub _process_loci {
	my ( $self, $display, $data, $prefstore, $guid, $updated_ref, $not_default_ref ) = @_;
	my $q = $self->{'cgi'};
	foreach my $field (@$display) {
		if ( $q->param("$field\_change") && $q->param("id_$data->{'id'}") ) {
			my $value = $q->param($field);
			$prefstore->set_locus( $guid, $self->{'system'}->{'db'}, $data->{'id'}, $field, $value );
			print "<td>$value <span class=\"highlight\">*</span></td>";
			$$updated_ref = 1;
		} elsif ( $q->param("$field\_default") && $q->param("id_$data->{'id'}") ) {
			my $locus_info = $self->{'datastore'}->get_locus_info( $data->{'id'} );
			my $value      = $locus_info->{$field};
			if ( $field eq 'main_display' or $field eq 'query_field' or $field eq 'analysis' ) {
				$value = $value ? 'true' : 'false';
			}
			$prefstore->delete_locus( $guid, $self->{'system'}->{'db'}, $data->{'id'}, $field );
			print "<td>$value</td>";
		} else {
			my $value;
			if ( $field eq 'isolate_display' ) {
				$value = $self->{'prefs'}->{'isolate_display_loci'}->{ $data->{'id'} };
				my $locus_info = $self->{'datastore'}->get_locus_info( $data->{'id'} );
				if ( $value ne $locus_info->{'isolate_display'} ) {
					$value .= " <span class=\"non-default\">&#134;</span>";
					$$not_default_ref = 1;
				}
			} elsif ( $field eq 'main_display'
				or $field eq 'query_field'
				or $field eq 'analysis' )
			{
				$value =
				  $self->{'prefs'}->{"$field\_loci"}->{ $data->{'id'} }
				  ? 'true'
				  : 'false';
				my $locus_info = $self->{'datastore'}->get_locus_info( $data->{'id'} );
				if (   ( $value eq 'true' && !$locus_info->{$field} )
					|| ( $value eq 'false' && $locus_info->{$field} ) )
				{
					$value .= " <span class=\"non-default\">&#134;</span>";
					$$not_default_ref = 1;
				}
			} else {
				$value = $data->{$field};
				$value = $self->clean_locus($value) if $field eq 'id';
			}
			print "<td>$value</td>";
		}
	}
	return;
}

sub _process_scheme_fields {
	my ( $self, $display, $data, $prefstore, $guid, $updated_ref, $not_default_ref ) = @_;
	my $q = $self->{'cgi'};
	foreach my $field (@$display) {
		if (   $q->param("$field\_change")
			&& $q->param("field_$data->{'scheme_id'}\_$data->{'field'}") )
		{
			my $value = $q->param($field);
			$prefstore->set_scheme_field( $guid, $self->{'system'}->{'db'}, $data->{'scheme_id'}, $data->{'field'}, $field, $value );
			print "<td>$value <span class=\"highlight\">*</span></td>";
			$$updated_ref = 1;
		} elsif ( $q->param("$field\_default")
			&& $q->param("field_$data->{'scheme_id'}\_$data->{'field'}") )
		{
			my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $data->{'scheme_id'}, $data->{'field'} );
			my $value = $scheme_field_info->{$field} ? 'true' : 'false';
			$prefstore->delete_scheme_field( $guid, $self->{'system'}->{'db'}, $data->{'scheme_id'}, $data->{'field'}, $field );
			print "<td>$value</td>";
		} else {
			my $value;
			if ( any { $field eq $_ } qw (isolate_display main_display query_field dropdown) ) {
				$value =
				  $self->{'prefs'}->{"$field\_scheme_fields"}->{ $data->{'scheme_id'} }->{ $data->{'field'} }
				  ? 'true'
				  : 'false';
				my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $data->{'scheme_id'}, $data->{'field'} );
				if (   ( $value eq 'true' && !$scheme_field_info->{$field} )
					|| ( $value eq 'false' && $scheme_field_info->{$field} ) )
				{
					$value .= " <span class=\"non-default\">&#134;</span>";
					$$not_default_ref = 1;
				}
			} else {
				$value = $data->{$field};
			}
			print defined $value ? "<td>$value</td>" : '<td />';
		}
	}
	return;
}

sub _process_schemes {
	my ( $self, $display, $data, $prefstore, $guid, $updated_ref, $not_default_ref ) = @_;
	my $q = $self->{'cgi'};
	foreach my $field (@$display) {
		if (   $q->param("$field\_change")
			&& $q->param("id_$data->{'id'}") )
		{
			my $value = $q->param($field);
			$prefstore->set_scheme( $guid, $self->{'system'}->{'db'}, $data->{'id'}, $field, $value );
			print "<td>$value <span class=\"highlight\">*</span></td>";
			$$updated_ref = 1;
		} elsif ( $q->param("$field\_default")
			&& $q->param("id_$data->{'id'}") )
		{
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $data->{'id'} );
			my $value = $scheme_info->{$field} ? 'true' : 'false';
			$prefstore->delete_scheme( $guid, $self->{'system'}->{'db'}, $data->{'id'}, $field );
			print "<td>$value</td>";
		} else {
			my $value;
			if ( any { $field eq $_ } qw (isolate_display main_display query_field analysis) ) {
				$value =
				  $self->{'prefs'}->{"$field\_schemes"}->{ $data->{'id'} }
				  ? 'true'
				  : 'false';
				my $scheme_info = $self->{'datastore'}->get_scheme_info( $data->{'id'} );
				if (   ( $value eq 'true' && !$scheme_info->{$field} )
					|| ( $value eq 'false' && $scheme_info->{$field} ) )
				{
					$value .= " <span class=\"non-default\">&#134;</span>";
					$$not_default_ref = 1;
				}
			} else {
				$value = $data->{$field};
			}
			print defined $value ? "<td>$value</td>" : '<td />';
		}
	}
	return;
}

sub _get_tooltip {
	my ( $self, $action ) = @_;
	my $table = $self->{'cgi'}->param('table');
	my $record = $table eq 'schemes' ? 'scheme fields and loci' : $self->get_record_name($table);
	my $value;
	if ( $action eq 'isolate_display' ) {
		my $t = $table eq 'loci' ? 'how' : 'whether';
		$value = "isolate_display - Sets $t to display the $record in the isolate information page.";
	} elsif ( $action eq 'main_display' ) {
		$value = "main_display - Sets whether to display the $record in the isolate query results table.";
	} elsif ( $action eq 'query_field' ) {
		my $plural = $table eq 'schemes' ? '' : 's';
		$value =
"query_field - Sets whether the $record can be used in isolate queries.  This setting affects whether the $record appear$plural in the drop-down list boxes in the query interfaces.";
	} elsif ( $action eq 'analysis' ) {
		my $plural = $table eq 'schemes' ? '' : 's';
		$value = "analysis - Sets whether the $record can be used in data analysis functions.";
	} elsif ( $action eq 'dropdown' ) {
		$value = "dropdown - Sets whether the $record has a dropdown list box in the query interface.";
	}
	if ( $table eq 'schemes' ) {
		$value .= "  If set to 'false', this setting will override any display options for individual scheme loci or fields.";
	}
	return $value;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	my $record = $self->get_record_name( $self->{'cgi'}->param('table') );
	return "Customize $record display - $desc";
}
1;
