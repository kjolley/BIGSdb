#Properly handle unicode in web forms
#See http://en.wikibooks.org/wiki/Perl_Programming/Unicode_UTF-8#Input_-_Web_Forms
package BIGSdb::CGI::as_utf8;
use strict;
use warnings;

BEGIN {
	use CGI; # 3.47;    # earlier versions have a UTF-8 double-decoding bug
	{
		no warnings 'redefine';
		my $param_org    = \&CGI::param;
		my $might_decode = sub {
			my $p = shift;

			# make sure upload() filehandles are not modified
			return $p if !$p || ( ref $p && fileno($p) );
			utf8::decode($p);    # may fail, but only logs an error
			$p;
		};
		*CGI::param = sub {

			# setting a param goes through the original interface
			goto &$param_org if scalar @_ != 2;
			my ( $q, $p ) = @_;    # assume object calls always
			return wantarray
			  ? map { $might_decode->($_) } $q->$param_org($p)
			  : $might_decode->( $q->$param_org($p) );
		  }
	}
}
1;
