#Written by Keith Jolley
#Copyright (c) 2010-2018, University of Oxford
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
package BIGSdb::CurateProfileAddPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CurateAddPage);
use BIGSdb::Utils;
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
use List::MoreUtils qw(none any uniq);
my $logger = get_logger('BIGSdb.Page');
use constant SUCCESS => 1;

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Add new profile - $desc";
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/curator_guide.html#adding-new-scheme-profile-definitions";
}

sub print_content {
	my ($self)    = @_;
	my $scheme_id = $self->{'cgi'}->param('scheme_id');
	my $set_id    = $self->get_set_id;
	if ( !$self->{'datastore'}->scheme_exists($scheme_id) ) {
		say q(<h1>Add new profile</h1>);
		$self->print_bad_status( { message => q(Invalid scheme passed.), navbar => 1 } );
		return;
	}
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$self->print_bad_status(
			{
				message => q(You can only add profiles to a sequence/profile database - )
				  . q(this is an isolate database.),
				navbar => 1
			}
		);
		return;
	}
	if ( !$self->can_modify_table('profiles') ) {
		$self->print_bad_status( { message => q(Your user account is not allowed to add new profiles.), navbar => 1 } );
		return;
	}
	if ($set_id) {
		if ( !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
			$self->print_bad_status( { message => q(The selected scheme is inaccessible.), navbar => 1 } );
			return;
		}
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	say qq(<h1>Add new $scheme_info->{'name'} profile</h1>);
	my $loci        = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $primary_key = $scheme_info->{'primary_key'};
	if ( !$primary_key ) {
		$self->print_bad_status(
			{
				message => q(This scheme doesn't have a primary key field defined. Profiles )
				  . q(cannot be entered until this has been done.),
				navbar => 1
			}
		);
		return;
	} elsif ( !@$loci ) {
		$self->print_bad_status(
			{
				message => q(This scheme doesn't have any loci belonging to it. Profiles cannot )
				  . q(be entered until there is at least one locus defined.),
				navbar => 1
			}
		);
		return;
	}
	my %newdata;
	my $pk_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my $q             = $self->{'cgi'};
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$scheme_fields) {
		my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		$newdata{"field:$field"} = $q->param("field:$field");
		if ( $field eq $primary_key && $pk_field_info->{'type'} eq 'integer' ) {
			$newdata{$primary_key} = $self->next_id( 'profiles', $scheme_id );
		}
	}
	if ( $q->param('submission_id') ) {
		$self->_set_submission_params( $q->param('submission_id') );
	}
	if ( $q->param('sent') ) {
		return if $self->_upload( $scheme_id, \%newdata );
	}
	my $icon = $self->get_form_icon( 'profiles', 'plus' );
	say $icon;
	$self->_print_interface( $scheme_id, \%newdata );
	return;
}

sub _set_submission_params {
	my ( $self, $submission_id ) = @_;
	my $submission = $self->{'submissionHandler'}->get_submission($submission_id);
	return if !$submission;
	my $profile_submission = $self->{'submissionHandler'}->get_profile_submission($submission_id);
	return if !$profile_submission;
	my $q = $self->{'cgi'};
	$q->param( 'field:sender' => $submission->{'submitter'} );
	return if !BIGSdb::Utils::is_int( $q->param('index') );
	my $profile_index = 1;

	foreach my $profile ( @{ $profile_submission->{'profiles'} } ) {
		if ( $q->param('index') == $profile_index ) {
			my $designations = $profile->{'designations'};
			$q->param( "locus:$_" => $designations->{$_} ) foreach keys %$designations;
			last;
		}
		$profile_index++;
	}
	return;
}

sub clean_field {
	my ( $self, $value_ref ) = @_;
	$$value_ref =~ s/^\s*//x;
	$$value_ref =~ s/\s*$//x;
	return;
}

sub _check_upload_data {
	my ( $self, $scheme_id, $newdata ) = @_;
	my $q = $self->{'cgi'};
	my ( @bad_field_buffer, @fields_with_values );
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	foreach my $field (@$scheme_fields) {
		$newdata->{"field:$field"} = $q->param("field:$field");
		$self->clean_field( \$newdata->{"field:$field"} );
		push @fields_with_values, $field if $newdata->{"field:$field"};
		my $field_bad = $self->_is_scheme_field_bad( $scheme_id, $field, $newdata->{"field:$field"} );
		push @bad_field_buffer, $field_bad if $field_bad;
	}
	$newdata->{'field:curator'} = $self->get_curator_id;
	$newdata->{'field:sender'}  = $q->param('field:sender');
	if ( !$newdata->{'field:sender'} ) {
		push @bad_field_buffer, q(Field 'sender' requires a value.);
	} elsif ( !BIGSdb::Utils::is_int( $newdata->{'field:sender'} ) ) {
		push @bad_field_buffer, q(Field 'sender' is invalid.);
	}
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
	if ( $self->{'datastore'}->is_profile_retired( $scheme_id, $newdata->{"field:$scheme_info->{'primary_key'}"} ) ) {
		push @bad_field_buffer,
		  qq($scheme_info->{'primary_key'}-$newdata->{"field:$scheme_info->{'primary_key'}"} has been retired.);
	}
	my $loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	foreach my $locus (@$loci) {
		$newdata->{"locus:$locus"} = $q->param("locus:$locus");
		$self->clean_field( \$newdata->{"locus:$locus"} );
		my $field_bad = $self->is_locus_field_bad( $scheme_id, $locus, $newdata->{"locus:$locus"} );
		push @bad_field_buffer, $field_bad if $field_bad;
	}
	return ( \@bad_field_buffer, \@fields_with_values );
}

sub _upload {
	my ( $self, $scheme_id, $newdata ) = @_;
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $set_id        = $self->get_set_id;
	my $scheme_info   = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	my $primary_key   = $scheme_info->{'primary_key'};
	my $q             = $self->{'cgi'};
	my $insert        = 1;
	my ( $bad_field_buffer, $fields_with_values ) = $self->_check_upload_data( $scheme_id, $newdata );
	my @extra_inserts;
	my @new_pubmeds = split /\r?\n/x, $q->param('pubmed');
	my $pubmed_error = 0;

	foreach my $new (@new_pubmeds) {
		chomp $new;
		next if $new eq '';
		if ( !BIGSdb::Utils::is_int($new) ) {
			push @$bad_field_buffer, 'PubMed ids must be integers' if !$pubmed_error;
			$pubmed_error = 1;
		} else {
			my $profile_id = $newdata->{"field:$primary_key"};
			push @extra_inserts,
			  {
				statement => 'INSERT INTO profile_refs (scheme_id,profile_id,pubmed_id,curator,datestamp) VALUES '
				  . '(?,?,?,?,?)',
				arguments => [ $scheme_id, $profile_id, $new, $newdata->{'field:curator'}, 'now' ]
			  };
		}
	}
	if (@$bad_field_buffer) {
		local $" = '<br />';
		$self->print_bad_status(
			{
				message => q(There are problems with your record submission. Please address the following:),
				detail  => qq(@$bad_field_buffer),
				navbar  => 1
			}
		);
		$insert = 0;
	}

	#Make sure profile not already entered
	if ($insert) {
		my %designations = map { $_ => $newdata->{"locus:$_"} } @$loci;
		my $ret =
		  $self->{'datastore'}->check_new_profile( $scheme_id, \%designations, $newdata->{"field:$primary_key"} );
		$self->print_bad_status( { message => $ret->{'msg'}, navbar => 1 } ) if $ret->{'msg'};
		$insert = 0 if $ret->{'exists'} || $ret->{'err'};
	}
	if ($insert) {
		my $pk_exists =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM profiles WHERE (scheme_id,profile_id)=(?,?))',
			[ $scheme_id, $newdata->{"field:$primary_key"} ] );
		if ($pk_exists) {
			$self->print_bad_status(
				{
					message => qq($primary_key-$newdata->{"field:$primary_key"} has already been )
					  . qq(defined - please choose a different $primary_key.),
					navbar => 1
				}
			);
			$insert = 0;
		}
		my $sender_exists =
		  $self->{'datastore'}
		  ->run_query( 'SELECT EXISTS(SELECT * FROM users WHERE id=?)', $newdata->{'field:sender'} );
		if ( !$sender_exists ) {
			$self->print_bad_status( { message => q(Invalid sender set.), navbar => 1 } );
			$insert = 0;
		}
		if ($insert) {
			my @inserts;
			my ( @mv_fields, @mv_values );
			push @inserts,
			  {
				statement => 'INSERT INTO profiles (scheme_id,profile_id,sender,curator,date_entered,datestamp) '
				  . 'VALUES (?,?,?,?,?,?)',
				arguments => [
					$scheme_id,                 $newdata->{"field:$primary_key"},
					$newdata->{'field:sender'}, $newdata->{'field:curator'},
					'now',                      'now'
				]
			  };
			foreach my $locus (@$loci) {
				push @inserts,
				  {
					statement => 'INSERT INTO profile_members (scheme_id,locus,profile_id,allele_id,curator,datestamp) '
					  . 'VALUES (?,?,?,?,?,?)',
					arguments => [
						$scheme_id,                       $locus,
						$newdata->{"field:$primary_key"}, $newdata->{"locus:$locus"},
						$newdata->{'field:curator'},      'now'
					]
				  };
				( my $cleaned = $locus ) =~ s/'/_PRIME_/gx;
				push @mv_fields, $cleaned;
				push @mv_values, $newdata->{"locus:$locus"};
			}
			foreach my $field (@$fields_with_values) {
				push @inserts,
				  {
					statement => 'INSERT INTO profile_fields(scheme_id,scheme_field,profile_id,value,curator,'
					  . 'datestamp) VALUES (?,?,?,?,?,?)',
					arguments => [
						$scheme_id,                       $field,
						$newdata->{"field:$primary_key"}, $newdata->{"field:$field"},
						$newdata->{'field:curator'},      'now'
					]
				  };
				push @mv_fields, $field;
				push @mv_values, $newdata->{"field:$field"};
			}
			push @inserts, @extra_inserts;
			local $" = ';';
			eval {
				foreach my $insert (@inserts) {
					$self->{'db'}->do( $insert->{'statement'}, undef, @{ $insert->{'arguments'} } );
				}
			};
			if ($@) {
				my $detail;
				if ( $@ =~ /duplicate/ && $@ =~ /unique/ ) {
					$detail = q(Data entry would have resulted in records with either duplicate ids or another )
					  . q(unique field with duplicate values.);
				} else {
					$logger->error("Insert failed: $@");
				}
				$self->print_bad_status(
					{
						message => 'Insert failed - transaction cancelled - no records have been touched.',
						detail  => $detail
					}
				);
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
				my $submission_id = $q->param('submission_id');
				$self->print_good_status(
					{
						message       => qq($primary_key-$newdata->{"field:$primary_key"} added.),
						navbar        => 1,
						submission_id => $submission_id,
						more_url =>
						  qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=profileAdd&amp;)
						  . qq(scheme_id=$scheme_id)
					}
				);
				$self->update_profile_history( $scheme_id, $newdata->{"field:$primary_key"}, 'Profile added' );
				return SUCCESS;
			}
		}
	}
	return;
}

