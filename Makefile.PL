#!/usr/bin/perl
my $required_svn = '0.36.0';

use inc::Module::Install;

name		('SVK');
author		('Chia-liang Kao <clkao@clkao.org>');
abstract	('A decentralized version control system');
license		('perl');
version_from	('lib/SVK.pm');
install_script	('bin/svk');

requires(
        'SVN::Core'   => $required_svn,
        'Algorithm::Annotate'   => '0',
        'Text::Diff'            => '0',
        'YAML'                  => '0',
        'IO::String'            => '0',
        'Regexp::Shellish'      => '0',
        'Data::Hierarchy'       => '0.13',
        'PerlIO::via::dynamic'  => '0.02',
        'SVN::Simple::Edit'     => '0.21',
);
features(
    'SVN::Mirror support' => [
	-default => 1,
	'SVN::Mirror'    => '0.29',
    ],
);

include('ExtUtils::AutoInstall');
auto_install();

WriteAll( sign => 1 );

die "SVN::Core $required_svn must be manually installed"
    unless eval {require SVN::Core} && $SVN::Core::VERSION >= $required_svn;
