#Contigs.pm - Contig export and analysis plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2013-2018, University of Oxford
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
package BIGSdb::Plugins::Contigs;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Plugin);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use List::MoreUtils qw(any none);
use Archive::Tar;
use Archive::Tar::Constant;
use constant MAX_ISOLATES => 1000;
use List::MoreUtils qw(uniq);
use BIGSdb::Constants qw(SEQ_METHODS);

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name         => 'Contig export',
		author       => 'Keith Jolley',
		affiliation  => 'University of Oxford, UK',
		email        => 'keith.jolley@zoo.ox.ac.uk',
		description  => 'Analyse and export contigs selected from query results',
		category     => 'Export',
		buttontext   => 'Contigs',
		menutext     => 'Contigs',
		module       => 'Contigs',
		url          => "$self->{'config'}->{'doclink'}/data_export.html#contig-export",
		version      => '1.1.4',
		dbtype       => 'isolates',
		section      => 'export,postquery',
		input        => 'query',
		help         => 'tooltips',
		order        => 20,
		system_flag  => 'ContigExport',
		tar_filename => 'contigs.tar'
	);
	return \%att;
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 1 };
	return;
}

sub _get_contigs {
	my ( $self, $args ) = @_;
	my ( $isolate_id, $pc_untagged, $match ) = @{$args}{qw (isolate_id pc_untagged match  )};
	my $buffer;
	if ( !defined $isolate_id || !BIGSdb::Utils::is_int($isolate_id) ) {
		say q(Invalid isolate id passed.);
	}
	$pc_untagged //= 0;
	if ( !defined $pc_untagged || !BIGSdb::Utils::is_int($pc_untagged) ) {
		say q(Invalid percentage tagged threshold value passed.);
		return;
	}
	my $data = $self->_calculate( $isolate_id, { pc_untagged => $pc_untagged, get_contigs => 1 } );
	my $export_seq = $match ? $data->{'match_seq'} : $data->{'non_match_seq'};
	if ( !@$export_seq ) {
		say q(No sequences matching selected criteria.);
		return;
	}
	foreach (@$export_seq) {
		$buffer .= qq(>$_->{'seqbin_id'}\n);
		my $cleaned_seq = BIGSdb::Utils::break_line( $_->{'sequence'}, 60 ) || '';
		$buffer .= qq($cleaned_seq\n);
	}
	return \$buffer;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('format') eq 'text' ) {
		my $contigs = $self->_get_contigs( { $q->Vars } );
		say $$contigs;
		return;
	} elsif ( $q->param('batchDownload') && ( $q->param('format') // '' ) eq 'tar' && !$self->{'no_archive'} ) {
		$self->_batchDownload;
		return;
	}
	say q(<h1>Contig analysis and export</h1>);
	return if $self->has_set_changed;
	if ( $q->param('submit') ) {
		my $ids = $self->filter_list_to_ids( [ $q->param('isolate_id') ] );
		my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
		push @$ids, @$pasted_cleaned_ids;
		@$ids = uniq @$ids;
		my $filtered_ids = $self->filter_ids_by_project( $ids, $q->param('project_list') );
		if (@$invalid_ids) {
			local $" = ', ';
			$self->print_bad_status(
				{
					message => qq(The following isolates in your pasted list are invalid: @$invalid_ids.)
				}
			);
			$self->_print_interface;
			return;
		}
		if ( !@$filtered_ids ) {
			$self->print_bad_status(
				{
					message => q(You must include one or more isolates. Make sure your )
					  . q(selected isolates haven't been filtered to none by selecting a project.)
				}
			);
			$self->_print_interface;
			return;
		} elsif ( @$filtered_ids > MAX_ISOLATES ) {
			my $max_isolates =
			  ( $self->{'system'}->{'contig_analysis_limit'}
				  && BIGSdb::Utils::is_int( $self->{'system'}->{'contig_analysis_limit'} ) )
			  ? $self->{'system'}->{'contig_analysis_limit'}
			  : MAX_ISOLATES;
			my $selected_count = @$filtered_ids;
			$self->print_bad_status(
				{
					message => qq(Contig analysis is limited to $max_isolates )
					  . qq(isolates. You have selected $selected_count.)
				}
			);
			$self->_print_interface;
			return;
		}
		$self->_print_interface;
		$self->_run_analysis($filtered_ids);
	} else {
		$self->_print_interface;
	}
	return;
}

sub _run_analysis {
	my ( $self, $filtered_ids ) = @_;
	my $list_file = $self->make_temp_file(@$filtered_ids);
	my $q         = $self->{'cgi'};
	say q(<div class="box" id="resultstable">);
	my $pc_untagged = $q->param('pc_untagged');
	$pc_untagged = 0 if !defined $pc_untagged || !BIGSdb::Utils::is_int($pc_untagged);
	my $title = qq(Contigs with >=$pc_untagged\% sequence length untagged);
	say qq(<h2>$title</h2><table class="tablesorter" id="sortTable"><thead>)
	  . qq(<tr><th rowspan="2">id</th><th rowspan="2">$self->{'system'}->{'labelfield'}</th>)
	  . q(<th rowspan="2">contigs</th><th colspan="2" class="{sorter: false}">matching contigs</th>)
	  . qq(<th colspan="2" class="{sorter: false}">non-matching contigs</th></tr>\n<tr><th>count</th>)
	  . q(<th class="{sorter: false}">download</th><th>count</th>)
	  . q(<th class="{sorter: false}">download</th></tr></thead><tbody>);
	my $filebuffer =
	  qq($title:\n\nid\t$self->{'system'}->{'labelfield'}\tcontigs\tmatching contigs\tnon-matching contigs\n);
	my $label_field = $self->{'system'}->{'labelfield'};
	my $isolate_sql = $self->{'db'}->prepare("SELECT $label_field FROM $self->{'system'}->{'view'} WHERE id=?");
	my $td          = 1;
	local $| = 1;

	foreach my $isolate_id (@$filtered_ids) {
		my $isolate_values = $self->{'datastore'}->get_isolate_field_values($isolate_id);
		my $isolate_name   = $isolate_values->{ lc($label_field) };
		say qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=info&amp;id=$isolate_id">$isolate_id</a></td><td>$isolate_name</td>);
		my $results = $self->_calculate( $isolate_id, { pc_untagged => $pc_untagged } );
		say qq(<td>$results->{'total'}</td><td>$results->{'pc_untagged'}</td>);
		my @attributes;
		push @attributes, qq(pc_untagged=$pc_untagged);
		push @attributes, q(min_length=) . ( $q->param('min_length_list') // 0 );
		push @attributes, q(seq_method=) . $q->param('seq_method_list') if $q->param('seq_method_list');
		push @attributes, q(experiment=) . $q->param('experiment_list') if $q->param('experiment_list');
		push @attributes, q(header=) . $q->param('header_list') // 1;
		local $" = q(&amp;);
		say $results->{'pc_untagged'}
		  ? qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;)
		  . qq(name=Contigs&amp;format=text&amp;isolate_id=$isolate_id&amp;match=1&amp;@attributes">)
		  . q(<span class="file_icon fas fa-download"></span></a></td>)
		  : q(<td></td>);
		my $non_match = $results->{'total'} - $results->{'pc_untagged'};
		say $non_match
		  ? qq(<td>$non_match</td><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=plugin&amp;name=Contigs&amp;format=text&amp;isolate_id=$isolate_id&amp;match=0&amp;@attributes">)
		  . q(<span class="file_icon fas fa-download"></span></a></td>)
		  : qq(<td>$non_match</td><td></td>);
		say q(</tr>);
		$filebuffer .= qq($isolate_id\t$isolate_name\t$results->{'total'}\t$results->{'pc_untagged'}\t$non_match\n);
		$td = $td == 1 ? 2 : 1;

		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->rflush;
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
	}
	say q(</tbody></table>);
	my $prefix   = BIGSdb::Utils::get_random();
	my $filename = "$self->{'config'}->{'tmp_dir'}/$prefix.txt";
	open( my $fh, '>', $filename ) || $logger->error("Can't open $filename for writing");
	say $fh $filebuffer;
	close $fh;
	say qq(<ul><li><a href="/tmp/$prefix.txt">Download table in tab-delimited text format</a></li>);

	if ( !$self->{'no_archive'} ) {
		my $header = $q->param('header_list') // 1;
		say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;)
		  . qq(name=Contigs&amp;batchDownload=$list_file&amp;format=tar&amp;header=$header">Batch download )
		  . q(all contigs from selected isolates (tar format)</a></li>);
	}
	say q(</ul></div>);
	return;
}

sub _calculate {
	my ( $self, $isolate_id, $options ) = @_;
	my $q = $self->{'cgi'};
	my $qry =
	    'SELECT id,GREATEST(r.length,length(s.sequence)) AS seq_length,original_designation FROM '
	  . 'sequence_bin s LEFT JOIN remote_contigs r ON s.id=r.seqbin_id WHERE isolate_id=?';
	my @criteria = ($isolate_id);
	my $method = $q->param('seq_method_list') // $q->param('seq_method');
	if ($method) {
		if ( !any { $_ eq $method } SEQ_METHODS ) {
			$logger->error("Invalid method $method");
			return;
		}
		$qry .= ' AND method=?';
		push @criteria, $method;
	}
	my $experiment = $q->param('experiment_list') // $q->param('experiment');
	if ($experiment) {
		if ( !BIGSdb::Utils::is_int($experiment) ) {
			$logger->error("Invalid experiment $experiment");
			return;
		}
		$qry .= ' AND id IN (SELECT seqbin_id FROM experiment_sequences WHERE experiment_id=?)';
		push @criteria, $experiment;
	}
	$qry .= ' ORDER BY id';
	my $dataset = $self->{'datastore'}->run_query( $qry, \@criteria, { fetch => 'all_arrayref' } );
	my ( $total, $pc_untagged ) = ( 0, 0 );
	my ( @match_seq, @non_match_seq );
	foreach my $data (@$dataset) {
		my ( $seqbin_id, $seq_length, $orig_designation ) = @$data;
		my $min_length = $q->param('min_length_list') // $q->param('min_length');
		next if ( $min_length && BIGSdb::Utils::is_int($min_length) && $seq_length < $min_length );
		my $match = 1;
		$total++;
		my $tagged_length =
		  $self->{'datastore'}->run_query( 'SELECT sum(abs(end_pos-start_pos)) FROM allele_sequences WHERE seqbin_id=?',
			$seqbin_id, { cache => 'Contigs::tagged_length' } );
		$tagged_length //= 0;
		$tagged_length = $seq_length if $tagged_length > $seq_length;

		if ( ( ( $seq_length - $tagged_length ) * 100 / $seq_length ) >= $options->{'pc_untagged'} ) {
			$pc_untagged++;
		} else {
			$match = 0;
		}
		if ( $options->{'get_contigs'} ) {
			my $header = ( $q->param('header') // 1 ) == 1 ? ( $orig_designation || $seqbin_id ) : $seqbin_id;
			my $seq_ref = $self->{'contigManager'}->get_contig($seqbin_id);
			if ($match) {
				push @match_seq, { seqbin_id => $header, sequence => $$seq_ref };
			} else {
				push @non_match_seq, { seqbin_id => $header, sequence => $$seq_ref };
			}
		}
	}
	my %values =
	  ( total => $total, pc_untagged => $pc_untagged, match_seq => \@match_seq, non_match_seq => \@non_match_seq );
	return \%values;
}

sub _print_interface {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $view       = $self->{'system'}->{'view'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	my $selected_ids;
	if ( $q->param('isolate_id') ) {
		my @ids = $q->param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query_file ) {
		$selected_ids = $self->get_ids_from_query($qry_ref);
	} else {
		$selected_ids = [];
	}
	my $seqbin_values = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM sequence_bin)');
	if ( !$seqbin_values ) {
		$self->print_bad_status( { message => q(This database contains no genomes.), navbar => 1 } );
		return;
	}
	say q(<div class="box" id="queryform"><p>Please select the required isolate ids from which contigs are )
	  . q(associated - use Ctrl or Shift to make multiple selections.  Please note that the total length of )
	  . q(tagged sequence is calculated by adding up the length of all loci tagged within the contig - if )
	  . q(these loci overlap then the total tagged length will be reported as being longer than it really is )
	  . q(but it won't exceed the length of the contig.</p>);
	say $q->start_form;
	say q(<div class="scrollable">);
	$self->print_seqbin_isolate_fieldset( { selected_ids => $selected_ids, isolate_paste_list => 1 } );
	$self->_print_options_fieldset;
	$self->print_sequence_filter_fieldset( { min_length => 1 } );
	$self->print_action_fieldset( { name => 'Contigs' } );
	say $q->hidden($_) foreach qw (page name db set_id);
	say q(</div>);
	say $q->end_form;
	say q(</div>);
	return;
}

sub _print_options_fieldset {
	my ($self)    = @_;
	my $q         = $self->{'cgi'};
	my @pc_values = ( 0 .. 100 );
	say q(<fieldset style="float:left"><legend>Options</legend>);
	say q(<ul><li><label for="pc_untagged">Identify contigs with >= </label>);
	say $q->popup_menu( -name => 'pc_untagged', -id => 'pc_untagged', -values => \@pc_values );
	say q(% of sequence untagged</li>);
	say q(<li><label for="header_list">FASTA header line: </label>);
	say $q->popup_menu(
		-name   => 'header_list',
		-id     => 'header_list',
		-values => [qw (1 2)],
		-labels => { 1 => 'original designation', 2 => 'seqbin id' }
	);
	say $self->get_tooltip(
		q(FASTA header line - Seqbin id will be used if the original designation ) . q(has not been stored.) );
	say q(</li></ul></fieldset>);
	return;
}

sub _batchDownload {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	binmode STDOUT;
	my @list;
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/" . $q->param('batchDownload');
	local $| = 1;
	if ( !-e $filename ) {
		$logger->error("File $filename does not exist");
		my $error_file = 'error.txt';
		my $tar        = Archive::Tar->new;
		$tar->add_data( $error_file, 'No record list passed.  Please repeat query.' );
		if ( $ENV{'MOD_PERL'} ) {
			my $tf = $tar->write;
			$self->{'mod_perl_request'}->print($tf);
			$self->{'mod_perl_request'}->rflush;
		} else {
			$tar->write( \*STDOUT );
		}
	} else {
		open( my $fh, '<', $filename ) || $logger->error("Can't open $filename for reading");
		while (<$fh>) {
			chomp;
			push @list, $_ if BIGSdb::Utils::is_int($_);
		}
		close $fh;
		foreach my $id (@list) {
			if ( $id =~ /(\d+)/x ) {
				$id = $1;
			} else {
				next;
			}
			my $isolate_name = $self->get_isolate_name_from_id($id);
			$isolate_name =~ s/\W/_/gx;
			my $contig_file = "$id\_$isolate_name.fas";
			my $data = $self->_get_contigs( { isolate_id => $id, pc_untagged => 0, match => 1 } );

			#Modified from Archive::Tar::Streamed to allow mod_perl support.
			my $tar = Archive::Tar->new;
			$tar->add_data( $contig_file, $$data );

			#Write out tar file except EOF block so that we can add additional files.
			my $tf = $tar->write;
			if ( $ENV{'MOD_PERL'} ) {
				$self->{'mod_perl_request'}->print( substr $tf, 0, length($tf) - ( BLOCK * 2 ) );
				$self->{'mod_perl_request'}->rflush;
			} else {
				syswrite STDOUT, $tf, length($tf) - ( BLOCK * 2 );
			}
		}

		#Add EOF block
		if ( $ENV{'MOD_PERL'} ) {
			$self->{'mod_perl_request'}->print(TAR_END);
			$self->{'mod_perl_request'}->rflush;
		} else {
			syswrite STDOUT, TAR_END;
		}
	}
	return;
}
1;
