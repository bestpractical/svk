#!/usr/bin/perl
# ExtUtils::AutoInstall Bootstrap Code, version 7.
BEGIN{my$p='ExtUtils::AutoInstall';my$v=0.45;$p->VERSION||0>=$v
or+eval"use $p $v;1"or+do{my$e=$ENV{PERL_EXTUTILS_AUTOINSTALL};
(!defined($e)||$e!~m/--(?:default|skip|testonly)/and-t STDIN or
eval"use ExtUtils::MakeMaker;WriteMakefile(PREREQ_PM=>{'$p',$v}
);1"and exit)and print"==> $p $v required. Install it from CP".
"AN? [Y/n] "and<STDIN>!~/^n/i and print"*** Installing $p\n"and
do{if (eval '$>' and lc(`sudo -V`) =~ /version/){system('sudo',
$^X,"-MCPANPLUS","-e","CPANPLUS::install $p");eval"use $p $v;1"
||system('sudo', $^X, "-MCPAN", "-e", "CPAN::install $p")}eval{
require CPANPLUS;CPANPLUS::install$p};eval"use $p $v;1"or eval{
require CPAN;CPAN::install$p};eval"use $p $v;1"||die"*** Please
manually install $p $v from cpan.org first...\n"}}}

my $required_svn = '0.33.0';

use ExtUtils::AutoInstall
    ( -version        => '0.40',
      -core           =>
      [ 'SVN::Core'   => $required_svn,
        'Algorithm::Annotate'   => '0',
        'Data::Hierarchy'       => '0.13',
        'SVN::Simple::Edit'     => '0.21',
      ],
      'SVN::Mirror support' =>
      [ -default    => 1,
	SVN::Mirror    => '0.22',
      ],
    );

WriteMakefile(
    AUTHOR              => 'Chia-liang Kao (clkao@clkao.org)',
    ABSTRACT            => 'A decentralized version control system',
    NAME                => 'SVN::XD',
    VERSION_FROM        => 'lib/SVN/XD.pm',
    DISTNAME            => 'SVN-XD',
    EXE_FILES    => [ 'bin/svk' ],
    dist                => {
        COMPRESS        => 'gzip -9',
        SUFFIX          => '.gz',
    },
);

die "SVN::Core $required_svn must be manually installed"
    unless eval {require SVN::Core} && $SVN::Core::VERSION >= $required_svn;
