package SVK::Config;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base 'Class::Data::Inheritable';

__PACKAGE__->mk_classdata(qw(_svnconfig));

my $pool = SVN::Pool->new;

sub svnconfig {
    my $class = shift;
    return undef if $ENV{SVKNOSVNCONFIG};

    return $class->_svnconfig if $class->_svnconfig;

    SVN::Core::config_ensure(undef);
    return $class->_svnconfig( SVN::Core::config_get_config(undef, $pool) );
}

1;
