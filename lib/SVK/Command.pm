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
use SVK::Util qw( abs_path $SEP IS_WIN32 );
use SVK::I18N;

=head1 NAME

SVK::Command - Base class and dispatcher for SVK commands

=head1 SYNOPSIS

    use SVK::Command;
    my $xd = SVK::XD->new ( ... );
    my $cmd = 'checkout';
    my @args = qw( file1 file2 );
    open my $output_fh, '>', 'svk.log' or die $!;
    SVK::Command->invoke ($xd, $cmd, $output_fh, @args);

=head1 DESCRIPTION

This module resolves alias for commands and dispatches them, usually with
the C<invoke> method.  If the command invocation is incorrect, usage
information is displayed instead.

=head1 METHODS

=head2 Class Methods

=cut

my %alias = qw( co checkout
		up update
		blame annotate
		ci commit
		del delete
		rm delete
		pg propget
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

=head3 new ($xd)

Base constructor for all commands.

=cut

sub new {
    my ($class, $xd) = @_;
    my $self = bless { xd => $xd }, $class;
    return $self;
}

=head3 get_cmd ($cmd, $xd)

Load the command subclass specified in C<$cmd>, and return a new
instance of it, populated with C<$xd>.  Command aliases are handled here.

=cut

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

sub _cmd_map {
    my ($cmd) = @_;
    $cmd = $alias{$cmd} if exists $alias{$cmd};
    $cmd =~ s/^(.)/\U$1/;
    return $cmd;
}

=head3 invoke ($xd, $cmd, $output_fh, @args)

Takes a L<SVK::XD> object, the command name, the output scalar reference,
and the arguments for the command. The command name is translated with the
C<%alias> map.

On Win32, after C<@args> is parsed for named options, the remaining positional
arguments are expanded for shell globbing with C<File::Glob::bsd_glob>.

=cut

sub invoke {
    my ($pkg, $xd, $cmd, $output, @args) = @_;
    my ($help, $ofh, $ret);
    local @ARGV = @args;
    my $pool = SVN::Pool->new_default;
    $ofh = select $output if $output;
    my $error;
    local $SVN::Error::handler = sub {
	$error = $_[0];
	SVN::Error::croak_on_error (@_);
    };
    eval {
	$cmd = get_cmd ($pkg, $cmd, $xd);
	$cmd->{svnconfig} = $xd->{svnconfig} if $xd;
	die loc ("Unknown options.\n")
	    unless GetOptions ('h|help' => \$help, _opt_map($cmd, $cmd->options));

	# Fake shell globbing on Win32 if we are called from main
	if (IS_WIN32 and caller(1) eq 'main') {
	    require File::Glob;
	    @ARGV = map {
		/[?*{}\[\]]/
		    ? File::Glob::bsd_glob($_, File::Glob::GLOB_NOCHECK())
		    : $_
	    } @ARGV;
	}

	if ($help || !(@args = $cmd->parse_arg(@ARGV))) {
	    select STDERR unless $output;
	    $cmd->usage;
	}
	else {
	    eval { $cmd->lock (@args); $ret = $cmd->run (@args) };
	    print STDERR "======>[$@]\n" if $ENV{DEBUG};
	    $xd->unlock if $xd;
	    die $@ if $@;
	}
    };
    $ofh = select STDERR unless $output;
    unless ($error and $cmd->handle_error ($error)) {
	print $ret if $ret;
	print $@ if $@;
    }
    select $ofh if $ofh
}

=head2 Instance Methods

C<SVK::Command-E<gt>invoke> loads the corresponding class
C<SVK::Command::I<$name>>, so that's the class you want to implement
the following methods in:

=head3 options ()

Returns a hash where the keys are L<Getopt::Long> specs and the values
are a string that will be the keys storing the parsed option in
C<$self>.

Subclasses should override this to add their own options.  Defaults to
an empty list.

=cut

sub options { () }

sub _opt_map {
    my ($self, %opt) = @_;
    return map {$_ => \$self->{$opt{$_}}} sort keys %opt;
}

=head3 parse_arg (@args)

This method is called with the remaining arguments after parsing named
options with C<options> above.  It should use the C<arg_*> methods to
return a list of parsed arguments for the command's C<lock> and C<run> method
to process.  Defaults to return a single C<undef>.

=cut

sub parse_arg { return (undef) }

=head3 lock (@parse_args)

Calls the C<lock_*> methods to lock the L<SVK::XD> object. The arguments
will be what is returned from C<parse_arg>.

=cut

sub lock {
}

=head3 run (@parsed_args)

Actually process the command. The arguments will be what is returned
from C<parse_arg>.

Returned undef on success. Return a string message to notify the
caller errors.

=cut

sub run {
    require Carp;
    Carp::croak("Subclasses should implement its 'run' method!");
}

=head2 Utility Methods

Except for C<arg_depotname>, all C<args_*> methods below returns a
L<SVK::Target> object, which consists of a hash with the following keys:

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

=head3 arg_condensed (@args)

Argument is a number of checkout paths.

=cut

sub arg_condensed {
    my ($self, @arg) = @_;
    return if $#arg < 0;

    s{[/\Q$SEP\E]$}{}o for @arg; # XXX band-aid

    my ($report, $copath, @targets )= $self->{xd}->condense (@arg);
    my ($repospath, $path, $cinfo, $repos) = $self->{xd}->find_repos_from_co ($copath, 1);
    my $target = SVK::Target->new
	( repos => $repos,
	  repospath => $repospath,
	  depotpath => $cinfo->{depotpath},
	  copath => $copath,
	  path => $path,
	  report => $report,
	  targets => @targets ? \@targets : undef );
    my $root = $target->root ($self->{xd});
    until ($root->check_path ($target->{path}) == $SVN::Node::dir) {
	my $targets = delete $target->{targets};
	$target->anchorify;
	$target->{targets} = [map {"$target->{targets}[0]/$_"} @$targets]
	    if $targets;
    }
    return $target;
}

=head3 arg_co_maybe ($arg)

Argument might be a checkout path or a depotpath.

=cut

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

=head3 arg_copath ($arg)

Argument is a checkout path.

=cut

sub arg_copath {
    my ($self, $arg) = @_;
    my ($repospath, $path, $cinfo, $repos) = $self->{xd}->find_repos_from_co ($arg, 1);
    return SVK::Target->new
	( repos => $repos,
	  repospath => $repospath,
	  report => $arg,
	  copath => abs_path ($arg),
	  path => $path,
	  cinfo => $cinfo,
	  depotpath => $cinfo->{depotpath},
	);
}

=head3 arg_depotpath ($arg)

Argument is a depotpath, including the slashes and depot name.

=cut

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

=head3 arg_depotname ($arg)

Argument is a name of depot. such as '' or 'test' that is being used
normally between two slashes.

=cut

sub arg_depotname {
    my ($self, $arg) = @_;

    return $self->{xd}->find_depotname ($arg, 1);
}

=head3 arg_path ($arg)

Argument is a plain path in the filesystem.

=cut

sub arg_path {
    my ($self, $arg) = @_;

    return abs_path ($arg);
}

my %empty = map { ($_ => undef) } qw/.schedule .copyfrom .copyfrom_rev .newprop scheduleanchor/;
sub _schedule_empty { %empty };

=head3 lock_target ($target)

XXX Undocumented

=cut

sub lock_target {
    my ($self, $target) = @_;
    $self->{xd}->lock ($target->{copath});
}

=head3 lock_none ()

XXX Undocumented

=cut

sub lock_none {
    my ($self) = @_;
    $self->{xd}->giant_unlock ();
}

=head3 brief_usage ($file)

Display an one-line brief usage of the command object.  Optionally, a file
could be given to extract the usage from the POD.

=cut

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

=head3 usage ($want_detail)

Display usage.  If C<$want_detail> is true, the C<DESCRIPTION>
section is displayed as well.

=cut

sub usage {
    my ($self, $want_detail) = @_;
    # XXX: the order from selected is not preserved.
    my $fname = ref($self);
    $fname =~ s|::|/|g;
    my $parser = Pod::Simple::Text->new;
    my $buf;
    $parser->output_string(\$buf);
    $parser->parse_file($INC{"$fname.pm"});

    $buf =~ s/SVK::Command::(\w+)/\l$1/g;
    $buf =~ s/^AUTHORS.*//sm;
    $buf =~ s/^DESCRIPTION.*//sm unless $want_detail;
    foreach my $line (split(/\n\n+/, $buf, -1)) {
	if (my @lines = $line =~ /^( {4}\s+.+\s*)$/mg) {
            foreach my $chunk (@lines) {
                $chunk =~ /^(\s*)(.+?)( *)(: .+?)?(\s*)$/ or next;
                my $spaces = $3;
                my $loc = $1 . loc($2 . ($4||'')) . $5;
                $loc =~ s/: /$spaces: / if $spaces;
                print $loc, "\n";
            }
            print "\n";
	}
        elsif ($line =~ /^(\s+)(\w+ - .*)$/) {
            print $1, loc($2), "\n\n";
        }
        elsif (length $line) {
            print loc($line), "\n\n";
	}
    }
}

=head2 Error Handling

=cut

# XXX: here we should really just use $SVN::Error::handler.  But the
# problem is that it's called within the contxt of editor calls, so
# returning causes continuation; while dying would cause
# SVN::Delta::Editor to confess.

=head3 handle_error ($error)

XXX Undocumented

=cut

sub handle_error {
    my ($self, $error) = @_;
    my $err_code = $error->apr_err;
    return unless $self->{$err_code};
    $_->($error) for @{$self->{$err_code}};
    return 1;
}

=head3 add_handler ($error, $handler)

XXX Undocumented

=cut

sub add_handler {
    my ($self, $err, $handler) = @_;
    push @{$self->{$err}}, $handler;
}

=head3 msg_handler ($error, $message)

XXX Undocumented

=cut

sub msg_handler {
    my ($self, $err, $msg) = @_;
    $self->add_handler
	($err, sub {
	     print $_[0]->expanded_message."\n$msg\n";
	 });
}


1;

__DATA__

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
