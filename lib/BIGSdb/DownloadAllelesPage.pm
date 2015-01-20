#Written by Keith Jolley
#Copyright (c) 2010-2015, University of Oxford
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
use BIGSdb::Page qw(LOCUS_PATTERN);

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
	say qq(<p>Click within the tree to display details of loci belonging to schemes or groups of schemes - clicking a group folder will )
	  . qq(display the loci for all schemes within the group and any subgroups. Click the nodes to expand/collapse.</p>\n)
	  . qq(<noscript><p class="highlight">Enable Javascript to enhance your viewing experience.</p></noscript>)
	  . qq(<div id="tree" class="tree">);
	say $self->get_tree(undef);
	say qq(</div>\n<div id="scheme_table"></div>);
	return;
}

sub _print_child_group_scheme_tables {
	my ( $self, $id, $level, $scheme_shown ) = @_;
	my $child_groups = $self->{'datastore'}->run_query(
		"SELECT id FROM scheme_groups LEFT JOIN scheme_group_group_members ON "
		  . "scheme_groups.id=group_id WHERE parent_group_id=? ORDER BY display_order",
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
		"SELECT scheme_id FROM scheme_group_scheme_members LEFT JOIN schemes ON "
		  . "schemes.id=scheme_id WHERE group_id=? $set_clause ORDER BY display_order",
		$id,
		{ fetch => 'col_arrayref', cache => 'DownloadAllelesPage::print_group_scheme_tables' }
	);
	if (@$schemes) {
		foreach my $scheme_id (@$schemes) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
			$scheme_info->{'description'} =~ s/&/\&amp;/g;
			$self->_print_scheme_table( $scheme_id, $scheme_info->{'description'} ) if !$scheme_shown->{$scheme_id};
			$scheme_shown->{$scheme_id} = 1;
		}
	}
	return;
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('locus') ) {
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			say "This function is not available for isolate databases.";
			return;
		}
		if ( $self->{'system'}->{'disable_seq_downloads'} && $self->{'system'}->{'disable_seq_downloads'} eq 'yes' && !$self->is_admin ) {
			say "Allele sequence downloads are disabled for this database.";
			return;
		}
		my $locus = $q->param('locus');
		$locus =~ s/%27/'/g;    #Web-escaped locus
		if ( $self->{'datastore'}->is_locus($locus) ) {
			my $set_id = $self->get_set_id;
			if ($set_id) {
				if ( !$self->{'datastore'}->is_locus_in_set( $locus, $set_id ) ) {
					say "$locus is not available";
					return;
				}
			}
			$self->_print_sequences($locus);
		} else {
			say "$locus is not a locus!";
		}
		return;
	}
	local $| = 1;
	my $set_id = $self->get_set_id;
	$self->{'prefix'}  = BIGSdb::Utils::get_random();
	$self->{'outfile'} = "$self->{'config'}->{'tmp_dir'}/$self->{'prefix'}.txt";
	if ( defined $q->param('scheme_id') ) {
		my $scheme_id = $q->param('scheme_id');
		$self->_create_temp_allele_count_table( { scheme_id => $scheme_id } );
		if ( !BIGSdb::Utils::is_int($scheme_id) ) {
			$logger->warn("Invalid scheme selected - $scheme_id");
			return;
		}
		if ( $scheme_id == -1 ) {
			my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
			foreach my $scheme (@$schemes) {
				$self->_print_scheme_table( $scheme->{'id'}, $scheme->{'description'} );
			}
			$self->_print_scheme_table( 0, 'Other loci' );
		} elsif ($set_id) {
			if ( $scheme_id && !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
				$logger->warn("Scheme $scheme_id is not available.");
				return;
			}
		}
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		my $desc = $scheme_id ? $scheme_info->{'description'} : 'Other loci';
		$self->_print_scheme_table( $scheme_id, $desc );
		$self->_print_table_link;
		return;
	} elsif ( defined $q->param('group_id') ) {
		my $group_id = $q->param('group_id');
		if ( !BIGSdb::Utils::is_int($group_id) ) {
			$logger->warn("Invalid group selected - $group_id");
			return;
		}
		$self->_create_temp_allele_count_table;
		my $scheme_ids;
		if ( $group_id == 0 ) {
			my $set_clause = $set_id ? " AND id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)" : '';
			my $qry = "SELECT id FROM schemes WHERE id NOT IN (SELECT scheme_id FROM scheme_group_scheme_members) "
			  . "$set_clause ORDER BY display_order";
			$scheme_ids = $self->{'datastore'}->run_query( $qry, undef, { fetch => 'col_arrayref' } );
			foreach my $scheme_id (@$scheme_ids) {
				my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
				$self->_print_scheme_table( $scheme_id, $scheme_info->{'description'} );
			}
		} else {
			my $scheme_shown_ref;
			$self->_print_group_scheme_tables( $group_id, $scheme_shown_ref );
			$self->_print_child_group_scheme_tables( $group_id, 1, $scheme_shown_ref );
		}
		$self->_print_table_link;
		return;
	}
	say "<h1>Download allele sequences</h1>";
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		say "<div class=\"box\" id=\"statusbad\"><p>This function is not available for isolate databases.</p></div>";
		return;
	}
	if ( ( $self->{'system'}->{'disable_seq_downloads'} // '' ) eq 'yes' && !$self->is_admin ) {
		say "<div class=\"box\" id=\"statusbad\"><p>Allele sequence downloads are disabled for this database.</p></div>";
		return;
	}
	my $all_loci = $self->{'datastore'}->get_loci;
	if ( !@$all_loci ) {
		say "<div class=\"box\" id=\"statusbad\"><p>No loci have been defined for this database.</p></div>";
		return;
	}
	say "<div class=\"box\" id=\"resultstable\">";
	if ( $q->param('tree') ) {
		say "<p>Loci by scheme | "
		  . "<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles&amp;list=1\">"
		  . "Alphabetical list</a>"
		  . " | <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles\">"
		  . "All loci by scheme</a></p>";
		$self->_print_tree;
	} elsif ( $q->param('list') ) {
		say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles&amp;tree=1\">"
		  . "Loci by scheme</a>"
		  . " | Alphabetical list"
		  . " | <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles\">"
		  . "All loci by scheme</a></p>";
		$self->_create_temp_allele_count_table;
		$self->_print_alphabetical_list;
	} else {
		say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles&amp;tree=1\">"
		  . "Loci by scheme</a>"
		  . " | <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles&amp;list=1\">"
		  . "Alphabetical list</a>"
		  . " | All loci by scheme</p>";
		$self->_create_temp_allele_count_table;
		$self->_print_all_loci_by_scheme;
	}
	say "</div>";
	return;
}

