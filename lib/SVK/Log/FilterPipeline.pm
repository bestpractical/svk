package SVK::Log::FilterPipeline;
use strict;
use warnings;

use SVK::I18N;

sub new {
    my ($proto, %args) = @_;

    # make the presentation filter object
    my ( $class, $argument ) = split_filter( $args{presentation} || 'std' );
    $args{presentation} = {};
    $args{presentation}{object} = build_filter_object($class, $argument);

    # make the selection filter pipeline
    my @selectors = split_selectors( $args{selection} || '' );
    $args{selection} = [];
    for my $selector (@selectors) {
        my ( $class, $argument ) = split_filter($selector);

        my %details;
        $details{object} = build_filter_object($class, $argument);

        push @{ $args{selection} }, \%details;
    }

    # populate the stash with values the filters may want
    $args{indent} = ' ' x ( $args{indent} || 0 );
    $args{stash} = {
        quiet         => $args{quiet},
        verbose       => $args{verbose},
        host          => $args{host} || '',

        # specific to Std filter, yuck!
        indent        => $args{indent},
        verbatim      => $args{verbatim},
        no_sep        => $args{no_sep},
        remote_only   => $args{remote_only},
    };
    $args{output} ||= select;

    # next call to filter() will be the first time
    $args{first_time} = 1;

    return bless \%args, ( $proto );
}

sub get_pipeline_command {
    my ($exception) = @_;
    return 'continue' if !$exception;

    my ($command) = $exception =~ /\Apipeline, (\w+) please/;
    return $command if $command;

    die $exception;  # rethrow other exceptions
}

sub split_filter {
    my ($raw_filter) = @_;
    my ($class, $argument) = split(/\s+/, $raw_filter, 2);
    $argument = q{} if !defined $argument;
    return ($class, $argument);
}

sub split_selectors {
    my ($raw_pipeline) = @_;

    # split on '|' characters that are not preceded by a '\'
    my @selectors = map { my $a = $_; $a =~ s/\\ \|/|/gxms; $a }
                    split /\s* (?<!\\) [|] \s*/xms, $raw_pipeline;
    return @selectors;
}

sub build_filter_object {
    my ($class, $argument) = @_;

    # try to locate the log filter implementation
    my $found;
    ATTEMPT:
    for my $attempt ( _find_candidate_modules($class) ) {
        if ( eval { require $attempt } ) {
            $found = $attempt;
            last ATTEMPT;
        }
    }

    # hmm, no luck
    die loc("Can't load log filter '$class'.\n") if !$found;

    # convert $found from a path to a package name
    my (undef, undef, $filename) = File::Spec->splitpath($found);
    $filename =~ s/.pm\z//xms;
    $found = "SVK::Log::Filter::$filename";

    # success! make the new object
    return $found->new($argument);
}

# given the name of a log filter class, returns a list with paths to all
# modules which might implement that filter class.  We do this instead
# of simply C< eval "require $attempt" > because of case-sensitivity issues
# This technique allows us to later specify paths outside @INC to search
# for filter implementations (from a config file or something)
sub _find_candidate_modules {
    my ($class) = @_;

    require File::Spec;
    require File::Find;

    # make a list of directories where the module might be hiding
    my @haystack =
        grep { -d $_ } 
        map  { File::Spec->catfile($_, qw(SVK Log Filter)) }
        @INC;

    # search all the directories for possible implementations
    my $needle = lc($class) . '.pm';
    my @candidates;
    File::Find::find(
        sub {
            # XXX descending directories might be wrong
            return unless -f $_;
            push @candidates, $File::Find::name if lc($_) eq $needle;
        },
        @haystack,
    );

    return @candidates;
}

sub filter {
    my ($self, %args) = @_;

    # extract our arguments
    my ($rev, $root, $props) = @args{qw/rev root props/};

    # ignore this revision if necessary
    my $suppress = $self->{suppress};
    return if $suppress && $suppress->($rev);

    # select the proper output location
    my $oldfh = select $self->{output};

    # handle setup and header
    if ( $self->{first_time} ) {
        $self->set_up_selection();
        $self->set_up_presentation();
        $self->{first_time} = 0;
    }

    # process the selection pipeline and output the revision
    require SVK::Log::ChangedPaths;
    my $changed_paths = SVK::Log::ChangedPaths->new($root);
    my $cmd = $self->run_pipeline( $rev, $changed_paths, $props );
    if ( $cmd eq 'next' ) { select $oldfh; return 1; }
    if ( $cmd eq 'last' ) { select $oldfh; return 0; }
    $self->present_revision( $rev, $changed_paths, $props );

    # restore the previous output location
    select $oldfh;

    return 1;
}

