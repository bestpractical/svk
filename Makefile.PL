#!/usr/bin/perl
use ExtUtils::MakeMaker;

WriteMakefile(
    AUTHOR              => 'Chia-liang Kao (clkao@clkao.org)',
    ABSTRACT            => 'subversion keeper',
    NAME                => 'SVN::XD',
    VERSION_FROM        => 'lib/SVN/XD.pm',
    DISTNAME            => 'SVN-XD',
    PREREQ_PM           => {
        'SVN::Core'   => '0',
    },
    EXE_FILES    => [ 'bin/svk' ],
    dist                => {
        COMPRESS        => 'gzip -9',
        SUFFIX          => '.gz',
    },
);

