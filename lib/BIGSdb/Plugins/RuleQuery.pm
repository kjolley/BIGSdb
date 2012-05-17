#RuleQuery.pm - Plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2012, University of Oxford
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
package BIGSdb::Plugins::RuleQuery;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin BIGSdb::SequenceQueryPage);
use List::MoreUtils qw(uniq);
use Error qw(:try);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my %att = (
		name             => 'Rule Query',
		author           => 'Keith Jolley',
		affiliation      => 'University of Oxford, UK',
		email            => 'keith.jolley@zoo.ox.ac.uk',
		description      => 'Rule-based sequence scanning and reporting',
		menu_description => 'Rule-based reporting.',
		category         => 'Analysis',
		menutext         => 'Rule Query',
		module           => 'RuleQuery',
		version          => '1.0.0',
		dbtype           => 'sequences',
		seqdb_type       => 'sequences',
		section          => '',
		url              => 'http://pubmlst.org/software/database/bigsdb/administration/rule_based_query.shtml',
		requires         => 'offline_jobs',
		order            => 15
	);
	return \%att;
}

sub _get_defined_rules {
	my ($self) = @_;
	my $rule_dir = "$self->{'system'}->{'dbase_config_dir'}/$self->{'instance'}/rules";
	opendir( my $dir, $rule_dir ) || $logger->error("Can't open $rule_dir for reading");
	my $rulesets;
	while ( my $file = readdir($dir) ) {
		next if $file !~ /\.rule$/;
		( my $id = $file ) =~ s/\.rule$//;
		$id =~ tr/ /_/;
		( my $desc = $id ) =~ tr/_/ /;
		my %ruleset = ( path => "$rule_dir/$file", description => $desc );
		$rulesets->{$id} = \%ruleset;
	}
	closedir($dir);
	return $rulesets;
}

sub run {
	my ($self)   = @_;
	my $q        = $self->{'cgi'};
	my $rulesets = $self->_get_defined_rules;
	if ( !$rulesets ) {
		print "<div class=\"box\" id=\"statusbad\">No rulesets have been defined for this database.</p></div>\n";
		return;
	}
	my $ruleset_id = $q->param('ruleset');
	if ( defined $ruleset_id ) {
		if ( !defined $rulesets->{$ruleset_id} ) {
			print "<div class=\"box\" id=\"statusbad\"><p>Ruleset is not defined.</p></div>\n";
			return;
		}
	}
	print $ruleset_id ? "<h1>$rulesets->{$ruleset_id}->{'description'}</h1>\n" : "<h1>Sequence query</h1>\n" if !$q->param('data');
	my $sequence = $q->param('sequence');
	$self->remove_all_identifier_lines( \$sequence ) if $sequence;
	my $valid_DNA = 1;
	if ($sequence) {
		if ( !defined $ruleset_id ) {
			print "<div class=\"box statusbad\"><p>Please select a ruleset</p></div>\n";
		} else {
			if ( !BIGSdb::Utils::is_valid_DNA( \$sequence, { allow_ambiguous => 1 } ) ) {
				print "<div class=\"box statusbad\"><p>The sequence is not valid DNA.</p></div>\n";
				$valid_DNA = 0;
			}
		}
	}
	if ( $sequence && $ruleset_id && $valid_DNA ) {
		my $params = $q->Vars;
		$params->{'rule_path'} = $rulesets->{$ruleset_id}->{'path'};
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		my $job_id    = $self->{'jobManager'}->add_job(
			{
				'dbase_config' => $self->{'instance'},
				'ip_address'   => $q->remote_host,
				'module'       => 'RuleQuery',
				'parameters'   => $params,
				'username'     => $self->{'username'},
				'email'        => $user_info->{'email'},
			}
		);
		print <<"HTML";
<div class="box" id="resultstable">
<p>This analysis has been submitted to the job queue.</p>
<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=job&amp;id=$job_id">
Follow the progress of this job and view the output.</a></p> 	
</div>	
HTML
		return;
	}
	$self->_print_interface( $rulesets, $ruleset_id );
	return;
}

