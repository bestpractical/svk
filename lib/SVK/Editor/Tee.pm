package SVK::Editor::Tee;
use strict;
use base 'SVK::Editor';
use List::MoreUtils qw(any);

__PACKAGE__->mk_accessors(qw(editors baton_maps));

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    $self->baton_maps({});
    $self->{batons} = 0;
    return $self;
}

sub run_editors { # if only we have zip..
    my ($self, $baton, $callback) = @_;
    my $i = 0;
    my @ret;
    for (@{$self->editors}) {
	push @ret, scalar $callback->($_, defined $baton ? $self->baton_maps->{$baton}[$i++] : undef);
    }
    return \@ret;
}

sub AUTOLOAD {
    my ($self, @arg) = @_;
    my $func = our $AUTOLOAD;
    $func =~ s/^.*:://;
    return if $func =~ m/^[A-Z]+$/;
    my $baton;
    my $baton_at = $self->baton_at($func);
    $baton = $arg[$baton_at] if $baton_at >= 0;

    my $rets = $self->run_editors
	( $baton,
	  sub { my ($editor, $baton) = @_;
		$arg[$baton_at] = $baton if defined $baton;
		$editor->$func(@arg);
	    });

    if ($func =~ m/^close_(?:file|directory)/) {
	delete $self->baton_maps->{$baton};
	delete $self->{baton_pools}{$baton};
    }

    if ($func =~ m/^(?:add|open)/) {
	$self->baton_maps->{++$self->{batons}} = $rets;
	return $self->{batons};
    }

    return;
}


sub window_handler {
    my ($self, $handlers, $window) = @_;
    for (@$handlers) {
	next unless $_;
	SVN::TxDelta::invoke_window_handler($_->[0], $window, $_->[1]);
    }
}

#my $pool = SVN::Pool->new;
sub apply_textdelta {
    my ($self, $baton, @arg) = @_;
    my $rets = $self->run_editors($baton,
				  sub { my ($editor, $baton) = @_;
					unless ($baton) {
					    use Data::Dumper;
					}
					$editor->apply_textdelta($baton, @arg);
				    });

    if (any { defined $_ } @$rets) {
	my $foo = sub { $self->window_handler($rets, @_) };
	my $pool = $self->{baton_pools}{$baton} = SVN::Pool->new;
	return [SVN::Delta::wrap_window_handler($foo, $pool)];
    }

    return;
}


1;
