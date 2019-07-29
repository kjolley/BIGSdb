#Written by Keith Jolley
#Copyright (c) 2018, University of Oxford
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
package BIGSdb::DownloadFilePage;
use strict;
use warnings;
use 5.010;
use parent qw(BIGSdb::Page);
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');

sub print_content {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	if ( $q->param('file') ) {
		$self->_print_file( scalar $q->param('file') );
		return;
	}
	say q(<h1>Files available for download</h1>);
	my $conf_file = $self->_get_conf_file;
	if ( !-e $conf_file ) {
		$self->print_bad_status(
			{ message => 'There are no files available for download from this database configuration.', navbar => 1 } );
		return;
	}
	my $files = $self->_get_files;
	if ( !@$files ) {
		$self->print_bad_status(
			{ message => 'There are no files available for download from this database configuration.', navbar => 1 } );
		return;
	}
	say q(<div class="box" id="resultstable"><div class="scrollable">);
	say
q(<table class="resultstable"><tr><th>File</th><th>Description</th><th>Type</th><th>Size</th><th>Updated</th></tr>);
	my $td = 1;
	foreach my $file (@$files) {
		my $desc    = $file->{'description'} // q();
		my $size    = BIGSdb::Utils::get_nice_size( -s $file->{'filename'} );
		my $updated = localtime( ( stat( $file->{'filename'} ) )[9] );
		my $url =
		  "$self->{'system'}->{'script_name'}?db=$self->{'instance'}&amp;page=downloadFiles&amp;file=$file->{'label'}";
		say qq(<tr class="td$td"><td><a href="$url">$file->{'label'}</a></td><td>$desc</td>)
		  . qq(<td>$file->{'type'}</td><td>$size</td><td>$updated</td></tr>);
	}
	say q(</table>);
	say q(</div></div>);
	return;
}

sub _print_file {
	my ( $self, $label ) = @_;
	my $file = $self->_get_file_info($label);
	if ( !$file ) {
		say q(<h1>Files available for download</h1>);
		$self->print_bad_status( { message => 'File does not exist.', navbar => 1 } );
	}
	my $contents = BIGSdb::Utils::slurp( $file->{'filename'} );
	print $$contents;
	return;
}

sub _get_file_info {
	my ( $self, $label ) = @_;
	my $files = $self->_get_files;
	foreach my $file (@$files) {
		if ( $label eq $file->{'label'} ) {
			return $file;
		}
	}
	return;
}

sub _get_conf_file {
	my ($self) = @_;
	return "$self->{'config_dir'}/dbases/$self->{'instance'}/download_files.conf";
}

sub _get_files {
	my ($self) = @_;
	my $conf_file = $self->_get_conf_file;
	my %label_used;
	my $files = [];
	open( my $fh, '<:encoding(utf8)', $conf_file ) || $logger->error("Cannot open $conf_file for reading");
	while ( my $line = <$fh> ) {
		$line =~ s/^\s+|\s+$//gx;    #Remove trailing spaces
		$line =~ s/\#.*$//x;         #Strip comment lines
		next if !$line;
		my ( $filename, $label, $desc, $file_type ) = split /\ *\t\ */x, $line;
		next if !$filename;
		if ( !-e $filename ) {
			$logger->error("Error in $conf_file: $filename does not exist.");
			next;
		}
		if ( !$label ) {
			if ( $filename =~ /([^\/]*)$/x ) {
				$label = $1;
				$label //= 'File';
			}
		}
		if ( $label_used{$label} ) {
			$logger->error("Error in $conf_file: Label $label used more than once.");
			next;
		}
		$label_used{$label} = 1;
		my $file = { filename => $filename, label => $label, type => $file_type // 'text' };
		$file->{'description'} = $desc if $desc;
		push @$files, $file;
	}
	close $fh;
	return $files;
}

sub get_title {
	my ($self) = @_;
	my $desc = $self->{'system'}->{'description'} || 'BIGSdb';
	return "Files available for download - $desc";
}

sub initiate {
	my ($self) = @_;
	my $q = $self->{'cgi'};
	my %display_in_browser = map { $_ => 1 } qw(xhtml html text);
	$self->{'noCache'} = 1;
	if ( $q->param('file') ) {
		my $label = $q->param('file');
		my $file  = $self->_get_file_info($label);
		if ($file) {
			$self->{'attachment'} = $label if !$display_in_browser{ $file->{'type'} };
			$self->{'type'} = $file->{'type'};
		}
	} else {
		$self->{'jQuery'} = 1;
	}
	return;
}
1;