sub _print_interface {
	my ( $self, $scheme_id, $newdata ) = @_;
	my $q           = $self->{'cgi'};
	my $set_id      = $self->get_set_id;
	my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id, get_pk => 1 } );
	my $primary_key = $scheme_info->{'primary_key'};
	my $msg =
	  $scheme_info->{'allow_missing_loci'}
	  ? q[ This scheme allows profile definitions to contain missing alleles (designate ]
	  . q[these as '0') or ignored alleles (designate these as 'N').]
	  : q[];
	say q(<div class="box" id="queryform">);
	say q(<div class="scrollable">);
	say qq(<p>Please fill in the fields below - required fields are marked with an exclamation mark (!).$msg</p>);
	say q(<fieldset class="form" style="float:left"><legend>Record</legend>);
	my $loci         = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $fields       = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $longest_name = BIGSdb::Utils::get_largest_string_length( [ @$loci, @$fields ] );
	my $width        = int( 0.5 * $longest_name ) + 2;
	$width = 15 if $width > 15;
	$width = 6  if $width < 6;
	print $q->start_form;
	$q->param( sent => 1 );
	say $q->hidden($_) foreach qw (page db sent scheme_id submission_id);
	say q(<ul style="white-space:nowrap">);
	my ( $label, $title ) = $self->get_truncated_label( $primary_key, 24 );
	my $title_attribute = $title ? qq( title="$title") : q();
	say qq(<li><label for="field:$primary_key" class="form" style="width:${width}em"$title_attribute>$label: !</label>);
	my $pk_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	my %html5_args = ( required => 'required' );
	$html5_args{'type'} = 'number' if $pk_field_info->{'type'} eq 'integer';
	say $self->textfield(
		-name => "field:$primary_key",
		-id   => "field:$primary_key",
		-size => $pk_field_info->{'type'} eq 'integer' ? 10 : 30,
		-value => $q->param("field:$primary_key") // $newdata->{$primary_key},
		%html5_args
	);
	my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );

	if ( $scheme_field_info->{'description'} ) {
		say $self->get_tooltip(qq($primary_key - $scheme_field_info->{'description'}));
	}
	say q(</li>);
	foreach my $locus (@$loci) {
		%html5_args = ( required => 'required' );
		my $locus_info = $self->{'datastore'}->get_locus_info($locus);
		$html5_args{'type'} = 'number'
		  if $locus_info->{'allele_id_format'} eq 'integer' && !$scheme_info->{'allow_missing_loci'};
		my $cleaned = $self->clean_locus( $locus, { strip_links => 1 } );
		( $label, $title ) = $self->get_truncated_label( $cleaned, 24 );
		$title_attribute = $title ? qq( title="$title") : q();
		say qq(<li><label for="locus:$locus" class="form" style="width:${width}em"$title_attribute>$label: !</label>);
		say $self->textfield(
			-name  => "locus:$locus",
			-id    => "locus:$locus",
			-size  => 10,
			-value => $q->param("locus:$locus") // $newdata->{"locus:$locus"},
			%html5_args
		);
		say q(</li>);
	}
	say qq(<li><label for="field:sender" class="form" style="width:${width}em">sender: !</label>);
	my ( $users, $user_names ) = $self->{'datastore'}->get_users;
	say $self->popup_menu(
		-name     => 'field:sender',
		-id       => 'field:sender',
		-values   => [ '', @$users ],
		-labels   => $user_names,
		-default  => $newdata->{'field:sender'},
		-required => 'required'
	);
	say q(</li>);
	foreach my $field (@$fields) {
		next if $field eq $primary_key;
		$scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
		%html5_args = ();
		$html5_args{'type'} = 'number' if $scheme_field_info->{'type'} eq 'integer';
		( $label, $title ) = $self->get_truncated_label( $field, 24 );
		$title_attribute = $title ? " title=\"$title\"" : '';
		say qq(<li><label for="field:$field" class="form" style="width:${width}em"$title_attribute>$label: </label>);
		say $self->textfield(
			-name  => "field:$field",
			-id    => "field:$field",
			-size  => $scheme_field_info->{'type'} eq 'integer' ? 10 : 50,
			-value => $newdata->{"field:$field"},
			%html5_args
		);

		if ( $scheme_field_info->{'description'} ) {
			say $self->get_tooltip(qq($label - $scheme_field_info->{'description'}));
		}
		say q(</li>);
	}
	say qq(<li><label class="form" style="width:${width}em">curator: !</label><b>)
	  . $self->get_curator_name . q[ (]
	  . $self->{'username'}
	  . q[)</b></li>];
	say qq(<li><label class="form" style="width:${width}em">date_entered: !</label><b>)
	  . BIGSdb::Utils::get_datestamp()
	  . q(</b></li>);
	say qq(<li><label class="form" style="width:${width}em">datestamp: !</label><b>)
	  . BIGSdb::Utils::get_datestamp()
	  . q(</b></li>);
	say qq(<li><label for="pubmed" class="form" style="width:${width}em">PubMed ids:</label>);
	say $q->textarea( -name => 'pubmed', -id => 'pubmed', -rows => 2, -cols => 12, -style => 'width:10em' );
	say q(</li></ul>);
	$self->print_action_fieldset( { scheme_id => $scheme_id } );
	say $q->end_form;
	say q(</fieldset></div></div>);
	return;
}

