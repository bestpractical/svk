#!/usr/bin/perl
package svk;
require 'bin/svk';

package main;
require Data::Hierarchy;
require SVN::Core;
require SVN::Repos;
use strict;

require IO::Scalar;

my $output = '';
#select IO::Scalar->new (\$output);

sub new_repos {
    my $repospath = "/tmp/svn-$$";
    my $reposbase = $repospath;
    my $repos;
    my $i = 0;
    while (-e $repospath) {
	$repospath = $reposbase . '-'. (++$i);
    }
    $repos = SVN::Repos::create("$repospath", undef, undef, undef, undef)
	or die "failed to create repository at $repospath";
    return ($repospath, $repos);
}

sub build_test {
    my (@depot) = @_;

    my $depotmap = {map {$_ => (new_repos())[0]} '',@depot};
    return {depotmap => $depotmap,
	    checkout => Data::Hierarchy->new};
}

sub get_copath {
    my ($name) = @_;
    my $copath = "t/checkout/$name";
    `mkdir -p $copath` unless -d $copath;
    `rm -rf $copath` if -e $copath;
    return ($copath, File::Spec->rel2abs($copath));
}

sub cleanup_test {
    my $info = shift;
    use YAML;
    print Dump($info) if $ENV{TEST_VERBOSE};
    for (values %{$info->{depotmap}}) {
	die if $_ eq '/';
	print `svn log -v file://$_`
	    if $ENV{TEST_VERBOSE};
#	diag "removing $_";
	`rm -rf $_`;
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
    my ($depot) = @_;
    my $pool = SVN::Pool->new_default;
    my ($repospath, $path, $repos) = svk::find_repos ($depot, 1);
    my $edit = get_editor ($repospath, $path, $repos);
    $edit->open_root ();
    $edit->modify_file ($edit->add_file ('/me'),
			"first line in me\n2nd line in me\n");
    $edit->modify_file ($edit->add_file ('/A/be'),
			"first line in be\n2nd line in be\n");
    $edit->modify_file ($edit->add_file ('/A/P/pe'),
			"first line in pe\n2nd line in pe\n");
    $edit->add_directory ('/B');
    $edit->add_directory ('/C');
    $edit->add_directory ('/A/Q');
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
    $edit = get_editor ($repospath, $path, $repos);
    $edit->open_root ();
    $edit->modify_file ('/me', "first line in me\n2nd line in me - mod\n");
    $edit->modify_file ($edit->add_file ('/B/fe'),
			"file fe added later\n");
    $edit->delete_entry ('/A/P');
    $edit->copy_directory('/B/S', "file://${repospath}A", 1);
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
