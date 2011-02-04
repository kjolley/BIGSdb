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

package BIGSdb::CurateAlleleUpdatePage;
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
	if ($self->{'cgi'}->param('no_header') ){
		$self->{'type'} = 'no_header';
		$self->{'noCache'} = 1;
		return;
	}
	$self->{'jQuery'} = 1;    #Use JQuery javascript library
	$self->{'jQuery.jstree'} = 1;
}

sub print_content {
	my ($self)   = @_;
	my $q         = $self->{'cgi'};
	my $clear_pad = 1;
	my $locus     = $q->param('locus')
	  || $q->param('allele_designations_locus')
	  || $q->param('pending_allele_designations_locus');
	my $id = $q->param('isolate_id')
	  || $q->param('allele_designations_isolate_id')
	  || $q->param('pending_allele_designations_isolate_id');
	if ( !$id ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No id passed.</p></div>\n";
		return;
	}
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Invalid locus passed.</p></div>\n";
		return;
	}
	print "<h1>Update $locus allele for isolate $id</h1>\n";
	if ( !$self->can_modify_table('allele_designations') ) {
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update allele designations.</p></div>\n";
		return;
	} elsif (!$self->is_allowed_to_view_isolate($id)){
		print "<div class=\"box\" id=\"statusbad\"><p>Your user account is not allowed to update allele designations for this isolate.</p></div>\n";
		return;		
	}
	my $qry = "SELECT * FROM $self->{'system'}->{'view'} WHERE id = ?";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($id); };
	if ($@) {
		$logger->error("Can't execute: $qry  value: $id");
	} else {
		$logger->debug("Query: $qry value: $id");
	}
	my $data = $sql->fetchrow_hashref();
	if ( !$data->{'id'} ) {
		print
"<div class=\"box\" id=\"statusbad\"><p>No record with id = $id exists.</p></div>\n";
		return;
	}
	my ( $left_buffer, $right_buffer );
	$right_buffer .= "<h2>Locus: $locus</h2>";
	$right_buffer .= "<h3>Allele designation";
	$right_buffer .=
