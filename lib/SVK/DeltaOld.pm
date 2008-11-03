# BEGIN BPS TAGGED BLOCK {{{
# COPYRIGHT:
# 
# This software is Copyright (c) 2003-2006 Best Practical Solutions, LLC
#                                          <clkao@bestpractical.com>
# 
# (Except where explicitly superseded by other copyright notices)
# 
# 
# LICENSE:
# 
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of either:
# 
#   a) Version 2 of the GNU General Public License.  You should have
#      received a copy of the GNU General Public License along with this
#      program.  If not, write to the Free Software Foundation, Inc., 51
#      Franklin Street, Fifth Floor, Boston, MA 02110-1301 or visit
#      their web page on the internet at
#      http://www.gnu.org/copyleft/gpl.html.
# 
#   b) Version 1 of Perl's "Artistic License".  You should have received
#      a copy of the Artistic License with this package, in the file
#      named "ARTISTIC".  The license is also available at
#      http://opensource.org/licenses/artistic-license.php.
# 
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# CONTRIBUTION SUBMISSION POLICY:
# 
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of the
# GNU General Public License and is only of importance to you if you
# choose to contribute your changes and enhancements to the community
# by submitting them to Best Practical Solutions, LLC.)
# 
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with SVK,
# to Best Practical Solutions, LLC, you confirm that you are the
# copyright holder for those contributions and you grant Best Practical
# Solutions, LLC a nonexclusive, worldwide, irrevocable, royalty-free,
# perpetual, license to use, copy, create derivative works based on
# those contributions, and sublicense and distribute those contributions
# and any derivatives thereof.
# 
# END BPS TAGGED BLOCK }}}
package SVK::DeltaOld;
use strict;
use warnings;

use base 'Class::Accessor::Fast';
use SVK::I18N;
use SVK::Util qw(HAS_SYMLINK is_symlink get_encoder from_native to_native
                 md5_fh splitpath splitdir catdir abs2rel);
use autouse 'File::Find' => qw(find);
use SVK::Logger;

__PACKAGE__->mk_accessors(qw(xd checkout));

# XXX: checkout_delta is getting too complicated and too many options

# Here be dragon. below is checkout_delta related function.

sub _delta_rev {
    my ($self, $arg) = @_;
    my $entry = $arg->{cinfo};
    my $schedule = $entry->{'.schedule'} || '';
    # XXX: uncomment this as mutation coverage test
    # return  $entry->{revision};

    # Lookup the copy source rev for the case of open_directory inside
    # add_directotry with history.  But shouldn't do so for replaced
    # items, because the rev here is used for delete_entry
    my ($source_path, $source_rev) = $schedule ne 'replace' ?
	$self->xd->_copy_source($entry, $arg->{copath}) : ();
    ($source_path, $source_rev) = ($arg->{path}, $entry->{revision})
	unless defined $source_path;
    return $source_rev;

}

sub _delta_content {
    my ($self, %arg) = @_;

    my $handle = $arg{editor}->apply_textdelta ($arg{baton}, $arg{md5}, $arg{pool});
    return unless $handle && $#{$handle} > 0;

    if ($arg{send_delta} && $arg{base}) {
	my $spool = SVN::Pool->new_default ($arg{pool});
	my $source = $arg{base_root}->file_contents ($arg{base_path}, $spool);
	my $txstream = SVN::TxDelta::new
	    ($source, $arg{fh}, $spool);
	SVN::TxDelta::send_txstream ($txstream, @$handle, $spool);
    }
    else {
	SVN::TxDelta::send_stream ($arg{fh}, @$handle, SVN::Pool->new ($arg{pool}))
    }
}

