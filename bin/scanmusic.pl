#!/usr/bin/perl -w

use strict;
use diagnostics;

use File::Find qw(find);
use Image::ExifTool qw(:Public);
use Data::Dumper;
use Try::Tiny; 
use DBI;

use Replaygainer;
use Replaygainer::AudioFileInfo;
use Replaygainer::Worker;

use Getopt::Long;
use Cwd;
use Errno qw(EINVAL :POSIX);
use Term::ReadKey;

my $name = 'replaygainer';
my $version = '0.0.1';

# actions in interactive mode
use constant {
    LIST => 1,
    ASK  => 2,
    QUIT => 3,
};

# command line parameters

my $dir = getcwd();
my $verbose;
my $help;
my $list;
my $interactive;
my $add_album_gain;
my $add_file_gain;

# parse and check yommand line arguments

GetOptions(
  "dir=s"            => \$dir,
  "verbose"          => \$verbose,
  "help"             => \$help,
  "list"             => \$list,
  "interactive"      => \$interactive,
  "add-album-gain"   => \$add_album_gain,
  "f|add-file-gain"  => \$add_file_gain,
) or print_help_and_exit(
    EINVAL,
    "Usage error: Error in command line arguments.\n"
);

print_help_and_exit() if $help;

if ($interactive and ($add_album_gain or $add_file_gain)) {
    print_help_and_exit(
        EINVAL,
        "Usage error: You can not request interactive mode and use --add-(album|file)-gain at the same time.\n"
    );
}

if ($add_album_gain and $add_file_gain) {
    print_help_and_exit(
        EINVAL,
        "Usage error: You can only use either --add-album-gain or --add-file-gain, not both.\n"
    );
}

# main

my $exif_tool = new Image::ExifTool({Duplicates => 1});

my $total = 0;
my $total_touched = 0;
my $total_touched_audio = 0;

my @dirs_without_rg;

{
    my $done_dirs = {};

    sub scanfile {
        $total++;
        if (-f $_ and not defined $done_dirs->{$File::Find::dir}) {
            $total_touched++;
            my $info = $exif_tool->ImageInfo($_);

            try {
                my $foo = new Replaygainer::AudioFileInfo({
                    %$info,
                    dir  => $File::Find::dir,
                    file => $_,
                });
                $total_touched_audio++;
                unless ($foo->has_replaygain_track_gain()) {
                    push @dirs_without_rg, $File::Find::dir;
                    print $foo->full_path() . " has no replaygain info.\n" if $verbose;
                    $done_dirs->{$File::Find::dir} = 1;
                }
            }
            catch {
                ;
            }

        }
    }
}

print "Scanning $dir for albums with missing replaygain information...\n";

find(\&scanfile, ".");

print "\nScanned $total files total ($total_touched files touched, $total_touched_audio of those were audio files)\n" if $verbose;

my $num_dirs_without_rg = @dirs_without_rg;

print "\nFound $num_dirs_without_rg directories with files missing replaygain information.\n\n";

if (not $interactive) {
    list() if $list;
}
else {
    while (1) {
        print<<EOT;
What do you want to do next? Your options:

  [1] list all albums without file replaygain information
  [2] apply replaygain information to each album/track by deciding whether
      to apply file gain only or album gain additionally
  [3] quit

EOT

        perform_action(read_action());
    }
}


# subroutines

sub valid_action {
    my $action = shift;

    return scalar grep /$action/, (LIST, ASK, QUIT);
}

sub read_action {
    my $key;
    my $errs = 0;
    ReadMode 4;
    while ($key = ReadKey(0) and not valid_action($key)) {
        print "\n" if $key eq "\n" and next;
        print "Invalid action '$key'\n";
        if ($errs++ > 5) { die "\nm(\n"; }
    }
    ReadMode 0;
    return $key;
}

sub perform_action {
    my $action = shift;

    list() if $action eq LIST;
    print "Bye...\n\n" and exit() if $action eq QUIT;
    #list() if $action eq LIST;
}

sub list {
    foreach my $dir (@dirs_without_rg) {
        print "$dir\n";
    }
    print "\n";
}

sub print_help_and_exit {
    my $errno = shift;
    my $msg = shift;

    print<<EOT;
$name (v$version) -- A tool to find music albums missing replaygain
 information and to add it upon request

  -d <dir>, --dir=<dir>      Root directory where to begin scanning
  -i, --interactive          Interactive mode: asks for each album missing
                              replaygain information whether to additionally
                              add album gain
  -f, --add-file-gain        Adds file gain (only) to all albums missing
                              replaygain information
  -a, --add-album-gain       Adds file gain and album gain to all albums
                              missing replaygain information
  -v, --verbose              Display verbose information
  -h, --help                 Display this help

EOT

    warn $msg if $msg;

    exit $errno;

}

