package SVK::Command;
use strict;
our $VERSION = '0.09';
use Getopt::Long qw(:config no_ignore_case);
# XXX: Pod::Simple isn't happy with SVN::Simple::Edit, so load it first
use SVN::Simple::Edit;
use Pod::Simple::SimpleTree ();
use Pod::Text ();
use File::Find ();
use Cwd;

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
		sm smerge
		sy sync
		desc describe
		st status
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
    return map {$_ => \$self->{$opt{$_}}}keys %opt;
}

sub _cmd_map {
    my ($cmd) = @_;
    $cmd = $alias{$cmd} if exists $alias{$cmd};
    $cmd =~ s/^(.)/\U$1/;
    return $cmd;
}

sub get_cmd {
    my ($pkg, $cmd) = @_;
    $pkg = join('::', $pkg, _cmd_map ($cmd));
    unless (eval "require $pkg; 1" && UNIVERSAL::can($pkg, 'run')) {
	warn $@ if $@;
	return "Command not recognized, try $0 help.\n";
    }
    $pkg->new;
}

sub help {
    my ($pkg, $cmd) = @_;
    unless ($cmd) {
	my @cmd;
	my $dir = $INC{'SVK/Command.pm'};
	$dir =~ s/\.pm$//;
	print "Available commands:\n";
	File::Find::find (sub {
			      push @cmd, $File::Find::name if m/\.pm$/;
			  }, $dir);
	$pkg->brief_usage ($_) for sort @cmd;
	return;
    }
    get_cmd ($pkg, $cmd)->usage(1);
}

sub invoke {
    my $pkg = shift;
    my $xd = shift;
    my $cmd = shift;
    local @ARGV = @_;

    $cmd = get_cmd ($pkg, $cmd);
    $cmd->{xd} = $xd;
    die unless GetOptions ($cmd, _opt_map($cmd, $cmd->options));
    my @args = $cmd->parse_arg(@ARGV);
    $cmd->lock (@args);
    my $ret = $cmd->run (@args);
    $xd->unlock ();
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
            print "\t". $rows[0]->[2]."\n";
            last;
        }
    }
}

sub usage {
    my ($self, $detail) = @_;
    my $parser = new Pod::Text->new ();
    # XXX: the order from selected is not preserved.
    my $fname = ref($self);
    $fname =~ s|::|/|g;
    $parser->select ( $detail ? 'NAME|SYNOPSIS|OPTIONS|DESCRIPTION' : 'SYNOPSIS|OPTIONS');
    $parser->parse_from_file ($INC{"$fname.pm"});
    exit 0;
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
    my ($report, $copath, @targets )= main::condense (@arg);

    my ($repospath, $path, $cinfo, $repos) = main::find_repos_from_co ($copath, 1);
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
	main::find_repos_from_co_maybe ($arg, 1);
    return { repos => $repos,
	     repospath => $repospath,
	     depotpath => $cinfo->{depotpath} || $arg,
	     copath => $copath,
	     path => $path,
	   };
}

sub arg_copath {
    my ($self, $arg) = @_;

    my ($repospath, $path, $cinfo, $repos) = main::find_repos_from_co ($arg, 1);
    return { repos => $repos,
	     repospath => $repospath,
	     copath => Cwd::abs_path ($arg),
	     path => $path,
	     cinfo => $cinfo,
	     depotpath => $cinfo->{depotpath},
	   };
}

sub arg_depotpath {
    my ($self, $arg) = @_;

    my ($repospath, $path, $repos) = main::find_repos ($arg, 1);

    return { repos => $repos,
	     repospath => $repospath,
	     path => $path,
	     depotpath => $arg,
	   };
}

sub arg_depotname {
    my ($self, $arg) = @_;

    return main::find_depotname ($arg, 1);
}

sub arg_path {
    my ($self, $arg) = @_;

    return Cwd::abs_path ($arg);
}

1;

