package SVK::Command::Help;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::I18N;
use SVK::Util qw( get_encoding );
use autouse 'File::Find' => qw(find);

sub parse_arg { shift; @_ ? @_ : 'index'; }

# Note: lock is not called for help, as it's invoked differently from
# other commands.

sub run {
    my $self = shift;
    foreach my $topic (@_) {
        if ($topic eq 'commands') {
            my @cmd;
            my $dir = $INC{'SVK/Command.pm'};
            $dir =~ s/\.pm$//;
            print loc("Available commands:\n");
            find (
                sub { push @cmd, $File::Find::name if m/\.pm$/ }, $dir,
            );
            $self->brief_usage ($_) for sort @cmd;
        }
        elsif (my $cmd = eval { $self->get_cmd ($topic) }) {
            $cmd->usage(1);
        }
        elsif (my $file = $self->_find_topic($topic)) {
            open my $fh, '<:utf8', $file or die $!;
            my $parser = Pod::Simple::Text->new;
            my $buf;
            $parser->output_string(\$buf);
            $parser->parse_file($fh);

            $buf =~ s/^NAME\s+SVK::Help::\S+ - (.+)\s+DESCRIPTION/    $1:/;

            require Encode;
            my $encoder = Encode::find_encoding(get_encoding())
                       || Encode::find_encoding('utf8');
            print $encoder->encode($buf);
        }
        else {
            die loc("Cannot find help topic '%1'.\n", $topic);
        }
    }
    return;
}

my ($inc, @prefix);
sub _find_topic {
    my ($self, $topic) = @_;

    if (!$inc) {
        my $pkg = __PACKAGE__;
        $pkg =~ s{::}{/};
        $inc = substr( __FILE__, 0, -length("$pkg.pm") );

        @prefix = (loc("SVK::Help"));
        $prefix[0] =~ s{::}{/}g;
        push @prefix, 'SVK/Help' if $prefix[0] ne 'SVK/Help';
    }

    foreach my $dir ($inc, @INC) {
        foreach my $prefix (@prefix) {
            foreach my $basename (ucfirst(lc($topic)), uc($topic)) {
                foreach my $ext ('pod', 'pm') {
                    my $file = "$dir/$prefix/$basename.$ext";
                    return $file if -f $file;
                }
            }
        }
    }

    return;
}

1;

__DATA__

=head1 NAME

SVK::Command::Help - Show help

=head1 SYNOPSIS

 help COMMAND

=head1 OPTIONS

 None

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
