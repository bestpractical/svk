package SVK::Editor::Network;
use strict;
our $VERSION = $SVK::VERSION;
use base qw(SVK::Editor::Patch);
use FreezeThaw qw(freeze);

sub emit {
    my ($self, $call) = @_;
    my ($ret, $func, @arg) = @$call;
    my $baton_at = $self->baton_at ($func);
    if ($baton_at >= 0) {
	my $arg = $arg[$baton_at];
	die "can find baton $arg"
	    unless exists $self->{baton_holder}{$arg};
	$arg[$baton_at] = $self->{baton_holder}{$arg};
	delete $self->{baton_holder}{$arg} if $func =~ m/^close/;
    }
    my $ret_baton = $self->SUPER::emit ($self->{editor}, $func, undef, @arg);
    $self->{baton_holder}{$ret} = $ret_baton if $ret;
}

sub freeze_fd {
    my ($sock, $data) = @_;
    my $buf = freeze ($data);
    $sock->print (pack ('n', length ($buf)), $buf);
}

sub write_call {
    my ($self, $call) = @_;
    $self->{sock}->print ($self->{prefix}) if defined $self->{prefix};
    freeze_fd ($self->{sock}, $call) or die $!;
}

our $AUTOLOAD;

sub AUTOLOAD {
    my ($self, @arg) = @_;
    my $func = $AUTOLOAD;
    $func =~ s/^.*:://;
    return if $func =~ m/^[A-Z]+$/;

    # flush textdelta
    if ($func eq 'close_file' && $self->{textdelta}{$arg[0]}) {
	$self->{read_callback}->($self->{sock});
	$self->write_call ($self->{textdelta}{$arg[0]});
	delete $self->{textdelta}{$arg[0]};
    }

    pop @arg if ref ($arg[-1]) eq '_p_apr_pool_t';

    my $ret = $func =~ m/^(?:add|open)/ ? ++$self->{batons} : undef;
    $self->write_call ([$ret, $func, @arg]);
    return $ret;
}

sub apply_textdelta {
    my ($self, $baton, @arg) = @_;
    pop @arg if ref ($arg[-1]) =~ m/^(?:SVN::Pool|_p_apr_pool_t)$/;

    $self->{textdelta}{$baton} = [undef, 'apply_textdelta', $baton, @arg, undef];
    open my ($svndiff), '>', \$self->{textdelta}{$baton}[-1];
    return [SVN::TxDelta::to_svndiff ($svndiff)];
}

1;

