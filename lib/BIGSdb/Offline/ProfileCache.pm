#Written by Keith Jolley
#Copyright (c) 2024, University of Oxford
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
package BIGSdb::Offline::ProfileCache;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Offline::Script);
use File::Path qw(make_path remove_tree);
use Fcntl qw(:flock);
use Text::CSV;

sub get_profiles {
	my ( $self, $scheme_id, $options ) = @_;
	if ( !$self->_cache_exists($scheme_id) ) {
		return $self->_create_profile_cache( $scheme_id, $options );
	}
	my $path      = $self->_get_cache_dir($scheme_id);
	my $lock_file = "$path/LOCK";
	my $read_file = "$path/READ_$$";
	open( my $read_fh, '>', $read_file ) || $self->{'logger'}->error('Cannot write READ file');
	close $read_fh;
	if ( -e $lock_file ) {

		#Wait for lock to clear - cache is being created by other process.
		open( my $lock_fh, '<', $lock_file ) || $self->{'logger'}->error('Cannot open lock file.');
		flock( $lock_fh, LOCK_SH ) or $self->{'logger'}->error("Cannot flock $lock_file: $!");
		close $lock_fh;
	}
	my $filename = "$path/profiles.tsv";
	if ( !-e $filename ) {
		$self->{'logger'}->error("Cache file $filename does not exist.");
		return;
	}
	my $scheme_info =
	  $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $options->{'set_id'}, get_pk => 1 } );
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $profiles      = [];
	my $non_pk_fields = @$scheme_fields - 1;
	open( my $fh, '<:encoding(utf8)', $filename ) || $self->{'logger'}->error("Cannot open $filename for reading.");
	my $tsv    = Text::CSV->new( { sep_char => "\t" } );
	my $header = 1;

	while ( my $row = $tsv->getline($fh) ) {
		if ($header) {
			$header = 0;
			next;
		}
		my $pk = shift @$row;
		for ( 0 .. $non_pk_fields - 1 ) {
			pop @$row;
		}
		push @$profiles,
		  {
			pk      => $pk,
			profile => $row
		  };
	}
	close;
	unlink $read_file;
	return $profiles;
}

sub _create_profile_cache {
	my ( $self, $scheme_id, $options ) = @_;
	my $profiles = [];
	my $path     = $self->_get_cache_dir($scheme_id);
	make_path($path);

	#This method may be called by apache during a web query, by the bigsdb or any other user
	#if called from external script. We need to make sure that cache files can be overwritten
	#by all.
	chmod 0777, "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}", $path;

	#Prevent two processes running in the same directory.
	my $lock_file = "$path/LOCK";
	open( my $lock_fh, '>', $lock_file ) || $self->{'logger'}->error('Cannot open lock file');
	if ( !flock( $lock_fh, LOCK_EX ) ) {
		$self->{'logger'}->error("Cannot flock $lock_file: $!");
		return;
	}
	my $tsv_file = "$path/profiles.tsv";
	unlink $tsv_file;    #Recreate rather than overwrite to ensure both apache and bigsdb users can write
	my $scheme_info =
	  $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $options->{'set_id'}, get_pk => 1 } );
	my $primary_key   = $scheme_info->{'primary_key'};
	my @heading       = ( $scheme_info->{'primary_key'} );
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my @fields        = ( $scheme_info->{'primary_key'}, 'profile' );
	my $locus_indices = $self->{'datastore'}->get_scheme_locus_indices($scheme_id);
	my @order;
	my $limit = 10000;

	foreach my $locus (@$loci) {
		my $locus_info   = $self->{'datastore'}->get_locus_info( $locus, { set_id => $options->{'set_id'} } );
		my $header_value = $locus_info->{'set_name'} // $locus;
		push @heading, $header_value;
		push @order,   $locus_indices->{$locus};
	}
	foreach my $field (@$scheme_fields) {
		next if $field eq $scheme_info->{'primary_key'};
		push @heading, $field;
		push @fields,  $field;
	}
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $pk_info          = $self->{'datastore'}->get_scheme_field_info( $scheme_id, $primary_key );
	local $" = ',';
	my $qry = "SELECT @fields FROM $scheme_warehouse";
	$qry .= ' ORDER BY ' . ( $pk_info->{'type'} eq 'integer' ? "CAST($primary_key AS int)" : $primary_key );
	$qry .= " LIMIT $limit OFFSET ?";
	local $" = "\t";
	my $profile_fh;
	make_path($path);    #In case directory has since been deleted.

	if ( !open( $profile_fh, '>:encoding(utf8)', $tsv_file ) ) {
		$self->{'logger'}->error("Cannot open $tsv_file for writing");
		return;
	}
	local $" = "\t";
	say $profile_fh "@heading";
	my $offset = 0;
	while (1) {
		no warnings 'uninitialized';    #scheme field values may be undefined
		my $definitions = $self->{'datastore'}
		  ->run_query( $qry, $offset, { fetch => 'all_arrayref', cache => 'ProfileCache::create_profile_cache' } );
		foreach my $definition (@$definitions) {
			my $pk      = shift @$definition;
			my $profile = shift @$definition;
			print $profile_fh qq($pk\t@$profile[@order]);
			print $profile_fh qq(\t@$definition) if @$scheme_fields > 1;
			print $profile_fh qq(\n);
			push @$profiles,
			  {
				pk      => $pk,
				profile => [ @$profile[@order] ]
			  };
		}
		$offset += $limit;
		last unless @$definitions;
	}
	if ($lock_fh) {
		close $lock_fh;
		unlink $lock_file;
	}
	return $profiles;
}

