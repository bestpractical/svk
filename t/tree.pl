#!/usr/bin/perl
END {
    rm_test($_) for @TOCLEAN;
}

require Data::Hierarchy;
require SVN::Core;
require SVN::Repos;
require SVN::Fs;
use File::Path;
use SVK;
use SVK::XD;
use strict;

our @TOCLEAN;
END {
    cleanup_test($_) for @TOCLEAN;
}


our $output = '';
#select IO::Scalar->new (\$output);

my $pool = SVN::Pool->new_default;

sub new_repos {
    my $repospath = "/tmp/svk-$$";
    my $reposbase = $repospath;
    my $repos;
    my $i = 0;
    while (-e $repospath) {
	$repospath = $reposbase . '-'. (++$i);
    }
    $repos = SVN::Repos::create("$repospath", undef, undef, undef, undef)
	or die "failed to create repository at $repospath";
    return $repospath;
}

sub build_test {
    my (@depot) = @_;

    my $depotmap = {map {$_ => (new_repos())[0]} '',@depot};
    my $xd = SVK::XD->new (depotmap => $depotmap,
			   checkout => Data::Hierarchy->new);
    my $svk = SVK->new (xd => $xd, output => \$output);
    push @TOCLEAN, [$xd, $svk];
    return ($xd, $svk);
}

sub get_copath {
    my ($name) = @_;
    my $copath = "t/checkout/$name";
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
    return unless $ENV{TEST_VERBOSE};
    my ($xd, $svk) = @{+shift};
    use YAML;
    print Dump($xd);
    for my $depot (sort keys %{$xd->{depotmap}}) {
	my $path = $xd->{depotmap}{$depot};
	print "===> depot $depot:\n";
	undef $svk->{output};
	$svk->log ('-v', "/$depot/");
    }
}

sub append_file {
    my ($file, $content) = @_;
    open my ($fh), '>>', $file or die $!;
    print $fh $content;
    close $fh;
}

sub overwrite_file {
    my ($file, $content) = @_;
    open my ($fh), '>', $file or die $!;
    print $fh $content;
    close $fh;
}

sub is_file_content {
    my ($file, $content, $test) = @_;
    open my ($fh), '<', $file or die $!;
    local $/;
    is (<$fh>, $content, $test);
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

    my $edit = get_editor ($repospath, $path, $repos);
    $edit->open_root ();
    $edit->modify_file ($edit->add_file ('/me'),
			"first line in me\n2nd line in me\n");
    $edit->modify_file ($edit->add_file ('/A/be'),
			"\$Rev\$ \$Rev\$\nfirst line in be\n2nd line in be\n");
    $edit->change_file_prop ('/A/be', 'svn:keywords', 'Rev URL');
    $edit->modify_file ($edit->add_file ('/A/P/pe'),
			"first line in pe\n2nd line in pe\n");
    $edit->add_directory ('/B');
    $edit->add_directory ('/C');
    $edit->add_directory ('/A/Q');
    $edit->modify_file ($edit->add_file ('/A/Q/qu'),
			"first line in qu\n2nd line in qu\n");
    $edit->add_directory ('/C/R');
    $edit->close_edit ();
    my $tree = { child => { me => {},
			    A => { child => { be => {},
					      P => { child => {pe => {},
							      }},
					      Q => { child => {}},
					    }},
			    B => {},
			    C => { child => { R => { child => {}}}}
			  }};
    my $rev = $repos->fs->youngest_rev;
    $edit = get_editor ($repospath, $path, $repos);
    $edit->open_root ();
    $edit->modify_file ('/me', "first line in me\n2nd line in me - mod\n");
    $edit->modify_file ($edit->add_file ('/B/fe'),
			"file fe added later\n");
    $edit->delete_entry ('/A/P');
    $edit->copy_directory('/B/S', "file://${repospath}/${path}/A", $rev);
    $edit->modify_file ($edit->add_file ('/D/de'),
			"file de added later\n");
    $edit->close_edit ();

    $tree->{child}{B}{child}{fe} = {};
    # XXX: have to clone this...
    %{$tree->{child}{B}{child}{S}} = (child => {%{$tree->{child}{A}{child}}},
				      history => '/A:1');
    delete $tree->{child}{A}{child}{P};
    $tree->{child}{D}{child}{de} = {};

    return $tree;
}


sub tree_from_fsroot {
    # generate a hash describing a given fs root
}

sub tree_from_xdroot {
    # generate a hash describing the content in an xdroot
}

1;
