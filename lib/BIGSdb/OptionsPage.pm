#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
package BIGSdb::OptionsPage;
use strict;
use warnings;
use base qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Page qw(FLANKING);

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw(jQuery noCache);
	return;
}

sub _toggle_option {
	my ( $self, $field ) = @_;
	my $prefs = $self->{'prefs'};
	my $value = $prefs->{$field} ? 'off' : 'on';
	my $guid  = $self->get_guid;
	return if !$guid;
	$self->{'prefstore'}->set_general( $guid, $self->{'system'}->{'db'}, $field, $value );
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('toggle_tooltips') ) {

		#AJAX call - don't display
		$self->_toggle_option('tooltips');
		return;
	}
	my $system = $self->{'system'};
	my $prefs  = $self->{'prefs'};
	my $desc   = $system->{'description'};
	$self->{'extended'} = $self->get_extended_attributes if $self->{'system'}->{'dbtype'} eq 'isolates';
	print "<h1>Set database options</h1>\n";
	if ( !$q->cookie('guid') ) {
		print <<"HTML";
<div class="box" id="statusbad">
<h2>Unable to proceed</h2>
<p>In order to store options, a cookie needs to be 
saved on your computer. Cookies appear to be disabled, however.  Please enable them in your 
browser settings to proceed.</p>
</div>
HTML
		return;
	}
	print <<"HTML";
<div class="box" id="queryform"><p>Here you can set options for your use of the website.  Options are
remembered between sessions and affect the current database ($desc) 
only. If some 
of the options don't appear to set when you next go to a query page, 
try refreshing the page (Shift + Refresh) as some pages are cached by 
your browser.</p></div>

HTML
	print $q->start_form;
	print $q->hidden('db');
	print "<div class=\"tabs\">\n";
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print "<script type=\"text/javascript\">if (!location.hash){var l=getCookie('optionsTab');if (l){location.hash='#'+getCookie('optionsTab')};}</script>\n";
	}
	print <<"HTML";
<ul class="tabNavigation">

<li><a href="#_general" id="general" onclick="document.cookie='optionsTab=general; path=/'">General</a></li>
HTML
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print "<li><a href=\"#_display\" id=\"display\" onclick=\"document.cookie='optionsTab=display; path=/'\">Display</a></li>\n";
		print "<li><a href=\"#_query\" id=\"query\" onclick=\"document.cookie='optionsTab=query; path=/'\">Query</a></li>\n";
	}
	
	print "</ul>\n";
	$self->_print_general_tab;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->_print_display_tab;
		$self->_print_query_tab;
	}
	print "</div>\n";
	print "<p />\n";
	print "<table style=\"width:95%\"><tr><td style=\"text-align:left\">\n";
	$q->param( 'page', 'options' );
	print $q->hidden('page');
	print $q->submit( -name => 'reset', -label => 'Reset all to defaults', -class => 'button' );
	print $q->hidden('db');
	print "</td><td style=\"text-align:right\">";
	print $q->submit( -name => 'set', -label => 'Set options', -class => 'submit' );
	print "</td></tr>";
	print "<tr><td class=\"comment\">Will reset ALL options (including locus and scheme field display)</td><td></td></tr></table>\n";
	print $q->end_form;
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Options - $desc";
}

