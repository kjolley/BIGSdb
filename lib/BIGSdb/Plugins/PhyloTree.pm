#PhyloTree.pm - Phylogenetic tree plugin for BIGSdb
#Written by Keith Jolley
#Copyright (c) 2016, University of Oxford
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
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See thef
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::Plugins::PhyloTree;
use strict;
use warnings;
use parent qw(BIGSdb::Plugins::SequenceExport);
use 5.010;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Plugins');
use Error qw(:try);
use List::MoreUtils qw(uniq);
use File::Copy;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use LWP::UserAgent;
use BIGSdb::Utils;
use constant MAX_RECORDS     => 1000;
use constant MAX_SEQS        => 100_000;
use constant ITOL_UPLOAD_URL => 'http://itol.embl.de/batch_uploader.cgi';
use constant ITOL_DOMAIN     => 'itol.embl.de';
use constant ITOL_TREE_URL   => 'http://itol.embl.de/tree';

sub get_attributes {
	my ($self) = @_;
	my %att = (
		name             => 'PhyloTree',
		author           => 'Keith Jolley',
		affiliation      => 'University of Oxford, UK',
		email            => 'keith.jolley@zoo.ox.ac.uk',
		description      => 'Generate phylogenetic trees',
		menu_description => 'Generate phylogenetic trees',
		category         => 'Analysis',
		buttontext       => 'PhyloTree',
		menutext         => 'PhyloTree',
		module           => 'PhyloTree',
		version          => '0.0.1',
		dbtype           => 'isolates',
		section          => 'analysis,postquery',
		input            => 'query',
		help             => 'tooltips',
		requires         => 'aligner,offline_jobs,js_tree,clustalw',
		order            => 35,
		min              => 2,
		max              => MAX_RECORDS
	);
	return \%att;
}

