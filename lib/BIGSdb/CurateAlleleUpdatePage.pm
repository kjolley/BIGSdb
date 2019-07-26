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
package BIGSdb::CurateAlleleUpdatePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::CuratePage);
use BIGSdb::Utils;
use BIGSdb::Constants qw(:interface);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub initiate {
	my ($self) = @_;
	if ( $self->{'cgi'}->param('no_header') ) {
		$self->{'type'}    = 'no_header';
		$self->{'noCache'} = 1;
		return;
	}
	$self->{$_} = 1 foreach qw(jQuery jQuery.jstree noCache);
	return;
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $locus  = $q->param('locus');
	$locus =~ s/^cn_//x;
	my $isolate_id = $q->param('isolate_id') // $q->param('allele_designations_isolate_id');
	if ( !$isolate_id ) {
		say q(<h1>Allele update</h1>);
		$self->print_bad_status( { message => q(No isolate id passed.), navbar => 1 } );
		return;
	}
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		say q(<h1>Allele update</h1>);
		$self->print_bad_status( { message => q(Invalid locus passed.), navbar => 1 } );
		return;
	}
	my $cleaned_locus = $self->clean_locus($locus);
	say qq(<h1>Update $cleaned_locus allele for isolate $isolate_id</h1>);
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		$self->print_bad_status( { message => q(Invalid id - Isolate ids are integers.), navbar => 1 } );
		return;
	}
	if ( !$self->can_modify_table('allele_designations') ) {
		$self->print_bad_status(
			{ message => q(Your user account is not allowed to update allele designations.), navbar => 1 } );
		return;
	} elsif ( !$self->is_allowed_to_view_isolate($isolate_id) ) {
		$self->print_bad_status(
			{
				message => q(Either this isolate does not exist or your user account is not allowed )
				  . q(to update allele designations for this isolate.),
				navbar => 1
			}
		);
		return;
	}
	my $data =
	  $self->{'datastore'}
	  ->run_query( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id, { fetch => 'row_hashref' } );
	if ( !$data ) {
		$self->print_bad_status( { message => qq(No record with id = $isolate_id exists.), navbar => 1 } );
		return;
	}
	my $right_buffer = qq(<h2>Locus: $cleaned_locus</h2>\n);
	my @params       = keys %{ $q->Vars };
	my $update;
	my $id;
	foreach my $param (@params) {
		if ( $param =~ /^(\d+)_update/x ) {
			$update              = 1;
			$id                  = $1;
			$data->{'update_id'} = $id;
			$q->param( update_id => $id );
			last;
		}
	}
	if ( $q->param('sent') ) {
		$right_buffer .= $self->_update( $isolate_id, $locus, $data );
		if ( $right_buffer =~ /statusbad/ && $q->param('update_id') ) {
			$update = 1;
			$id     = $q->param('update_id');
		}
	} elsif ( $q->param('sent2') ) {
		$right_buffer .= $self->_delete( $isolate_id, $locus );
	}
	my $datestamp = BIGSdb::Utils::get_datestamp();
	if ($update) {
		$right_buffer .= qq(<h3>Update allele designation</h3>\n);
		my $designation =
		  $self->{'datastore'}
		  ->run_query( 'SELECT * FROM allele_designations WHERE id=?', $id, { fetch => 'row_hashref' } );
		$right_buffer .=
		  $self->create_record_table( 'allele_designations', $designation,
			{ update => 1, nodiv => 1, prepend_table_name => 1 } );
	} else {
		$right_buffer .= qq(<h3>Add new allele designation</h3>\n);
		$q->delete('update_id');
		my $designation =
		  { isolate_id => $isolate_id, locus => $locus, date_entered => $datestamp, method => 'manual' };
		$right_buffer .=
		  $self->create_record_table( 'allele_designations', $designation,
			{ update => 0, reset_params => 1, nodiv => 1, prepend_table_name => 1, newdata_readonly => 1 } );
	}
	$right_buffer .= $self->_get_existing_designations( $isolate_id, $locus );
	say q(<div class="box" id="resultstable">);
	say q(<div class="scrollable"><table><tr><td style="vertical-align:top">);
	$self->_display_isolate_summary($isolate_id);
	say q(<h2>Update other loci:</h2>);
	print $q->start_form;
	my $set_id = $self->get_set_id;
	my ( $loci, $labels ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
	say q(<label for="locus">Locus: </label>);
	say $q->popup_menu( -name => 'locus', -id => 'locus', -values => $loci, -labels => $labels );
	say $q->submit( -label => 'Add/update', -class => 'button' );
	$q->param( update_id => $data->{'update_id'} );

	if ( !defined $q->param('isolate_id') && defined $q->param('allele_designations_isolate_id') ) {
		$q->param( isolate_id => scalar $q->param('allele_designations_isolate_id') );
	}
	say $q->hidden($_) foreach qw(db page isolate_id update_id);
	say $q->end_form;
	say q(</td><td style="vertical-align:top; padding-left:2em">);
	say $right_buffer;
	say q(</td></tr></table></div>);
	say q(</div>);
	return;
}

