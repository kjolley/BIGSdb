#Written by Keith Jolley
#Copyright (c) 2010-2012, University of Oxford
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
	if ( $self->{'cgi'}->param('locus') ) {
		$self->{'type'} = 'text';
		return;
	} elsif ( $self->{'cgi'}->param('no_header') ) {
		$self->{'type'}    = 'no_header';
		$self->{'noCache'} = 1;
		return;
	}
	$self->{$_} = 1 foreach qw (jQuery jQuery.jstree);
	return;
}

sub get_javascript {
	my ($self) = @_;
	return $self->get_tree_javascript;
}

sub _print_tree {
	my ($self) = @_;
	print << "HTML";
<p>Click within the tree to display details of loci belonging to schemes or groups of schemes - 
clicking a group folder will display the loci for all schemes within the group and any subgroups. 
Click the nodes to expand/collapse.</p>
<noscript>
<p class="highlight">Enable Javascript to enhance your viewing experience.</p>
</noscript>
<div id="tree" class="tree">
HTML
	say $self->get_tree(undef);
	say "</div>\n<div id=\"scheme_table\"></div>";
	return;
}

sub _print_child_group_scheme_tables {
	my ( $self, $id, $level, $scheme_shown ) = @_;
	my $child_groups = $self->{'datastore'}->run_list_query(
"SELECT id FROM scheme_groups LEFT JOIN scheme_group_group_members ON scheme_groups.id=group_id WHERE parent_group_id=? ORDER BY display_order",
		$id
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
	my $set_clause = '';
	if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
		$set_clause = " AND scheme_id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)"
		  if $set_id && BIGSdb::Utils::is_int($set_id);
	}
	my $qry =
"SELECT scheme_id FROM scheme_group_scheme_members LEFT JOIN schemes ON schemes.id=scheme_id WHERE group_id=? $set_clause ORDER BY display_order";
	my $schemes = $self->{'datastore'}->run_list_query( $qry, $id );
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
			if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
				my $set_id = $self->get_set_id;
				if ( $set_id && BIGSdb::Utils::is_int($set_id) ) {
					if ( !$self->{'datastore'}->is_locus_in_set( $locus, $set_id ) ) {
						say "$locus is not available";
						return;
					}
				} else {
					say "Set id must be an integer.";
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
	if ( defined $q->param('scheme_id') ) {
		my $scheme_id = $q->param('scheme_id');
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
		} elsif ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
			if ( !BIGSdb::Utils::is_int($set_id) ) {
				$logger->warn("Set id must be an integer.");
				return;
			}
			if ( $scheme_id && !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id ) ) {
				$logger->warn("Scheme $scheme_id is not available.");
				return;
			}
		}
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		my $desc = $scheme_id ? $scheme_info->{'description'} : 'Other loci';
		$self->_print_scheme_table( $scheme_id, $desc );
		return;
	} elsif ( defined $q->param('group_id') ) {
		my $group_id = $q->param('group_id');
		if ( !BIGSdb::Utils::is_int($group_id) ) {
			$logger->warn("Invalid group selected - $group_id");
			return;
		}
		my $scheme_ids;
		if ( $group_id == 0 ) {
			my $set_clause = '';
			if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
				$set_clause = " AND id IN (SELECT scheme_id FROM set_schemes WHERE set_id=$set_id)"
				  if $set_id && BIGSdb::Utils::is_int($set_id);
			}
			my $qry =
"SELECT id FROM schemes WHERE id NOT IN (SELECT scheme_id FROM scheme_group_scheme_members) $set_clause ORDER BY display_order";
			$scheme_ids = $self->{'datastore'}->run_list_query($qry);
			foreach my $scheme_id (@$scheme_ids) {
				my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
				$self->_print_scheme_table( $scheme_id, $scheme_info->{'description'} );
			}
		} else {
			my $scheme_shown_ref;
			$self->_print_group_scheme_tables( $group_id, $scheme_shown_ref );
			$self->_print_child_group_scheme_tables( $group_id, 1, $scheme_shown_ref );
		}
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
		$self->_print_alphabetical_list;
	} else {
		say "<p><a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles&amp;tree=1\">"
		  . "Loci by scheme</a>"
		  . " | <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles&amp;list=1\">"
		  . "Alphabetical list</a>"
		  . " | All loci by scheme</p>";
		$self->_print_all_loci_by_scheme;
	}
	say "</div>";
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
		$scheme_descs_exist = $self->{'datastore'}->run_simple_query(
"SELECT COUNT(*) FROM locus_descriptions LEFT JOIN scheme_members ON locus_descriptions.locus=scheme_members.locus WHERE scheme_id=?",
			$scheme_id
		)->[0];
		$scheme_aliases_exist =
		  $self->{'datastore'}->run_simple_query(
			"SELECT COUNT(*) FROM locus_aliases LEFT JOIN scheme_members ON locus_aliases.locus=scheme_members.locus WHERE scheme_id=?",
			$scheme_id )->[0];
		$scheme_curators_exist = $self->{'datastore'}->run_simple_query(
"SELECT COUNT(*) FROM locus_curators LEFT JOIN scheme_members ON locus_curators.locus=scheme_members.locus WHERE scheme_id=? AND (hide_public IS NULL OR NOT hide_public)",
			$scheme_id
		)->[0];
	} else {
		$scheme_descs_exist =
		  $self->{'datastore'}->run_simple_query(
"SELECT COUNT(*) FROM locus_descriptions LEFT JOIN scheme_members ON locus_descriptions.locus=scheme_members.locus WHERE scheme_id IS NULL"
		  )->[0];
		$scheme_aliases_exist =
		  $self->{'datastore'}->run_simple_query(
"SELECT COUNT(*) FROM locus_aliases LEFT JOIN scheme_members ON locus_aliases.locus=scheme_members.locus WHERE scheme_id IS NULL"
		  )->[0];
		$scheme_curators_exist =
		  $self->{'datastore'}->run_simple_query(
"SELECT COUNT(*) FROM locus_curators LEFT JOIN scheme_members ON locus_curators.locus=scheme_members.locus WHERE scheme_id IS NULL AND (hide_public IS NULL OR NOT hide_public)"
		  )->[0];
	}
	if (@$loci) {
		$desc =~ s/\&/\&amp;/g;
		print "<h2>$desc</h2>\n";
		print "<table class=\"resultstable\">";
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
					curators_exist => $scheme_curators_exist
				}
			);
			$td = $td == 1 ? 2 : 1;
		}
		print "</table>\n";
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
	my $qry = "SELECT allele_id,sequence FROM sequences WHERE locus=? ORDER BY "
	  . ( $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST(allele_id AS int)' : 'allele_id' );
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($locus) };

	if ($@) {
		$logger->error($@);
		print "Can't retrieve sequences.\n";
		return;
	}
	my $delimiter = $self->{'cgi'}->param('delimiter') ? $self->{'cgi'}->param('delimiter') : '_';
	while ( my ( $id, $sequence ) = $sql->fetchrow_array ) {
		print ">$cleaned$delimiter$id\n";
		my $cleaned_seq = BIGSdb::Utils::break_line( $sequence, 60 ) || '';
		print "$cleaned_seq\n";
	}
	return;
}

