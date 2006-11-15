package SVK::Logger;
use strict;
use warnings;

use SVK::Version;  our $VERSION = $SVK::VERSION;

use Log::Log4perl qw(get_logger :levels);

my $conf = q{
  log4perl.rootLogger=INFO, Screen
  log4perl.appender.Screen = Log::Log4perl::Appender::Screen
  log4perl.appender.Screen.layout = PatternLayout
  log4perl.appender.Screen.layout.ConversionPattern = %m%n
};

# ... passed as a reference to init()
Log::Log4perl::init( \$conf );
    
sub import {
  my $class = shift;
  my $var = shift || 'logger';
  
  # it's ok if people add a sigil; we can get rid of that.
  $var =~ s/^\$*//;
  
  # Find out which package we'll export into.
  my $caller = caller() . '';

  (my $name = $caller) =~ s/::/./g;
  my $logger = Log::Log4perl->get_logger(lc($name));
  {
    # As long as we don't use a package variable, each module we export
    # into will get their own object. Also, this allows us to decide on 
    # the exported variable name. Hope it isn't too bad form...
    no strict 'refs';
    *{ $caller . "::$var" } = \$logger;
  }
}

1;

__END__

=head1 NAME

SVK::Logger - logging framework for SVK

=head1 SYNOPSIS

  use SVK::Logger;
  
  $logger->warn('foo');
  $logger->info('bar');
  
or 

  use SVK::Logger '$foo';
  
  $foo->error('bad thingimajig');

=head2 DESCRIPTION

SVK::Logger is a wrapper around Log::Log4perl. When using the module, it
imports into your namespace a variable called $logger (or you can pass a
variable name to import to decide what the variable should be) with a
category based on the name of the calling module.

=head1 MOTIVATION

Ideally, for support requests, if something is not going the way it
should be we should be able to tell people: "rerun the command with the
SVKDEBUG=1 environment variable set and mail the output to
$SUPPORTADDRESS":

  env SVKDEBUG=1 svk <command that failed> 2>&1 | mail $SUPPORTADDRESS

On Windows, the same can be achieved by doing:

  XXX - somebody clueful please fill in -- I don't know Windows

=head1 AUTHORS

Stig Brautaset E<lt>stig@brautaset.orgE<gt>

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2006 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>


=cut
