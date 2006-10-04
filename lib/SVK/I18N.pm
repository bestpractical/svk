package SVK::I18N;

use strict;
use base 'Exporter';

our @EXPORT = 'loc';

sub loc {
    no strict 'refs';
    local $SIG{__WARN__} = sub {};
    local $@;

    if ( !lang_is_english() && eval {
        require Locale::Maketext::Lexicon;
        require Locale::Maketext::Simple;
        Locale::Maketext::Simple->VERSION >= 0.13 &&
        Locale::Maketext::Lexicon->VERSION >= 0.42
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
	    (\w+|\*)\(		#   a function call -- 1
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
		($1 eq 'quant' || $1 eq '*') ? ' ' . (($digit > 1) ? ($4 || "$3s") : $3) :
		''
	    ) : ''
	);
    }egx;
    return $str;
}

# try to determine if the locale is English.  This might yield a false
# negative in some corner cases, but then Locale::Maketext::Simple
# will do a more thorough analysis.  This is just an optimization.
sub lang_is_english {
    for my $env_name (qw( LANGUAGE LC_ALL LC_MESSAGES LANG )) {
        next if !$ENV{$env_name};
        return 1 if $ENV{$env_name} =~ /^en/;
        return;
    }

    return;
}

1;
