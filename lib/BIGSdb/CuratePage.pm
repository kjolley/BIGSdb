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
package BIGSdb::CuratePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Page qw(SEQ_FLAGS ALLELE_FLAGS DATABANKS);

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery noCache);
	return;
}
sub get_title     { return "Curator's interface - BIGSdb" }
sub print_content { }

sub get_curator_name {
	my ($self) = @_;
	if ( $self->{'username'} ) {
		my $qry = "SELECT first_name, surname FROM users WHERE user_name=?";
		my $name = $self->{'datastore'}->run_simple_query( $qry, $self->{'username'} );
		if ( ref $name eq 'ARRAY' ) {
			return "$name->[0] $name->[1]";
		}
	} else {
		return "unknown user";
	}
}

sub create_record_table {
	my ( $self, $table, $newdata_ref, $update, $nodiv, $prepend_table_name, $newdata_readonly ) = @_;
	if ( ref $newdata_ref ne 'HASH' ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Record doesn't exist.</p></div>";
		return '';
	}
	my %newdata = %{$newdata_ref};
	my $q       = $self->{'cgi'};
	my $buffer;
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my $qry        = "select id,user_name,first_name,surname from users where id>0 order by surname";
	my $sql        = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	my @users;
	my %usernames;

	while ( my ( $user_id, $username, $firstname, $surname ) = $sql->fetchrow_array ) {
		push @users, $user_id;
		$usernames{$user_id} = "$surname, $firstname ($username)";
	}
	$buffer .= $q->start_form;
	$q->param( 'action', $update ? 'update' : 'add' );
	$q->param( 'table', $table );
	$buffer .= $q->hidden($_) foreach qw(page table db action );
	$buffer .= $q->hidden( 'locus', $newdata{'locus'} ) if $table eq 'allele_designations';
	$buffer .= $q->hidden( 'sent', 1 );
	$buffer .= "<div class=\"box\" id=\"queryform\">" if !$nodiv;
	$buffer .= "<p>Please fill in the fields below - required fields are marked with an exclamation mark (!).</p>\n";
	$buffer .= "<div class=\"scrollable\">"           if !$nodiv;
	$buffer .= "<table>\n";

	if ( @$attributes > 15 ) {
		$buffer .= "<tr><td colspan=\"2\" style=\"text-align:right\">";
		if ( !$q->param('submit') ) {
			$buffer .= $q->submit( -name => 'Submit', -class => 'submit' );
		}
		$buffer .= "</td></tr>\n";
	}
	foreach my $required ( '1', '0' ) {
		foreach my $att (@$attributes) {
			my $name = $prepend_table_name ? "$table\_$att->{'name'}" : $att->{'name'};
			if (   ( $att->{'required'} eq 'yes' && $required )
				|| ( ( !$att->{'required'} || $att->{'required'} eq 'no' ) && !$required ) )
			{
				my $length = $att->{'length'} || ( $att->{'type'} eq 'int' ? 15 : 50 );
				$buffer .= "<tr><td style=\"text-align:right\">";
				if ( $att->{'tooltip'} ) {
					$buffer .= "<a class=\"tooltip\" title=\"$att->{'tooltip'}\">&nbsp;<i>i</i>&nbsp;</a>";
				}
				( my $cleaned_name = $att->{name} ) =~ tr/_/ /;
				$buffer .= " $cleaned_name:&nbsp;";
				$buffer .= '!' if $att->{'required'} eq 'yes';
				$buffer .= "</td><td style=\"text-align:left\">";
				if (   ( $update && $att->{'primary_key'} )
					|| ( $newdata_readonly && $newdata{ $att->{'name'} } ) )
				{
					my $desc;
					if ( ( $att->{'name'} eq 'locus' && $table ne 'set_loci' ) || ( $table eq 'loci' && $att->{'name'} eq 'id' ) ) {
						$desc = $self->clean_locus( $newdata{ $att->{'name'} } );
					} elsif ( $att->{'labels'} ) {
						$desc = $self->_get_foreign_key_label( $name, $newdata_ref, $att );
					} else {
						( $desc = $newdata{ $att->{'name'} } ) =~ tr/_/ /;
					}
					$buffer .= "<b>$desc";
					if ( $table eq 'samples' && $att->{'name'} eq 'isolate_id' ) {
						$buffer .= ") " . $self->get_isolate_name_from_id( $newdata{ $att->{'name'} } );
					}
					$buffer .= '</b>';
					$buffer .= $q->hidden( $name, $newdata{ $att->{'name'} } );
				} elsif ( $q->param('page') eq 'update' && ( $att->{'user_update'} // '' ) eq 'no' ) {
					if ( $att->{'name'} eq 'sequence' ) {
						my $data_length = length( $newdata{ $att->{'name'} } );
						if ( $data_length > 5000 ) {
							$buffer .=
							    "<span class=\"seq\"><b>"
							  . BIGSdb::Utils::truncate_seq( \$newdata{ $att->{'name'} }, 40 )
							  . "</b></span><br />sequence is $data_length characters (too long to display)";
						} else {
							$buffer .= "<span class=\"seq\"><b>" . BIGSdb::Utils::split_line( $newdata{ $att->{'name'} } ) . "</b></span>";
						}
					} else {
						$buffer .= "<b>$newdata{$att->{'name'}}</b>";
					}
				} elsif ( $att->{'name'} eq 'sender' ) {
					$buffer .= $q->popup_menu(
						-name    => $name,
						-values  => [ '', @users ],
						-labels  => \%usernames,
						-default => $newdata{ $att->{'name'} }
					);
				} elsif ( $table eq 'sequences' && $att->{'name'} eq 'allele_id' && $q->param('locus') ) {
					my $locus_info = $self->{'datastore'}->get_locus_info( $q->param('locus') );
					if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
						my $default = $self->{'datastore'}->get_next_allele_id( $q->param('locus') );
						$buffer .= $q->textfield( -name => $name, -size => $length, -maxlength => $length, -default => $default );
					} else {
						$buffer .=
						  $q->textfield( -name => $name, -size => $length, -maxlength => $length, -default => $newdata{ $att->{'name'} } );
					}
				} elsif ( ( $table eq 'sequences' || $table eq 'sequence_refs' || $table eq 'accession' || $table eq 'locus_descriptions' )
					&& $att->{'name'} eq 'locus'
					&& !$self->is_admin )
				{
					my $set_id = $self->get_set_id;
					my ( $values, $desc ) =
					  $self->{'datastore'}
					  ->get_locus_list( { set_id => $set_id, no_list_by_common_name => 1, locus_curator => $self->get_curator_id } );
					$values = [] if ref $values ne 'ARRAY';
					$buffer .= $q->popup_menu(
						-name    => $name,
						-id      => $name,
						-values  => [ '', @$values ],
						-labels  => $desc,
						-default => $newdata{ $att->{'name'} }
					);
				} elsif ( ( $att->{'dropdown_query'} // '' ) eq 'yes'
					&& $att->{'foreign_key'} )
				{
					my @fields_to_query;
					my $desc;
					if ( $att->{'labels'} ) {
						( my $fields_ref, $desc ) = $self->get_all_foreign_key_fields_and_labels($att);
						@fields_to_query = @$fields_ref;
					} else {
						push @fields_to_query, 'id';
					}
					local $" = ',';
					my $qry;
					my $set_id = $self->get_set_id;
					my $values;
					if ( $att->{'foreign_key'} eq 'users' ) {
						$qry    = "SELECT id FROM users WHERE id>0 ORDER BY @fields_to_query";
						$values = $self->{'datastore'}->run_list_query($qry);
					} elsif ( $att->{'foreign_key'} eq 'loci' && $table ne 'set_loci' && $set_id ) {
						( $values, $desc ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id, no_list_by_common_name => 1 } );
					} elsif ( $att->{'foreign_key'} eq 'schemes' && $table ne 'set_schemes' && $set_id ) {
						my $scheme_list = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
						push @$values, $_->{'id'} foreach @$scheme_list;
					} else {
						$qry    = "SELECT id FROM $att->{'foreign_key'} ORDER BY @fields_to_query";
						$values = $self->{'datastore'}->run_list_query($qry);
					}
					$values = [] if ref $values ne 'ARRAY';
					$buffer .= $q->popup_menu(
						-name    => $name,
						-id      => $name,
						-values  => [ '', @$values ],
						-labels  => $desc,
						-default => $newdata{ $att->{'name'} }
					);
				} elsif ( $att->{'name'} eq 'datestamp' ) {
					$buffer .= "<b>" . $self->get_datestamp . "</b>\n";
				} elsif ( $att->{'name'} eq 'date_entered' ) {
					if ( $q->param('page') eq 'update' or $q->param('page') eq 'alleleUpdate' ) {
						$buffer .= "<b>" . $newdata{ $att->{'name'} } . "</b>\n";
					} else {
						$buffer .= "<b>" . $self->get_datestamp . "</b>\n";
					}
				} elsif ( $att->{'name'} eq 'curator' ) {
					$buffer .= "<b>" . $self->get_curator_name . ' (' . $self->{'username'} . ")</b>\n";
				} elsif ( $att->{'type'} eq 'bool' ) {
					$buffer .= $self->_get_boolean_field( $name, $newdata_ref, $att );
				} elsif ( $att->{'optlist'} ) {
					my @optlist;
					if ( $att->{'optlist'} eq 'isolate_fields' ) {
						@optlist = @{ $self->{'xmlHandler'}->get_field_list() };
					} else {
						@optlist = split /;/, $att->{'optlist'};
					}
					unshift @optlist, '' if !$att->{'default'};
					$buffer .= $q->popup_menu( -name => $name, -values => [@optlist], -default => $newdata{ $att->{'name'} } );
				} else {
					if ( $length >= 256 ) {
						$newdata{ $att->{'name'} } = BIGSdb::Utils::split_line( $newdata{ $att->{'name'} } )
						  if $att->{'name'} eq 'sequence';
						$buffer .= $q->textarea( -name => $name, -rows => 6, -cols => 70, -default => $newdata{ $att->{'name'} } );
					} elsif ( $length >= 120 ) {
						$newdata{ $att->{'name'} } = BIGSdb::Utils::split_line( $newdata{ $att->{'name'} } )
						  if $att->{'name'} eq 'sequence';
						$buffer .= $q->textarea( -name => $name, -rows => 3, -cols => 70, -default => $newdata{ $att->{'name'} } );
					} else {
						$buffer .= $q->textfield(
							-name      => $name,
							-id        => $name,
							-size      => $length,
							-maxlength => $length,
							-default   => $newdata{ $att->{'name'} }
						);
					}
				}
				if ( $att->{'comments'} ) {
					my $padding = $att->{'type'} eq 'bool' ? '3em' : '0';
					$buffer .= " <span class=\"comment\" style=\"padding-left:$padding\">$att->{'comments'}</span>";
				} elsif ( $att->{'type'} eq 'date'
					&& lc( $att->{'name'} ne 'datestamp' )
					&& lc( $att->{'name'} ne 'date_entered' ) )
				{
					$buffer .= " <span class=\"comment\">format: yyyy-mm-dd (or 'today')</span>";
				}
				$buffer .= "</td></tr>\n";
			}
		}
	}
	given ($table) {
		when ('sequences')          { $buffer .= $self->_create_extra_fields_for_sequences($newdata_ref) }
		when ('locus_descriptions') { $buffer .= $self->_create_extra_fields_for_locus_descriptions($newdata_ref) }
		when ('sequence_bin')       { $buffer .= $self->_create_extra_fields_for_seqbin($newdata_ref) }
	}
	$buffer .= "<tr><td>";
	my $page        = $q->param('page');
	my $extra_field = '';
	if ( $update || $table eq 'pending_allele_designations' ) {
		my @extra;
		foreach (@$attributes) {
			if ( $_->{'primary_key'} ) {
				push @extra, "$_->{'name'}=$newdata{$_->{'name'}}" if defined $newdata{ $_->{'name'} };
			}
		}
		local $" = "&amp;";
		$extra_field = "&amp;@extra" if @extra;
	}
	$buffer .= "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=$page&amp;"
	  . "table=$table$extra_field\" class=\"resetbutton\">Reset</a></td><td style=\"text-align:right\">";
	$buffer .= $q->submit( -name => 'Submit', -class => 'submit' ) if !$q->param('submit');
	$buffer .= "</td></tr>\n</table>\n";
	$buffer .= "</div>\n</div>\n" if !$nodiv;
	$buffer .= $q->end_form;
	return $buffer;
}