sub _print_table_header_row {
	my ( $self, $options ) = @_;
	print "<tr><th>Locus</th><th>Download</th><th>Type</th><th>Alleles</th><th>Length</th>";
	print "<th>Full name/product</th>" if $options->{'descs_exist'};
	print "<th>Aliases</th>\n"         if $options->{'aliases_exist'};
	print "<th>Curator(s)</th>\n"      if $options->{'curators_exist'};
	print "</tr>\n";
	return;
}

sub _print_locus_row {
	my ( $self, $locus, $display_name, $options ) = @_;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	if ( !$self->{'sql'}->{'count'} ) {
		$self->{'sql'}->{'count'} = $self->{'db'}->prepare("SELECT COUNT(*) FROM sequences WHERE locus=?");
	}
	if ( !$self->{'sql'}->{'desc'} ) {
		$self->{'sql'}->{'desc'} = $self->{'db'}->prepare("SELECT COUNT(*) FROM locus_descriptions WHERE locus=?");
	}
	if ( !$self->{'sql'}->{'name'} ) {
		$self->{'sql'}->{'name'} = $self->{'db'}->prepare("SELECT full_name,product FROM locus_descriptions WHERE locus=?");
	}
	if ( !$self->{'sql'}->{'alias'} ) {
		$self->{'sql'}->{'alias'} = $self->{'db'}->prepare("SELECT alias FROM locus_aliases WHERE locus=? ORDER BY alias");
	}
	if ( !$self->{'sql'}->{'curator'} ) {
		$self->{'sql'}->{'curator'} =
		  $self->{'db'}->prepare("SELECT curator_id FROM locus_curators WHERE locus=? AND (hide_public IS NULL OR NOT hide_public)");
	}
	eval { $self->{'sql'}->{'count'}->execute($locus) };
	$logger->($@) if $@;
	my ($count) = $self->{'sql'}->{'count'}->fetchrow_array;
	print "<tr class=\"td$options->{'td'}\"><td>$display_name ";
	eval { $self->{'sql'}->{'desc'}->execute($locus) };
	$logger->($@) if $@;
	my ($desc_exists) = $self->{'sql'}->{'desc'}->fetchrow_array;

	if ($desc_exists) {
		print
" <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=locusInfo&amp;locus=$locus\" class=\"info_tooltip\">&nbsp;i&nbsp;</a>";
	}
	print "</td><td>";
	print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles&amp;locus=$locus\" class=\"downloadbutton\">&darr;</a>"
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
	if ( $options->{'descs_exist'} ) {
		eval { $self->{'sql'}->{'name'}->execute($locus) };
		$logger->($@) if $@;
		my ( $name, $product ) = $self->{'sql'}->{'name'}->fetchrow_array;
		my @names_product;
		push @names_product, $name    if $name;
		push @names_product, $product if $product;
		local $" = ' / ';
		print "<td>@names_product</td>";
	}
	if ( $options->{'aliases_exist'} ) {
		eval { $self->{'sql'}->{'alias'}->execute($locus) };
		$logger->($@) if $@;
		my @aliases;
		while ( my ($alias) = $self->{'sql'}->{'alias'}->fetchrow_array ) {
			push @aliases, $alias if $display_name !~ /$alias/;
		}
		local $" = '; ';
		print "<td>@aliases</td>\n";
	}
	if ( $options->{'curators_exist'} ) {
		eval { $self->{'sql'}->{'curator'}->execute($locus) };
		$logger->($@) if $@;
		my @curators;
		my $info;
		while ( my ($curator) = $self->{'sql'}->{'curator'}->fetchrow_array ) {
			push @curators, $curator;
			$info->{$curator} = $self->{'datastore'}->get_user_info($curator);
		}
		@curators = sort { $info->{$a}->{'surname'} cmp $info->{$b}->{'surname'} } @curators;
		my $first = 1;
		print "<td>";
		foreach my $curator (@curators) {
			print ', ' if !$first;
			my $first_initial = $info->{$curator}->{'first_name'} ? substr( $info->{$curator}->{'first_name'}, 0, 1 ) . '. ' : '';
			print "<a href=\"mailto:$info->{$curator}->{'email'}\">" if $info->{$curator}->{'email'};
			print "$first_initial$info->{$curator}->{'surname'}";
			print "</a>" if $info->{$curator}->{'email'};
			$first = 0;
		}
		print "</td>";
	}
	print "</tr>\n";
	return;
}

