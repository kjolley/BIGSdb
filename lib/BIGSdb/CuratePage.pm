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
package BIGSdb::CuratePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(any none);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Constants qw(SEQ_FLAGS ALLELE_FLAGS DATABANKS);

sub initiate {
	my ($self) = @_;
	$self->{$_} = 1 foreach qw (jQuery jQuery.multiselect noCache );
	return;
}
sub get_title     { return q(Curator's interface - BIGSdb) }
sub print_content { }

sub get_curator_name {
	my ($self) = @_;
	if ( $self->{'username'} ) {
		my $name = $self->{'datastore'}->run_query( 'SELECT first_name, surname FROM users WHERE user_name=?',
			$self->{'username'}, { fetch => 'row_hashref', cache => 'CuratePage::get_curator_name' } );
		return $name ? "$name->{'first_name'} $name->{'surname'}" : 'unknown user';
	}
	return 'unknown user';
}

sub create_record_table {
	my ( $self, $table, $newdata, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	if ( ref $newdata ne 'HASH' ) {
		say q(<div class="box" id="statusbad"><p>Record doesn't exist.</p></div>);
		return '';
	} elsif ( defined $newdata->{'isolate_id'} && !$self->is_allowed_to_view_isolate( $newdata->{'isolate_id'} ) ) {
		say q(<div class="box" id="statusbad"><p>Your account is not allowed to modify values for isolate )
		  . qq(id-$newdata->{'isolate_id'}.</p></div>);
		return '';
	}
	my $q = $self->{'cgi'};
	my $buffer;
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	$buffer .= $q->start_form;
	$q->param( action => $options->{'update'} ? 'update' : 'add' );
	$q->param( table => $table );
	$buffer .= $q->hidden($_) foreach qw(page table db action submission_id);

	if ( $table eq 'allele_designations' ) {
		$buffer .= $q->hidden( locus => $newdata->{'locus'} );
		$buffer .= $q->hidden('update_id');
	}
	$buffer .= $q->hidden( sent => 1 );
	$buffer .= q(<div class="box" id="queryform">) if !$options->{'nodiv'};
	$buffer .= qq(<p>Please fill in the fields below - required fields are marked with an exclamation mark (!).</p>\n);
	$buffer .= q(<div class="scrollable" style="white-space:nowrap">) if !$options->{'nodiv'};
	$buffer .= q(<fieldset class="form" style="float:left"><legend>Record</legend><ul>);
	my @field_names  = map { $_->{'name'} } @$attributes;
	my $longest_name = BIGSdb::Utils::get_largest_string_length( \@field_names );
	my $width        = int( 0.5 * $longest_name ) + 2;
	$width = 15 if $width > 15;
	$width = 6  if $width < 6;
	my %width_override = ( loci => 14, pcr => 12, sequences => 10, locus_descriptions => 11 );
	$width = $width_override{$table} // $width;
	$buffer .= $self->_get_form_fields( $attributes, $table, $newdata, $options, $width );
	my %methods = (
		sequences    => '_create_extra_fields_for_sequences',
		sequence_bin => '_create_extra_fields_for_seqbin',
		loci         => '_create_extra_fields_for_loci'
	);

	if ( $methods{$table} ) {
		my $method = $methods{$table};
		$buffer .= $self->$method( $newdata, $width );
	} elsif ( $table eq 'locus_descriptions' ) {
		$buffer .= $self->_create_extra_fields_for_locus_descriptions( $q->param('locus') // '', $width );
	}
	$buffer .= qq(</ul></fieldset>\n);
	my $page = $q->param('page');
	my @extra;
	if ( $options->{'update'} || $options->{'reset_params'} ) {
		my $pk_fields = $self->{'datastore'}->get_table_pks($table);
		foreach my $pk (@$pk_fields) {
			push @extra, ( $pk => $newdata->{$pk} ) if $newdata->{$pk};
		}
	}
	$buffer .= $self->print_action_fieldset( { get_only => 1, page => $page, table => $table, @extra } );
	$buffer .= qq(</div>\n</div>\n) if !$options->{'nodiv'};
	$buffer .= $q->end_form;
	return $buffer;
}

sub _populate_submission_params {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	return if !$q->param('submission_id');
	return if $q->param('page') ne 'add';
	if ( $q->param('table') eq 'sequences' && $q->param('index') && !$q->param('sequence') ) {
		my $submission_seq = $self->_get_allele_submission_sequence( $q->param('submission_id'), $q->param('index') );
		$q->param( sequence => $submission_seq );
	}
	return;
}

sub _get_allele_submission_sequence {
	my ( $self, $submission_id, $index ) = @_;
	return if $self->{'system'}->{'dbtype'} ne 'sequences';
	return $self->{'datastore'}
	  ->run_query( 'SELECT sequence FROM allele_submission_sequences WHERE (submission_id,index)=(?,?)',
		[ $submission_id, $index ] );
}

sub get_user_list_and_labels {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $users      = [];
	my $user_names = {};
	$user_names->{''} = $options->{'blank_message'} ? $options->{'blank_message'} : q( );
	my $user_data =
	  $self->{'datastore'}->run_query( 'SELECT id,user_name,first_name,surname FROM users WHERE id>0 ORDER BY surname',
		undef, { fetch => 'all_arrayref', slice => {} } );
	foreach my $user (@$user_data) {
		push @$users, $user->{'id'};
		$user_names->{ $user->{'id'} } = "$user->{'surname'}, $user->{'first_name'} ($user->{'user_name'})";
	}
	return ( $users, $user_names );
}

sub _get_form_fields {
	my ( $self, $attributes, $table, $newdata_ref, $options, $width ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	$self->_populate_submission_params if $q->param('submission_id');
	my %newdata = %{$newdata_ref};
	my $buffer  = '';
	foreach my $required (qw(1 0)) {
		foreach my $att (@$attributes) {
			next if ( any { $att->{'name'} eq $_ } @{ $options->{'noshow'} } );

			#Project description can include HTML - don't escape.   We may need to exclude other tables too.
			$newdata{ $att->{'name'} } = BIGSdb::Utils::escape_html( $newdata{ $att->{'name'} } )
			  if $table ne 'projects';
			my %html5_args;
			$html5_args{'required'} = 'required' if $att->{'required'} eq 'yes';
			if ( $att->{'type'} eq 'int' && !$att->{'dropdown_query'} && !$att->{'optlist'} ) {
				@html5_args{qw(type min step)} = qw(number 1 1);
			}
			my $name = $options->{'prepend_table_name'} ? "$table\_$att->{'name'}" : $att->{'name'};
			if (   ( $att->{'required'} eq 'yes' && $required )
				|| ( ( !$att->{'required'} || $att->{'required'} eq 'no' ) && !$required ) )
			{
				my $length = $att->{'length'} || ( $att->{'type'} eq 'int' ? 15 : 50 );
				( my $cleaned_name = $att->{name} ) =~ tr/_/ /;
				my ( $label, $title ) = $self->get_truncated_label( $cleaned_name, 24 );
				my $title_attribute = $title ? qq( title="$title") : q();

				#Associate label with form element (element has to exist)
				my $for =
				     ( none { $att->{'name'} eq $_ } qw (curator date_entered datestamp) )
				  && $att->{'type'} ne 'bool'
				  && !(( $options->{'update'} && $att->{'primary_key'} )
					|| ( $options->{'newdata_readonly'} && $newdata{ $att->{'name'} } ) )
				  ? " for=\"$name\""
				  : '';
				$buffer .= qq(<li><label$for class="form" style="width:${width}em"$title_attribute>);
				$buffer .= qq($label:);
				$buffer .= q(!) if $att->{'required'} eq 'yes';
				$buffer .= q(</label>);
				if (   ( $options->{'update'} && $att->{'primary_key'} )
					|| ( $options->{'newdata_readonly'} && $newdata{ $att->{'name'} } ) )
				{
					my $desc;
					if (
						!$self->{'curate'}
						&& (   ( $att->{'name'} eq 'locus' && $table ne 'set_loci' )
							|| ( $table eq 'loci' && $att->{'name'} eq 'id' ) )
					  )
					{
						$desc = $self->clean_locus( $newdata{ $att->{'name'} } );
					} elsif ( $att->{'labels'} ) {
						$desc = $self->_get_foreign_key_label( $name, $newdata_ref, $att );
					} else {
						( $desc = $newdata{ $att->{'name'} } ) =~ tr/_/ /;
					}
					$buffer .= "<b>$desc";
					if ( $table eq 'samples' && $att->{'name'} eq 'isolate_id' ) {
						$buffer .= ') ' . $self->get_isolate_name_from_id( $newdata{ $att->{'name'} } );
					}
					$buffer .= '</b>';
					$buffer .= $q->hidden( $name, $newdata{ $att->{'name'} } );
				} elsif ( $q->param('page') eq 'update' && ( $att->{'user_update'} // '' ) eq 'no' ) {
					$buffer .= qq(<span id="$att->{'name'}">\n);
					if ( $att->{'name'} eq 'sequence' ) {
						my $data_length = length( $newdata{ $att->{'name'} } );
						if ( $data_length > 5000 ) {
							$buffer .=
							    q[<span class="seq"><b>]
							  . BIGSdb::Utils::truncate_seq( \$newdata{ $att->{'name'} }, 40 )
							  . qq[</b></span><br />sequence is $data_length characters (too long to display)];
						} else {
							$buffer .= $q->textarea(
								-name     => $att->{'name'},
								-rows     => 6,
								-cols     => 40,
								-disabled => 'disabled',
								-default  => BIGSdb::Utils::split_line( $newdata{ $att->{'name'} } )
							);
						}
					} else {
						$buffer .= "<b>$newdata{$att->{'name'}}</b>";
					}
					$buffer .= "</span>\n";
				} elsif ( $att->{'name'} eq 'sender' ) {
					my ( $users, $user_names ) = $self->get_user_list_and_labels;
					$buffer .= $q->popup_menu(
						-name    => $name,
						-id      => $name,
						-values  => [ '', @$users ],
						-labels  => $user_names,
						-default => $newdata{ $att->{'name'} },
						%html5_args
					);
				} elsif ( $table eq 'sequences' && $att->{'name'} eq 'allele_id' && $q->param('locus') ) {
					my $locus_info = $self->{'datastore'}->get_locus_info( $q->param('locus') );
					if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
						my $default = $self->{'datastore'}->get_next_allele_id( $q->param('locus') );
						$buffer .= $self->textfield(
							name      => $name,
							id        => $name,
							size      => $length,
							maxlength => $length,
							value     => $default,
							%html5_args
						);
					} else {
						$buffer .= $self->textfield(
							name      => $name,
							id        => $name,
							size      => $length,
							maxlength => $length,
							value     => $newdata{ $att->{'name'} },
							%html5_args
						);
					}
				} elsif (
					(
						   $table eq 'sequences'
						|| $table eq 'sequence_refs'
						|| $table eq 'accession'
						|| $table eq 'locus_descriptions'
					)
					&& $att->{'name'} eq 'locus'
					&& !$self->is_admin
				  )
				{
					my $set_id = $self->get_set_id;
					my ( $values, $desc ) =
					  $self->{'datastore'}->get_locus_list(
						{ set_id => $set_id, no_list_by_common_name => 1, locus_curator => $self->get_curator_id } );
					$values = [] if ref $values ne 'ARRAY';
					$buffer .= $q->popup_menu(
						-name    => $name,
						-id      => $name,
						-values  => [ '', @$values ],
						-labels  => $desc,
						-default => $newdata{ $att->{'name'} },
						%html5_args
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
					my $qry;
					my $set_id = $self->get_set_id;
					my $values;
					if ( $att->{'foreign_key'} eq 'users' ) {
						local $" = ',';
						$qry = "SELECT id FROM users WHERE id>0 ORDER BY @fields_to_query";
						$values = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
					} elsif ( $att->{'foreign_key'} eq 'loci' && $table ne 'set_loci' && $set_id ) {
						( $values, $desc ) =
						  $self->{'datastore'}->get_locus_list( { set_id => $set_id, no_list_by_common_name => 1 } );
					} elsif ( $att->{'foreign_key'} eq 'schemes' && $table ne 'set_schemes' && $set_id ) {
						my $scheme_list = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
						push @$values, $_->{'id'} foreach @$scheme_list;
					} else {
						local $" = ',';
						$qry = "SELECT id FROM $att->{'foreign_key'} ORDER BY @fields_to_query";
						$values = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
					}
					$values = [] if ref $values ne 'ARRAY';
					$buffer .= $q->popup_menu(
						-name    => $name,
						-id      => $name,
						-values  => [ '', @$values ],
						-labels  => $desc,
						-default => $newdata{ $att->{'name'} },
						%html5_args
					);
				} elsif ( $att->{'name'} eq 'datestamp' ) {
					$buffer .= '<b>' . $self->get_datestamp . "</b>\n";
				} elsif ( $att->{'name'} eq 'date_entered' ) {
					if ( $q->param('page') eq 'update' or $q->param('page') eq 'alleleUpdate' ) {
						$buffer .= '<b>' . $newdata{ $att->{'name'} } . "</b>\n";
					} else {
						$buffer .= '<b>' . $self->get_datestamp . "</b>\n";
					}
				} elsif ( $att->{'name'} eq 'curator' ) {
					$buffer .= '<b>' . $self->get_curator_name . ' (' . $self->{'username'} . ")</b>\n";
				} elsif ( $att->{'type'} eq 'bool' ) {
					$buffer .= $self->_get_boolean_field( $name, $newdata_ref, $att );
				} elsif ( $att->{'optlist'} ) {
					my @optlist;
					if ( $att->{'optlist'} eq 'isolate_fields' ) {
						@optlist = @{ $self->{'xmlHandler'}->get_field_list() };
					} else {
						@optlist = split /;/x, $att->{'optlist'};
					}
					unshift @optlist, '';
					my $labels = { '' => ' ' };    #Required for HTML5 validation
					$buffer .= $q->popup_menu(
						-name    => $name,
						-id      => $name,
						-values  => [@optlist],
						-default => $options->{'update'} ? $newdata{ $att->{'name'} } : $att->{'default'},
						-labels  => $labels,
						%html5_args
					);
				} else {
					if ( $length >= 256 ) {
						$newdata{ $att->{'name'} } = BIGSdb::Utils::split_line( $newdata{ $att->{'name'} } )
						  if $att->{'name'} eq 'sequence';
						$buffer .= $q->textarea(
							-name    => $name,
							-id      => $name,
							-rows    => 6,
							-cols    => 75,
							-default => $newdata{ $att->{'name'} },
							%html5_args
						);
					} elsif ( $length >= 120 ) {
						$newdata{ $att->{'name'} } = BIGSdb::Utils::split_line( $newdata{ $att->{'name'} } )
						  if $att->{'name'} eq 'sequence';
						$buffer .= $q->textarea(
							-name    => $name,
							-id      => $name,
							-rows    => 3,
							-cols    => 75,
							-default => $newdata{ $att->{'name'} },
							%html5_args
						);
					} else {
						$buffer .= $self->textfield(
							name      => $name,
							id        => $name,
							size      => ( $length > 75 ? 75 : $length ),
							maxlength => $length,
							value     => $newdata{ $att->{'name'} },
							%html5_args
						);
					}
				}
				if ( $att->{'tooltip'} ) {
					$buffer .= qq(&nbsp;<a class="tooltip" title="$att->{'tooltip'}">)
					  . q(<span class="fa fa-info-circle"></span></a>);
				}
				if ( $att->{'comments'} ) {
					my $padding = $att->{'type'} eq 'bool' ? '3em' : 0;
					$buffer .= qq( <span class="comment" style="padding-left:$padding">$att->{'comments'}</span>);
				} elsif ( $att->{'type'} eq 'date'
					&& lc( $att->{'name'} ne 'datestamp' )
					&& lc( $att->{'name'} ne 'date_entered' ) )
				{
					$buffer .= q( <span class="comment">format: yyyy-mm-dd (or 'today')</span>);
				}
				$buffer .= qq(</li>\n);
			}
		}
	}
	return $buffer;
}

sub _get_foreign_key_label {
	my ( $self, $name, $newdata_ref, $att ) = @_;
	my @fields_to_query;
	my @values = split /\|/x, $att->{'labels'};
	foreach (@values) {
		if ( $_ =~ /\$(.*)/x ) {
			push @fields_to_query, $1;
		}
	}
	local $" = ',';
	my $data = $self->{'datastore'}->run_query(
		"select id,@fields_to_query from $att->{'foreign_key'} WHERE id=?",
		$newdata_ref->{ $att->{'name'} },
		{ fetch => 'row_hashref' }
	);
	my $desc = $att->{'labels'};
	$desc =~ s/$_/$data->{$_}/x foreach @fields_to_query;
	$desc =~ s/[\|\$]//gx;
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

sub _create_extra_fields_for_sequences {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $newdata, $width ) = @_;
	my $q = $self->{'cgi'};
	my $buffer;
	if ( ( $self->{'system'}->{'allele_flags'} // '' ) eq 'yes' ) {
		my $list = $self->{'datastore'}->get_allele_flags( $q->param('locus'), $q->param('allele_id') );
		$buffer .= qq(<li><label for="flags" class="form" style="width:${width}em">Flags:</label>\n);
		$buffer .= $q->scrolling_list(
			-name     => 'flags',
			-id       => 'flags',
			-values   => [ALLELE_FLAGS],
			-size     => 5,
			-multiple => 'true',
			-default  => $list
		);
		$buffer .= q( <span class="comment no_touch">Use Ctrl click to select/deselect multiple choices</span>);
		$buffer .= qq(</li>\n);
	}
	my @databanks = DATABANKS;
	my @default_pubmed;
	my $default_databanks;
	if ( $q->param('page') eq 'update' && $q->param('locus') ) {
		my $pubmed_list = $self->{'datastore'}->run_query(
			'SELECT pubmed_id FROM sequence_refs WHERE (locus,allele_id)=(?,?) ORDER BY pubmed_id',
			[ $q->param('locus'), $q->param('allele_id') ],
			{ fetch => 'col_arrayref' }
		);
		@default_pubmed = @$pubmed_list;
		foreach my $databank (@databanks) {
			my $list = $self->{'datastore'}->run_query(
				'SELECT databank_id FROM accession WHERE (locus,allele_id,databank)=(?,?,?) ORDER BY databank_id',
				[ $q->param('locus'), $q->param('allele_id'), $databank ],
				{ fetch => 'col_arrayref' }
			);
			$default_databanks->{$databank} = $list;
		}
	}
	$buffer .= qq(<li><label for="pubmed" class="form" style="width:${width}em">PubMed ids:</label>);
	local $" = "\n";
	$buffer .= $q->textarea(
		-name    => 'pubmed',
		-id      => 'pubmed',
		-rows    => 2,
		-cols    => 12,
		-style   => 'width:10em',
		-default => "@default_pubmed"
	);
	$buffer .= qq(</li>\n);
	foreach my $databank (@databanks) {
		$buffer .= qq(<li><label for="databank_$databank" class="form" style="width:${width}em">$databank ids:</label>);
		my @default;
		if ( ref $default_databanks->{$databank} eq 'ARRAY' ) {
			@default = @{ $default_databanks->{$databank} };
		}
		$buffer .= $q->textarea(
			-name    => "databank_$databank",
			-id      => "databank_$databank",
			-rows    => 2,
			-cols    => 12,
			-style   => 'width:10em',
			-default => "@default"
		);
		$buffer .= qq(</li>\n);
	}
	if ( $q->param('locus') ) {
		my $locus   = $q->param('locus');
		my $ext_att = $self->{'datastore'}->run_query(
			'SELECT field,description,value_format,required,length,option_list FROM '
			  . 'locus_extended_attributes WHERE locus=? ORDER BY field_order',
			$locus,
			{ fetch => 'all_arrayref' }
		);
		foreach my $att (@$ext_att) {
			my ( $field, $desc, $format, $required, $length, $optlist ) = @$att;
			$buffer .=
			    qq(<li><label for="$field" class="form" style="width:${width}em">$field:)
			  . ( $required ? '!' : '' )
			  . qq(</label>\n);
			$length = 12 if !$length;
			my %html5_args;
			$html5_args{'required'} = 'required' if $required;
			if ( $format eq 'integer' && !$optlist ) {
				@html5_args{qw(type min step)} = qw(number 1 1);
			}
			if ( $format eq 'boolean' ) {
				$buffer .= $q->popup_menu(
					-name    => $field,
					-id      => $field,
					-values  => [ '', qw (true false) ],
					-default => $newdata->{$field},
					%html5_args
				);
			} elsif ($optlist) {
				my @options = split /\|/x, $optlist;
				unshift @options, '';
				$buffer .= $q->popup_menu(
					-name    => $field,
					-id      => $field,
					-values  => \@options,
					-default => $newdata->{$field},
					%html5_args
				);
			} elsif ( $length > 256 ) {
				$buffer .= $q->textarea(
					-name    => $field,
					-id      => $field,
					-rows    => 6,
					-cols    => 70,
					-default => $newdata->{$field},
					%html5_args
				);
			} elsif ( $length > 60 ) {
				$buffer .= $q->textarea(
					-name    => $field,
					-id      => $field,
					-rows    => 3,
					-cols    => 70,
					-default => $newdata->{$field},
					%html5_args
				);
			} else {
				$buffer .= $self->textfield(
					name      => $field,
					id        => $field,
					size      => $length,
					maxlength => $length,
					value     => $newdata->{$field},
					%html5_args
				);
			}
			$buffer .= qq(<span class="comment"> $desc</span>\n) if $desc;
			$buffer .= qq(</li>\n);
		}
		my $locus_info = $self->{'datastore'}->get_locus_info( $q->param('locus') );
		if ( ( !$q->param('locus') || ( ref $locus_info eq 'HASH' && $locus_info->{'data_type'} ne 'peptide' ) )
			&& $q->param('page') ne 'update' )
		{
			$buffer .= q(<li>);
			$buffer .= $q->checkbox( -name => 'ignore_similarity', -label => 'Override sequence similarity check' );
			$buffer .= qq(</li>\n);
		}
	}
	$buffer .= q(<li>);
	$buffer .= $q->checkbox( -name => 'ignore_length', -label => 'Override sequence length check' );
	$buffer .= qq(</li>\n);
	return $buffer;
}

sub _create_extra_fields_for_locus_descriptions {
	my ( $self, $locus, $width ) = @_;
	my $q = $self->{'cgi'};
	my $buffer;
	my @default_aliases;
	if ( $q->param('page') eq 'update' && $locus ) {
		my $alias_list =
		  $self->{'datastore'}->run_query( 'SELECT alias FROM locus_aliases WHERE locus=? ORDER BY alias',
			$locus, { fetch => 'col_arrayref' } );
		@default_aliases = @$alias_list;
	}
	$buffer .= qq(<li><label for="aliases" class="form" style="width:${width}em">aliases:&nbsp;</label>);
	local $" = "\n";
	$buffer .=
	  $q->textarea( -name => 'aliases', -id => 'aliases', -rows => 2, -cols => 12, -default => "@default_aliases" );
	$buffer .= "</li>\n";
	return $buffer if $self->{'system'}->{'dbtype'} eq 'isolates';
	my @default_pubmed;
	if ( $q->param('page') eq 'update' && $locus ) {
		my $pubmed_list =
		  $self->{'datastore'}->run_query( 'SELECT pubmed_id FROM locus_refs WHERE locus=? ORDER BY pubmed_id',
			$locus, { fetch => 'col_arrayref' } );
		@default_pubmed = @$pubmed_list;
	}
	$buffer .= qq(<li><label for="pubmed" class="form" style="width:${width}em">PubMed ids:&nbsp;</label>);
	$buffer .=
	  $q->textarea( -name => 'pubmed', -id => 'pubmed', -rows => 2, -cols => 12, -default => "@default_pubmed" );
	$buffer .= "</li>\n";
	my @default_links;
	if ( $q->param('page') eq 'update' && $locus ) {
		my $desc_data =
		  $self->{'datastore'}->run_query( 'SELECT url,description FROM locus_links WHERE locus=? ORDER BY link_order',
			$locus, { fetch => 'all_arrayref', slice => {} } );
		foreach my $data (@$desc_data) {
			push @default_links, "$data->{'url'}|$data->{'description'}";
		}
	}
	$buffer .= qq[<li><label for="links" class="form" style="width:${width}em">links: <br /><span class="comment">]
	  . q[(Format: URL|description)</span></label>];
	$buffer .= $q->textarea( -name => 'links', -id => 'links', -rows => 3, -cols => 40, -default => "@default_links" );
	$buffer .= q(</li>);
	return $buffer;
}

sub _create_extra_fields_for_seqbin {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $newdata_ref, $width ) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = '';
	if ( $q->param('page') ne 'update' ) {
		my $experiments =
		  $self->{'datastore'}->run_query( 'SELECT id,description FROM experiments ORDER BY description',
			undef, { fetch => 'all_arrayref', slice => {} } );
		my @ids = (0);
		my %desc;
		$desc{0} = ' ';
		foreach my $experiment (@$experiments) {
			push @ids, $experiment->{'id'};
			$desc{ $experiment->{'id'} } = $experiment->{'description'};
		}
		if ( @ids > 1 ) {
			$buffer .=
			  qq(<li><label for="experiment" class="form" style="width:${width}em">link to experiment:&nbsp;</label>\n);
			$buffer .= $q->popup_menu(
				-name    => 'experiment',
				-id      => 'experiment',
				-values  => \@ids,
				-default => $newdata_ref->{'experiment'},
				-labels  => \%desc
			);
			$buffer .= "</li>\n";
		}
	}
	my $seq_attributes =
	  $self->{'datastore'}->run_query( 'SELECT key,type,description FROM sequence_attributes ORDER BY key',
		undef, { fetch => 'all_arrayref', slice => {} } );
	if ( $q->param('page') eq 'update' ) {
		my $attribute_values =
		  $self->{'datastore'}->run_query( 'SELECT key,value FROM sequence_attribute_values WHERE seqbin_id=?',
			$newdata_ref->{'id'}, { fetch => 'all_arrayref', slice => {} } );
		foreach my $att_value (@$attribute_values) {
			$newdata_ref->{ $att_value->{'key'} } = $att_value->{'value'};
		}
	}
	if (@$seq_attributes) {
		foreach my $attribute (@$seq_attributes) {
			( my $label = $attribute->{'key'} ) =~ s/_/ /;
			$buffer .= qq(<li><label for="$attribute->{'key'}" class="form" style="width:${width}em">$label:</label>\n);
			$buffer .= $q->textfield(
				-name  => $attribute->{'key'},
				-id    => $attribute->{'key'},
				-value => $newdata_ref->{ $attribute->{'key'} }
			);
			if ( $attribute->{'description'} ) {
				$buffer .= qq( <a class="tooltip" title="$attribute->{'key'} - $attribute->{'description'}">)
				  . q(<span class="fa fa-info-circle"></span></a>);
			}
		}
	}
	return $buffer;
}

sub _create_extra_fields_for_loci {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $newdata_ref, $width ) = @_;
	my $q      = $self->{'cgi'};
	my $buffer = '';
	if ( $self->{'system'}->{'dbtype'} eq 'sequences' ) {
		my $attributes = $self->{'datastore'}->get_table_field_attributes('locus_descriptions');
		if ( defined $newdata_ref->{'id'} ) {
			my $desc_ref = $self->{'datastore'}->run_query( 'SELECT * FROM locus_descriptions WHERE locus=?',
				$newdata_ref->{'id'}, { fetch => 'row_hashref' } );
			( $newdata_ref->{$_} = $desc_ref->{$_} ) foreach qw(full_name product description);
		}
		$buffer .=
		  $self->_get_form_fields( $attributes, 'locus_descriptions', $newdata_ref,
			{ noshow => [qw(locus curator datestamp)] }, $width );
	}
	$buffer .= $self->_create_extra_fields_for_locus_descriptions( $q->param('id') // '', $width );
	return $buffer;
}

sub check_record {
	my ( $self, $table, $newdata, $update, $allowed_values ) = @_;

	#TODO prevent scheme group belonging to a child
	my $record_name = $self->get_record_name($table);
	my $q           = $self->{'cgi'};
	my ( @problems, @missing );
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my @primary_key_query;
	foreach my $att (@$attributes) {
		next if $update && $att->{'user_update'} && $att->{'user_update'} eq 'no';
		my $original_data = $newdata->{ $att->{'name'} };
		if ( $att->{'name'} =~ /sequence$/x ) {
			$newdata->{ $att->{'name'} } = uc( $newdata->{ $att->{'name'} } // '' );
			$newdata->{ $att->{'name'} } =~ s/\s//gx;
		}
		if ( $att->{'required'} eq 'yes'
			&& ( !defined $newdata->{ $att->{'name'} } || $newdata->{ $att->{'name'} } eq '' ) )
		{
			push @missing, $att->{'name'};
		} elsif ( $newdata->{ $att->{'name'} }
			&& $att->{'type'} eq 'int'
			&& !BIGSdb::Utils::is_int( $newdata->{ $att->{'name'} } ) )
		{
			push @problems, "$att->{name} must be an integer.\n";
		} elsif ( $newdata->{ $att->{'name'} }
			&& $att->{'type'} eq 'float'
			&& !BIGSdb::Utils::is_float( $newdata->{ $att->{'name'} } ) )
		{
			push @problems, "$att->{name} must be a floating point number.\n";
		} elsif ( $newdata->{ $att->{'name'} }
			&& $att->{'type'} eq 'date'
			&& !BIGSdb::Utils::is_date( $newdata->{ $att->{'name'} } ) )
		{
			push @problems, "$newdata->{$att->{name}} must be in date format (yyyy-mm-dd or 'today').\n";
		} elsif ( defined $newdata->{ $att->{'name'} }
			&& $newdata->{ $att->{'name'} } ne ''
			&& $att->{'regex'}
			&& $newdata->{ $att->{'name'} } !~ /$att->{'regex'}/x )
		{
			push @problems, "Field '$att->{name}' does not conform to specified format.\n";
		} elsif ( $att->{'unique'} ) {
			my $exists =
			  $self->{'datastore'}
			  ->run_query( "SELECT EXISTS(SELECT * FROM $table WHERE $att->{name} =?)", $newdata->{ $att->{'name'} } );
			if (   ( $update && $exists && $newdata->{ $att->{'name'} } ne $allowed_values->{ $att->{'name'} } )
				|| ( $exists && !$update ) )
			{
				if ( $att->{'name'} =~ /sequence/ ) {
					my @primary_keys = $self->{'datastore'}->get_primary_keys($table);
					local $" = ', ';
					my $values = $self->{'datastore'}->run_query(
						"SELECT @primary_keys FROM $table WHERE $att->{'name'}=?",
						$newdata->{ $att->{'name'} },
						{ fetch => 'row_arrayref' }
					);
					my @key;
					for ( my $i = 0 ; $i < scalar @primary_keys ; $i++ ) {
						push @key, "$primary_keys[$i]: $values->[$i]";
					}
					push @problems, "This sequence already exists in the database as '@key'.";
				} else {
					my $article = $record_name =~ /^[aeio]/x ? 'An' : 'A';
					push @problems,
					  "$article $record_name already exists with $att->{'name'} = '$newdata->{$att->{'name'}}', "
					  . "please choose a different $att->{'name'}.";
				}
			}
		} elsif ( $att->{'foreign_key'} ) {
			my $exists =
			  $self->{'datastore'}
			  ->run_query( "SELECT EXISTS(SELECT * FROM $att->{'foreign_key'} WHERE id=?)", $original_data );
			if ( !$exists ) {
				push @problems,
				  "$att->{'name'} should refer to a record within the $att->{'foreign_key'} table, but it doesn't.";
			}
		} elsif ( ( $table eq 'allele_designations' )
			&& $att->{'name'} eq 'allele_id' )
		{
			#special case to check for allele id format and regex which is defined in loci table
			my $format =
			  $self->{'datastore'}->run_query( 'SELECT allele_id_format,allele_id_regex FROM loci WHERE id=?',
				$newdata->{'locus'}, { fetch => 'row_hashref' } );
			if ( $format->{'allele_id_format'} eq 'integer'
				&& !BIGSdb::Utils::is_int( $newdata->{ $att->{'name'} } ) )
			{
				push @problems, "$att->{'name'} must be an integer.\n";
			} elsif ( $format->{'allele_id_regex'} && $newdata->{ $att->{'name'} } !~ /$format->{'allele_id_regex'}/x )
			{
				push @problems, "$att->{'name'} value is invalid - it must match the regular "
				  . "expression /$format->{'allele_id_regex'}/.";
			}
		} elsif ( ( $table eq 'isolate_field_extended_attributes' )
			&& $att->{'name'} eq 'attribute'
			&& $newdata->{ $att->{'name'} } =~ /'/x )
		{
			push @problems, "Attribute contains invalid characters.\n";
		} elsif ( ( $table eq 'isolate_value_extended_attributes' )
			&& $att->{'name'} eq 'value' )
		{
			#special case to check for extended attribute value format and
			#regex which is defined in isolate_field_extended_attributes table
			my $format = $self->{'datastore'}->run_query(
				'SELECT value_format,value_regex,length FROM isolate_field_extended_attributes '
				  . 'WHERE isolate_field=? AND attribute=?',
				[ $newdata->{'isolate_field'}, $newdata->{'attribute'} ],
				{ fetch => 'row_arrayref' }
			);
			next if !$format;
			if ( $format->[0] eq 'integer'
				&& !BIGSdb::Utils::is_int( $newdata->{ $att->{'name'} } ) )
			{
				push @problems, "$att->{'name'} must be an integer.\n";
			} elsif ( $format->[1] && $newdata->{ $att->{'name'} } !~ /$format->[1]/x ) {
				push @problems, "$att->{'name'} value is invalid - it must match the regular expression /$format->[1]/";
			} elsif ( $format->[2] && length( $newdata->{ $att->{'name'} } ) > $format->[2] ) {
				push @problems, "$att->{'name'} value is too long - it must be no longer than $format->[2] characters";
			}
		} elsif ( $table eq 'users' && $att->{'name'} eq 'status' ) {

			#special case to check that changing user status is allowed
			my $status =
			  $self->{'datastore'}->run_query( 'SELECT status FROM users WHERE user_name=?', $self->{'username'} );
			my ( $user_status, $user_username );
			if ($update) {
				( $user_status, $user_username ) =
				  $self->{'datastore'}->run_query( 'SELECT status,user_name FROM users WHERE id=?', $newdata->{'id'} );
			}
			$user_status //= q();
			if (   $status ne 'admin'
				&& defined $user_status
				&& $newdata->{'status'} ne $user_status
				&& $update )
			{
				push @problems,
				  "You must have admin rights to change the status of a user.\n";
			}
			if (   $status ne 'admin'
				&& $newdata->{'status'} ne 'admin'
				&& $user_status eq 'admin' )
			{
				push @problems, "You must have admin rights to revoke admin status from another user.\n";
			}
			if (   $status ne 'admin'
				&& $newdata->{'status'} eq 'admin'
				&& $user_status ne 'admin'
				&& $update )
			{
				push @problems, "You must have admin rights to upgrade a user to admin status.\n";
			}
			if (   $status ne 'admin'
				&& $newdata->{'status'} ne 'user'
				&& !$update )
			{
				push @problems, "You must have admin rights to create a user with a status other than 'user'.\n";
			}
			if (   $status ne 'admin'
				&& defined $user_username
				&& $newdata->{'user_name'} ne $user_username
				&& $update )
			{
				push @problems, "You must have admin rights to change the username of a user.\n";
			}
		} elsif ( $table eq 'isolate_value_extended_attributes' && $att->{'name'} eq 'attribute' ) {
			my $attribute_exists = $self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM isolate_field_extended_attributes WHERE (isolate_field,attribute)=(?,?))',
				[ $newdata->{'isolate_field'}, $newdata->{'attribute'} ]
			);
			if ( !$attribute_exists ) {
				my $fields = $self->{'datastore'}->run_query(
					'SELECT isolate_field FROM isolate_field_extended_attributes WHERE attribute=?',
					$newdata->{'attribute'},
					{ fetch => 'col_arrayref' }
				);
				my $message = "Attribute $newdata->{'attribute'} has not been defined for "
				  . "the $newdata->{'isolate_field'} field.\n";
				if (@$fields) {
					local $" = ', ';
					$message .= "  Fields with this attribute defined are: @$fields.";
				}
				push @problems, $message;
			}
		}
		if ( $att->{'primary_key'} ) {
			( my $cleaned_name = $newdata->{ $att->{name} } ) =~ s/'/\\'/gx;
			push @primary_key_query, "$att->{name} = E'$cleaned_name'";
		}
	}
	if (@missing) {
		local $" = ', ';
		push @problems, "Please fill in all required fields. The following fields are missing: @missing";
	} elsif ( @primary_key_query && !@problems ) {    #only run query if there are no other problems
		local $" = ' AND ';
		my $exists = $self->{'datastore'}->run_query("SELECT EXISTS(SELECT * FROM $table WHERE @primary_key_query)");
		if ( $exists && !$update ) {
			my $article = $record_name =~ /^[aeio]/x ? 'An' : 'A';
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
	return sprintf( '%d-%02d-%02d', $year, $mon, $day );
}

sub is_field_bad {
	my ( $self, $table, $fieldname, $value, $flag ) = @_;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' && $table eq 'isolates' ) {
		return $self->_is_field_bad_isolates( $fieldname, $value, $flag );
	} else {
		return $self->_is_field_bad_other( $table, $fieldname, $value, $flag );
	}
}

sub _user_exists {
	my ( $self, $user_id ) = @_;
	if ( !$self->{'cache'}->{'users'} ) {
		my $users = $self->{'datastore'}->run_query( 'SELECT id FROM users', undef, { fetch => 'col_arrayref' } );
		%{ $self->{'cache'}->{'users'} } = map { $_ => 1 } @$users;
	}
	return 1 if $self->{'cache'}->{'users'}->{$user_id};
	return;
}

sub _is_field_bad_isolates {
	my ( $self, $fieldname, $value, $flag ) = @_;
	my $q = $self->{'cgi'};
	$value = '' if !defined $value;
	$value =~ s/<blank>//x;
	$value =~ s/null//;
	my $thisfield = $self->{'xmlHandler'}->get_field_attributes($fieldname);
	$thisfield->{'type'} ||= 'text';
	my $set_id = $self->get_set_id;

	#Field can't be compulsory if part of a metadata collection. If field is null make sure it's not a required field.
	$thisfield->{'required'} = 'no' if !$set_id && $fieldname =~ /^meta_/x;
	if ( $value eq '' ) {
		if ( $fieldname eq 'aliases' || $fieldname eq 'references' || ( ( $thisfield->{'required'} // '' ) eq 'no' ) ) {
			return 0;
		} else {
			return 'is a required field and cannot be left blank.';
		}
	}

	#Make sure curator is set right
	if ( $fieldname eq 'curator' && $value ne $self->get_curator_id ) {
		return 'must be set to the currently logged in curator id (' . $self->get_curator_id . ').';
	}

	#Make sure int fields really are integers and obey min/max values if set
	if ( $thisfield->{'type'} eq 'int' ) {
		if ( !BIGSdb::Utils::is_int($value) ) { return 'must be an integer' }
		elsif ( defined $thisfield->{'min'} && $value < $thisfield->{'min'} ) {
			return "must be equal to or larger than $thisfield->{'min'}.";
		} elsif ( defined $thisfield->{'max'} && $value > $thisfield->{'max'} ) {
			return "must be equal to or smaller than $thisfield->{'max'}.";
		}
	}

	#Make sure sender is in database
	if ( $fieldname eq 'sender' or $fieldname eq 'sequenced_by' ) {
		my $sender_exists = $self->_user_exists($value);
		return qq(is not in the database users table - see <a href="$self->{'system'}->{'script_name'}?)
		  . qq(db=$self->{'instance'}&amp;page=fieldValues&amp;field=f_sender">list of values</a>)
		  if !$sender_exists;
	}

	#If a regex pattern exists, make sure data conforms to it
	if ( $thisfield->{'regex'} ) {
		if ( $value !~ /^$thisfield->{'regex'}$/x ) {
			if ( !( $thisfield->{'required'} && $thisfield->{'required'} eq 'no' && $value eq '' ) ) {
				return 'does not conform to the required formatting.';
			}
		}
	}

	#Make sure floats fields really are floats
	if ( $thisfield->{'type'} eq 'float' && !BIGSdb::Utils::is_float($value) ) {
		return 'must be a floating point number';
	}

	#Make sure the datestamp is today
	if ( $fieldname eq 'datestamp' && ( $value ne $self->get_datestamp ) ) {
		return q[must be today's date in yyyy-mm-dd format (] . $self->get_datestamp . q[) or use 'today'];
	}
	if ( $flag && $flag eq 'insert' ) {

		#Make sure the date_entered is today
		if ( $fieldname eq 'date_entered'
			&& ( $value ne $self->get_datestamp ) )
		{
			return q[must be today's date in yyyy-mm-dd format (] . $self->get_datestamp . q[) or use 'today'];
		}
	}

	#make sure date fields really are dates in correct format
	if ( $thisfield->{'type'} eq 'date' && !BIGSdb::Utils::is_date($value) ) {
		return 'must be a valid date in yyyy-mm-dd format';
	}

	#Make sure id number has not been used previously
	if ( $flag && $flag eq 'insert' && ( $fieldname eq 'id' ) ) {
		my $exists =
		  $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)",
			$value, { cache => 'CuratePage::is_field_bad_isolates::id_exists' } );
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
	foreach my $att (@$attributes) {
		if ( $att->{'name'} eq $fieldname ) {
			$thisfield = $att;
			last;
		}
	}
	$thisfield->{'type'} ||= 'text';

	#If field is null make sure it's not a required field
	if ( !defined $value || $value eq '' ) {
		if ( !$thisfield->{'required'} || $thisfield->{'required'} ne 'yes' ) {
			return 0;
		} else {
			my $msg = 'is a required field and cannot be left blank.';
			if ( $thisfield->{'optlist'} ) {
				my @optlist = split /;/x, $thisfield->{'optlist'};
				local $" = q(', ');
				$msg .= " Allowed values are '@optlist'.";
			}
			return $msg;
		}
	}

	#Make sure curator is set right
	if ( $fieldname eq 'curator' && $value ne $self->get_curator_id ) {
		return 'must be set to the currently logged in curator id (' . $self->get_curator_id . ').';
	}

	#Make sure int fields really are integers
	if ( $thisfield->{'type'} eq 'int' && !BIGSdb::Utils::is_int($value) ) {
		return 'must be an integer';
	}

	#Make sure sender is in database
	if ( $fieldname eq 'sender' or $fieldname eq 'sequenced_by' ) {
		my $qry = 'SELECT DISTINCT id FROM users';
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute };
		$logger->error($@) if $@;
		while ( my ($senderid) = $sql->fetchrow_array ) {
			if ( $value == $senderid ) {
				return 0;
			}
		}
		return qq(is not in the database users table - see <a href="$self->{'system'}->{'script_name'}?)
		  . qq(db=$self->{'instance'}&amp;page=fieldValues&amp;field=f_sender">list of values</a>);
	}

	#If a regex pattern exists, make sure data conforms to it
	if ( $thisfield->{'regex'} ) {
		if ( $value !~ /^$thisfield->{regex}$/x ) {
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
		return q[must be today's date in yyyy-mm-dd format (] . $self->get_datestamp . q[) or use 'today'];
	}
	if ( $flag eq 'insert' ) {

		#Make sure the date_entered is today
		if ( $fieldname eq 'date_entered'
			&& ( $value ne $self->get_datestamp ) )
		{
			return q[must be today's date in yyyy-mm-dd format (] . $self->get_datestamp . q[) or use 'today'];
		}
	}
	if ( $flag eq 'insert'
		&& ( $thisfield->{'unique'} ) )
	{
		#Make sure unique field values have not been used previously
		my $qry = "SELECT DISTINCT $thisfield->{'name'} FROM $table";
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute };
		$logger->error($@) if $@;
		while ( my ($id) = $sql->fetchrow_array ) {
			if ( $value eq $id ) {
				if ( $thisfield->{'name'} =~ /sequence/ ) {
					$value = q(<span class="seq">) . ( BIGSdb::Utils::truncate_seq( \$value, 40 ) ) . q(</span>);
				}
				return qq('$value' is already in database);
			}
		}
	}

	#Make sure options list fields only use a listed option (or null if optional)
	if ( $thisfield->{'optlist'} ) {
		my @options = split /;/x, $thisfield->{'optlist'};
		foreach (@options) {
			if ( $value eq $_ ) {
				return 0;
			}
		}
		if ( $thisfield->{'required'} && $thisfield->{'required'} eq 'no' ) {
			return 0 if ( $value eq '' );
		}
		return qq('$value' is not on the list of allowed values for this field.);
	}

	#Make sure field is not too long
	if ( $thisfield->{length} && length($value) > $thisfield->{'length'} ) {
		return "field is too long (maximum length $thisfield->{'length'})";
	}

	#Make sure a foreign key value exists in foreign table
	if ( $thisfield->{'foreign_key'} ) {
		my $qry;
		if ( $fieldname eq 'isolate_id' ) {
			$qry = "SELECT EXISTS(SELECT * FROM $self->{'system'}->{'view'} WHERE id=?)";
		} else {
			$qry = "SELECT EXISTS(SELECT * FROM $thisfield->{'foreign_key'} WHERE id=?)";
		}
		$value = $self->map_locus_name($value) if $fieldname eq 'locus';
		my $exists =
		  $self->{'datastore'}->run_query( $qry, $value, { cache => "CuratePage::is_field_bad_other:$fieldname" } );
		if ( !$exists ) {
			if ( $thisfield->{'foreign_key'} eq 'isolates' && $self->{'system'}->{'view'} ne 'isolates' ) {
				return "value '$value' does not exist in isolates table or is not accessible to your account";
			}
			return "value '$value' does not exist in $thisfield->{'foreign_key'} table";
		}
	}
	return 0;
}

sub clean_value {
	my ( $self, $value, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	$value =~ s/'/\\'/gx if !$options->{'no_escape'};
	$value =~ s/\r//gx;
	$value =~ s/\n/ /gx;
	$value =~ s/^\s*//x;
	$value =~ s/\s*$//x;
	return $value;
}

sub map_locus_name {
	my ( $self, $locus ) = @_;
	my $set_id = $self->get_set_id;
	return $locus if !$set_id;
	my $locus_list = $self->{'datastore'}->run_query(
		'SELECT locus FROM set_loci WHERE (set_id,set_name)=(?,?)',
		[ $set_id, $locus ],
		{ fetch => 'col_arrayref' }
	);
	return $locus if @$locus_list != 1;
	return $locus_list->[0];
}

sub update_history {
	my ( $self, $isolate_id, $action ) = @_;
	return if !$action || !$isolate_id;
	my $curator_id = $self->get_curator_id;
	if ( !$self->{'sql'}->{'CuratePage::update_history'} ) {
		$self->{'sql'}->{'CuratePage::update_history'} =
		  $self->{'db'}->prepare('INSERT INTO history (isolate_id,timestamp,action,curator) VALUES (?,?,?,?)');
	}
	if ( !$self->{'sql'}->{'CuratePage::update_history_time'} ) {
		$self->{'sql'}->{'CuratePage::update_history_time'} =
		  $self->{'db'}->prepare('UPDATE isolates SET (datestamp,curator) = (?,?) WHERE id=?');
	}
	eval {
		$self->{'sql'}->{'CuratePage::update_history'}->execute( $isolate_id, 'now', $action, $curator_id );
		$self->{'sql'}->{'CuratePage::update_history_time'}->execute( 'now', $curator_id, $isolate_id );
	};
	if ($@) {
		$logger->error("Can't update history for isolate $isolate_id '$action' $@");
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
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
			my $view_exists =
			  $self->{'datastore'}
			  ->run_query( 'SELECT EXISTS(SELECT * FROM matviews WHERE v_name=?)', "scheme_$scheme_id" );
			$self->{'db'}->do("SELECT drop_matview('mv_scheme_$scheme_id')") if $view_exists;
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
	my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
	return if !@$loci || !@$fields;    #No point creating view if table doesn't have either loci or fields.
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	return if !$scheme_info->{'primary_key'};    #No point creating view without a primary key.
	my $qry = "CREATE OR REPLACE VIEW scheme_$scheme_id AS SELECT profiles.profile_id AS "
	  . "$scheme_info->{'primary_key'},profiles.sender,profiles.curator,profiles.date_entered,profiles.datestamp";

	foreach (@$fields) {
		$qry .= ",$_.value AS $_" if $_ ne $scheme_info->{'primary_key'};
	}
	foreach (@$loci) {
		( my $cleaned = $_ ) =~ s/'/_PRIME_/gx;
		$qry .= ",$cleaned.allele_id AS $cleaned";
	}
	$qry .= ' FROM profiles';
	foreach (@$loci) {
		( my $cleaned  = $_ ) =~ s/'/_PRIME_/gx;
		( my $cleaned2 = $_ ) =~ s/'/\\'/gx;
		$qry .= " INNER JOIN profile_members AS $cleaned ON profiles.profile_id=$cleaned.profile_id AND "
		  . "$cleaned.locus=E'$cleaned2' AND profiles.scheme_id=$cleaned.scheme_id";
	}
	foreach (@$fields) {
		next if $_ eq $scheme_info->{'primary_key'};
		$qry .= " LEFT JOIN profile_fields AS $_ ON profiles.profile_id=$_.profile_id AND $_.scheme_field=E'$_' AND "
		  . "profiles.scheme_id=$_.scheme_id";
	}
	$qry .= " WHERE profiles.scheme_id = $scheme_id";
	eval {
		$self->{'db'}->do($qry);
		$self->{'db'}->do("GRANT SELECT ON scheme_$scheme_id TO $self->{'system'}->{'user'}");
		if ( ( $self->{'system'}->{'materialized_views'} // '' ) eq 'yes' ) {
			$self->{'db'}->do("SELECT create_matview('mv_scheme_$scheme_id', 'scheme_$scheme_id')");
			$self->{'db'}
			  ->do("CREATE UNIQUE INDEX i_mv$scheme_id\_1 ON mv_scheme_$scheme_id ($scheme_info->{'primary_key'})");
			$self->_create_mv_indexes( $scheme_id, $fields, $loci );
		}
	};
	$logger->error($@) if $@;
	return;
}

sub refresh_material_view {

	#Needs to be committed outside of subroutine (to allow refresh as part of transaction)
	my ( $self, $scheme_id ) = @_;
	return if !( ( $self->{'system'}->{'materialized_views'} // '' ) eq 'yes' );
	my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
	return if !@$loci || !@$fields;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	return if !$scheme_info->{'primary_key'};    #No point creating view without a primary key.
	eval { $self->{'db'}->do("SELECT refresh_matview('mv_scheme_$scheme_id')"); };
	$logger->error($@) if $@;
	return;
}

sub _create_mv_indexes {
	my ( $self, $scheme_id, $fields, $loci ) = @_;

	#We don't need to index every loci.  The first three will do.
	my $i = 0;
	foreach my $locus (@$loci) {
		$i++;
		$locus =~ s/'/_PRIME_/gx;
		eval { $self->{'db'}->do("CREATE INDEX i_mv$scheme_id\_$locus ON mv_scheme_$scheme_id ($locus)"); };
		$logger->warn("Can't create index $@") if $@;
		last if $i == 3;
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	foreach my $field (@$fields) {
		next if $field eq $scheme_info->{'primary_key'};
		my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		if ( $scheme_field_info->{'index'} ) {
			eval { $self->{'db'}->do("CREATE INDEX i_mv$scheme_id\_$field ON mv_scheme_$scheme_id ($field)") };
			$logger->warn("Can't create index $@") if $@;
		}
	}
	return;
}
1;
