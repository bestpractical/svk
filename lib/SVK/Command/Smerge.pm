package SVK::Command::Smerge;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Merge );
use SVK::XD;

sub options {
    ($_[0]->SUPER::options,
     'B|baseless'	=> 'baseless',
     'b|base=s'         => 'merge_base',
     'baserev=i'        => 'rev',
    );
}

sub run {
    my ($self, @arg) = @_;
    $self->{auto}++;
    if ($self->{baserev}) {
	print loc("--baserev is deprecated, use --base instead\n");
	$self->{base} ||= $self->{baserev};
    }
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

 -I [--incremental]     : apply each change individually
 -l [--log]             : use logs of merged revisions as commit message
 -B [--baseless]        : use the earliest revision as the merge point
 -b [--base] BASE       : use BASE as the merge base, which can be PATH:REV
 -s [--sync]            : synchronize mirrored sources before update
 -t [--to]              : merge to the specified path
 -f [--from]            : merge from the specified path
 --verbatim             : verbatim merge log without indents and header
 --no-ticket            : do not record this merge point
 --track-rename         : track changes made to renamed node
 --host HOST            : use HOST as the hostname shown in merge log
 --remoterev            : use remote revision numbers in merge log
 -m [--message] MESSAGE : specify commit message MESSAGE
 -F [--file] FILENAME   : read commit message from FILENAME
 --template             : use the specified message as the template to edit
 --encoding ENC         : treat -m/-F value as being in charset encoding ENC
 -P [--patch] NAME      : instead of commit, save this change as a patch
 -S [--sign]            : sign this change
 -C [--check-only]      : try operation but make no changes
 --direct               : commit directly even if the path is mirrored

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
