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
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::AjaxMenu;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use BIGSdb::Utils;

sub initiate {
	my ($self) = @_;
	$self->{'type'} = 'no_header';
	return;
}

sub print_content {
	my ($self) = @_;
	$self->_menu_header;
	$self->_home;
	if ( $self->{'curate'} ) {
		$self->{'system'}->{'dbtype'} eq 'isolates'
		  ? $self->_isolate_curate_items
		  : $self->_seqdef_curate_items;
		my $base_url = $self->_get_base_url;
		say q(<span class="main_icon fa fa-info-circle fa-lg pull-left"></span>);
		say q(<ul class="menu">);
		say qq(<li><a href="$self->{'config'}->{'doclink'}/curator_guide.html" target="_blank">)
		  . q(Curators' guide</a></li>);
		say q(</ul>);
	} else {
		$self->{'system'}->{'dbtype'} eq 'isolates'
		  ? $self->_isolate_items
		  : $self->_seqdef_items;
	}
	if ( $self->{'system'}->{'related_databases'} ) {
		my @dbases = split /;/x, $self->{'system'}->{'related_databases'};
		if (@dbases) {
			say q(<span class="dataset_icon fa fa-database fa-lg pull-left"></span>);
			say q(<ul class="menu">);
			foreach my $dbase (@dbases) {
				my ( $config, $name ) = split /\|/x, $dbase;
				say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$config">$name</a></li>);
			}
			say q(</ul>);
		}
	}
	return;
}

sub _menu_header {
	my ($self) = @_;
	my @possible_header_files = (
		"$ENV{'DOCUMENT_ROOT'}$self->{'system'}->{'webroot'}/menu_header.html",
		"$ENV{'DOCUMENT_ROOT'}/menu_header.html",
		"$self->{'config_dir'}/menu_header.html"
	);
	foreach my $file (@possible_header_files) {
		if ( -e $file ) {
			my $header = BIGSdb::Utils::slurp($file);
			say q(<div style="text-align:center">);
			say $$header;
			say q(</div>);
			return;
		}
	}
	return;
}

sub _home {
	my ($self) = @_;
	say q(<span class="main_icon fa fa-home fa-lg pull-left" style="margin-top:0.8em"></span>);
	say q(<ul class="menu">);
	say qq(<li><a href="$self->{'system'}->{'webroot'}">Home</a></li>);
	if ( $self->{'curate'} ) {
		if ( $self->{'system'}->{'curator_home'} ) {
			say qq(<li><a href="$self->{'system'}->{'curator_home'}">Curator home</a></li>);
		}
	} else {
		if ( $self->{'system'}->{'curate_link'} ) {
			say qq(<li><a href="$self->{'system'}->{'curate_link'}">Curate</a></li>);
		}
	}
	say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}">Contents</a></li>);
	say q(</ul>);
	return;
}

sub _get_base_url {
	my ($self) = @_;
	my $set_id = $self->get_set_id;
	my $set_string = $set_id ? qq(&amp;set_id=$set_id) : q();
	return qq($self->{'system'}->{'script_name'}?db=$self->{'instance'}$set_string);
}

