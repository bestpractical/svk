#!perl

use strict;
use warnings;
use Cwd 'abs_path';

use File::Spec;



=head1 NAME

buildsvk.pl - packaging svk

=head1 SYNOPSIS

  buildsvk.pl    # build svk from src/SVK-version.tar.gz dist file
  buildsvk.pl .. # build svk from the toplevel tree of current checkout


=head1 DESCRIPTION

Put the CPAN dist files under src and C<buildsvk.pl> will create a build tarball
which bundles the svn libraries.  To use, just untar and symlink C<svk> under it
to a bin path.  There will also be a maketest script for you to run the included
tests.

If you are on win32, This will build a bundled installer for you including svn
libraries and all necessary perl core modules.  you need the strawberry-perl.zip
and svn-win*{,_pl}.zip under current directory before you run buildsvk.pl.
strawberry-perl.zip can be obtained by zipping the freshly installed
strawberry-perl for the moment.  You will also need NSIS installed under
$PATH or C:\program files\nsis.  You also need the unzip.exe binary in your path
(FIXME: just use our extract method)

=head1 TODO

=over 4

=item *

README file in the build.

=item *

cleanup win32 build code to be more like unix build.

=back


=cut

my $build = SVK::Build->new;
my $t = time();

$build->prepare_perl();
$build->prepare_svn_core();

$build->build_module('libwin32') if $^O eq 'MSWin32';

$build->build_module($_) for qw(Scalar-List-Utils Class-Autouse version Sub-Uplevel Test-Simple Test-Exception Data-Hierarchy PerlIO-via-dynamic PerlIO-via-symlink SVN-Simple PerlIO-eol Algorithm-Diff Algorithm-Annotate Pod-Escapes Pod-Simple IO-Digest TimeDate Getopt-Long Encode PathTools YAML-Syck Locale-Maketext-Simple App-CLI List-MoreUtils Path-Class Class-Data-Inheritable Class-Accessor UNIVERSAL-require File-Temp Log-Log4perl Time-Progress);
$build->build_module($_) for qw(Locale-Maketext-Lexicon TermReadKey IO-Pager);
$build->build_module($_) for qw(File-chdir SVN-Mirror);
$build->build_module($_) for qw(FreezeThaw);
$build->build_module($_) for qw(PerlIO-via-Bzip2 Compress-Bzip2 PerlIO-gzip SVN-Dump);

my $svkroot = shift;
if ($svkroot) {
    $build->perlmake_install($svkroot);
}
else {
    $build->build_module('SVK');
    ($svkroot) = glob($build->build_dir.'/SVK-*');
}

$build->prepare_dist($svkroot);

warn 'build finished - '.(time() - $t);

exit 0;

package SVK::Build;
use Archive::Extract;
use Archive::Tar;
use Env::Path;
use File::Path (qw(mkpath rmtree));
use File::chdir;
use File::Copy 'copy';
use File::Temp 'tempdir';

our $BUILD_BASE;

