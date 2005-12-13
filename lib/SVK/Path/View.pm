package SVK::Path::View;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base 'SVK::Path';

__PACKAGE__->mk_accessors(qw(source view));

sub new {
    my $class = shift;
    if (ref $class) {
	my $source = delete $class->{source} or Carp::cluck;
	my $oldrev = $class->revision;
	my $self = $class->_clone;
	%$self = (%$self, @_, source => $source->new);
	if ($self->revision != $oldrev) {
	     $source = $source->new(revision => $self->revision) ;
	}
	$class->source($source);
	die unless $self->source;
	return $self;
    }
    my $arg = $_[0];
    my $view = delete $arg->{view};
    return $class->Class::Accessor::Fast::new({ source => SVK::Path->new(%$arg),
						%$arg, view => $view
					      });
}

sub _root {
    my $self = shift;

    return SVK::Root::View->new_from_view
	( $self->repos->fs,
	  $self->view, $self->revision );
}

sub refresh_revision {
    my $self = shift;

    $self->SUPER::refresh_revision;
    $self->_recreate_view;

    return $self;
}

sub get_editor {
    my ($self, %arg) = @_;
    my ($editor, $inspector, %extra) = $self->source->new(path => $self->view->anchor)->get_editor(%arg);
    $editor = SVK::Editor::Rename->new(editor => $editor, rename_map => $self->view->rename_map);

    return ($editor, $inspector, %extra);
}

sub _recreate_view {
    my $self = shift;
    $self->view((SVK::Command->create_view($self->repos,
					   $self->view->base.'/'.$self->view->name,
					   $self->revision))[1]);
}

sub as_depotpath {
    my ($self, $revision) = @_;
    # return $self->source;
    if (defined $revision) {
	$self = $self->new;
	$self->source->revision($revision);
	$self->revision($revision);
	$self->_recreate_view;
    }
    return $self;
}

sub depotpath {
    my $self = shift;

    return '/'.$self->depotname.$self->view->spec;
}

1;
