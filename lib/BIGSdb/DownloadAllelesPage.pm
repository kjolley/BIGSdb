#Written by Keith Jolley
#Copyright (c) 2010-2016, University of Oxford
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
package BIGSdb::DownloadAllelesPage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::TreeViewPage);
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use BIGSdb::Constants qw(LOCUS_PATTERN);

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('locus') ) {
		$self->{'type'} = 'text';
		my $locus = $q->param('locus') // 'alleles';
		$self->{'attachment'} = "$locus.fas";
		return;
	} elsif ( $q->param('no_header') ) {
		$self->{'type'}    = 'no_header';
		$self->{'noCache'} = 1;
		return;
	}
	$self->{$_} = 1 foreach qw (jQuery jQuery.jstree);
	$self->{'noCache'} = 1 if ( $self->{'system'}->{'sets'} // '' ) eq 'yes';
	return;
}

sub get_help_url {
	my ($self) = @_;
	return "$self->{'config'}->{'doclink'}/data_downloads.html#allele-sequence-definitions";
}

sub get_javascript {
	my ($self) = @_;
	return $self->get_tree_javascript;
}

sub _print_tree {
	my ($self) = @_;
	say q(<p>Click within the tree to display details of loci belonging to schemes or groups of schemes - )
	  . q(clicking a group folder will display the loci for all schemes within the group and any subgroups. )
	  . q(Click the nodes to expand/collapse.</p>);
	say q(<noscript><p class="highlight">Enable Javascript to enhance your viewing experience.</p></noscript>)
	  . q(<div id="tree" class="tree">);
	say $self->get_tree(undef);
	say q(</div><div id="scheme_table"></div>);
	return;
}

sub _print_child_group_scheme_tables {
	my ( $self, $id, $level, $scheme_shown ) = @_;
	my $child_groups = $self->{'datastore'}->run_query(
		'SELECT id FROM scheme_groups LEFT JOIN scheme_group_group_members ON '
		  . 'scheme_groups.id=group_id WHERE parent_group_id=? ORDER BY display_order',
		$id,
		{ fetch => 'col_arrayref', cache => 'DownloadAllelesPage::print_child_group_scheme_tables' }
	);
	if (@$child_groups) {
		foreach (@$child_groups) {
			my $group_info = $self->{'datastore'}->get_scheme_group_info($_);
			my $new_level  = $level;
			last if $new_level == 10;    #prevent runaway if child is set as the parent of a parental group
			$self->_print_group_scheme_tables($_);
			$self->_print_child_group_scheme_tables( $_, ++$new_level, $scheme_shown );
		}
	}
	return;
}

