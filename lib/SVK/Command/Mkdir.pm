package SVK::Command::Mkdir;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( abs2rel get_anchor );
use File::Path;

sub options {
    ($_[0]->SUPER::options,
     'p|parent' => 'parent');
}

sub parse_arg {
    my ($self, @arg) = @_;
    # XXX: support multiple
    return if $#arg != 0;
    my @targets;
    my $path = $arg[0];
    # parsing all of the folder we need to add.
    until (@targets = eval { ($self->arg_co_maybe ($path)) }) {
	my ($parent, $target) = get_anchor(1, $path);
	unless ($parent and $self->{parent}) {
	    # non a copath or something wrong
	    # XXX: better check for error types
	    # should tell the user about parent not exist
            return ($self->arg_depotpath($path));
        }
        $self->parse_arg($parent);
	undef $self->{parent};
    }
    # execute the mkdir
    if ($@ || grep {$_->{copath}} @targets) {
        my $target = $self->arg_condensed ($path);
        foreach (@{$target->{targets}}) {
            my $copath = $target->copath ($_);
	    $self->{parent} ? mkpath ([$copath])
	    	: mkdir ($copath) or die "$copath: $!";
        }
        return $self->rebless (
           add => {
              recursive => 1
           }
        )->parse_arg ($path)
    }
    return @targets;
}

sub run {
    my ($self, $target) = @_;
    $self->get_commit_message ();
    my ($anchor, $editor) = $self->get_dynamic_editor ($target);
    $editor->close_directory
	($editor->add_directory (abs2rel ($target->path, $anchor => undef, '/'),
				 0, undef, -1));
    $self->adjust_anchor ($editor);
    $self->finalize_dynamic_editor ($editor);
    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Mkdir - Create a versioned directory

=head1 SYNOPSIS

 mkdir DEPOTPATH
 mkdir PATH

=head1 OPTIONS

 -m [--message] arg     : specify commit message ARG
 -p [--parent]          : create intermediate directories as required
 -C [--check-only]      : try operation but make no changes
 -P [--patch] arg       : instead of commit, save this change as a patch
 -S [--sign]            : sign this change

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
