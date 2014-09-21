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
use Replaygainer::Dirs;
use Replaygainer::DirWithState;
use Replaygainer::Worker;

use Getopt::Long;
use Cwd;
use Errno qw(EINVAL ENOENT :POSIX);
use Term::ReadKey;
use AnyEvent;
use Module::Find qw(usesub);

my $name = 'replaygainer';
my $version = $Replaygainer::VERSION;

use constant {
    # actions
    LIST_CMD => 1,
    ASK_CMD  => 2,
    QUIT_CMD => 3,

    # state variables used in interactive loop
    QUIT     => 4,
    CONTINUE => 5,
};

#
# command line parameters
#

my $dir = getcwd();
my $verbose;
my $help;
my $list;
my $interactive;
my $add_album_gain;
my $add_track_gain;

#
# parse and check yommand line arguments
#

GetOptions(
  "dir=s"             => \$dir,
  "verbose"           => \$verbose,
  "help"              => \$help,
  "list"              => \$list,
  "interactive"       => \$interactive,
  "add-album-gain"    => \$add_album_gain,
  "t|add-track-gain"  => \$add_track_gain,
) or print_help_and_exit(
    EINVAL,
    "Usage error: Error in command line arguments.\n"
);

print_help_and_exit() if $help;

if (not -d $dir) {
    print "Invalid directory '$dir', can not continue.\n";
    exit ENOENT;
}

if ($interactive and ($add_album_gain or $add_track_gain)) {
    print_help_and_exit(
        EINVAL,
        "Usage error: You can not request interactive mode and use --add-(album|track)-gain at the same time.\n"
    );
}

if ($add_album_gain and $add_track_gain) {
    print_help_and_exit(
        EINVAL,
        "Usage error: You can only use either --add-album-gain or --add-track-gain, not both.\n"
    );
}

#
# main
#

my $exif_tool = new Image::ExifTool({Duplicates => 1});

# next three are global vars that are being updated in scanfile()
my $total = 0;
my $total_touched = 0;
my $total_touched_audio = 0;

my $dirs_without_rg = Replaygainer::Dirs->new();

print "Scanning $dir for albums with missing replaygain information...\n";

find(sub { scanfile($dirs_without_rg) }, ".");

print "\nScanned $total files total ($total_touched files touched, $total_touched_audio of those were audio files)\n" if $verbose;

my $num_dirs_without_rg = keys %{$dirs_without_rg->dirs};

print "\nFound $num_dirs_without_rg directories with files missing replaygain information.\n\n";

my @found = usesub Replaygainer::Worker;

foreach my $plugin (@found) { print $plugin . "\n"; }

if (not $interactive) {
    list_cmd() if $list;
}
else {
    my $continue = CONTINUE;

    while ($continue == CONTINUE) {
        print<<EOT;
What do you want to do next? Your options:

  [1] list all albums without file replaygain information
  [2] apply replaygain information to each album/track by deciding whether
      to apply file gain only or album gain additionally
  [3] quit

EOT

        $continue = perform_action(read_action(), $dirs_without_rg);
    }
}


#
# subroutines
#

sub valid_action {
    my $action = shift;

    return scalar grep /$action/, (LIST_CMD, ASK_CMD, QUIT_CMD)
        if ord($action) >= 32 and ord($action) <= 126;
    return 0;
}

sub read_action {
    my $key;
    my $errs = 0;
    ReadMode(3);
    while ($key = ReadKey(0) and not valid_action($key)) {
        print "\n" if $key eq "\n" and next;
        print "Invalid action '$key'\n";
        if ($errs++ > 5) { die "\nm(\n"; }
    }
    ReadMode(0);
    return $key;
}

sub perform_action {
    my $action = shift;
    my $dirs_without_rg = shift;

    return list_cmd($dirs_without_rg) if $action eq LIST_CMD;
    return quit_cmd() if $action eq QUIT_CMD;
    return ask_cmd($dirs_without_rg) if $action eq ASK_CMD;

    # quit if nothing matches
    return QUIT;
}

sub quit_cmd {
    print "Bye...\n\n";
    return QUIT;
}

sub list_cmd {
    my $dirs_without_rg = shift;

    foreach my $dir (keys %{$dirs_without_rg->dirs}) {
        print "$dir\n";
    }
    print "\n";

    return CONTINUE;
}

{
    my $w = AnyEvent->condvar;
    my $work_monitor_started = 0;

    sub run_next_job {
        my $dirs_without_rg = shift;

        $dirs_without_rg->get_processable_dir
    }

    sub maybe_start_work_monitor {
        if (not $work_monitor_started) {
            my $pid = fork();
            
            if (not defined $pid) {
                die "Unable to fork().\n";
            }
            elsif ($pid == 0) {
                print "Monitor working in background ...\n";
                sleep 2;
                exit 0;
            }
            else {
                print "Started background processing ...\n";
                $work_monitor_started = 1;
                my $w = AnyEvent->child(pid => $pid, cb => sub {
                    my ($pid, $status) = @_;
                    print "CHILD EXITED :-)\n";
                });
            }
        }
        else {
            print "Monitor already started, nothing to do.\n";
        }
    }

    sub ask_cmd {
        my $dirs_without_rg = shift;

        sub query_user {
            my $dir = shift;

            print $dir->path . " [a]lbum or [t]rack gain? ";

            my $key;
            ReadMode(3);
            while ($key = ReadKey(0) and not ($key eq 'a' or $key eq 't')) {}
            ReadMode(0);

            if ($key eq 'a') {
                print "album\n";
                return 'album';
            }
            elsif ($key eq 't') {
                print "track\n";
                return 'track';
            }
        }

        foreach my $dir ($dirs_without_rg->get_fresh_dirs) {
            my $gain_mode = query_user($dir);
            $dir->gain_mode($gain_mode);
        }
        
        return QUIT;
    }
}

sub scanfile {
    my $dirs_without_rg = shift;

    $total++;
    if (-f $_ and not $dirs_without_rg->path_known($File::Find::dir)) {
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
            
                $dirs_without_rg->add(Replaygainer::DirWithState->new({
                    path     => $File::Find::dir,
                    mimetype => $foo->mimetype,
                }));
                print $foo->full_path() . " has no replaygain info.\n" if $verbose;
                maybe_start_work_monitor();
            }
        }
        catch {
            ;
        }
    }
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
  -t, --add-track-gain       Adds track gain (only) to all albums missing
                              replaygain information
  -a, --add-album-gain       Adds track gain and album gain to all albums
                              missing replaygain information
  -v, --verbose              Display verbose information
  -h, --help                 Display this help

EOT

    warn $msg if defined $msg;

    exit defined $errno ? $errno : 0;

}

