package SVK::PathResolve;
use strict;
use SVK::I18N;
use SVK::Logger;
use SVK::Util qw(get_prompt);

sub new {
    my ($class, %args) = @_;
    return bless(\%args, $class);
}

sub add_file {
    my ($self, $path) = @_;
    
    my $default = 'a';
    my $prompt = loc(
        "Conflict found in %1:\na)add, s)kip, h)elp? [%2] ",
        $path, $default
    );

    my $action = lc(get_prompt(
        $prompt, qr/^[ash]?/i
    ) || $default);
    return $action if $action !~ /^h/;

    die "help is not implemented yet";

}

sub add_directory {
    my ($self, $path) = @_;
    
    my $default = 'a';
    my $prompt = loc(
        "Conflict found in %1:\na)dd all, o)only this, s)kip, h)elp? [%2] ",
        $path, $default
    );

    my $action = lc(get_prompt(
        $prompt, qr/^[ash]?/i
    ) || $default);
    return $action if $action !~ /^h/;

    die "help is not implemented yet";
}

sub change_file {
    my ($self, $path) = @_;
    
    my $default = 'a';
    my $prompt = loc(
        "Conflict found in %1:\na)add, s)kip, h)elp? [%2] ",
        $path, $default
    );

    my $action = lc(get_prompt(
        $prompt, qr/^[ash]?/i
    ) || $default);
    return $action if $action !~ /^h/;

    die "help is not implemented yet";
}


1;
