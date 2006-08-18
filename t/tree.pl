#!/usr/bin/perl

my $pid = $$;

END {
    return unless $$ == $pid;
    rm_test($_) for @TOCLEAN;
}

use strict;
use SVK;
require Data::Hierarchy;
use File::Path;
use File::Temp;
use SVK::Util qw( dirname catdir tmpdir can_run abs_path $SEP $EOL IS_WIN32 HAS_SVN_MIRROR );
use Test::More;
require Storable;
use SVK::Path::Checkout;
use Clone;

# Fake standard input
our $answer = [];
our $show_prompt = 0;

BEGIN {
    no warnings 'redefine';
    # override get_prompt in XD so devel::cover is happy for
    # already-exported symbols being overridden
    *SVK::Util::get_prompt = *SVK::XD::get_prompt = sub {
	local $| = 1;
	print "$_[0]\n" if $show_prompt;
	print STDOUT "$_[0]\n" if $main::DEBUG;
	return $answer unless ref($answer); # compat
	die "expecting input" unless @$answer;
	my $ans = shift @$answer;
	print STDOUT "-> $answer->[0]\n" if $main::DEBUG;
	return $ans unless ref($ans);
	
	if (ref($ans->[0]) eq 'Regexp') {
	    Carp::cluck "prompt mismatch ($_[0]) vs ($ans->[0])" unless $_[0] =~ m/$ans->[0]/s;
	}
	else {
	    Carp::cluck "prompt mismatch ($_[0]) vs ($ans->[0])" if $_[0] ne $ans->[0];
	}
	return $ans->[1];
    } unless $ENV{DEBUG_INTERACTIVE};

    chdir catdir(abs_path(dirname(__FILE__)), '..' );
}

sub plan_svm {
    unless (HAS_SVN_MIRROR) {
	plan skip_all => "SVN::Mirror not installed";
	exit;
    };
    plan @_;
}

use Carp;
use SVK;
use SVK::XD;

our @TOCLEAN;
END {
    return unless $$ == $pid;
    $SIG{__WARN__} = sub { 1 };
    cleanup_test($_) for @TOCLEAN;
}

our $output = '';
our $copath;

for (qw/SVKRESOLVE SVKMERGE SVKDIFF SVKPGP SVKLOGOUTPUT LC_CTYPE LC_ALL LANG LC_MESSAGES/) {
    $ENV{$_} = '' if $ENV{$_};
}
$ENV{LANGUAGE} = $ENV{LANGUAGES} = 'i-default';

$ENV{SVKRESOLVE} = 's'; # default for test
$ENV{HOME} ||= (
    $ENV{HOMEDRIVE} ? catdir(@ENV{qw( HOMEDRIVE HOMEPATH )}) : ''
) || (getpwuid($<))[7];
$ENV{USER} ||= (
    (defined &Win32::LoginName) ? Win32::LoginName() : ''
) || $ENV{USERNAME} || (getpwuid($<))[0];

$ENV{SVNFSTYPE} ||= (($SVN::Core::VERSION =~ /^1\.0/) ? 'bdb' : 'fsfs');

# Make "prove -l" happy; abs_path() returns "undef" if the path 
# does not exist. This makes perl very unhappy.
@INC = grep defined, map abs_path($_), @INC;

if ($ENV{DEBUG}) {
    {
        package Tie::StdScalar::Tee;
        require Tie::Scalar;
        our @ISA = 'Tie::StdScalar';
        sub STORE { print STDOUT $_[1] ; ${$_[0]} = $_[1]; }
    }
    tie $output => 'Tie::StdScalar::Tee';
}

my $pool = SVN::Pool->new_default;

sub new_repos {
    my $repospath = catdir(tmpdir(), "svk-$$");
    my $reposbase = $repospath;
    my $repos;
    my $i = 0;
    while (-e $repospath) {
	$repospath = $reposbase . '-'. (++$i);
    }
    my $pool = SVN::Pool->new_default;
    $repos = SVN::Repos::create("$repospath", undef, undef, undef,
				{'fs-type' => $ENV{SVNFSTYPE}})
	or die "failed to create repository at $repospath";
    return $repospath;
}

sub build_test {
    my (@depot) = @_;

    my $depotmap = {map {$_ => (new_repos())[0]} '',@depot};
    my $xd = SVK::XD->new (depotmap => $depotmap,
			   svkpath => $depotmap->{''});
    my $svk = SVK->new (xd => $xd, $ENV{DEBUG_INTERACTIVE} ? () : (output => \$output));
    push @TOCLEAN, [$xd, $svk];
    return ($xd, $svk);
}

