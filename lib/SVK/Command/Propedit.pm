package SVK::Command::Propedit;
use strict;
our $VERSION = '0.09';

use base qw( SVK::Command );
use SVK::XD;
use SVK::Util qw(get_buffer_from_editor);

sub options {
    ('v|verbose'    => 'verbose',
     'r|revision=i' => 'rev');
}

sub parse_arg {
    my ($self, @arg) = @_;
    return ($arg[0], $self->arg_co_maybe ($arg[1]));
}

sub run {
    my ($self, $pname, $target) = @_;

    my $pvalue = SVK::XD::do_proplist ( $self->{info},
					%$target
				      )->{$pname};


    $pvalue = get_buffer_from_editor ("property $pname", undef, $pvalue || '',
				      '/tmp/svk-propXXXXX');

    SVK::XD::do_propset ( $self->{info},
			  propname => $pname,
			  propvalue => $pvalue,
			  %$target
			);

    return;
}

1;
