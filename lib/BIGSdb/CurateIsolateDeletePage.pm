#Written by Keith Jolley
#Copyright (c) 2010, University of Oxford
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

package BIGSdb::CurateIsolateDeletePage;
use strict;
use base qw(BIGSdb::CuratePage);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub get_javascript {
	my ($self) = @_;
	return $self->get_tree_javascript;
}

sub initiate {
	my ($self) = @_;
	$self->{'jQuery'} = 1; 
	$self->{'jQuery.jstree'} = 1;
}

sub print_content {
	my ($self) = @_;
	my $q    = $self->{'cgi'};
	my $id   = $q->param('id');
	my $sql;
	my $buffer;
	print "<h1>Delete isolate</h1>\n";
	if ( !$self->can_modify_table('isolates') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to delete records to the isolates table.</p></div>\n";
		return;
	} elsif (!$self->is_allowed_to_view_isolate($id)){
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to delete this isolate record.</p></div>\n";
		return;
	}
	my $qry = "SELECT * FROM $self->{'system'}->{'view'} WHERE id = ?";
	$sql = $self->{'db'}->prepare($qry);

	if ( !$q->param('id') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No id passed.</p></div>\n";
		return;
	}
	eval { $sql->execute($id); };
	if ($@) {
		$logger->error("Can't execute: $qry  value: $id");
	} else {
		$logger->debug("Query: $qry  value: $id");
	}
	my ($data) = $sql->fetchrow_hashref();
	if ( !$$data{'id'} ) {
		print
"<div class=\"box\" id=\"statusbad\"><p>No record with id = $id exists.</p></div>\n";
		return;
	}
	$buffer .= "<div class=\"box\" id=\"resultstable\">\n";
	$buffer .= "<p>You have selected to delete the following record:</p>";
	$buffer .= $q->start_form;
	foreach (qw (page db id)) {
		$buffer .= $q->hidden($_);
	}
	$buffer .= $q->submit( -name => 'submit', -value => 'Delete!', -class=>'submit' );
	$buffer .= $q->end_form;
	$buffer .= "<p />\n";
	my $isolate_record = BIGSdb::IsolateInfoPage->new(
		(
			'system'        => $self->{'system'},
			'cgi'           => $self->{'cgi'},
			'instance'      => $self->{'instance'},
			'prefs'         => $self->{'prefs'},
			'prefstore'     => $self->{'prefstore'},
			'config'        => $self->{'config'},
			'datastore'     => $self->{'datastore'},
			'db'            => $self->{'db'},
			'xmlHandler'    => $self->{'xmlHandler'},
			'dataConnector' => $self->{'dataConnector'},
			'curate'		=> 1
		)
	);
	my $record_table = $isolate_record->get_isolate_record($id);
	$buffer .= $record_table;
	$buffer .= "<p />\n";
	$buffer .= $q->start_form;
	$q->param('page', 'isolateDelete'); #need to set as this may have changed if there is a seqbin display button
	foreach (qw (page db id)) {
		$buffer .= $q->hidden($_);
	}
	$buffer .= $q->submit( -name => 'submit', -value => 'Delete!', -class=>'submit' );
	$buffer .= $q->end_form;
	$buffer .= "</div>\n";
	if ( $q->param('submit') ) {
		my @qry;
		push @qry,
		  "DELETE FROM isolates WHERE id = '$$data{'id'}'";
		foreach (@qry) {
			eval { $self->{'db'}->do($_); };
			if ($@) {
				print
"<div class=\"box\" id=\"statusbad\"><p>Delete failed - transaction cancelled - no records have been touched.</p>\n";
				print "<p>Failed SQL: $_</p>\n";
				print "<p>Error message: $@</p></div>\n";
				$logger->error("Delete failed: $_ $@");
				$self->{'db'}->rollback();
				return;
			}
		}
		$self->{'db'}->commit()
		  && print
"<div class=\"box\" id=\"resultsheader\"><p>Isolate id:$$data{'id'} deleted!</p>";
		print "<p><a href=\""
		  . $q->script_name
		  . "?db=$self->{'instance'}\">Back to main page</a></p></div>\n";
		return;
	}
	print $buffer;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Delete isolate - $desc";
}
1;