sub _cache_exists {
	my ( $self, $scheme_id ) = @_;
	my $path = $self->_get_cache_dir($scheme_id);
	return if !-e $path;
	return if $self->_delete_cache_if_stale($scheme_id);
	return 1;
}

sub _delete_cache_if_stale {
	my ( $self, $scheme_id ) = @_;
	my $path           = $self->_get_cache_dir($scheme_id);
	my $cache_is_stale = -e "$path/stale" || !-s "$path/profiles.tsv";
	my $cache_age      = $self->_get_cache_age($scheme_id);
	if ( $cache_age > $self->{'config'}->{'cache_days'} || $cache_is_stale ) {
		return $self->_delete_cache($scheme_id);
	}
	return;
}

sub _get_read_files {
	my ( $self, $path ) = @_;
	my @read_files    = glob("$path/READ*");
	my $returned_list = [];
	my $age           = 5 * 60;                #5 minutes;
	foreach my $file (@read_files) {
		if ( time - ( stat $file )[9] > $age ) {
			if ( $file =~ /^($path\/READ_\d+)$/x ) {    #Untaint
				unlink $1;    #Clean out files older than 5 minutes as these may be from crashed processes.
			}
		} else {
			push @$returned_list, $file;
		}
	}
	return $returned_list;
}

sub _delete_cache {
	my ( $self, $scheme_id ) = @_;
	$self->{'logger'}->info("Deleting cache scheme_${scheme_id}");
	my $path = $self->_get_cache_dir($scheme_id);

	#Return if query is currently running.
	my $read_files = $self->_get_read_files($path);
	if (@$read_files) {
		$self->{'logger'}->debug("Profile query running - cannot delete cache $path.");
		return;
	}
	my $tsv_file  = "$path/profiles.tsv";
	my $lock_file = "$path/LOCK";
	if ( -e $lock_file ) {
		$self->{'logger'}->error("Cannot delete cache as lock file exists - $lock_file.");
		return;
	}
	my $profiles_fh;
	if ( !open( $profiles_fh, '>', $tsv_file ) ) {
		$self->{'logger'}->error("Cannot open $tsv_file for writing");
		return;
	}
	if ( flock( $profiles_fh, LOCK_EX ) ) {
		remove_tree( $path, { error => \my $err } );
		if (@$err) {
			$self->{'logger'}->error("Cannot remove cache directory $path");
		}
		return 1;
	} else {
		$self->{'logger'}->error("Cannot flock $tsv_file: $!");
	}
	return;
}

sub _get_cache_age {
	my ( $self, $scheme_id ) = @_;
	my $path       = $self->_get_cache_dir($scheme_id);
	my $fasta_file = "$path/profiles.tsv";
	return 0 if !-e $fasta_file;
	return -M $fasta_file;
}

sub _get_cache_dir {
	my ( $self, $scheme_id ) = @_;
	my $dir = "$self->{'config'}->{'secure_tmp_dir'}/$self->{'system'}->{'db'}/scheme_${scheme_id}";
	if ( $dir =~ /(.+)/x ) {
		return $1;    #Untaint
	}
	return $dir;
}

sub mark_profile_cache_stale {
	my ( $self, $scheme_id ) = @_;
	my $dir             = $self->_get_cache_dir($scheme_id);
	return if !-e $dir;
	my $stale_flag_file = "$dir/stale";
	open( my $fh, '>', $stale_flag_file ) || $self->{'logger'}->error("Cannot mark scheme $scheme_id stale.");
	close $fh;
	return;
}
1;
