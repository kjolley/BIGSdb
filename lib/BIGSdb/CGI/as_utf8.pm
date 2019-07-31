#Properly handle unicode in web forms
#See https://en.wikibooks.org/wiki/Perl_Programming/Unicode_UTF-8#Input_-_Web_forms
package BIGSdb::CGI::as_utf8;
use strict;
use warnings;
use Log::Log4perl qw(get_logger);
my $logger = get_logger('BIGSdb.Page');
use constant LIST_CONTEXT_WARN => 1;

BEGIN {
	use CGI 4.08;    #Needed to support CGI::multi_param
	$CGI::LIST_CONTEXT_WARN = 0;
	{
		no warnings 'redefine';
		my $param_org    = \&CGI::param;
		my $might_decode = sub {
			my $p = shift;

			# make sure upload() filehandles are not modified
			return $p if !$p || ( ref $p && fileno($p) );
			utf8::decode($p);       # may fail, but only logs an error
			$p;
		};
		*CGI::param = sub {

			# setting a param goes through the original interface
			goto &$param_org if scalar @_ != 2;
			my ( $q, $p ) = @_;     # assume object calls always
			if ( wantarray  ) {
				my ( $package, $filename, $line ) = caller;
				if ( $package ne 'CGI' && LIST_CONTEXT_WARN ) {
					$logger->logcarp('CGI::param called in list context');
				}
			}
			return wantarray
			  ? map { $might_decode->($_) } $q->$param_org($p)
			  : $might_decode->( $q->$param_org($p) );
		  }
	}
}
1;
