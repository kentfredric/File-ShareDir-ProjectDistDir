use strict;
use warnings;

package Example_06;

use File::ShareDir::ProjectDistDir;

use Path::Tiny qw(path);

sub test {
  return scalar path( dist_file( 'Example_06', 'file' ) )->slurp();
}

1;
