#!/usr/bin/perl
my $required_svn = '1.2.0';
my $required_svm = '0.71';

use strict;
use inc::Module::Install;

name		('SVK');
author		('Chia-liang Kao <clkao@clkao.org>');
abstract	('A decentralized version control system');
license		('perl');
version_from	('lib/SVK/Version.pm');
install_script	('bin/svk');
clean_files	('t/checkout', 't/apache_svn');
requires(
    # 'SVN::Core'                => $required_svn,
    'Algorithm::Annotate'      => '0',
    'Algorithm::Diff'          => '1.1901',
    'YAML::Syck'               => '0.60',
    'Data::Hierarchy'          => '0.30',
    'PerlIO::via::dynamic'     => '0.11',
    'PerlIO::via::symlink'     => '0.02',
    'IO::Digest'               => '0',
    'SVN::Simple::Edit'        => '0.27',
    'URI'                      => '0',
    'PerlIO::eol'              => '0.13',
    'Class::Autouse'           => '1.15',
    'App::CLI'                 => '0',
    'List::MoreUtils'          => '0',
    'Class::Accessor::Fast'    => '0',
    'Class::Data::Inheritable' => '0',
    'Path::Class'              => '0.15',
    'UNIVERSAL::require'       => '0',
    'File::Temp'               => '0.14',    # in core since 5.8.1
    'Encode'                   => '2.10',    # in core since 5.8.7
    'Getopt::Long'             => '2.35',    # in core since 5.8.8
    'Pod::Escapes'             => '0',       # in core since 5.9.3
    'Pod::Simple'              => '0',       # in core since 5.9.3
    'File::Spec'               => '3.19',    # in core since 5.9.3
);
build_requires(
    'Test::More'               => '0.42',
    'Clone'                    => 0,
);
features(
    'Localized messages' => [
	-default => 1,
        'Locale::Maketext::Lexicon' => '0.62',
        'Locale::Maketext::Simple'  => '0.16',
    ],
    'Message display through a pager' => [
        -default => 1,
        'IO::Pager'             => '0',
    ],
);

if( eval{ require SVN::Mirror } ) {
    requires( 'SVN::Mirror' => $required_svm );
} else {
    features( 'SVN::Mirror support' => [
               -default => 1,
               'SVN::Mirror'    => $required_svm,
           ],
	    );
}

features(
    'Patch management' => [
	-default => 1,
	'Compress::Zlib'    => '0',
	'FreezeThaw'        => '0',
    ],
);

# Include subdirectory tests too.
tests("t/*.t t/*/*.t");

include('ExtUtils::AutoInstall');
auto_install();

auto_provides();
WriteAll( sign => 1 );

$::VERSION = $required_svn;
die << "." unless eval {require SVN::Core; SVN::Core->VERSION >= main->VERSION };
===> Warning: SVN::Core missing or outdated.
Please manually install SVN::Core by compiling Subversion
(version $required_svn or above) with SWIG/Perl bindings,
and try this installation process again.
.