sub run {
	my ($self)     = @_;
	my $q          = $self->{'cgi'};
	my $query_file = $q->param('query_file');
	my $scheme_id  = $q->param('scheme_id');
	my $desc       = $self->get_db_description;
	my $max_records = $self->{'system'}->{'phylotree_record_limit'} // MAX_RECORDS;
	my $max_seqs    = $self->{'system'}->{'phylotree_seq_limit'}    // MAX_SEQS;
	say "<h1>Generate phylogenetic trees - $desc</h1>";
	return if $self->has_set_changed;
	my $allow_alignment = 1;

	if ( !-x $self->{'config'}->{'muscle_path'} && !-x $self->{'config'}->{'mafft_path'} ) {
		$logger->error( 'This plugin requires an aligner (MAFFT or MUSCLE) to be installed and one is not. '
			  . 'Please install one of these or check the settings in bigsdb.conf.' );
		$allow_alignment = 0;
	}
	my $pk;
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		$pk = 'id';
	} else {
		return if defined $scheme_id && $self->is_scheme_invalid( $scheme_id, { with_pk => 1 } );
		if ( !$q->param('submit') ) {
			$self->print_scheme_section( { with_pk => 1 } );
			$scheme_id = $q->param('scheme_id');    #Will be set by scheme section method
		}
		if ( !defined $scheme_id ) {
			say q(<div class="box" id="statusbad"><p>Invalid scheme selected.</p></div>);
			return;
		}
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { get_pk => 1 } );
		$pk = $scheme_info->{'primary_key'};
	}
	if ( $q->param('submit') ) {
		my $loci_selected = $self->get_selected_loci;
		my ( $pasted_cleaned_loci, $invalid_loci ) = $self->get_loci_from_pasted_list;
		$q->delete('locus');
		push @$loci_selected, @$pasted_cleaned_loci;
		@$loci_selected = uniq @$loci_selected;
		$self->add_scheme_loci($loci_selected);
		if (@$invalid_loci) {
			local $" = q(, );
			say q(<div class="box" id="statusbad"><p>The following loci in your pasted list are )
			  . qq(invalid: @$invalid_loci.</p></div>);
		} elsif ( !@$loci_selected ) {
			print q(<div class="box" id="statusbad"><p>You must select one or more loci);
			print q( or schemes) if $self->{'system'}->{'dbtype'} eq 'isolates';
			say q(.</p></div>);
		} elsif ( $self->attempted_spam( \( $q->param('list') ) ) ) {
			say q(<div class="box" id="statusbad"><p>Invalid data detected in list.</p></div>);
		} else {
			$self->set_scheme_param;
			my $params = $q->Vars;
			$params->{'pk'}     = $pk;
			$params->{'set_id'} = $self->get_set_id;
			my @list = split /[\r\n]+/x, $q->param('list');
			@list = uniq @list;
			if ( !@list ) {
				if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
					my $qry = "SELECT id FROM $self->{'system'}->{'view'} ORDER BY id";
					my $id_list = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
					@list = @$id_list;
				} else {
					my $pk_info = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $pk );
					my $qry = 'SELECT profile_id FROM profiles WHERE scheme_id=? ORDER BY ';
					$qry .= $pk_info->{'type'} eq 'integer' ? 'CAST(profile_id AS INT)' : 'profile_id';
					my $id_list = $self->{'datastore'}->run_query( $qry, $scheme_id, { fetch => 'col_arrayref' } );
					@list = @$id_list;
				}
			}
			my $total_seqs = @$loci_selected * @list;
			if ( $total_seqs > $max_seqs ) {
				say qq(<div class="box" id="statusbad"><p>Output is limited to a total of $total_seqs sequences )
				  . qq((records x loci).  You have selected $total_seqs.</p></div>);
				return;
			}
			$q->delete('list');
			my @itol_dataset = $q->param('itol_dataset');
			$q->delete('itol_dataset');
			local $" = '|_|';
			$params->{'itol_dataset'} = "@itol_dataset";
			my $user_info = $self->{'datastore'}->get_user_info_from_username( $self->{'username'} );
			my $job_id    = $self->{'jobManager'}->add_job(
				{
					dbase_config => $self->{'instance'},
					ip_address   => $q->remote_host,
					module       => 'PhyloTree',
					parameters   => $params,
					username     => $self->{'username'},
					email        => $user_info->{'email'},
					loci         => $loci_selected,
					isolates     => \@list
				}
			);
			say $self->get_job_redirect($job_id);
			return;
		}
	}
	my $limit = $self->_get_limit;
	say q(<div class="box" id="queryform">);

	#TODO Remove BETA flag.
	say q(<p><span class="flag" style="color:red">BETA</span> Please report any issues with this plugin to )
	  . q(<a href="keith.jolley@zoo.ox.ac.uk">Keith Jolley</a>.</p>);
	say q(<p>This tool will generate neighbor-joining trees from concatenated nucleotide sequences. Only DNA )
	  . q(loci that have a corresponding database containing allele sequence identifiers, )
	  . q(or DNA and peptide loci with genome sequences tagged, can be included. Please check the loci that you )
	  . q(would like to include.  Alternatively select one or more schemes to include all loci that are members )
	  . q(of the scheme.</p>);
	my $commify_max_records = BIGSdb::Utils::commify($max_records);
	my $commify_max_seqs    = BIGSdb::Utils::commify($max_seqs);
	say qq(<p>Analysis is limited to $commify_max_records records or $commify_max_seqs sequences (records x loci).</p>);
	my $list = $self->get_id_list( $pk, $query_file );
	$self->print_sequence_export_form( $pk, $list, $scheme_id, { ignore_seqflags => 1, ignore_incomplete => 1 } );
	say q(</div>);
	return;
}

sub print_extra_form_elements {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my ( $fields, $labels ) =
	  $self->get_field_selection_list( { isolate_fields => 1, extended_attributes => 1, scheme_fields => 1 } );
	my @allowed_fields;
	my %disabled = map { $_ => 1 } qw(f_id f_comments f_date_entered f_datestamp f_sender f_curator);
	if ( $self->{'system'}->{'noshow'} ) {
		my @noshow = split /,/x, $self->{'system'}->{'noshow'};
		$disabled{"f_$_"} = 1 foreach @noshow;
	}
	foreach my $field (@$fields) {
		next if $disabled{$field};
		push @allowed_fields, $field;
	}
	say q(<fieldset style="float:left"><legend>iTOL datasets</legend>);
	say q(<p>Select to create data overlays</p>);
	say $q->scrolling_list(
		-name     => 'itol_dataset',
		-id       => 'itol_dataset',
		-values   => \@allowed_fields,
		-labels   => $labels,
		-size     => 8,
		-multiple => 'true'
	);
	say q(</fieldset>);
	return;
}