sub _print_group_scheme_tables {
	my ( $self, $id, $scheme_shown ) = @_;
	my $set_id     = $self->get_set_id;
	my $set_clause = $set_id ? " AND scheme_id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)" : '';
	my $schemes    = $self->{'datastore'}->run_query(
		'SELECT scheme_id FROM scheme_group_scheme_members LEFT JOIN schemes ON '
		  . "schemes.id=scheme_id WHERE group_id=? $set_clause ORDER BY display_order",
		$id,
		{ fetch => 'col_arrayref', cache => 'DownloadAllelesPage::print_group_scheme_tables' }
	);
	if (@$schemes) {
		foreach my $scheme_id (@$schemes) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
			$scheme_info->{'name'} =~ s/&/\&amp;/gx;
			$self->_print_scheme_table($scheme_id) if !$scheme_shown->{$scheme_id};
			$scheme_shown->{$scheme_id} = 1;
		}
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $q      = $self->{'cgi'};
	my $locus  = $q->param('locus');
	my $set_id = $self->get_set_id;
	if ($locus) {
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			say 'This function is not available for isolate databases.';
			return;
		}
		if ( ( $self->{'system'}->{'disable_seq_downloads'} // q() ) eq 'yes'
			&& !$self->is_admin )
		{
			say 'Allele sequence downloads are disabled for this database.';
			return;
		}
		$locus =~ s/%27/'/gx;    #Web-escaped locus
		if ( $self->{'datastore'}->is_locus($locus) ) {
			if ( $set_id && !$self->{'datastore'}->is_locus_in_set( $locus, $set_id ) ) {
				say "$locus is not available";
				return;
			}
			$self->_print_sequences($locus);
		} else {
			say "$locus is not a locus!";
		}
		return;
	}
	local $| = 1;
	$self->{'prefix'}  = BIGSdb::Utils::get_random();
	$self->{'outfile'} = "$self->{'config'}->{'tmp_dir'}/$self->{'prefix'}.txt";
	if ( defined $q->param('scheme_id') ) {
		my $scheme_id = $q->param('scheme_id');
		if ( !BIGSdb::Utils::is_int($scheme_id) ) {
			$logger->warn("Invalid scheme selected - $scheme_id");
			return;
		}
		if ( $scheme_id == -1 ) {
			my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
			foreach my $scheme (@$schemes) {
				$self->_print_scheme_table( $scheme->{'id'} );
			}
			$self->_print_scheme_table(0);
		} elsif ($set_id) {
			if ( $scheme_id && !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
				$logger->warn("Scheme $scheme_id is not available.");
				return;
			}
		}
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		$self->_print_scheme_table($scheme_id);
		$self->_print_table_link;
		return;
	} elsif ( defined $q->param('group_id') ) {
		my $group_id = $q->param('group_id');
		if ( !BIGSdb::Utils::is_int($group_id) ) {
			$logger->warn("Invalid group selected - $group_id");
			return;
		}
		my $scheme_ids;
		if ( $group_id == 0 ) {
			my $set_clause = $set_id ? " AND id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)" : q();
			my $qry = 'SELECT id FROM schemes WHERE id NOT IN (SELECT scheme_id FROM scheme_group_scheme_members) '
			  . "$set_clause ORDER BY display_order";
			$scheme_ids = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
			foreach my $scheme_id (@$scheme_ids) {
				my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
				$self->_print_scheme_table($scheme_id);
			}
		} else {
			my $scheme_shown_ref;
			$self->_print_group_scheme_tables( $group_id, $scheme_shown_ref );
			$self->_print_child_group_scheme_tables( $group_id, 1, $scheme_shown_ref );
		}
		$self->_print_table_link;
		return;
	}
	say q(<h1>Download allele sequences</h1>);
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say q(<div class="box" id="statusbad"><p>This function is not available for isolate databases.</p></div>);
		return;
	}
	if ( ( $self->{'system'}->{'disable_seq_downloads'} // '' ) eq 'yes' && !$self->is_admin ) {
		say q(<div class="box" id="statusbad"><p>Allele sequence downloads are )
		  . q(disabled for this database.</p></div>);
		return;
	}
	my $all_loci = $self->{'datastore'}->get_loci;
	if ( !@$all_loci ) {
		say q(<div class="box" id="statusbad"><p>No loci have been defined for this database.</p></div>);
		return;
	}
	say q(<div class="box" id="resultstable">);
	if ( $q->param('tree') ) {
		say qq(<p>Select loci by scheme | <a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . q(page=downloadAlleles&amp;list=1">Alphabetical list</a>  | )
		  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles">)
		  . q(All loci by scheme</a></p>);
		$self->_print_tree;
	} elsif ( $q->param('list') ) {
		say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . q(page=downloadAlleles&amp;tree=1">Select loci by scheme</a> | Alphabetical list | )
		  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles">)
		  . q(All loci by scheme</a></p>);
		$self->_print_alphabetical_list;
	} else {
		say qq(<p><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . q(page=downloadAlleles&amp;tree=1\">Select loci by scheme</a>  | )
		  . qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
		  . q(page=downloadAlleles&amp;list=1">Alphabetical list</a> | All loci by scheme</p>);
		$self->_print_all_loci_by_scheme;
	}
	say q(</div>);
	return;
}

sub _print_table_link {
	my ($self) = @_;
	if ( $self->{'text_buffer'} ) {
		say qq(<p style="margin-top:1em">Download table: <a href="/tmp/$self->{'prefix'}.txt">tab-delimited text</a>);
		open( my $fh, '>:encoding(utf8)', $self->{'outfile'} )
		  || $logger->error("Cannot open $self->{'outfile'} for appending");
		say $fh $self->{'text_buffer'};
		close $fh;
		my $excel = BIGSdb::Utils::text2excel( $self->{'outfile'} );
		if ( -e $excel ) {
			say qq( | <a href="/tmp/$self->{'prefix'}.xlsx">Excel format</a>);
		}
		say q(</p>);
	}
	return;
}

sub _print_all_loci_by_scheme {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	foreach my $scheme (@$schemes) {
		$self->_print_scheme_table( $scheme->{'id'} );
	}
	$self->_print_scheme_table(0);
	$self->_print_table_link;
	return;
}

sub _print_scheme_table {
	my ( $self, $scheme_id ) = @_;
	my $set_id = $self->get_set_id;
	my $loci =
	    $scheme_id
	  ? $self->{'datastore'}->get_scheme_loci($scheme_id)
	  : $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
	my $td = 1;
	my ( $scheme_info, $scheme_descs_exist, $scheme_aliases_exist, $scheme_curators_exist );
	if ($scheme_id) {
		$scheme_descs_exist = $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM locus_descriptions LEFT JOIN scheme_members ON '
			  . 'locus_descriptions.locus=scheme_members.locus WHERE scheme_id=?)',
			$scheme_id,
			{ cache => 'DownloadAllelesPage::print_scheme_table::scheme_descs_exist' }
		);
		$scheme_aliases_exist = $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM locus_aliases LEFT JOIN scheme_members ON '
			  . 'locus_aliases.locus=scheme_members.locus WHERE scheme_id=?)',
			$scheme_id,
			{ cache => 'DownloadAllelesPage::print_scheme_table::scheme_aliases_exists' }
		);
		$scheme_curators_exist = $self->{'datastore'}->run_query(
			'SELECT EXISTS(SELECT * FROM locus_curators LEFT JOIN scheme_members ON '
			  . 'locus_curators.locus=scheme_members.locus WHERE scheme_id=? AND '
			  . '(hide_public IS NULL OR NOT hide_public))',
			$scheme_id,
			{ cache => 'DownloadAllelesPage::print_scheme_table::scheme_curators_exists' }
		);
		$scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
	} else {
		$scheme_descs_exist =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM locus_descriptions LEFT JOIN scheme_members ON '
			  . 'locus_descriptions.locus=scheme_members.locus WHERE scheme_id IS NULL)' );
		$scheme_aliases_exist =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM locus_aliases LEFT JOIN scheme_members ON '
			  . 'locus_aliases.locus=scheme_members.locus WHERE scheme_id IS NULL)' );
		$scheme_curators_exist =
		  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM locus_curators LEFT JOIN scheme_members ON '
			  . 'locus_curators.locus=scheme_members.locus WHERE scheme_id IS NULL AND '
			  . '(hide_public IS NULL OR NOT hide_public))' );
		$scheme_info->{'name'} = 'Other loci';
	}
	return if !@$loci;
	$scheme_info->{'name'} =~ s/\&/\&amp;/gx;
	say qq(<h2><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;)
	  . qq(page=schemeInfo&amp;scheme_id=$scheme_id">$scheme_info->{'name'}</a></h2>);
	my $flags = $self->get_scheme_flags($scheme_id);
	if ($flags){
		say qq(<div style="margin-bottom:1em">$flags</div>);
	}
	say q(<div class="scrollable"><table class="resultstable">);
	$self->_print_table_header_row(
		{
			descs_exist    => $scheme_descs_exist,
			aliases_exist  => $scheme_aliases_exist,
			curators_exist => $scheme_curators_exist
		}
	);
	foreach my $locus (@$loci) {
		$self->_print_locus_row(
			$locus,
			$self->clean_locus($locus),
			{
				td             => $td,
				descs_exist    => $scheme_descs_exist,
				aliases_exist  => $scheme_aliases_exist,
				curators_exist => $scheme_curators_exist,
				scheme         => $scheme_info->{'name'}
			}
		);
		$td = $td == 1 ? 2 : 1;
		if ( $ENV{'MOD_PERL'} ) {
			return if $self->{'mod_perl_request'}->connection->aborted;
			$self->{'mod_perl_request'}->rflush;
		}
	}
	say q(</table></div>);
	return;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Download allele sequences - $desc";
}

sub _print_sequences {
	my ( $self, $locus ) = @_;
	my $set_id = $self->get_set_id;
	my $locus_info = $self->{'datastore'}->get_locus_info( $locus, { set_id => $set_id } );
	( my $cleaned = $locus_info->{'set_name'} // $locus ) =~ s/^_//x;
	$cleaned =~ tr/ /_/;
	my $qry = q(SELECT allele_id,sequence FROM sequences WHERE locus=? AND allele_id NOT IN ('0', 'N') ORDER BY )
	  . ( $locus_info->{'allele_id_format'} eq 'integer' ? q(CAST(allele_id AS int)) : q(allele_id) );
	my $alleles = $self->{'datastore'}->run_query( $qry, $locus, { fetch => 'all_arrayref' } );
	if ( !@$alleles ) {
		say 'Cannot retrieve sequences.';
		return;
	}
	my $delimiter = $self->{'cgi'}->param('delimiter') ? $self->{'cgi'}->param('delimiter') : '_';
	foreach my $allele (@$alleles) {
		say ">$cleaned$delimiter$allele->[0]";
		my $cleaned_seq = BIGSdb::Utils::break_line( $allele->[1], 60 ) || '';
		say "$cleaned_seq";
	}
	return;
}

sub _print_table_header_row {
	my ( $self, $options ) = @_;
	say q(<tr><th>Locus</th><th>Download</th><th>Type</th><th>Alleles</th><th>Length (setting)</th>)
	  . q(<th>Min length</th><th>Max length</th>);
	say q(<th>Full name/product</th>) if $options->{'descs_exist'};
	say q(<th>Aliases</th>)           if $options->{'aliases_exist'};
	say q(<th>Curator(s)</th>)        if $options->{'curators_exist'};
	say q(<th>Last updated</th></tr>);
	return;
}

sub _query_locus_stats {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'locus_stats'} ) {
		$self->{'cache'}->{'locus_stats'} =
		  $self->{'datastore'}
		  ->run_query( 'SELECT * FROM locus_stats', undef, { fetch => 'all_hashref', key => 'locus' } );
	}
	return;
}

sub _query_locus_descriptions {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'desc'} ) {
		$self->{'cache'}->{'desc'} =
		  $self->{'datastore'}->run_query( 'SELECT locus,full_name,product FROM locus_descriptions',
			undef, { fetch => 'all_hashref', key => 'locus' } );
	}
	return;
}

