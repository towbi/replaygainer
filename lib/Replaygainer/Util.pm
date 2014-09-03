package Replaygainer::Util;

use Exporter;

our @EXPORT_OK = qw(zip2);

# function to zip two arrays
#
# (author: merlyn (Randal Schwartz)
sub zip2 {
    my $p = @_ / 2; 
    return @_[ map { $_, $_ + $p } 0 .. $p - 1 ];
}