sub _get_identifier_list {
	my ( $self, $fasta_file ) = @_;
	open( my $fh, '<', $fasta_file ) || $logger->error("Cannot open $fasta_file for reading");
	my @ids;
	while ( my $line = <$fh> ) {
		if ( $line =~ /^>(\S*)/x ) {
			push @ids, $1;
		}
	}
	close $fh;
	return \@ids;
}

sub run_job {
	my ( $self, $job_id, $params ) = @_;
	$self->set_offline_view($params);
	$self->{'exit'} = 0;
	local @SIG{qw (INT TERM HUP)} = ( sub { $self->{'exit'} = 1 } ) x 3; #Allow temp files to be cleaned on kill signals
	my $ids      = $self->{'jobManager'}->get_job_isolates($job_id);
	my $loci     = $self->{'jobManager'}->get_job_loci($job_id);
	my $filename = "$self->{'config'}->{'tmp_dir'}/$job_id.xmfa";
	my $ret_val  = $self->make_isolate_seq_file(
		{
			job_id       => $job_id,
			params       => $params,
			limit        => MAX_RECORDS,
			ids          => $ids,
			loci         => $loci,
			filename     => $filename,
			max_progress => 80
		}
	);

	if ( $self->{'exit'} ) {
		$self->{'jobManager'}->update_job_status( $job_id, { status => 'terminated' } );
		unlink $filename;
		return;
	}
	my $message_html;
	my $problem_ids = $ret_val->{'problem_ids'};
	if (@$problem_ids) {
		local $" = ', ';
		$message_html = "<p>The following ids could not be processed (they do not exist): @$problem_ids.</p>\n";
	}
	my $no_output = $ret_val->{'no_output'};
	if ($no_output) {
		$message_html .=
		  "<p>No output generated. Please ensure that your sequences have been defined for these isolates.</p>\n";
	} else {
		try {
			$self->{'jobManager'}
			  ->update_job_status( $job_id, { stage => 'Generating FASTA file from aligned blocks' } );
			my $fasta_file = BIGSdb::Utils::xmfa2fasta($filename);
			if ( -e $fasta_file ) {
				$self->{'jobManager'}->update_job_output( $job_id,
					{ filename => "$job_id.fas", description => '10_Concatenated FASTA', } );
			}
			$self->{'jobManager'}->update_job_status( $job_id, { stage => 'Constructing NJ tree' } );
			my $tree_file = "$self->{'config'}->{'tmp_dir'}/$job_id.ph";
			my $cmd       = "$self->{'config'}->{'clustalw_path'} -tree -infile=$fasta_file > /dev/null";
			system $cmd;
			if ( -e $tree_file ) {
				$self->{'jobManager'}->update_job_output( $job_id,
					{ filename => "$job_id.ph", description => '20_NJ tree (Newick format)', } );
			}
			my $identifiers = $self->_get_identifier_list($fasta_file);
			$self->_itol_upload( $job_id, $params, $identifiers, \$message_html );
		}
		catch BIGSdb::CannotOpenFileException with {
			$logger->error('Cannot create FASTA file from XMFA.');
		};
		unlink $filename if -e "$filename.gz";
	}
	$self->{'jobManager'}->update_job_status( $job_id, { message_html => $message_html } ) if $message_html;
	return;
}

