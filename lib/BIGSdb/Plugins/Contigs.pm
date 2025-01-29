#Contigs.pm - Contig export and analysis plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2013-2025, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
use IO::Compress::Gzip qw(gzip $GzipError);
use constant MAX_ISOLATES => 1000;
use List::MoreUtils qw(uniq);
use BIGSdb::Constants qw(:interface SEQ_METHODS);

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name    => 'Contig export',
		authors => [
			{
				name        => 'Keith Jolley',
				affiliation => 'University of Oxford, UK',
				email       => 'keith.jolley@biology.ox.ac.uk',
			}
		],
		description      => 'Analyse and export contigs selected from query results',
		full_description => 'This plugin enables the contigs associated with each isolate in a dataset to be '
		  . 'downloaded in FASTA format. They can also be downloaded in batch mode as a TAR file. The contigs included '
		  . 'in the download can be filtered based on the percentage of the sequence that has been tagged with a '
		  . 'locus so that poorly annotated regions can be analysed specifically.',
		category           => 'Export',
		buttontext         => 'Contigs',
		menutext           => 'Contigs',
		module             => 'Contigs',
		url                => "$self->{'config'}->{'doclink'}/data_export/contig_export.html",
		version            => '2.0.0',
		dbtype             => 'isolates',
		section            => 'export,postquery',
		input              => 'query',
		help               => 'tooltips',
		order              => 20,
		system_flag        => 'ContigExport',
		enabled_by_default => 1,
		tar_gz_filename    => 'contigs.tar.gz',
		requires => 'seqbin,offline_jobs',                   #Offline jobs set to force log in if required for downloads
		image    => '/images/plugins/Contigs/screenshot.png'
	);
	return \%att;
}

sub get_initiation_values {
	return { 'jQuery.tablesort' => 1 };
}

sub set_pref_requirements {
	my ($self) = @_;
	$self->{'pref_requirements'} =
	  { general => 1, main_display => 0, isolate_display => 0, analysis => 1, query_field => 1 };
	return;
}