sub set_options {
	my ($self)     = @_;
	my $stylesheet = $self->get_stylesheet;
	my $q          = $self->{'cgi'};
	my $prefs      = $self->{'prefs'};
	my $prefstore  = $self->{'prefstore'};
	my $system     = $self->{'system'};
	if ( $q->param('set') ) {
		my $guid = $self->get_guid;
		return if !$guid;
		my $dbname = $self->{'system'}->{'db'};
		foreach (qw (displayrecs alignwidth flanking )) {
			$prefstore->set_general( $guid, $dbname, $_, $prefs->{$_} ) if BIGSdb::Utils::is_int( $prefs->{$_} ) && $prefs->{$_} >= 0;
		}
		$prefstore->set_general( $guid, $dbname, 'pagebar', $prefs->{'pagebar'} );
		foreach (qw (hyperlink_loci tooltips)) {
			$prefstore->set_general( $guid, $dbname, $_, $prefs->{$_} ? 'on' : 'off' );
		}
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			foreach (
				qw (mark_provisional_main mark_provisional display_pending_main sequence_details_main locus_alias
				display_pending update_details sequence_details sample_details undesignated_alleles)
			  )
			{
				$prefstore->set_general( $guid, $dbname, $_, $prefs->{$_} ? 'on' : 'off' );
			}
			my $extended = $self->get_extended_attributes;
			foreach ( @{ $self->{'xmlHandler'}->get_field_list() } ) {
				$prefstore->set_field( $guid, $dbname, $_, 'maindisplay', $prefs->{'maindisplayfields'}->{$_} ? 'true' : 'false' );
				$prefstore->set_field( $guid, $dbname, $_, 'dropdown',    $prefs->{'dropdownfields'}->{$_}    ? 'true' : 'false' );
				my $extatt = $extended->{$_};
				if ( ref $extatt eq 'ARRAY' ) {
					foreach my $extended_attribute (@$extatt) {
						$prefstore->set_field( $guid, $dbname, "$_\..$extended_attribute", 'maindisplay',
							$prefs->{'maindisplayfields'}->{"$_\..$extended_attribute"} ? 'true' : 'false' );
						$prefstore->set_field( $guid, $dbname, "$_\..$extended_attribute", 'dropdown',
							$prefs->{'dropdownfields'}->{"$_\..$extended_attribute"} ? 'true' : 'false' );
					}
				}
			}
			$prefstore->set_field( $guid, $dbname, 'aliases', 'maindisplay',
				$prefs->{'maindisplayfields'}->{'aliases'} ? 'true' : 'false' );
			my $composites = $self->{'datastore'}->run_list_query("SELECT id FROM composite_fields");
			foreach (@$composites) {
				$prefstore->set_field( $guid, $dbname, $_, 'maindisplay', $prefs->{'maindisplayfields'}->{$_} ? 'true' : 'false' );
			}
			my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes");
			foreach (@$schemes) {
				my $field = "scheme_$_\_profile_status";
				$prefstore->set_field( $guid, $dbname, $field, 'dropdown', $prefs->{'dropdownfields'}->{$field} ? 'true' : 'false' );
			}
		}
		$prefstore->update_datestamp($guid);
	} elsif ( $q->param('reset') ) {
		my $guid = $self->get_guid;
		$prefstore->delete_guid($guid) if $guid;
	}
	return;
}