sub _print_alphabetical_list {
	my ($self) = @_;
	my $locus_pattern = LOCUS_PATTERN;
	foreach my $letter ( 0 .. 9, 'A' .. 'Z' ) {
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
			my $descs_exist =
			  $self->{'datastore'}->run_simple_query( "SELECT 1 WHERE EXISTS(SELECT locus FROM locus_descriptions "
				  . "WHERE locus IN (SELECT id FROM loci WHERE UPPER(id) LIKE E'$qry_letter%' OR upper(common_name) LIKE E'$qry_letter%') "
				  . "OR locus IN (SELECT locus FROM locus_aliases WHERE UPPER(alias) LIKE E'$qry_letter%'))" );
			my $aliases_exist =
			  $self->{'datastore'}
			  ->run_simple_query( "SELECT 1 WHERE EXISTS(SELECT locus FROM locus_aliases " . "WHERE alias LIKE E'$qry_letter%')" );
			my $curators_exist =
			  $self->{'datastore'}->run_simple_query( "SELECT 1 WHERE EXISTS(SELECT locus FROM locus_curators "
				  . "WHERE (locus IN (SELECT id FROM loci WHERE UPPER(id) LIKE E'$qry_letter%' OR upper(common_name) LIKE E'$qry_letter%') "
				  . "OR locus IN (SELECT locus FROM locus_aliases WHERE UPPER(alias) LIKE E'$qry_letter%')) AND NOT hide_public)" );
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
	return;
}

sub _get_loci_by_letter {
	my ( $self, $letter ) = @_;
	my $set_clause = '';
	if ( ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ) {
		my $set_id = $self->get_set_id;
		if ( $set_id && BIGSdb::Utils::is_int($set_id) ) {

			#make sure 'id IN' has a space before it - used in the substitution a few lines on (also matches scheme_id otherwise).
			$set_clause = "AND ( id IN (SELECT locus FROM scheme_members WHERE scheme_id IN (SELECT scheme_id FROM set_schemes WHERE "
			  . "set_id=$set_id)) OR id IN (SELECT locus FROM set_loci WHERE set_id=$set_id))";
		}
	}
	my $main = $self->{'datastore'}->run_list_query("SELECT id FROM loci WHERE UPPER(id) LIKE E'$letter%' $set_clause");
	my $common =
	  $self->{'datastore'}->run_list_query_hashref("SELECT id,common_name FROM loci WHERE UPPER(common_name) LIKE E'$letter%' $set_clause");
	$set_clause =~ s/ id IN/ locus IN/g;
	my $aliases =
	  $self->{'datastore'}->run_list_query_hashref("SELECT locus,alias FROM locus_aliases WHERE alias ILIKE E'$letter%' $set_clause");
	return ( $main, $common, $aliases );
}
1;