" <a class=\"tooltip\" title=\"Allele designation - This is the primary designation and is used in all analyses.\">&nbsp;<i>i</i>&nbsp;</a>";
	$right_buffer .= "</h3>\n";
	my @problems;
	my $new_pending_problems;

	if ( $q->param('sent') ) {
		my $table = $q->param('table');
		if (   $table ne 'allele_designations'
			&& $table ne 'pending_allele_designations' )
		{
			$logger->warn("Invalid table submitted");
			print
"<div class=\"box\" id=\"statusbad\"><p>Invalid table submitted.</p></div>\n";
			return;
		}
		my %newdata;
		my $attributes =
		  $self->{'datastore'}->get_table_field_attributes($table);
		my @query_values;
		foreach (@$attributes) {
			my $value = $q->param("$table\_$_->{'name'}");
			$value =~ s/'/\\'/g;
			if ( $_->{'primary_key'} eq 'yes' ) {
				push @query_values, "$_->{'name'} = '$value'";
			}
		}
		if ( !@query_values ) {
			$right_buffer .=
"<div class=\"box\" id=\"statusbad\"><p>No identifying attributes sent.</p>\n";
			return;
		}
		foreach (@$attributes) {
			if ( $q->param("$table\_$_->{'name'}") ne '' ) {
				$newdata{ $_->{'name'} } = $q->param("$table\_$_->{'name'}");
			}
		}
		$newdata{'datestamp'}    = $self->get_datestamp;
		$newdata{'curator'}      = $self->get_curator_id();
		$newdata{'date_entered'} =
		    $q->param('action') eq 'update'
		  ? $data->{'date_entered'}
		  : $self->get_datestamp;
		@problems = $self->check_record( $table, \%newdata, 1, $data );
		if (@problems) {
			$" = "<br />\n";
			if ( $table eq 'allele_designations' ) {
				$right_buffer .=
				  "<div class=\"statusbad_no_resize\"><p>@problems</p></div>\n";
			} else {
				$new_pending_problems .=
				  "<div class=\"statusbad_no_resize\"><p>@problems</p></div>\n";
			}
		} else {
			my ( @values, @add_values, @fields, @updated_field );
			my $allele = $self->{'datastore'}->get_allele_designation( $id, $locus );
			foreach (@$attributes) {
				push @fields, $_->{'name'};
				$newdata{ $_->{'name'} } =~ s/\\/\\\\/g;
				$newdata{ $_->{'name'} } =~ s/'/\\'/g;				
				if ( $_->{'name'} =~ /sequence$/ ) {
					$newdata{ $_->{'name'} } = uc( $newdata{ $_->{'name'} } );
					$newdata{ $_->{'name'} } =~ s/\s//g;
				}
				if ( $newdata{ $_->{'name'} } ne '' ) {
					push @values, "$_->{'name'} = '$newdata{ $_->{'name'}}'";
					push @add_values, "'$newdata{ $_->{'name'}}'";
				} else {
					push @values,     "$_->{'name'} = null";
					push @add_values, 'null';
				}
				if ($newdata{ $_->{'name'}} ne $allele->{lc($_->{'name'})} && $_->{'name'} ne 'datestamp' && $_->{'name'} ne 'curator'){
					push @updated_field,"$locus $_->{'name'}: $allele->{lc($_->{'name'})} -> $newdata{ $_->{'name'}}";
				}
			}
			$" = ',';
			if ( $q->param('action') eq 'update' ) {
				my $qry = "UPDATE $table SET @values WHERE ";
				$" = ' AND ';
				$qry .= "@query_values";
				eval { $self->{'db'}->do($qry); };
				if ($@) {
					$right_buffer .=
"<div class=\"statusbad_no_resize\"><p>Update failed - transaction cancelled - no records have been touched.</p>\n";
					$right_buffer .= "<p>Failed SQL: $qry</p>\n";
					$right_buffer .= "<p>Error message: $@</p></div>\n";
					$self->{'db'}->rollback();
				} else {
					$self->{'db'}->commit();
					$right_buffer .=
"<div class=\"statusgood_no_resize\"><p>allele designation updated!</p></div>";
					$"='<br />';
					$self->update_history($id,"@updated_field");
				}
			} elsif ( $q->param('action') eq 'add' ) {

		#if adding pending designation, check that an existing one with the same
		#primary key does not exist.
				my $proceed = 1;
				if ( $table eq 'pending_allele_designations' ) {
					my $exists = $self->{'datastore'}->run_simple_query(
"SELECT COUNT(*) FROM pending_allele_designations WHERE isolate_id=? AND locus=? AND allele_id=? AND sender=? AND method=?",
						$newdata{'isolate_id'}, $newdata{'locus'},
						$newdata{'allele_id'},  $newdata{'sender'},
						$newdata{'method'}
					)->[0];
					if ( $exists ) {
						$new_pending_problems .=
"<div class=\"statusbad_no_resize\"><p>Pending allele designation could not be added as it would result in a duplicate entry, i.e. a pending designation with the same allele_id, sender and method.</p></div>\n";
						$proceed   = 0;
						$clear_pad = 0;
					}
				} elsif ( $table eq 'allele_designations' ) {
					my $exists = $self->{'datastore'}->run_simple_query(
"SELECT COUNT(*) FROM allele_designations WHERE isolate_id=? AND locus=?",
						$newdata{'isolate_id'}, $newdata{'locus'}
					)->[0];
					if ( $exists ) {
						$new_pending_problems .=
"<div class=\"statusbad_no_resize\"><p>Pending allele designation could not be added as it would result in a duplicate entry, i.e. a pending designation with the same allele_id, sender and method.</p></div>\n";
						$proceed = 0;
						$right_buffer .=
"<div class=\"statusbad_no_resize\"><p>Allele designation already exists - please add a new pending designation instead.</p></div>\n";
					}
				}
				if ($proceed) {
					$" = ',';
					my $qry =
					  "INSERT INTO $table (@fields) VALUES (@add_values)";
					my $results_buffer;
					eval { $self->{'db'}->do($qry); };
					if ($@) {
						$results_buffer .=
"<div class=\"statusbad_no_resize\"><p>Update failed - transaction cancelled - no records have been touched.</p>\n";
						$results_buffer .= "<p>Failed SQL: $qry</p>\n";
						$results_buffer .= "<p>Error message: $@</p></div>\n";
						$self->{'db'}->rollback();
					} else {
						$self->{'db'}->commit();
						$results_buffer .=
"<div class=\"statusgood_no_resize\"><p>allele designation updated!</p></div>";
						my $display_table = $table eq 'allele_designations' ? '' : 'pending';
						$self->update_history($id,"$locus: new $display_table designation '$newdata{'allele_id'}'");
					}
					if ( $table eq 'allele_designations' ) {
						$right_buffer .= $results_buffer;
					} else {
						$new_pending_problems .= $results_buffer;
					}
				}
			}
		}
	} elsif ( $q->param('sent2') ) {
		my $qry =
"SELECT * FROM pending_allele_designations WHERE isolate_id=? AND locus=? ORDER BY datestamp";
		my $sql = $self->{'db'}->prepare($qry);
		eval { $sql->execute( $id, $locus ); };
		if ($@) {
			$logger->error("Can't execute $qry: values: $id, $locus");
		}
		while ( my $allele = $sql->fetchrow_hashref() ) {
			my $pk =
"$allele->{'allele_id'}\_$allele->{'sender'}\_$allele->{'method'}";
			if ( $q->param("$pk\_promote") ) {
				my $to_be_promoted = $allele;
				my $qry            =
"SELECT * FROM allele_designations WHERE isolate_id=? AND locus=?";
				my $sql = $self->{'db'}->prepare($qry);
				eval { $sql->execute( $id, $locus ); };
				if ($@) {
					$logger->error("Can't execute $qry: values: $id, $locus");
				}
				my $to_be_demoted = $sql->fetchrow_hashref();

				#Swap designation with pending
				my $curator_id = $self->get_curator_id();
				my $pad_exists = $self->{'datastore'}->run_simple_query(
"SELECT COUNT(*) FROM pending_allele_designations WHERE isolate_id=? AND locus=? AND allele_id=? AND sender=? AND method=?",
					$id, $locus,
					$to_be_demoted->{'allele_id'},
					$to_be_demoted->{'sender'},
					$to_be_demoted->{'method'}
				)->[0];
				if (
					$pad_exists
					&& !(
						$to_be_demoted->{'allele_id'} eq
						$to_be_promoted->{'allele_id'}
						&& $to_be_demoted->{'sender'} eq
						$to_be_promoted->{'sender'}
						&& $to_be_demoted->{'method'} eq
						$to_be_promoted->{'method'}
					)
				  )
				{
					$right_buffer .=
"<div class=\"statusbad_no_resize\"><p>Can't swap designations as it would result in two identical pending designations (same allele, sender and method).  In order to proceed, please delete the pending designation that matches the existing designation that you are demoting.</p></div>\n";
				} else {
					eval {
						$self->{'db'}->do(
"DELETE FROM allele_designations WHERE isolate_id='$id' AND locus='$locus'"
						);
						$self->{'db'}->do(
"INSERT INTO allele_designations (isolate_id,locus,allele_id,sender,status,method,curator,date_entered,datestamp,comments) VALUES ('$id','$locus','$to_be_promoted->{'allele_id'}','$to_be_promoted->{'sender'}','provisional','$to_be_promoted->{'method'}',$curator_id,'$to_be_promoted->{'date_entered'}','today','$to_be_promoted->{'comments'}')"
						);
						$self->{'db'}->do(
"DELETE FROM pending_allele_designations WHERE isolate_id='$id' AND locus='$locus' AND allele_id='$to_be_promoted->{'allele_id'}' AND sender='$to_be_promoted->{'sender'}' AND method='$to_be_promoted->{'method'}'"
						);
						$self->{'db'}->do(
"INSERT INTO pending_allele_designations (isolate_id,locus,allele_id,sender,method,curator,date_entered,datestamp,comments) VALUES ('$id','$locus','$to_be_demoted->{'allele_id'}','$to_be_demoted->{'sender'}','$to_be_demoted->{'method'}',$curator_id,'$to_be_demoted->{'date_entered'}','today','$to_be_demoted->{'comments'}')"
						);
					};
					if ($@) {
						$logger->error("Can't swap designations $@");
						$self->{'db'}->rollback;
					} else {
						$self->{'db'}->commit;
						$self->update_history($id,"$locus: designation '$to_be_promoted->{'allele_id'}' promoted from pending (designation '$to_be_demoted->{'allele_id'}' demoted to pending)");
						
					}
				}
			} elsif ( $q->param("$pk\_delete") ) {
				eval {
					$self->{'db'}->do(
"DELETE FROM pending_allele_designations WHERE isolate_id='$id' AND locus='$locus' AND allele_id='$allele->{'allele_id'}' AND sender='$allele->{'sender'}' AND method='$allele->{'method'}'"
					);
				};
				if ($@) {
					$logger->error("Can't delete pending designation $@");
					$self->{'db'}->rollback;
				} else {
					$self->{'db'}->commit;
					$self->update_history($id,"$locus: pending designation '$allele->{'allele_id'}' deleted");
					
				}
			}
		}
	}
	$right_buffer .= $self->_get_allele_designation_form( $id, $locus );