sub _print_interface {
	my ( $self, $rulesets, $ruleset_id ) = @_;
	my $q = $self->{'cgi'};
	print "<div class=\"box queryform\">\n";
	print $q->start_form;
	if ( defined $ruleset_id ) {
		my $rule_description = "$self->{'system'}->{'dbase_config_dir'}/$self->{'instance'}/rules/$ruleset_id/description.html";
		if ( -e $rule_description ) {
			$self->print_file($rule_description);
		}
	} else {
		$self->_select_ruleset($rulesets);
	}
	print "<div><fieldset><legend>Enter query sequence (single or multiple contigs up to whole genome in size)</legend>\n";
	print $q->textarea( -name => 'sequence', -rows => 6, -cols => 70 );
	print "</fieldset>\n</div>\n<span style=\"float:left\">";
	print $q->reset( -label => 'Reset', -class => 'reset' );
	print "</span><span style=\"float:right;padding-right:5em\">\n";
	print $q->submit( -label => 'Submit', -class => 'submit' );
	print "</span>\n<div style=\"clear:both\"></div>\n";
	print $q->hidden($_) foreach qw(db page name ruleset);
	print $q->end_form;
	print "</div>\n";
	return;
}

sub _select_ruleset {
	my ( $self, $rulesets ) = @_;
	my $q = $self->{'cgi'};
	print "<fieldset><legend>Please select ruleset</legend>";
	my ( @ids, %labels );
	foreach my $ruleset_id ( sort { $a cmp $b } keys %$rulesets ) {
		my $ruleset = $rulesets->{$ruleset_id};
		push @ids, $ruleset_id;
		$labels{$ruleset_id} = $ruleset->{'description'};
	}
	print "<label for=\"ruleset\">Ruleset: </label>\n";
	print $q->popup_menu( -name => 'ruleset', -id => 'ruleset', -values => [ '', @ids ], -labels => \%labels );
	print "</fieldset>\n";
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->remove_all_identifier_lines( \$params->{'sequence'} );
	$self->{'sequence'} = \$params->{'sequence'};
	$self->{'job_id'}   = $job_id;
	my $code_ref = $self->_read_code( $params->{'rule_path'} );
	if ( ref $code_ref eq 'SCALAR' ) {
		eval "$$code_ref";    ## no critic (ProhibitStringyEval)
	}
	if ($@) {
		$logger->error($@);
	}

	#DEBUGGING#
	#	use autouse 'Data::Dumper' => qw(Dumper);
	#	$self->{'html'} .= "<pre>" . Dumper( $self->{'results'} ) . "</pre>";
	#	$self->{'jobManager'}->update_job_status( $job_id, { 'message_html' => $self->{'html'} } );
	#END#######
	return;
}

