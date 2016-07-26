#Written by Keith Jolley
#Copyright (c) 2010-2016, University of Oxford
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
use 5.010;
use parent qw(BIGSdb::Page);
use List::MoreUtils qw(any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery tooltips noCache);
	return;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_query.html#modifying-locus-and-scheme-display-options";
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
	say qq(<h1>Customize $record display</h1>);

	if ( !$q->cookie('guid') ) {
		say q(<div class="box" id="statusbad"><span class="warning_icon fa fa-thumbs-o-down fa-5x pull-left"></span>)
		  . q(<h2>Unable to proceed</h2><p class="statusbad">In order to store options, a cookie needs to be saved )
		  . q(on your computer. Cookies appear to be disabled, however. )
		  . q(Please enable them in your browser settings to proceed.</p></div>);
		return;
	}
	if ( !$filename ) {
		say qq(<div class="box" id="statusbad"><p>No $record data passed.</p></div>);
		return;
	}
	my %valid_table = map { $_ => 1 } qw (loci scheme_fields schemes);
	if ( !$table || !$valid_table{$table} ) {
		say qq(<div class="box" id="statusbad"><p>Table '$table' is not a valid table for customization.</p></div>);
		return;
	}
	my $file = "$self->{'config'}->{'secure_tmp_dir'}/$filename";
	my $qry;
	if ( -e $file ) {
		if ( open( my $fh, '<', $file ) ) {
			$qry = <$fh>;
			close $fh;
		}
	} else {
		say q(<div class="box" id="statusbad"><p>Can't open query.</p></div>);
		$logger->error("Can't open query file $file");
	}
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my ( @display, @cleaned_headers );
	my %type;
	foreach my $att (@$attributes) {
		next if $att->{'hide'} eq 'yes';
		if (   $att->{'primary_key'}
			|| $att->{'name'} =~ /display/
			|| ( any { $att->{'name'} eq $_ } qw (name query_field analysis disable) )
			|| ( $att->{'name'} eq 'dropdown' && $table eq 'scheme_fields' ) )
		{
			push @display, $att->{'name'};
			my $cleaned = $att->{'name'};
			$cleaned =~ tr/_/ /;
			push @cleaned_headers, $cleaned;
			$type{ $att->{'name'} } = $att->{'type'};
		}
	}
	my $results = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'all_arrayref', slice => {} } );
	if ( !@$results ) {
		say q(<div class="box" id="statusbad"><p>No matches found!</p></div>);
		return;
	}
	print $q->start_form;
	local $" = q(</th><th>);
	say q(<div class="box" id="resultstable">);
	say qq(<p>Here you can customize the display of $record records.  These settings will be remembered between )
	  . q(sessions. Click the checkboxes to select loci and select the required option for each attribute.</p>);
	say q(<div class="scrollable">);
	say q(<table class="resultstable">);
	say qq(<tr><th>Select</th><th>@cleaned_headers</th></tr>);
	my $td = 1;
	local $" = q(&amp;);
	my ( @js, @js2 );
	my ( $updated, $not_default ) = ( 0, 0 );

	foreach my $data (@$results) {
		say qq(<tr class="td$td"><td>);
		my $id = $table eq 'scheme_fields' ? "field_$data->{'scheme_id'}_$data->{'field'}" : "id_$data->{'id'}";
		my $cleaned_id = $self->clean_checkbox_id($id);
		print $q->checkbox( -name => $id, -id => $cleaned_id, -label => '', -checked => 'checked' );
		push @js,  qq(\$("#$cleaned_id").prop("checked",true));
		push @js2, qq(\$("#$cleaned_id").prop("checked",false));
		print q(</td>);
		my $args = {
			display         => \@display,
			data            => $data,
			prefstore       => $prefstore,
			guid            => $guid,
			updated_ref     => \$updated,
			not_default_ref => \$not_default
		};
		my %dispatch = (
			loci          => sub { $self->_process_loci($args) },
			schemes       => sub { $self->_process_schemes($args) },
			scheme_fields => sub { $self->_process_scheme_fields($args) }
		);
		$dispatch{$table}->();
		say q(</tr>);
		$td = $td == 2 ? 1 : 2;
	}
	say q(</table></div><p>);
	say q( <span class="highlight">* Value updated</span>) if $updated;
	say q( <span class="non-default">&#134; Non-default value (overridden by user selection)</span>)
	  if $not_default;
	say q(</p>);
	say qq(<input type="button" value="Select all" onclick='@js' class="button" />);
	say qq(<input type="button" value="Select none" onclick='@js2' class="button" />);
	say q(<noscript><span class="comment"> Enable javascript for select buttons to work!</span></noscript>);
	say q(</div>);
	say q(<div class="box" id="resultsheader"><div class="scrollable">);
	say q(<fieldset><legend>Modify options</legend><ul>);
	my %action = map { $_ => 1 } qw (main_display isolate_display query_field analysis disable);

	foreach my $att (@$attributes) {
		next
		  if $att->{'hide'} eq 'yes'
		  || ( !$action{ $att->{'name'} } && !( $att->{'name'} eq 'dropdown' && $table eq 'scheme_fields' ) );
		( my $cleaned = $att->{'name'} ) =~ tr/_/ /;
		my $tooltip = $self->_get_tooltip( $att->{'name'} );
		say qq(<li style="white-space:nowrap"><label for="$att->{'name'}" class="parameter" )
		  . qq(style="padding-top:0.7em">$cleaned <a class="tooltip" title="$tooltip">)
		  . q(<span class="fa fa-info-circle"></span></a></label>);
		if ( $att->{'type'} eq 'bool' ) {
			say $q->popup_menu( -name => $att->{'name'}, -id => $att->{'name'}, -values => [qw(true false)] );
		} elsif ( $att->{'optlist'} ) {
			my @values = split /;/x, $att->{'optlist'};
			say $q->popup_menu( -name => $att->{'name'}, -id => $att->{'name'}, -values => [@values] );
		}
		say $q->submit( -name => "$att->{'name'}_change",  -label => 'Change',           -class => 'button' );
		say $q->submit( -name => "$att->{'name'}_default", -label => 'Restore defaults', -class => 'button' );
		say q(</li>);
	}
	say q(</ul></fieldset></div></div>);
	print $q->hidden($_) foreach qw (db page filename table);
	print $q->hidden( set => 1 );
	print $q->end_form;
	return;
}