sub _print_table_link {
	my ($self) = @_;
	if ( -e $self->{'outfile'} ) {
		say qq(<p style="margin-top:1em">Download table: <a href="/tmp/$self->{'prefix'}.txt">tab-delimited text</a>);
		my $excel = BIGSdb::Utils::text2excel( $self->{'outfile'} );
		if ( -e $excel ) {
			say qq( | <a href="/tmp/$self->{'prefix'}.xlsx">Excel format</a>);
		}
		say "</p>";
	}
	return;
}

sub _print_all_loci_by_scheme {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my $schemes = $self->{'datastore'}->get_scheme_list( { set_id => $set_id } );
	foreach my $scheme (@$schemes) {
		if ( $ENV{'MOD_PERL'} ) {
			return if $self->{'mod_perl_request'}->connection->aborted;
			$self->{'mod_perl_request'}->rflush;
		}
		$self->_print_scheme_table( $scheme->{'id'}, $scheme->{'description'} );
	}
	$self->_print_scheme_table( 0, 'Other loci' );
	$self->_print_table_link;
	return;
}

sub _print_scheme_table {
	my ( $self, $scheme_id, $desc ) = @_;
	my $set_id = $self->get_set_id;
	my $loci =
	  $scheme_id ? $self->{'datastore'}->get_scheme_loci($scheme_id) : $self->{'datastore'}->get_loci_in_no_scheme( { set_id => $set_id } );
	my $td = 1;
	my ( $scheme_descs_exist, $scheme_aliases_exist, $scheme_curators_exist );
	if ($scheme_id) {
		$scheme_descs_exist = $self->{'datastore'}->run_query(
			"SELECT EXISTS(SELECT * FROM locus_descriptions LEFT JOIN scheme_members ON locus_descriptions.locus=scheme_members.locus "
			  . "WHERE scheme_id=?)",
			$scheme_id
		);
		$scheme_aliases_exist = $self->{'datastore'}->run_query(
			"SELECT EXISTS(SELECT * FROM locus_aliases LEFT JOIN scheme_members ON locus_aliases.locus=scheme_members.locus WHERE "
			  . "scheme_id=?)",
			$scheme_id
		);
		$scheme_curators_exist = $self->{'datastore'}->run_query(
			"SELECT EXISTS(SELECT * FROM locus_curators LEFT JOIN scheme_members ON locus_curators.locus=scheme_members.locus "
			  . "WHERE scheme_id=? AND (hide_public IS NULL OR NOT hide_public))",
			$scheme_id
		);
	} else {
		$scheme_descs_exist =
		  $self->{'datastore'}->run_query(
			    "SELECT EXISTS(SELECT * FROM locus_descriptions LEFT JOIN scheme_members ON locus_descriptions.locus=scheme_members.locus "
			  . "WHERE scheme_id IS NULL)" );
		$scheme_aliases_exist =
		  $self->{'datastore'}->run_query(
			    "SELECT EXISTS(SELECT * FROM locus_aliases LEFT JOIN scheme_members ON locus_aliases.locus=scheme_members.locus WHERE "
			  . "scheme_id IS NULL)" );
		$scheme_curators_exist =
		  $self->{'datastore'}->run_query(
			    "SELECT EXISTS(SELECT * FROM locus_curators LEFT JOIN scheme_members ON locus_curators.locus=scheme_members.locus "
			  . "WHERE scheme_id IS NULL AND (hide_public IS NULL OR NOT hide_public))" );
	}
	if (@$loci) {
		$desc =~ s/\&/\&amp;/g;
		say "<h2>$desc</h2>";
		say "<table class=\"resultstable\">";
		$self->_print_table_header_row(
			{ descs_exist => $scheme_descs_exist, aliases_exist => $scheme_aliases_exist, curators_exist => $scheme_curators_exist } );
		foreach my $locus (@$loci) {
			$self->_print_locus_row(
				$locus,
				$self->clean_locus($locus),
				{
					td             => $td,
					descs_exist    => $scheme_descs_exist,
					aliases_exist  => $scheme_aliases_exist,
					curators_exist => $scheme_curators_exist,
					scheme         => $desc
				}
			);
			$td = $td == 1 ? 2 : 1;
		}
		say "</table>";
	}
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
	( my $cleaned = $locus_info->{'set_name'} // $locus ) =~ s/^_//;
	$cleaned =~ tr/ /_/;
	my $qry = "SELECT allele_id,sequence FROM sequences WHERE locus=? AND allele_id NOT IN ('0', 'N') ORDER BY "
	  . ( $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST(allele_id AS int)' : 'allele_id' );
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($locus) };

	if ($@) {
		$logger->error($@);
		say "Can't retrieve sequences.";
		return;
	}
	my $delimiter = $self->{'cgi'}->param('delimiter') ? $self->{'cgi'}->param('delimiter') : '_';
	while ( my ( $id, $sequence ) = $sql->fetchrow_array ) {
		say ">$cleaned$delimiter$id";
		my $cleaned_seq = BIGSdb::Utils::break_line( $sequence, 60 ) || '';
		say "$cleaned_seq";
	}
	return;
}

sub _print_table_header_row {
	my ( $self, $options ) = @_;
	say "<tr><th>Locus</th><th>Download</th><th>Type</th><th>Alleles</th><th>Length</th>";
	say "<th>Full name/product</th>" if $options->{'descs_exist'};
	say "<th>Aliases</th>"           if $options->{'aliases_exist'};
	say "<th>Curator(s)</th>"        if $options->{'curators_exist'};
	say "<th>Last updated</th>";
	say "</tr>";
	return;
}

sub _print_locus_row {
	my ( $self, $locus, $display_name, $options ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my ( $count, $last_updated ) = $self->{'datastore'}->run_query( "SELECT allele_count, last_updated FROM allele_count WHERE locus=?",
		$locus, { cache => 'DownloadAllelesPage::print_locus_row::count' } );
	$count //= 0;
	print qq(<tr class="td$options->{'td'}"><td>$display_name );
	print qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=locusInfo&amp;locus=$locus" )
	  . qq(class="info_tooltip">&nbsp;i&nbsp;</a>);
	print "</td><td>";
	print qq(<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles&amp;locus=$locus" )
	  . qq(class="downloadbutton">&darr;</a>)
	  if $count;
	print "</td><td>$locus_info->{'data_type'}</td><td>$count</td>";

	if ( $locus_info->{'length_varies'} ) {
		print "<td>Variable: ";
		if ( $locus_info->{'min_length'} || $locus_info->{'max_length'} ) {
			print "(";
			print "$locus_info->{'min_length'} min" if $locus_info->{'min_length'};
			print "; "                              if $locus_info->{'min_length'} && $locus_info->{'max_length'};
			print "$locus_info->{'max_length'} max" if $locus_info->{'max_length'};
			print ")";
		} else {
			print "No limits set";
		}
		print "</td>\n";
	} else {
		print "<td>Fixed: $locus_info->{'length'} " . ( $locus_info->{'data_type'} eq 'DNA' ? 'bp' : 'aa' ) . "</td>\n";
	}
	my $products;
	if ( $options->{'descs_exist'} ) {
		my $desc = $self->{'datastore'}->run_query( "SELECT full_name,product FROM locus_descriptions WHERE locus=?",
			$locus, { fetch => 'row_hashref', cache => 'DownloadAllelesPage::print_locus_row::desc' } );
		my @names_product;
		if ( $desc->{'full_name'} ) {
			$desc->{'full_name'} =~ s/[\r\n]/ /g;
			push @names_product, $desc->{'full_name'}
		}
		if ( $desc->{'product'} ) {
			$desc->{'product'} =~ s/[\r\n]/ /g;
			push @names_product, $desc->{'product'};
		}
		local $" = ' / ';
		$products = "@names_product";
		print "<td>$products</td>";
	}
	my $aliases = [];
	if ( $options->{'aliases_exist'} ) {
		$aliases = $self->{'datastore'}->run_query( "SELECT alias FROM locus_aliases WHERE locus=? ORDER BY alias",
			$locus, { fetch => 'col_arrayref', cache => 'DownloadAllelesPage::print_locus_row::aliases' } );
		local $" = '; ';
		print "<td>@$aliases</td>\n";
	}
	my $curator_list;
	if ( $options->{'curators_exist'} ) {
		my $curator_ids =
		  $self->{'datastore'}
		  ->run_query( "SELECT curator_id FROM locus_curators WHERE locus=? AND (hide_public IS NULL OR NOT hide_public)",
			$locus, { fetch => 'col_arrayref', cache => 'DownloadAllelesPage::print_locus_row::curators' } );
		my $info;
		foreach my $curator_id (@$curator_ids) {
			$info->{$curator_id} = $self->{'datastore'}->get_user_info($curator_id);
		}
		my $first = 1;
		print "<td>";
		foreach my $curator_id ( sort { $info->{$a}->{'surname'} cmp $info->{$b}->{'surname'} } @$curator_ids ) {
			print ', ' if !$first;
			$curator_list .= '; ' if !$first;
			my $first_initial = $info->{$curator_id}->{'first_name'} ? substr( $info->{$curator_id}->{'first_name'}, 0, 1 ) . '. ' : '';
			print qq(<a href="mailto:$info->{$curator_id}->{'email'}">) if $info->{$curator_id}->{'email'};
			print "$first_initial$info->{$curator_id}->{'surname'}";
			$curator_list .= "$first_initial$info->{$curator_id}->{'surname'}";
			print "</a>" if $info->{$curator_id}->{'email'};
			$first = 0;
		}
		print "</td>";
	}
	$last_updated //= '';
	say "<td>$last_updated</td></tr>";
	open( my $fh, '>>', $self->{'outfile'} ) || $logger->error("Can't open $self->{'outfile'} for appending");
	if ( !-s $self->{'outfile'} ) {
		say $fh ( $options->{'scheme'} ? "scheme\t" : '' )
		  . "locus\tdata type\talleles\tlength varies\tstandard length\tmin length\tmax length\tfull name/product\taliases\tcurators";
	}
	local $" = '; ';
	say $fh ( $options->{'scheme'} ? "$options->{'scheme'}\t" : '' )
	  . "$locus\t$locus_info->{'data_type'}\t$count\t"
	  . ( $locus_info->{'length_varies'} ? 'true' : 'false' ) . "\t"
	  . ( $locus_info->{'length'}     // '' ) . "\t"
	  . ( $locus_info->{'min_length'} // '' ) . "\t"
	  . ( $locus_info->{'max_length'} // '' ) . "\t"
	  . ( $products                   // '' ) . "\t"
	  . ( "@$aliases"                 // '' ) . "\t"
	  . ( $curator_list               // '' );
	close $fh;
	return;
}

sub _print_alphabetical_list {
	my ($self) = @_;
	my $locus_pattern = LOCUS_PATTERN;
	foreach my $letter ( 0 .. 9, 'A' .. 'Z', "'" ) {
		if ( $ENV{'MOD_PERL'} ) {
			return if $self->{'mod_perl_request'}->connection->aborted;
			$self->{'mod_perl_request'}->rflush;
		}
		my $qry_letter = $letter =~ /\d/ ? '\\\_' . $letter : $letter;
		my ( $main, $common, $aliases ) = $self->_get_loci_by_letter($qry_letter);
		if ( @$main || @$common || @$aliases ) {
			my %names;
			$names{"l_$_"}                            = $self->clean_locus($_)             foreach @$main;
			$names{"cn_$_->{'id'}"}                   = "$_->{'common_name'} [$_->{'id'}]" foreach @$common;
			$names{"la_$_->{'locus'}||$_->{'alias'}"} = "$_->{'alias'} [$_->{'locus'}]"    foreach @$aliases;
			my $descs_exist = $self->{'datastore'}->run_query(
				"SELECT EXISTS(SELECT * FROM locus_descriptions WHERE locus IN (SELECT id FROM loci WHERE UPPER(id) LIKE ? OR "
				  . "upper(common_name) LIKE ?) OR locus IN (SELECT locus FROM locus_aliases WHERE UPPER(alias) LIKE ?))",
				[ ("$qry_letter%") x 3 ],
				{ cache => 'DownloadAllelesPage::print_alphabetical_list::descs_exists' }
			);
			my $aliases_exist = $self->{'datastore'}->run_query( "SELECT EXISTS(SELECT * FROM locus_aliases WHERE alias LIKE ?)",
				"$qry_letter%", { cache => 'DownloadAllelesPage::print_alphabetical_list::aliases_exists' } );
			my $curators_exist = $self->{'datastore'}->run_query(
				"SELECT EXISTS(SELECT * FROM locus_curators WHERE (locus IN (SELECT id FROM loci WHERE UPPER(id) LIKE ? OR "
				  . "upper(common_name) LIKE ?) OR locus IN (SELECT locus FROM locus_aliases WHERE UPPER(alias) LIKE ?)) AND NOT "
				  . "hide_public)",
				[ ("$qry_letter%") x 3 ],
				{ cache => 'DownloadAllelesPage::print_alphabetical_list::curators_exists' }
			);
			print "<h2>$letter</h2>\n";
			print "<table class=\"resultstable\">";
			$self->_print_table_header_row(
				{ descs_exist => $descs_exist, aliases_exist => $aliases_exist, curators_exist => $curators_exist } );
			my $td = 1;

			foreach my $locus ( sort { $names{$a} cmp $names{$b} } keys %names ) {
				my $locus_name = $locus =~ /$locus_pattern/ ? $1 : undef;
				$self->_print_locus_row( $locus_name, $names{$locus},
					{ td => $td, descs_exist => $descs_exist, aliases_exist => $aliases_exist, curators_exist => $curators_exist, } );
				$td = $td == 1 ? 2 : 1;
			}
			print "</table>\n";
		}
	}
	$self->_print_table_link;
	return;
}

sub _get_loci_by_letter {
	my ( $self, $letter ) = @_;
	my $set_id = $self->get_set_id;

	#make sure 'id IN' has a space before it - used in the substitution a few lines on (also matches scheme_id otherwise).
	my $set_clause =
	  $set_id
	  ? "AND ( id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE "
	  . "set_id=$set_id)) OR id IN (SELECT locus FROM set_loci WHERE set_id=$set_id))"
	  : '';
	my $main = $self->{'datastore'}->run_query( "SELECT id FROM loci WHERE UPPER(id) LIKE ? $set_clause",
		"$letter%", { fetch => 'col_arrayref', cache => 'DownloadAllelePage::get_loci_by_letter::main' } );
	my $common = $self->{'datastore'}->run_query( "SELECT id,common_name FROM loci WHERE UPPER(common_name) LIKE ? $set_clause",
		"$letter%", { fetch => 'all_arrayref', slice => {}, cache => 'DownloadAllelePage::get_loci_by_letter::common' } );
	$set_clause =~ s/ id IN/ locus IN/g;
	my $aliases = $self->{'datastore'}->run_query( "SELECT locus,alias FROM locus_aliases WHERE alias ILIKE ? $set_clause",
		"$letter%", { fetch => 'all_arrayref', slice => {}, cache => 'DownloadAllelePage::get_loci_by_letter::aliases' } );
	return ( $main, $common, $aliases );
}

sub _create_temp_allele_count_table {
	my ( $self, $options ) = @_;
	$options = {} if ref $options ne 'HASH';
	my $scheme_clause = '';
	my $scheme_id     = $options->{'scheme_id'};
	if ( $scheme_id && $scheme_id > 0 && BIGSdb::Utils::is_int($scheme_id) ) {
		$scheme_clause = "AND EXISTS (SELECT * FROM scheme_members WHERE sequences.locus=scheme_members.locus AND scheme_id=$scheme_id)";
	}
	my $qry = "CREATE TEMP TABLE allele_count AS (SELECT locus, COUNT(allele_id) AS allele_count, MAX(datestamp) AS last_updated FROM "
	  . "sequences WHERE allele_id NOT IN ('N','0') $scheme_clause GROUP BY locus); CREATE INDEX i_tac ON allele_count (locus)";
	eval { $self->{'db'}->do($qry) };
	$logger->error($@) if $@;
	return;
}
1;
