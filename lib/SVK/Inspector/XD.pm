package SVK::Inspector::XD;

use strict;
use warnings;

use base qw {
	SVK::Inspector
};

require SVN::Core;
require SVN::Repos;
require SVN::Fs;

use SVK::Util qw( is_symlink md5_fh );

=head1 NAME

SVK::Inspector::XD - checkout inspector

=head1 SYNOPSIS

use SVK::XD;
use SVK::Inspector::XD;

my $xd = SVK::XD->new(...);

my %editor_extras = (
    get_copath => sub { ... },
    get_path => sub { ... },
    oldroot => ... #the parent of the current checkout
    get_fh => sub { ... }
    ... 
);

my $inspector = SVK::Inspector::XD->new($xd, \%editor_extras); 

=cut 


__PACKAGE__->mk_accessors(qw(xd args get_copath get_path));

sub oldroot {
    my $self = shift;
    $self->args->{oldroot};
}

sub get_fh {
    my $self = shift;
    $self->args->{get_fh}->(@_);
}

sub exist { 
    my ($self, $path, $pool) = @_;
    my $copath;
    ($path,$copath) = $self->get_paths($path);
    
    lstat ($copath);
    return $SVN::Node::none unless -e _;
    
    return (is_symlink || -f _) ? $SVN::Node::file : $SVN::Node::dir
    if $self->xd->{checkout}->get ($copath)->{'.schedule'} or
        $self->oldroot->check_path ($path, $pool);
    return $SVN::Node::unknown;
}
  
sub rev { 
    
    my ($self, $path) = @_;
    my $copath;
    ($path,$copath) = $self->get_paths($path);
    
    return $self->xd->{checkout}->get($copath)->{revision}     
}
sub localmod { 
    my ($self, $path, $checksum) = @_;
    
    my $copath;
    ($path,$copath) = $self->get_paths($path);
    
    # XXX: really want something that returns the file.
    my $base = SVK::XD::get_fh($self->oldroot, '<', $path, $copath);
    my $md5 = md5_fh ($base);
    return undef if $md5 eq $checksum;
    seek $base, 0, 0;
    return [$base, undef, $md5];
}
           
sub localprop { 
    my ($self, $path, $propname) = @_;
    my $copath;
    ($path,$copath) = $self->get_paths($path);
    
    return $self->xd->get_props ($self->oldroot, $path, $copath)->{$propname};
}
           
  
sub dirdelta { 
    my ($self, $path, $base_root, $base_path, $pool) = @_;
    my $copath;
    ($path,$copath) = $self->get_paths($path);
    my $modified;
    my $editor =  SVK::Editor::Status->new( 
        notify => SVK::Notify->new( 
            cb_flush => sub {
                               my ($path, $status) = @_;
                               $modified->{$path} = $status->[0];
                            }));
    $self->xd->checkout_delta( %{$self->args},
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

sub get_paths {
    my ($self, $path) = @_;
    
    # XXX: No translation for XD
    $path = $self->translate($path);
    
    my $copath = $path;
    
    $self->args->{get_copath}->($copath);
    $self->args->{get_path}->($path);
    
    return ($path, $copath);
}
           
1;
