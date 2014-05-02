#Written by Keith Jolley
#Copyright (c) 2010-2014, University of Oxford
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
use Error qw(:try);
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
	$locus =~ s/^cn_//;
	my $isolate_id = $q->param('isolate_id') // $q->param('allele_designations_isolate_id');
	if ( !$isolate_id ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No isolate id passed.</p></div>";
		return;
	}
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid locus passed.</p></div>";
		return;
	}
	my $cleaned_locus = $self->clean_locus($locus);
	say "<h1>Update $cleaned_locus allele for isolate $isolate_id</h1>";
	if ( !BIGSdb::Utils::is_int($isolate_id) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Invalid id - Isolate ids are integers.</p></div>";
		return;
	}
	if ( !$self->can_modify_table('allele_designations') ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update allele designations.</p></div>";
		return;
	} elsif ( !$self->is_allowed_to_view_isolate($isolate_id) ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update allele designations "
		  . "for this isolate.</p></div>";
		return;
	}
	my $data = $self->{'datastore'}->run_simple_query_hashref( "SELECT * FROM $self->{'system'}->{'view'} WHERE id=?", $isolate_id );
	if ( !$data->{'id'} ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No record with id = $isolate_id exists.</p></div>";
		return;
	}
	my $right_buffer = "<h2>Locus: $cleaned_locus</h2>\n";
	my @params       = keys %{ $q->Vars };
	my $update;
	my $id;
	foreach my $param (@params) {
		if ( $param =~ /^(\d+)_update/ ) {
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
	my $datestamp = $self->get_datestamp;
	if ($update) {
		$right_buffer .= "<h3>Update allele designation</h3>\n";
		my $designation = $self->{'datastore'}->run_simple_query_hashref( "SELECT * FROM allele_designations WHERE id=?", $id );
		$right_buffer .=
		  $self->create_record_table( 'allele_designations', $designation, { update => 1, nodiv => 1, prepend_table_name => 1 } );
	} else {
		$right_buffer .= "<h3>Add new allele designation</h3>\n";
		$q->delete('update_id');
		my $designation = { isolate_id => $isolate_id, locus => $locus, date_entered => $datestamp, method => 'manual' };
		$right_buffer .=
		  $self->create_record_table( 'allele_designations', $designation,
			{ update => 0, reset_params => 1, nodiv => 1, prepend_table_name => 1, newdata_readonly => 1 } );
	}
	$right_buffer .= $self->_get_existing_designations( $isolate_id, $locus );
	say "<div class=\"box\" id=\"resultstable\">";
	say "<div class=\"scrollable\"><table><tr><td style=\"vertical-align:top\">";
	$self->_display_isolate_summary($isolate_id);
	say "<h2>Update other loci:</h2>";
	print $q->start_form;
	my $set_id = $self->get_set_id;
	my ( $loci, $labels ) = $self->{'datastore'}->get_locus_list( { set_id => $set_id } );
	say "<label for=\"locus\">Locus: </label>";
	say $q->popup_menu( -name => 'locus', -id => 'locus', -values => $loci, -labels => $labels );
	say $q->submit( -label => 'Add/update', -class => 'submit' );
	$q->param( update_id => $data->{'update_id'} );
	say $q->hidden($_) foreach qw(db page isolate_id update_id);
	say $q->end_form;
	say "</td><td style=\"vertical-align:top; padding-left:2em\">";
	say $right_buffer;
	say "</td></tr></table>\n</div>";
	say "</div>";
	return;
}

sub _get_existing_designations {
	my ( $self, $isolate_id, $locus ) = @_;
	my $q            = $self->{'cgi'};
	my $buffer       = '';
	my $designations = $self->{'datastore'}->get_allele_designations( $isolate_id, $locus );
	if (@$designations) {
		$buffer .= "<h3>Existing designations</h3>\n";
		$buffer .= $q->start_form;
		$buffer .= qq(<table class="resultstable"><tr><th>Update</th><th>Delete</th><th>allele id</th><th>sender</th>)
		  . qq(<th>status</th><th>method</th><th>comments</th></tr>\n);
		my $td = 1;
		foreach my $designation (@$designations) {
			my $sender = $self->{'datastore'}->get_user_info( $designation->{'sender'} );
			$designation->{'comments'} //= '';
			$buffer .= qq(<tr class="td$td"><td>);
			$buffer .= $q->submit( -name => "$designation->{'id'}\_update", -label => 'Update', -class => 'smallbutton' );
			$buffer .= '</td><td>';
			$buffer .= $q->submit( -name => "$designation->{'id'}\_delete", -label => 'Delete', -class => 'smallbutton' );
			$buffer .= "</td><td>$designation->{'allele_id'}</td><td>$sender->{'first_name'} $sender->{'surname'}</td>"
			  . "<td>$designation->{'status'}</td><td>$designation->{'method'}</td><td>$designation->{'comments'}</td></tr>";
			$td = $td == 1 ? 2 : 1;
		}
		$buffer .= "</table>\n";
		$buffer .= $q->hidden( sent2 => 1 );
		$q->param( isolate_id => $isolate_id );
		$buffer .= $q->hidden($_) foreach qw(db page locus isolate_id);
		$buffer .= $q->end_form;
	}
	return $buffer;
}

sub _delete {
	my ( $self, $isolate_id, $locus ) = @_;
	my $q      = $self->{'cgi'};
	my @params = keys %{ $q->Vars };
	foreach my $param (@params) {
		if ( $param =~ /^(\d+)_delete/ ) {
			my $id = $1;
			my $designation = $self->{'datastore'}->run_simple_query_hashref( "SELECT * FROM allele_designations WHERE id=?", $id );

			#Although id is the PK, include isolate_id and locus to prevent somebody from easily modifying CGI params.
			eval {
				$self->{'db'}->do( "DELETE FROM allele_designations WHERE (id,isolate_id,locus)=(?,?,?)", undef, $id, $isolate_id, $locus );
			};
			if ($@) {
				$logger->error($@);
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
				$self->update_history( $isolate_id, "$locus: designation '$designation->{'allele_id'}' deleted" );
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
	$newdata->{'datestamp'}    = $self->get_datestamp;
	$newdata->{'curator'}      = $self->get_curator_id;
	$newdata->{'date_entered'} = $q->param('action') eq 'update' ? $data->{'date_entered'} : $self->get_datestamp;
	@problems = $self->check_record( 'allele_designations', $newdata, 1, $data );
	my $existing_designation;
	if ( $q->param('update_id') ) {    #Update existing allele
		$existing_designation =
		  $self->{'datastore'}->run_simple_query_hashref( "SELECT * FROM allele_designations WHERE id=?", $q->param('update_id') );
	} else {                           #Add new allele
		$existing_designation =
		  $self->{'datastore'}->run_simple_query_hashref( "SELECT * FROM allele_designations WHERE (isolate_id,locus,allele_id)=(?,?,?)",
			$isolate_id, $locus, $newdata->{'allele_id'} );
	}
	if ( $q->param('update_id') && $existing_designation && $newdata->{'allele_id'} ne $existing_designation->{'allele_id'} ) {
		my $allele_id_exists =
		  $self->{'datastore'}
		  ->run_simple_query( "SELECT EXISTS (SELECT * FROM allele_designations WHERE isolate_id=? AND locus=? AND allele_id=?)",
			$isolate_id, $locus, $newdata->{'allele_id'} )->[0];
		if ($allele_id_exists) {
			push @problems, "Allele designation '$newdata->{'allele_id'}' already exists.\n";
		}
	} elsif ( !$q->param('update_id') && $existing_designation ) {
		push @problems, "Allele designation '$newdata->{'allele_id'}' already exists.\n";
	}
	if (@problems) {
		local $" = "<br />\n";
		$buffer .= "<div class=\"statusbad_no_resize\"><p>@problems</p></div>\n";
	} else {
		my ( @values, @add_values, @fields, @updated_field );
		foreach my $attribute (@$attributes) {
			push @fields, $attribute->{'name'};
			$newdata->{ $attribute->{'name'} } = '' if !defined $newdata->{ $attribute->{'name'} };
			if ( ( $newdata->{ $attribute->{'name'} } // '' ) ne '' ) {
				my $escaped = $newdata->{ $attribute->{'name'} };
				$escaped =~ s/\\/\\\\/g;
				$escaped =~ s/'/\\'/g;
				push @values,     "$attribute->{'name'} = E'$escaped'";
				push @add_values, "E'$escaped'";
			} else {
				push @values,     "$attribute->{'name'} = null";
				push @add_values, 'null';
			}
			if (   defined $existing_designation->{ lc( $attribute->{'name'} ) }
				&& $newdata->{ $attribute->{'name'} } ne $existing_designation->{ lc( $attribute->{'name'} ) }
				&& $attribute->{'name'}               ne 'datestamp'
				&& $attribute->{'name'}               ne 'date_entered'
				&& $attribute->{'name'}               ne 'curator' )
			{
				push @updated_field,
				  "$locus $attribute->{'name'}: $existing_designation->{lc($attribute->{'name'})} -> $newdata->{ $attribute->{'name'}}";
			}
		}
		local $" = ',';
		if ( $q->param('action') eq 'update' ) {

			#Although id is the PK, include isolate_id and locus to prevent somebody from easily modifying CGI params.
			my $qry = "UPDATE allele_designations SET @values WHERE (id,isolate_id,locus)=(?,?,?)";
			eval { $self->{'db'}->do( $qry, undef, $q->param('update_id'), $isolate_id, $locus ) };
			if ($@) {
				$buffer .=
				  "<div class=\"statusbad_no_resize\"><p>Update failed - transaction cancelled - no records have been touched.</p>\n";
				$buffer .= "<p>Failed SQL: $qry</p>\n";
				$buffer .= "<p>Error message: $@</p></div>\n";
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
				$buffer .= "<div class=\"statusgood_no_resize\"><p>allele designation updated!</p></div>";
				local $" = '<br />';
				$self->update_history( $isolate_id, "@updated_field" );
			}
		} elsif ( $q->param('action') eq 'add' ) {
			local $" = ',';
			my $qry = "INSERT INTO allele_designations (@fields) VALUES (@add_values)";
			my $results_buffer;
			eval { $self->{'db'}->do($qry) };
			if ($@) {
				$results_buffer .=
				  "<div class=\"statusbad_no_resize\"><p>Update failed - transaction cancelled - no records have been touched.</p></div>\n";
				$logger->error("$qry $@");
				$self->{'db'}->rollback;
			} else {
				$self->{'db'}->commit;
				$results_buffer .= "<div class=\"statusgood_no_resize\"><p>allele designation added!</p></div>";
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
	$locus =~ s/^cn_//;
	return "Update $locus allele for isolate $id - $desc";
}
1;