sub _get_foreign_key_label {
	my ( $self, $name, $newdata_ref, $att ) = @_;
	my @fields_to_query;
	my @values = split /\|/, $att->{'labels'};
	foreach (@values) {
		if ( $_ =~ /\$(.*)/ ) {
			push @fields_to_query, $1;
		}
	}
	local $" = ',';
	my $data =
	  $self->{'datastore'}
	  ->run_simple_query_hashref( "select id,@fields_to_query from $att->{'foreign_key'} WHERE id=?", $newdata_ref->{ $att->{'name'} } );
	my $desc = $att->{'labels'};
	$desc =~ s/$_/$data->{$_}/ foreach @fields_to_query;
	$desc =~ s/[\|\$]//g;
	return $desc;
}

sub _get_boolean_field {
	my ( $self, $name, $newdata_ref, $att ) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = '';
	my $default;
	if ( $q->param('page') eq 'update' && ( $newdata_ref->{ $att->{'name'} } // '' ) ne '' ) {
		$default = $newdata_ref->{ $att->{'name'} } ? 'true' : 'false';
	} else {
		$default = $newdata_ref->{ $att->{'name'} };
	}
	$default //= '-';
	local $" = ' ';
	$buffer .= $q->radio_group( -name => $name, -values => [qw (true false)], -default => $default );
	return $buffer;
}

sub _create_extra_fields_for_sequences {
	my ( $self, $newdata ) = @_;
	my $q = $self->{'cgi'};
	my $buffer;
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		my $list = $self->{'datastore'}->get_allele_flags( $q->param('locus'), $q->param('allele_id') );
		$buffer .=
		  "<tr><td style=\"text-align:right\">Flags: <br /><span class=\"comment\">(Ctrl-click to select multiple)</span></td><td>";
		$buffer .= $q->scrolling_list(
			-name     => 'flags',
			-id       => 'flags',
			-values   => [ALLELE_FLAGS],
			-size     => 5,
			-multiple => 'true',
			-default  => $list
		);
		$buffer .= "</td></tr>\n";
	}
	my @databanks = DATABANKS;
	my @default_pubmed;
	my $default_databanks;
	if ( $q->param('page') eq 'update' && $q->param('locus') ) {
		my $pubmed_list =
		  $self->{'datastore'}->run_list_query( "SELECT pubmed_id FROM sequence_refs WHERE locus=? AND allele_id=? ORDER BY pubmed_id",
			$q->param('locus'), $q->param('allele_id') );
		@default_pubmed = @$pubmed_list;
		foreach (@databanks) {
			my $list =
			  $self->{'datastore'}
			  ->run_list_query( "SELECT databank_id FROM accession WHERE locus=? AND allele_id=? AND databank=? ORDER BY databank_id",
				$q->param('locus'), $q->param('allele_id'), $_ );
			$default_databanks->{$_} = $list;
		}
	}
	$buffer .= "<tr><td style=\"text-align:right\">PubMed ids: </td><td>";
	local $" = "\n";
	$buffer .= $q->textarea( -name => 'pubmed', -rows => 2, -cols => 12, -style => 'width:10em', -default => "@default_pubmed" );
	$buffer .= "</td></tr>\n";
	foreach my $databank (@databanks) {
		$buffer .= "<tr><td style=\"text-align:right\">$databank ids: </td><td>";
		my @default;
		if ( ref $default_databanks->{$databank} eq 'ARRAY' ) {
			@default = @{ $default_databanks->{$databank} };
		}
		$buffer .= $q->textarea( -name => "databank_$databank", -rows => 2, -cols => 12, -style => 'width:10em', -default => "@default" );
		$buffer .= "</td></tr>\n";
	}
	if ( $q->param('locus') ) {
		my $sql =
		  $self->{'db'}->prepare( "SELECT field,description,value_format,required,length,option_list FROM "
			  . "locus_extended_attributes WHERE locus=? ORDER BY field_order" );
		my $locus = $q->param('locus');
		eval { $sql->execute($locus) };
		$logger->error($@) if $@;
		while ( my ( $field, $desc, $format, $required, $length, $optlist ) = $sql->fetchrow_array ) {
			$buffer .=
			  "<tr><td style=\"text-align:right\"> $field:&nbsp;" . ( $required ? '!' : '' ) . "</td><td style=\"text-align:left\">";
			$length = 12 if !$length;
			if ( $format eq 'boolean' ) {
				$buffer .= $q->popup_menu( -name => $field, -values => [ '', qw (true false) ], -default => $newdata->{$field} );
			} elsif ($optlist) {
				my @options = split /\|/, $optlist;
				unshift @options, '';
				$buffer .= $q->popup_menu( -name => $field, -values => \@options, -default => $newdata->{$field} );
			} elsif ( $length > 256 ) {
				$newdata->{ $_->{'name'} } = BIGSdb::Utils::split_line( $newdata->{ $_->{'name'} } ) if $_->{'name'} eq 'sequence';
				$buffer .= $q->textarea( -name => $field, -rows => 6, -cols => 70, -default => $newdata->{$field} );
			} elsif ( $length > 60 ) {
				$newdata->{ $_->{'name'} } = BIGSdb::Utils::split_line( $newdata->{ $_->{'name'} } ) if $_->{'name'} eq 'sequence';
				$buffer .= $q->textarea( -name => $field, -rows => 3, -cols => 70, -default => $newdata->{$field} );
			} else {
				$buffer .= $q->textfield( -name => $field, -size => $length, -maxlength => $length, -default => $newdata->{$field} );
			}
			$buffer .= "<span class=\"comment\"> $desc</span>\n" if $desc;
			$buffer .= "</td></tr>\n";
		}
		my $locus_info = $self->{'datastore'}->get_locus_info( $q->param('locus') );
		if ( ( !$q->param('locus') || ( ref $locus_info eq 'HASH' && $locus_info->{'data_type'} ne 'peptide' ) )
			&& $q->param('page') ne 'update' )
		{
			$buffer .= "<tr><td colspan=\"2\" style=\"padding-top:1em\">";
			$buffer .= $q->checkbox( -name => 'ignore_similarity', -label => 'Override sequence similarity check' );
			$buffer .= "</td></tr>";
		}
	}
	return $buffer;
}

