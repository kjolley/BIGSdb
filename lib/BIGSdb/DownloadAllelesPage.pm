#Written by Keith Jolley
#Copyright (c) 2010-2011, University of Oxford
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
use base qw(BIGSdb::Page);
use List::MoreUtils qw(none any);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

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
Click the nodes to expand/collapse.  
<a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles">
See all download links on a single page</a>.</p>
<noscript>
<p class="highlight">Enable Javascript to enhance your viewing experience.</p>
</noscript>
<div id="tree" class="tree">
HTML
	print $self->get_tree(undef);
	print "</div>\n<div id=\"scheme_table\"></div>\n";
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
}

sub _print_group_scheme_tables {
	my ( $self, $id, $scheme_shown ) = @_;
	my $schemes = $self->{'datastore'}->run_list_query(
"SELECT scheme_id FROM scheme_group_scheme_members LEFT JOIN schemes ON schemes.id=scheme_id WHERE group_id=? ORDER BY display_order",
		$id
	);
	if (@$schemes) {
		foreach (@$schemes) {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($_);
			$scheme_info->{'description'} =~ s/&/\&amp;/g;
			$self->_print_scheme_table( $_, $scheme_info->{'description'} ) if !$scheme_shown->{$_};
			$scheme_shown->{$_} = 1;
		}
	}
}

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('locus') ) {
		if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
			print "This function is not available for isolate databases.\n";
			return;
		}
		if ( $self->{'system'}->{'disable_seq_downloads'} && $self->{'system'}->{'disable_seq_downloads'} eq 'yes' && !$self->is_admin ) {
			print "Allele sequence downloads are disabled for this database.\n";
			return;
		}
		my $locus = $q->param('locus');
		$locus =~ s/%27/'/g;    #Web-escaped locus
		if ( $self->{'datastore'}->is_locus($locus) ) {
			$self->_print_sequences($locus);
		} else {
			print "$locus is not a locus!\n";
		}
		return;
	}
	if ( defined $q->param('scheme_id') ) {
		my $scheme_id = $q->param('scheme_id');
		if ( !BIGSdb::Utils::is_int($scheme_id) ) {
			$logger->warn("Invalid scheme selected - $scheme_id");
			return;
		}
		if ( $scheme_id == -1 ) {
			my $schemes = $self->{'datastore'}->run_list_query_hashref("SELECT id,description FROM schemes ORDER BY display_order,id");
			foreach (@$schemes) {
				$self->_print_scheme_table( $_->{'id'}, $_->{'description'} );
			}
			$self->_print_scheme_table( 0, 'Other loci' );
		} else {
			my $scheme_info = $self->{'datastore'}->get_scheme_info($scheme_id);
			my $desc = $scheme_id ? $scheme_info->{'description'} : 'Other loci';
			$self->_print_scheme_table( $scheme_id, $desc );
		}
		return;
	} elsif ( $q->param('group_id') ) {
		my $group_id = $q->param('group_id');
		if ( !BIGSdb::Utils::is_int($group_id) ) {
			$logger->warn("Invalid group selected - $group_id");
			return;
		}
		my $scheme_ids;
		if ( $group_id == 0 ) {
			$scheme_ids =
			  $self->{'datastore'}->run_list_query(
				"SELECT id FROM schemes WHERE id NOT IN (SELECT scheme_id FROM scheme_group_scheme_members) ORDER BY display_order");
			foreach (@$scheme_ids) {
				my $scheme_info = $self->{'datastore'}->get_scheme_info($_);
				$self->_print_scheme_table( $_, $scheme_info->{'description'} );
			}
		} else {
			my $scheme_shown;
			$self->_print_group_scheme_tables( $group_id, $scheme_shown );
			$self->_print_child_group_scheme_tables( $group_id, 1, $scheme_shown );
		}
		return;
	}
	print "<h1>Download allele sequences</h1>";
	if ( $self->{'system'}->{'dbtype'} eq 'isolates' ) {
		print "<div class=\"box\" id=\"statusbad\"><p>This function is not available for isolate databases.</p></div>\n";
		return;
	}
	if ( defined $self->{'system'}->{'disable_seq_downloads'} && $self->{'system'}->{'disable_seq_downloads'} eq 'yes' && !$self->is_admin )
	{
		print "<div class=\"box\" id=\"statusbad\"><p>Allele sequence downloads are disabled for this database.</p></div>\n";
		return;
	}
	my $all_loci = $self->{'datastore'}->get_loci();
	if ( !@$all_loci ) {
		print "<div class=\"box\" id=\"statusbad\"><p>No loci have been defined for this database.</p></div>\n";
		return;
	}
	print "<div class=\"box\" id=\"resultstable\">\n";
	if ( $q->param('tree') ) {
		$self->_print_tree;
		print "</div>\n";
		return;
	}
	my $qry = "SELECT id,description FROM schemes ORDER BY display_order,id";
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute };
	$logger->error($@) if $@;
	while ( my ( $scheme_id, $desc ) = $sql->fetchrow_array() ) {
		$self->_print_scheme_table( $scheme_id, $desc );
	}
	$self->_print_scheme_table( 0, 'Other loci' );
	print "</div>\n";
}