sub _print_general_tab {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	print "<div class=\"tab\" id=\"_general\">\n";
	print "<h2>General options</h2>\n";
	print "<table style=\"width:95%\"><tr><td style=\"vertical-align:top; width:50%\">\n";
	print "<table style=\"width:100%\"><tr><th>Interface</th></tr>\n";
	print "<tr class=\"td1\" style=\"text-align:left\"><td>Display \n";
	print $q->popup_menu( -name => 'displayrecs', -values => [qw (10 25 50 100 200 500 all)], -default => $prefs->{'displayrecs'} );
	print " records per page</td></tr>\n";
	print "<tr class=\"td1\" style=\"text-align:left\"><td>Page bar position: \n";
	print $q->popup_menu( -name => 'pagebar', -values => [ 'top and bottom', 'top only', 'bottom only' ], -default => $prefs->{'pagebar'} );
	print "</td></tr>\n";

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
		print $q->checkbox( -name => 'locus_alias', -checked => $prefs->{'locus_alias'}, -label => 'Display locus aliases if set.' );
		print "</td></tr>\n";
	}
	print "<tr class=\"td1\" style=\"text-align:left\"><td>Display \n";
	print $q->popup_menu( -name => 'alignwidth', -values => [qw (50 60 70 80 90 100 110 120 130 140 150)],
		-default => $prefs->{'alignwidth'} );
	print " nucleotides per line in sequence alignments</td></tr>\n";
	print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
	print $q->checkbox( -name => 'tooltips', -checked => $prefs->{'tooltips'}, -label => 'Enable tooltips (beginner\'s mode)' );
	print "</td></tr>\n";
	print "</table>\n";
	print "<table style=\"width:100%\">";
	print "<tr><th>Sequence bin display</th></tr>\n";
	print "<tr class=\"td1\" style=\"text-align:left\"><td>Display \n";
	print $q->popup_menu( -name => 'flanking', -values => [ FLANKING ], -default => $prefs->{'flanking'} );
	print " nucleotides of flanking sequence (where available)</td></tr>\n";
	print "</table>\n";
	print "</td><td style=\"vertical-align:top\">\n";

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print "<table style=\"width:100%\"><tr><th>Main results table</th></tr>\n";
		print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
		print $q->checkbox(
			-name    => 'hyperlink_loci',
			-checked => $prefs->{'hyperlink_loci'},
			-label   => 'Hyperlink allele designations where possible.'
		);
		print "</td></tr>\n";
		print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
		print $q->checkbox(
			-name    => 'mark_provisional_main',
			-checked => $prefs->{'mark_provisional_main'},
			-label   => 'Differentiate provisional allele designations.'
		);
		print "</td></tr>\n";
		print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
		print $q->checkbox(
			-name    => 'display_pending_main',
			-checked => $prefs->{'display_pending_main'},
			-label   => 'Display pending allele designations.'
		);
		print "</td></tr>\n";
		print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
		print $q->checkbox(
			-name    => 'sequence_details_main',
			-checked => $prefs->{'sequence_details_main'},
			-label   => 'Display information about sequence bin records tagged with locus information (tooltip).'
		);
		print "</td></tr>\n";
		print "</table>\n";
		print "<table style=\"width:100%\"><tr><th>Isolate full record</th></tr>\n";
		print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
		print $q->checkbox(
			-name    => 'mark_provisional',
			-checked => $prefs->{'mark_provisional'},
			-label   => 'Differentiate provisional allele designations.'
		);
		print "</td></tr>\n";
		print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
		print $q->checkbox(
			-name    => 'display_pending',
			-checked => $prefs->{'display_pending'},
			-label   => 'Display pending allele designations.'
		);
		print "</td></tr>\n";
		print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
		print $q->checkbox(
			-name    => 'update_details',
			-checked => $prefs->{'update_details'},
			-label   => 'Display sender, curator and last updated details for allele designations (tooltip).'
		);
		print "</td></tr>\n";
		print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
		print $q->checkbox(
			-name    => 'sequence_details',
			-checked => $prefs->{'sequence_details'},
			-label   => 'Display information about sequence bin records tagged with locus information (tooltip).'
		);
		print "</td></tr>\n";
		print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
		print $q->checkbox(
			-name    => 'sample_details',
			-checked => $prefs->{'sample_details'},
			-label   => 'Display full information about sample records (tooltip).'
		);
		print "</td></tr>\n";
		print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
		print $q->checkbox(
			-name    => 'undesignated_alleles',
			-checked => $prefs->{'undesignated_alleles'},
			-label =>
'Display all loci even where no allele is designated or sequence tagged (this may slow down display where hundreds of loci are defined).'
		);
		print "</td></tr>\n";
		print "</table>\n";
	}
	print "</td></tr>\n";
	print "</table></div>\n";
	return;
}

