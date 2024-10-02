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
use JSON;

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
	my $scheme_info =
	  $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $options->{'set_id'}, get_pk => 1 } );
	my $scheme_fields = $self->{'datastore'}->get_scheme_fields($scheme_id);
	my $loci          = $self->{'datastore'}->get_scheme_loci($scheme_id);
	my $profiles      = [];
	my $filename      = "$path/profiles.dump";
	if ( !-e $filename ) {
		$self->{'logger'}->error("Cache file $filename does not exist.");
		return;
	}
	open( my $fh, '<:encoding(utf8)', $filename ) || $self->{'logger'}->error("Cannot open $filename for reading.");
	my $parse_needed = -e "$path/PARSE_NEEDED";
	if ( !$parse_needed ) {    #No double quotes - can just split on comma.
		while ( my $row = <$fh> ) {
			my ( $pk, $profile ) = split /\t/x, $row;
			$profile =~ s/^\{//x;    # Remove the curly braces (separate statements is quicker)
			$profile =~ s/\}$//x;
			my @profile = split( ',', $profile );
			push @$profiles,
			  {
				pk      => $pk,
				profile => \@profile
			  };
		}
	} else {
		my $array_parser = Text::CSV->new( { binary => 1, sep_char => ',', quote_char => '"' } );
		eval {
			while ( my $row = <$fh> ) {
				my ( $pk, $profile ) = split /\t/x, $row;
				$profile =~ s/^\{//x;
				$profile =~ s/\}$//x;
				$array_parser->parse($profile);
				my @profile = $array_parser->fields;
				eval { push @$profiles, { pk => $pk, profile => \@profile } };
				$self->{'logger'}->error($@) if $@;
			}
		};
		$self->{'logger'}->error($@) if $@;
	}
	close $fh;
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
	my $scheme_info =
	  $self->{'datastore'}->get_scheme_info( $scheme_id, { set_id => $options->{'set_id'}, get_pk => 1 } );
	my $scheme_warehouse = "mv_scheme_$scheme_id";
	my $dump_file        = "$path/profiles.dump";
	my $profile_fh;
	if ( !open( $profile_fh, '>:encoding(utf8)', $dump_file ) ) {
		$self->{'logger'}->error("Cannot open $dump_file for writing");
		return;
	}
	my @fields = ( lc( $scheme_info->{'primary_key'} ), 'profile' );
	local $" = q(,);
	$self->{'db'}->do("COPY $scheme_warehouse(@fields) TO STDOUT");
	my $row;
	my $array_parser = Text::CSV->new( { binary => 1, sep_char => ',', quote_char => '"' } );
	my $quotes_found;
	while ( $self->{'db'}->pg_getcopydata($row) >= 0 ) {
		print $profile_fh $row;
		my ( $pk, $profile ) = split /\t/x, $row;
		$profile =~ s/^\{//x;                    # Remove the curly braces
		$profile =~ s/\}$//x;
		if ( index( $profile, '"' ) == -1 ) {    #No double quotes - can just split on comma.
			my @profile = split( ',', $profile );
			push @$profiles,
			  {
				pk      => $pk,
				profile => \@profile
			  };
		} else {
			$array_parser->parse($profile);
			eval { push @$profiles, { pk => $pk, profile => [ $array_parser->fields ] }; };
			$self->{'logger'}->error($@) if $@;
			$quotes_found = 1;
		}
	}
	close $profile_fh;
	if ($quotes_found) {
		my $flag_file = "$path/PARSE_NEEDED";
		open( my $read_fh, '>', $flag_file ) || $self->{'logger'}->error("Cannot write $flag_file file");
		close $read_fh;
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
	my $cache_is_stale = -e "$path/stale" || !-s "$path/profiles.dump";
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
	my $tsv_file  = "$path/profiles.dump";
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
	my $fasta_file = "$path/profiles.dump";
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
	my $dir = $self->_get_cache_dir($scheme_id);
	return if !-e $dir;
	my $stale_flag_file = "$dir/stale";
	open( my $fh, '>', $stale_flag_file ) || $self->{'logger'}->error("Cannot mark scheme $scheme_id stale.");
	close $fh;
	return;
}
1;
