package SVK::Editor::Network;
use strict;
use SVK::Editor::Patch;
our $VERSION = $SVK::VERSION;
our @ISA = qw(SVK::Editor::Patch);
use Storable qw/nstore_fd/;

our $AUTOLOAD;

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

sub AUTOLOAD {
    my ($self, @arg) = @_;
    my $func = $AUTOLOAD;
    $func =~ s/^.*:://;
    return if $func =~ m/^[A-Z]+$/;

    # flush textdelta
    if ($func eq 'close_file' && $self->{textdelta}{$arg[0]}) {
	$self->{read_callback}->($self->{sock});

	$self->{sock}->print ($self->{prefix}) if defined $self->{prefix};
        nstore_fd ($self->{textdelta}{$arg[0]}, $self->{sock});
	delete $self->{textdelta}{$arg[0]};
    }

    pop @arg if ref ($arg[-1]) eq '_p_apr_pool_t';

    my $ret = $func =~ m/^(?:add|open)/ ? ++$self->{batons} : undef;
    $self->{sock}->print ($self->{prefix}) if defined $self->{prefix};
    nstore_fd ([$ret, $func, @arg], $self->{sock}) or die $!;
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