sub _is_scheme_field_bad {
	my ( $self, $scheme_id, $field, $value ) = @_;
	my $scheme_field_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $field );
	if ( $scheme_field_info->{'primary_key'} && $value eq '' ) {
		return "Field '$field' is the primary key and requires a value.";
	} elsif ( $value ne ''
		&& $scheme_field_info->{'type'} eq 'integer'
		&& !BIGSdb::Utils::is_int($value) )
	{
		return qq(Field '$field' must be an integer.);
	} elsif ( $value ne '' && $scheme_field_info->{'value_regex'} && $value !~ /$scheme_field_info->{'value_regex'}/x )
	{
		return "Field value is invalid - it must match the regular expression /$scheme_field_info->{'value_regex'}/.";
	}
}

sub is_locus_field_bad {
	my ( $self, $scheme_id, $locus, $value ) = @_;
	if ( !$self->{'cache'}->{'locus_info'}->{$locus} ) {   #may be called thousands of time during a batch add so cache.
		$self->{'cache'}->{'locus_info'}->{$locus} = $self->{'datastore'}->get_locus_info($locus);
	}
	my $locus_info = $self->{'cache'}->{'locus_info'}->{$locus};
	my $set_id     = $self->get_set_id;
	my $mapped     = $self->clean_locus( $locus, { no_common_name => 1 } );
	if ( !defined $value || $value eq '' ) {
		return "Locus '$mapped' requires a value.";
	} elsif ( $value eq '0' || $value eq 'N' ) {
		my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
		if ( $scheme_info->{'allow_missing_loci'} ) {
			if ( !$self->{'datastore'}->sequence_exists( $locus, $value ) ) {
				$self->define_missing_allele( $locus, $value );
			}
			return;
		}
		return "$mapped value is invalid - this scheme does not allow missing (0) or arbitrary alleles (N) "
		  . 'in the profile.';
	}
	if ( $locus_info->{'allele_id_format'} eq 'integer' && !BIGSdb::Utils::is_int($value) ) {
		return "Locus '$mapped' must be an integer.";
	}
	if ( $locus_info->{'allele_id_regex'} && $value !~ /$locus_info->{'allele_id_regex'}/x ) {
		return "$mapped value is invalid - it must match the regular expression /$locus_info->{'allele_id_regex'}/.";
	}
	if ( !defined $self->{'cache'}->{'seq_exists'}->{$locus}->{$value} ) {
		$self->{'cache'}->{'seq_exists'}->{$locus}->{$value} = $self->{'datastore'}->sequence_exists( $locus, $value );
	}
	if ( !$self->{'cache'}->{'seq_exists'}->{$locus}->{$value} ) {
		return "Allele $mapped $value has not been defined.";
	}
	return;
}

