package SVK::Command::Delete;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::I18N;
use SVK::Util qw( abs2rel );

sub options {
    ($_[0]->SUPER::options,
     'force'	=> 'force',
     'K|keep-local'	=> 'keep');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return if $#arg < 0;
    my $target;
    @arg = map { $self->{xd}->target_from_copath_maybe($_) } @arg;

    # XXX: better check for @target being the same type
    if (grep {$_->isa('SVK::Path::Checkout')} @arg) {
	die loc("Mixed depotpath and checkoutpath not supported.\n")
	    if grep {!$_->isa('SVK::Path::Checkout')} @arg;

	return $self->{xd}->target_condensed(@arg);
    }

    return @arg;
}

sub lock {
    my ($self, $target) = @_;
    $self->lock_target ($target);
}

sub do_delete_direct {
    my ( $self, @args ) = @_;
    my $target = $args[0];
    my $m      = $self->under_mirror($target);
    if ( $m && $m->path eq $target->path ) {
        $m->detach;
        $target->refresh_revision;
        undef $m;
    }

    $self->get_commit_message;
    $target->normalize;
    my ( $anchor, $editor ) = $self->get_dynamic_editor($target);
    for (@args) {
        my $rev = $target->revision;
        $rev = $m->find_remote_rev($rev)
          if
          $m; # XXX: why do we need this? path->get_editor shuold do translation
        $editor->delete_entry( abs2rel( $_->path, $anchor => undef, '/' ),
            $rev, 0 );
        $self->adjust_anchor($editor);
    }
    $self->finalize_dynamic_editor($editor);
}

sub _ensure_mirror {
    my ($self, $target) = @_;

    my @m = $target->contains_mirror or return;

    return if $#m == 0 && $m[0] eq $target->path_anchor;

    my $depotname = $target->depotname;
    die loc("%1 contains mirror, remove explicitly: ", "/$depotname".$target->path_anchor).
	join(',', map { "/$depotname$_" } @m)."\n"
}

sub run {
    my ($self, @args) = @_;


    if ($args[0]->isa('SVK::Path::Checkout')) {
	my $target = $args[0]; # already condensed
	$self->_ensure_mirror($target);
	$self->{xd}->do_delete( $target, no_rm => $self->{keep}, 
		'force_delete' => $self->{force} );
    }
    else {
	$self->_ensure_mirror($_) for @args;
	die loc("Different source.\n") unless
	    $args[0]->same_source(@args);
	$self->do_delete_direct( @args );
    }

    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Delete - Remove versioned item

=head1 SYNOPSIS

 delete [PATH...]
 delete [DEPOTPATH...]

=head1 OPTIONS

 -K [--keep-local]      : do not remove the local file
 -m [--message] MESSAGE : specify commit message MESSAGE
 -F [--file] FILENAME   : read commit message from FILENAME
 --template             : use the specified message as the template to edit
 --encoding ENC         : treat -m/-F value as being in charset encoding ENC
 -P [--patch] NAME      : instead of commit, save this change as a patch
 -S [--sign]            : sign this change
 -C [--check-only]      : try operation but make no changes
 --direct               : commit directly even if the path is mirrored
 --force                : delete the file/directory even if modified

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