#only allow pending designations to be added if a main designation already exists
	my $exists = $self->{'datastore'}->run_simple_query(
"SELECT COUNT(*) FROM allele_designations WHERE isolate_id=? AND locus=?",
		$id, $locus
	)->[0];
	my $pending_count = $self->{'datastore'}->run_simple_query(
"SELECT COUNT(*) FROM pending_allele_designations WHERE isolate_id=? AND locus=?",
		$id, $locus
	)->[0];
	if ( $exists ) {
		if ( $pending_count ) {
			$right_buffer .= "<h3>Pending designations";
			$right_buffer .=
" <a class=\"tooltip\" title=\"Pending designations - These are provisional designations that may have been generated by automatic scripts.  Their presence may be indicated on the web interface but they are not used in any analyses.<p />Pending designations may be promoted to selected designations. In this case existing designations will be demoted to pending designations.\">&nbsp;<i>i</i>&nbsp;</a>";
			$right_buffer .= "</h3>\n";
			my $qry =
"SELECT * FROM pending_allele_designations WHERE isolate_id=? AND locus=? ORDER BY datestamp";
			my $sql = $self->{'db'}->prepare($qry);
			eval { $sql->execute( $id, $locus ); };
			if ($@) {
				$logger->error("Can't execute $qry: values: $id, $locus");
			}
			$right_buffer .= $q->start_form;
			$right_buffer .=
"<table class=\"resultstable\"><tr><th>Promote</th><th>Delete</th><th>Allele</th><th>More</th><th>Sender</th><th>Method</th><th>Datestamp</th></tr>\n";
			my $td = 1;
			while ( my $allele = $sql->fetchrow_hashref() ) {
				my $update_details_tooltip =
				  $self->get_update_details_tooltip( $locus, $allele );
				$right_buffer .= "<tr class=\"td$td\"><td>";
				my $pk =
"$allele->{'allele_id'}\_$allele->{'sender'}\_$allele->{'method'}";
				$right_buffer .= $q->submit(
					-name  => "$pk\_promote",
					-label => 'Promote',
					-class => 'smallbutton'
				);
				$right_buffer .= "</td><td>\n";
				$right_buffer .= $q->submit(
					-name  => "$pk\_delete",
					-label => 'Delete',
					-class => 'smallbutton'
				);
				$right_buffer .= "</td><td>$allele->{'allele_id'}</td>";
				$right_buffer .=
"<td><a class=\"update_tooltip\" title=\"$update_details_tooltip\">&nbsp;...&nbsp;</a></td>";
				my $sender =
				  $self->{'datastore'}->get_user_info( $allele->{'sender'} );
				$right_buffer .=
				  "<td>$sender->{'first_name'} $sender->{'surname'}</td>";
				$right_buffer .= "<td>$allele->{'method'}</td>";
				$right_buffer .= "<td>$allele->{'datestamp'}</td>";
				$right_buffer .= "</tr>\n";
				$td = $td == 1 ? 2 : 1;
			}
			$right_buffer .= "</table>\n";
			$q->param( 'isolate_id',    $id );
			$q->param( 'sent2', 1 );
			foreach (qw (page db isolate_id locus sent2)) {
				$right_buffer .= $q->hidden($_);
			}
			$right_buffer .= $q->endform;
			$right_buffer .= "<p />";
			$right_buffer .= $new_pending_problems;
		}
		$right_buffer .= "<h3>Add new pending designation";
		$right_buffer .=
" <a class=\"tooltip\" title=\"Pending designations - These are provisional designations that may have been generated by automatic scripts.  Their presence may be indicated on the web interface but they are not used in any analyses.<p />Pending designations may be promoted to selected designations. In this case existing designations will be demoted to pending designations.\">&nbsp;<i>i</i>&nbsp;</a>"
		  if !$pending_count;
		$right_buffer .= "</h3>\n";
		$right_buffer .= $new_pending_problems if !$pending_count;
		if ($clear_pad) {
			foreach (qw (allele_id sender method comments)) {
				$q->param( "pending_allele_designations_$_", '' );
			}
		}
		$right_buffer .=
		  $self->_get_new_pending_designation_form( $id, $locus );
	} 
	print "<div class=\"box\" id=\"resultstable\">\n";
	print "<table><tr><td style=\"vertical-align:top\">\n";
	print "<h2>Isolate summary:</h2>\n";
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
			'curate'        => 1
		)
	);
	print $isolate_record->get_isolate_summary( $id, 1 );
	print "<h2>Update other loci:</h2>\n";
	print $q->start_form;
	my $loci = $self->{'datastore'}->get_loci(1);
	print "Locus: ";
	print $q->popup_menu(-name=>'locus',-values=>$loci);
	print $q->submit(-label=>'Add/update',-class=>'submit');
	$q->param( 'isolate_id',$id);
	foreach (qw(db page isolate_id)){
		print $q->hidden($_);
	}
	print $q->end_form;
	print "</td><td style=\"vertical-align:top; padding-left:2em\">";
	print $right_buffer;
	print "</td></tr></table>\n";
	print "</div>\n";
}

