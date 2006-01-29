package SVK::Accessor;
use strict;

use base qw(Class::Accessor::Fast Class::Data::Inheritable);
use Storable;

__PACKAGE__->mk_classdata('_shared_accessors');
__PACKAGE__->mk_classdata('_clonable_accessors');

sub mk_shared_accessors {
    my $class = shift;
    $class->mk_accessors(@_);
    my $fun =  $class->SUPER::can('_shared_accessors');
    no strict 'refs';
    unless (${$class.'::_shared_accessors_init'}) {
	my $y = $fun->($class) || [];
	$class->_shared_accessors(Storable::dclone($y));
	${$class.'::_shared_accessors_init'} = 1;
    }

    push @{$class->_shared_accessors}, @_;
}

sub mk_clonable_accessors {
    my $class = shift;
    $class->mk_accessors(@_);
    my $fun =  $class->SUPER::can('_clonable_accessors');
    no strict 'refs';
    unless (${$class.'::_clonable_accessors_init'}) {
	my $y = $fun->($class) || [];
	$class->_clonable_accessors(Storable::dclone($y));
	${$class.'::_clonable_accessors_init'} = 1;
    }

    push @{$class->_clonable_accessors}, @_;
}

sub clonable_accessors {
    my $self = shift;
    return (@{$self->_clonable_accessors});
}

sub shared_accessors {
    my $self = shift;
    return (@{$self->_shared_accessors});
}


sub real_new {
    my $self = shift;
    $self->SUPER::new(@_);
}

sub new {
    my ($self, @arg) = @_;
    Carp::cluck "bad usage" unless ref($self);

    return $self->mclone(@arg);
}

sub clone {
    my ($self) = @_;

    my $cloned = ref($self)->real_new;
    for my $key ($self->shared_accessors) {
	$cloned->$key($self->$key);
    }
    for my $key ($self->clonable_accessors) {
        next if $key =~ m/^_/;
	Carp::cluck unless $self->can($key);
	my $value = $self->$key;
	if (UNIVERSAL::can($value, 'clone')) {
	    $cloned->$key($value->clone);
	}
	else {
	    $cloned->$key(ref $value ? Storable::dclone($value) : $value);
	}
    }
    return $cloned;
}

sub mclone {
    my $self = shift;
    my $args = ref($_[0]) ? $_[0] : { @_ };
    my $cloned = $self->clone;
    for my $key (keys %$args) {
	Carp::cluck unless $cloned->can($key);
	$cloned->$key($args->{$key});
    }
    return $cloned;
}

1;