sub _submissions_link {
	my ($self) = @_;
	return if ( $self->{'system'}->{'submissions'} // '' ) ne 'yes';
	my $set_id = $self->get_set_id // 0;
	my $set_string = ( $self->{'system'}->{'sets'} // '' ) eq 'yes' ? "&amp;choose_set=1&amp;sets_list=$set_id" : q();
	say q(<span class="main_icon fa fa-upload fa-lg pull-left"></span>);
	say q(<ul class="menu">);
	say qq(<li><a href="$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=submit$set_string">)
	  . q(Submissions</a></li>);
	say q(</ul>);
	return;
}

sub _options_link {
	my ($self) = @_;
	my $base_url = $self->_get_base_url;
	say q(<span class="main_icon fa fa-cogs fa-lg pull-left"></span>);
	say q(<ul class="menu">);
	say qq(<li><a href="$base_url&amp;page=options">General options</a></li>);
	say q(</ul>);
	return;
}

sub _isolate_items {
	my ($self) = @_;
	my $base_url = $self->_get_base_url;
	say q(<span class="main_icon fa fa-search fa-lg pull-left"></span>);
	say q(<ul class="menu">);
	say qq(<li><a href="$base_url&amp;page=query">Search or browse</a></li>);
	say qq(<li><a href="$base_url&amp;page=profiles">Allelic combinations</a></li>);
	my $projects = $self->{'datastore'}->run_query('SELECT EXISTS(SELECT * FROM projects WHERE list)');
	say qq(<li><a href="$base_url&amp;page=projects">Projects</a></li>) if $projects;

	#Field help
	my $publications =
	  $self->{'datastore'}
	  ->run_query("SELECT EXISTS(SELECT * FROM refs WHERE isolate_id IN (SELECT id FROM $self->{'system'}->{'view'}))");
	say qq(<li><a href="$base_url&amp;page=plugin&amp;name=PublicationBreakdown">Publications</a></li>)
	  if $publications;
	say q(</ul>);
	$self->_options_link;
	$self->_submissions_link;
	say q(<span class="main_icon fa fa-info-circle fa-lg pull-left"></span>);
	say q(<ul class="menu">);
	say qq(<li><a href="$base_url&amp;page=version">About BIGSdb</a></li>);
	say q(<li><a href="http://bigsdb.readthedocs.io" target="_blank">User guide</a></li>);
	say qq(<li><a href="$base_url&amp;page=plugin&amp;name=DatabaseFields">Field descriptions</a></li>);
	say qq(<li><a href="$base_url&amp;page=fieldValues">Defined field values</a></li>);
	say q(</ul>);
	return;
}

sub _seqdef_items {
	my ($self) = @_;
	my $base_url = $self->_get_base_url;
	say q(<span class="main_icon fa fa-search fa-lg pull-left"></span>);
	say q(<ul class="menu">);
	say qq(<li><a href="$base_url&amp;page=sequenceQuery">Sequences</a></li>);
	say qq(<li><a href="$base_url&amp;page=batchSequenceQuery">Batch sequences</a></li>);
	say qq(<li><a href="$base_url&amp;page=tableQuery&amp;table=sequences">Sequence attributes</a></li>);
	say qq(<li><a href="$base_url&amp;page=plugin&amp;name=SequenceComparison">Sequence comparison</a></li>);
	say qq(<li><a href="$base_url&amp;page=profiles">Allelic profiles</a></li>);
	say qq(<li><a href="$base_url&amp;page=batchProfiles">Batch profiles</a></li>);
	say qq(<li><a href="$base_url&amp;page=profiles">Allelic combinations</a></li>);
	say q(</ul>);
	$self->_options_link;
	$self->_submissions_link;
	say q(<span class="main_icon fa fa-info-circle fa-lg pull-left"></span>);
	say q(<ul class="menu">);
	say qq(<li><a href="$base_url&amp;page=version">About BIGSdb</a></li>);
	say q(<li><a href="http://bigsdb.readthedocs.io" target="_blank">User guide</a></li>);
	say q(</ul>);
	return;
}

sub _isolate_curate_items {
	my ($self) = @_;
	$self->_users_link;
	my $buffer = $self->_isolates_link;
	if ($buffer) {
		say q(<span class="main_icon fa fa-file-text fa-lg pull-left"></span>);
		say q(<ul class="menu">);
		say $buffer;
		say q(</ul>);
	}
	return;
}

sub _seqdef_curate_items {
	my ($self) = @_;
	$self->_users_link;
	my $buffer = $self->_sequences_link;
	$buffer .= $self->_profiles_link;
	if ($buffer) {
		say q(<span class="main_icon fa fa-file-text fa-lg pull-left"></span>);
		say q(<ul class="menu">);
		say $buffer;
		say q(</ul>);
	}
	return;
}

sub _users_link {
	my ($self) = @_;
	return if !$self->can_modify_table('users');
	my $base_url = $self->_get_base_url;
	say q(<span class="main_icon fa fa-user fa-lg pull-left"></span>);
	say q(<ul class="menu">);
	say qq(<li><a href="$base_url&amp;page=add&amp;table=users">Add user</a></li>);
	say qq(<li><a href="$base_url&amp;page=tableQuery&amp;table=users">Query users</a></li>);
	say q(</ul>);
	return;
}

sub _sequences_link {
	my ($self) = @_;
	my $locus_curator = $self->is_admin ? undef : $self->get_curator_id;
	my $set_id = $self->get_set_id;
	my ( $loci, undef ) =
	  $self->{'datastore'}
	  ->get_locus_list( { set_id => $set_id, locus_curator => $locus_curator, no_list_by_common_name => 1 } );
	return q() if !$self->is_admin && !@$loci;
	my $base_url = $self->_get_base_url;
	return qq(<li><a href="$base_url&amp;page=add&amp;table=sequences">Add sequence</a></li>);
}

sub _profiles_link {
	my ($self) = @_;
	my $schemes;
	my $set_id = $self->get_set_id;
	if ( $self->is_admin ) {
		$schemes = $self->{'datastore'}->run_query(
			'SELECT DISTINCT id FROM schemes RIGHT JOIN scheme_members ON schemes.id=scheme_members.scheme_id '
			  . 'JOIN scheme_fields ON schemes.id=scheme_fields.scheme_id WHERE primary_key',
			undef,
			{ fetch => 'col_arrayref' }
		);
	} else {
		$schemes = $self->{'datastore'}->run_query( 'SELECT scheme_id FROM scheme_curators WHERE curator_id=?',
			$self->get_curator_id, { fetch => 'col_arrayref' } );
	}
	my %desc;
	foreach my $scheme_id (@$schemes)
	{    #Can only order schemes after retrieval since some can be renamed by set membership
		my $scheme_info = $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $set_id } );
		$desc{$scheme_id} = $scheme_info->{'description'};
	}
	my $base_url = $self->_get_base_url;
	my $buffer   = q();
	foreach my $scheme_id ( sort { $desc{$a} cmp $desc{$b} } @$schemes ) {
		next if $set_id && !$self->{'datastore'}->is_scheme_in_set( $scheme_id, $set_id );
		$desc{$scheme_id} =~ s/\&/\&amp;/gx;

		#Only list schemes with short names
		#TODO Have this selectable as a flag in the scheme table
		next if length $desc{$scheme_id} > 10;
		$buffer .=
		    qq(<li>$desc{$scheme_id} profiles: )
		  . qq(<a href="$base_url&amp;page=profileAdd&amp;scheme_id=$scheme_id">add</a> | )
		  . qq(<a href="$base_url&amp;page=profileBatchAdd&amp;scheme_id=$scheme_id">batch</a></li>);
	}
	return $buffer;
}

sub _isolates_link {
	my ($self) = @_;
	if ( $self->can_modify_table('isolates') ) {
		my $base_url = $self->_get_base_url;
		return
		    qq(<li><a href="$base_url&amp;page=isolateAdd">Add isolates</a></li>)
		  . qq(<li><a href="$base_url&amp;page=batchAdd&amp;table=isolates">Batch add isolates</a></li>)
		  . qq(<li><a href="$base_url&amp;page=query">Query isolates</a></li>);
	}
	return;
}
1;
