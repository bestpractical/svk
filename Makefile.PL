#!/usr/bin/perl
my $required_svn = '1.0.7';
my $required_svm = '0.53';

use strict;
use inc::Module::Install;

name		('SVK');
author		('Chia-liang Kao <clkao@clkao.org>');
abstract	('A decentralized version control system');
license		('perl');
version_from	('lib/SVK.pm');
install_script	('bin/svk');
clean_files	('t/checkout', 't/apache_svn');
requires(
#        'SVN::Core'   => $required_svn,
        'Algorithm::Annotate'   => '0',
        'Algorithm::Diff'       => '0',
        'YAML'                  => '0',
        'Regexp::Shellish'      => '0',
        'Data::Hierarchy'       => '0.21',
        'File::Temp'            => '0.14',
        'Clone'	                => '0',
        'Pod::Escapes'          => '0',
        'Pod::Simple'           => '0',
        'PerlIO::via::dynamic'  => '0.11',
        'PerlIO::via::symlink'  => '0.02',
        'IO::Digest'		=> '0',
        'SVN::Simple::Edit'     => '0.26',
        'Date::Parse'           => '0',
        'File::Type'            => '0',
        'URI'                   => '0',
        'PerlIO::eol'           => '0.13',
);
features(
    'Localized messages' => [
	-default => 1,
        'Locale::Maketext::Lexicon' => '0.42',
        'Locale::Maketext::Simple'  => '0.12',
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

include('ExtUtils::AutoInstall');
auto_install();

WriteAll( sign => 1 );

$::VERSION = $required_svn;
die << "." unless eval {require SVN::Core; SVN::Core->VERSION >= main->VERSION };
===> Warning: SVN::Core missing or outdated.
Please manually install SVN::Core by compiling Subversion
(version $required_svn or above) with SWIG/Perl bindings,
and try this installation process again.
.