sub set_up_presentation {
    my ($self) = @_;

    my $stash  = $self->{stash};
    my $presenter = $self->{presentation}{object};
    $presenter->setup({ stash => $stash });
    $presenter->header({ stash => $stash });

    return;
}

sub set_up_selection {
    my ($self) = @_;

    my $stash  = $self->{stash};
    my $selectors = $self->{selection};
    for my $selection (@$selectors) {
        my $selector = $selection->{object};
        $selector->setup({ stash => $stash });
        $selector->header({ stash => $stash });
    }

    return;
}

sub run_pipeline {
    my ($self, $rev, $changed_paths, $props) = @_;

    my $stash     = $self->{stash};
    my $selectors = $self->{selection};

    # catch pipeline exceptions since they have the commands
    local $@;
    eval {
        for my $selection (@$selectors) {
            my $selector = $selection->{object};
            $selector->revision({
                stash => $stash,
                rev   => $rev,
                paths => $changed_paths,
                props => $props,
                get_remoterev => $self->{get_remoterev},
            });
        }
    };
    return get_pipeline_command($@);
}

sub present_revision {
    my ($self, $rev, $changed_paths, $props) = @_;

    my $stash = $self->{stash};
    my $presenter = $self->{presentation}{object};
    $presenter->revision({
        stash => $stash,
        rev   => $rev,
        paths => $changed_paths,
        props => $props,
        get_remoterev => $self->{get_remoterev},
    });

    return;
}

sub finished {
    my ($self) = @_;

    my $stash = $self->{stash};
    my $presenter = $self->{presentation}{object};
    my $selectors = $self->{selection};

    # run the footer() method for each filter
    $_->{object}->footer({ stash => $stash }) for @$selectors;
    $presenter->footer({ stash => $stash });

    # run the teardown() method for each filter
    $_->{object}->teardown({ stash => $stash }) for @$selectors;
    $presenter->teardown({ stash => $stash });

    return;
}

1;

__END__

=head1 NAME

SVK::Log::FilterPipeline - a pipeline of log filter objects

=head1 DESCRIPTION

An SVK::Log::FilterPipeline represents a particular collection of log filter
objects each of which needs to be called in turn.

=head1 METHODS

=head2 new

Construct a new L<SVK::Log::FilterPipeline> object by constructing the
specific filters that will handle the details and preparing for the first
revision.

=head2 build_filter_object

Given the name of a filter, try and construct an appropriate filter object.
Search C<@INC> for modules that match the name given.  If no appropriate classes
are available, we die with an appropriate warning.

This method creates an object for the filter by calling its new() method

=head2 filter

SVK::Command::Log calls this routine when it wants to display (or process) a
revision.  The method then dispatches the information to the methods of the
necessary filter objects in the pipeline to perform the real work.

=head2 finished

Tell all the filters that their jobs are done by calling C<footer> and
C<teardown> on each one.

=head2 get_pipeline_command

Examine an exception to determine if it's a pipeline control exception.  If it
is, return the desired pipeline command.  If it's not, rethrow the exception.
If no exception is provided, the command 'continue' is returned.

=head2 present_revision

Display a single revision by passing it to the pipeline's presentation filter.

=head2 run_pipeline

Send a revision down the pipeline.  Provide revision information to the
revision() method of each filter in the pipeline until one of them says to
stop.  Then return the pipeline command.

=head2 set_up_presentation

Handle initial set up for the presentation filter.  This should only be called
once during an L<SVK::Log::FilterPipeline>'s lifetime.

=head2 set_up_selection

Handle initial set up for the selection filter pipeline.  This should only be
called once during C<SVK::Log::FilterPipeline>'s lifetime.

=head2 split_filter

Split a string into a filter name and an arbitrary argument string.

=head2 split_selectors

Split the description of the selection filter pipeline into individual filter
names and their arguments.  Each filter is separated by a '|' character.
Literal pipe characters are included with '\|'.

=head1 AUTHORS

Michael Hendricks E<lt>michael@ndrix.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2006 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
