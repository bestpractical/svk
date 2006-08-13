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

# XXX: original behaviour of svn::delta::editor is "don't care" on
# methods not implemented.  we shuold probably do warn and fix them.
sub AUTOLOAD {}

1;
