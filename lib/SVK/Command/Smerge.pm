package SVK::Command::Smerge;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Merge );
use SVK::XD;

sub options {
    ($_[0]->SUPER::options,
     'B|baseless'	=> 'baseless',
     'b|base|baserev:i'	=> 'baserev',
    );
}

sub run {
    my ($self, @arg) = @_;
    $self->{auto}++;
    $self->SUPER::run (@arg);
}

1;

__DATA__

=head1 NAME

SVK::Command::Smerge - Automatically merge all changes between branches

=head1 SYNOPSIS

 smerge DEPOTPATH [PATH]
 smerge DEPOTPATH1 DEPOTPATH2
 smerge [--to|--from] [PATH]

=head1 OPTIONS

 -m [--message] MESSAGE	: specify commit message MESSAGE
 -C [--check-only]      : try operation but make no changes
 -I [--incremental]     : apply each change individually
 -l [--log]             : use logs of merged revisions as commit message
 -B [--baseless]        : use the earliest revision as the merge point
 -b [--base] REV	: use revision REV of SOURCE as the merge base
 -s [--sync]            : synchronize mirrored sources before update
 -t [--to]              : merge to the specified path
 -f [--from]            : merge from the specified path
 -P [--patch] NAME	: instead of commit, save this change as a patch
 -S [--sign]            : sign this change
 --verbatim             : verbatim merge log without indents and header
 --no-ticket            : do not record this merge point
 --track-rename         : track changes made to renamed node
 --host HOST		: use HOST as the hostname shown in merge log
 --remoterev            : use remote revision numbers in merge log

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
