package SVK::Command::Ignore;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base qw( SVK::Command );

use SVK::Util qw ( abs2rel );

sub parse_arg {
    my ($self, @arg) = @_;
    return unless @arg;
    return map { $self->arg_copath($_) } @arg;
}

sub lock {
    my $self = shift;

    my $condensed = $self->{xd}->target_condensed(@_);
    $self->{xd}->lock($condensed->copath_anchor);
}

sub do_ignore {
    my $self = shift;
    my $target = shift;

    my $report = $target->report;

    $target->anchorify;

    my $filename = $target->copath_target;

    my $current_props = $target->root->node_proplist($target->path_anchor);

    my $svn_ignore = $current_props->{'svn:ignore'};
    $svn_ignore = '' unless defined $svn_ignore;

    my $current_ignore_re = $self->{xd}->ignore($svn_ignore);
    if ($filename =~ m/$current_ignore_re/) {
        print "Already ignoring '$report'\n";
    } else {
        $svn_ignore .= "\n"
          if length $svn_ignore and substr($svn_ignore, -1, 1) ne "\n";
        $svn_ignore .= "$filename\n";

        $self->{xd}->do_propset
          (
           $target->for_checkout_delta,
           propname => 'svn:ignore',
           propvalue => $svn_ignore,
          );
    }
}

sub run {
    my ($self, @targets) = @_;
    $SVN::Error::handler = \&SVN::Error::confess_on_error;

    $self->do_ignore($_) for @targets;
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Ignore - Ignore files by setting svn:ignore property

=head1 SYNOPSIS

 ignore PATH...

=head1 DESCRIPTION

Adds the given paths to the 'svn:ignore' properties of their parents,
if they are not already there.

(If a given path contains a wildcard character (*, ?, [, or \), the
results are undefined -- specifically, the result of the check to see
if the entry is already there may not be what you expected.  Currently
it will not try to escape any such entries before adding them.)

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

# 15:09 < glasser> ok, syntax:
# 15:09 < glasser> svk ignore FILE [FILE...], only working on a co
# 15:10 < obra> there should also be a way to svk ignore a pattern
# 15:10 < glasser> adds each argument to the svn:ignore of its parent directory
# 15:10  * glasser nods
# 15:10 < glasser> i'm thinking for now just svk ignore some/dir/'*.foo'
# 15:10 < glasser> and not support svk ignore some/dir/*/and/bla 
# 15:10 < obra> nod
# 15:10 < glasser> (yet)
# 15:11 < obra> svk ignore --list
# 15:11 < obra> svk ignore --remove ?
# 15:11 < glasser> ie, the only parsing that is done is "find the directory"
# 15:11 < glasser> later we can act directly on depotpaths, etc
# 15:11  * glasser nods
# 15:12 < glasser> i think it's reasonable to (even once we have --list --remove etc) just allow "svk ignore foo bar" to work
#             (without requiring --add or whatever)
# 15:12 < glasser> also svk ignore --edit
# 15:13 < obra> yes
# 15:14 < glasser> these are good ideas, and will be stuck into a comment in Ignore.pm, but for now i'm just going to do the bare minimum