sub _itol_upload {
	my ( $self, $job_id, $params, $identifiers, $message_html ) = @_;
	$self->{'jobManager'}
	  ->update_job_status( $job_id, { stage => 'Uploading tree files to iTOL', percent_complete => 95 } );
	my $tree_file          = "$self->{'config'}->{'tmp_dir'}/$job_id.ph";
	my $itol_tree_filename = "$self->{'config'}->{'secure_tmp_dir'}/$job_id.tree";
	copy( $tree_file, $itol_tree_filename ) or $logger->error("Copy failed: $!");
	chdir $self->{'config'}->{'secure_tmp_dir'};
	my $zip = Archive::Zip->new;
	$zip->addFile("$job_id.tree");
	my @files_to_delete = ($itol_tree_filename);

	if ( $params->{'itol_dataset'} ) {
		my @itol_dataset_fields = split /\|_\|/x, $params->{'itol_dataset'};
		my $i = 1;
		foreach my $field (@itol_dataset_fields) {
			my $colour = BIGSdb::Utils::get_heatmap_colour_style( $i, scalar @itol_dataset_fields, { rgb => 1 } );
			$i++;
			my $file = $self->_create_itol_dataset( $job_id, $identifiers, $field, $colour );
			next if !$file;
			$zip->addFile($file);
			push @files_to_delete, $file;
		}
	}
	unless ( $zip->writeToFileNamed("$job_id.zip") == AZ_OK ) {
		$logger->error("Cannot write $job_id.zip");
	}
	unlink @files_to_delete;
	my $uploader = LWP::UserAgent->new( agent => 'BIGSdb' );
	my $response = $uploader->post(
		ITOL_UPLOAD_URL,
		Content_Type => 'form-data',
		Content      => [ zipFile => ["$job_id.zip"] ]
	);
	if ( $response->is_success ) {
		my @res = split /\n/x, $response->content;
		foreach my $res_line (@res) {

			#check for an upload error
			if ( $res_line =~ /^ERR/x ) {
				$$message_html .= q(<p class="statusbad">iTOL upload failed. iTOL returned )
				  . qq(the following error message:\n\n$res[-1]</p>);
				$logger->error("@res");
				last;
			}

			#upload without warnings, ID on first line
			if ( $res_line =~ /^SUCCESS:\ (\S+)/x ) {
				my $url    = ITOL_TREE_URL . "/$1";
				my $domain = ITOL_DOMAIN;
				$$message_html .= qq(<ul><li><a href="$url" target="_blank">Launch tree in iTOL</a> )
				  . qq(<span class="link"><span style="font-size:1.2em">&rarr;</span> $domain</span></li></ul>);
				last;
			}
		}
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => $$message_html } );
	} else {
		$logger->error( $response->as_string );
		$$message_html .= q(<p class="statusbad">iTOL upload failed.</p>);
		$self->{'jobManager'}->update_job_status( $job_id, { message_html => $$message_html } );
	}
	unlink "$self->{'config'}->{'secure_tmp_dir'}/$job_id.zip";
	return;
}

