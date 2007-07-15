#!perl

use strict;
use warnings;
use Cwd 'abs_path';

use File::Spec;



=head1 NAME

buildsvk.pl - packaging svk

=head1 SYNOPSIS



=head1 DESCRIPTION

Put the dist files under src and C<buildsvk.pl> will create a build
directory with everything installed under it.

=cut

my $build = SVK::Build->new;
my $t = time();

$build->prepare_perl();
$build->prepare_svn_core();

$build->build_module('libwin32', 'Console') if $^O eq 'MSWin32';

$build->build_module($_) for qw(Scalar-List-Utils Class-Autouse version Sub-Uplevel Test-Simple Test-Exception Data-Hierarchy PerlIO-via-dynamic PerlIO-via-symlink SVN-Simple PerlIO-eol Algorithm-Diff Algorithm-Annotate Pod-Escapes Pod-Simple IO-Digest TimeDate Getopt-Long Encode PathTools YAML-Syck Locale-Maketext-Simple App-CLI List-MoreUtils Path-Class Class-Data-Inheritable Class-Accessor UNIVERSAL-require File-Temp Log-Log4perl);
$build->build_module($_) for qw(Locale-Maketext-Lexicon TermReadKey IO-Pager);
$build->build_module($_) for qw(File-chdir SVN-Mirror);
$build->build_module($_) for qw(FreezeThaw);

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
    my $ae = Archive::Extract->new( archive => shift );

    $ae->extract( to => $self->build_base )
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

    my ($file) = glob("src/$module-*");
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

sub prepare_dist {
    my $self = shift;
    my $toplevel = shift;
    copy('svk-wrapper' => $self->build_dir."/svk");
    chmod 0755, $self->build_dir."/svk";

    open my $fh, "$toplevel/MANIFEST" or die "Could not create $toplevel/MANIFEST: ".$!;
    while (<$fh>) {
	chomp;
	next unless m{^t/};
	my $file = $_;
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
    Env::Path->PATH->Assign( map { abs_path(File::Spec->catfile($self->build_dir, 'strawberry-perl', $_, 'bin')) } qw(perl dmake mingw));
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
    $self->extract('strawberry-perl.zip');
}

sub prepare_svn_core {
    my $self = shift;
    return 1 if -e File::Spec->catfile($self->build_dir, 'strawberry-perl', 'perl', 'lib', 'SVN' );

    $self->extract('svn-win32-1.4.4.zip');
    $self->extract('svn-win32-1.4.4_pl.zip');

    my $svnperl = File::Spec->catfile($self->build_dir, 'svn-win32-1.4.4', 'perl', 'site', 'lib' );

    my $strperl = File::Spec->catfile($self->build_dir, 'strawberry-perl', 'perl', 'lib' );

    rename(File::Spec->catfile($svnperl, "SVN") =>
	   File::Spec->catfile($strperl, "SVN")) or die $!;

    rename(File::Spec->catfile($svnperl, "auto", "SVN") =>
	   File::Spec->catfile($strperl, "auto", "SVN")) or die $!;

    move($_ => File::Spec->catfile($self->build_dir, 'strawberry-perl', 'perl', 'bin'))
	for glob($self->build_dir."/svn-win32-1.4.4/bin/*.dll");
}

sub prepare_dist {
    my $self = shift;
    my $toplevel = shift;
    my @paroptions;
    open my $fh, 'win32/paroptions.txt' or die $!;
    while (<$fh>) { next if m/^#/; chomp; push @paroptions, split(/ /,$_) };
    push @paroptions,
         -a => "$toplevel/lib/SVK/Help;lib/SVK/Help",
         -a => "$toplevel/lib/SVK/I18N;lib/SVK/I18N",
         -a => $self->perldest."/auto/POSIX;lib/auto/POSIX",
         -I => "$toplevel/lib",
         (map { (-a => File::Spec->catfile($self->build_dir, 'strawberry-perl', 'perl', 'bin', $_).";bin/$_") }
              qw(perl.exe perl58.dll prove.bat intl3_svn.dll libapr.dll libapriconv.dll libaprutil.dll libdb44.dll libeay32.dll ssleay32.dll) ),
         -a => "$toplevel/blib/script/svk;bin/svk",
         -a => "$toplevel/blib/script/svk.bat;bin/svk.bat",
         -a => "$toplevel/pkg/win32/maketest.bat;win32/maketest.bat",
         -a => "$toplevel/pkg/win32/svk.ico;win32/svk.ico",
         -a => "$toplevel/pkg/win32/svk-uninstall.ico;win32/svk-uninstall.ico",
         -a => "$toplevel/pkg/win32/svk.nsi;win32/svk.nsi",
         -a => "$toplevel/pkg/win32/Path.nsh;win32/Path.nsh",
         -a => "$toplevel/contrib;site/contrib",
         -a => "$toplevel/utils;site/utils",
         -a => "$toplevel/t;site/t",
         -a => "$toplevel/README;README",
         -a => "$toplevel/CHANGES;CHANGES",
         -a => "$toplevel/ARTISTIC;ARTISTIC",
         -a => "$toplevel/COPYING;COPYING";


    move($_ => File::Spec->catfile($self->build_dir, 'strawberry-perl', 'perl', 'bin'))
	for glob($self->build_dir."/svn-win32-1.4.4/bin/*.dll");

    rmtree ['build'] if -d 'build';
    mkdir('build');
    system('pp', @paroptions, "$toplevel/blib/script/svk");

    system('zip', qw(-d build\SVK.par lib\SVK));
    system('zip', qw(-d build\t\checkout lib\SVK));
    system('unzip', qw(-o -d build build/SVK.par));
    $self->build_archive($self->get_svk_version($toplevel));
}

sub build_archive {
    my ($self, $version) = @_;
    Env::Path->PATH->Prepend("C:/Program Files/NSIS");
    system('makensis', "/X !define MUI_VERSION $version", 'build/win32/svk.nsi');
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

