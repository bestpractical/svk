package SVK::Command;
use strict;
our $VERSION = $SVK::VERSION;
use Getopt::Long qw(:config no_ignore_case bundling);
# XXX: Pod::Simple isn't happy with SVN::Simple::Edit, so load it first
use SVN::Simple::Edit;
use SVK::Target;
use Pod::Simple::Text ();
use Pod::Simple::SimpleTree ();
use File::Find ();
use Cwd;
use SVK::I18N;

my %alias = qw( co checkout
		up update
		blame annotate
		ci commit
		del delete
		rm delete
		ps propset
		pe propedit
		pl proplist
		cp copy
		mv move
		ren move
		rename move
		mi mirror
		sm smerge
		sy sync
		desc describe
		st status
		stat status
		ver version
		ls list
	      );

sub new {
    my ($class, $xd) = @_;
    my $self = bless { xd => $xd }, $class;
    return $self;
}

sub options { () }

sub parse_arg { return (undef) }

sub _opt_map {
    my ($self, %opt) = @_;
    return map {$_ => \$self->{$opt{$_}}} sort keys %opt;
}

sub _cmd_map {
    my ($cmd) = @_;
    $cmd = $alias{$cmd} if exists $alias{$cmd};
    $cmd =~ s/^(.)/\U$1/;
    return $cmd;
}

sub get_cmd {
    my ($pkg, $cmd, $xd) = @_;
    die "Command not recognized, try $0 help.\n"
	unless $cmd =~ m/^[a-z]+$/;
    $pkg = join('::', 'SVK::Command', _cmd_map ($cmd));
    unless (eval "require $pkg; 1" && UNIVERSAL::can($pkg, 'run')) {
	$pkg =~ s|::|/|g;
	warn $@ if $@ && exists $INC{"$pkg.pm"};
	die "Command not recognized, try $0 help.\n";
    }
    $pkg->new ($xd);
}

sub invoke {
    my ($pkg, $xd, $cmd, $output, @args) = @_;
    my ($help, $ofh, $ret);
    local @ARGV = @args;
    my $pool = SVN::Pool->new_default;
    $ofh = select $output if $output;
    eval {
	$cmd = get_cmd ($pkg, $cmd, $xd);
	die loc ("Unknown options.\n")
	    unless GetOptions ('h|help' => \$help, _opt_map($cmd, $cmd->options));

	if ($help || !(@args = $cmd->parse_arg(@ARGV))) {
	    $cmd->usage;
	}
	else {
	    eval { $cmd->lock (@args); $ret = $cmd->run (@args) };
	    $xd->unlock if $xd;
	    die $@ if $@;
	}
    };
    print $ret if $ret;
    print $@ if $@;
    select $ofh if $output;
}

sub brief_usage {
    my ($self, $file) = @_;
    my $fname = ref($self);
    $fname =~ s|::|/|g;
    my $parser = Pod::Simple::SimpleTree->new;
    my @rows = @{$parser->parse_file($file || $INC{"$fname.pm"})->root};
    while (my $row = shift @rows) {
        if ( ref($row) eq 'ARRAY' && $row->[0] eq 'head1' && $row->[2] eq 'NAME')  {
            my $buf = $rows[0][2];
            $buf =~ s/SVK::Command::(\w+ - .+)/loc(lcfirst($1))/eg;
            print "   $buf\n";
            last;
        }
    }
}

sub usage {
    my ($self, $detail) = @_;
    # XXX: the order from selected is not preserved.
    my $fname = ref($self);
    $fname =~ s|::|/|g;
    my $parser = Pod::Simple::Text->new;
    my $buf;
    $parser->output_string(\$buf);
    $parser->parse_file($INC{"$fname.pm"});

    $buf =~ s/SVK::Command::(\w+)/\l$1/g;
    $buf =~ s/^AUTHORS.*//sm;
    $buf =~ s/^DESCRIPTION.*//sm unless $detail;
    foreach my $line (split(/\n/, $buf, -1)) {
	if ($line =~ /^(\s*)(.+?: )( *)(.+?)(\s*)$/) {
	    my $spaces = $3;
	    my $loc = $1 . loc($2 . $4) . $5;
	    $loc =~ s/: /: $spaces/ if $spaces;
	    print $loc, "\n";
	}
	elsif ($line =~ /^(\s*)(.+?)(\s*)$/) {
	    print $1||'', loc($2), $3||'', "\n";
	}
	else {
	    print "\n";
	}
    }
}

sub lock_target {
    my ($self, $target) = @_;
    $self->{xd}->lock ($target->{copath});
}

sub lock_none {
    my ($self) = @_;
    $self->{xd}->giant_unlock ();
}

