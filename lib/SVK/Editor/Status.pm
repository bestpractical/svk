package SVK::Editor::Status;
use strict;
use SVN::Delta;
use SVK::Version;  our $VERSION = $SVK::VERSION;
use base 'SVK::Editor';

__PACKAGE__->mk_accessors(qw(report notify tree ignore_absent));

sub new {
    my ($class, @arg) = @_;
    my $self = $class->SUPER::new (@arg);
    $self->notify( SVK::Notify->new_with_report
		   (defined $self->report ? $self->report : '') ) unless $self->notify;
    $self->tree(Data::Hierarchy->new) unless $self->tree;
    use Data::Dumper;
    warn Dumper($self) if $main::DEBUG;
    return $self;
}

sub _tree_get {
    my $self = shift;
    my $path = shift;
    $path = $self->tree->{sep} . $path;
    return $self->tree->get($path, @_);
}

sub _tree_store {
    my $self = shift;
    my $path = shift;
    $path = $self->tree->{sep} . $path;
    return $self->tree->store($path, @_);
}

sub open_root {
    my ($self, $baserev) = @_;
    $self->notify->node_status ('', '');
    $self->notify->node_baserev ('', $baserev);
    return '';
}

sub add_or_replace {
    my ($self, $path) = @_;
    if ($self->notify->node_status ($path)) {
	$self->notify->node_status ($path, 'R')
	    if $self->notify->node_status ($path) eq 'D';
    }
    else {
	$self->notify->node_status ($path, 'A');
    }
}

sub add_file {
    my ($self, $path, $pdir, $from_path, $from_rev) = @_;
    $self->add_or_replace ($path);
    $self->notify->hist_status ($path, '+', $from_path, $from_rev)
	if $from_path;
    return $path;
}

sub open_file {
    my $self = shift;
    return $self->open_node(@_);
}

sub apply_textdelta {
    my ($self, $path) = @_;
    return undef if $self->notify->node_status ($path) eq 'R';
    $self->notify->node_status ($path, 'M')
	if !$self->notify->node_status ($path) || $self->notify->hist_status ($path);
    return undef;
}

sub change_file_prop {
    my ($self, $path, $name, $value) = @_;
    $self->notify->prop_status ($path, 'M');
}

sub close_file {
    my ($self, $path) = @_;
    $self->notify->flush ($path);
}

sub absent_file {
    my ($self, $path) = @_;
    return if $self->ignore_absent;
    $self->notify->node_status ($path, '!');
    $self->notify->flush ($path);
}

sub delete_entry {
    my ($self, $path) = @_;
    $self->notify->node_status ($path, 'D');
    my $info = $self->_tree_get ($path);
    $self->notify->hist_status ($path, '+', $info->{frompath},
	$info->{fromrev}) if $info->{frompath};
}

sub add_directory {
    my ($self, $path, $pdir, $from_path, $from_rev) = @_;
    $self->add_or_replace ($path);
    if ($from_path) {
	$self->notify->hist_status ($path, '+', $from_path, $from_rev);
	$self->_tree_store ($path, {frompath => $from_path,
                                    fromrev => $from_rev});
    }
    $self->notify->flush ($path, 1);
    return $path;
}

sub open_directory {
    my $self = shift;
    return $self->open_node(@_);
}

sub change_dir_prop {
    my ($self, $path, $name, $value) = @_;
    $self->notify->prop_status ($path, 'M');
}

sub close_directory {
    my ($self, $path) = @_;
    $self->notify->flush_dir ($path);
}

sub open_node {
    my ($self, $path, $pdir, $baserev, $pool) = @_;
    $self->notify->node_status ($path, '')
	unless $self->notify->node_status ($path);
    $self->notify->node_baserev ($path, $baserev);
    my $info = $self->_tree_get ($path);
    $self->notify->hist_status ($path, '+', $info->{frompath},
	$info->{fromrev}) if $info->{frompath};
    return $path;
}

sub absent_directory {
    my ($self, $path) = @_;
    return if $self->ignore_absent;
    $self->notify->node_status ($path, '!');
    $self->notify->flush ($path);
}

sub conflict {
    my ($self, $path) = @_;
    $self->notify->node_status ($path, 'C');
}

sub obstruct {
    my ($self, $path) = @_;
    $self->notify->node_status ($path, '~');
}

sub unknown {
    my ($self, $path) = @_;
    $self->notify->node_status ($path, '?');
    $self->notify->flush ($path);
}

sub ignored {
    my ($self, $path) = @_;
    $self->notify->node_status ($path, 'I');
    $self->notify->flush ($path);
}

sub unchanged {
    my ($self, $path, @args) = @_;
    $self->open_node($path, @args);
    $self->notify->flush ($path);
}

1;
