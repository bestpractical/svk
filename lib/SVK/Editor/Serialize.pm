package SVK::Editor::Serialize;
use base 'SVK::Editor';

__PACKAGE__->mk_accessors(qw(cb_serialize_entry));

sub AUTOLOAD {
    my ($self, @arg) = @_;
    my $func = our $AUTOLOAD;
    $func =~ s/^.*:://;
    return if $func =~ m/^[A-Z]+$/;
    my $baton;
    pop @arg if ref ($arg[-1]) =~ m/^(?:SVN::Pool|_p_apr_pool_t)$/;

    warn "==> starting " if $func eq 'open_root';

    if ((my $baton_at = $self->baton_at ($func)) >= 0) {
	$baton = $arg[$baton_at];
    }
    else {
	$baton = 0;
    }

    my $ret = $func =~ m/^(?:add|open)/ ? ++$self->{batons} : undef;
    Carp::cluck unless defined $func;
    $self->cb_serialize_entry->([$ret, $func, @arg]);
    return $ret;
}

my $apply_textdelta_entry;

sub close_file {
    my ($self, $baton, $checksum) = @_;
    if ($apply_textdelta_entry) {
	$self->cb_serialize_entry->($apply_textdelta_entry);
	$apply_textdelta_entry = undef;
    }
    $self->cb_serialize_entry->([undef, 'close_file', $baton, $checksum]);
}

sub apply_textdelta {
    my ($self, $baton, @arg) = @_;
    pop @arg if ref ($arg[-1]) =~ m/^(?:SVN::Pool|_p_apr_pool_t)$/;
    my $entry = [undef, 'apply_textdelta', $baton, @arg, ''];
    open my ($svndiff), '>', \$entry->[-1];
#    $self->cb_serialize_entry->($entry);
    $apply_textdelta_entry = $entry;
    return [SVN::TxDelta::to_svndiff($svndiff)];
}


1;
