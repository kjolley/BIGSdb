#Written by Keith Jolley
#Copyright (c) 2010-2017, University of Oxford
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
use BIGSdb::Utils;
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(any);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Constants qw(SEQ_FLAGS ALLELE_FLAGS DATABANKS SCHEME_FLAGS);

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
		my $name = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		return $name ? "$name->{'first_name'} $name->{'surname'}" : 'unknown user';
	}
	return 'unknown user';
}

sub create_record_table {
	my ( $self, $table, $newdata, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	if ( ref $newdata ne 'HASH' ) {
		say q(<div class="box" id="statusbad"><p>Record doesn't exist.</p></div>);
		return q();
	} elsif ( defined $newdata->{'isolate_id'} && !BIGSdb::Utils::is_int( $newdata->{'isolate_id'} ) ) {
		say q(<div class="box" id="statusbad"><p>Invalid isolate_id submitted.</p></div>);
		return q();
	} elsif ( defined $newdata->{'isolate_id'}
		&& $table ne 'retired_isolates'
		&& !$self->is_allowed_to_view_isolate( $newdata->{'isolate_id'} ) )
	{
		say q(<div class="box" id="statusbad"><p>Your account is not allowed to modify values for isolate )
		  . qq(id-$newdata->{'isolate_id'}.</p></div>);
		return q();
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
		loci         => '_create_extra_fields_for_loci',
		schemes      => '_create_extra_fields_for_schemes',
		users        => '_create_extra_fields_for_users'
	);

	if ( $methods{$table} ) {
		my $method = $methods{$table};
		$buffer .= $self->$method( $newdata, $width, $options );
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

sub _get_form_fields {
	my ( $self, $attributes, $table, $newdata_ref, $options, $width ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $q = $self->{'cgi'};
	my %disabled = $options->{'disabled'} ? map { $_ => 1 } @{ $options->{'disabled'} } : ();
	$self->populate_submission_params;
	my $buffer = q();
	foreach my $required (qw(1 0)) {
	  FIELD: foreach my $att (@$attributes) {
			next FIELD if $att->{'hide_in_form'};
			next FIELD if ( any { $att->{'name'} eq $_ } @{ $options->{'noshow'} } );
			my $html5_args = $self->_get_html5_args($att);
			next FIELD if !$self->_show_field( $required, $att );
			my $name = $options->{'prepend_table_name'} ? "$table\_$att->{'name'}" : $att->{'name'};
			my $length = $att->{'length'} || ( $att->{'type'} eq 'int' ? 15 : 50 );
			my $args = {
				table      => $table,
				newdata    => $newdata_ref,
				name       => $name,
				att        => $att,
				options    => $options,
				width      => $width,
				length     => $length,
				html5_args => $html5_args,
				disabled   => $disabled{ $att->{'name'} }
			};
			my $label = $self->_get_label($args);
			$buffer .= qq(<li>$label);
			my %field_checks = (
				primary_key    => sub { $self->_get_primary_key_field($args) },
				no_user_update => sub { $self->_get_no_update_field($args) },
				sender         => sub { $self->_get_user_field($args) },
				allele_id      => sub { $self->_get_allele_id_field($args) },
				non_admin_loci => sub { $self->_get_non_admin_locus_field($args) },
				foreign_key    => sub { $self->_get_foreign_key_dropdown_field($args) },
				datestamp      => sub { $self->_get_datestamp_field($args) },
				date_entered   => sub { $self->_get_date_entered_field($args) },
				curator        => sub { $self->_get_curator_field($args) },
				boolean        => sub { $self->_get_boolean_field($args) },
				optlist        => sub { $self->_get_optlist_field($args) },
				text_field     => sub { $self->_get_text_field($args) },
			);
		  FIELD_CHECK: foreach my $check (
				qw(primary_key no_user_update sender allele_id non_admin_loci
				foreign_key datestamp date_entered curator boolean optlist text_field)
			  )
			{
				my $check_buffer = $field_checks{$check}->();
				$buffer .= $check_buffer;
				if ($check_buffer) {
					$buffer .= $self->_show_tooltip($args);
					next FIELD;
				}
			}
			$buffer .= qq(</li>\n);
		}
	}
	return $buffer;
}

sub _show_field {
	my ( $self, $showing_required, $att ) = @_;
	if (   ( $att->{'required'} && $showing_required )
		|| ( !$att->{'required'} && !$showing_required ) )
	{
		return 1;
	}
	return;
}

sub _get_label {
	my ( $self, $args ) = @_;
	my ( $newdata, $name, $att, $options, $width ) = @$args{qw(newdata name att options width)};
	( my $cleaned_name = $att->{name} ) =~ tr/_/ /;
	my ( $label, $title ) = $self->get_truncated_label( $cleaned_name, 24 );
	my $title_attribute = $title ? qq( title="$title") : q();

	#Associate label with form element (element has to exist)
	my %auto_field = map { $_ => 1 } qw (curator date_entered datestamp);
	my $for =
	    !$auto_field{ $att->{'name'} }
	  && $att->{'type'} ne 'bool'
	  && !(( $options->{'update'} && $att->{'primary_key'} )
		|| ( $options->{'newdata_readonly'} && $newdata->{ $att->{'name'} } ) )
	  ? qq( for="$name")
	  : q();
	my $buffer = qq(<label$for class="form" style="width:${width}em"$title_attribute>);
	$buffer .= qq($label:);
	$buffer .= q(!) if $att->{'required'};
	$buffer .= q(</label>);
	return $buffer;
}

#Client side form validation for required fields and integer values
sub _get_html5_args {
	my ( $self, $att ) = @_;
	my %html5_args;
	$html5_args{'required'} = 'required' if $att->{'required'};
	if ( !$att->{'dropdown_query'} && !$att->{'optlist'} ) {
		if ( $att->{'type'} eq 'int' && !$att->{'dropdown_query'} && !$att->{'optlist'} ) {
			@html5_args{qw(type min step)} = qw(number 0 1);
		}
		if ( $att->{'type'} eq 'float' ) {
			@html5_args{qw(type min step)} = qw(number 0 any);
		}
	}
	return \%html5_args;
}

sub _get_primary_key_field {
	my ( $self, $args ) = @_;
	my ( $table, $name, $newdata, $att, $options ) = @$args{qw(table name newdata att options)};
	return q()
	  if !(( $options->{'update'} && $att->{'primary_key'} )
		|| ( $options->{'newdata_readonly'} && $newdata->{ $att->{'name'} } ) );
	my $q = $self->{'cgi'};
	my $desc;
	if (
		!$self->{'curate'}
		&& (   ( $att->{'name'} eq 'locus' && $table ne 'set_loci' )
			|| ( $table eq 'loci' && $att->{'name'} eq 'id' ) )
	  )
	{
		$desc = $self->clean_locus( $newdata->{ $att->{'name'} } );
	} elsif ( $att->{'labels'} ) {
		$desc = $self->_get_foreign_key_label( $name, $newdata, $att );
	} elsif ( $att->{'user_field'} ) {
		$desc = $self->{'datastore'}->get_user_string( $newdata->{ $att->{'name'} } );
	} else {
		( $desc = $newdata->{ $att->{'name'} } ) =~ tr/_/ /;
	}
	my $buffer = "<b>$desc";
	if ( $table eq 'samples' && $att->{'name'} eq 'isolate_id' ) {
		$buffer .= ') ' . $self->get_isolate_name_from_id( $newdata->{ $att->{'name'} } );
	}
	$buffer .= '</b>';
	$buffer .= $q->hidden( $name, $newdata->{ $att->{'name'} } );
	return $buffer;
}

sub _get_no_update_field {
	my ( $self,    $args ) = @_;
	my ( $newdata, $att )  = @$args{qw(newdata att)};
	my $q = $self->{'cgi'};
	return q() if !( $q->param('page') eq 'update' && $att->{'no_user_update'} );
	my $buffer = qq(<span id="$att->{'name'}">\n);
	if ( $att->{'name'} eq 'sequence' ) {
		my $data_length = length( $newdata->{ $att->{'name'} } );
		if ( $data_length > 5000 ) {
			$buffer .=
			    q[<span class="seq"><b>]
			  . BIGSdb::Utils::truncate_seq( \$newdata->{ $att->{'name'} }, 40 )
			  . qq[</b></span><br />sequence is $data_length characters (too long to display)];
		} else {
			$buffer .= $q->textarea(
				-name     => $att->{'name'},
				-rows     => 6,
				-cols     => 40,
				-disabled => 'disabled',
				-default  => BIGSdb::Utils::split_line( $newdata->{ $att->{'name'} } )
			);
		}
	} else {
		$buffer .= qq(<b>$newdata->{$att->{'name'}}</b>);
	}
	$buffer .= qq(</span>\n);
	return $buffer;
}

sub _get_user_field {
	my ( $self, $args ) = @_;
	my ( $name, $newdata, $att, $html5_args ) = @$args{qw(name newdata att html5_args)};
	return q() if $att->{'name'} ne 'sender' && !$att->{'user_field'};
	my ( $users, $user_names ) = $self->{'datastore'}->get_users( { curators => $att->{'is_curator_only'} } );
	my $q = $self->{'cgi'};
	return $q->popup_menu(
		-name    => $name,
		-id      => $name,
		-values  => [ '', @$users ],
		-labels  => $user_names,
		-default => $newdata->{ $att->{'name'} },
		%$html5_args
	);
}

sub _get_allele_id_field {
	my ( $self, $args ) = @_;
	my ( $table, $name, $newdata, $att, $length, $html5_args ) = @$args{qw(table name newdata att length html5_args)};
	my $q = $self->{'cgi'};
	return q() if !( $table eq 'sequences' && $att->{'name'} eq 'allele_id' && $q->param('locus') );
	my $locus_info = $self->{'datastore'}->get_locus_info( $q->param('locus') );
	if ( $locus_info->{'allele_id_format'} eq 'integer' ) {
		my $default = $q->param('allele_id') // $self->{'datastore'}->get_next_allele_id( $q->param('locus') );
		return $self->textfield(
			name      => $name,
			id        => $name,
			size      => $length,
			maxlength => $length,
			value     => $default,
			%$html5_args
		);
	} else {
		return $self->textfield(
			name      => $name,
			id        => $name,
			size      => $length,
			maxlength => $length,
			value     => $newdata->{ $att->{'name'} },
			%$html5_args
		);
	}
}

sub _get_non_admin_locus_field {
	my ( $self, $args ) = @_;
	my ( $table, $name, $newdata, $att, $html5_args ) = @$args{qw(table name newdata att html5_args)};
	my %seq_table = map { $_ => 1 } qw(sequences retired_allele_ids sequence_refs accession locus_descriptions);
	return q() if !( $seq_table{$table} && $att->{'name'} eq 'locus' && !$self->is_admin );
	my $set_id = $self->get_set_id;
	my ( $values, $desc ) =
	  $self->{'datastore'}
	  ->get_locus_list( { set_id => $set_id, no_list_by_common_name => 1, locus_curator => $self->get_curator_id } );
	$values = [] if ref $values ne 'ARRAY';
	my $q = $self->{'cgi'};
	return $q->popup_menu(
		-name    => $name,
		-id      => $name,
		-values  => [ '', @$values ],
		-labels  => $desc,
		-default => $newdata->{ $att->{'name'} },
		%$html5_args
	);
}

sub _get_foreign_key_dropdown_field {
	my ( $self, $args ) = @_;
	my ( $table, $name, $newdata, $att, $html5_args ) = @$args{qw(table name newdata att html5_args)};
	return q() if !( $att->{'dropdown_query'} && $att->{'foreign_key'} );
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
		$qry = q(SELECT id FROM users WHERE id>0 );
		$qry .= q(AND status!='user' ) if $att->{'is_curator_only'};
		$qry .= qq(ORDER BY @fields_to_query);
		$values = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	} elsif ( $att->{'foreign_key'} eq 'loci' && $table ne 'set_loci' && $set_id ) {
		( $values, $desc ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id, no_list_by_common_name => 1 } );
	} elsif ( $att->{'foreign_key'} eq 'schemes' && $table ne 'set_schemes' ) {
		my $scheme_list =
		  $self->{'datastore'}->get_scheme_list( { set_id => $set_id, with_pk => $att->{'with_pk_only'} } );
		foreach my $scheme (@$scheme_list) {
			if ( $att->{'is_curator_only'} && !$self->is_admin ) {
				my $curator_id = $self->get_curator_id;
				my $is_curator = $self->{'datastore'}->is_scheme_curator( $scheme->{'id'}, $curator_id );
				push @$values, $scheme->{'id'} if $is_curator;
			} else {
				push @$values, $scheme->{'id'};
			}
		}
	} else {
		local $" = ',';
		$qry = "SELECT id FROM $att->{'foreign_key'} ORDER BY @fields_to_query";
		$values = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
	}
	$values = [] if ref $values ne 'ARRAY';
	my $q = $self->{'cgi'};
	return $q->popup_menu(
		-name    => $name,
		-id      => $name,
		-values  => [ '', @$values ],
		-labels  => $desc,
		-default => $newdata->{ $att->{'name'} },
		%$html5_args
	);
}

sub _get_datestamp_field {
	my ( $self, $args ) = @_;
	my ($att) = @$args{qw(att)};
	return q() if $att->{'name'} ne 'datestamp';
	my $datestamp = BIGSdb::Utils::get_datestamp();
	return qq(<b>$datestamp</b>\n);
}

sub _get_date_entered_field {
	my ( $self,    $args ) = @_;
	my ( $newdata, $att )  = @$args{qw(newdata att)};
	return q() if $att->{'name'} ne 'date_entered';
	my $q = $self->{'cgi'};
	if ( $q->param('page') eq 'update' or $q->param('page') eq 'alleleUpdate' ) {
		return qq(<b>$newdata->{ $att->{'name'} }</b>\n);
	} else {
		my $datestamp = BIGSdb::Utils::get_datestamp();
		return qq(<b>$datestamp</b>\n);
	}
}

sub _get_curator_field {
	my ( $self, $args ) = @_;
	my ($att) = @$args{qw(att)};
	return q() if $att->{'name'} ne 'curator';
	my $name = $self->get_curator_name;
	return qq(<b>$name ($self->{'username'})</b>\n);
}

sub _get_optlist_field {
	my ( $self, $args ) = @_;
	my ( $name, $newdata, $att, $options, $html5_args ) = @$args{qw(name newdata att options html5_args)};
	return q() if !$att->{'optlist'};
	my @optlist;
	if ( $att->{'optlist'} eq 'isolate_fields' ) {
		@optlist = @{ $self->{'xmlHandler'}->get_field_list() };
	} else {
		@optlist = split /;/x, $att->{'optlist'};
	}
	unshift @optlist, '';
	my $labels = { '' => ' ' };    #Required for HTML5 validation
	my $q = $self->{'cgi'};
	return $q->popup_menu(
		-name    => $name,
		-id      => $name,
		-values  => [@optlist],
		-default => $options->{'update'} ? $newdata->{ $att->{'name'} } : $att->{'default'},
		-labels  => $labels,
		%$html5_args
	);
}

sub _get_text_field {
	my ( $self, $args ) = @_;
	my ( $name, $length, $newdata, $att, $options, $html5_args ) =
	  @$args{qw(name length newdata att options html5_args)};
	my $q = $self->{'cgi'};
	my %disabled = $args->{'disabled'} ? ( disabled => 'disabled' ) : ();
	if ( $length >= 256 ) {
		$newdata->{ $att->{'name'} } = BIGSdb::Utils::split_line( $newdata->{ $att->{'name'} } )
		  if $att->{'name'} eq 'sequence';
		return $q->textarea(
			-name    => $name,
			-id      => $name,
			-rows    => 6,
			-cols    => 75,
			-default => $newdata->{ $att->{'name'} },
			%disabled,
			%$html5_args
		);
	} elsif ( $length >= 120 ) {
		$newdata->{ $att->{'name'} } = BIGSdb::Utils::split_line( $newdata->{ $att->{'name'} } )
		  if $att->{'name'} eq 'sequence';
		return $q->textarea(
			-name    => $name,
			-id      => $name,
			-rows    => 3,
			-cols    => 75,
			-default => $newdata->{ $att->{'name'} },
			%disabled,
			%$html5_args
		);
	} else {
		return $self->textfield(
			name      => $name,
			id        => $name,
			size      => ( $length > 75 ? 75 : $length ),
			maxlength => $length,
			value     => $newdata->{ $att->{'name'} },
			%disabled,
			%$html5_args
		);
	}
}

sub _show_tooltip {
	my ( $self, $args ) = @_;
	my ( $name, $att )  = @$args{qw(name att)};
	my $buffer = q();
	if ( $att->{'tooltip'} ) {
		$buffer .= qq(&nbsp;<a class="tooltip" title="$att->{'tooltip'}"><span class="fa fa-info-circle"></span></a>);
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
	my ( $self, $args ) = @_;
	my ( $name, $newdata, $att ) = @$args{qw(name newdata att)};
	return q() if $att->{'type'} ne 'bool';
	my $q = $self->{'cgi'};
	my $default;
	if ( $q->param('page') eq 'update' && ( $newdata->{ $att->{'name'} } // '' ) ne '' ) {
		$default = $newdata->{ $att->{'name'} } ? 'true' : 'false';
	} else {
		$default = $newdata->{ $att->{'name'} };
	}
	$default //= '-';
	local $" = ' ';
	return $q->radio_group( -name => $name, -values => [qw (true false)], -default => $default );
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
			my $args = {
				format     => $format,
				optlist    => $optlist,
				newdata    => $newdata,
				field      => $field,
				length     => $length,
				html5_args => \%html5_args
			};
			my %field_checks = (
				boolean => sub { $self->_get_extra_seq_field_boolean($args) },
				optlist => sub { $self->_get_extra_seq_field_optlist($args) },
				text    => sub { $self->_get_extra_seq_field_text($args) }
			);
		  FIELD_CHECK: foreach my $check (qw(boolean optlist text)) {
				my $check_buffer = $field_checks{$check}->();
				$buffer .= $check_buffer;
				last FIELD_CHECK if $check_buffer;
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

sub _get_extra_seq_field_boolean {
	my ( $self, $args ) = @_;
	my ( $format, $newdata, $field, $html5_args ) = @$args{qw(format newdata field html5_args)};
	return q() if $format ne 'boolean';
	my $q = $self->{'cgi'};
	return $q->radio_group(
		-name    => $field,
		-values  => [qw (true false)],
		-default => $newdata->{$field} // '-',
		%$html5_args
	);
}

sub _get_extra_seq_field_optlist {
	my ( $self, $args ) = @_;
	my ( $optlist, $newdata, $field, $html5_args ) = @$args{qw(optlist newdata field html5_args)};
	return q() if !$optlist;
	my @options = split /\|/x, $optlist;
	unshift @options, '';
	my $q = $self->{'cgi'};
	return $q->popup_menu(
		-name    => $field,
		-id      => $field,
		-values  => \@options,
		-default => $newdata->{$field},
		%$html5_args
	);
}

sub _get_extra_seq_field_text {
	my ( $self, $args ) = @_;
	my ( $newdata, $field, $html5_args, $length ) = @$args{qw( newdata field html5_args length)};
	my $q = $self->{'cgi'};
	if ( $length > 256 ) {
		return $q->textarea(
			-name    => $field,
			-id      => $field,
			-rows    => 6,
			-cols    => 70,
			-default => $newdata->{$field},
			%$html5_args
		);
	} elsif ( $length > 60 ) {
		return $q->textarea(
			-name    => $field,
			-id      => $field,
			-rows    => 3,
			-cols    => 70,
			-default => $newdata->{$field},
			%$html5_args
		);
	} else {
		return $self->textfield(
			name      => $field,
			id        => $field,
			size      => $length,
			maxlength => $length,
			value     => $newdata->{$field},
			%$html5_args
		);
	}
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

sub _create_extra_fields_for_schemes {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $newdata_ref, $width ) = @_;
	my $q = $self->{'cgi'};
	my $current_flags;
	my ( $current_refs, $current_links ) = ( [], [] );
	if ( $q->param('page') eq 'update' ) {
		$current_flags =
		  $self->{'datastore'}->run_query( 'SELECT flag FROM scheme_flags WHERE scheme_id=? ORDER BY flag',
			$newdata_ref->{'id'}, { fetch => 'col_arrayref' } );
		$current_refs =
		  $self->{'datastore'}->run_query( 'SELECT pubmed_id FROM scheme_refs WHERE scheme_id=? ORDER BY pubmed_id',
			$newdata_ref->{'id'}, { fetch => 'col_arrayref' } );
		my $links =
		  $self->{'datastore'}
		  ->run_query( 'SELECT url,description FROM scheme_links WHERE scheme_id=? ORDER BY link_order',
			$newdata_ref->{'id'}, { fetch => 'all_arrayref', slice => {} } );
		foreach my $link_data (@$links) {
			push @$current_links, "$link_data->{'url'}|$link_data->{'description'}";
		}
	}
	my $buffer = qq(<li><label for="flags" class="form" style="width:${width}em">flags:</label>\n);
	$buffer .= $q->scrolling_list(
		-name     => 'flags',
		-id       => 'flags',
		-values   => [SCHEME_FLAGS],
		-multiple => 'multiple',
		-default  => $current_flags
	);
	$buffer .= q( <span class="comment">Use CTRL/SHIFT click to select or deselect values</span></li>);
	$buffer .= qq(<li><label for="pubmed" class="form" style="width:${width}em">PubMed ids:&nbsp;</label>);
	local $" = qq(\n);
	$buffer .=
	  $q->textarea( -name => 'pubmed', -id => 'pubmed', -rows => 2, -cols => 12, -default => "@$current_refs" );
	$buffer .= qq(</li>\n);
	$buffer .= qq[<li><label for="links" class="form" style="width:${width}em">links: <br /><span class="comment">]
	  . q[(Format: URL|description)</span></label>];
	$buffer .= $q->textarea( -name => 'links', -id => 'links', -rows => 3, -cols => 40, -default => "@$current_links" );
	$buffer .= qq(</li>\n);
	return $buffer;
}

sub _create_extra_fields_for_users {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $newdata, $width, $options ) = @_;
	my $q = $self->{'cgi'};
	my $buffer = $self->_get_user_site_db_field( $newdata, $width, $options );
	$buffer .= $self->_get_user_quota_field( $newdata, $width, $options );
	return $buffer;
}

sub _get_user_site_db_field {
	my ( $self, $newdata, $width, $options ) = @_;
	my $user_dbs = $self->{'datastore'}->run_query( 'SELECT id,name FROM user_dbases ORDER BY list_order,name',
		undef, { fetch => 'all_arrayref', slice => {} } );
	return q() if !@$user_dbs;
	return q() if !$options->{'update'} && !$self->{'permissions'}->{'modify_site_users'};
	my $q      = $self->{'cgi'};
	my $ids    = [];
	my $labels = {};
	my $default_db;

	foreach my $db (@$user_dbs) {
		$default_db = $db->{'id'} if !defined $default_db;
		push @$ids, $db->{'id'};
		$labels->{ $db->{'id'} } = $db->{'name'};
	}
	push @$ids, 0;
	my %disabled_field = $options->{'disabled'} ? map { $_ => 1 } @{ $options->{'disabled'} } : ();
	my %disabled = $disabled_field{'user_db'} ? ( disabled => 'disabled' ) : ();
	$labels->{0} = 'this database only';
	if ( $options->{'update'} ) {
		$newdata->{'user_db'} //= 0;
	}
	my $default = $newdata->{'user_db'} // $default_db;
	my $buffer = qq(<li><label for="user_db" class="form" style="width:${width}em">site/domain:</label>\n);
	$buffer .= $q->popup_menu(
		-name    => 'user_db',
		-id      => 'user_db',
		-values  => $ids,
		-labels  => $labels,
		-default => $default,
		%disabled
	);
	$buffer .= qq(</li>\n);
	return $buffer;
}

sub _get_user_quota_field {
	my ( $self, $newdata, $width, $options ) = @_;
	return q() if $self->{'system'}->{'dbtype'} ne 'isolates';
	my $q = $self->{'cgi'};
	if ( $options->{'update'} ) {
		if ( $newdata->{'status'} eq 'user' ) {
			$newdata->{'quota'} = 0;
		} else {
			my $current_quota =
			  $self->{'datastore'}->run_query( 'SELECT value FROM user_limits WHERE (user_id,attribute)=(?,?)',
				[ $newdata->{'id'}, 'private_isolates' ] );
			$newdata->{'quota'} = $current_quota // $self->{'system'}->{'default_private_records'} // 0;
		}
	} else {
		$newdata->{'quota'} = $q->param('quota') // $self->{'system'}->{'default_private_records'} // 0;
	}
	my $buffer = qq(<li><label for="quota" class="form" style="width:${width}em">private quota:</label>\n);
	$buffer .= $self->textfield(
		-name  => 'quota',
		-id    => 'quota',
		-style => 'width:6em',
		-value => $newdata->{'quota'},
		-type  => 'number',
		-min   => 0
	);
	$buffer .= q( <span class="comment">User must be either a submitter, curator, )
	  . q(or admin to upload private records</span>);
	return $buffer;
}

sub check_record {
	my ( $self, $table, $newdata, $update, $allowed_values ) = @_;

	#TODO prevent scheme group belonging to a child
	#TODO check optlist values
	my $record_name = $self->get_record_name($table);
	my $q           = $self->{'cgi'};
	my ( @problems, @missing );
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	my @primary_key_query;
  ATT: foreach my $att (@$attributes) {
		next if $update && $att->{'no_user_update'};
		if ( $att->{'name'} =~ /sequence$/x ) {
			$newdata->{ $att->{'name'} } = uc( $newdata->{ $att->{'name'} } // '' );
			$newdata->{ $att->{'name'} } =~ s/\s//gx;
		}
		if ( $att->{'primary_key'} ) {
			( my $cleaned_name = $newdata->{ $att->{name} } ) =~ s/'/\\'/gx;
			push @primary_key_query, "$att->{name} = E'$cleaned_name'";
		}
		if ( $self->_check_is_missing( $att, $newdata ) ) {
			push @missing, $att->{'name'};
			next ATT;
		}
		my @checks = qw(integer float date regex foreign_key);
		foreach my $check (@checks) {
			my $method = "_check_$check";
			my $message = $self->$method( $att, $newdata );
			if ($message) {
				push @problems, $message;
				next ATT;
			}
		}
		my $message = $self->_check_unique( $att, $newdata, $table, $update, $allowed_values );
		if ($message) {
			push @problems, $message;
			next ATT;
		}
		my @table_field_checks = (
			{
				table  => 'allele_designations',
				field  => 'allele_id',
				method => sub { $self->_check_allele_designations_allele_id( $att, $newdata ) }
			},
			{
				table  => 'isolate_field_extended_attributes',
				field  => 'attribute',
				method => sub {
					$self->_check_isolate_field_extended_attributes( $att, $newdata );
				  }
			},
			{
				table  => 'isolate_value_extended_attributes',
				field  => 'value',
				method => sub {
					$self->_check_isolate_field_extended_attribute_value( $att, $newdata );
				  }
			},
			{
				table  => 'users',
				field  => 'status',
				method => sub {
					$self->_check_users_status( $att, $newdata, $update );
				  }
			},
			{
				table  => 'isolate_value_extended_attributes',
				field  => 'attribute',
				method => sub {
					$self->_check_isolate_field_extended_attribute_name( $att, $newdata );
				  }
			},
			{
				table  => 'retired_allele_ids',
				field  => 'allele_id',
				method => sub {
					$self->_check_retired_allele_id( $att, $newdata );
				  }
			}
		);
		foreach my $check (@table_field_checks) {
			if ( $table eq $check->{'table'} && $att->{'name'} eq $check->{'field'} ) {
				$message = $check->{'method'}->();
				if ($message) {
					push @problems, $message;
					next ATT;
				}
			}
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

sub _check_is_missing {
	my ( $self, $att, $newdata ) = @_;
	if ( $att->{'required'}
		&& ( !defined $newdata->{ $att->{'name'} } || $newdata->{ $att->{'name'} } eq '' ) )
	{
		return 1;
	}
	return;
}

sub _check_integer {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $att, $newdata ) = @_;
	if (   $newdata->{ $att->{'name'} }
		&& $att->{'type'} eq 'int'
		&& !BIGSdb::Utils::is_int( $newdata->{ $att->{'name'} } ) )
	{
		return "$att->{name} must be an integer.";
	}
	return;
}

sub _check_float {      ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $att, $newdata ) = @_;
	if (   $newdata->{ $att->{'name'} }
		&& $att->{'type'} eq 'float'
		&& !BIGSdb::Utils::is_float( $newdata->{ $att->{'name'} } ) )
	{
		return "$att->{name} must be a floating point number.";
	}
	return;
}

sub _check_date {       ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $att, $newdata ) = @_;
	if (   $newdata->{ $att->{'name'} }
		&& $att->{'type'} eq 'date'
		&& !BIGSdb::Utils::is_date( $newdata->{ $att->{'name'} } ) )
	{
		return "$newdata->{$att->{name}} must be in date format (yyyy-mm-dd).";
	}
	return;
}

sub _check_regex {      ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $att, $newdata ) = @_;
	if (   defined $newdata->{ $att->{'name'} }
		&& $newdata->{ $att->{'name'} } ne ''
		&& $att->{'regex'}
		&& $newdata->{ $att->{'name'} } !~ /$att->{'regex'}/x )
	{
		return "Field '$att->{name}' does not conform to specified format.";
	}
	return;
}

sub _check_foreign_key {    ## no critic (ProhibitUnusedPrivateSubroutines) #Called by dispatch table
	my ( $self, $att, $newdata ) = @_;
	return if !$att->{'foreign_key'};
	my $exists =
	  $self->{'datastore'}
	  ->run_query( "SELECT EXISTS(SELECT * FROM $att->{'foreign_key'} WHERE id=?)", $newdata->{ $att->{'name'} } );
	if ( !$exists ) {
		return "$att->{'name'} should refer to a record within the $att->{'foreign_key'} table, but it doesn't.";
	}
}

sub _check_unique {
	my ( $self, $att, $newdata, $table, $update, $allowed_values ) = @_;
	return if !$att->{'unique'};
	my $exists =
	  $self->{'datastore'}
	  ->run_query( "SELECT EXISTS(SELECT * FROM $table WHERE $att->{name} =?)", $newdata->{ $att->{'name'} } );
	if (   ( $update && $exists && $newdata->{ $att->{'name'} } ne $allowed_values->{ $att->{'name'} } )
		|| ( $exists && !$update ) )
	{
		return "A record already exists with $att->{'name'} = '$newdata->{$att->{'name'}}', "
		  . "please choose a different $att->{'name'}.";
	}
	return;
}

#Check for allele id format and regex which is defined in loci table
sub _check_allele_designations_allele_id {
	my ( $self, $att, $newdata ) = @_;
	my $format = $self->{'datastore'}->run_query( 'SELECT allele_id_format,allele_id_regex FROM loci WHERE id=?',
		$newdata->{'locus'}, { fetch => 'row_hashref' } );
	if ( $format->{'allele_id_format'} eq 'integer'
		&& !BIGSdb::Utils::is_int( $newdata->{ $att->{'name'} } ) )
	{
		return "$att->{'name'} must be an integer.";
	} elsif ( $format->{'allele_id_regex'}
		&& $newdata->{ $att->{'name'} } !~ /$format->{'allele_id_regex'}/x )
	{
		return "$att->{'name'} value is invalid - it must match the regular "
		  . "expression /$format->{'allele_id_regex'}/.";
	}
	return;
}

sub _check_isolate_field_extended_attributes {
	my ( $self, $att, $newdata ) = @_;
	if ( $newdata->{ $att->{'name'} } =~ /'/x ) {
		return 'Attribute contains invalid characters.';
	}
	return;
}

#Check for extended attribute value format and
#regex which is defined in isolate_field_extended_attributes table
sub _check_isolate_field_extended_attribute_value {
	my ( $self, $att, $newdata ) = @_;
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
		return "$att->{'name'} must be an integer.";
	} elsif ( $format->[1] && $newdata->{ $att->{'name'} } !~ /$format->[1]/x ) {
		return "$att->{'name'} value is invalid - it must match the regular expression /$format->[1]/.";
	} elsif ( $format->[2] && length( $newdata->{ $att->{'name'} } ) > $format->[2] ) {
		return "$att->{'name'} value is too long - it must be no longer than $format->[2] characters.";
	}
	return;
}

#Check that changing user status is allowed
sub _check_users_status {
	my ( $self, $att, $newdata, $update ) = @_;
	my $status = $self->{'datastore'}->run_query( 'SELECT status FROM users WHERE user_name=?', $self->{'username'} );
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
		return q(You must have admin rights to change the status of a user.);
	}
	if (   $status ne 'admin'
		&& $newdata->{'status'} ne 'admin'
		&& $user_status eq 'admin' )
	{
		return q(You must have admin rights to revoke admin status from another user.);
	}
	if (   $status ne 'admin'
		&& $newdata->{'status'} eq 'admin'
		&& $user_status ne 'admin'
		&& $update )
	{
		return q(You must have admin rights to upgrade a user to admin status.);
	}
	if (   $status ne 'admin'
		&& $newdata->{'status'} ne 'user'
		&& !$update )
	{
		return q(You must have admin rights to create a user with a status other than 'user'.);
	}
	if (   $status ne 'admin'
		&& defined $user_username
		&& defined $newdata->{'user_name'}
		&& $newdata->{'user_name'} ne $user_username
		&& $update )
	{
		return q(You must have admin rights to change the username of a user.);
	}
	return;
}

sub _check_isolate_field_extended_attribute_name {
	my ( $self, $att, $newdata ) = @_;
	my $attribute_exists =
	  $self->{'datastore'}->run_query(
		'SELECT EXISTS(SELECT * FROM isolate_field_extended_attributes WHERE (isolate_field,attribute)=(?,?))',
		[ $newdata->{'isolate_field'}, $newdata->{'attribute'} ] );
	if ( !$attribute_exists ) {
		my $fields = $self->{'datastore'}->run_query(
			'SELECT isolate_field FROM isolate_field_extended_attributes WHERE attribute=?',
			$newdata->{'attribute'},
			{ fetch => 'col_arrayref' }
		);
		my $message =
		  "Attribute $newdata->{'attribute'} has not been defined for the $newdata->{'isolate_field'} field.\n";
		if (@$fields) {
			local $" = ', ';
			$message .= " Fields with this attribute defined are: @$fields.";
		}
		return $message;
	}
	return;
}

sub _check_retired_allele_id {
	my ( $self, $att, $newdata ) = @_;
	my $exists =
	  $self->{'datastore'}->run_query( 'SELECT EXISTS (SELECT * FROM sequences WHERE (locus,allele_id)=(?,?))',
		[ $newdata->{'locus'}, $newdata->{'allele_id'} ] );
	if ($exists) {
		return 'This allele has already been defined - delete it before you retire the identifier.';
	}
	return;
}

sub format_data {
	my ( $self, $table, $data_ref ) = @_;
	if ( $table eq 'pcr' ) {
		$data_ref->{$_} =~ s/[\r\n]//gx foreach qw (primer1 primer2);
	}
	my $attributes = $self->{'datastore'}->get_table_field_attributes($table);
	foreach my $att (@$attributes) {
		next if !defined $data_ref->{ $att->{'name'} };
		if ( $att->{'name'} eq 'affiliation' ) {
			$data_ref->{ $att->{'name'} } =~ s/,?\s*\r?\n/, /gx;
			$data_ref->{ $att->{'name'} } =~ s/,(\S)/, $1/gx;
		}
		$data_ref->{ $att->{'name'} } = $self->clean_value( $data_ref->{ $att->{'name'} }, { no_escape => 1 } );
		if ( $att->{'name'} =~ /sequence$/x ) {
			$data_ref->{ $att->{'name'} } = uc( $data_ref->{ $att->{'name'} } );
			$data_ref->{ $att->{'name'} } =~ s/\s//gx;
		}
	}
	return;
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

#This should only be called once all databases accesses have completed.
sub update_blast_caches {
	my ($self) = @_;
	$self->{'update_blast_caches'} = 1;

	#Use double fork to prevent zombie processes on apache2-mpm-worker
	defined( my $kid = fork ) or $logger->error('cannot fork');
	if ($kid) {
		waitpid( $kid, 0 );
	} else {
		defined( my $grandkid = fork ) or $logger->error('Kid cannot fork');
		if ($grandkid) {
			CORE::exit(0);
		} else {
			open STDIN,  '<', '/dev/null' || $logger->error("Can't detach STDIN: $!");
			open STDOUT, '>', '/dev/null' || $logger->error("Can't detach STDOUT: $!");
			open STDERR, '>&STDOUT' || $logger->error("Can't detach STDERR: $!");
			BIGSdb::Offline::UpdateBlastCaches->new(
				{
					config_dir       => $self->{'config_dir'},
					lib_dir          => $self->{'lib_dir'},
					dbase_config_dir => $self->{'dbase_config_dir'},
					instance         => $self->{'instance'},
					options          => { q => 1 },
				}
			);
			CORE::exit(0);
		}
	}
	return;
}

sub get_form_icon {
	my ( $self, $table, $highlight ) = @_;
	my $icons = { users => 'fa-user', user_groups => 'fa-users', experiments => 'fa-flask' };
	my $highlight_class = {
		plus   => 'fa-plus form_icon_plus',
		edit   => 'fa-pencil form_icon_edit',
		trash  => 'fa-times form_icon_trash',
		import => 'fa-arrow-left form_icon_plus'
	};
	my $icon = $icons->{$table} // 'fa-file-text';
	my $bordered =
	    q(<span class="form_icon"><span class="fa-stack fa-3x">)
	  . qq(<span class="fa $icon fa-stack-2x form_icon_main"></span>)
	  . qq(<span class="fa $highlight_class->{$highlight} fa-stack-1x" style="left:0.5em;"></span></span></span>);
	return $bordered;
}
1;