sub _get_contigs {
	my ( $self,       $args )   = @_;
	my ( $isolate_id, $single ) = @{$args}{qw (isolate_id single)};
	my $buffer = q();
	if ( !defined $isolate_id || !BIGSdb::Utils::is_int($isolate_id) ) {
		say q(Invalid isolate id passed.) if $single;
		return \$buffer;
	}
	my $contig_records =
	  $self->{'datastore'}->run_query( 'SELECT id,original_designation FROM sequence_bin WHERE isolate_id=?',
		$isolate_id, { fetch => 'all_hashref', key => 'id', cache => 'Contigs::get_contigs' } );
	my $contig_ids = [ keys %$contig_records ];
	if ( !@$contig_ids ) {
		say q(No sequences matching selected criteria.) if $single;
		return \$buffer;
	}
	my $contigs = $self->{'contigManager'}->get_contigs_by_list($contig_ids);
	my $q       = $self->{'cgi'};
	foreach
	  my $contig_id ( sort { ( length( $contigs->{$b} ) <=> length( $contigs->{$a} ) ) || ( $a <=> $b ) } @$contig_ids )
	{
		my $header =
			( $q->param('header') // 1 ) == 1
		  ? ( $contig_records->{$contig_id}->{'original_designation'} || $contig_id )
		  : $contig_id;
		$buffer .= qq(>$header\n);
		my $cleaned_seq = BIGSdb::Utils::break_line( $contigs->{$contig_id}, 60 ) || '';
		$buffer .= qq($cleaned_seq\n);
	}
	return \$buffer;
}

sub run {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('format') eq 'text' ) {
		my $contigs = $self->_get_contigs( { $q->Vars, single => 1 } );
		say $$contigs;
		return;
	} elsif ( $q->param('batchDownload') && ( $q->param('format') // '' ) eq 'tar_gz' && !$self->{'no_archive'} ) {
		$self->_batch_download;
		return;
	}
	say q(<h1>Contig analysis and export</h1>);
	if ( ( $self->{'system'}->{'ContigExport'} // q() ) eq 'no' ) {
		$self->print_bad_status( { message => q(Contig exports are disabled.) } );
		return;
	}
	return if $self->has_set_changed;
	if ( $q->param('submit') ) {
		my $ids = $self->filter_list_to_ids( [ $q->multi_param('isolate_id') ] );
		my ( $pasted_cleaned_ids, $invalid_ids ) = $self->get_ids_from_pasted_list( { dont_clear => 1 } );
		push @$ids, @$pasted_cleaned_ids;
		@$ids = uniq @$ids;
		my $limit = $self->_get_limit;
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
		if ( !@$ids ) {
			$self->print_bad_status(
				{
					message => q(You must include one or more isolates. Make sure your )
					  . q(selected isolates haven't been filtered to none by selecting a project.)
				}
			);
			$self->_print_interface;
			return;
		} elsif ( @$ids > $limit ) {
			my $selected_count = @$ids;
			my $nice_limit     = BIGSdb::Utils::commify($limit);
			my $nice_selected  = BIGSdb::Utils::commify($selected_count);
			$self->print_bad_status(
				{
					message => qq(Contig analysis is limited to $nice_limit )
					  . qq(isolates. You have selected $nice_selected.)
				}
			);
			$self->_print_interface;
			return;
		}
		$self->_print_interface;
		$self->_run_analysis($ids);
	} else {
		$self->_print_interface;
	}
	return;
}

sub _get_limit {
	my ($self) = @_;
	my $limit = $self->{'system'}->{'contig_export_limit'} // $self->{'config'}->{'contig_export_limit'}
	  // MAX_ISOLATES;
	if ( !BIGSdb::Utils::is_int($limit) ) {
		$limit = MAX_ISOLATES;
	}
	return $limit;
}

sub _run_analysis {
	my ( $self, $ids ) = @_;
	my $list_file = $self->make_temp_file(@$ids);
	my $q         = $self->{'cgi'};
	say q(<div class="box" id="resultstable">);
	my $title = q(Sequence bin attributes for selected isolates);
	say qq(<h2>$title</h2><table class="tablesorter" id="sortTable"><thead>)
	  . qq(<tr><th>id</th><th>$self->{'system'}->{'labelfield'}</th><th>contigs</th><th>total length</th>)
	  . q(<th>N50</th><th>L50</th><th class="sorter-false">download</th></tr></thead><tbody>);
	my $filebuffer  = qq(id\t$self->{'system'}->{'labelfield'}\tcontigs\ttotal length\tN50\tL50\n);
	my $label_field = $self->{'system'}->{'labelfield'};
	my $isolate_sql = $self->{'db'}->prepare("SELECT $label_field FROM $self->{'system'}->{'view'} WHERE id=?");
	my $td          = 1;
	local $| = 1;
	my $list_table = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $ids );
	my $contig_stats =
	  $self->{'datastore'}
	  ->run_query( "SELECT s.* FROM seqbin_stats s JOIN $list_table l ON s.isolate_id=l.value ORDER BY s.isolate_id",
		undef, { fetch => 'all_hashref', key => 'isolate_id' } );
	my $show_archive_link;

	foreach my $isolate_id (@$ids) {
		my $isolate_values = $self->{'datastore'}->get_isolate_field_values($isolate_id);
		my $isolate_name   = $isolate_values->{ lc($label_field) };
		say qq(<tr class="td$td"><td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . qq(page=info&amp;id=$isolate_id">$isolate_id</a></td><td>$isolate_name</td>);
		my $contigs      = $contig_stats->{$isolate_id}->{'contigs'} // 0;
		my $nice_contigs = BIGSdb::Utils::commify($contigs);
		my $length       = $contig_stats->{$isolate_id}->{'total_length'} // 0;
		my $nice_length  = BIGSdb::Utils::commify($length);
		my $n50          = $contig_stats->{$isolate_id}->{'n50'} // '-';
		my $nice_n50     = BIGSdb::Utils::is_int($n50) ? BIGSdb::Utils::commify($n50) : '-';
		my $l50          = $contig_stats->{$isolate_id}->{'l50'} // '-';
		my $nice_l50     = BIGSdb::Utils::is_int($l50) ? BIGSdb::Utils::commify($l50) : '-';
		my $header       = $q->param('header_list') // 1;
		$header = 1 if !BIGSdb::Utils::is_int($header);
		say qq(<td>$nice_contigs</td><td>$nice_length</td><td>$nice_n50</td><td>$nice_l50</td>);

		if ($length) {
			say qq(<td><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;)
			  . qq(name=Contigs&amp;format=text&amp;isolate_id=$isolate_id&amp;header=$header">)
			  . q(<span class="file_icon fas fa-download"></span></a></td>);
			$show_archive_link = 1;
		} else {
			say q(<td></td>);
		}
		$filebuffer .= qq($isolate_id\t$isolate_name\t$contigs\t$length\t$n50\t$l50\n);
		$td = $td == 1 ? 2 : 1;
		if ( $ENV{'MOD_PERL'} ) {
			eval { $self->{'mod_perl_request'}->rflush };
			return if $self->{'mod_perl_request'}->connection->aborted;
		}
	}
	say q(</tbody></table>);
	my $prefix   = BIGSdb::Utils::get_random();
	my $filename = "$self->{'config'}->{'tmp_dir'}/$prefix.txt";
	open( my $fh, '>', $filename ) || $logger->error("Can't open $filename for writing");
	say $fh $filebuffer;
	close $fh;
	my ( $text, $excel, $archive ) = ( TEXT_FILE, EXCEL_FILE, ARCHIVE_FILE );
	print q(<p style="margin-top:1em">)
	  . qq(<a href="/tmp/$prefix.txt" title="Download table in tab-delimited text format">$text</a>);
	my $excel_file = BIGSdb::Utils::text2excel($filename);

	if ( -e $excel_file ) {
		print qq(<a href="/tmp/$prefix.xlsx" title="Download table in Excel format">$excel</a>);
	}
	if ( !$self->{'no_archive'} && $show_archive_link ) {
		my $header = $q->param('header_list') // 1;
		say qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=plugin&amp;)
		  . qq(name=Contigs&amp;batchDownload=$list_file&amp;format=tar_gz&amp;header=$header" )
		  . qq(title="Batch download all contigs from selected isolates (tar.gz format)">$archive</a>);
	}
	say q(</p></div>);
	return;
}

sub _print_interface {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $view       = $self->{'system'}->{'view'};
	my $query_file = $q->param('query_file');
	my $qry_ref    = $self->get_query($query_file);
	my $selected_ids;
	if ( $q->param('isolate_id') ) {
		my @ids = $q->multi_param('isolate_id');
		$selected_ids = \@ids;
	} elsif ( defined $query_file ) {
		$selected_ids = $self->get_ids_from_query($qry_ref);
	} else {
		$selected_ids = [];
	}
	my $seqbin_values = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT id FROM sequence_bin)');
	if ( !$seqbin_values ) {
		$self->print_bad_status( { message => q(This database view contains no genomes.), navbar => 1 } );
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
	say q(<ul><li><label for="header_list">FASTA header line: </label>);
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

sub _batch_download {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	binmode STDOUT;
	my $list     = [];
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/" . $q->param('batchDownload');
	local $| = 1;
	if ( !-e $filename ) {
		$logger->error("File $filename does not exist");
		my $error_file = 'error.txt';
		my $tar        = Archive::Tar->new;
		$tar->add_data( $error_file, 'No record list passed. Please repeat query.' );
		$tar->write( \*STDOUT );
	} else {
		open( my $fh, '<', $filename ) || $logger->error("Cannot open $filename for reading");
		while (<$fh>) {
			chomp;
			push @$list, $_ if BIGSdb::Utils::is_int($_);
		}
		close $fh;
		my $temp_list = $self->{'datastore'}->create_temp_list_table_from_array( 'int', $list );
		my $names =
		  $self->{'datastore'}
		  ->run_query( "SELECT id,$self->{'system'}->{'labelfield'} FROM isolates i JOIN $temp_list t ON i.id=t.value",
			undef, { fetch => 'all_arrayref' } );
		my %names = map { $_->[0] => $_->[1] } @$names;
		my $gz    = IO::Compress::Gzip->new( \*STDOUT )
		  or $logger->error("IO::Compress::Gzip failed: $GzipError");
		foreach my $id (@$list) {
			if ( $id =~ /(\d+)/x ) {
				$id = $1;
			} else {
				next;
			}
			my $data = $self->_get_contigs( { isolate_id => $id } );
			next if !$$data;
			my $isolate_name = $names{$id} // 'unknown';
			$isolate_name =~ s/\W/_/gx;
			my $contig_file = "${id}_$isolate_name.fas";

			#Modified from Archive::Tar::Streamed to allow mod_perl support.
			my $tar = Archive::Tar->new;
			$tar->add_data( $contig_file, $$data );

			#Write out tar file except EOF block so that we can add additional files.
			my $tf = $tar->write;
			syswrite $gz, $tf, length($tf) - ( BLOCK * 2 );
			if ( $ENV{'MOD_PERL'} ) {
				return if $self->{'mod_perl_request'}->connection->aborted;
			}
		}

		#Add EOF block
		syswrite $gz, TAR_END;
		$gz->close;
	}
	return;
}
1;