sub prepare_perl { 1 };
sub prepare_svn_core {
    my $self = shift;
    my $output = `ldd \`which svn\``;
    for ($output =~ m/^.*$/mg) {
	my ($lib, $file) = m/(\S.*?) => (\S.*?)\s/ or next;
	if ($lib =~ m/libsvn_*/) {
	warn "$lib $file";
	    copy($file, $self->build_dir);
	}
    }
    $self->prepare_svn_perl_binding();
}
sub prepare_svn_perl_binding {
    my $self = shift;
    my $output = `ldd \`locate -l 1 _Core.so\``;
    for ($output =~ m/^.*$/mg) {
	my ($lib, $file) = m/(\S.*?) => (\S.*?)\s/ or next;
	if ($lib =~ m/libsvn_swig*/ || $lib =~ m/libapr*/) {
	warn "$lib $file";
	    copy($file, $self->build_dir);
	}
    }
    my @SVNCoreModules = ( 'Base', 'Client', 'Core',
	'Delta', 'Fs', 'Ra', 'Repos', 'Wc');
    for my $prefix (@INC) {
	for my $SVNdir ("/SVN/","/auto/SVN/") {
	    my $fullpath = $prefix.$SVNdir;
	    if (-d $fullpath) {
		mkpath [$self->perldest.$SVNdir];
		for my $module (@SVNCoreModules) {
		    my $file = $module.".pm";
		    if (-f $fullpath.$file) {
			warn $file;
			copy($fullpath.$file, $self->perldest.$SVNdir);
		    }
		    if (-d $fullpath.'_'.$module) {
			mkpath [$self->perldest.$SVNdir.'_'.$module];
			for my $ext (".bs", ".so") {
			    my $file = $fullpath.'_'.$module.'/_'.$module.$ext;
			    if (-f $file) {
				warn $file;
				copy($file, $self->perldest.$SVNdir.'_'.$module);
			    }
			}
		    }
		}
	    }
	}
    }
}

sub build_dir {
    shift->build_base ."/dest";
}

sub build_base {
    $BUILD_BASE ||= tempdir(); 
}

sub prepare_build_dir {
    my $self = shift;
    mkpath [$self->build_dir];
}

sub new {
    my $class = shift;
    if ($^O eq 'MSWin32') {
	$class .= '::Win32';
    } elsif ($^O eq 'darwin') {
        $class .= "::Darwin";
    }

    my $self = bless {}, $class;
    $self->prepare_build_dir;
    return $self;
}


sub extract {
    my $self = shift;
    my ($arc, $to) = @_;
    my $ae = Archive::Extract->new( archive => $arc );

    $ae->extract( to => $to || $self->build_base )
	or die $ae->error;
}

sub perl { [ $^X, '-I'.$_[0]->perldest ] }
sub make { 'make' }

sub build_module {
    my $self = shift;
    my $module = shift;
    my $subdir = shift;
    # XXX: try to match version number only for the glob here
    my ($dir) = glob($self->build_dir."/$module-*");
    rmtree [$dir] if $dir;

    my ($file) = glob("src/$module-*") or die $module;
    $self->extract($file);

    ($dir) = glob($self->build_base."/$module-*");

    $self->perlmake_install( $subdir ? "$dir/$subdir" : $dir );
}

sub perlmake_install {
    my ($self, $dir) = @_;
    my $PERLDEST = $self->perldest;
    my $PERLDESTARCH = $PERLDEST;

    local $CWD = $dir;
    warn "$CWD\n";
    system @{$self->perl}, qw(Makefile.PL INSTALLDIRS=perl),
	    "INSTALLARCHLIB=$PERLDESTARCH",
	    "INSTALLPRIVLIB=$PERLDEST",
	    "INSTALLBIN=$PERLDEST/../bin",
      	    "INSTALLSCRIPT=$PERLDEST/../bin",
	    "INSTALLMAN1DIR=$PERLDEST/../man/man1",
	    "INSTALLMAN3DIR=$PERLDEST/../man/man3";

    $ENV{PERL_EXTUTILS_AUTOINSTALL} = '--skipdeps';
    system $self->make, qw( all install ) ;
}

sub perldest {
    my $self = shift;
    $self->build_dir.'/perl';
}

sub test_files {
    my $self = shift;
    my $toplevel = shift;
    my @tests;

    open my $fh, "$toplevel/MANIFEST" or die "Could not create $toplevel/MANIFEST: ".$!;
    while (<$fh>) {
	chomp;
	next unless m{^t/};
        push @tests, $_;
    }
    return @tests;
}

