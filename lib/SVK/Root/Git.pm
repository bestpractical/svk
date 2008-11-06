package SVK::Root::Git;
use strict;
use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw(depot commit));

sub _get_path {
    my ($self, $full_path) = @_;
    my $refs = [ map { m/.*? (.*)/ }
                     $self->depot->run_cmd('show-ref') =~ m/^.*$/mg ];
    my $re = join('|', @$refs);
    my ($tree, $path);
    if (($tree, $path) = $full_path =~ m{^/($re)(?:/(.*))?$}) {
        $path = '' unless defined $path;
    } else {
        $tree = 'refs/heads/master';
#        $path = substr($full_path,2);
        $path = $full_path;
        $path =~ s#^/##;
    }
    my ($ref) = $self->depot->run_cmd("show-ref $tree") =~ m/^(.*?) /;
    return ($ref, $path);
}

sub file_contents {
    my ($self, $full_path, $pool) = @_;
    my ($tree, $path) = $self->_get_path( $full_path );

    # find the node ref:
    my ($blob) = `git --git-dir @{[ $self->depot->repospath ]} ls-tree $tree $path` =~ m/^.*? blob (.*?)\s/;
    my $content = `git --git-dir @{[ $self->depot->repospath ]} cat-file blob $blob`;
    open my $fh, '<', \$content;
    return $fh;
#    my ($copath, $root) = $self->_get_copath($path, $pool);
#    return SVK::XD::get_fh($root, '<', $path, $copath);
}

sub check_path {

    my ($self, $full_path, $pool) = @_;
    my ($tree, $path) = $self->_get_path( $full_path );

    return $SVN::Node::dir unless length $path;
    # find the node ref:
    my ($type, $key) = `git --git-dir @{[ $self->depot->repospath ]} ls-tree $tree $path` =~ m/^.*? (.*?) (.*?)\s/;

    return $type ? $type eq 'blob' ? $SVN::Node::file
                                   : $SVN::Node::dir
                 : $SVN::Node::unknown;
}

sub dir_entries {
    my ($self, $full_path, $pool) = @_;
    my ($tree, $path) = $self->_get_path( $full_path );
    # find the node ref:
    Carp::confess unless defined $path;
    $path .= '/' if length $path;
    my $entries = { map {  my $x = {}; @$x{qw(mode type key name)} = split /\s/, $_; $x->{name} =~ s{^$path}{};
                           $x->{name} => $x } `git --git-dir @{[ $self->depot->repospath ]} ls-tree $tree $path` =~ m/^.*$/mg };

    # XXX: just a holder
    require SVK::Root::Checkout;
    return { map { $_ => SVK::Root::Checkout::Entry->new
                       ({ kind => $entries->{$_}{type} eq 'blob' ? $SVN::Node::file : $SVN::Node::dir })
                   } keys %$entries };

}

sub node_proplist {
    return {};
}

1;
