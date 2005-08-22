package SVK::Command::Move;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base qw( SVK::Command::Copy );
use SVK::Util qw ( abs2rel );
use SVK::I18N;

sub lock {
    my $self = shift;
    $self->lock_coroot(@_);
}

sub handle_direct_item {
    my $self = shift;
    my ($editor, $anchor, $m, $src, $dst) = @_;
    my $srcm = $self->under_mirror ($src);
    my $call;
    if ($srcm && $srcm->{target_path} eq $src->path) {
	# this should be in svn::mirror
	my $props = $src->root->node_proplist($src->path);
	# this is very annoying: for inejecting an additional
	# editor call, has to give callback to Command::Copy's
	# handle_direct_item
	$call = sub {
	    $editor->change_dir_prop($_[0], $_, $props->{$_},
				     )
 		for grep { m/^svm:/ } keys %$props;
	};
	push @{$self->{post_process_mirror}}, [$src->path, $dst->path];
    }
    $self->SUPER::handle_direct_item (@_, $call);

    $editor->delete_entry (abs2rel ($src->path, $anchor => undef, '/'),
			   $m ? scalar $m->find_remote_rev ($src->{revision})
			      : $src->{revision}, 0);
    $self->adjust_anchor ($editor);
}

sub handle_co_item {
    my ($self, $src, $dst) = @_;
    $self->SUPER::handle_co_item ($src->new, $dst); # might be modified
    $self->{xd}->do_delete (%$src);
}

sub run {
    my $self = shift;
    my $src = $_[0];
    my $ret = $self->SUPER::run(@_);
    if ($self->{post_process_mirror}) {
	# XXX: also should set svm:incomplete revprop
	# should be in SVN::Mirror as well
	my $mstring = $src->root->node_prop('/', 'svm:mirror');
	for (@{$self->{post_process_mirror}}) {
	    my ($from, $to) = @$_;
	    $mstring =~ s/^\Q$from\E$/$to/;
	}
	my $cmd = $self->command('propset', { revision => undef,
					      message => 'svk: fix-up for mirror move' });
	$cmd->run($cmd->parse_arg('svm:mirror', $mstring,
				  '/'.$src->depotname.'/'));
    }
    return $ret;
}

__DATA__

=head1 NAME

SVK::Command::Move - Move a file or directory

=head1 SYNOPSIS

 move DEPOTPATH1 DEPOTPATH2

=head1 OPTIONS

 -r [--revision] REV    : act on revision REV instead of the head revision
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

Moveright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