sub _query_locus_aliases {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'aliases'} ) {
		my $all_aliases =
		  $self->{'datastore'}
		  ->run_query( 'SELECT locus,alias FROM locus_aliases ORDER BY alias', undef, { fetch => 'all_arrayref' } );
		foreach my $alias (@$all_aliases) {
			push @{ $self->{'cache'}->{'aliases'}->{ $alias->[0] } }, $alias->[1];
		}
	}
	return;
}

sub _query_curators {
	my ($self) = @_;
	if ( !$self->{'cache'}->{'curators'} ) {
		my $curator_ids =
		  $self->{'datastore'}
		  ->run_query( 'SELECT locus,curator_id FROM locus_curators WHERE hide_public IS NULL OR NOT hide_public',
			undef, { fetch => 'all_arrayref' } );
		foreach my $curator (@$curator_ids) {
			push @{ $self->{'cache'}->{'curators'}->{ $curator->[0] } }, $curator->[1];
		}
	}
	return;
}

sub _print_locus_row {
	my ( $self, $locus, $display_name, $options ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	$self->_query_locus_stats;
	my $count = $self->{'cache'}->{'locus_stats'}->{$locus}->{'allele_count'};
	print qq(<tr class="td$options->{'td'}"><td><a href="$self->{'system'}->{'script_name'}?)
	  . qq(db=$self->{'instance'}&amp;page=locusInfo&amp;locus=$locus">$display_name</a></td><td> );
	print qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles&amp;)
	  . qq(locus=$locus"> <span class="file_icon fa fa-download"></span></a>)
	  if $count;
	print qq(</td><td>$locus_info->{'data_type'}</td><td>$count</td>);
	if ( $locus_info->{'length_varies'} ) {
		print q(<td>Variable: );
		if ( $locus_info->{'min_length'} || $locus_info->{'max_length'} ) {
			print q[(];
			print qq[$locus_info->{'min_length'} min] if $locus_info->{'min_length'};
			print q[; ]                               if $locus_info->{'min_length'} && $locus_info->{'max_length'};
			print qq[$locus_info->{'max_length'} max] if $locus_info->{'max_length'};
			print q[)];
		} else {
			print q(No limits set);
		}
		say q(</td>);
	} else {
		say qq(<td>Fixed: $locus_info->{'length'} ) . ( $locus_info->{'data_type'} eq 'DNA' ? 'bp' : 'aa' ) . q(</td>);
	}
	$self->{'cache'}->{'locus_stats'}->{$locus}->{'min_length'} //= q();
	$self->{'cache'}->{'locus_stats'}->{$locus}->{'max_length'} //= q();
	print qq(<td>$self->{'cache'}->{'locus_stats'}->{$locus}->{'min_length'}</td>);
	print qq(<td>$self->{'cache'}->{'locus_stats'}->{$locus}->{'max_length'}</td>);
	my $products;
	if ( $options->{'descs_exist'} ) {
		$self->_query_locus_descriptions;
		my $desc = $self->{'cache'}->{'desc'}->{$locus};
		my @names_product;
		foreach my $field (qw (full_name product)) {
			push @names_product, $desc->{$field} if $desc->{$field};
		}
		local $" = ' / ';
		$products = qq(@names_product);
		print qq(<td>$products</td>);
	}
	my $aliases = [];
	if ( $options->{'aliases_exist'} ) {
		$self->_query_locus_aliases;
		$aliases = $self->{'cache'}->{'aliases'}->{$locus} // [];
		local $" = '; ';
		say "<td>@$aliases</td>";
	}
	my $curator_list;
	if ( $options->{'curators_exist'} ) {
		$self->_query_curators;
		my $locus_curators = $self->{'cache'}->{'curators'}->{$locus} // [];
		my $info;
		foreach my $curator_id (@$locus_curators) {
			$info->{$curator_id} = $self->{'datastore'}->get_user_info($curator_id);
		}
		my $first = 1;
		print q(<td>);
		foreach my $curator_id ( sort { $info->{$a}->{'surname'} cmp $info->{$b}->{'surname'} } @$locus_curators ) {
			print ', ' if !$first;
			$curator_list .= '; ' if !$first;
			my $first_initial =
			  $info->{$curator_id}->{'first_name'} ? substr( $info->{$curator_id}->{'first_name'}, 0, 1 ) . q(. ) : q();
			print qq(<a href="mailto:$info->{$curator_id}->{'email'}">) if $info->{$curator_id}->{'email'};
			print qq($first_initial$info->{$curator_id}->{'surname'});
			$curator_list .= qq($first_initial$info->{$curator_id}->{'surname'});
			print q(</a>) if $info->{$curator_id}->{'email'};
			$first = 0;
		}
		print q(</td>);
	}
	my $last_updated = $self->{'cache'}->{'locus_stats'}->{$locus}->{'datestamp'};
	$last_updated //= q();
	say "<td>$last_updated</td></tr>";
	if ( !$self->{'text_buffer'} ) {
		$self->{'text_buffer'} .=
		    ( $options->{'scheme'} ? "scheme\t" : '' )
		  . "locus\tdata type\talleles\tlength varies\tstandard length\tmin length (setting)\t"
		  . "max length (setting)\tmin length\tmax_length\tfull name/product\taliases\tcurators\n";
	}
	local $" = '; ';
	$self->{'text_buffer'} .=
	    ( $options->{'scheme'} ? "$options->{'scheme'}\t" : '' )
	  . "$locus\t$locus_info->{'data_type'}\t$count\t"
	  . ( $locus_info->{'length_varies'} ? 'true' : 'false' ) . qq(\t)
	  . ( $locus_info->{'length'}     // '' ) . qq(\t)
	  . ( $locus_info->{'min_length'} // '' ) . qq(\t)
	  . ( $locus_info->{'max_length'} // '' ) . qq(\t)
	  . $self->{'cache'}->{'locus_stats'}->{$locus}->{'min_length'} . qq(\t)
	  . $self->{'cache'}->{'locus_stats'}->{$locus}->{'max_length'} . qq(\t)
	  . ( $products     // '' ) . qq(\t)
	  . ( "@$aliases"   // '' ) . qq(\t)
	  . ( $curator_list // '' ) . qq(\n);
	return;
}

sub _print_alphabetical_list {
	my ($self) = @_;
	my $locus_pattern = LOCUS_PATTERN;
	foreach my $letter ( 0 .. 9, 'A' .. 'Z', q(') ) {
		if ( $ENV{'MOD_PERL'} ) {
			return if $self->{'mod_perl_request'}->connection->aborted;
			$self->{'mod_perl_request'}->rflush;
		}
		my $qry_letter = $letter =~ /\d/x ? '\\\_' . $letter : $letter;
		my ( $main, $common, $aliases ) = $self->_get_loci_by_letter($qry_letter);
		if ( @$main || @$common || @$aliases ) {
			my %names;
			$names{"l_$_"}                            = $self->clean_locus($_)             foreach @$main;
			$names{"cn_$_->{'id'}"}                   = "$_->{'common_name'} [$_->{'id'}]" foreach @$common;
			$names{"la_$_->{'locus'}||$_->{'alias'}"} = "$_->{'alias'} [$_->{'locus'}]"    foreach @$aliases;
			my $descs_exist = $self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM locus_descriptions WHERE locus IN '
				  . '(SELECT id FROM loci WHERE UPPER(id) LIKE ? OR upper(common_name) LIKE ?) OR locus IN '
				  . '(SELECT locus FROM locus_aliases WHERE UPPER(alias) LIKE ?))',
				[ ("$qry_letter%") x 3 ],
				{ cache => 'DownloadAllelesPage::print_alphabetical_list::descs_exists' }
			);
			my $aliases_exist =
			  $self->{'datastore'}->run_query( 'SELECT EXISTS(SELECT * FROM locus_aliases WHERE alias LIKE ?)',
				"$qry_letter%", { cache => 'DownloadAllelesPage::print_alphabetical_list::aliases_exists' } );
			my $curators_exist = $self->{'datastore'}->run_query(
				'SELECT EXISTS(SELECT * FROM locus_curators WHERE (locus IN '
				  . '(SELECT id FROM loci WHERE UPPER(id) LIKE ? OR UPPER(common_name) LIKE ?) OR '
				  . 'locus IN (SELECT locus FROM locus_aliases WHERE UPPER(alias) LIKE ?)) AND NOT hide_public)',
				[ ("$qry_letter%") x 3 ],
				{ cache => 'DownloadAllelesPage::print_alphabetical_list::curators_exists' }
			);
			say qq(<h2>$letter</h2>);
			say q(<table class="resultstable">);
			$self->_print_table_header_row(
				{ descs_exist => $descs_exist, aliases_exist => $aliases_exist, curators_exist => $curators_exist } );
			my $td = 1;

			foreach my $locus ( sort { $names{$a} cmp $names{$b} } keys %names ) {
				my $locus_name = $locus =~ /$locus_pattern/x ? $1 : undef;
				$self->_print_locus_row(
					$locus_name,
					$names{$locus},
					{
						td             => $td,
						descs_exist    => $descs_exist,
						aliases_exist  => $aliases_exist,
						curators_exist => $curators_exist,
					}
				);
				$td = $td == 1 ? 2 : 1;
			}
			say q(</table>);
		}
	}
	$self->_print_table_link;
	return;
}

sub _get_loci_by_letter {
	my ( $self, $letter ) = @_;
	my $set_id = $self->get_set_id;

	#make sure 'id IN' has a space before it - used in the substitution a
	#few lines on (also matches scheme_id otherwise).
	my $set_clause =
	  $set_id
	  ? 'AND ( id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE '
	  . "set_id=$set_id)) OR id IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	my $main = $self->{'datastore'}->run_query( "SELECT id FROM loci WHERE UPPER(id) LIKE ? $set_clause",
		"$letter%", { fetch => 'col_arrayref', cache => 'DownloadAllelePage::get_loci_by_letter::main' } );
	my $common =
	  $self->{'datastore'}->run_query( "SELECT id,common_name FROM loci WHERE UPPER(common_name) LIKE ? $set_clause",
		"$letter%",
		{ fetch => 'all_arrayref', slice => {}, cache => 'DownloadAllelePage::get_loci_by_letter::common' } );
	$set_clause =~ s/ id IN/ locus IN/g;
	my $aliases =
	  $self->{'datastore'}->run_query( "SELECT locus,alias FROM locus_aliases WHERE alias ILIKE ? $set_clause",
		"$letter%",
		{ fetch => 'all_arrayref', slice => {}, cache => 'DownloadAllelePage::get_loci_by_letter::aliases' } );
	return ( $main, $common, $aliases );
}
1;