sub _unknown_verbose {
    my ($self, %arg) = @_;
    my $ignore = $self->xd->ignore;
    # The caller should have processed the entry already.
    my %seen = ($arg{copath} => 1);
    my @new_targets;
    if ($arg{targets}) {
ENTRY:	for my $entry (@{$arg{targets}}) {
	    my $now = '';
	    for my $dir (splitdir ($entry)) {
		$now .= $now ? "/$dir" : $dir;
		my $copath = SVK::Path::Checkout->copath ($arg{copath}, $now);
		next if $seen{$copath};
		$seen{$copath} = 1;
		lstat $copath;
		unless (-e _) {
		    $logger->warn( loc ("Unknown target: %1.", $copath));
		    next ENTRY;
		}
		unless (-r _) {
		    $logger->warn( loc ("Warning: %1 is unreadable.", $copath));
		    next ENTRY;
		}
		$arg{cb_unknown}->($arg{editor}, catdir($arg{entry}, $now), $arg{baton});
	    }
	    push @new_targets, SVK::Path::Checkout->copath ($arg{copath}, $entry);
	}
	
	return unless @new_targets;
    }
    my $nentry = $arg{entry};
    to_native($nentry, 'path', $arg{encoder});
    find ({ preprocess => sub { sort @_ },
	    wanted =>
	    sub {
		$File::Find::prune = 1, return if m/$ignore/;
		my $copath = catdir($File::Find::dir, $_);
		return if $seen{$copath};
		my $schedule = $self->{checkout}->get ($copath)->{'.schedule'} || '';
		return if $schedule eq 'delete';
		my $dpath = abs2rel($copath, $arg{copath} => $nentry, '/');
		from_native($dpath, 'path');
		$arg{cb_unknown}->($arg{editor}, $dpath, $arg{baton});
	  }}, defined $arg{targets} ? @new_targets : $arg{copath});
}

sub _node_deleted {
    my ($self, %arg) = @_;
    $arg{rev} = $self->_delta_rev(\%arg);
    $arg{editor}->delete_entry (@arg{qw/entry rev baton pool/});

    if ($arg{kind} == $SVN::Node::dir && $arg{delete_verbose}) {
	foreach my $file (sort $self->{checkout}->find
			  ($arg{copath}, {'.schedule' => 'delete'})) {
	    next if $file eq $arg{copath};
	    $file = abs2rel($file, $arg{copath} => undef, '/');
	    from_native($file, 'path', $arg{encoder});
	    $arg{editor}->delete_entry ("$arg{entry}/$file", @arg{qw/rev baton pool/});
	}
    }
}

sub _node_deleted_or_absent {
    my ($self, %arg) = @_;
    my $schedule = $arg{cinfo}{'.schedule'} || '';

    if ($schedule eq 'delete' || $schedule eq 'replace') {
	my $should_do_delete = !$arg{_really_in_copy} || $arg{copath} eq ($arg{cinfo}{scheduleanchor} || '');
	$self->_node_deleted (%arg)
	    if $should_do_delete;
	# when doing add over deleted entry, descend into it
	if ($schedule eq 'delete') {
	    $self->_unknown_verbose (%arg)
		if $arg{cb_unknown} && $arg{unknown_verbose};
	    return $should_do_delete;
	}
    }

    if ($arg{type}) {
	if ($arg{kind} && !$schedule &&
	    (($arg{type} eq 'file') xor ($arg{kind} == $SVN::Node::file))) {
	    if ($arg{obstruct_as_replace}) {
		$self->_node_deleted (%arg);
	    }
	    else {
		$arg{cb_obstruct}->($arg{editor}, $arg{entry}, $arg{baton})
		    if $arg{cb_obstruct};
		return 1;
	    }
	}
    }
    else {
	# deleted during base_root -> xdroot
	if (!$arg{base_root_is_xd} && $arg{kind} == $SVN::Node::none) {
	    $self->_node_deleted (%arg);
	    return 1;
	}
	return 1 if $arg{absent_ignore};
	# absent
	my $type = $arg{kind} == $SVN::Node::dir ? 'directory' : 'file';

	if ($arg{absent_as_delete}) {
	    $arg{rev} = $self->_delta_rev(\%arg);
	    $self->_node_deleted (%arg);
	}
	else {
	    my $func = "absent_$type";
	    $arg{editor}->$func (@arg{qw/entry baton pool/});
	}
	return 1 unless $type ne 'file' && $arg{absent_verbose};
    }
    return 0;
}

sub _prop_delta {
    my ($baseprop, $newprop) = @_;
    return $newprop unless $baseprop && keys %$baseprop;
    return { map {$_ => undef} keys %$baseprop } unless $newprop && keys %$newprop;
    my $changed;
    for my $propname (keys %{ { %$baseprop, %$newprop } }) {
	# deref propvalue
	my @value = map { $_ ? ref ($_) ? '' : $_ : '' }
	    map {$_->{$propname}} ($baseprop, $newprop);
	$changed->{$propname} = $newprop->{$propname}
	    unless $value[0] eq $value[1];
    }
    return $changed;
}