sub _create_extra_fields_for_locus_descriptions {
	my ( $self, $newdata_ref ) = @_;
	my $q = $self->{'cgi'};
	my $buffer;
	my @default_aliases;
	if ( $q->param('page') eq 'update' && $q->param('locus') ) {
		my $alias_list =
		  $self->{'datastore'}->run_list_query( "SELECT alias FROM locus_aliases WHERE locus=? ORDER BY alias", $q->param('locus') );
		@default_aliases = @$alias_list;
	}
	$buffer .= "<tr><td style=\"text-align:right\">aliases: </td><td>";
	local $" = "\n";
	$buffer .= $q->textarea( -name => 'aliases', -rows => 2, -cols => 12, -style => 'width:10em', -default => "@default_aliases" );
	$buffer .= "</td></tr>\n";
	my @default_pubmed;
	if ( $q->param('page') eq 'update' && $q->param('locus') ) {
		my $pubmed_list =
		  $self->{'datastore'}->run_list_query( "SELECT pubmed_id FROM locus_refs WHERE locus=? ORDER BY pubmed_id", $q->param('locus') );
		@default_pubmed = @$pubmed_list;
	}
	$buffer .= "<tr><td style=\"text-align:right\">PubMed ids: </td><td>";
	$buffer .= $q->textarea( -name => 'pubmed', -rows => 2, -cols => 12, -style => 'width:10em', -default => "@default_pubmed" );
	$buffer .= "</td></tr>\n";
	my @default_links;
	if ( $q->param('page') eq 'update' && $q->param('locus') ) {
		my $sql = $self->{'db'}->prepare("SELECT url,description FROM locus_links WHERE locus=? ORDER BY link_order");
		eval { $sql->execute( $q->param('locus') ) };
		$logger->error($@) if $@;
		while ( my ( $url, $desc ) = $sql->fetchrow_array ) {
			push @default_links, "$url|$desc";
		}
	}
	$buffer .= "<tr><td style=\"text-align:right\">links: <br /><span class=\"comment\">(Format: URL|description)</span></td><td>";
	$buffer .= $q->textarea( -name => 'links', -rows => 3, -cols => 12, -default => "@default_links" );
	$buffer .= "</td></tr>\n";
	return $buffer;
}

