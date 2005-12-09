package SVK::Root;
use strict;
use warnings;

use base qw{ Class::Accessor::Fast };

__PACKAGE__->mk_accessors(qw(root txn pool));

sub AUTOLOAD {
    my $func = our $AUTOLOAD;
    $func =~ s/^.*:://;
    return if $func =~ m/^[A-Z]+$/;

    no strict 'refs';
    no warnings 'redefine';

    *$func = sub {
        my $self = shift;
        # warn "===> $self $func: ".join(',',@_).' '.join(',', (caller(0))[0..3])."\n";
        return $self->root->$func (@_);
    };

    goto &$func;
}

sub DESTROY {
    return unless $_[0]->txn;
    # if this destructor is called upon the pool cleanup which holds the
    # txn also, we need to use a new pool, otherwise it segfaults for
    # doing allocation in a pool that is being destroyed.
    $_[0]->txn->abort(SVN::Pool->new) if $_[0]->txn;
}

1;
