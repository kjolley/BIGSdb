#RuleQuery.pm - Plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2012-2017, University of Oxford
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
use parent qw(BIGSdb::Plugin);
use List::MoreUtils qw(uniq);
use Error qw(:try);
use BIGSdb::Utils;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');

sub get_attributes {
	my ($self) = @_;
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
		version          => '1.1.0',
		dbtype           => 'sequences',
		seqdb_type       => 'sequences',
		section          => '',
		url              => "$self->{'config'}->{'doclink'}/administration.html#rule-based-sequence-queries",
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
		next if $file !~ /\.rule$/x;
		( my $id = $file ) =~ s/\.rule$//x;
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
		say q(<div class="box" id="statusbad">No rulesets have been defined for this database.</p></div>);
		return;
	}
	my $ruleset_id = $q->param('ruleset');
	if ( defined $ruleset_id ) {
		if ( !defined $rulesets->{$ruleset_id} ) {
			say q(<div class="box" id="statusbad"><p>Ruleset is not defined.</p></div>);
			return;
		}
	}
	say $ruleset_id ? qq(<h1>$rulesets->{$ruleset_id}->{'description'}</h1>) : q(<h1>Sequence query</h1>)
	  if !$q->param('data');
	my $sequence = $q->param('sequence');
	$q->delete('sequence');
	my $valid_DNA = 1;
	if ($sequence) {
		if ( !defined $ruleset_id ) {
			say q(<div class="box statusbad"><p>Please select a ruleset</p></div>);
		} else {
			if ( !BIGSdb::Utils::is_valid_DNA( \$sequence, { allow_ambiguous => 1 } ) ) {
				say q(<div class="box statusbad"><p>The sequence is not valid DNA.</p></div>);
				$valid_DNA = 0;
			}
		}
		my $temp = BIGSdb::Utils::get_random();
		my $file = "$self->{'config'}->{'tmp_dir'}/$temp.seq";
		$q->param( upload_file => "$temp.seq" );
		open( my $fh, '>', $file ) || $logger->error("Can't open $file for writing");
		say $fh $sequence;
		close $fh;
	} elsif ( $q->param('fasta_upload') ) {
		my $upload_file = $self->_upload_fasta_file;
		$q->param( upload_file => $upload_file );
	}
	if ( ( $sequence || $q->param('upload_file') ) && $ruleset_id && $valid_DNA ) {
		my $params = $q->Vars;
		$params->{'rule_path'} = $rulesets->{$ruleset_id}->{'path'};
		my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
		my $job_id    = $self->{'jobManager'}->add_job(
			{
				dbase_config => $self->{'instance'},
				ip_address   => $q->remote_host,
				module       => 'RuleQuery',
				parameters   => $params,
				username     => $self->{'username'},
				email        => $user_info->{'email'},
			}
		);
		say $self->get_job_redirect($job_id);
		return;
	}
	$self->_print_interface( $rulesets, $ruleset_id );
	return;
}

sub _upload_fasta_file {
	my ($self)   = @_;
	my $temp     = BIGSdb::Utils::get_random();
	my $filename = "$self->{'config'}->{'tmp_dir'}/${temp}_upload.fas";
	my $buffer;
	open( my $fh, '>', $filename ) || $logger->error("Could not open $filename for writing.");
	my $fh2 = $self->{'cgi'}->upload('fasta_upload');
	binmode $fh2;
	binmode $fh;
	read( $fh2, $buffer, $self->{'config'}->{'max_upload_size'} );
	print $fh $buffer;
	close $fh;
	return "${temp}_upload.fas";
}

