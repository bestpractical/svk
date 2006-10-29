package SVK::Path::Checkout;
use strict;
use SVK::Version;  our $VERSION = $SVK::VERSION;

use base 'SVK::Accessor';

use SVK::Path;

__PACKAGE__->mk_shared_accessors(qw(xd));
__PACKAGE__->mk_clonable_accessors(qw(report source copath_anchor copath_target));
__PACKAGE__->mk_accessors(qw(_pool _inspector));

use Class::Autouse qw(SVK::Editor::XD SVK::Root::Checkout);

use autouse 'SVK::Util' => qw( get_anchor catfile abs2rel get_encoder to_native );

=head1 NAME

SVK::Path::Checkout - SVK path class associating a checkout

=head1 SYNOPSIS

 See below

=head1 DESCRIPTION

The class represents a node in svk depot, associated with a checkout
copy.

=cut

sub real_new {
    my $class = shift;
    my $self = $class->SUPER::real_new(@_);
    unless (ref $self->report) {
	$self->report($self->_to_pclass($self->report))
	    if defined $self->report && length $self->report;
    }
    return $self;
}

sub root {
    my $self = shift;
    my $root = SVK::Root::Checkout->new({ path => $self });
    # XXX: It might not always be the case that we hold svk::path object
    # when using the root.
    use Scalar::Util 'weaken';
    weaken $root->{path};
    return $root;
}

sub create_xd_root {
    my $self = shift;
    my $copath = $self->copath($self->copath_target);

    my (undef, $coroot) = $self->xd->{checkout}->get($copath);
    Carp::cluck $copath.YAML::Syck::Dump($self->xd->{checkout}) unless $coroot;
    my @paths = $self->xd->{checkout}->find($coroot, {revision => qr'.*'});
    my $tmp = $copath;
    $tmp =~ s/^\Q$coroot//;
    my $coroot_path = $self->path;
    $coroot_path =~ s/\Q$tmp\E$// or return $self->source->root;
    $coroot_path = '/' unless length $coroot_path;

    my $base_root = $self->source->root;
    return $base_root if $#paths <= 0;

    my $pool = SVN::Pool->new;
    my ($root, $base_rev);
    for (@paths) {
	$pool->clear;
	my $cinfo = $self->xd->{checkout}->get($_);
	my $path = abs2rel($_, $coroot => $coroot_path, '/');
	unless ($root) {
	    $root = $base_root->txn_root($self->pool);;
	    $base_rev = $base_root->node_created_rev($path, $pool);
	    if ($base_rev == 0) {
		# for interrupted checkout, the anchor will be at rev 0
		my @path = ();
		for my $dir (File::Spec::Unix->splitdir($path)) {
		    push @path, $dir;
		    next unless length $dir;
		    $root->make_dir(File::Spec::Unix->catdir(@path));
		}
	    }
	    next;
	}
	my $parent = Path::Class::File->new_foreign('Unix', $path)->parent;
	next if $cinfo->{revision} == $root->node_created_rev("$parent", $pool);
	my ($fromroot, $frompath) = $base_root->get_revision_root($path, $cinfo->{revision}, $pool);
	$root->delete($path, $pool)
	    if eval { $root->check_path ($path, $pool) != $SVN::Node::none };
	unless ($cinfo->{'.deleted'}) {
	    if ($frompath eq $path) {
		SVN::Fs::revision_link( $fromroot->root,
					$root->root, $path, $pool );
	    }
	    else {
		SVN::Fs::copy( $fromroot->root, $frompath,
			       $root->root, $path, $pool );
	    }
	}
    }
    return $root;
}

=head2 copath

Return the checkout path of the target, optionally with additional
path component.

=cut

my $_copath_catsplit = $^O eq 'MSWin32' ? \&catfile :
sub { defined $_[0] && length $_[0] ? "$_[0]/$_[1]" : "$_[1]" };

sub copath {
    my $self = shift;
    my $copath = ref($self) ? $self->copath_anchor : shift;
    my $paths = shift;
    return $copath unless defined $paths && length $paths;
    return $_copath_catsplit->($copath, $paths);
}

sub report { __PACKAGE__->make_accessor('report')->(@_) }

sub report_copath {
    my ($self, $copath) = @_;
    my $report = length($self->report) ? $self->report : undef;
    my $rel = abs2rel( $copath, $self->copath_anchor => $report );
    # XXX: abs2rel from F::S already does this.  tweak S::U abs2rel
    # and usage properly
    return length $rel ? $rel : '.';
}

sub copath_targets {
    my $self = shift;
    return $self->copath unless exists $self->source->{targets}[0];
    my $enc = get_encoder;
    return map { $self->copath($_) }
        map {my $t = $_; to_native($t, 'path', $enc); $t }
            @{$self->source->{targets}};
}

sub contains_copath {
    my ($self, $copath) = @_;
    foreach my $base ($self->copath_targets) {
	if ($copath ne abs2rel( $copath, $base) ) {
	    return 1;
	}
    }
    return 0;
}

sub descend {
    my ($self, $entry) = @_;
    $self->source->descend($entry);

    to_native($entry, 'path');
    $self->copath_anchor(catfile($self->copath_anchor, $entry));

    $self->report( catfile($self->report, $entry) );
    return $self;
}