sub _read_code {
	my ( $self, $rule_path ) = @_;
	open( my $fh, '<', $rule_path ) || $logger->error("Can't open $rule_path for reading");
	my $code;
	my $line_number;
	while ( my $line = <$fh> ) {
		$line_number++;
		if ( $line =~ /^([\w_\-&\.,;:\|\$\@\%#'"\/\\\(\){}\[\]=<>\*\+\s\?~]*)$/ && $line !~ /system/ && $line !~ /[\W\s]+db[\W\s]+/ )
		{ #prevent system calls (inc. backticks) and direct access to db (need to stop $self->{'db'}, $self->{"db"}, $self->{qw ( db )} etc.)
			$line = $1;
			foreach my $command (
				qw(scan_locus scan_scheme scan_group append_html get_scheme_html get_client_field update_status
				get_locus_info)
			  )
			{
				$line =~ s/$command/\$self->_$command/g;
			}
			$line =~ s/\$results/\$self->{'results'}/g;
			$line =~ s/<h1>/<h3 style=\\"border-bottom:none\\">/g;
			$line =~ s/<\/h1>/<\/h3>/g;
			$code .= $line;
		} else {
			$logger->error("Line $line_number: \"$line\" rejected.  Script terminated.");
			return;
		}
	}
	close $fh;
	return \$code;
}

sub _get_locus_info {
	my ( $self, $locus ) = @_;
	return $self->{'datastore'}->get_locus_info($locus);
}

sub _scan_locus {
	my ( $self, $locus ) = @_;
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		$logger->error("Invalid locus $locus");
		return;
	}
	( my $blast_file, undef ) =
	  $self->run_blast( { locus => $locus, seq_ref => $self->{'sequence'}, qry_type => 'DNA', num_results => 5, cache => 0 } );
	my $exact_matches = $self->parse_blast_exact( $locus, $blast_file );
	$self->{'results'}->{'locus'}->{$locus} = $exact_matches->[0]->{'allele'} if @$exact_matches;    #only use first match
	return;
}

sub _scan_scheme {
	my ( $self, $scheme_id ) = @_;
	( my $blast_file, undef ) = $self->run_blast(
		{ locus => "SCHEME_$scheme_id", seq_ref => $self->{'sequence'}, qry_type => 'DNA', num_results => 50000, cache => 0 } );
	my $exact_matches = $self->parse_blast_exact( "SCHEME_$scheme_id", $blast_file );
	my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my ( %locus_assigned, %allele );
	foreach my $match (@$exact_matches) {
		foreach my $locus (@$scheme_loci) {
			next if $locus_assigned{$locus};
			my $locus_info = $self->{'datastore'}->get_locus_info($locus);
			my $regex;
			if ( $locus_info->{'allele_id_regex'} ) {
				$regex = $locus_info->{'allele_id_regex'};
			} else {
				$regex = $locus_info->{'allele_id_format'} eq 'integer' ? '\d+' : '.+';
			}
			if ( $match->{'allele'} =~ /^$locus:(.+)/ ) {
				my $allele_id = $1;
				if ( $allele_id =~ /$regex/ ) {
					$match->{'allele'}                      = $allele_id;
					$allele{$locus}                         = $allele_id;
					$self->{'results'}->{'locus'}->{$locus} = $allele_id;
					$locus_assigned{$locus}                 = 1;
					last;
				}
			}
		}
	}
	my @profiles;
	my $missing_data = 0;
	foreach my $locus (@$scheme_loci) {
		my $allele_id = $allele{$locus};
		if ( defined $allele_id ) {
			push @profiles, $allele_id;
		} else {
			$missing_data = 1;
			last;
		}
	}
	if ( !$missing_data ) {
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		my $scheme_loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
		my @placeholders;
		push @placeholders, '?' foreach (@$scheme_loci);
		if ( @$scheme_fields && $scheme_loci ) {
			local $" = ',';
			my $field_values =
			  $self->{'datastore'}
			  ->run_simple_query_hashref( "SELECT @$scheme_fields FROM scheme_$scheme_id WHERE (@$scheme_loci) = (@placeholders)",
				@profiles );
			foreach my $field (@$scheme_fields) {
				$self->{'results'}->{'scheme'}->{$scheme_id}->{$field} = $field_values->{ lc($field) }
				  if defined $field_values->{ lc($field) };
			}
		}
	}
	return;
}

sub _scan_group {
	my ( $self, $group_id ) = @_;
	my @groups = $group_id;
	push @groups, @{ $self->_get_child_groups($group_id) };
	foreach my $group (@groups) {
		my $group_schemes =
		  $self->{'datastore'}->run_list_query( "SELECT scheme_id FROM scheme_group_scheme_members WHERE group_id=?", $group );
		foreach my $scheme_id (@$group_schemes) {
			$self->_scan_scheme( $scheme_id, $self->{'sequence'} );
		}
	}
	return;
}

sub _get_child_groups {
	my ( $self, $group_id ) = @_;
	my @child_groups;
	my @groups_to_test = $group_id;
	while (1) {
		my @temp_groups;
		foreach my $group (@groups_to_test) {
			my $groups =
			  $self->{'datastore'}->run_list_query( "SELECT group_id FROM scheme_group_group_members WHERE parent_group_id=?", $group );
			push @temp_groups, @$groups;
		}
		last if !@temp_groups;
		@groups_to_test = @temp_groups;
		push @child_groups, @temp_groups;
	}
	@child_groups = uniq @child_groups;
	return \@child_groups;
}

sub _append_html {
	my ( $self, $text ) = @_;
	$self->{'html'} .= "$text\n";
	$self->{'jobManager'}->update_job_status( $self->{'job_id'}, { 'message_html' => $self->{'html'} } );
	return;
}

sub _update_status {
	my ( $self, $status_hash ) = @_;
	return if ref $status_hash ne 'HASH';
	$self->{'jobManager'}->update_job_status( $self->{'job_id'}, $status_hash );
	return;
}

sub _get_scheme_html {
	my ( $self, $scheme_id, $options ) = @_;
	$options = { table => 1, fields => 1, loci => 1 } if ref $options ne 'HASH';
	my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $buffer = '';
	if ( $options->{'table'} ) {
		local $" = "</th><th>";
		$buffer .= "<table class=\"resultstable\"><tr>";
		$buffer .= "<th>@$loci</th>" if @$loci && $options->{'loci'};
		$buffer .= "<th>@$fields</th>" if @$fields && $options->{'fields'};
		$buffer .= "</tr>\n<tr class=\"td1\">";
		if ( $options->{'loci'} ) {
			foreach my $locus (@$loci) {
				my $value = $self->{'results'}->{'locus'}->{$locus} // '-';
				$buffer .= "<td>$value</td>";
			}
		}
		if ( $options->{'fields'} ) {
			foreach my $field (@$fields) {
				my $value = $self->{'results'}->{'scheme'}->{$scheme_id}->{$field} // '-';
				$buffer .= "<td>$value</td>";
			}
		}
		$buffer .= "</tr></table>\n";
	} else {
		$buffer .= "<ul>" if $options->{'loci'} || $options->{'fields'};
		if ( @$loci && $options->{'loci'} ) {
			foreach my $locus (@$loci) {
				my $value = $self->{'results'}->{'locus'}->{$locus} // '-';
				$buffer .= "<li>$locus: $value</li>\n";
			}
		}
		if ( @$fields && $options->{'fields'} ) {
			foreach my $field (@$fields) {
				my $value = $self->{'results'}->{'scheme'}->{$scheme_id}->{$field} // '-';
				$buffer .= "<li>$field: $value</li>";
			}
		}
		$buffer .= "</ul>" if $options->{'loci'} || $options->{'fields'};
	}
	return $buffer;
}

sub _get_client_field {
	my ( $self, $client_db_id, $locus, $field, $options ) = @_;
	return if !BIGSdb::Utils::is_int( $client_db_id // '' );
	$options = {} if ref $options ne 'HASH';
	my $client = $self->{'datastore'}->get_client_db($client_db_id);
	my $value  = $self->{'results'}->{'locus'}->{$locus};
	return if !defined $value;
	my $field_data;
	my $proceed = 1;
	try {
		$field_data = $client->get_fields( $field, $locus, $self->{'results'}->{'locus'}->{$locus} );
	}
	catch BIGSdb::DatabaseConfigurationException with {
		my $ex = shift;
		$logger->error($ex);
		$proceed = 0;
	};
	return if !$proceed;
	my $total = 0;
	$total += $_->{'frequency'} foreach @$field_data;
	foreach my $data (@$field_data) {
		$data->{'percentage'} = BIGSdb::Utils::decimal_place( 100 * $data->{'frequency'} / $total, 1 );
	}
	if ( $options->{'min_percentage'} ) {
		return $self->_filter_min_percentage( $field_data, $options->{'min_percentage'} );
	}
	return $field_data;
}

sub _filter_min_percentage {
	my ( $self, $field_data, $min_percentage ) = @_;
	return $field_data if !BIGSdb::Utils::is_int($min_percentage);
	my @new_data;
	foreach my $data (@$field_data) {
		push @new_data, $data if $data->{'percentage'} >= $min_percentage;
	}
	return \@new_data;
}
1;