sub prepare_dist {
    my $self = shift;
    my $toplevel = shift;
    copy('svk-wrapper' => $self->build_dir."/svk");
    chmod 0755, $self->build_dir."/svk";


    for my $file ($self->test_files($toplevel)) {
	my (undef, $dir, undef) = File::Spec->splitpath($file);
	mkpath [ $self->build_dir."/$dir" ];
	copy($toplevel.'/'.$file => $self->build_dir."/$file");
    }
    
    copy('maketest' => $self->build_dir."/maketest");
    chmod 0755, $self->build_dir."/maketest";

    my $version = $self->get_svk_version($toplevel);

    rename($self->build_dir => $self->build_base.'/svk-'.$version);

    $self->build_archive( 'svk-'.$version);


}

sub get_svk_version {
    my ($self, $toplevel) = @_;
    my $version = eval {
	local @INC = @INC; unshift @INC, "$toplevel/lib"; require SVK::Version;
	SVK->VERSION;
    };

}

sub build_archive {
    my $self = shift;
    my $path = shift;
    my $olddir = $CWD;
    {
	local $CWD = $self->build_base;
	warn "In ".$self->build_base . " looking for ". $path;
	my @cmd = ( 'tar', 'czvf' , "$olddir/$path.tgz", $path);
	system( @cmd);
	if ($!) { die "Failed to create tarball: ". $! .  join (' ',@cmd);}
    }
    if (-f "$path.tgz" ) {

        print "Congratulations! You have a new build of $path in ".$olddir."/".$path.".tgz\n";
    } else { 
        warn "Couldn't build ".$self->build_base."/$path into a tarball\n";
    }
}

package SVK::Build::Win32;
use base 'SVK::Build';
use Cwd 'abs_path';
use File::Path (qw(rmtree));
use File::Spec;
use File::Copy 'move';

use constant svn_version => '1.5.0';

sub build_dir {
    'c:/tmp/svk-build';
}

sub build_base {
    'c:/tmp/svk-build';
}

sub perl {
    my $self = shift;
    [abs_path(File::Spec->catfile($self->build_dir,
				  qw(strawberry-perl perl bin perl.exe))) ];
}

sub make { 'dmake' }

sub perlmake_install {
    my $self = shift;
    local %ENV = %ENV;
    Env::Path->PATH->Assign( map { abs_path(File::Spec->catfile($self->build_dir, 'strawberry-perl', $_, 'bin')) } qw(perl c));
    return $self->SUPER::perlmake_install(@_);
}

sub perldest {
    File::Spec->catdir(abs_path($_[0]->build_dir), qw(strawberry-perl perl lib));
}

sub prepare_perl {
    my $self = shift;

    if (-d $self->perldest) {
	warn "found strawberry perl, remove ".$self->perldest." for clean build.\n";
	return 1;
    }
    mkdir('strawberry-perl');
    $self->extract('strawberry-perl.zip' => $self->build_dir.'/strawberry-perl');
}

sub prepare_svn_core {
    my $self = shift;
    return 1 if -e File::Spec->catfile($self->build_dir, 'strawberry-perl', 'perl', 'lib', 'SVN' );

    $self->extract("svn-win32-@{[svn_version]}.zip");
    $self->extract("svn-win32-@{[svn_version]}_pl.zip");

    my $svnperl = File::Spec->catfile($self->build_dir, "svn-win32-@{[svn_version]}", 'perl', 'site', 'lib' );

    my $strperl = File::Spec->catfile($self->build_dir, 'strawberry-perl', 'perl', 'lib' );

    rename(File::Spec->catfile($svnperl, "SVN") =>
	   File::Spec->catfile($strperl, "SVN")) or die $!;

    rename(File::Spec->catfile($svnperl, "auto", "SVN") =>
	   File::Spec->catfile($strperl, "auto", "SVN")) or die $!;

    move($_ => File::Spec->catfile($self->build_dir, 'strawberry-perl', 'perl', 'bin'))
	for glob($self->build_dir."/svn-win32-@{[svn_version]}/bin/*.dll");

    move($self->build_dir."/svn-win32-@{[svn_version]}/iconv" => File::Spec->catfile($self->build_dir, 'strawberry-perl', 'iconv'))
}