sub anchorify {
    my ($self) = @_;
    $self->source->anchorify;
    # XXX: waiting for new path::class
    # $self->copath_anchor($self->_to_pclass($self->copath_anchor))
    #     unless ref($self->copath_anchor);
    # $self->copath_target($self->copath_anchor->basename);
    # $self->copath_anchor($self->copath_anchor->parent);
    my ($copath_anchor, $copath_target) = get_anchor(1, $self->copath_anchor);
    $self->copath_anchor($copath_anchor);
    $self->copath_target($copath_target);

    if (defined $self->report) {
	$self->report($self->_to_pclass($self->report))
	    unless ref($self->report);
	$self->report($self->report->parent);
    }

}

sub _get_inspector {
    my $self = shift;
    return SVK::Inspector::Root->new
	({ root => $self->root,
	   anchor => $self->path_anchor,
	   _pool => $self->pool,
	 });
}

sub as_depotpath {
    my $self = shift;
    return $self->source->new( defined $_[0] ? (revision => $_[0]) : () );
}

sub refresh_revision {
    my $self = shift;
    $self->source->refresh_revision;
    $self->_inspector(undef);
    return $self;
}

# XXX:
for my $pass_through (qw/pool inspector _to_pclass dump copy_ancestors _copy_ancestors nearest_copy is_merged_from/) {
    no strict 'refs';
    no warnings 'once';
    *{$pass_through} = *{'SVK::Path::'.$pass_through};
}

for my $proxy (qw/same_repos same_source is_mirrored normalize path universal contains_mirror depot depotpath depotname related_to copied_from search_revision merged_from revision repos path_anchor path_target repospath as_url/) {
    no strict 'refs';
    *{$proxy} = sub { my $self = shift;
		      Carp::confess unless $self->source;
		      $self->source->$proxy(@_);
		  };
}

sub for_checkout_delta {
    my $self = shift;
    my $source = $self->source;
    return ( copath => $self->copath,
	     path => $source->path_anchor,
	     targets => $source->{targets},
	     repos => $source->repos,
	     repospath => $source->repospath,
	     report => $self->report,
	   )
}

=head2 get_editor

Returns the L<SVK::Editor::XD> object, L<SVK::Inspector>, and the callback 
hash used by L<SVK::Editor::Merge>

=cut

sub get_editor {
    my ($self, %arg) = @_;
    my ($copath, $path, $spath) = ($self->copath_anchor, $self->path_anchor, $arg{store_path});
    $spath = $path unless defined $spath;
    my $encoding = $self->xd->{checkout}->get($copath)->{encoding};
    $path = '' if $path eq '/';
    $spath = '' if $spath eq '/';
    $encoding = Encode::find_encoding($encoding) if $encoding;
    $arg{get_path} = sub { $_[0] = "$path/$_[0]" };
    $arg{get_store_path} = sub { $_[0] = "$spath/$_[0]" };
    my $xdroot = $self->create_xd_root;
    $arg{oldroot} ||= $xdroot;
    $arg{newroot} ||= $xdroot;
    my $storage = SVK::Editor::XD->new (%arg,
					get_copath =>
            sub { to_native ($_[0], 'path', $encoding) if $encoding;
                  $_[0] = $self->copath($_[0]) },
					repos => $self->repos,
					target => $self->path_target,
					xd => $self->xd);
    my $inspector = $self->inspector;

    return ($storage, $inspector,
        cb_rev => sub {
            my ($path) = @_;
            my $copath;
            ($path,$copath) = $self->_get_paths($path);
            return $self->xd->{checkout}->get($copath)->{revision};
        },

        cb_conflict => sub {
            my ($path) = @_;
            my $copath;
            ($path, $copath) = $self->_get_paths($path);
            $self->xd->{checkout}->store ($copath, {'.conflict' => 1})
                unless $arg{check_only};
        },
        cb_add_merged => sub { 
            return if $arg{check_only};
            my ($path) = @_;
            my $copath;
            ($path, $copath) = $self->_get_paths($path);
            my $entry = $self->xd->{checkout}->get($copath);
            $self->xd->{checkout}->store( $copath, { '.schedule' => undef } );
	},
        cb_prop_merged => sub { 
            return if $arg{check_only};
            my ($path, $name) = @_;
            my $copath;
            ($path, $copath) = $self->_get_paths($path);
            my $entry = $self->xd->{checkout}->get ($copath);
            warn $entry unless ref $entry eq 'HASH';
            my $prop = $entry->{'.newprop'};
            delete $prop->{$name};
            $self->xd->{checkout}->store ($copath, {'.newprop' => $prop,
                         keys %$prop ? () :
                         ('.schedule' => undef)}
                        );
        });

}

sub _get_paths {
    my ($self, $path) = @_;
    $path = $self->inspector->translate($path);
    my $copath = $self->copath($path);
    $path = length $path ? $self->path_anchor."/$path" : $self->path_anchor;

    return ($path, $copath);
}

sub prev {
    my $self = shift;
    return $self->source;
}

=head1 SEE ALSO

L<SVK::Path>

=head1 AUTHORS

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-2005 by Chia-liang Kao E<lt>clkao@clkao.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut

1;