sub build_floating_test {
    my ($directory) = @_;

    my $svkpath = File::Spec->catfile($directory, '.svk');
    my $xd = SVK::XD->new (statefile => File::Spec->catfile($svkpath, 'config'),
			   svkpath => $svkpath,
			   floating => $directory);
    $xd->load;
    my $svk = SVK->new (xd => $xd, $ENV{DEBUG_INTERACTIVE} ? () : (output => \$output));
    push @TOCLEAN, [$xd, $svk];
    return ($xd, $svk);
}

sub get_copath {
    my ($name) = @_;
    my $copath = SVK::Path::Checkout->copath ('t', "checkout/$name");
    mkpath [$copath] unless -d $copath;
    rmtree [$copath] if -e $copath;
    return ($copath, File::Spec->rel2abs($copath));
}

sub rm_test {
    my ($xd, $svk) = @{+shift};
    for my $depot (sort keys %{$xd->{depotmap}}) {
	my $path = $xd->{depotmap}{$depot};
	die if $path eq '/';
	rmtree [$path];
    }
}

sub cleanup_test {
    my ($xd, $svk) = @{+shift};
    for my $depot (sort keys %{$xd->{depotmap}}) {
	my $pool = SVN::Pool->new_default;
	my (undef, undef, $repos) = eval { $xd->find_repos("/$depot/", 1) };
	diag "uncleaned txn on /$depot/"
	    if $repos && @{$repos->fs->list_transactions};
    }
    return unless $ENV{TEST_VERBOSE};
    use YAML::Syck;
    print Dump($xd);
    for my $depot (sort keys %{$xd->{depotmap}}) {
	my $pool = SVN::Pool->new_default;
	my (undef, undef, $repos) = $xd->find_repos ("/$depot/", 1);
	print "===> depot $depot (".$repos->fs->get_uuid."):\n";
	$svk->log ('-v', "/$depot/");
	print ${$svk->{output}};
    }
}

sub append_file {
    my ($file, $content) = @_;
    open my ($fh), '>>', $file or die "can't append $file: $!";
    print $fh $content;
    close $fh;
}

sub overwrite_file {
    my ($file, $content) = @_;
    open my ($fh), '>', $file or confess "Cannot overwrite $file: $!";
    print $fh $content;
    close $fh;
}

sub overwrite_file_raw {
    my ($file, $content) = @_;
    open my ($fh), '>:raw', $file or confess "Cannot overwrite $file: $!";
    print $fh $content;
    close $fh;
}

sub is_file_content {
    my ($file, $content, $test) = @_;
    open my ($fh), '<', $file or confess "Cannot read from $file: $!";
    my $actual_content = do { local $/; <$fh> };

    @_ = ($actual_content, $content, $test);
    goto &is;
}

sub is_file_content_raw {
    my ($file, $content, $test) = @_;
    open my ($fh), '<:raw', $file or confess "Cannot read from $file: $!";
    local $/;
    @_ = (<$fh>, $content, $test);
    goto &is;
}

sub _do_run {
    my ($svk, $cmd, $arg) = @_;
    my $unlock = SVK::XD->can('unlock');
    my $giant_unlock = SVK::XD->can('giant_unlock');
    no warnings 'redefine';
    my $origxd = Storable::dclone($svk->{xd}->{checkout});
    require SVK::Command::Checkout;
    my $giant_locked = 1;
    local *SVK::XD::giant_unlock = sub {
	$giant_locked = 0;
	goto $giant_unlock;
    };
    local *SVK::XD::unlock = sub {
	my $self = shift;
	unless ($giant_locked) {
	    my $newxd = Storable::dclone($self->{checkout});
	    my @paths = $self->{checkout}->find ('', {lock => $$});
	    my %empty = (lock => undef, '.conflict' => undef,
			 '.deleted' => undef,
			  SVK::Command::Checkout::detach->_remove_entry,
			  SVK::Command->_schedule_empty);
	    for (@paths) {
		$origxd->store($_, \%empty, {override_sticky_descendents => 1});
		$newxd-> store($_, \%empty, {override_sticky_descendents => 1});
	    }
	    diag Carp::longmess.YAML::Syck::Dump({orig => $origxd, new => $newxd, paths => \@paths})
		unless eq_hash($origxd, $newxd);
	}
	$unlock->($self, @_);
    };
    $svk->$cmd (@$arg);
}

sub is_output {
    my ($svk, $cmd, $arg, $expected, $test) = @_;
    _do_run($svk, $cmd, $arg);
    my $cmp = (grep {ref ($_) eq 'Regexp'} @$expected)
	? \&is_deeply_like : \&is_deeply;
    my $o = $output;
    $o =~ s/\r?\n$//;
    @_ = ([split (/\r?\n/, $o, -1)], $expected, $test || join(' ', map { / / ? qq("$_") : $_ } $cmd, @$arg));
    goto &$cmp;
}

