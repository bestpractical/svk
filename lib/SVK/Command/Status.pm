package SVK::Command::Status;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;
use SVK::StatusEditor;

sub parse_arg {
    my $self = shift;
    my @arg = @_;
    @arg = ('') if $#arg < 0;

    return $self->arg_condensed (@arg);
}

sub run {
    my ($self, $target) = @_;
    my ($txn, $xdroot) = SVK::XD::create_xd_root ($self->{info}, %$target);

    SVK::XD::checkout_delta ( $self->{info},
			      %$target,
			      baseroot => $xdroot,
			      xdroot => $xdroot,
			      delete_verbose => 1,
			      strict_add => 1,
			      editor => SVK::StatusEditor->new
			      ( copath => $target->{copath},
				dpath => $target->{path},
				rpath => $target->{report}),
			      cb_conflict => \&SVK::StatusEditor::conflict,
			      cb_unknown =>
			      sub { $_[1] =~ s|^\Q$target->{copath}\E/|$target->{report}|;
				    print "?  $_[1]\n" }
			    );
    $txn->abort if $txn;
    return;
}

1;
