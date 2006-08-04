package SVK::Log::Filter::Std;

use base qw( SVK::Log::Filter::Output );

use SVK::I18N;
use SVK::Util qw( get_encoding reformat_svn_date );

our $sep;

sub setup {
    my ($self, $args) = @_;
    my $stash = $args->{stash};

    $sep = $stash->{verbatim} || $stash->{no_sep} ? '' : ('-' x 70)."\n";
    print $sep;

    # avoid get_encoding() calls for each revision
    $self->{encoding} = get_encoding();
}

sub revision {
    my ($self, $args) = @_;
    my ($stash, $rev, $props) = @{$args}{qw( stash rev props )};

    # get short names for attributes
    my            ( $indent, $verbatim, $quiet )
    = @{$stash}{qw(  indent   verbatim   quiet )};


    my ( $author, $date ) = @{$props}{qw/svn:author svn:date/};
    my $message = $sep;   # assume quiet
    if (!$quiet) {
        $message  = $indent ? '' : "\n";
        $message .= $props->{'svn:log'} . "\n$sep";
    }

    # clean up the date
    $date = reformat_svn_date("%Y-%m-%d %T %z", $date);

    $author = loc('(no author)') if !defined($author) or !length($author);
    if ( !$verbatim ) {
        print $indent;
        print fancy_rev( $stash, $rev, $args->{get_remoterev} );
        print ":  $author | $date\n";
    }

    # display the paths that were modified by this revision
    if ( $stash->{verbose} ) {
        print build_changed_details( $stash, $args->{paths}, $self->{encoding} );
    }

    $message =~ s/^/$indent/mg if $indent and !$verbatim;
    require Encode;
    Encode::from_to( $message, 'UTF-8', $self->{encoding} );
    print($message);
}

sub fancy_rev {
    my ( $stash, $rev, $get_remoterev ) = @_;

    # find the remote revision number (if possible)
    my $host          = $stash->{host};
    my $remoterev     = $get_remoterev->($rev) if $get_remoterev;

    $host = '@' . $host       if length($host);
    return "r$rev$host"       if !$remoterev;
    return "r$remoterev$host" if $stash->{remote_only};

    return "r$rev$host (orig r$remoterev)";
}

sub build_changed_details {
    my ($stash, $changed, $encoding) = @_;

    # get short names for some useful quantities
    my $indent   = $stash->{indent};

    my $output = '';

    $output .= $indent . loc("Changed paths:\n");
    for my $changed_path ( $changed->paths() ) {
        my ( $copyfrom_rev, $copyfrom_path ) =  $changed_path->copied_from();
        my $action     = $changed_path->action();
        my $propaction = $changed_path->property_action();
        my $status     = $action . $propaction;

        # encode the changed path in the local encoding
        my $encoded_path = $changed_path->path();
        Encode::from_to( $encoded_path, 'utf8', $encoding );

        # finally, we can print the details about the changed file
        $output .= $indent . "  $status $encoded_path";
        if ( defined $copyfrom_path ) {
            Encode::from_to( $copyfrom_path, 'utf8', $encoding );
            $output .= ' ';
            $output .= loc( "(from %1:%2)", $copyfrom_path, $copyfrom_rev );
        }
        $output .= "\n";
    }

    return $output;
}

1;


__END__

=head1 NAME

SVK::Log::Filter::Std - display log messages in standard SVK format

=head1 SYNOPSIS

    > svk log
    ----------------------------------------------------------------------
    r1234 (orig r456):  author | 2006-05-15 09:28:52 -0600

    This is the commit message for the revision.
    ----------------------------------------------------------------------
    > svk log --output std
    ...

=head1 DESCRIPTION

The Std filter is the standard output filter for displaying log messages.  The
log format is designed to be similar to the output of Subversion's log
command.  Two arguments to the log command modify the standard output format.

=head2 quiet

Providing this command-line option to the log command prevents the contents of
the log message from being displayed.  All other information is displayed as
usual.

=head2 verbose

Providing this command-line option to the log command displays history
information for each revision.  The history includes the kind of modification
(modify, add, delete) and any copy history for each path that was modified in
the revision.


=head1 STASH/PROPERTY MODIFICATIONS

Std leaves all properties and the stash intact.

=head1 AUTHORS

Michael Hendricks E<lt>michael@ndrix.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2006 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