sub _prop_changed {
    my ($root1, $path1, $root2, $path2) = @_;
    ($root1, $root2) = map {$_->isa ('SVK::Root') ? $_->root : $_} ($root1, $root2);
    # XXX: do better check for this case, or make this a root helper method.
    return 1 if $root1->isa('SVK::Root::Checkout') || $root2->isa('SVK::Root::Checkout');
    return SVN::Fs::props_changed ($root1, $path1, $root2, $path2);
}

sub _node_props {
    my ($self, %arg) = @_;
    my $schedule = $arg{cinfo}{'.schedule'} || '';
    my $props = $arg{kind} ? $schedule eq 'replace' ? {} : $arg{xdroot}->node_proplist ($arg{path}) :
	$arg{base_kind} ? $arg{base_root}->node_proplist ($arg{base_path}) : {};
    my $newprops = (!$schedule && $arg{auto_add} && $arg{kind} == $SVN::Node::none && $arg{type} eq 'file')
	? $self->xd->auto_prop ($arg{copath}) : $arg{cinfo}{'.newprop'};
    my $fullprop = SVK::XD::_combine_prop ($props, $newprops);
    if (!$arg{base} or $arg{in_copy}) {
	$newprops = $fullprop;
    }
    elsif (!$arg{base_root_is_xd} && $arg{base}) {
	$newprops = _prop_delta ($arg{base_root}->node_proplist ($arg{base_path}), $fullprop)
	    if $arg{kind} && $arg{base_kind} && _prop_changed (@arg{qw/base_root base_path xdroot path/});
    }
    return ($newprops, $fullprop)
}

sub _node_type {
    my $copath = shift;
    my $st = [lstat ($copath)];
    return '' if !-e _;
    unless (-r _) {
	$logger->warn( loc ("Warning: %1 is unreadable.", $copath));
	return;
    }
    return ('file', $st) if -f _ or is_symlink;
    return ('directory', $st) if -d _;
    $logger->warn( loc ("Warning: unsupported node type %1.", $copath));
    return ('', $st);
}

use Fcntl ':mode';

sub _delta_file {
    my ($self, %arg) = @_;
    my $pool = SVN::Pool->new_default (undef);
    my $cinfo = $arg{cinfo} ||= $self->{checkout}->get ($arg{copath});
    my $schedule = $cinfo->{'.schedule'} || '';
    my $modified;

    if ($arg{cb_conflict} && $cinfo->{'.conflict'}) {
	++$modified;
        $arg{cb_conflict}->($arg{editor}, $arg{entry}, $arg{baton}, $cinfo->{'.conflict'});
    }

    return 1 if $self->_node_deleted_or_absent (%arg, pool => $pool);

    my ($newprops, $fullprops) = $self->_node_props (%arg);
    if (HAS_SYMLINK && (defined $fullprops->{'svn:special'} xor S_ISLNK($arg{st}[2]))) {
	# special case obstructure for links, since it's not standard
	return 1 if $self->_node_deleted_or_absent (%arg,
						    type => 'link',
						    pool => $pool);
	if ($arg{obstruct_as_replace}) {
	    $schedule = 'replace';
	    $fullprops = $newprops = $self->xd->auto_prop($arg{copath}) || {};
	}
	else {
	    return 1;
	}
    }
    $arg{add} = 1 if $arg{auto_add} && $arg{base_kind} == $SVN::Node::none ||
	$schedule eq 'replace';

    my $fh = SVK::XD::get_fh ($arg{xdroot}, '<', $arg{path}, $arg{copath}, $fullprops);
    my $mymd5 = md5_fh ($fh);
    my ($baton, $md5);

    $arg{base} = 0 if $arg{in_copy} || $schedule eq 'replace';

    unless ($schedule || $arg{add} ||
	($arg{base} && $mymd5 ne ($md5 = $arg{base_root}->file_md5_checksum ($arg{base_path})))) {
	$arg{cb_unchanged}->($arg{editor}, $arg{entry}, $arg{baton},
			     $self->_delta_rev(\%arg)
			    ) if ($arg{cb_unchanged} && !$modified);
	return $modified;
    }

    $baton = $arg{editor}->add_file ($arg{entry}, $arg{baton},
				     $cinfo->{'.copyfrom'} ?
				     ($arg{cb_copyfrom}->(@{$cinfo}{qw/.copyfrom .copyfrom_rev/}))
				     : (undef, -1), $pool)
	if $arg{add};

    $baton ||= $arg{editor}->open_file ($arg{entry}, $arg{baton}, $self->_delta_rev(\%arg), $pool)
	if keys %$newprops;

    $arg{editor}->change_file_prop ($baton, $_, ref ($newprops->{$_}) ? undef : $newprops->{$_}, $pool)
	for sort keys %$newprops;

    if (!$arg{base} ||
	$mymd5 ne ($md5 ||= $arg{base_root}->file_md5_checksum ($arg{base_path}))) {
	seek $fh, 0, 0;
	$baton ||= $arg{editor}->open_file ($arg{entry}, $arg{baton}, $self->_delta_rev(\%arg), $pool);
	$self->_delta_content (%arg, baton => $baton, pool => $pool,
			       fh => $fh, md5 => $arg{base} ? $md5 : undef);
    }

    $arg{editor}->close_file ($baton, $mymd5, $pool) if $baton;
    return 1;
}