sub _get_existing_designations {
	my ( $self, $isolate_id, $locus ) = @_;
	my $q            = $self->{'cgi'};
	my $buffer       = '';
	my $designations = $self->{'datastore'}->get_allele_designations( $isolate_id, $locus );
	if (@$designations) {
		$buffer .= qq(<h3>Existing designations</h3>\n);
		$buffer .= q(<table class="resultstable"><tr><th>Update</th><th>Delete</th><th>allele id</th><th>sender</th>)
		  . qq(<th>status</th><th>method</th><th>comments</th></tr>\n);
		my $td = 1;
		foreach my $designation (@$designations) {
			my $sender = $self->{'datastore'}->get_user_info( $designation->{'sender'} );
			$designation->{'comments'} //= '';
			$buffer .= qq(<tr class="td$td"><td>);
			my ( $edit, $delete ) = ( EDIT, DELETE );
			my $des_id = $designation->{'id'};
			$buffer .=
			    qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=alleleUpdate&amp;isolate_id=$isolate_id&amp;locus=$locus&amp;${des_id}_update=1" )
			  . qq(class="action">$edit</a>);
			$buffer .= q(</td><td>);
			$buffer .=
			    qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
			  . qq(page=alleleUpdate&amp;isolate_id=$isolate_id&amp;locus=$locus&amp;${des_id}_delete=1&amp;)
			  . qq(sent2=1" class="action">$delete</a>);
			$buffer .=
			    qq(</td><td>$designation->{'allele_id'}</td><td>$sender->{'first_name'} $sender->{'surname'}</td>)
			  . qq(<td>$designation->{'status'}</td><td>$designation->{'method'}</td><td>$designation->{'comments'}</td></tr>);
			$td = $td == 1 ? 2 : 1;
		}
		$buffer .= qq(</table>\n);
	}
	return $buffer;
}

sub _delete {
	my ( $self, $isolate_id, $locus ) = @_;
	my $q      = $self->{'cgi'};
	my @params = keys %{ $q->Vars };
	foreach my $param (@params) {
		if ( $param =~ /^(\d+)_delete/x ) {
			my $id = $1;
			my $designation =
			  $self->{'datastore'}
			  ->run_query( 'SELECT * FROM allele_designations WHERE id=?', $id, { fetch => 'row_hashref' } );

			#Although id is the PK, include isolate_id and locus to prevent somebody from easily modifying CGI params.
			eval {
				$self->{'db'}->do( 'DELETE FROM allele_designations WHERE (id,isolate_id,locus)=(?,?,?)',
					undef, $id, $isolate_id, $locus );
			};
			if ($@) {
				$logger->error($@);
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
				$self->update_history( $isolate_id, "$locus: designation '$designation->{'allele_id'}' deleted" )
				  if defined $designation->{'allele_id'};
			}
		}
	}
	my $buffer = '';
	return $buffer;
}

sub _update {
	my ( $self, $isolate_id, $locus, $data ) = @_;
	my @problems;
	my $buffer     = '';
	my $q          = $self->{'cgi'};
	my $newdata    = {};
	my $attributes = $self->{'datastore'}->get_table_field_attributes('allele_designations');
	foreach (@$attributes) {
		my $param = "allele_designations\_$_->{'name'}";
		if ( defined $q->param($param) && $q->param($param) ne '' ) {
			$newdata->{ $_->{'name'} } = $q->param($param);
		}
	}
	$newdata->{'datestamp'} = BIGSdb::Utils::get_datestamp();
	$newdata->{'curator'}   = $self->get_curator_id;
	$newdata->{'date_entered'} =
	  $q->param('action') eq 'update' ? $data->{'date_entered'} : BIGSdb::Utils::get_datestamp();
	@problems = $self->check_record( 'allele_designations', $newdata, 1, $data );

	#TODO Use placeholders for all SQL values.
	my $existing_designation;
	if ( $q->param('update_id') ) {    #Update existing allele
		$existing_designation = $self->{'datastore'}->run_query(
			'SELECT * FROM allele_designations WHERE id=?',
			scalar $q->param('update_id'),
			{ fetch => 'row_hashref' }
		);
	} else {                           #Add new allele
		$existing_designation = $self->{'datastore'}->run_query(
			'SELECT * FROM allele_designations WHERE (isolate_id,locus,allele_id)=(?,?,?)',
			[ $isolate_id, $locus, $newdata->{'allele_id'} ],
			{ fetch => 'row_hashref' }
		);
	}
	if (   $q->param('update_id')
		&& $existing_designation
		&& $newdata->{'allele_id'} ne $existing_designation->{'allele_id'} )
	{
		my $allele_id_exists =
		  $self->{'datastore'}
		  ->run_query( 'SELECT EXISTS (SELECT * FROM allele_designations WHERE (isolate_id,locus,allele_id)=(?,?,?))',
			[ $isolate_id, $locus, $newdata->{'allele_id'} ] );
		if ($allele_id_exists) {
			push @problems, "Allele designation '$newdata->{'allele_id'}' already exists.\n";
		}
	} elsif ( !$q->param('update_id') && $existing_designation ) {
		push @problems, "Allele designation '$newdata->{'allele_id'}' already exists.\n";
	}
	if (@problems) {
		local $" = qq(<br />\n);
		$buffer .= qq(<div class="statusbad_no_resize"><p>@problems</p></div>\n);
	} else {
		my ( @values, @add_values, @fields, @updated_field );
		foreach my $attribute (@$attributes) {
			push @fields, $attribute->{'name'};
			$newdata->{ $attribute->{'name'} } = '' if !defined $newdata->{ $attribute->{'name'} };
			if ( ( $newdata->{ $attribute->{'name'} } // '' ) ne '' ) {
				my $escaped = $newdata->{ $attribute->{'name'} };
				$escaped =~ s/\\/\\\\/gx;
				$escaped =~ s/'/''/gx;
				push @values,     "$attribute->{'name'} = E'$escaped'";
				push @add_values, "E'$escaped'";
			} else {
				push @values,     "$attribute->{'name'} = null";
				push @add_values, 'null';
			}
			if (   defined $existing_designation->{ lc( $attribute->{'name'} ) }
				&& $newdata->{ $attribute->{'name'} } ne $existing_designation->{ lc( $attribute->{'name'} ) }
				&& $attribute->{'name'} ne 'datestamp'
				&& $attribute->{'name'} ne 'date_entered'
				&& $attribute->{'name'} ne 'curator' )
			{
				push @updated_field, "$locus $attribute->{'name'}: "
				  . "$existing_designation->{lc($attribute->{'name'})} -> $newdata->{ $attribute->{'name'}}";
			}
		}
		local $" = ',';
		if ( $q->param('action') eq 'update' ) {

			#Although id is the PK, include isolate_id and locus to prevent somebody from easily modifying CGI params.
			my $qry = "UPDATE allele_designations SET @values WHERE (id,isolate_id,locus)=(?,?,?)";
			eval { $self->{'db'}->do( $qry, undef, scalar $q->param('update_id'), $isolate_id, $locus ) };
			if ($@) {
				$buffer .= q(<div class="statusbad_no_resize"><p>Update failed - transaction cancelled - )
				  . qq(no records have been touched.</p>\n);
				$buffer .= qq(<p>Failed SQL: $qry</p>\n);
				$buffer .= qq(<p>Error message: $@</p></div>\n);
				$logger->error($@);
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
				$buffer .= q(<div class="statusgood_no_resize"><p>allele designation updated!</p></div>);
				local $" = '<br />';
				$self->update_history( $isolate_id, "@updated_field" );
			}
		} elsif ( $q->param('action') eq 'add' ) {
			local $" = ',';
			my $qry = "INSERT INTO allele_designations (@fields) VALUES (@add_values)";
			my $results_buffer;
			eval { $self->{'db'}->do($qry) };
			if ($@) {
				$results_buffer .= q(<div class="statusbad_no_resize"><p>Update failed - transaction cancelled - )
				  . qq(no records have been touched.</p></div>\n);
				$logger->error("$qry $@");
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
				$results_buffer .= q(<div class="statusgood_no_resize"><p>allele designation added!</p></div>);
				$self->update_history( $isolate_id, "$locus: new designation '$newdata->{'allele_id'}'" );
			}
			$buffer .= $results_buffer;
		}
	}
	return $buffer;
}

sub _display_isolate_summary {
	my ( $self, $id ) = @_;
	my $isolate_record = BIGSdb::IsolateInfoPage->new(
		(
			system        => $self->{'system'},
			cgi           => $self->{'cgi'},
			instance      => $self->{'instance'},
			prefs         => $self->{'prefs'},
			prefstore     => $self->{'prefstore'},
			config        => $self->{'config'},
			datastore     => $self->{'datastore'},
			db            => $self->{'db'},
			xmlHandler    => $self->{'xmlHandler'},
			dataConnector => $self->{'dataConnector'},
			contigManager => $self->{'contigManager'},
			curate        => 1
		)
	);
	print $isolate_record->get_isolate_summary( $id, 1 );
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $q     = $self->{'cgi'};
	my $locus = $q->param('locus') || $q->param('allele_designations_locus');
	my $id    = $q->param('isolate_id') || $q->param('allele_designations_isolate_id');
	$id    //= '';
	$locus //= '';
	$locus =~ s/^cn_//x;
	return "Update $locus allele for isolate $id - $desc";
}
1;