sub _print_interface {
	my ( $self, $rulesets, $ruleset_id ) = @_;
	my $q = $self->{'cgi'};
	say q(<div class="box queryform">);
	print $q->start_form;
	if ( defined $ruleset_id ) {
		my $rule_description =
		  "$self->{'system'}->{'dbase_config_dir'}/$self->{'instance'}/rules/$ruleset_id/description.html";
		if ( -e $rule_description ) {
			$self->print_file($rule_description);
		}
	} else {
		$self->_select_ruleset($rulesets);
	}
	say q(<div><fieldset style="float:left"><legend>Enter query sequence )
	  . q((single or multiple contigs up to whole genome in size)</legend>);
	say $q->textarea( -name => 'sequence', -rows => 6, -cols => 70 );
	say q(</fieldset>);
	say q(<fieldset style="float:left"><legend>Alternatively upload FASTA file</legend>);
	say q(Select FASTA file:<br />);
	say $q->filefield( -name => 'fasta_upload', -id => 'fasta_upload', -size => 10, -maxlength => 512 );
	say q(</fieldset>);
	$self->print_action_fieldset( { name => 'RuleQuery', ruleset => $ruleset_id } );
	say q(</div>);
	say $q->hidden($_) foreach qw(db page name ruleset);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _select_ruleset {
	my ( $self, $rulesets ) = @_;
	my $q = $self->{'cgi'};
	say q(<fieldset><legend>Please select ruleset</legend>);
	my ( @ids, %labels );
	foreach my $ruleset_id ( sort { $a cmp $b } keys %$rulesets ) {
		my $ruleset = $rulesets->{$ruleset_id};
		push @ids, $ruleset_id;
		$labels{$ruleset_id} = $ruleset->{'description'};
	}
	say q(<label for="ruleset">Ruleset: </label>);
	say $q->popup_menu( -name => 'ruleset', -id => 'ruleset', -values => [ '', @ids ], -labels => \%labels );
	say q(</fieldset>);
	return;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	my $sequence = '';
	my @input =
	  ( $params->{'fasta_upload'} ? 'Uploaded file: ' . $params->{'fasta_upload'} : 'Pasted sequence' );
	if ( $params->{'sequence'} ) {
		$sequence = $params->{'sequence'};
	} elsif ( $params->{'upload_file'} ) {
		my $file    = "$self->{'config'}->{'tmp_dir'}/$params->{'upload_file'}";
		my $seq_ref = BIGSdb::Utils::slurp($file);
		$sequence = $$seq_ref;
	}
	$self->{'sequence'} = \$sequence;
	my $length = BIGSdb::Utils::commify( length $sequence );
	push @input, "Sequence length: $length bp";
	my $input_text = q(<h3 style="border-bottom:none">Sample</h3><ul>);
	$input_text .= qq(<li>$_</li>) foreach @input;
	$input_text .= q(</ul>);
	$self->{'jobManager'}->update_job_status( $job_id, { 'message_html' => $input_text } );
	$self->{'html'}   = $input_text;
	$self->{'job_id'} = $job_id;
	my $code_ref = $self->_read_code( $params->{'rule_path'} );

	if ( ref $code_ref eq 'SCALAR' ) {
		eval "$$code_ref";    ## no critic (ProhibitStringyEval)
	}
	$logger->error($@) if $@;
	return;
}

sub _get_blast_object {
	my ( $self, $loci ) = @_;
	local $" = q(,);
	my $exemplar = ( $self->{'system'}->{'exemplars'} // q() ) eq 'yes' ? 1 : 0;
	$exemplar = 0 if @$loci == 1;
	my $blast_obj = BIGSdb::Offline::Blast->new(
		{
			config_dir       => $self->{'config_dir'},
			lib_dir          => $self->{'lib_dir'},
			dbase_config_dir => $self->{'dbase_config_dir'},
			host             => $self->{'system'}->{'host'},
			port             => $self->{'system'}->{'port'},
			user             => $self->{'system'}->{'user'},
			password         => $self->{'system'}->{'password'},
			options          => {
				l          => qq(@$loci),
				always_run => 1,
				exemplar   => $exemplar,
			},
			instance => $self->{'instance'},
			logger   => $logger
		}
	);
	return $blast_obj;
}

sub _read_code {
	my ( $self, $rule_path ) = @_;
	open( my $fh, '<', $rule_path ) || $logger->error("Can't open $rule_path for reading");
	my $code;
	my $line_number;
	while ( my $line = <$fh> ) {
		$line_number++;

		#Prevent system calls (inc. backticks) and direct access to db
		#(need to stop $self->{'db'}, $self->{"db"}, $self->{qw ( db )} etc.)
		if (   $line =~ /^([\w_\-&\.,;:\|\$\@\%#'"\/\\\(\){}\[\]=<>\*\+\s\?~]*)$/x
			&& $line !~ /system/x
			&& $line !~ /[\W\s]+db[\W\s]+/x )
		{
			$line = $1;
			foreach my $command (
				qw(scan_locus scan_scheme scan_group append_html get_scheme_html get_client_field update_status
				get_locus_info)
			  )
			{
				$line =~ s/$command/\$self->_$command/gx;
			}
			$line =~ s/\$results/\$self->{'results'}/gx;
			$line =~ s/<h1>/<h3 style=\\"border-bottom:none\\">/gx;
			$line =~ s/<\/h1>/<\/h3>/gx;
			$code .= $line;
		} else {
			$logger->error("Line $line_number: \"$line\" rejected.  Script terminated.");
			return;
		}
	}
	close $fh;
	return \$code;
}

sub _get_locus_info {    ## no critic (ProhibitUnusedPrivateSubroutines) #Can be called by rule file.
	my ( $self, $locus ) = @_;
	return $self->{'datastore'}->get_locus_info($locus);
}

sub _scan_locus {        ## no critic (ProhibitUnusedPrivateSubroutines) #Can be called by rule file.
	my ( $self, $locus ) = @_;
	if ( !$self->{'datastore'}->is_locus($locus) ) {
		$logger->error("Invalid locus $locus");
		return;
	}
	my $blast_obj = $self->_get_blast_object( [$locus] );
	$blast_obj->blast( $self->{'sequence'} );
	my $exact_matches = $blast_obj->get_exact_matches;
	$self->{'results'}->{'locus'}->{$locus} = $exact_matches->{$locus}->[0]
	  if ref $exact_matches->{$locus};    #only use first match
	return;
}

sub _scan_scheme {
	my ( $self, $scheme_id ) = @_;
	my $set_id      = $self->get_set_id;
	my $scheme_loci = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $blast_obj   = $self->_get_blast_object($scheme_loci);
	$blast_obj->blast( $self->{'sequence'} );
	my $exact_matches = $blast_obj->get_exact_matches;
	foreach my $locus (@$scheme_loci) {
		my $locus_matches = $exact_matches->{$locus};
		next if !$locus_matches;
		if ( @{$locus_matches} ) {
			$self->{'results'}->{'locus'}->{$locus} = $locus_matches->[0];
		}
	}
	my @profiles;
	my $missing_data = 0;
	foreach my $locus (@$scheme_loci) {
		if ( defined $self->{'results'}->{'locus'}->{$locus} ) {
			push @profiles, $self->{'results'}->{'locus'}->{$locus};
		} else {
			$missing_data = 1;
			last;
		}
	}
	if ( !$missing_data ) {
		my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
		my @placeholders;
		push @placeholders, '?' foreach (@$scheme_loci);
		if ( @$scheme_fields && $scheme_loci ) {
			local $" = ',';
			my $field_values = $self->{'datastore'}->run_query(
				"SELECT @$scheme_fields FROM mv_scheme_$scheme_id WHERE profile=?",
				BIGSdb::Utils::get_pg_array( \@profiles ),
				{ fetch => 'row_hashref' }
			);
			foreach my $field (@$scheme_fields) {
				$self->{'results'}->{'scheme'}->{$scheme_id}->{$field} = $field_values->{ lc($field) }
				  if defined $field_values->{ lc($field) };
			}
		}
	}
	return;
}

sub _scan_group {    ## no critic (ProhibitUnusedPrivateSubroutines) #Can be called by rule file.
	my ( $self, $group_id ) = @_;
	my @groups = $group_id;
	push @groups, @{ $self->_get_child_groups($group_id) };
	foreach my $group (@groups) {
		my $group_schemes =
		  $self->{'datastore'}->run_query( 'SELECT scheme_id FROM scheme_group_scheme_members WHERE group_id=?',
			$group, { fetch => 'col_arrayref' } );
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
			  $self->{'datastore'}
			  ->run_query( 'SELECT group_id FROM scheme_group_group_members WHERE parent_group_id=?',
				$group, { fetch => 'col_arrayref' } );
			push @temp_groups, @$groups;
		}
		last if !@temp_groups;
		@groups_to_test = @temp_groups;
		push @child_groups, @temp_groups;
	}
	@child_groups = uniq @child_groups;
	return \@child_groups;
}

sub _append_html {    ## no critic (ProhibitUnusedPrivateSubroutines) #Can be called by rule file.
	my ( $self, $text ) = @_;
	$self->{'html'} .= "$text\n";
	$self->{'jobManager'}->update_job_status( $self->{'job_id'}, { 'message_html' => $self->{'html'} } );
	return;
}

sub _update_status {    ## no critic (ProhibitUnusedPrivateSubroutines) #Can be called by rule file.
	my ( $self, $status_hash ) = @_;
	return if ref $status_hash ne 'HASH';
	$self->{'jobManager'}->update_job_status( $self->{'job_id'}, $status_hash );
	return;
}

sub _get_scheme_html {    ## no critic (ProhibitUnusedPrivateSubroutines) #Can be called by rule file.
	my ( $self, $scheme_id, $options ) = @_;
	$options = { table => 1, fields => 1, loci => 1 } if ref $options ne 'HASH';
	my $fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $loci   = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $buffer = '';
	if ( $options->{'table'} ) {
		local $" = q(</th><th>);
		$buffer .= q(<table class="resultstable"><tr>);
		$buffer .= qq(<th>@$loci</th>) if @$loci && $options->{'loci'};
		$buffer .= qq(<th>@$fields</th>) if @$fields && $options->{'fields'};
		$buffer .= q(</tr><tr class="td1">);
		if ( $options->{'loci'} ) {
			foreach my $locus (@$loci) {
				my $value = $self->{'results'}->{'locus'}->{$locus} // '-';
				$buffer .= qq(<td>$value</td>);
			}
		}
		if ( $options->{'fields'} ) {
			foreach my $field (@$fields) {
				my $value = $self->{'results'}->{'scheme'}->{$scheme_id}->{$field} // '-';
				$buffer .= qq(<td>$value</td>);
			}
		}
		$buffer .= qq(</tr></table>\n);
	} else {
		$buffer .= q(<ul>) if $options->{'loci'} || $options->{'fields'};
		if ( @$loci && $options->{'loci'} ) {
			foreach my $locus (@$loci) {
				my $value = $self->{'results'}->{'locus'}->{$locus} // '-';
				$buffer .= qq(<li>$locus: $value</li>\n);
			}
		}
		if ( @$fields && $options->{'fields'} ) {
			foreach my $field (@$fields) {
				my $value = $self->{'results'}->{'scheme'}->{$scheme_id}->{$field} // '-';
				$buffer .= qq(<li>$field: $value</li>);
			}
		}
		$buffer .= q(</ul>) if $options->{'loci'} || $options->{'fields'};
	}
	return $buffer;
}

sub _get_client_field {    ## no critic (ProhibitUnusedPrivateSubroutines) #Can be called by rule file.
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