sub _print_scheme_table {
	my ( $self, $scheme_id, $desc ) = @_;
	my $loci      = $scheme_id ? $self->{'datastore'}->get_scheme_loci($scheme_id) : $self->{'datastore'}->get_loci_in_no_scheme();
	my $count_sql = $self->{'db'}->prepare("SELECT COUNT(*) FROM sequences WHERE locus=?");
	my $td        = 1;
	my $desc_sql  = $self->{'db'}->prepare("SELECT COUNT(*) FROM locus_descriptions WHERE locus=?");
	my $name_sql  = $self->{'db'}->prepare("SELECT full_name,product FROM locus_descriptions WHERE locus=?");
	my $alias_sql = $self->{'db'}->prepare("SELECT alias FROM locus_aliases WHERE locus=? ORDER BY alias");
	my $curator_sql =
	  $self->{'db'}->prepare("SELECT curator_id FROM locus_curators WHERE locus=? AND (hide_public IS NULL OR NOT hide_public)");
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
		print "<table class=\"resultstable\"><tr><th>Locus</th><th>Download</th>
			<th>Type</th><th>Alleles</th><th>Length</th>";
		print "<th>Full name/product</th>" if $scheme_descs_exist;
		print "<th>Aliases</th>\n"         if $scheme_aliases_exist;
		print "<th>Curator(s)</th>\n"      if $scheme_curators_exist;
		print "</tr>\n";

		foreach (@$loci) {
			my $cleaned    = $self->clean_locus($_);
			my $locus_info = $self->{'datastore'}->get_locus_info($_);
			eval { $count_sql->execute($_) };
			$logger->($@) if $@;
			my ($count) = $count_sql->fetchrow_array;
			print "<tr class=\"td$td\"><td>$cleaned ";
			eval { $desc_sql->execute($_) };
			$logger->($@) if $@;
			my ($desc_exists) = $desc_sql->fetchrow_array;
			print "($locus_info->{'common_name'})" if $locus_info->{'common_name'};

			if ($desc_exists) {
				print
" <a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=locusInfo&amp;locus=$_\" class=\"info_tooltip\">&nbsp;i&nbsp;</a>";
			}
			print "</td><td>";
			print
"<a href=\"$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadAlleles&amp;locus=$_\" class=\"downloadbutton\">&darr;</a>"
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
			if ($scheme_descs_exist) {
				eval { $name_sql->execute($_) };
				$logger->($@) if $@;
				my ( $name, $product ) = $name_sql->fetchrow_array;
				my @names_product;
				push @names_product, $name    if $name;
				push @names_product, $product if $product;
				$" = ' / ';
				print "<td>@names_product</td>";
			}
			if ($scheme_aliases_exist) {
				eval { $alias_sql->execute($_) };
				$logger->($@) if $@;
				my @aliases;
				while ( my ($alias) = $alias_sql->fetchrow_array ) {
					push @aliases, $alias;
				}
				$" = '; ';
				print "<td>@aliases</td>\n";
			}
			if ($scheme_curators_exist) {
				eval { $curator_sql->execute($_) };
				$logger->($@) if $@;
				my @curators;
				my $info;
				while ( my ($curator) = $curator_sql->fetchrow_array ) {
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
			$td = $td == 1 ? 2 : 1;
		}
		print "</table>\n";
	}
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Download allele sequences - $desc";
}

sub _print_sequences {
	my ( $self, $locus ) = @_;
	( my $cleaned = $locus ) =~ s/^_//;
	my $locus_info = $self->{'datastore'}->get_locus_info($locus);
	my $qry        = "SELECT allele_id,sequence FROM sequences WHERE locus=? ORDER BY "
	  . ( $locus_info->{'allele_id_format'} eq 'integer' ? 'CAST(allele_id AS int)' : 'allele_id' );
	my $sql = $self->{'db'}->prepare($qry);
	eval { $sql->execute($locus) };
	if ($@) {
		$logger->error($@);
		print "Can't retrieve sequences.\n";
		return;
	}
	while ( my ( $id, $sequence ) = $sql->fetchrow_array ) {
		print ">$cleaned $id\n";
		my $cleaned_seq = BIGSdb::Utils::break_line( $sequence, 60 ) || '';
		print "$cleaned_seq\n";
	}
	return;
}
1;