sub _print_display_tab {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	print "<div class=\"tab\" id=\"_display\">\n";
	print "<h2>Isolate field display options</h2>\n";
	print "<p>Options are for isolate table fields.  Loci settings can be made by performing a locus query.</p>\n";
	print "<table style=\"width:95%\">\n";
	print "<tr><th>Fields to display in main table</th></tr>\n";
	print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
	print "<table style=\"width:100%\"><tr><td valign=\"top\">\n";
	my $i    = 0;
	my $cols = 1;
	my $checked;
	my $fields = $self->{'xmlHandler'}->get_field_list();
	my ( @js, @js2, @js3, %composites, %composite_display_pos, %composite_main_display );
	my $qry = "SELECT id,position_after,main_display FROM composite_fields";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	if ($@) {
		$logger->error($@);
	} else {
		while ( my @data = $sql->fetchrow_array() ) {
			$composite_display_pos{ $data[0] }  = $data[1];
			$composite_main_display{ $data[0] } = $data[2];
			$composites{ $data[1] }             = 1;
		}
	}
	my $field_count = scalar @$fields + scalar keys %composite_display_pos;
	if ( ref $self->{'extended'} eq 'HASH' ) {
		foreach ( keys %{ $self->{'extended'} } ) {
			foreach ( @{ $self->{'extended'}->{$_} } ) {
				$field_count++;
			}
		}
	}
	foreach my $field (@$fields) {
		if ( $field ne 'id' ) {
			print $q->checkbox(
				-name    => "field_$field",
				-id      => "field_$field",
				-checked => $prefs->{'maindisplayfields'}->{$field},
				-value   => 'checked',
				-label   => $field
			);
			push @js,  "\$(\"#field_$field\").attr(\"checked\",true)";
			push @js2, "\$(\"#field_$field\").attr(\"checked\",false)";
			my %thisfield = $self->{'xmlHandler'}->get_field_attributes($field);
			my $value = $thisfield{'maindisplay'} && $thisfield{'maindisplay'} eq 'no' ? 'false' : 'true';
			push @js3, "\$(\"#field_$field\").attr(\"checked\",$value)";
			$i++;
			if ( $i >= ($field_count) / 5 ) {
				print "</td><td valign=\"top\">";
				$i = 0;
				$cols++;
			} else {
				print "<br />\n";
			}
			my $extatt = $self->{'extended'}->{$field};
			if ( ref $extatt eq 'ARRAY' ) {
				foreach my $extended_attribute (@$extatt) {
					print $q->checkbox(
						-name    => "extended_$field..$extended_attribute",
						-id      => "extended_$field\___$extended_attribute",
						-checked => $prefs->{'maindisplayfields'}->{"$field\..$extended_attribute"},
						-value   => 'checked',
						-label   => "$field..$extended_attribute"
					);
					push @js,  "\$(\"#extended_$field\___$extended_attribute\").attr(\"checked\",true)";
					push @js2, "\$(\"#extended_$field\___$extended_attribute\").attr(\"checked\",false)";
					push @js3, "\$(\"#extended_$field\___$extended_attribute\").attr(\"checked\",false)";
					$i++;
					if ( $i >= ($field_count) / 5 ) {
						print "</td><td valign=\"top\">";
						$i = 0;
						$cols++;
					} else {
						print "<br />\n";
					}
				}
			}
			if ( $field eq $self->{'system'}->{'labelfield'} ) {
				print $q->checkbox(
					-name    => "field_aliases",
					-id      => "field_aliases",
					-checked => $prefs->{'maindisplayfields'}->{'aliases'},
					-value   => 'checked',
					-label   => 'aliases'
				);
				push @js,  "\$(\"#field_aliases\").attr(\"checked\",true)";
				push @js2, "\$(\"#field_aliases\").attr(\"checked\",false)";
				my $value = $self->{'system'}->{'maindisplay_aliases'} && $self->{'system'}->{'maindisplay_aliases'} eq 'yes' ? 'true' : 'false';
				push @js3, "\$(\"#field_aliases\").attr(\"checked\",$value)";
				$i++;
				if ( $i >= ($field_count) / 5 ) {
					print "</td><td valign=\"top\">";
					$i = 0;
					$cols++;
				} else {
					print "<br />\n";
				}
			}
		}
		if ( $composites{$field} ) {
			foreach ( keys %composite_display_pos ) {
				next if $composite_display_pos{$_} ne $field;
				print $q->checkbox(
					-name    => "field_$_",
					-id      => "field_$_",
					-checked => $prefs->{'maindisplayfields'}->{$_},
					-value   => 'checked',
					-label   => $_
				);
				push @js,  "\$(\"#field_$_\").attr(\"checked\",true)";
				push @js2, "\$(\"#field_$_\").attr(\"checked\",false)";
				my $value = $composite_main_display{$_} ? 'true' : 'false';
				push @js3, "\$(\"#field_$_\").attr(\"checked\",$value)";
				$i++;
				if ( $i >= ( 1 + $field_count ) / 5 ) {
					print "</td><td valign=\"top\">";
					$i = 0;
					$cols++;
				} else {
					print "<br />\n";
				}
			}
		}
	}
	print "</td><td valign=\"top\">";
	$cols++;
	print "</td></tr>\n";
	print "</table>\n";
	print "</td></tr></table>\n";
	local $" = ';';
	print "<input type=\"button\" value=\"Select all\" onclick='@js' class=\"button\" />\n";
	print "<input type=\"button\" value=\"Select none\" onclick='@js2' class=\"button\" />\n";
	print "<input type=\"button\" value=\"Select default\" onclick='@js3' class=\"button\" />\n";
	print "<noscript><span class=\"comment\"> Enable javascript for select buttons to work!</span></noscript>\n";
	print "</div>\n";
	return;
}

