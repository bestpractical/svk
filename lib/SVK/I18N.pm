package SVK::I18N;

use strict;
use base 'Exporter';

our @EXPORT = 'loc';

sub loc {
    no strict 'refs';
    local $SIG{__WARN__} = sub {};

    if (eval {
	require Locale::Maketext::Simple;
	Locale::Maketext::Simple->VERSION >= 0.12
    }) {
	Locale::Maketext::Simple->import(
	    Subclass    => '',
	    Path	    => substr(__FILE__, 0, -3),
	    Style	    => 'gettext',
	    Encoding    => 'locale',
	);
    }
    else {
	*loc = *_default_gettext;
    }

    goto &{"SVK::I18N::loc"};
}

sub _default_gettext {
    my $str = shift;
    $str =~ s{
	%			# leading symbol
	(?:			# either one of
	    \d+			#   a digit, like %1
	    |			#     or
	    (\w+)\(		#   a function call -- 1
		(?:		#     either
		    %\d+	#	an interpolation
		    |		#     or
		    ([^,]*)	#	some string -- 2
		)		#     end either
		(?:		#     maybe followed
		    ,		#       by a comma
		    ([^),]*)	#       and a param -- 3
		)?		#     end maybe
		(?:		#     maybe followed
		    ,		#       by another comma
		    ([^),]*)	#       and a param -- 4
		)?		#     end maybe
		[^)]*		#     and other ignorable params
	    \)			#   closing function call
	)			# closing either one of
    }{
	my $digit = $2 || shift;
	$digit . (
	    $1 ? (
		($1 eq 'tense') ? (($3 eq 'present') ? 'ing' : 'ed') :
		($1 eq 'quant') ? ' ' . (($digit > 1) ? ($4 || "$3s") : $3) :
		''
	    ) : ''
	);
    }egx;
    return $str;
}

1;
