package SVK::Path::View;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use SVK::I18N;

use base 'SVK::Path';

__PACKAGE__->mk_accessors(qw(source view));

use SVK::Util qw( abs2rel );
use SVK::Root::View;

sub new {
    my $class = shift;
    if (ref $class) {
	my %arg = @_;
	my $source = delete $class->{source} or Carp::cluck;
	my $oldrev = $class->revision;
	my $self = $class->_clone;
	my $revision = delete $arg{revision};
	%$self = (%$self, %arg, source => $source->new(revision => $revision));
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
	  $self->view, $self->source->revision );
}

sub refresh_revision {
    my $self = shift;

    $self->SUPER::refresh_revision;
    $self->_recreate_view;

    return $self;
}

sub get_editor {
    my ($self, %arg) = @_;
    my $anchor = $self->_to_pclass($self->path_anchor, 'Unix');
    my $map = $self->view->rename_map('');
    my $actual_anchor = $self->_to_pclass($self->root->rename_check($anchor, $map), 'Unix');


    if ($self->{targets}) {

	my @view_targets = map { $self->{path} eq '/' ? $_ : "$self->{path}/$_"} @{$self->{targets}};
	my @actual_targets = map { $self->root->rename_check($_, $map) }
	    @view_targets;

	my @tmp =  map { $self->source->new( path => $_ ) } @actual_targets;
	my $tmp = shift @tmp;

	unless ($tmp->same_source(@tmp)) {
	    # XXX: be more informative
	    die loc("Can't commit a view with changes in multiple mirror sources.\n");
	}
    }
    else {
	die "view get_editor used without targets";
    }

    my ($editor, $inspector, %extra) = $self->source->new(path => $actual_anchor)->get_editor(%arg);

    my $prefix = abs2rel($self->source->path_anchor,
			 $actual_anchor => undef, '/');

    if (@{$self->view->rename_map2($anchor, $actual_anchor)}) {
	$editor = SVK::Editor::View->new
	    ( editor => $editor,
	      rename_map => $self->view->rename_map2($anchor, $actual_anchor),
	      prefix => $prefix,
	    );
    }
    $editor = SVN::Delta::Editor->new(_debug => 1, _editor => [$editor])
	if $main::DEBUG;
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
