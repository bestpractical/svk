#!/usr/bin/perl
use Test::More;
use strict;
require 't/tree.pl';

-r '/dev/tty' ? plan tests => 2 : plan skip_all => 'no tty';

our ($output, @TOCLEAN);

my $xd = SVK::XD->new (depotmap => {},
		       checkout => Data::Hierarchy->new);
my $svk = SVK->new (xd => $xd, output => \$output);
push @TOCLEAN, [$xd, $svk];

use File::Temp;
sub jam {
    local $SIG{TTOU} = "IGNORE"; # "Stopped for tty output"
    my $TIOCSTI = 0x80017472;
    local *TTY;
    open(TTY, '<', '/dev/tty');
    for (split(//, $_[0])) {
        ioctl(TTY, $TIOCSTI, $_) || die "bad TIOCSTI: $!";
    }
    close(TTY);
}

my $tmp = File::Temp->new;

print $tmp (<< 'TMP');
#!/bin/sh
sleep 1
echo $1 $2
cat > $2 << EOF
'': '$1'

===edit the above depot map===

EOF

TMP
$tmp->close;
chmod 0755, $tmp->filename;
my $repospath = "/tmp/svk-$$";
$ENV{EDITOR} = "$tmp $repospath";
jam("n\n");
$svk->depotmap;
ok (!-e $repospath);
jam("y\n");
$svk->depotmap ('--init');
ok (-d $repospath);
