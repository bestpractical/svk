package SVK::Log::Filter;

use SVK::I18N;
use base qw( Exporter );
our @EXPORT = qw( SELF STASH REV PATHS PROPS pipeline );

# order of parameters to the revision() sub. (inlined by compiler)
sub SELF  () { 0 }
sub STASH () { 1 }
sub REV   () { 2 }
sub PATHS () { 3 }
sub PROPS () { 4 }

# construct a new SVK::Log::Filter object by constructing the specific filters
# that will handle the details and prepare for the first revision.
sub new {
    my ($proto, %args) = @_;

    # make the presentation object
    my ( $class, $argument ) = split_filter( $args{presentation} || 'std' );
    $args{presentation} = {};
    $args{presentation}{object}   = build_filter_object($class);
    $args{presentation}{argument} = $argument;

    # make the selection pipeline
    my @selectors = split_selectors( $args{selection} || '' );
    $args{selection} = [];
    for my $selector (@selectors) {
        my ( $class, $argument ) = split_filter($selector);

        my %details;
        $details{object}   = build_filter_object($class);
        $details{argument} = $argument;

        push @{ $args{selection} }, \%details;
    }

    # populate the stash with values the filters may want
    $args{indent} = ' ' x ( $args{indent} || 0 );
    $args{stash} = {
        quiet         => $args{quiet},
        verbose       => $args{verbose},
        get_remoterev => $args{get_remoterev},
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

# make ourselves a base class of the package that imported us and
# import some constants and subroutines into that namespace
sub import {
    my $pkg = $_[0];  # leave package in @_ for goto()

    # make ourselves a base class
    my $inheritor = caller;
    push @{ $inheritor . '::ISA' }, $pkg;

    # install subs into our derived class using Exporter::import
    goto \&Exporter::import;
}

# generate exceptions which control the filter pipeline.  The wording is just
# so that we can distinguish our control exceptions from real exceptions
sub pipeline {
    my ($command) = @_;
    die "pipeline, $command please";
}

# Examine an exception to determine if it's a pipeline control exception.
# If it is, return the desired pipeline command.  If it's not, rethrow the
# exception.  If no exception is provided, the command 'continue' is retured.
sub get_pipeline_command {
    my ($exception) = @_;
    return 'continue' if !$exception;

    my ($command) = $exception =~ /\Apipeline, (\w+) please/;
    return $command if $command;

    die $exception;  # rethrow other exceptions
}

# Split a string into a filter name and an arbitrary argument string.
sub split_filter {
    my ($raw_filter) = @_;
    my ($class, $argument) = split(/\s+/, $raw_filter, 2);
    $argument = q{} if !defined $argument;
    return ($class, $argument);
}

# Split the description of the selection filter pipeline into individual
# filter names and their arguments.  Each filter is separated by a '|'
# character.  Literal pipe characters are included with '\|'
sub split_selectors {
    my ($raw_pipeline) = @_;

    # split on '|' characters that are not preceded by a '\'
    my @selectors = map { my $a = $_; $a =~ s/\\ \|/|/gxms; $a }
                    split /\s* (?<!\\) [|] \s*/xms, $raw_pipeline;
    return @selectors;
}

# Given the name of a filter, try and construct an appropriate filter object.
# Search @INC for modules that match the name given.  If no appropriate
# classes are available, we die with an appropriate warning.
#
# Although this method creates a Perl object for the filter, none of the
# filter implementation's code is actually invoked (unless of course, the
# filter implementation uses BEGIN blocks).
sub build_filter_object {
    my ($class) = @_;

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

    # success! make the new object from a scalar reference
    return bless \my($anon_scalar), $found;
}

# given the name of a log filter class, returns a list with paths to all
# modules which might implement that filter class.  We do this instead
# of simply C< eval "require $attempt" > because of case-sensitivity issues
# (this approach should also be more amenable to future updates)
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

# SVK::Command::Log calls this routine when it wants to display (or process) a
# revision.  The method then dispatches the information to the methods of the
# necessary filter objects to perform the real work.
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

# handle initial set up for the output/presentation filter
# this should only be called once during SVK::Log::Filter's lifetime
sub set_up_presentation {
    my ($self) = @_;
    my $stash  = $self->{stash};

    my $presentation = $self->{presentation};
    my ( $presenter, $argument ) = @{ $presentation }{qw/ object argument /};

    $stash->{argument} = $argument;
    $presenter->setup($stash);
    $presenter->header($stash);
    delete $stash->{argument};

    return;
}

# handle initial set up for the selection filter pipeline
# this should only be called once during SVK::Log::Filter's lifetime
sub set_up_selection {
    my ($self) = @_;
    my $stash  = $self->{stash};

    my $selectors = $self->{selection};
    for my $selection (@$selectors) {
        my ( $selector, $argument ) = @{ $selection }{qw/ object argument /};

        $stash->{argument} = $argument;
        $selector->setup($stash);
        $selector->header($stash);
    }

    delete $stash->{argument};
    return;
}

# Send a revision down the pipeline.  Provide revision information to the
# revision() method of each filter in the pipeline until one of them says to
# stop.  Then return the pipeline command.
sub run_pipeline {
    my ($self, $rev, $changed_paths, $props) = @_;

    my $stash     = $self->{stash};
    my $selectors = $self->{selection};

    # catch pipeline exceptions since they have the commands
    local $@;
    eval {
        for my $selection (@$selectors) {
            my $selector = $selection->{object};
            $selector->revision( $stash, $rev, $changed_paths, $props );
        }
    };
    return get_pipeline_command($@);
}

# Process the revision information for output.
sub present_revision {
    my ($self, $rev, $changed_paths, $props) = @_;

    my $stash = $self->{stash};
    my $presenter = $self->{presentation}{object};
    $presenter->revision( $stash, $rev, $changed_paths, $props );

    return;
}

# Tell all the filters that their jobs are done by calling footer() and
# teardown() on each one.
sub finished {
    my ($self) = @_;

    my $stash = $self->{stash};
    my $presenter = $self->{presentation}{object};
    my $selectors = $self->{selection};

    # run the footer() method for each filter
    $_->{object}->footer($stash) for @$selectors;    # a bit meaningless
    $presenter->footer($stash);

    # run the teardown() method for each filter
    $_->{object}->teardown($stash) for @$selectors;
    $presenter->teardown($stash);

    return;
}

# empty implementations so derived classes only have to implement
# the methods that need
sub setup    { 1 }
sub header   { 1 }
sub footer   { 1 }
sub teardown { 1 }
sub revision { 1 }


1;

__END__

=head1 NAME

SVK::Log::Filter - base class for all log filters

=head1 DESCRIPTION

WARNING: C<use>ing this module pollutes your namespace by default.

SVK::Log::Filter provides a general way to handle revision properties so that
they may be displayed or otherwise processed.  The SVK "log" command uses
filter objects to handle the details of processing the revision properties.
The bulk of this document explains how to write log filters.

A log filter is just a Perl object with special methods.  At specific points
while processing log information, SVK will call these methods on the filter
object.  SVK::Log::Filter provides sensible defaults for each of these
methods.  The methods (in order of invocation) are L</setup>, L</header>,
L</revision>, L</footer>, L</teardown>. Each is fully documented in the
section L</METHOD REFERENCE>.


=head1 TUTORIAL

Although log filters which output and log filters which select are exactly the
same kind of objects, they are genearlly conceptualized separately.  The
following tutorial provides a simple example for each type of filter.

=head2 OUTPUT

For our simple output filter example, we want to display something like the following

    1. r3200 by john
    2. r3194 by tom
    3. r3193 by larry

Namely, the number the revisions we've seen, then show the actual revision
number from the repository and indicate the author of that revision.   We want
this log filter to be accessible by a command like "svk log --output list"
The code to accomplish that is

   1   package SVK::Log::Filter::List;
   2   use SVK::Log::Filter;
       
   3   sub setup {
   4       my ($stash) = $_[STASH];
   5       $stash->{list_count} = 1;
   6   }
       
   7   sub revision {
   8       my ($stash, $rev, $props) = @_[STASH, REV, PROPS];
       
   9       printf "%d. r%d by %s\n",
  10           $stash->{list_count}++,
  11           $rev,
  12           $props{'svn:author'}
  13       ;
  14   }

First, we must establish the name of this filter.  SVK looks for filters with
the namespace prefix SVK::Log::Filter.  The final portion of the name can
either have the first letter capitalized or all the letters capitalized.  On
line 2, we use SVK::Log::Filter which quietly makes itself one of our base
classes.  If you had tried C<use base qw( SVK::Log::Filter )> the filter would
not have worked correctly.  That's because SVK::Log::Filter also imports some
constants into the namespace of its derived classes.

On lines 3-6, we get to the first real meat.  Since we want to count the
revisions that we see, we have to store the information somewhere that will
persist between method calls.  That's the purpose of the "stash."  The stash
is simply a hash reference in which log filters may store information. Every
filter method invoked by SVK's log command is given a reference to the stash.
To get a reference to the stash, simply use the C<STASH> constant to acces the
C<@_> array.  Once we have a reference to the stash, we initialize the value
of 'list_count' to 1.  This is where we'll store the number for the next
revision that we'll see.  We use the name 'list_count' to avoid name conflicts
with other filters in the pipeline. Remember that anything you put in the
stash is accessible to filters downstream in the pipeline.  That means that
the stash provides a way for one filter to communicate arbitrary information
to other filters.  Finally, on line 6, our C<setup> method is finished.  The
return value of the method is irrelevant.

The C<revision> method on lines 7-14 does the real work of the filter.  First
(line 8) it uses the constants STASH, REV and PROPS to get the stash, revision
number and properties for this revision.  The it simply prints whatever it
wants to display.  SVK takes care of directing output to the appropriate
place.  You'll notice that the revision properties are provided as a hash.
The key of the hash is the name of the property and the value of the hash is
the value of the property.

That's it.  Put SVK::Log::Filter::List somewhere in C<@INC> and SVK will find
it.

=head2 SELECTION

The simple selection filter example will pass revisions based on whether the
revision number is even or odd.  The filter accepts a single argument 'odd' or
'even' indicating which revisions should be passed down the pipeline.
Additionally, if the filter ever encounters the revision number "42" it will
stop the entire pipeline and process no more revisions.  The invocation is
something like "svk log --filter 'parity even'" to display all even revisions.

   1   package SVK::Log::Filter::Parity;
   2   use SVK::Log::Filter;
       
   3   sub setup {
   4       my ($stash) = $_[STASH];
       
   5       my $argument = lc( $stash->{argument} );
   6       $stash->{parity_bit} = $argument eq 'even' ? 0
   7                            : $argument eq 'odd'  ? 1
   8                            : die "Parity argument not 'even' or 'odd'\n"
   9                            ;
  10   }
       
  11   sub revision {
  12       my ($stash, $rev) = @_[STASH, REV];
       
  13       pipeline('last') if $rev == 42;
  14       pipeline('next') if $rev % 2 != $stash->{parity};
  15   }

There are only a few differences between this implementation and the output
filter implementation.  The first difference is in line 5.  When C<setup> is
invoked, the stash always has a key 'argument' which contains the command-line
argument provided to your filter.  In this case, the argument should be either
'even' or 'odd'.  Based on the argument, we initialize the stash to remind us
what parity we're looking for.

The unique characteristics of C<revision> are the calls to the C<pipeline>
subroutine in lines 13 and 14.  If we want to stop the pipeline entirely, call
C<pipeline> with the argument 'last'.  The current revision and all subsequent
revisions will not be display.  If the argument to C<pipeline> is 'next', the
current revision will not be displayed and the pipeline will proceed with the
next revision in sequence.  If you don't call C<pipeline>, the current
revision is passed down the remainder of the pipeline so that it can be
processed and displayed.

=head1 EXPORTED CONSTANTS/SUBROUTINES

This is a list of all the constants and subroutines that L<SVK::Log::Filter>
exports into the namespace of log filter classes.  The constants are used to
slice the C<@_> array to access arguments to the filter methods.

=head2 pipeline

This is the only subroutine exported by SVK::Log::Filter.  It's used to
control the behavior of the filter pipeline.  It accepts a single scalar as
the argument.  If the argument is 'next', the pipeline stops processing the
current revision (including any output filter) and starts processing the next
revision starting over at the beginning of the pipeline.  If the argument to
C<pipeline> is 'last', the pipeline is stopped entirely (including any output
filters).  Once the pipeline has stopped, the SVK log command finishes any
final details and stops.

=head2 PATHS

Provided to : C<revision>

The value of the PATHS argument is an L<SVK::Log::ChangedPaths> object.
The object provides methods for indicating which paths were changed by this
revision and approximately how they were changed (modified file contents,
modified file properties, etc.)

See the documentation for SVK::Log::ChangedPaths for more details.

=head2 REV

Provided to : C<revision>

The value of the REV argument is the Subversion revision number for the
current revision.

=head2 PROPS

Provided to : C<revision>

The value of the PROPS argument is a hash reference containing all the
revision properties for the current revision.  The keys of the hash are the
property names and the values of the hash are the property values.  For
example, the author of a revision is available with
C<< $_[PROPS]->{'svn:author'} >>.

If you change values in the PROPS hashref, those changes are visible to all
subsequent filters in the pipeline.  This can be useful and dangerous.
Dangerous if you accidentally modify a property, useful if you intentionally
modify a property.  For instance, it's possible to make a "selection" filter
which uses Babelfish L<http://babelfish.altavista.com/> to translate log
messages from one language to another.  By modifying the 'svn:log' property,
other log filters can operate on the translated log message without knowing
that it's translated.

=head2 STASH

Provided to : C<header>, C<footer>, C<revision>, C<setup>, C<teardown>

The value of the STASH argument is a reference to a hash.  The stash persists
throughout the entire log filtering process.  It may be used to store
arbitrary information across method calls and to pass information from one
filter to another filter in the pipeline.

When creating new keys in the stash, it's important to avoid unintentional
name collisions with other filters in the pipeline.  The best practice is to
preface the name of each key with the name of your filter ("myfilter_key") or
to create your own hash reference inside the stash
(C<< $stash->{myfilter}{key} >>).  If your filter puts information into the
stash which other filters may want to access, please document the location of
that information in the stash.

=head1 METHOD REFERENCE

The following are methods of SVK::Log::Filter subclasses.  When defining a
subclass, one need only override those methods that are necessary for
implementing the filter.  All methods have sensible defaults (namely, do
nothing).  The methods are listed here in the order in which they are called.

=head2 setup

This method is called once just before the filter is used for the first time.
This is the place to initialize the stash, process command-line arguments,
read configuration files, connect to a database, etc.

=head2 header

This method is called once just before the first revision is processed but
after C<setup> has completed.  This is an ideal place to display information
which should appear at the top of the log display.

=head2 revision

This method is called for each revision that SVK wants to process.  The bulk
of a log filter's code goes towards implementing this method.  Output filters
may simply print the information that they want displayed.  Other filters
should either modify the revision properties (see L</PROPS>) or use pipeline
commands (see L</pipeline>) to skip irrelevant revisions.

=head2 footer

This method is similar to the C<header> method, but it's called once after all
the revisions have been displayed.  This is the place to do any final output.

=head2 teardown

This method is called once just before the log filter is discarded.  This is
the place to disconnect from databases, close file handles, etc.

=head1 STASH REFERENCE

=head1 argument

This key (and associated value) is only present in the stash when the
L</setup> method is called.  The value of the key is the text provided to the
log filter during command-line invocation.  Any leading or trailing whitespace
is stripped from the argument.  If no argument was provided, the value will be
the empty string.

For example, if the command invocation were "svk log --filter 'foo bar etc   '",
the value of the "argument" key would be "foo bar etc"

=head1 get_remoterev

If the value of this key is true, the value is a coderef.  When the coderef is
invoked with a single revision number as the argument, it returns the number
of the equivalent revision in the upstream repository.  The value of this key
may be undefined if the logs are being processed for something other than a
mirror.  The following code may be useful when working with "get_remoterev"

    my ($stash, $rev) = @_[STASH, REV];
    my $get_remoterev = $stash->{get_remoterev};
    my $remote_rev = $get_remoterev ? $get_remoterev->($rev) : 'unkown';
    print "The remote revision for r$rev is $remote_rev.\n";

=head1 quiet

If the user included the "--quiet" flag when invoking "svk log" the value of
this key will be a true value.  Otherwise, the value will be false.

=head1 verbose

If the user included the "--verbose" flag when invoking "svk log" the value of
this key will be a true value.  Otherwise, the value will be false.

=head1 AUTHORS

Michael Hendricks E<lt>michael@palmcluster.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