sub lock {
}

sub arg_condensed {
    my ($self, @arg) = @_;
    return if $#arg < 0;
    my ($report, $copath, @targets )= $self->{xd}->condense (@arg);

    my ($repospath, $path, $cinfo, $repos) = $self->{xd}->find_repos_from_co ($copath, 1);
    return SVK::Target->new
	( repos => $repos,
	  repospath => $repospath,
	  copath => $copath,
	  path => $path,
	  report => $report,
	  targets => @targets ? \@targets : undef );
}

sub arg_co_maybe {
    my ($self, $arg) = @_;
    my $rev = $arg =~ s/\@(\d+)$// ? $1 : undef;
    my ($repospath, $path, $copath, $cinfo, $repos) =
	$self->{xd}->find_repos_from_co_maybe ($arg, 1);
    return SVK::Target->new
	( repos => $repos,
	  repospath => $repospath,
	  depotpath => $cinfo->{depotpath} || $arg,
	  copath => $copath,
	  report => $arg,
	  path => $path,
	  revision => $rev,
	);
}

sub arg_copath {
    my ($self, $arg) = @_;
    my ($repospath, $path, $cinfo, $repos) = $self->{xd}->find_repos_from_co ($arg, 1);
    return SVK::Target->new
	( repos => $repos,
	  repospath => $repospath,
	  report => $arg,
	  copath => Cwd::abs_path ($arg),
	  path => $path,
	  cinfo => $cinfo,
	  depotpath => $cinfo->{depotpath},
	);
}

sub arg_depotpath {
    my ($self, $arg) = @_;
    my $rev = $arg =~ s/\@(\d+)$// ? $1 : undef;
    my ($repospath, $path, $repos) = $self->{xd}->find_repos ($arg, 1);

    return SVK::Target->new
	( repos => $repos,
	  repospath => $repospath,
	  path => $path,
	  report => $arg,
	  revision => $rev,
	  depotpath => $arg,
	);
}

sub arg_depotname {
    my ($self, $arg) = @_;

    return $self->{xd}->find_depotname ($arg, 1);
}

sub arg_path {
    my ($self, $arg) = @_;

    return Cwd::abs_path ($arg);
}

1;

__DATA__

=head1 NAME

SVK::Command - Base class for SVK commands

=head1 SYNOPSIS

  use SVK::Command;
  # invoking commands
  SVK::Command->invoke ($xd, $cmd, $output, @arg);

=head1 DESCRIPTION

=head2 Invoking commands

Use C<SVK::Command-E<gt>invoke>. The arguments in order are the
L<SVK::XD> object, the command name, the output scalar ref, and the
arguments for the command. The command name is translated with the
C<%alias> map.

=head2 Implementing svk commands

C<SVK::Command-E<gt>invoke> loads the corresponding class
C<SVK::Command::I<$name>>, so that's the class you want to implement
the following methods in:

=head3 options

Returns a hash where the keys are L<Getopt::Long> specs and the values
are a string that will be the keys storing the parsed option in
C<$self>.

=head3 parse_arg

Given the array of command arguments, use C<arg_*> methods to return a
more meaningful array of arguments.

=head3 lock

Use the C<lock_*> methods to lock the L<SVK::XD> object. The arguments
will be what is returned from C<parse_arg>.

=head3 run

Actually process the command. The arguments will be what is returned
from C<parse_arg>.

Returned undef on success. Return a string message to notify the
caller errors.

=head1 METHODS

=head2 Methods for C<parse_arg>

=over

=item arg_depotname

Argument is a name of depot. such as '' or 'test' that is being used
normally between two slashes.

=item arg_path

Argument is a plain path in the filesystem.

=item arg_copath

Argument is a checkout path.

=item arg_depotpath

Argument is a depotpath, including the slashes and depot name.

=item arg_co_maybe

Argument might be a checkout path or a depotpath.

=item arg_condensed

Argument is a number of checkout paths.

=back

All the methods except C<arg_depotname> returns a L<SVK::Target>
object, which is a hash with the following keys:

=over

=item cinfo

=item copath

=item depotpath

=item path

=item repos

=item repospath

=item report

=item targets

=back

The hashes are handy to pass to many other functions.

=head2 Methods for C<lock>

=over

=item lock_none

=item lock_target

=back

=head2 Others

=over

=item brief_usage

Display an one-line brief usage of the command. Optionally a file
could be given to extract the usage from the pod.

=item usage

Display usage. An optional argument is to display detail or not.

=back

=head1 TODO

=head1 SEE ALSO

L<SVK>, L<SVK::XD>, C<SVK::Command::*>

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
