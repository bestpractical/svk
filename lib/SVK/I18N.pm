package SVK::I18N;

use strict;
use base 'Exporter';
use Locale::Maketext::Simple 0.12 ();

our @EXPORT = 'loc';

sub loc {
    no strict 'refs';
    local $SIG{__WARN__} = sub {};
    Locale::Maketext::Simple->import(
	Subclass    => '',
	Path	    => substr(__FILE__, 0, -3),
	Style	    => 'gettext',
	Encoding    => 'locale',
    );
    goto &{"SVK::I18N::loc"};
}

1;
