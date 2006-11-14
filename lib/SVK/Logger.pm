package SVK::Logger;
use strict;
use warnings;

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





=cut

1;