sub define_missing_allele {
	my ( $self, $locus, $allele ) = @_;
	my $seq;
	if    ( $allele eq '0' ) { $seq = 'null allele' }
	elsif ( $allele eq 'N' ) { $seq = 'arbitrary allele' }
	else                     { return }
	my $sql =
	  $self->{'db'}
	  ->prepare( 'INSERT INTO sequences (locus, allele_id, sequence, sender, curator, date_entered, datestamp, '
		  . 'status) VALUES (?,?,?,?,?,?,?,?)' );
	eval { $sql->execute( $locus, $allele, $seq, 0, 0, 'now', 'now', '' ) };
	if ($@) {
		$logger->error($@) if $@;
		$self->{'db'}->rollback;
		return;
	}
	$self->{'db'}->commit;
	return;
}

sub update_profile_history {
	my ( $self, $scheme_id, $profile_id, $action ) = @_;
	return if !$action || !$scheme_id || !$profile_id;
	my $curator_id = $self->get_curator_id;
	eval {
		$self->{'db'}
		  ->do( 'INSERT INTO profile_history (scheme_id,profile_id,timestamp,action,curator) VALUES ' . '(?,?,?,?,?)',
			undef, $scheme_id, $profile_id, 'now', $action, $curator_id );
	};
	if ($@) {
		$logger->error("Can't update history for scheme_id:$scheme_id profile:$profile_id '$action' $@");
		$self->{'db'}->rollback;
	} else {
		$self->{'db'}->commit;
	}
	return;
}
1;