sub _create_extra_fields_for_seqbin {
	my ( $self, $newdata_ref ) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = '';
	return $buffer if $q->param('page') eq 'update';
	my $sql = $self->{'db'}->prepare("SELECT id,description FROM experiments ORDER BY description");
	eval { $sql->execute };
	$logger->error($@) if $@;
	my @ids = (0);
	my %desc;
	$desc{0} = '';

	while ( my ( $id, $desc ) = $sql->fetchrow_array ) {
		push @ids, $id;
		$desc{$id} = $desc;
	}
	if ( @ids > 1 ) {
		$buffer .= "<tr><td style=\"text-align:right\">link to experiment: </td><td style=\"text-align:left\">";
		$buffer .= $q->popup_menu( -name => 'experiment', -values => \@ids, -default => $newdata_ref->{'experiment'}, -labels => \%desc );
		$buffer .= "</td></tr>\n";
	}
	return $buffer;
}

sub check_record {
	my ( $self, $table, $newdataref, $update, $allowed_valuesref ) = @_;

	#TODO prevent scheme group belonging to a child
	my $record_name = $self->get_record_name($table);
	my %newdata     = %{$newdataref};
	my $q           = $self->{'cgi'};
	my ( @problems, @missing );
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my @primary_key_query;
	foreach (@$attributes) {
		next if $update && $_->{'user_update'} && $_->{'user_update'} eq 'no';
		my $original_data = $newdata{ $_->{'name'} };
		$newdata{ $_->{'name'} }            =~ s/'/\\'/g if defined $newdata{ $_->{'name'} };
		$$allowed_valuesref{ $_->{'name'} } =~ s/'/\\'/g if defined $$allowed_valuesref{ $_->{'name'} };
		if ( $_->{'name'} =~ /sequence$/ ) {
			$newdata{ $_->{'name'} } = uc( $newdata{ $_->{'name'} } // '' );
			$newdata{ $_->{'name'} } =~ s/\s//g;
		}
		if ( $_->{'required'} eq 'yes' && ( !defined $newdata{ $_->{'name'} } || $newdata{ $_->{'name'} } eq '' ) ) {
			push @missing, $_->{'name'};
		} elsif ( $newdata{ $_->{'name'} }
			&& $_->{'type'} eq 'int'
			&& !BIGSdb::Utils::is_int( $newdata{ $_->{'name'} } ) )
		{
			push @problems, "$_->{name} must be an integer.\n";
		} elsif ( $newdata{ $_->{'name'} }
			&& $_->{'type'} eq 'float'
			&& !BIGSdb::Utils::is_float( $newdata{ $_->{'name'} } ) )
		{
			push @problems, "$_->{name} must be a floating point number.\n";
		} elsif ( $newdata{ $_->{'name'} }
			&& $_->{'type'} eq 'date'
			&& !BIGSdb::Utils::is_date( $newdata{ $_->{'name'} } ) )
		{
			push @problems, "$newdata{$_->{name}} must be in date format (yyyy-mm-dd or 'today').\n";
		} elsif ( defined $newdata{ $_->{'name'} }
			&& $newdata{ $_->{'name'} } ne ''
			&& $_->{'regex'}
			&& $newdata{ $_->{'name'} } !~ /$_->{'regex'}/ )
		{
			push @problems, "Field '$_->{name}' does not conform to specified format.\n";
		} elsif ( $_->{'unique'} ) {
			my $retval =
			  $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM $table WHERE $_->{name} = ?", $newdata{ $_->{'name'} } );
			if (   ( $update && $retval->[0] && $newdata{ $_->{'name'} } ne $$allowed_valuesref{ $_->{'name'} } )
				|| ( $retval->[0] && !$update ) )
			{
				if ( $_->{'name'} =~ /sequence/ ) {
					my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
					local $" = ', ';
					my $values =
					  $self->{'datastore'}
					  ->run_simple_query( "SELECT @primary_keys FROM $table WHERE $_->{'name'}=?", $newdata{ $_->{'name'} } );
					my @key;
					for ( my $i = 0 ; $i < scalar @primary_keys ; $i++ ) {
						push @key, "$primary_keys[$i]: $values->[$i]";
					}
					push @problems, "This sequence already exists in the database as '@key'.";
				} else {
					my $article = $record_name =~ /^[aeio]/ ? 'An' : 'A';
					push @problems,
"$article $record_name already exists with $_->{'name'} = '$newdata{$_->{'name'}}', please choose a different $_->{'name'}.";
				}
			}
		} elsif ( $_->{'foreign_key'} ) {
			my $retval = $self->{'datastore'}->run_simple_query( "SELECT COUNT(*) FROM $_->{'foreign_key'} WHERE id=?", $original_data );
			if ( !$retval->[0] ) {
				push @problems, "$_->{'name'} should refer to a record within the $_->{'foreign_key'} table, but it doesn't.";
			}
		} elsif ( ( $table eq 'allele_designations' || $table eq 'pending_allele_designations' )
			&& $_->{'name'} eq 'allele_id' )
		{

			#special case to check for allele id format and regex which is defined in loci table
			my $format =
			  $self->{'datastore'}->run_simple_query("SELECT allele_id_format,allele_id_regex FROM loci WHERE id=E'$newdata{'locus'}'");
			if ( $format->[0] eq 'integer'
				&& !BIGSdb::Utils::is_int( $newdata{ $_->{'name'} } ) )
			{
				push @problems, "$_->{'name'} must be an integer.\n";
			} elsif ( $format->[1] && $newdata{ $_->{'name'} } !~ /$format->[1]/ ) {
				push @problems, "$_->{'name'} value is invalid - it must match the regular expression /$format->[1]/.";
			}
		} elsif ( ( $table eq 'isolate_field_extended_attributes' )
			&& $_->{'name'} eq 'attribute'
			&& $newdata{ $_->{'name'} } =~ /'/ )
		{
			push @problems, "Attribute contains invalid characters.\n";
		} elsif ( ( $table eq 'isolate_value_extended_attributes' )
			&& $_->{'name'} eq 'value' )
		{

			#special case to check for extended attribute value format and regex which is defined in isolate_field_extended_attributes table
			my $format = $self->{'datastore'}->run_simple_query(
				"SELECT value_format,value_regex,length FROM isolate_field_extended_attributes WHERE isolate_field=? AND attribute=?",
				$newdata{'isolate_field'},
				$newdata{'attribute'}
			);
			if ( $format->[0] eq 'integer'
				&& !BIGSdb::Utils::is_int( $newdata{ $_->{'name'} } ) )
			{
				push @problems, "$_->{'name'} must be an integer.\n";
			} elsif ( $format->[1] && $newdata{ $_->{'name'} } !~ /$format->[1]/ ) {
				push @problems, "$_->{'name'} value is invalid - it must match the regular expression /$format->[1]/";
			} elsif ( $format->[2] && length( $newdata{ $_->{'name'} } ) > $format->[2] ) {
				push @problems, "$_->{'name'} value is too long - it must be no longer than $format->[2] characters";
			}
		} elsif ( $table eq 'users' && $_->{'name'} eq 'status' ) {

			#special case to check that changing user status is allowed
			my ($status) = @{ $self->{'datastore'}->run_simple_query( "SELECT status FROM users WHERE user_name=?", $self->{'username'} ) };
			my ( $user_status, $user_username );
			if ($update) {
				my $user_ref = $self->{'datastore'}->run_simple_query( "SELECT status,user_name FROM users WHERE id=?", $newdata{'id'} );
				( $user_status, $user_username ) = @$user_ref if ref $user_ref eq 'ARRAY';
			}
			if (   $status ne 'admin'
				&& !$self->{'permissions'}->{'set_user_permissions'}
				&& defined $user_status
				&& $newdata{'status'} ne $user_status
				&& $update )
			{
				push @problems, "You must have either admin rights or specific permission to change the status of a user.\n";
			}
			if (   $status ne 'admin'
				&& $self->{'permissions'}->{'set_user_permissions'}
				&& $newdata{'status'} ne 'admin'
				&& $user_status eq 'admin' )
			{
				push @problems, "You must have admin rights to revoke admin status from another user.\n";
			}
			if (   $status ne 'admin'
				&& $self->{'permissions'}->{'set_user_permissions'}
				&& $newdata{'status'} eq 'admin'
				&& $user_status ne 'admin'
				&& $update )
			{
				push @problems, "You must have admin rights to upgrade a user to admin status.\n";
			}
			if (   $status ne 'admin'
				&& $newdata{'status'} eq 'admin'
				&& !$update )
			{
				push @problems, "You must have admin rights to create a user with admin status.\n";
			}
			if (   $status ne 'admin'
				&& defined $user_username
				&& $newdata{'user_name'} ne $user_username
				&& $update )
			{
				push @problems, "You must have admin rights to change the username of a user.\n";
			}
		} elsif ( $table eq 'isolate_value_extended_attributes' && $_->{'name'} eq 'attribute' ) {
			my $attribute_exists = $self->{'datastore'}->run_simple_query(
				"SELECT COUNT(*) FROM isolate_field_extended_attributes WHERE isolate_field=? AND attribute=?",
				$newdata{'isolate_field'},
				$newdata{'attribute'}
			)->[0];
			if ( !$attribute_exists ) {
				my $fields =
				  $self->{'datastore'}->run_list_query( "SELECT isolate_field FROM isolate_field_extended_attributes WHERE attribute=?",
					$newdata{'attribute'} );
				my $message = "Attribute $newdata{'attribute'} has not been defined for the $newdata{'isolate_field'} field.\n";
				if (@$fields) {
					local $" = ', ';
					$message .= "  Fields with this attribute defined are: @$fields.";
				}
				push @problems, $message;
			}
		}
		if ( $_->{'primary_key'} ) {
			push @primary_key_query, "$_->{name} = E'$newdata{$_->{name}}'";
		}
	}
	if (@missing) {
		local $" = ', ';
		push @problems, "Please fill in all required fields. The following fields are missing: @missing";
	} elsif ( @primary_key_query && !@problems ) {    #only run query if there are no other problems
		local $" = ' AND ';
		my $retval = $self->{'datastore'}->run_simple_query("SELECT COUNT(*) FROM $table WHERE @primary_key_query")->[0];
		if ( $retval && !$update ) {
			my $article = $record_name =~ /^[aeio]/ ? 'An' : 'A';
			push @problems, "$article $record_name already exists with this primary key.";
		}
	}
	return @problems;
}

sub get_datestamp {
	my @date = localtime;
	my $year = 1900 + $date[5];
	my $mon  = $date[4] + 1;
	my $day  = $date[3];
	return ( sprintf( "%d-%02d-%02d", $year, $mon, $day ) );
}

sub get_sender_fullname {
	my ( $self, $id ) = @_;
	if ($id) {
		my $qry = "SELECT first_name,surname FROM users WHERE id=?";
		my $sender_ref = $self->{'datastore'}->run_simple_query( $qry, $id );
		return if ref $sender_ref ne 'ARRAY';
		return "$sender_ref->[0] $sender_ref->[1]";
	}
}

sub is_field_bad {
	my ( $self, $table, $fieldname, $value, $flag ) = @_;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq $self->{'system'}->{'view'} ) {
		return $self->_is_field_bad_isolates( $fieldname, $value, $flag );
	} else {
		return $self->_is_field_bad_other( $table, $fieldname, $value, $flag );
	}
}

sub _is_field_bad_isolates {
	my ( $self, $fieldname, $value, $flag ) = @_;
	my $q = $self->{'cgi'};
	$value = '' if !defined $value;
	$value =~ s/<blank>//;
	$value =~ s/null//;
	my $thisfield = $self->{'xmlHandler'}->get_field_attributes($fieldname);
	$thisfield->{'type'} ||= 'text';
	my $set_id = $self->get_set_id;
	$thisfield->{'required'} = 'no' if !$set_id && $fieldname =~ /^meta_/;    #Field can't be compulsory if part of a metadata collection.
	#If field is null make sure it's not a required field
	if ( $value eq '' ) {
		if (   $fieldname ~~ [qw(aliases references)] || ( ($thisfield->{'required'} // '') eq 'no' ) ){
			return 0;
		} else {
			return 'is a required field and cannot be left blank.';
		}
	}

	#Make sure curator is set right
	if ( $fieldname eq 'curator' && $value ne $self->get_curator_id ) {
		return "must be set to the currently logged in curator id (" . $self->get_curator_id . ").";
	}

	#Make sure int fields really are integers
	if ( $thisfield->{'type'} eq 'int' && !BIGSdb::Utils::is_int($value) ) {
		return 'must be an integer';
	}

	#Make sure sender is in database
	if ( $fieldname eq 'sender' or $fieldname eq 'sequenced_by' ) {
		my $qry = "SELECT DISTINCT id FROM users";
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute };
		$logger->error($@) if $@;
		while ( my ($senderid) = $sql->fetchrow_array ) {
			if ( $value == $senderid ) {
				return 0;
			}
		}
		return
		    "is not in the database users table - see <a href=\""
		  . $q->script_name
		  . "?db=$self->{'instance'}&amp;page=fieldValues&amp;field=f_sender\">list of values</a>";
	}

	#If a regex pattern exists, make sure data conforms to it
	if ( $thisfield->{'regex'} ) {
		if ( $value !~ /^$thisfield->{'regex'}$/ ) {
			if ( !( $thisfield->{'required'} && $thisfield->{'required'} eq 'no' && $value eq '' ) ) {
				return 'does not conform to the required formatting';
			}
		}
	}

	#Make sure floats fields really are floats
	if ( $thisfield->{'type'} eq 'float' && !BIGSdb::Utils::is_float($value) ) {
		return 'must be a floating point number';
	}

	#Make sure the datestamp is today
	if ( $fieldname eq 'datestamp' && ( $value ne $self->get_datestamp ) ) {
		return "must be today\'s date in yyyy-mm-dd format (" . $self->get_datestamp . ") or use 'today'";
	}
	if ( $flag && $flag eq 'insert' ) {

		#Make sure the date_entered is today
		if ( $fieldname eq 'date_entered'
			&& ( $value ne $self->get_datestamp ) )
		{
			return "must be today\'s date in yyyy-mm-dd format (" . $self->get_datestamp . ") or use 'today'";
		}
	}

	#make sure date fields really are dates in correct format
	if ( $thisfield->{'type'} eq 'date' && !BIGSdb::Utils::is_date($value)  ) {
		return "must be a valid date in yyyy-mm-dd format";
	}
	if (   $flag
		&& $flag eq 'insert'
		&& ( $fieldname eq 'id' ) )
	{

		#Make sure id number has not been used previously
		my $qry;
		$qry = "SELECT COUNT(*) FROM $self->{'system'}->{'view'} WHERE id=?";
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute($value) };
		$logger->error($@) if $@;
		my ($exists) = $sql->fetchrow_array;
		if ($exists) {
			return "$value is already in database";
		}
	}

	#Make sure options list fields only use a listed option (or null if optional)
	if ( $thisfield->{'optlist'} ) {
		my $options = $self->{'xmlHandler'}->get_field_option_list($fieldname);
		foreach (@$options) {
			if ( $value eq $_ ) {
				return 0;
			}
		}
		if ( $thisfield->{'required'} && $thisfield->{'required'} eq 'no' ) {
			return 0 if ( $value eq '' );
		}
		return "'$value' is not on the list of allowed values for this field.";
	}

	#Make sure field is not too long
	if ( $thisfield->{'length'} && length($value) > $thisfield->{'length'} ) {
		return "field is too long (maximum length $thisfield->{'length'})";
	}
	return 0;
}

sub _is_field_bad_other {
	my ( $self, $table, $fieldname, $value, $flag ) = @_;
	my $q          = $self->{'cgi'};
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my $thisfield;
	foreach (@$attributes) {
		if ( $_->{'name'} eq $fieldname ) {
			$thisfield = $_;
		}
	}
	$thisfield->{'type'} ||= 'text';

	#If field is null make sure it's not a required field
	if ( !defined $value || $value eq '' ) {
		if ( !$thisfield->{'required'} || $thisfield->{'required'} ne 'yes' ) {
			return 0;
		} else {
			return 'is a required field and cannot be left blank.';
		}
	}

	#Make sure curator is set right
	if ( $fieldname eq 'curator' && $value ne $self->get_curator_id ) {
		return "must be set to the currently logged in curator id (" . $self->get_curator_id . ").";
	}

	#Make sure int fields really are integers
	if ( $thisfield->{'type'} eq 'int' && !BIGSdb::Utils::is_int($value) ) {
		return 'must be an integer';
	}

	#Make sure sender is in database
	if ( $fieldname eq 'sender' or $fieldname eq 'sequenced_by' ) {
		my $qry = "SELECT DISTINCT id FROM users";
		my $sql = $self->{'db'}->prepare($qry) or die 'cannot prepare';
		eval { $sql->execute };
		$logger->error($@) if $@;
		while ( my ($senderid) = $sql->fetchrow_array ) {
			if ( $value == $senderid ) {
				return 0;
			}
		}
		return
		    "is not in the database user's table - see <a href=\""
		  . $q->script_name
		  . "?db=$self->{'instance'}&amp;page=fieldValues&amp;field=f_sender\">list of values</a>";
	}

	#If a regex pattern exists, make sure data conforms to it
	if ( $thisfield->{'regex'} ) {
		if ( $value !~ /^$thisfield->{regex}$/ ) {
			if ( !( $thisfield->{'required'} && $thisfield->{'required'} eq 'no' && $value eq '' ) ) {
				return 'does not conform to the required formatting';
			}
		}
	}

	#Make sure floats fields really are floats
	if ( $thisfield->{'type'} eq 'float' && !BIGSdb::Utils::is_float($value) ) {
		return 'must be a floating point number';
	}

	#Make sure the datestamp is today
	if ( $fieldname eq 'datestamp' && ( $value ne $self->get_datestamp ) ) {
		return "must be today\'s date in yyyy-mm-dd format (" . $self->get_datestamp . ") or use 'today'";
	}
	if ( $flag eq 'insert' ) {

		#Make sure the date_entered is today
		if ( $fieldname eq 'date_entered'
			&& ( $value ne $self->get_datestamp ) )
		{
			return "must be today\'s date in yyyy-mm-dd format (" . $self->get_datestamp . ") or use 'today'";
		}
	}
	if ( $flag eq 'insert'
		&& ( $thisfield->{'unique'} ) )
	{

		#Make sure unique field values have not been used previously
		my $qry = "SELECT DISTINCT $thisfield->{'name'} FROM $table";
		my $sql = $self->{'db'}->prepare($qry) or die 'cannot prepare';
		eval { $sql->execute };
		$logger->error($@) if $@;
		while ( my ($id) = $sql->fetchrow_array ) {
			if ( $value eq $id ) {
				if ( $thisfield->{'name'} =~ /sequence/ ) {
					$value = "<span class=\"seq\">" . ( BIGSdb::Utils::truncate_seq( \$value, 40 ) ) . "</span>";
				}
				return "'$value' is already in database";
			}
		}
	}

	#Make sure options list fields only use a listed option (or null if optional)
	if ( $thisfield->{'optlist'} ) {
		my @options = split /;/, $thisfield->{'optlist'};
		foreach (@options) {
			if ( $value eq $_ ) {
				return 0;
			}
		}
		if ( $thisfield->{'required'} && $thisfield->{'required'} eq 'no' ) {
			return 0 if ( $value eq '' );
		}
		return "'$value' is not on the list of allowed values for this field.";
	}

	#Make sure field is not too long
	if ( $thisfield->{length} && length($value) > $thisfield->{'length'} ) {
		return "field is too long (maximum length $thisfield->{'length'})";
	}

	#Make sure a foreign key value exists in foreign table
	if ( $thisfield->{'foreign_key'} ) {
		my $qry = "SELECT COUNT(*) FROM $thisfield->{'foreign_key'} WHERE id=?";
		my $sql = $self->{'db'}->prepare($qry) or die 'cannot prepare';
		$value = $self->map_locus_name($value) if $fieldname eq 'locus';
		eval { $sql->execute($value) };
		$logger->error($@) if $@;
		my ($exists) = $sql->fetchrow_array;
		if ( !$exists ) {
			return "value '$value' does not exist in $thisfield->{foreign_key} table";
		}
	}
	return 0;
}

sub clean_value {
	my ( $self, $value ) = @_;
	$value =~ s/'/\\'/g;
	$value =~ s/\r//g;
	$value =~ s/\n/ /g;
	return $value;
}

sub map_locus_name {
	my ( $self, $locus ) = @_;
	my $set_id = $self->get_set_id;
	return $locus if !$set_id;
	my $locus_list = $self->{'datastore'}->run_list_query( "SELECT locus FROM set_loci WHERE set_id=? AND set_name=?", $set_id, $locus );
	return $locus if @$locus_list != 1;
	return $locus_list->[0];
}

sub update_history {
	my ( $self, $isolate_id, $action ) = @_;
	return if !$action || !$isolate_id;
	my $curator_id = $self->get_curator_id;
	my $sql        = $self->{'db'}->prepare("INSERT INTO history (isolate_id,timestamp,action,curator) VALUES (?,?,?,?)");
	eval { $sql->execute( $isolate_id, 'now', $action, $curator_id ) };
	if ($@) {
		$logger->error("Can't update history for isolate $isolate_id '$action' $@");
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}

sub promote_pending_allele_designation {
	my ( $self, $isolate_id, $locus ) = @_;

	#Promote earliest pending designation if it exists
	my $pending_designations_ref = $self->{'datastore'}->get_pending_allele_designations( $isolate_id, $locus );
	return if !@$pending_designations_ref;
	my $pending    = $pending_designations_ref->[0];
	my $curator_id = $self->get_curator_id();
	$locus =~ s/'/\\'/g;
	eval {
		$self->{'db'}->do(
"INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,date_entered,datestamp,comments) VALUES ($pending->{'isolate_id'},E'$pending->{'locus'}','$pending->{'allele_id'}',$pending->{'sender'},'provisional','$pending->{'method'}',$curator_id,'$pending->{'date_entered'}','now','$pending->{'comments'}')"
		);
		$self->{'db'}->do(
"DELETE FROM pending_allele_designations WHERE isolate_id=$isolate_id AND locus=E'$locus' AND allele_id='$pending->{'allele_id'}' AND sender=$pending->{'sender'} AND method='$pending->{'method'}'"
		);
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		$self->update_history( $pending->{'isolate_id'},
			"$pending->{'locus'}: new designation '$pending->{'allele_id'}' (promoted from pending)" );
	}
	return;
}

sub delete_pending_designations {
	my ( $self, $isolate_id, $locus ) = @_;
	my $pending_designations_ref = $self->{'datastore'}->get_pending_allele_designations( $isolate_id, $locus );
	return if !@$pending_designations_ref;
	my $rows;
	eval {
		$rows = $self->{'db'}->do( "DELETE FROM pending_allele_designations WHERE isolate_id=? AND locus=?", undef, $isolate_id, $locus );
	};
	if ($@) {
		$logger->error($@);
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
		if ($rows) {
			my $plural = $rows == 1 ? '' : 's';
			$self->update_history( $isolate_id, "$locus: $rows pending designation$plural deleted" );
		}
	}
	return;
}

sub remove_profile_data {

	#Change needs to be committed outside of subroutine (to allow deletion as part of transaction)
	my ( $self, $scheme_id ) = @_;
	my $qry = "DELETE FROM profiles WHERE scheme_id = $scheme_id";
	eval { $self->{'db'}->do($qry) };
	$logger->error($@) if $@;
	return;
}

sub drop_scheme_view {

	#Change needs to be committed outside of subroutine (to allow drop as part of transaction)
	my ( $self, $scheme_id ) = @_;
	my $qry = "DROP VIEW IF EXISTS scheme_$scheme_id";
	eval {
		$self->{'db'}->do($qry);
		if ( $self->{'system'}->{'materialized_views'} && $self->{'system'}->{'materialized_views'} eq 'yes' ) {
			my $view_exists_ref =
			  $self->{'datastore'}
			  ->run_simple_query( "SELECT 1 WHERE EXISTS(SELECT * FROM matviews WHERE v_name = ?)", "scheme_$scheme_id" );
			$self->{'db'}->do("SELECT drop_matview('mv_scheme_$scheme_id')")
			  if ref $view_exists_ref eq 'ARRAY' && $view_exists_ref->[0];
		}
	};
	$logger->error($@) if $@;
	return;
}

sub create_scheme_view {

	#Used for profiles database.  A scheme view is created from the normalized data stored
	#in profiles, profile_members and profile_fields.  Searching by profile from the normalized
	#tables was too slow.
	#Needs to be committed outside of subroutine (to allow creation as part of transaction)
	my ( $self, $scheme_id ) = @_;
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	return if !@$loci || !@$scheme_fields;    #No point creating view if table doesn't have either loci or fields.
	my $pk_ref = $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key", $scheme_id );
	my $pk;
	if ( ref $pk_ref eq 'ARRAY' ) {
		$pk = $pk_ref->[0];
	} else {
		return;                               #No point creating view without a primary key.
	}
	my $qry = "CREATE OR REPLACE VIEW scheme_$scheme_id AS SELECT profiles.profile_id AS $pk,profiles.sender,"
	  . "profiles.curator,profiles.date_entered,profiles.datestamp";
	foreach (@$scheme_fields) {
		$qry .= ",$_.value AS $_" if $_ ne $pk;
	}
	foreach (@$loci) {
		( my $cleaned = $_ ) =~ s/'/_PRIME_/g;
		$qry .= ",$cleaned.allele_id AS $cleaned";
	}
	$qry .= " FROM profiles";
	foreach (@$loci) {
		( my $cleaned  = $_ ) =~ s/'/_PRIME_/g;
		( my $cleaned2 = $_ ) =~ s/'/\\'/g;
		$qry .=
" INNER JOIN profile_members AS $cleaned ON profiles.profile_id=$cleaned.profile_id AND $cleaned.locus=E'$cleaned2' AND profiles.scheme_id=$cleaned.scheme_id";
	}
	foreach (@$scheme_fields) {
		next if $_ eq $pk;
		$qry .=
" LEFT JOIN profile_fields AS $_ ON profiles.profile_id=$_.profile_id AND $_.scheme_field=E'$_' AND profiles.scheme_id=$_.scheme_id";
	}
	$qry .= " WHERE profiles.scheme_id = $scheme_id";
	eval {
		$self->{'db'}->do($qry);
		$self->{'db'}->do("GRANT SELECT ON scheme_$scheme_id TO $self->{'system'}->{'user'}");
		if ( $self->{'system'}->{'materialized_views'} && $self->{'system'}->{'materialized_views'} eq 'yes' ) {
			$self->{'db'}->do("SELECT create_matview('mv_scheme_$scheme_id', 'scheme_$scheme_id')");
			$self->{'db'}->do("CREATE UNIQUE INDEX i_mv$scheme_id\_1 ON mv_scheme_$scheme_id ($pk)");
			local $" = ',';
			my $locus_string = "@$loci";
			$locus_string =~ s/'/\\'/g;
			$self->{'db'}->do("CREATE UNIQUE INDEX i_mv$scheme_id\_2 ON mv_scheme_$scheme_id ($locus_string)");
		}
	};
	$logger->error($@) if $@;
	return;
}

sub refresh_material_view {

	#Needs to be committed outside of subroutine (to allow refresh as part of transaction)
	my ( $self, $scheme_id ) = @_;
	return if !( $self->{'system'}->{'materialized_views'} && $self->{'system'}->{'materialized_views'} eq 'yes' );
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	return if !@$loci || !@$scheme_fields;
	my $pk_ref = $self->{'datastore'}->run_simple_query( "SELECT field FROM scheme_fields WHERE scheme_id=? AND primary_key", $scheme_id );
	my $pk;

	if ( ref $pk_ref eq 'ARRAY' ) {
		$pk = $pk_ref->[0];
	} else {
		return;
	}
	eval {
		$self->{'db'}->do("DROP INDEX i_mv$scheme_id\_1");
		$self->{'db'}->do("DROP INDEX i_mv$scheme_id\_2");
		$self->{'db'}->do("SELECT refresh_matview('mv_scheme_$scheme_id')");
		$self->{'db'}->do("CREATE UNIQUE INDEX i_mv$scheme_id\_1 ON mv_scheme_$scheme_id ($pk)");
		local $" = ',';
		my $locus_string = "@$loci";
		$locus_string =~ s/'/\\'/g;
		$self->{'db'}->do("CREATE UNIQUE INDEX i_mv$scheme_id\_2 ON mv_scheme_$scheme_id ($locus_string)");
	};
	$logger->error($@) if $@;
	return;
}
1;