sub _get_allele_designation_form {
	my ( $self, $isolate_id, $locus ) = @_;
	my $attributes =
	  $self->{'datastore'}->get_table_field_attributes('allele_designations');
	my $allele =
	  $self->{'datastore'}->get_allele_designation( $isolate_id, $locus );
	my $buffer;
	if ( ref $allele eq 'HASH' ) {
		$buffer =
		  $self->create_record_table( 'allele_designations', $allele, 1, 1,
			1 );
	} else {
		my $datestamp = $self->get_datestamp();
		$allele = {
			'isolate_id'   => $isolate_id,
			'locus'        => $locus,
			'date_entered' => $datestamp
		};
		$buffer =
		  $self->create_record_table( 'allele_designations', $allele, 0, 1,
			1 );
	}
	return $buffer;
}

sub _get_new_pending_designation_form {
	my ( $self, $isolate_id, $locus ) = @_;
	my $buffer;
	my $datestamp = $self->get_datestamp();
	my $allele    = {
		'isolate_id'   => $isolate_id,
		'locus'        => $locus,
		'date_entered' => $datestamp
	};
	$buffer =
	  $self->create_record_table( 'pending_allele_designations', $allele, 0, 1,
		1, 1 );
	return $buffer;
}

sub get_title {
	my ($self)   = @_;
	my $desc  = $self->{'system'}->{'description'} || 'BIGSdb';
	my $q     = $self->{'cgi'};
	my $locus = $q->param('locus');
	my $id    = $q->param('id');
	return "Update $locus allele for isolate $id - $desc";
}
1;