sub is_sorted_output {
    my ($svk, $cmd, $arg, $expected, $test) = @_;
    _do_run($svk, $cmd, $arg);
    my $cmp = (grep {ref ($_) eq 'Regexp'} @$expected)
	? \&is_deeply_like : \&is_deeply;
    @_ = ([sort split (/\r?\n/, $output)], [sort @$expected], $test || join(' ', $cmd, @$arg));
    goto &$cmp;
}

sub is_deeply_like {
    my ($got, $expected, $test) = @_;
    for (0..$#{$expected}) {
	if (ref ($expected->[$_]) eq 'SCALAR' ) {
	    @_ = ($#{$got}, $#{$got}, $test);
	    goto &is;
	}
	elsif (ref ($expected->[$_]) eq 'Regexp' ) {
	    unless ($got->[$_] =~ m/$expected->[$_]/) {
		diag "Different at $_:\n$got->[$_]\n$expected->[$_]";
		@_ = (0, $test);
		goto &ok;
	    }
	}
	else {
	    if ($got->[$_] ne $expected->[$_]) {
		diag "Different at $_:\n$got->[$_]\n$expected->[$_]";
		@_ = (0, $test);
		goto &ok;
	    }
	}
    }
    @_ = ($#{$expected}, $#{$got}, $test);
    goto &is;
}

sub is_output_like {
    my ($svk, $cmd, $arg, $expected, $test) = @_;
    _do_run($svk, $cmd, $arg);
    @_ = ($output, $expected, $test || join(' ', $cmd, @$arg));
    goto &like;
}

sub is_output_unlike {
    my ($svk, $cmd, $arg, $expected, $test) = @_;
    _do_run($svk, $cmd, $arg);
    @_ = ($output, $expected, $test || join(' ', $cmd, @$arg));
    goto &unlike;
}

sub is_ancestor {
    my ($svk, $path, @expected) = @_;
    $svk->info ($path);
    my (@copied) = $output =~ m/Copied From: (.*?), Rev. (\d+)/mg;
    @_ = (\@copied, \@expected);
    goto &is_deeply;
}

sub copath {
    SVK::Path::Checkout->copath ($copath, @_);
}

sub status_native {
    my $copath = shift;
    my @ret;
    while (my ($status, $path) = splice (@_, 0, 2)) {
	push @ret, join (' ', $status, $copath ? copath ($path) :
			 File::Spec->catfile (File::Spec::Unix->splitdir ($path)));
    }
    return @ret;
}

sub status {
    my @ret;
    while (my ($status, $path) = splice (@_, 0, 2)) {
	push @ret, join (' ', $status, $path);
    }
    return @ret;
}

require SVN::Simple::Edit;

sub get_editor {
    my ($repospath, $path, $repos) = @_;

    return SVN::Simple::Edit->new
	(_editor => [SVN::Repos::get_commit_editor($repos,
						   "file://$repospath",
						   $path,
						   'svk', 'test init tree',
						   sub {})],
	 base_path => $path,
	 root => $repos->fs->revision_root ($repos->fs->youngest_rev),
	 missing_handler => SVN::Simple::Edit::check_missing ());
}

sub create_basic_tree {
    my ($xd, $depot) = @_;
    my $pool = SVN::Pool->new_default;
    my ($repospath, $path, $repos) = $xd->find_repos ($depot, 1);

    local $/ = $EOL;
    my $edit = get_editor ($repospath, $path, $repos);
    $edit->open_root ();

    $edit->modify_file ($edit->add_file ('/me'),
			"first line in me$/2nd line in me$/");
    $edit->modify_file ($edit->add_file ('/A/be'),
			"\$Rev\$ \$Revision\$$/\$FileRev\$$/first line in be$/2nd line in be$/");
    $edit->change_file_prop ('/A/be', 'svn:keywords', 'Rev URL Revision FileRev');
    $edit->modify_file ($edit->add_file ('/A/P/pe'),
			"first line in pe$/2nd line in pe$/");
    $edit->add_directory ('/B');
    $edit->add_directory ('/C');
    $edit->add_directory ('/A/Q');
    $edit->change_dir_prop ('/A/Q', 'foo', 'prop on A/Q');
    $edit->modify_file ($edit->add_file ('/A/Q/qu'),
			"first line in qu$/2nd line in qu$/");
    $edit->modify_file ($edit->add_file ('/A/Q/qz'),
			"first line in qz$/2nd line in qz$/");
    $edit->add_directory ('/C/R');
    $edit->close_edit ();
    my $tree = { child => { me => {},
			    A => { child => { be => {},
					      P => { child => {pe => {},
							      }},
					      Q => { child => {qu => {},
							       ez => {},
							      }},
					    }},
			    B => {},
			    C => { child => { R => { child => {}}}}
			  }};
    my $rev = $repos->fs->youngest_rev;
    $edit = get_editor ($repospath, $path, $repos);
    $edit->open_root ();
    $edit->modify_file ('/me', "first line in me$/2nd line in me - mod$/");
    $edit->modify_file ($edit->add_file ('/B/fe'),
			"file fe added later$/");
    $edit->delete_entry ('/A/P');
    $edit->copy_directory('/B/S', "file://${repospath}/${path}/A", $rev);
    $edit->modify_file ($edit->add_file ('/D/de'),
			"file de added later$/");
    $edit->close_edit ();

    $tree->{child}{B}{child}{fe} = {};
    # XXX: have to clone this...
    %{$tree->{child}{B}{child}{S}} = (child => {%{$tree->{child}{A}{child}}},
				      history => '/A:1');
    delete $tree->{child}{A}{child}{P};
    $tree->{child}{D}{child}{de} = {};

    return $tree;
}

sub waste_rev {
    my ($svk, $path) = @_;
    $svk->mkdir('-m', 'create', $path);
    $svk->rm('-m', 'create', $path);
}

sub tree_from_fsroot {
    # generate a hash describing a given fs root
}

sub tree_from_xdroot {
    # generate a hash describing the content in an xdroot
}

sub __ ($) {
    my $path = shift;
    $path =~ s{/}{$SEP}go;
    return $path;
}

sub _x { IS_WIN32 ? 1 : -x $_[0] }
sub not_x { IS_WIN32 ? 1 : not -x $_[0] }
sub _l { IS_WIN32 ? 1 : -l $_[0] }
sub not_l { IS_WIN32 ? 1 : not -l $_[0] }

sub uri {
    my $file = shift;
    $file =~ s{^|\\}{/}g if IS_WIN32;
    return "file://$file";
}

my @unlink;
sub set_editor {
    my $tmp = File::Temp->new( SUFFIX => '.pl', UNLINK => 0 );
    print $tmp $_[0];
    $tmp->close;

    my $perl = can_run($^X);
    my $tmpfile = $tmp->filename;

    if (defined &Win32::GetShortPathName) {
	$perl = Win32::GetShortPathName($perl);
	$tmpfile = Win32::GetShortPathName($tmpfile);
    }

    chmod 0755, $tmpfile;
    push @unlink, $tmpfile;

    $ENV{SVN_EDITOR} = "$perl $tmpfile";
}

sub replace_file {
    my ($file, $from, $to) = @_;
    my @content;

    open my $fh, '<', $file or croak "Cannot open $file: $!";
    while (<$fh>) {
        s/$from/$to/g;
        push @content, $_;
    }
    close $fh;

    open $fh, '>', $file or croak "Cannot open $file: $!";
    print $fh @content;
    close $fh;
}

# Samples of files with various MIME types
{
my %samples = (
    'empty.txt'     => q{},
    'false.bin'     => 'LZ  Not application/octet-stream',
    'foo.pl'        => "#!/usr/bin/perl\n",
    'foo.jpg'       => "\xff\xd8\xff\xe0\x00this is jpeg",
    'foo.bin'       => "\x1f\xf0\xff\x01\x00\xffthis is binary",
    'foo.html'      => "<html>",
    'foo.txt'       => "test....",
    'foo.c'         => "/*\tHello World\t*/",
    'not-audio.txt' => "if\n",  # reported: alley_cat 2006-06-02
);

# Return the names of mime sample files relative to a particular directory
sub glob_mime_samples {
    my ($directory) = @_;
    my @names;
    push @names, "$directory/$_" for sort keys %samples;
    return @names;
}

# Create a directory and fill it with files of different MIME types.
# The directory must be specified as the first argument.
sub create_mime_samples {
    my ($directory) = @_;

    mkdir $directory;
    overwrite_file ("mime/not-audio.txt", "if\n"); # reported: alley_cat 2006-06-02
    while ( my ($basename, $content) = each %samples ) {
        overwrite_file( "$directory/$basename", $content );
    }
}
}

sub chmod_probably_useless {
    return $^O eq 'MSWin32' || Cwd::cwd() =~ m!^/afs/!;
}

END {
    return unless $$ == $pid;
    unlink $_ for @unlink;
}

1;