sub prepare_dist {
    my $self = shift;
    my $toplevel = shift;
    my @paroptions;
    open my $tmpfh, '>test_files.txt' or die $!;
    print $tmpfh map { "$toplevel/$_;site/$_\n" } $self->test_files($toplevel);
    close $tmpfh;
    open my $fh, 'win32/paroptions.txt' or die $!;
    while (<$fh>) { next if m/^#/; chomp; push @paroptions, split(/ /,$_) };

    my @bundled_dll = map { s{.*\\}{}; $_ } glob(File::Spec->catfile($self->build_dir, 'strawberry-perl', 'perl', 'bin').'\*.dll');

    push @paroptions,
         -o => $self->build_dir."/SVK.par",
         -a => "$toplevel/lib/SVK/Help;lib/SVK/Help",
         -a => "$toplevel/lib/SVK/I18N;lib/SVK/I18N",
         -a => $self->perldest."/auto/POSIX;lib/auto/POSIX",
         -I => "$toplevel/lib",
         -I => $self->perldest,
         (map { (-a => File::Spec->catfile($self->build_dir, 'strawberry-perl', 'perl', 'bin', $_).";bin/$_") }
              qw(perl.exe prove.bat), @bundled_dll ),
         -a => "$toplevel/blib/script/svk;bin/svk",
         -a => "$toplevel/pkg/win32/maketest.bat;win32/maketest.bat",
         -a => "$toplevel/pkg/win32/svk.ico;win32/svk.ico",
         -a => "$toplevel/pkg/win32/svk-uninstall.ico;win32/svk-uninstall.ico",
         -a => "$toplevel/pkg/win32/svk.nsi;win32/svk.nsi",
         -a => "$toplevel/pkg/win32/Path.nsh;win32/Path.nsh",
         -a => File::Spec->catfile($self->build_dir, 'strawberry-perl', 'iconv').";iconv",
         -a => "$toplevel/contrib;site/contrib",
         -a => "$toplevel/utils;site/utils",
         -a => "$toplevel/README;README",
         -a => "$toplevel/CHANGES;CHANGES",
         -a => "$toplevel/ARTISTIC;ARTISTIC",
         -a => "$toplevel/COPYING;COPYING",
	 -A => "test_files.txt";
#         map { -a => "$toplevel/$_;site/$_" } $self->test_files($toplevel);



    rmtree ['build'] if -d 'build';
    mkdir('build');
    $ENV{PAR_VERBATIM} = 1; # dynloader gets upset and gives warnings if it has #line
    system('pp', @paroptions, "$toplevel/blib/script/svk");

    eval { $self->extract( $self->build_dir."/SVK.par" => $self->build_dir."/build" ); } or warn $@;
    $self->build_archive( $self->build_dir."/build", $self->get_svk_version($toplevel));
}

sub build_archive {
    my ($self, $dir, $version) = @_;
    Env::Path->PATH->Prepend("C:/Program Files/NSIS");
    system('makensis', "/X !define MUI_VERSION $version", "$dir/win32/svk.nsi");
    my ($file) = glob($self->build_dir."/build/*.exe");
    if ($file) {
        my (undef, $dir, $name) = File::Spec->splitpath($file);
        rename($file => $name);

        print "Congratulations! You have a new build.\n";
    } else { 
        warn "Couldn't build installer.\n";
    }
}

package SVK::Build::Darwin;
use base 'SVK::Build';
use File::Copy 'copy';
sub prepare_svn_core {
    my $self = shift;
    my $output = `otool -L \`which svn\``;
    for ($output =~ m/^.*$/mg) {
	my ($lib) = m/^\s*(.*?)\s/ or next;
    next if $lib =~ /^\/(?:System|usr\/lib)/;
        warn $lib;
	    copy($lib, $self->build_dir);
    }
}