sub _delta_dir {
    my ($self, %arg) = @_;
    if ($arg{entry} && $arg{exclude} && exists $arg{exclude}{$arg{entry}}) {
	$arg{cb_exclude}->($arg{path}, $arg{copath}) if $arg{cb_exclude};
	return;
    }
    my $pool = SVN::Pool->new_default (undef);
    my $cinfo = $arg{cinfo} ||= $self->{checkout}->get ($arg{copath});
    my $schedule = $cinfo->{'.schedule'} || '';
    $arg{add} = 1 if $arg{auto_add} && $arg{base_kind} == $SVN::Node::none ||
	$schedule eq 'replace';

    # compute targets for children
    my $targets;
    for (@{$arg{targets} || []}) {
	my ($volume, $directories, $file) = splitpath ($_);
	if ( my @dirs = splitdir($directories) ) {
	    my $path = $volume . shift(@dirs);
            $file = catdir(grep length, @dirs, $file);
	    push @{$targets->{$path}}, $file
	}
	else {
	    $targets->{$file} = undef;
	}
    }
    my $thisdir;
    if ($targets) {
	if (exists $targets->{''}) {
	    delete $targets->{''};
	    $thisdir = 1;
	}
    }
    else {
	$thisdir = 1;
    }
    # don't use depth when we are still traversing through targets
    my $descend = defined $targets || !(defined $arg{depth} && $arg{depth} == 0);
    # XXX: the top level entry is undefined, which should be fixed.
    $arg{cb_conflict}->($arg{editor}, defined $arg{entry} ? $arg{entry} : '', $arg{baton}, $cinfo->{'.conflict'})
	if $thisdir && $arg{cb_conflict} && $cinfo->{'.conflict'};

    return 1 if $self->_node_deleted_or_absent (%arg, pool => $pool);
    # if a node is replaced, it has no base, unless it was replaced with history.
    $arg{base} = 0 if $schedule eq 'replace' && !$cinfo->{'.copyfrom'};
    my ($entries, $baton) = ({});
    if ($arg{add}) {
	$baton = $arg{root} ? $arg{baton} :
	    $arg{editor}->add_directory ($arg{entry}, $arg{baton},
					 $cinfo->{'.copyfrom'} ?
					 ($arg{cb_copyfrom}->(@{$cinfo}{qw/.copyfrom .copyfrom_rev/}))
					 : (undef, -1), $pool);
    }

    $entries = $arg{base_root}->dir_entries ($arg{base_path})
	if $arg{base} && $arg{base_kind} == $SVN::Node::dir;

    $baton ||= $arg{root} ? $arg{baton}
	: $arg{editor}->open_directory ($arg{entry}, $arg{baton},
					$self->_delta_rev(\%arg), $pool);

    # check scheduled addition
    # XXX: does this work with copied directory?
    my ($newprops, $fullprops) = $self->_node_props (%arg);

    if ($descend) {

    my $signature;
    if ($self->{signature} && $arg{base_root_is_xd}) {
	$signature = $self->{signature}->load ($arg{copath});
	# if we are not iterating over all entries, keep the old signatures
	$signature->{keepold} = 1 if defined $targets
    }

    # XXX: Merge this with @direntries so we have single entry to descendents
    for my $entry (sort keys %$entries) {
	my $newtarget;
	my $copath = $entry;
	if (defined $targets) {
	    next unless exists $targets->{$copath};
	    $newtarget = delete $targets->{$copath};
	}
	to_native ($copath, 'path', $arg{encoder});
	my $kind = $entries->{$entry}->kind;
	my $unchanged = ($kind == $SVN::Node::file && $signature && !$signature->changed ($entry));
	$copath = SVK::Path::Checkout->copath ($arg{copath}, $copath);
	my ($ccinfo, $ccschedule) = $self->xd->get_entry($copath, 1);
	# a replace with history node requires handling the copy anchor in the
	# latter direntries loop.  we should really merge the two.
	if ($ccschedule eq 'replace' && $ccinfo->{'.copyfrom'}) {
	    delete $entries->{$entry};
	    $targets->{$entry} = $newtarget if defined $targets;
	    next;
	}
	my $newentry = defined $arg{entry} ? "$arg{entry}/$entry" : $entry;
	my $newpath = $arg{path} eq '/' ? "/$entry" : "$arg{path}/$entry";
	if ($unchanged && !$ccschedule && !$ccinfo->{'.conflict'}) {
	    $arg{cb_unchanged}->($arg{editor}, $newentry, $baton,
				 $self->_delta_rev({ %arg,
						     cinfo  => $ccinfo,
						     path   => $newpath,
						     copath => $copath })
				) if $arg{cb_unchanged};
	    next;
	}
	my ($type, $st) = _node_type ($copath);
	next unless defined $type;
	my $delta = $type ? $type eq 'directory' ? \&_delta_dir : \&_delta_file
	                  : $kind == $SVN::Node::file ? \&_delta_file : \&_delta_dir;
	my $obs = $type ? ($kind == $SVN::Node::dir xor $type eq 'directory') : 0;
	# if the sub-delta returns 1 it means the node is modified. invlidate
	# the signature cache
	$self->$delta ( %arg,
			add => $arg{in_copy} || ($obs && $arg{obstruct_as_replace}),
			type => $type,
			# if copath exist, we have base only if they are of the same type
			base => !$obs,
			depth => defined $arg{depth} ? defined $targets ? $arg{depth} : $arg{depth} - 1: undef,
			entry => $newentry,
			kind => $arg{base_root_is_xd} ? $kind : $arg{xdroot}->check_path ($newpath),
			base_kind => $kind,
			targets => $newtarget,
			baton => $baton,
			root => 0,
			st => $st,
			cinfo => $ccinfo,
			base_path => $arg{base_path} eq '/' ? "/$entry" : "$arg{base_path}/$entry",
			path => $newpath,
			copath => $copath)
	    and ($signature && $signature->invalidate ($entry));
    }

    if ($signature) {
	$signature->flush;
	undef $signature;
    }
    my $ignore = $self->xd->ignore($fullprops->{'svn:ignore'});

    my @direntries;
    # if we are at somewhere arg{copath} not exist, $arg{type} is empty
    if ($arg{type} && !(defined $targets && !keys %$targets)) {
	opendir my ($dir), $arg{copath} or Carp::confess "$arg{copath}: $!";
	for (readdir($dir)) {
	    # Completely deny the existance of .svk; we shouldn't
	    # show this even with e.g. --no-ignore.
	    next if $_ eq '.svk' and $self->xd->{floating};

	    if (eval {from_native($_, 'path', $arg{encoder}); 1}) {
		push @direntries, $_;
	    }
	    elsif ($arg{auto_add}) { # fatal for auto_add
		die "$_: $@";
	    }
	    else {
		print "$_: $@";
	    }
	}
	@direntries = sort grep { !m/^\.+$/ && !exists $entries->{$_} } @direntries;
    }

    for my $copath (@direntries) {
	my $entry = $copath;
	my $newtarget;
	if (defined $targets) {
	    next unless exists $targets->{$copath};
	    $newtarget = delete $targets->{$copath};
	}
	to_native ($copath, 'path', $arg{encoder});
	my %newpaths = ( copath => SVK::Path::Checkout->copath ($arg{copath}, $copath),
			 entry => defined $arg{entry} ? "$arg{entry}/$entry" : $entry,
			 path => $arg{path} eq '/' ? "/$entry" : "$arg{path}/$entry",
			 base_path => $arg{base_path} eq '/' ? "/$entry" : "$arg{base_path}/$entry",
			 targets => $newtarget, base_kind => $SVN::Node::none);
	$newpaths{kind} = $arg{base_root_is_xd} ? $SVN::Node::none :
	    $arg{xdroot}->check_path ($newpaths{path}) != $SVN::Node::none;
	my ($ccinfo, $sche) = $self->xd->get_entry($newpaths{copath}, 1);
	my $add = $sche || $arg{auto_add} || $newpaths{kind};
	# If we are not at intermediate path, process ignore
	# for unknowns, as well as the case of auto_add (import)
	if (!defined $targets) {
	    if ((!$add || $arg{auto_add}) && $entry =~ m/$ignore/) { 
		$arg{cb_ignored}->($arg{editor}, $newpaths{entry}, $arg{baton})
		    if $arg{cb_ignored};
		next;
	    }
	}
	if ($ccinfo->{'.conflict'}) {
            $arg{cb_conflict}->($arg{editor}, $newpaths{entry}, $arg{baton}, $cinfo->{'.conflict'})
		if $arg{cb_conflict};
	}
	unless ($add || $ccinfo->{'.conflict'}) {
	    if ($arg{cb_unknown}) {
		$arg{cb_unknown}->($arg{editor}, $newpaths{entry}, $arg{baton});
		$self->_unknown_verbose (%arg, %newpaths)
		    if $arg{unknown_verbose};
	    }
	    next;
	}
	my ($type, $st) = _node_type ($newpaths{copath}) or next;
	my $delta = $type eq 'directory' ? \&_delta_dir : \&_delta_file;
	my $copyfrom = $ccinfo->{'.copyfrom'};
	my ($fromroot) = $copyfrom ? $arg{xdroot}->get_revision_root($newpaths{path}, $ccinfo->{'.copyfrom_rev'}) : undef;
	$self->$delta ( %arg, %newpaths, add => 1, baton => $baton,
			root => 0, base => 0, cinfo => $ccinfo,
			type => $type,
			st => $st,
			depth => defined $arg{depth} ? defined $targets ? $arg{depth} : $arg{depth} - 1: undef,
			$copyfrom ?
			( base => 1,
			  _really_in_copy => 1,
			  in_copy => $arg{expand_copy},
			  base_kind => $fromroot->check_path ($copyfrom),
			  base_root_is_xd => 0,
			  base_root => $fromroot,
			  base_path => $copyfrom) : (),
		      );
    }

    }

    if ($thisdir) {
	$arg{editor}->change_dir_prop ($baton, $_, ref ($newprops->{$_}) ? undef : $newprops->{$_}, $pool)
	    for sort keys %$newprops;
    }
    if (defined $targets) {
	$logger->warn(loc ("Unknown target: %1.", $_)) for sort keys %$targets;
    }

    $arg{editor}->close_directory ($baton, $pool)
	unless $arg{root};
    return 0;
}

