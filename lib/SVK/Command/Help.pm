package SVK::Command::Help;
use strict;
our $VERSION = $SVK::VERSION;

use base qw( SVK::Command );
use SVK::I18N;
use Pod::Simple::Text ();

sub parse_arg { shift; @_ ? @_ : 'index'; }

sub run {
    my $self = shift;
    foreach my $topic (@_) {
        if ($topic eq 'commands') {
            my @cmd;
            my $dir = $INC{'SVK/Command.pm'};
            $dir =~ s/\.pm$//;
            print loc("Available commands:\n");
            File::Find::find (
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

            $buf =~ s/^NAME\s+SVK::Help::(.+)\s+DESCRIPTION/    $1:/;

            require Encode;
            print Encode::encode($self->_find_encoding, $buf);
        }
        else {
            warn loc("Cannot find help topic '%1'.\n", $topic);
        }
    }
    return;
}

sub _find_topic {
    my ($self, $topic) = @_;

    return (
        $self->_find_in_inc(loc("SVK::Help")."::\u\L$topic")
        || $self->_find_in_inc(loc("SVK::Help")."::\U$topic")
        || $self->_find_in_inc("SVK::Help::\u\L$topic")
        || $self->_find_in_inc("SVK::Help::\U$topic")
    );
}

sub _find_encoding {
    local $@;
    return eval {
        local $Locale::Maketext::Lexicon::Opts{encoding} = 'locale';
        Locale::Maketext::Lexicon::encoding();
    } || eval {
        require 'open.pm';
        return open::_get_locale_encoding();
    } || 'utf8';
}

sub _find_in_inc {
    my ($self, $file) = @_;
    
    $file =~ s{::}{/}g;

    # absolute file names
    return $file if -f $file;

    foreach my $dir (@INC) {
        return "$dir/$file.pod" if -f "$dir/$file.pod";
        return "$dir/$file.pm"  if -f "$dir/$file.pm";
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

Copyright 2003-2004 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
