package SVK::Editor::ByPass;

use base 'SVK::Editor';

__PACKAGE__->mk_accessors(qw(_editor));

# editor with the behaviour that when the subclass calls ->SUPER, it dispatches to ->{_editor}.

sub new {
    my $class = shift;
    my $self = ref($_[0]) =~ m/Editor/
	? $class->SUPER::new({ _editor => $_[0]})
	: $class->SUPER::new(@_);
    if ($self->_editor) {
	if (ref($self->_editor) eq 'ARRAY') {
	    Carp::cluck,die if $#{$self->_editor} == 1;
	    $self->_editor($self->_editor->[0]);
	}
    }
    Carp::cluck unless $self->_editor;
    return $self;
}

our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;
    my $editor = $self->_editor;
    my $func = $AUTOLOAD;
    my $method;
    $func =~ s/.*:://;
    if ($self->_debug) {
	# XXX: debug hook instead of just warn?
	Carp::carp $editor.' '.$func.' '.join(',', @_)
    }
    return if $func =~ m/^[A-Z]/;
    $method = $editor->can($func);
    unless ($method) {
	# XXX: might be able to short circuit chained bypass
	# maybe autoload
	return $editor->$func(@_);
    }
    unshift @_, $editor;
    goto $method;
}

1;