sub _process_loci {
	my ( $self, $args ) = @_;
	my ( $display, $data, $prefstore, $guid, $updated_ref, $not_default_ref ) =
	  @{$args}{qw (display data prefstore guid updated_ref not_default_ref)};
	my $q = $self->{'cgi'};
	foreach my $field (@$display) {
		if ( $q->param("${field}_change") && $q->param("id_$data->{'id'}") ) {
			my $value = $q->param($field);
			$prefstore->set_locus( $guid, $self->{'system'}->{'db'}, $data->{'id'}, $field, $value );
			print qq(<td>$value <span class="highlight">*</span></td>);
			$$updated_ref = 1;
		} elsif ( $q->param("$field\_default") && $q->param("id_$data->{'id'}") ) {
			my $locus_info = $self->{'datastore'}->get_locus_info( $data->{'id'} );
			my $value      = $locus_info->{$field};
			if ( $field eq 'main_display' or $field eq 'query_field' or $field eq 'analysis' ) {
				$value = $value ? 'true' : 'false';
			}
			$prefstore->delete_locus( $guid, $self->{'system'}->{'db'}, $data->{'id'}, $field );
			print qq(<td>$value</td>);
		} else {
			my $value;
			if ( $field eq 'isolate_display' ) {
				$value = $self->{'prefs'}->{'isolate_display_loci'}->{ $data->{'id'} };
				my $locus_info = $self->{'datastore'}->get_locus_info( $data->{'id'} );
				if ( $value ne $locus_info->{'isolate_display'} ) {
					$value .= q( <span class="non-default">&#134;</span>);
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
					$value .= q( <span class="non-default">&#134;</span>);
					$$not_default_ref = 1;
				}
			} else {
				$value = $data->{$field};
				$value = $self->clean_locus($value) if $field eq 'id';
			}
			print qq(<td>$value</td>);
		}
	}
	return;
}

sub _process_scheme_fields {
	my ( $self, $args ) = @_;
	my ( $display, $data, $prefstore, $guid, $updated_ref, $not_default_ref ) =
	  @{$args}{qw (display data prefstore guid updated_ref not_default_ref)};
	my $q = $self->{'cgi'};
	foreach my $field (@$display) {
		if (   $q->param("${field}_change")
			&& $q->param("field_$data->{'scheme_id'}\_$data->{'field'}") )
		{
			my $value = $q->param($field);
			$prefstore->set_scheme_field(
				{
					guid      => $guid,
					dbase     => $self->{'system'}->{'db'},
					scheme_id => $data->{'scheme_id'},
					field     => $data->{'field'},
					action    => $field,
					value     => $value
				}
			);
			print qq(<td>$value <span class="highlight">*</span></td>);
			$$updated_ref = 1;
		} elsif ( $q->param("${field}_default")
			&& $q->param("field_$data->{'scheme_id'}_$data->{'field'}") )
		{
			my $scheme_field_info =
			  $self->{'datastore'}->get_scheme_field_info( $data->{'scheme_id'}, $data->{'field'} );
			my $value = $scheme_field_info->{$field} ? 'true' : 'false';
			$prefstore->delete_scheme_field( $guid, $self->{'system'}->{'db'},
				$data->{'scheme_id'}, $data->{'field'}, $field );
			print qq(<td>$value</td>);
		} else {
			my $value;
			if ( any { $field eq $_ } qw (isolate_display main_display query_field dropdown) ) {
				$value =
				  $self->{'prefs'}->{"$field\_scheme_fields"}->{ $data->{'scheme_id'} }->{ $data->{'field'} }
				  ? 'true'
				  : 'false';
				my $scheme_field_info =
				  $self->{'datastore'}->get_scheme_field_info( $data->{'scheme_id'}, $data->{'field'} );
				if (   ( $value eq 'true' && !$scheme_field_info->{$field} )
					|| ( $value eq 'false' && $scheme_field_info->{$field} ) )
				{
					$value .= q( <span class="non-default">&#134;</span>);
					$$not_default_ref = 1;
				}
			} else {
				if ( $field eq 'scheme_id' ) {
					if ( !$self->{'cache'}->{'scheme'}->{ $data->{$field} } ) {
						$self->{'cache'}->{'scheme'}->{ $data->{$field} } =
						  $self->{'datastore'}->get_scheme_info( $data->{$field} )->{'name'};
					}
					$value = $self->{'cache'}->{'scheme'}->{ $data->{$field} };
				} else {
					$value = $data->{$field};
				}
			}
			print defined $value ? qq(<td>$value</td>) : q(<td></td>);
		}
	}
	return;
}

sub _process_schemes {
	my ( $self, $args ) = @_;
	my ( $display, $data, $prefstore, $guid, $updated_ref, $not_default_ref ) =
	  @{$args}{qw (display data prefstore guid updated_ref not_default_ref)};
	my $q = $self->{'cgi'};
	foreach my $field (@$display) {
		if (   $q->param("${field}_change")
			&& $q->param("id_$data->{'id'}") )
		{
			my $value = $q->param($field);
			$prefstore->set_scheme( $guid, $self->{'system'}->{'db'}, $data->{'id'}, $field, $value );
			print qq(<td>$value <span class="highlight">*</span></td>);
			$$updated_ref = 1;
		} elsif ( $q->param("${field}_default")
			&& $q->param("id_$data->{'id'}") )
		{
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $data->{'id'} );
			my $value = $scheme_info->{$field} ? 'true' : 'false';
			$prefstore->delete_scheme( $guid, $self->{'system'}->{'db'}, $data->{'id'}, $field );
			print qq(<td>$value</td>);
		} else {
			my $value;
			if ( any { $field eq $_ } qw (isolate_display main_display query_field analysis disable) ) {
				$value =
				  $self->{'prefs'}->{"${field}_schemes"}->{ $data->{'id'} }
				  ? 'true'
				  : 'false';
				my $scheme_info = $self->{'datastore'}->get_scheme_info( $data->{'id'} );
				if (   ( $value eq 'true' && !$scheme_info->{$field} )
					|| ( $value eq 'false' && $scheme_info->{$field} ) )
				{
					$value .= q( <span class="non-default">&#134;</span>);
					$$not_default_ref = 1;
				}
			} else {
				$value = $data->{$field};
			}
			print defined $value ? qq(<td>$value</td>) : q(<td></td>);
		}
	}
	return;
}

sub _get_tooltip {
	my ( $self, $action ) = @_;
	my $table = $self->{'cgi'}->param('table');
	my $record = $table eq 'schemes' ? 'scheme fields and loci' : $self->get_record_name($table);
	my $value;
	my %tooltip = (
		isolate_display => sub {
			my $t = $table eq 'loci' ? 'how' : 'whether';
			$value = "isolate display - Sets $t to display the $record in the isolate information page.";
		},
		main_display => sub {
			$value = "main display - Sets whether to display the $record in the isolate query results table.";
		},
		query_field => sub {
			my $plural = $table eq 'schemes' ? '' : 's';
			$value = "query field - Sets whether the $record can be used in isolate queries.  This setting "
			  . "affects whether the $record appear$plural in the drop-down list boxes in the query interfaces.";
		},
		analysis => sub {
			my $plural = $table eq 'schemes' ? '' : 's';
			$value = "analysis - Sets whether the $record can be used in data analysis functions.";
		},
		dropdown => sub {
			$value = "dropdown - Sets whether the $record has a dropdown list box in the query interface.";
		}
	);
	$tooltip{$action}->() if $tooltip{$action};
	if ( $table eq 'schemes' ) {
		$value .= q( If set to 'false', this setting will override any display )
		  . q(options for individual scheme loci or fields.);
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
