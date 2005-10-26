package SVK::Inspector::XD;

use strict;
use warnings;

use base qw {
	Class::Accessor
	SVK::Inspector
};

require SVN::Core;
require SVN::Repos;
require SVN::Fs;

use SVK::Util qw( is_symlink md5_fh );


__PACKAGE__->mk_accessors(qw(xd arg check_only));

sub compat_cb {
    my $self = shift;
    return map { my $name = $_;  "cb_$name" => sub { $self->$name(@_) } }
           qw{exist rev localmod localprop dirdelta 
              conflict prop_merged}; #XXX These shouldn't be part of this object.
}


sub new {
    my $class = shift;
    my ($xd, $arg) = @_;
    
    return $class->SUPER::new({ 
        xd => $xd, 
        arg => $arg,
        check_only => $arg->{check_only},
    });
}

# Convenience functions
sub get_copath {
    my $self = shift;
   # use Carp; Carp::cluck;
    $self->arg->{get_copath}->(@_);
}

sub get_path {
    my $self = shift;
    $self->arg->{get_path}->(@_);
}

sub oldroot {
    my $self = shift;
    $self->arg->{oldroot};
}

sub get_fh {
    my $self = shift;
    $self->arg->{get_fh}->(@_);
}

sub exist { 
    my ($self, $copath, $pool) = @_;
    my $path = $copath;
    $self->get_copath ($copath);
    lstat ($copath);
    return $SVN::Node::none unless -e _;
    
    $self->get_path ($path);
    return (is_symlink || -f _) ? $SVN::Node::file : $SVN::Node::dir
    if $self->xd->{checkout}->get ($copath)->{'.schedule'} or
        $self->oldroot->check_path ($path, $pool);
    return $SVN::Node::unknown;
}
  
sub rev { 
    my ($self, $path) = @_;
    my $copath = $path;
    $self->get_copath($copath);
    $self->xd->{checkout}->get($copath)->{revision} 
}
  
sub conflict { 
    my ($self, $path) = @_;
    my $copath = $path;
    
    $self->get_copath($copath);
    $self->xd->{checkout}->store ($copath, {'.conflict' => 1})
        unless $self->check_only;
}
  
sub prop_merged { 
    my $self = shift;
    return if $self->check_only;

    my ($path, $name) = @_;
    
    
    my $copath = $path;
    
    $self->get_copath ($copath);
    
    my $entry = $self->xd->{checkout}->get ($copath);
    warn $entry unless ref $entry eq 'HASH';
    my $prop = $entry->{'.newprop'};
    delete $prop->{$name};
    
    $self->xd->{checkout}->store ($copath, {'.newprop' => $prop,
                 keys %$prop ? () :
                 ('.schedule' => undef)}
                );
}
           
sub localmod { 
    my ($self, $path, $checksum) = @_;
    my $copath = $path;
    $self->get_copath($copath);
    $self->get_path  ($path);
    my $base = SVK::XD::get_fh($self->oldroot, '<', $path, $copath);
    my $md5 = md5_fh ($base);
    return undef if $md5 eq $checksum;
    seek $base, 0, 0;
    return [$base, undef, $md5];
}
           
sub localprop { 
    my ($self, $path, $propname) = @_;
    my $copath = $path;
    $self->get_copath ($copath);
    $self->get_path   ($path);
    return $self->xd->get_props ($self->oldroot, $path, $copath)->{$propname};
}
           
  
sub dirdelta { 
    my ($self, $path, $base_root, $base_path, $pool) = @_;
    my $copath = $path;
    $self->get_copath ($copath);
    $self->get_path   ($path);
    my $modified;
    my $editor =  SVK::Editor::Status->new( 
        notify => SVK::Notify->new( 
            cb_flush => sub {
                               my ($path, $status) = @_;
                               $modified->{$path} = $status->[0];
                            }));
    $self->xd->checkout_delta( %{$self->arg},
         # XXX: proper anchor handling
         path => $path,
         copath => $copath,
         base_root => $base_root,
         base_path => $base_path,
         xdroot => $self->oldroot,
         nodelay => 1,
         depth => 1,
         editor => $editor,
         absent_as_delete => 1,
         cb_unknown => \&SVK::Editor::Status::unknown,
    );
    return $modified;
}
           
1;
