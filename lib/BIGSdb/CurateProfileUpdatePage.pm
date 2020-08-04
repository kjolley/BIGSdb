#Written by Keith Jolley
#Copyright (c) 2010-2020, University of Oxford
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
package BIGSdb::CurateProfileUpdatePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateProfileAddPage);
use BIGSdb::Utils;
use List::MoreUtils qw(none);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	say q(<h1>Update profile</h1>);
	my ( $scheme_id, $profile_id ) =
	  ( scalar $q->param('scheme_id'), scalar $q->param('profile_id') );
	if ( !$scheme_id ) {
		$self->print_bad_status( { message => q(No scheme_id passed.) } );
		return;
	}
	if ( !BIGSdb::Utils::is_int($scheme_id) ) {
		$self->print_bad_status( { message => q(Scheme_id must be an integer.) } );
		return;
	}
	if ( !$profile_id ) {
		$self->print_bad_status( { message => q(No profile_id passed.) } );
		return;
	}
	if ( !$self->can_modify_table('profiles') ) {
		$self->print_bad_status( { message => q(Your user account is not allowed to modify profiles.) } );
		return;
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	if ( !$primary_key ) {
		$self->print_bad_status( { message => q(This scheme doesn't have a primary key field defined.) } );
		return;
	}
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	if ( !@$loci ) {
		$self->print_bad_status(
			{
				message => q(This scheme doesn't have any loci belonging to it.  )
				  . q(Profiles can not be entered until there is at least one locus defined.)
			}
		);
		return;
	}
	my $profile_data = $self->{'datastore'}->run_query(
		'SELECT * FROM profiles WHERE scheme_id=? AND profile_id=?',
		[ $scheme_id, $profile_id ],
		{ fetch => 'row_hashref' }
	);
	if ( !$profile_data->{'profile_id'} ) {
		$self->print_bad_status(
			{
				message => qq(No profile from scheme $scheme_id )
				  . qq(($scheme_info->{'name'}) with the selected id exists.)
			}
		);
		return;
	}
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $allele_data;
	foreach my $locus (@$loci) {
		$allele_data->{$locus} = $self->{'datastore'}->run_query(
			'SELECT allele_id FROM profile_members WHERE (scheme_id,locus,profile_id)=(?,?,?)',
			[ $scheme_id, $locus, $profile_id ],
			{ cache => 'CurateProfileUpdatePage::print_content::alleles' }
		);
	}
	my $field_data;
	foreach my $field (@$scheme_fields) {
		$field_data->{$field} = $self->{'datastore'}->run_query(
			'SELECT value FROM profile_fields WHERE (scheme_id,scheme_field,profile_id)=(?,?,?)',
			[ $scheme_id, $field, $profile_id ],
			{ cache => 'CurateProfileUpdatePage::print_content::fields' }
		);
	}
	my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $args = {
		scheme_id    => $scheme_id,
		primary_key  => $primary_key,
		profile_id   => $profile_id,
		profile_data => $profile_data,
		field_data   => $field_data,
		allele_data  => $allele_data
	};
	if ( $q->param('sent') ) {
		$self->_update($args);
	}
	$self->_print_interface($args);
	return;
}

sub _prepare_update {
	my ( $self, $args ) = @_;
	my ( $scheme_id, $primary_key, $profile_id, $allele_data, $field_data, $profile_data ) =
	  @{$args}{qw(scheme_id primary_key profile_id allele_data field_data profile_data)};
	my %newdata;
	my @bad_field_buffer;
	my $update = 1;
	my ( %locus_changed, %field_changed );
	my $q               = $self->{'cgi'};
	my $loci            = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields   = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $profile_changed = 0;
	my $set_id          = $self->get_set_id;

	foreach my $locus (@$loci) {
		$newdata{"locus:$locus"} = $q->param("locus:$locus");
		$self->clean_field( \$newdata{"locus:$locus"} );
		my $field_bad = $self->is_locus_field_bad( $scheme_id, $locus, $newdata{"locus:$locus"} );
		push @bad_field_buffer, $field_bad if $field_bad;
		if ( $allele_data->{$locus} ne $newdata{"locus:$locus"} ) {
			$locus_changed{$locus} = 1;
			$profile_changed = 1;
		}
	}
	if ( !@bad_field_buffer && $profile_changed ) {
		$newdata{"field:$primary_key"} = $profile_id;
		my %designations = map { $_ => $newdata{"locus:$_"} } @$loci;
		my $ret = $self->{'datastore'}->check_new_profile( $scheme_id, \%designations, $newdata{"field:$primary_key"} );
		push @bad_field_buffer, $ret->{'msg'} if $ret->{'exists'} || $ret->{'err'};
	}
	foreach my $field (@$scheme_fields) {
		next if $field eq $primary_key;
		$newdata{"field:$field"} = $q->param("field:$field");
		$self->clean_field( \$newdata{"field:$field"} );
		my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		if (   $field_info->{'type'} eq 'integer'
			&& $newdata{"field:$field"} ne ''
			&& !BIGSdb::Utils::is_int( $newdata{"field:$field"} ) )
		{
			push @bad_field_buffer, "Field '$field' must be an integer.";
		}
		$field_data->{$field} = defined $field_data->{$field} ? $field_data->{$field} : '';
		if ( $field_data->{$field} ne $newdata{"field:$field"} ) {
			$field_changed{$field} = 1;
		}
	}
	$newdata{'field:sender'} = $q->param('field:sender');
	if ( !BIGSdb::Utils::is_int( $newdata{'field:sender'} ) ) {
		push @bad_field_buffer, q(Field 'sender' is invalid.);
	}
	if ( $profile_data->{'sender'} ne $newdata{'field:sender'} ) {
		$field_changed{'sender'} = 1;
	}
	my @extra_inserts;
	my $curator_id       = $self->get_curator_id;
	my $existing_pubmeds = $self->{'datastore'}->run_query(
		'SELECT pubmed_id FROM profile_refs WHERE (scheme_id,profile_id)=(?,?)',
		[ $scheme_id, $profile_id ],
		{ fetch => 'col_arrayref' }
	);
	my @new_pubmeds = split /\r?\n/x, $q->param('pubmed');
	my $pubmed_error = 0;
	my @updated_field;
	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !@$existing_pubmeds || none { $new eq $_ } @$existing_pubmeds ) {
			if ( !BIGSdb::Utils::is_int($new) ) {
				push @bad_field_buffer, 'PubMed ids must be integers.</p>' if !$pubmed_error;
				$pubmed_error = 1;
			}
			push @extra_inserts,
			  {
				statement => 'INSERT INTO profile_refs (scheme_id,profile_id,pubmed_id,curator,datestamp) '
				  . 'VALUES (?,?,?,?,?)',
				arguments => [ $scheme_id, $profile_id, $new, $curator_id, 'now' ]
			  };
			push @updated_field, "new reference: 'Pubmed#$new'";
		}
	}
	foreach my $existing (@$existing_pubmeds) {
		if ( !@new_pubmeds || none { $existing eq $_ } @new_pubmeds ) {
			push @extra_inserts,
			  {
				statement => 'DELETE FROM profile_refs WHERE (scheme_id,profile_id,pubmed_id)=(?,?,?)',
				arguments => [ $scheme_id, $profile_id, $existing ]
			  };
		}
	}
	return (
		{
			bad_field_buffer => \@bad_field_buffer,
			locus_changed    => \%locus_changed,
			field_changed    => \%field_changed,
			extra_inserts    => \@extra_inserts,
			newdata          => \%newdata,
			updated_field    => \@updated_field
		}
	);
}

sub _update {
	my ( $self, $args ) = @_;
	my ( $scheme_id, $primary_key, $profile_id, $allele_data, $field_data, $profile_data ) =
	  @{$args}{qw(scheme_id primary_key profile_id allele_data field_data profile_data)};
	my $curator_id  = $self->get_curator_id;
	my $update_data = $self->_prepare_update($args);
	my ( $bad_field_buffer, $locus_changed, $field_changed, $extra_inserts, $newdata, $updated_field ) =
	  @{$update_data}{qw(bad_field_buffer locus_changed field_changed extra_inserts newdata updated_field)};
	if (@$bad_field_buffer) {
		local $" = q(<br />);
		$self->print_bad_status(
			{
				message => q(There are problems with your record submission. Please address the following:),
				detail  => qq(@$bad_field_buffer)
			}
		);
		return;
	} elsif ( !%$locus_changed && !%$field_changed && !@$extra_inserts ) {
		$self->print_bad_status( { message => q(No fields were changed.) } );
		return;
	}
	my $locus_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	foreach my $locus ( keys %$locus_changed ) {
		eval {
			$self->{'db'}->do(
				'UPDATE profile_members SET (allele_id,datestamp,curator)=(?,?,?) WHERE '
				  . '(scheme_id,locus,profile_id)=(?,?,?)',
				undef, $newdata->{"locus:$locus"}, 'now', $curator_id, $scheme_id, $locus, $profile_id
			);
		};
		if ($@) {
			$self->_handle_failure;
			return;
		}
		push @$updated_field, qq($locus: '$allele_data->{$locus}' -> '$newdata->{"locus:$locus"}');
	}
	foreach my $field ( keys %$field_changed ) {
		if ( $field eq 'sender' ) {
			eval {
				$self->{'db'}->do(
					'UPDATE profiles SET (sender,datestamp,curator)=(?,?,?) WHERE (scheme_id,profile_id)=(?,?)',
					undef, $newdata->{'field:sender'},
					'now', $curator_id, $scheme_id, $profile_id
				);
			};
			if ($@) {
				$self->_handle_failure;
				return;
			}
			push @$updated_field, qq($field: '$profile_data->{$field}' -> '$newdata->{"field:$field"}');
		} else {
			if ( defined $field_data->{$field} && $field_data->{$field} ne '' ) {
				eval {
					if ( $newdata->{"field:$field"} eq '' ) {
						$self->{'db'}
						  ->do( 'DELETE FROM profile_fields WHERE (scheme_id,scheme_field,profile_id)=(?,?,?)',
							undef, $scheme_id, $field, $profile_id );
					} else {
						$self->{'db'}->do(
							'UPDATE profile_fields SET (value,datestamp,curator)=(?,?,?) '
							  . 'WHERE (scheme_id,scheme_field,profile_id)=(?,?,?)',
							undef, $newdata->{"field:$field"}, 'now', $curator_id, $scheme_id, $field, $profile_id
						);
					}
				};
				if ($@) {
					$self->_handle_failure;
					return;
				}
			} else {
				eval {
					$self->{'db'}->do(
						'INSERT INTO profile_fields (scheme_id,scheme_field,profile_id,value,'
						  . 'curator,datestamp) VALUES (?,?,?,?,?,?)',
						undef, $scheme_id, $field, $profile_id, $newdata->{"field:$field"}, $curator_id, 'now'
					);
				};
				if ($@) {
					$self->_handle_failure;
					return;
				}
			}
			push @$updated_field, qq($field: '$field_data->{$field}' -> '$newdata->{"field:$field"}');
		}
		my $value = $newdata->{"field:$field"};
		undef $value if $newdata->{"field:$field"} eq q();
	}
	if ( keys %$locus_changed || keys %$field_changed ) {
		eval {
			$self->{'db'}->do( 'UPDATE profiles SET (datestamp,curator)=(?,?) WHERE (scheme_id,profile_id)=(?,?)',
				undef, 'now', $curator_id, $scheme_id, $profile_id );
		};
		if ($@) {
			$self->_handle_failure;
			return;
		}
	}
	local $" = q(;);
	eval {
		foreach my $insert (@$extra_inserts) {
			$self->{'db'}->do( $insert->{'statement'}, undef, @{ $insert->{'arguments'} } );
		}
	};
	if ($@) {
		$self->_handle_failure;
		return;
	}
	$self->{'db'}->commit;
	$self->print_good_status(
		{
			message => 'Profile updated.'
		}
	);
	local $" = q(<br />);
	$self->update_profile_history( $scheme_id, $profile_id, "@$updated_field" );
	return;
}

sub _handle_failure {
	my ($self) = @_;
	$logger->error($@);
	$self->{'db'}->rollback;
	$self->print_bad_status( { message => q(Update failed - transaction cancelled - record has not been touched.) } );
	return;
}

sub get_title {
	return q(Update profile);
}

sub _print_interface {
	my ( $self, $args ) = @_;
	my ( $scheme_id, $profile_id, $profile_data, $field_data, $primary_key, $allele_data ) =
	  @{$args}{qw(scheme_id profile_id profile_data field_data primary_key allele_data)};
	my $q           = $self->{'cgi'};
	my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
	my $icon        = $self->get_form_icon( 'profiles', 'edit' );
	say q(<div class="box" id="queryform">);
	say q(<div class="scrollable" style="white-space:nowrap">);
	say $icon;
	my ( $users, $usernames ) = $self->{'datastore'}->get_users;
	$usernames->{''} = ' ';    #Required for HTML5 validation.
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $longest_name  = BIGSdb::Utils::get_largest_string_length( [ @$loci, @$scheme_fields ] );
	my $width         = int( 0.5 * $longest_name ) + 2;
	$width = 15 if $width > 15;
	$width = 6  if $width < 6;
	print $q->start_form;
	say q(<fieldset class="form" style="float:left"><legend>Record</legend>);

	if ( !$q->param('sent') ) {
		say q(<p>Update your record as required - required fields are marked with an exclamation mark (!):</p>);
	}
	$q->param( sent => 1 );
	print $q->hidden($_) foreach qw (page db sent scheme_id profile_id);
	say q(<ul>);
	my ( $label, $title ) = $self->get_truncated_label( $primary_key, 24 );
	my $title_attribute = $title ? qq( title="$title") : q();
	say qq(<li><label class="form" style="width:${width}em"$title_attribute>$label: !</label>);
	say qq(<b>$profile_id</b></li>);

	foreach my $locus (@$loci) {
		my %html5_args = ( required => 'required' );
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		$html5_args{'type'} = 'number'
		  if $locus_info->{'allele_id_format'} eq 'integer' && !$scheme_info->{'allow_missing_loci'};
		my $mapped = $self->clean_locus( $locus, { no_common_name => 1, strip_links => 1 } );
		( $label, $title ) = $self->get_truncated_label( $mapped, 24 );
		$title_attribute = $title ? qq( title="$title") : q();
		say qq(<li><label for="locus:$locus" class="form" style="width:${width}em"$title_attribute>$label: !</label>);
		say $self->textfield(
			-name => "locus:$locus",
			-id   => "locus:$locus",
			-size => $locus_info->{'allele_id_format'} eq 'integer' ? 10 : 20,
			-value => $q->param("locus:$locus") // $allele_data->{$locus},
			%html5_args
		);
		say q(</li>);
	}
	foreach my $field (@$scheme_fields) {
		next if $field eq $primary_key;
		my $field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		my %html5_args;
		$html5_args{'type'} = 'number' if $field_info->{'type'} eq 'integer';
		( $label, $title ) = $self->get_truncated_label( $field, 24 );
		$title_attribute = $title ? qq( title="$title") : q();
		say qq(<li><label for="field:$field" class="form" style="width:${width}em"$title_attribute>$label: </label>);
		say $q->textfield(
			-name => "field:$field",
			-id   => "field:$field",
			-size => $field_info->{'type'} eq 'integer' ? 10 : 50,
			-value => $q->param("field:$field") // $field_data->{$field},
			%html5_args
		);
		say q(</li>);
	}
	say qq(<li><label for="field:sender" class="form" style="width:${width}em">sender: !</label>);
	say $q->popup_menu(
		-name    => 'field:sender',
		-id      => 'field:sender',
		-values  => [ '', @$users ],
		-labels  => $usernames,
		-default => $q->param('field:sender') // $profile_data->{'sender'}
	);
	say q(</li>);
	my $curator_name = $self->get_curator_name;
	say qq(<li><label class="form" style="width:${width}em">curator: !</label>)
	  . qq(<b>$curator_name ($self->{'username'})</b></li>);
	say qq(<li><label class="form" style="width:${width}em">date_entered: !</label><b>);
	say qq($profile_data->{'date_entered'}</b></li>);
	say qq(<li><label class="form" style="width:${width}em">datestamp: !</label><b>);
	say BIGSdb::Utils::get_datestamp();
	say q(</b></li>);
	my $pubmed_list = $self->{'datastore'}->run_query(
		'SELECT pubmed_id FROM profile_refs WHERE (scheme_id,profile_id)=(?,?) ORDER BY pubmed_id',
		[ $scheme_id, $profile_id ],
		{ fetch => 'col_arrayref' }
	);
	say qq(<li><label for="pubmed" class="form" style="width:${width}em">PubMed ids:</label>);
	local $" = "\n";
	say $q->textarea(
		-name    => 'pubmed',
		-id      => 'pubmed',
		-rows    => 2,
		-cols    => 12,
		-style   => 'width:10em',
		-default => "@$pubmed_list"
	);
	say q(</li></ul>);
	say q(</fieldset>);
	$self->print_action_fieldset( { scheme_id => $scheme_id, profile_id => $profile_id } );
	say $q->end_form;
	say q(</div></div>);
	return;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/curator_guide/0070_updating_and_deleting_profiles.html";
}
1;
