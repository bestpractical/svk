package SVK::Command;
use strict;
our $VERSION = '0.09';
use Getopt::Long qw(:config no_ignore_case);
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

sub options {}

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

sub help {
}

sub invoke {
    my $pkg = shift;
    my $info = shift;
    my $cmd = shift;
    local @ARGV = @_;

    $cmd = _cmd_map ($cmd) or return;
    $pkg = join('::', $pkg, $cmd);
    unless (eval "require $pkg; 1" && UNIVERSAL::can($pkg, 'run')) {
	warn $@ if $@;
	return "command not recognized, try $0 help\n";
    }

    $cmd = $pkg->new;
    $cmd->{info} = $info;
    die unless GetOptions ($cmd, _opt_map($cmd, $cmd->options));
    $cmd->run ($cmd->parse_arg(@ARGV));
}

sub arg_condensed {
    my ($self, @arg) = @_;
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

    my ($repospath, $path, $copath, undef, $repos) = 
	main::find_repos_from_co_maybe ($arg, 1);
    return { repos => $repos,
	     repospath => $repospath,
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

sub arg_path {
    my ($self, $arg) = @_;

    return Cwd::abs_path ($arg);
}

1;