sub _get_rev {
    $_[0]->{checkout}->get ($_[1])->{revision};
}

sub get_entry {
    my ($self, $copath, $dont_clone) = @_;
    my $entry = $self->checkout->get($copath, $dont_clone);
    return ($entry, $entry->{'.schedule'} || '');
}

sub checkout_delta1 {
    my ($self, $target, $editor, $opt) = @_;

    my $source = $target->source;
    my $xdroot = $target->create_xd_root;
    my $base_root = $opt->{base_root} || $xdroot;
    my $base_kind = $base_root->check_path($source->path_anchor);

    die "checkout_delta called with non-dir node"
        unless $base_kind == $SVN::Node::dir;

    my %arg = ( 
                base_root => $base_root,
                xdroot => $opt->{xdroot} || $base_root,
                base_root_is_xd => $opt->{xdroot} ? 0 : 1,
                encoder => get_encoder,

                copath => $target->copath,
                path => $source->path_anchor,
                base_path => $source->path_anchor,

                targets => $source->{targets},
                repos => $source->repos,
                repospath => $source->repospath,
                report => $target->report,

                kind => $base_kind,
                base_kind => $base_kind,
                cb_resolve_rev => sub { $_[1] },
                %$opt,
           );

    $arg{cb_copyfrom} ||= $arg{expand_copy} ? sub { (undef, -1) }
        : sub { my $path = $_[0]; $path =~ s/%/%25/g; ("file://".$source->repospath.$path, $_[1]) };

    $editor = SVK::Editor::Delay->new($editor)
           unless $arg{nodelay};

    # XXX: translate $repospath to use '/'
    my ($entry) = $self->xd->get_entry($target->copath, 1);
    my $rev = $arg{cb_resolve_rev}->($source->path_anchor, $entry->{revision});
    local $SIG{INT} = sub {
        $editor->abort_edit;
        die loc("Interrupted.\n");
    };

    my $baton = $editor->open_root($rev);
    $arg{editor} = $editor;
    $self->_delta_dir(%arg, baton => $baton, root => 1, base => 1, type => 'directory');
    $editor->close_directory($baton);
    $editor->close_edit();

}

1;