sub _create_itol_dataset {
	my ( $self, $job_id, $identifiers, $field, $colour ) = @_;
	my $field_info = $self->_get_field_type($field);
	my ( $type, $name, $extended_field, $scheme_id ) = @{$field_info}{qw(type field extended_field scheme_id)};
	$extended_field //= q();
	( my $cleaned_ext_field = $extended_field ) =~ s/'/\\'/gx;
	my $scheme_field_desc;
	my $scheme_temp_table = q();
	my @ids;

	foreach my $identifier (@$identifiers) {
		if ( $identifier =~ /^(\d+)/x ) {
			push @ids, $1;
		}
	}
	if ( $type eq 'scheme_field' ) {
		my $set_id = $self->get_set_id;
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		$scheme_field_desc = "$name ($scheme_info->{'name'})";
		$scheme_temp_table = $self->_create_scheme_field_temp_table( \@ids, $scheme_id, $name );
	}
	return if !$type;
	my %dataset_label = ( field => $name, extended_field => $extended_field, scheme_field => $scheme_field_desc );
	my $filename = "$self->{'config'}->{'secure_tmp_dir'}/${job_id}_$field";
	open( my $fh, '>', $filename ) || $logger->error("Can't open $filename for writing");
	say $fh 'DATASET_TEXT';
	say $fh 'SEPARATOR TAB';
	say $fh "DATASET_LABEL\t$dataset_label{$type}";
	say $fh "COLOR\t$colour";
	say $fh 'DATA';
	my %value_colour;

	#Find out how many distinct values there are in dataset
	if ( !$self->{'temp_list_created'} ) {
		$self->{'datastore'}->create_temp_list_table_from_array( 'int', \@ids, { table => $job_id } );
		$self->{'temp_list_created'} = 1;
	}
	my $distinct_qry = {
		field => "SELECT COUNT(DISTINCT($name)) FROM $self->{'system'}->{'view'} "
		  . "WHERE id IN (SELECT value FROM $job_id) AND $name IS NOT NULL",
		extended_field => 'SELECT COUNT(DISTINCT(e.value)) FROM isolate_value_extended_attributes AS e '
		  . "JOIN $self->{'system'}->{'view'} AS i ON e.isolate_field='$name' AND e.attribute=E'$cleaned_ext_field' "
		  . "AND e.field_value=i.$name WHERE i.id IN (SELECT value FROM $job_id)",
		scheme_field => "SELECT COUNT(DISTINCT(value)) FROM $scheme_temp_table"
	};
	my $distinct = $self->{'datastore'}->run_query( $distinct_qry->{$type} );
	my $count    = $self->{'datastore'}->run_query("SELECT COUNT(*) FROM $job_id");
	my $i        = 1;
	my $qry      = {
		field          => "SELECT $name FROM $self->{'system'}->{'view'} WHERE id=?",
		extended_field => 'SELECT e.value FROM isolate_value_extended_attributes AS e '
		  . "JOIN $self->{'system'}->{'view'} AS i ON e.isolate_field='$name' AND "
		  . "e.attribute=E'$cleaned_ext_field' AND e.field_value=i.$name WHERE i.id=?",
		scheme_field => "SELECT value FROM $scheme_temp_table WHERE id=?"
	};
	foreach my $identifier (@$identifiers) {
		if ( $identifier =~ /^(\d+)/x ) {
			my $id = $1;
			my $data =
			  $self->{'datastore'}->run_query( $qry->{$type}, $id, { cache => "PhyloTree::itol_dataset::$field" } );
			next if !defined $data;
			if ( !$value_colour{$data} ) {
				$value_colour{$data} = BIGSdb::Utils::get_heatmap_colour_style( $i, $distinct, { rgb => 1 } );
				$i++;
			}
			say $fh "$identifier\t$data\t-1\t$value_colour{$data}\tnormal\t1";
		}
	}
	close $fh;
	return $filename;
}

sub _create_scheme_field_temp_table {
	my ( $self, $ids, $scheme_id, $field ) = @_;
	my $temp_table = "temp_${scheme_id}_$field";
	eval {
		$self->{'db'}->do("CREATE TEMP table $temp_table (id int, value text,PRIMARY KEY (id))");
		foreach my $id (@$ids) {
			my $values =
			  $self->get_scheme_field_values( { isolate_id => $id, scheme_id => $scheme_id, field => $field } );
			next if !defined $values->[0];
			local $" = q(; );
			$self->{'db'}->do( "INSERT INTO $temp_table VALUES (?,?)", undef, $id, "@$values" );
		}
	};
	$logger->error($@) if $@;
	return $temp_table;
}

sub _get_field_type {
	my ( $self, $field ) = @_;
	if ( $field =~ /^f_(.+)/x ) {
		if ( $self->{'xmlHandler'}->is_field($1) ) {
			return { type => 'field', field => $1 };
		}
	}
	if ( $field =~ /^e_(.+)\|\|(.+)/x ) {
		if (
			$self->{'xmlHandler'}->is_field($1)
			&& $self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM isolate_field_extended_attributes '
				  . 'WHERE (isolate_field,attribute)=(?,?))',
				[ $1, $2 ]
			)
		  )
		{
			return { type => 'extended_field', field => $1, extended_field => $2 };
		}
	}
	if ( $field =~ /^s_(\d+)_(.+)/x ) {
		if ( $self->{'datastore'}->is_scheme_field( $1, $2 ) ) {
			return { type => 'scheme_field', scheme_id => $1, field => $2 };
		}
	}
	return;
}
1;
