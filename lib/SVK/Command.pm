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
use SVK::Util qw( get_prompt abs2rel abs_path is_uri catdir bsd_glob $SEP IS_WIN32 HAS_SVN_MIRROR );
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

my %alias = qw( ann		annotate
                blame		annotate
                praise		annotate
		co		checkout
		cm		cmerge
		ci		commit
		cp		copy
		del		delete
		remove		delete
		rm		delete
		depot		depotmap
		desc		describe
		di		diff
                h               help
                ?               help
		ls		list
		mi		mirror
		mv		move
		ren		move
		rename	    	move
		pd		propdel
		pdel		propdel
		pe		propedit
		pedit		propedit
		pg		propget
		pget		propget
		pl		proplist
		plist		proplist
		ps		propset
		pset		propset
		sm		smerge
		st		status
		stat		status
		sw		switch
		sy		sync
		up		update
		ver		version
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

To construct a command object from another command object, use the
C<command> instance method instead.

=cut

sub get_cmd {
    my ($pkg, $cmd, $xd) = @_;
    die "Command not recognized, try $0 help.\n"
	unless $cmd =~ m/^[?a-z]+$/;
    $pkg = join('::', 'SVK::Command', _cmd_map ($cmd));
    my $file = "$pkg.pm";
    $file =~ s!::!/!g;

    unless (eval {require $file; 1} and $pkg->can('run')) {
	warn $@ if $@ and exists $INC{$file};
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
arguments are expanded for shell globbing with C<bsd_glob>.

=cut

sub invoke {
    my ($pkg, $xd, $cmd, $output, @args) = @_;
    my ($help, $ofh, $ret);
    my $pool = SVN::Pool->new_default;
    $ofh = select $output if $output;
    my $error;
    local $SVN::Error::handler = sub {
	$error = $_[0];
	SVN::Error::croak_on_error (@_);
    };

    local $@;
    eval {
	$cmd = get_cmd ($pkg, $cmd, $xd);
	$cmd->{svnconfig} = $xd->{svnconfig} if $xd;
	$cmd->getopt (\@args, 'h|help|?' => \$help);

	# Fake shell globbing on Win32 if we are called from main
	if (IS_WIN32 and caller(1) eq 'main') {
	    @args = map {
		/[?*{}\[\]]/
		    ? bsd_glob($_, File::Glob::GLOB_NOCHECK())
		    : $_
	    } @args;
	}

	if ($help || !(@args = $cmd->parse_arg(@args))) {
	    select STDERR unless $output;
	    $cmd->usage;
	}
	else {
	    $cmd->msg_handler ($SVN::Error::FS_NO_SUCH_REVISION);
	    eval { $cmd->lock (@args); $ret = $cmd->run (@args) };
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

=head3 getopt ($argv, %opt)

Takes a arrayref of argv for run getopt for the command, with
additional %opt getopt options.

=cut

use constant opt_recursive => undef;

sub getopt {
    my ($self, $argv, %opt) = @_;
    local *ARGV = $argv;
    my $recursive = $self->opt_recursive;
    my $toggle = 0;
    $opt{$recursive ? 'N||non-recursive' : 'R|recursive'} = \$toggle
	if defined $recursive;
    die loc ("Unknown options.\n")
	unless GetOptions (%opt, $self->_opt_map ($self->options));
    $self->{recursive} = ($recursive + $toggle) % 2
	if defined $recursive;
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

=head3 opt_recursive

Defines if the command needs the recursive flag and its default.  The
value will be stored in C<recursive>.

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
    my ($repospath, $path, undef, $cinfo, $repos) = $self->{xd}->find_repos_from_co ($copath, 1);
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

=head3 arg_uri_maybe ($arg)

Argument might be a URI or a depotpath.  If it is a URI, try to find it
at or under one of currently mirrored paths.  If not found, prompts the
user to mirror and sync it.

=cut

sub arg_uri_maybe {
    my ($self, $arg) = @_;

    is_uri($arg) or return $self->arg_depotpath($arg);
    HAS_SVN_MIRROR or die loc("cannot load SVN::Mirror");

    require URI;
    my $uri = URI->new("$arg/")->canonical or die loc("%1 is not a valid URI.\n", $arg);
    my $map = $self->{xd}{depotmap};
    foreach my $depot (sort keys %$map) {
        local $@;
        my $repos = eval { ($self->{xd}->find_repos ("/$depot/", 1))[2] } or next;
	foreach my $path ( SVN::Mirror::list_mirror ($repos) ) {
	    my $m = SVN::Mirror->new (
                repos => $repos,
                get_source => 1,
                target_path => $path,
            );

            my $rel_uri = $uri->rel(URI->new("$m->{source}/")->canonical) or next;
            next if $rel_uri->eq($uri);
            next if $rel_uri =~ /^\.\./;

            my $depotpath = catdir('/', $depot, $path, $rel_uri);
            $depotpath = "/$depotpath" if !length($depot);
            return $self->arg_depotpath($depotpath);
	}
    }

    print loc("New URI encountered: %1\n", $uri);

    my $depots = join('|', map quotemeta, sort keys %$map);
    my ($base_uri, $rel_uri);

    {
        my $base = get_prompt(
            loc("Choose a base URI to mirror from (press enter to use the full URI): ", $uri),
            qr/^(?:[A-Za-z][-+.A-Za-z0-9]*:|$)/
        );
        if (!length($base)) {
            $base_uri = $uri;
            $rel_uri = '';
            last;
        }

        $base_uri = URI->new("$base/")->canonical;

        $rel_uri = $uri->rel($base_uri);
        next if $rel_uri->eq($uri);
        next if $rel_uri =~ /^\.\./;
        last;
    }

    my $path = get_prompt(
        loc("Name a depot path for this mirror (under //mirror/ if no leading '/'): "),
        qr{^(?:/(?:$depots)/)?[^/]},
    );
    $path = "//mirror/$path" unless $path =~ m!^/!;

    my $target = $self->arg_depotpath($path);
    $self->command ('mirror')->run ($target, $base_uri);

    print loc("Synchronizing the mirror for the first time:\n");
    print loc("  a        : Retrieve all revisions (default)\n");
    print loc("  h        : Only the most recent revision\n");
    print loc("  -count   : At most 'count' recent revisions\n");
    print loc("  revision : Start from the specified revision\n");

    my $answer = lc(get_prompt(
        loc("a)ll, h)ead, -count, revision? [a] "),
        qr(^[ah]?|^-?\d+$)
    ));
    $answer = 'a' unless length $answer;

    $self->command(
        sync => {
            skip_to => (
                ($answer eq 'a') ? undef :
                ($answer eq 'h') ? 'HEAD-1' :
                ($answer < 0)    ? "HEAD$answer" :
                                $answer
            ),
        }
    )->run ($target);

    my $depotpath = "$target->{depotpath}/$rel_uri";
    return $self->arg_depotpath($depotpath);
}

=head3 arg_co_maybe ($arg)

Argument might be a checkout path or a depotpath.

=cut

sub arg_co_maybe {
    my ($self, $arg) = @_;

    $arg = $self->arg_uri_maybe($arg)->{depotpath} if is_uri($arg);

    my $rev = $arg =~ s/\@(\d+)$// ? $1 : undef;
    my ($repospath, $path, $copath, $cinfo, $repos) =
	$self->{xd}->find_repos_from_co_maybe ($arg, 1);
    return SVK::Target->new
	( repos => $repos,
	  repospath => $repospath,
	  depotpath => $cinfo->{depotpath} || $arg,
	  copath => $copath,
	  report => $copath ? File::Spec->canonpath ($arg) : $arg,
	  path => $path,
	  revision => $rev,
	);
}

=head3 arg_copath ($arg)

Argument is a checkout path.

=cut

sub arg_copath {
    my ($self, $arg) = @_;
    my ($repospath, $path, $copath, $cinfo, $repos) = $self->{xd}->find_repos_from_co ($arg, 1);
    return SVK::Target->new
	( repos => $repos,
	  repospath => $repospath,
	  report => File::Spec->canonpath ($arg),
	  copath => $copath,
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

=head3 arg_depotroot ($arg)

Argument is a depot root, or a checkout path that needs to be resolved
into a depot root.

=cut

sub arg_depotroot {
    my ($self, $arg) = @_;

    local $@;
    $arg = eval { $self->arg_co_maybe ($arg || '')->new (path => '/') }
           || $self->arg_depotpath ("//");
    $arg->as_depotpath;

    return $arg;
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

=head3 parse_revlist ()

Parse -c or -r to a list of [from, to] pairs.

=cut

sub parse_revlist {
    my $self = shift;
    die loc("Revision required.\n") unless $self->{revspec} or $self->{chgspec};
    die loc("Can't assign --revision and --change at the same time.\n")
	if $self->{revspec} and $self->{chgspec};
    my ($fromrev, $torev);
    if ($self->{chgspec}) {
	my @revlist;
	for (split (',', $self->{chgspec})) {
	    if (($fromrev, $torev) = m/^(\d+)-(\d+)$/) {
		--$fromrev;
	    }
	    elsif (($torev) = m/^(\d+)$/) {
		$fromrev = $torev - 1;
	    }
	    else {
		die loc("Change spec %1 not recognized.\n", $_);
	    }
	    push @revlist , [$fromrev, $torev];
	}
	return @revlist;
    }

    # revspec
    if (($fromrev, $torev) = $self->{revspec} =~ m/^(\d+):(\d+)$/) {
	return ([$fromrev, $torev]);
    }
    else {
	die loc ("Revision spec must be N:M.\n");
    }
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
	     print $_[0]->expanded_message."\n".($msg ? "$msg\n" : '');
	 });
}

=head3 command ($cmd, \%args)

Construct a command object of the C<$cmd> subclass and return it.

The new object will share the C<xd> from the calling command object;
contents in C<%args> is also assigned into the new object.

=cut

sub command {
    my ($self, $command, $args, $is_rebless) = @_;

    $command = ucfirst(lc($command));
    require "SVK/Command/$command.pm";

    my $cmd = (
        $is_rebless ? bless($self, "SVK::Command::$command")
                    : "SVK::Command::$command"->new ($self->{xd})
    );
    $cmd->{$_} = $args->{$_} for sort keys %$args;

    return $cmd;
}

=head3 rebless ($cmd, \%args)

Like C<command> above, but modifies the calling object instead
of creating a new one.  Useful for a command object to recast
itself into another command class.

=cut

sub rebless {
    my ($self, $command, $args) = @_;
    return $self->command($command, $args, 1);
}

sub find_checkout_anchor {
    my ($self, $target, $track_merge, $track_sync) = @_;

    my $entry = $self->{xd}{checkout}->get ($target->{copath});
    my $anchor_target = $self->arg_depotpath ($entry->{depotpath});

    return ($anchor_target, undef) unless $track_merge;

    my @rel_path = split(
        '/',
        abs2rel ($target->{path}, $anchor_target->{path}, undef, '/')
    );

    my $copied_from;
    while (!$copied_from) {
        $copied_from = $anchor_target->copied_from ($track_sync);

        if ($copied_from) {
            return ($anchor_target, $copied_from);
            last;
        }
        elsif (@rel_path) {
            $anchor_target->descend (shift (@rel_path));
        }
        else {
            return ($self->arg_depotpath ($entry->{depotpath}), undef);
            last;
        }
    }
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
