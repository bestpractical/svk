package SVK::Command::Propset;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command::Commit );
use SVK::XD;
use SVK::Util qw(get_buffer_from_editor);

sub parse_arg {
    my ($self, @arg) = @_;
    return (@arg[0,1], $self->arg_co_maybe ($arg[2]));
}

sub run {
    my ($self, $pname, $pvalue, $target) = @_;

    if ($target->{copath}) {
	SVK::XD::do_propset ( $self->{info},
			      %$target,
			      propname => $pname,
			      propvalue => $pvalue,
			    );
    }
    else {
	$self->{message} = get_buffer_from_editor ('log message', $self->target_prompt,
						   "\n".$self->target_prompt."\n",
						   "/tmp/svk-commitXXXXX")
	    unless defined $self->{message};

	SVK::XD::do_propset_direct ($self->{info},
				    author => $ENV{USER},
				    %$target,
				    propname => $pname,
				    propvalue => $pvalue,
				    message => $self->{message},
				   );
    }

    return;
}

1;
