package SVK::Resolve::TkDiff;
use strict;
use base 'SVK::Resolve';

sub xfind_command {
    my $self = shift;
    $self->{diff3} = $self->SUPER::find_command('diff3') or return;
    return $self->SUPER::find_command(@_);
}

sub arguments {
    my $self = shift;

    open my $in, '<', $self->{merged} or die $!;
    open my $out, '>', "$self->{merged}.tkdiff" or die $!;

    while (<$in>) {
        if (m/==== .*$self->{marker}/) {
            print $out "=======\n";
            while (<$in>) {
                last if m/==== .*$self->{marker}/;
            }
            next;
        }

        if (/^([<>])(?=.*$self->{marker})/) {
            if ($1 eq '<') {
                print $out ">>>>>>> YOURS $self->{marker}\n";
            }
            else {
                print $out "<<<<<<< THEIRS $self->{marker}\n";
            }
            next;
        }
        print $out $_;
    }
    
    return (
        -conflict => "$self->{merged}.tkdiff",
        -o        => $self->{merged},
    );
}

sub run_resolver {
    my $self = shift;
    $self->SUPER::run_resolver(@_);
    return -e $self->{merged};
}

sub DESTROY {
    my $self = shift;
    unlink "$self->{merged}.tkdiff";
}

1;
