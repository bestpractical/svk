package SVK::Resolve::Emacs;
use strict;
use base 'SVK::Resolve';
use SVK::I18N;
use SVK::Util qw( devnull );

sub commands { 'gnuclient-emacs' }

sub arguments {
    my $self = shift;
    my $lisp = "(require 'svk-ediff)";

    # set up the signal handlers
    $self->{signal} ||= 'USR1';

    if ($self->{base} eq devnull()) {
        $lisp .= qq(
(ediff-files-internal
 "$self->{yours}" "$self->{theirs}" nil
 nil 'ediff-merge-files)
);
    } else {
        $lisp .= qq(
(ediff-files-internal
 "$self->{yours}" "$self->{theirs}" "$self->{base}"
 nil 'ediff-merge-files-with-ancestor)
)
    }

    $lisp .= qq(
(svk-merge-startup '((working-file . "$self->{yours}")
                       (selected-file . "$self->{theirs}")
                       (common-file . "$self->{base}")
                       (working-label . "$self->{label_yours}")
                       (selected-label . "$self->{label_theirs}")
                       (common-label . "$self->{label_base}")
                       (output-file . "$self->{merged}")
                       (process . $$)
                       (signal . SIG$self->{signal})))
'OK!
);

    return ('--eval' => $lisp);
}

sub run_resolver {
    my ($self, $cmd, @args) = @_;

    local $SIG{$self->{signal}} = sub {
        print loc("Emerge %1 done.\n");
        $self->{finished} = 1;
    };

    my $pid;
    if (!defined($pid = fork)) {
        die loc("Cannot fork: %1", $!);
    }
    elsif ($pid) {
        print loc(
            "Started %1, Try 'kill -%2 %3' to terminate if things mess up.\n",
            $pid, $self->{signal}, $$,
        );
        sleep 1 until $self->{finished};
    }
    else {
        exec($cmd, @args) or die loc("Could not run %1: %2", $cmd, $!);
    }

    return $self->{finished};
}

1;
