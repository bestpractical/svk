package SVK::Editor;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(qw(_debug));

use SVK::Editor::ByPass;

sub new {
    my $class = shift;
    # XXX: warn about plain hash passing
    my $arg = ref $_[0] ? $_[0] : { @_ };
    my $self = $class->SUPER::new($arg);

    # setup about debug.
    if ($class ne 'SVK::Editor::ByPass') {
	# XXX: load from SVK::Debug or something to decide what level
	# of debug we want for particular editors.
	$self->_debug(1) if ($ENV{SVKDEBUG} || '') =~ m/\Q$class\E/;
	return SVK::Editor::ByPass->new({ _debug => 1, _editor => $self})
	    if $self->_debug;
    }
    return $self;
}

sub baton_at {
    my ($self, $func) = @_;
    Carp::cluck unless defined $func;
    return -1
	if $func eq 'set_target_revision' || $func eq 'open_root' ||
	    $func eq 'close_edit' || $func eq 'abort_edit';
    return 2 if $func eq 'delete_entry';
    return $func =~ m/^(?:add|open|absent)/ ? 1 : 0;
}

# XXX: original behaviour of svn::delta::editor is "don't care" on
# methods not implemented.  we shuold probably do warn and fix them.
sub AUTOLOAD {}

1;
