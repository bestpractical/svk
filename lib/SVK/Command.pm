package SVK::Command;
use strict;
our $VERSION = '0.09';
use Getopt::Long qw(:config no_ignore_case);
# XXX: Pod::Simple isn't happy with SVN::Simple::Edit, so load it first
use SVN::Simple::Edit;
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
    my ($class) = @_;
    bless {}, $class;
}

sub options { () }

sub parse_arg {}

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
    my ($pkg, $cmd) = @_;
    $pkg = join('::', 'SVK::Command', _cmd_map ($cmd));
    unless (eval "require $pkg; 1" && UNIVERSAL::can($pkg, 'run')) {
	$pkg =~ s|::|/|g;
	warn $@ if $@ && exists $INC{"$pkg.pm"};
	print "Command not recognized, try $0 help.\n";
	exit 0;
    }
    $pkg->new;
}

sub invoke {
    my ($pkg, $xd, $cmd, $output, @arg) = @_;
    my $ofh;
    local @ARGV = @arg;

    $cmd = get_cmd ($pkg, $cmd);
    $cmd->{xd} = $xd;
    die unless GetOptions ($cmd, _opt_map($cmd, $cmd->options));
    my @args = $cmd->parse_arg(@ARGV);
    $cmd->lock (@args);
    $ofh = select $output if $output;
    my $ret = eval { $cmd->run (@args) };
    select $ofh if $output;
    $xd->unlock () if $xd;
    die $@ if $@;
    return $ret;
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
    $self->usage if $#arg < 0;
    my ($report, $copath, @targets )= $self->{xd}->condense (@arg);

    my ($repospath, $path, $cinfo, $repos) = $self->{xd}->find_repos_from_co ($copath, 1);
    return { repos => $repos,
	     repospath => $repospath,
	     copath => $copath,
	     path => $path,
	     report => $report,
	     targets => @targets ? \@targets : undef,
	   };
}

sub arg_co_maybe {
    my ($self, $arg) = @_;

    my ($repospath, $path, $copath, $cinfo, $repos) =
	$self->{xd}->find_repos_from_co_maybe ($arg, 1);
    return { repos => $repos,
	     repospath => $repospath,
	     depotpath => $cinfo->{depotpath} || $arg,
	     copath => $copath,
	     report => $arg,
	     path => $path,
	   };
}

sub arg_copath {
    my ($self, $arg) = @_;

    my ($repospath, $path, $cinfo, $repos) = $self->{xd}->find_repos_from_co ($arg, 1);
    return { repos => $repos,
	     repospath => $repospath,
	     report => $arg,
	     copath => Cwd::abs_path ($arg),
	     path => $path,
	     cinfo => $cinfo,
	     depotpath => $cinfo->{depotpath},
	   };
}

sub arg_depotpath {
    my ($self, $arg) = @_;

    my ($repospath, $path, $repos) = $self->{xd}->find_repos ($arg, 1);

    return { repos => $repos,
	     repospath => $repospath,
	     path => $path,
	     depotpath => $arg,
	   };
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

__END__
our $AUTOLOAD;

use Sub::WrapPackages (
        subs     => [qw(SVN::Delta::Editor::AUTOLOAD)],
        pre      => sub {
	    warn "my autoload is $AUTOLOAD ".caller(4);
            warn "$SVN::Delta::Editor::AUTOLOAD called with params ".
              join(', ', @_[1..$#_])."\n";
        },
        post     => sub {
            warn "$_[0] returned $_[1]\n";
        });

=comment

# workaround the svn::delta::editor problem in 1.0.x
my $ref = \&SVN::Delta::Editor::AUTOLOAD;
*SVN::Delta::Editor::AUTOLOAD =
    sub { my $ret = $ref-> (@_);
	  warn $SVN::Delta::Editor::AUTOLOAD;
	  $ret = undef if ref ($ret) eq 'ARRAY' && $#{$ret} == -1;
	  return $ret;
      };

=cut

1;
