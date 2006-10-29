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
        my $path = shift;
        $path = $path->stringify if index(ref($path), 'Path::Class') == 0;
        # warn "===> $self $func: ".join(',',@_).' '.join(',', (caller(0))[0..3])."\n";
        unshift @_, $path if defined $path;
        return $self->root->$func(@_);
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

# return the root and path on the given revnum, the returned path is
# with necessary translations.
sub get_revision_root {
    my $self = shift;
    my $path = shift;
    return ( $self->new({root => $self->fs->revision_root(@_)}), 
	     $path );
}

sub txn_root {
    my ($self, $pool) = @_;
    my $txn = $self->fs->begin_txn($self->revision_root_revision, $pool);
    return $self->new({ txn => $txn, root => $txn->root($pool) });
}

1;