sub _print_query_tab {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $prefs  = $self->{'prefs'};
	print "<div class=\"tab\" id=\"_query\">\n";
	print "<h2>" . ( $self->{'system'}->{'dbtype'} eq 'isolates' ? 'Isolate' : 'Profile' ) . " query interface options</h2>\n";
	print "<p>Options are for isolate table fields.  Loci and scheme field settings can be made by performing a locus query.</p>\n"
	  if $self->{'system'}->{'dbtype'} eq 'isolates';
	print "<table><tr><th>Fields to provide drop-down list boxes for when searching</th></tr>\n";
	print "<tr class=\"td1\" style=\"text-align:left\"><td>\n";
	print "<table style=\"width:100%\"><tr><td valign=\"top\">\n";
	my $i           = 0;
	my $cols        = 1;
	my $fields      = $self->{'xmlHandler'}->get_field_list();
	my @checkfields = @$fields;
	my %labels;

	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		my $schemes = $self->{'datastore'}->run_list_query("SELECT id FROM schemes ORDER BY display_order,id");
		foreach (@$schemes) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($_);
			my $field       = "scheme_$_\_profile_status";
			push @checkfields, $field;
			$labels{$field} = "$scheme_info->{'description'} profile completion";
		}
	}
	my ( @js, @js2, @js3 );
	my $field_count = @checkfields;
	if ( ref $self->{'extended'} eq 'HASH' ) {
		foreach ( keys %{ $self->{'extended'} } ) {
			foreach ( @{ $self->{'extended'}->{$_} } ) {
				$field_count++;
			}
		}
	}
	foreach (@checkfields) {
		my %thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
		if ( $_ ne 'id' ) {
			print $q->checkbox(
				-name    => "dropfield_$_",
				-id      => "dropfield_$_",
				-checked => $prefs->{'dropdownfields'}->{$_},
				-value   => 'checked',
				-label   => $labels{$_} || $_
			);
			push @js,  "\$(\"#dropfield_$_\").attr(\"checked\",true)";
			push @js2, "\$(\"#dropfield_$_\").attr(\"checked\",false)";
			my %thisfield = $self->{'xmlHandler'}->get_field_attributes($_);
			my $value = ($thisfield{'dropdown'} && $thisfield{'dropdown'} eq 'yes') ? 'true' : 'false';
			push @js3, "\$(\"#dropfield_$_\").attr(\"checked\",$value)";
			$i++;

			if ( $i >= $field_count / 6 ) {
				print "</td><td valign='top'>";
				$i = 0;
				$cols++;
			} else {
				print "<br />\n";
			}
		}
		my $extatt = $self->{'extended'}->{$_};
		if ( ref $extatt eq 'ARRAY' ) {
			foreach my $extended_attribute (@$extatt) {
				print $q->checkbox(
					-name    => "dropfield_e_$_\..$extended_attribute",
					-id      => "dropfield_e_$_\___$extended_attribute",
					-checked => $prefs->{'dropdownfields'}->{"$_\..$extended_attribute"},
					-value   => 'checked',
					-label   => "$_\..$extended_attribute"
				);
				push @js,  "\$(\"#dropfield_e_$_\___$extended_attribute\").attr(\"checked\",true)";
				push @js2, "\$(\"#dropfield_e_$_\___$extended_attribute\").attr(\"checked\",false)";
				push @js3, "\$(\"#dropfield_e_$_\___$extended_attribute\").attr(\"checked\",false)";
				$i++;
				if ( $i >= ($field_count) / 6 ) {
					print "</td><td valign=\"top\">";
					$i = 0;
					$cols++;
				} else {
					print "<br />\n";
				}
			}
		}
	}
	print "</td></tr></table>\n";
	print "</td></tr></table>\n";
	local $" = ';';
	print "<input type=\"button\" value=\"Select all\" onclick='@js' class=\"button\" />\n";
	print "<input type=\"button\" value=\"Select none\" onclick='@js2' class=\"button\" />\n";
	print "<input type=\"button\" value=\"Select default\" onclick='@js3' class=\"button\" />\n";
	print "<noscript><span class=\"comment\"> Enable javascript for select buttons to work!</span></noscript>\n";
	print "</div>\n";
	return;
}
1;
