use strict;
use warnings;

package File::ShareDir::ProjectDistDir;

# ABSTRACT: Simple set-and-forget using of a '/share' directory in your projects root

=begin MetaPOD::JSON v1.0.0

{
    "namespace":"File::ShareDir::ProjectDistDir"
}

=end MetaPOD::JSON

=head1 SYNOPSIS

  package An::Example::Package;

  use File::ShareDir::ProjectDistDir;

  # during development, $dir will be $projectroot/share
  # but once installed, it will be wherever File::Sharedir thinks it is.
  my $dir = dist_dir('An-Example')

Project layout requirements:

  $project/
  $project/lib/An/Example/Package.pm
  $project/share/   # files for package 'An-Example' go here.

You can use a directory name other than 'share' ( Assuming you make sure when
you install that, you specify the different directory there also ) as follows:

  use File::ShareDir::ProjectDistDir ':all', defaults => {
    projectdir => 'templates',
  };

=cut

use Path::Class::File;
use Path::IsDev qw();
use Path::FindDev qw(find_dev);
use Sub::Exporter qw(build_exporter);
use File::ShareDir qw();

my ($exporter) = build_exporter(
  {
    exports => [ dist_dir => \&build_dist_dir, dist_file => \&build_dist_file ],
    groups  => {
      all       => [qw( dist_dir dist_file )],
      'default' => [qw( dist_dir dist_file )]
    },
    collectors => [ 'defaults', ],
  }
);
my $env_key = 'FILE_SHAREDIR_PROJECTDISTDIR_DEBUG';

if ( $ENV{$env_key} ) {
  ## no critic (ProtectPrivateVars)
  *File::ShareDir::ProjectDistDir::_debug = sub ($) {
    *STDERR->printf( qq{[ProjectDistDir] %s\n}, $_[0] );
  };
  $Path::IsDev::DEBUG   = 1;
  $Path::FindDev::DEBUG = 1;
}
else {
  ## no critic (ProtectPrivateVars)
  *File::ShareDir::ProjectDistDir::_debug = sub ($) { }
}

## no critic (RequireArgUnpacking)
sub _croak         { require Carp;              goto &Carp::croak }
sub _path          { require Path::Tiny;        goto &Path::Tiny::path }
sub _pathclassfile { require Path::Class::File; return Path::Class::File->new(@_) }
sub _pathclassdir  { require Path::Class::Dir;  return Path::Class::Dir->new(@_) }

=method import

    use File::ShareDir::ProjectDistDir (@args);

This uses L<< C<Sub::Exporter>|Sub::Exporter >> to do the heavy lifting, so most usage of this module can be maximised by understanding that first.

=over 4

=item * B<C<:all>>

    ->import( ':all' , .... )

Import both C<dist_dir> and C<dist_file>

=item * B<C<dist_dir>>

    ->import('dist_dir' , .... )

Import the dist_dir method

=item * B<C<dist_dir>>

    ->import('dist_file' , .... )

Import the dist_file method

=item * B<C<projectdir>>

    ->import( .... , projectdir => 'share' )

Specify what the project directory is as a path relative to the base of your distributions source,
and this directory will be used as a C<ShareDir> simulation path for the exported methods I<During development>.

If not specified, the default value 'share' is used.

=item * B<C<filename>>

    ->import( .... , filename => 'some/path/to/foo.pm' );

Generally you don't want to set this, as its worked out by caller() to work out the name of
the file its being called from. This file's path is walked up to find the 'lib' element with a sibling
of the name of your C<projectdir>.

=item * B<C<distname>>

    ->import( .... , distname => 'somedistname' );

Specifying this argument changes the way the functions are emitted at I<installed C<runtime>>, so that instead of
taking the standard arguments File::ShareDir does, the specification of the C<distname> in those functions is eliminated.

i.e:

    # without this flag
    use File::ShareDir::ProjectDistDir qw( :all );

    my $dir = dist_dir('example');
    my $file = dist_file('example', 'path/to/file.pm' );

    # with this flag
    use File::ShareDir::ProjectDistDir ( qw( :all ), distname => 'example' );

    my $dir = dist_dir();
    my $file = dist_file('path/to/file.pm' );

=item * B<C<defaults>>

    ->import( ... , defaults => {
        filename => ....,
        projectdir => ....,
    });

This is mostly an alternative syntax for specifying C<filename> and C<projectdir>,
which is mostly used internally, and their corresponding other values are packed into this one.

=back

=head3 Sub::Exporter tricks of note.

=head4 Make your own sharedir util

    package Foo::Util;

    sub import {
        my ($caller_class, $caller_file, $caller_line )  = caller();
        if ( grep { /share/ } @_ ) {
            require File::ShareDir::ProjectDistDir;
            File::ShareDir::ProjectDistDir->import(
                filename => $caller_file,
                dist_dir => { distname => 'myproject' , -as => 'share' },
                dist_dir => { distname => 'otherproject' , -as => 'other_share' , projectdir => 'share2' },
                -into => $caller_class,
            );
        }
    }

    ....

    package Foo;
    use Foo::Util qw( share );

    my $dir = share();
    my $other_dir => other_share();


=cut

sub import {
  my ( $class, @args ) = @_;
  my $has_defaults = undef;

  my ( $xclass, $xfilename, $xline ) = caller;

  my $defaults = {
    filename   => $xfilename,
    projectdir => 'share',
    pathclass  => undef,
  };

  if ( not @args ) {
    @_ = ( $class, ':all', defaults => $defaults );
    goto $exporter;
  }

  for ( 0 .. $#args - 1 ) {
    my ( $key, $value );
    next unless $key = $args[$_] and $value = $args[ $_ + 1 ];

    if ( $key eq 'defaults' ) {
      $defaults = $value;
      undef $args[$_];
      undef $args[ $_ + 1 ];
      next;
    }
    for my $setting (qw( projectdir filename distname pathclass pathtiny )) {
      if ( $key eq $setting and not ref $value ) {
        $defaults->{$setting} = $value;
        undef $args[$_];
        undef $args[ $_ + 1 ];
        last;
      }
    }
  }

  $defaults->{filename}   = $xfilename if not defined $defaults->{filename};
  $defaults->{projectdir} = 'share'    if not defined $defaults->{projectdir};

  @_ = ( $class, ( grep { defined } @args ), 'defaults' => $defaults );

  goto $exporter;
}

sub _devel_sharedir {
  my ( $filename, $subdir ) = @_;

  _debug( 'Working on: ' . $filename );
  my $dev = find_dev( _path($filename)->parent );

  return if not defined $dev;

  my $devel_share_dir = $dev->child($subdir);
  if ( -d $devel_share_dir ) {
    _debug( 'ISDEV : exists : <devroot>/' . $subdir . ' > ' . $devel_share_dir );
    return $devel_share_dir;
  }
  _debug( 'ISPROD: does not exist : <devroot>/' . $subdir . ' > ' . $devel_share_dir );

  #warn "Not a devel $dir";
  return;
}

=method build_dist_dir

    use File::ShareDir::ProjectDirDir ( : all );

    #  this calls
    my $coderef = File::ShareDir::ProjectDistDir->build_dist_dir(
      'dist_dir' => {},
      { defaults => { filename => 'path/to/yourcallingfile.pm', projectdir => 'share' } }
    );

    use File::ShareDir::ProjectDirDir ( qw( :all ), distname => 'example-dist' );

    #  this calls
    my $coderef = File::ShareDir::ProjectDistDir->build_dist_dir(
      'dist_dir' => {},
      { distname => 'example-dist', defaults => { filename => 'path/to/yourcallingfile.pm', projectdir => 'share' } }
    );

    use File::ShareDir::ProjectDirDir
      dist_dir => { distname => 'example-dist', -as => 'mydistdir' },
      dist_dir => { distname => 'other-dist',   -as => 'otherdistdir' };

    # This calls
    my $coderef = File::ShareDir::ProjectDistDir->build_dist_dir(
      'dist_dir',
      { distname => 'example-dist' },
      { defaults => { filename => 'path/to/yourcallingfile.pm', projectdir => 'share' } },
    );
    my $othercoderef = File::ShareDir::ProjectDistDir->build_dist_dir(
      'dist_dir',
      { distname => 'other-dist' },
      { defaults => { filename => 'path/to/yourcallingfile.pm', projectdir => 'share' } },
    );

    # And leverages Sub::Exporter to create 2 subs in your package.


Generates the exported 'dist_dir' method. In development environments, the generated method will return
a path to the development directories 'share' directory. In non-development environments, this simply returns
C<File::ShareDir::dist_dir>.

As a result of this, specifying the Distribution name is not required during development, however, it will
start to matter once it is installed. This is a potential avenues for bugs if you happen to name it wrong.

=cut

sub _get_defaults {
  my ( $field, $arg, $col ) = @_;
  my $result;
  $result = $col->{defaults}->{$field} if $col->{defaults}->{$field};
  $result = $arg->{$field}             if $arg->{$field};
  return $result;
}

sub _wrap_return {
  my ( $type, $value ) = @_;
  if ( not $type ) {
    return $value unless ref $value;
    return "$value";
  }
  if ( $type eq 'pathtiny' ) {
    return $value if ref $value eq 'Path::Tiny';
    return Path::Tiny::path($value);
  }
  if ( $type eq 'pathclassdir' ) {
    return $value if ref $value eq 'Path::Class::Dir';
    require Path::Class::Dir;
    return Path::Class::Dir->new("$value");
  }
  if ( $type eq 'pathclassfile' ) {
    return $value if ref $value eq 'Path::Class::File';
    require Path::Class::File;
    return Path::Class::File->new("$value");
  }
  die "Unknown return type $type";
}

sub build_dist_dir {
  my ( $class, $name, $arg, $col ) = @_;

  my $projectdir = _get_defaults( projectdir => $arg, $col );
  my $pathclass  = _get_defaults( pathclass  => $arg, $col );
  my $pathtiny   = _get_defaults( pathtiny   => $arg, $col );

  my $wrap_return_type;

  if ($pathclass) { $wrap_return_type = 'pathclassdir' }
  if ($pathtiny)  { $wrap_return_type = 'pathtiny' }

  my $root = _devel_sharedir( $col->{defaults}->{filename}, $projectdir );

  my $distname = _get_defaults( distname => $arg, $col );

  # In dev
  if ($root) {
    return sub { return _wrap_return( $wrap_return_type, $root ) };
  }

  # Non-Dev, no hardcoded distname
  if ( not $distname ) {
    my $string_method = \&File::ShareDir::dist_dir;
    return sub { return _wrap_return( $wrap_return_type, $string_method->(@_) ) };
  }

  # Non-Dev, hardcoded distname
  my $string_method = sub() {
    @_ = ($distname);
    goto &File::ShareDir::dist_dir;
  };
  return sub { return _wrap_return( $wrap_return_type, $string_method->(@_) ) };
}

=method build_dist_file

    use File::ShareDir::ProjectDirDir ( : all );

    #  this calls
    my $coderef = File::ShareDir::ProjectDistDir->build_dist_file(
      'dist_file' => {},
      { defaults => { filename => 'path/to/yourcallingfile.pm', projectdir => 'share' } }
    );

    use File::ShareDir::ProjectDirDir ( qw( :all ), distname => 'example-dist' );

    #  this calls
    my $coderef = File::ShareDir::ProjectDistDir->build_dist_file(
      'dist_file' => {},
      { distname => 'example-dist', defaults => { filename => 'path/to/yourcallingfile.pm', projectdir => 'share' } }
    );

    use File::ShareDir::ProjectDirDir
      dist_file => { distname => 'example-dist', -as => 'mydistfile' },
      dist_file => { distname => 'other-dist',   -as => 'otherdistfile' };

    # This calls
    my $coderef = File::ShareDir::ProjectDistDir->build_dist_file(
      'dist_file',
      { distname => 'example-dist' },
      { defaults => { filename => 'path/to/yourcallingfile.pm', projectdir => 'share' } },
    );
    my $othercoderef = File::ShareDir::ProjectDistDir->build_dist_file(
      'dist_file',
      { distname => 'other-dist' },
      { defaults => { filename => 'path/to/yourcallingfile.pm', projectdir => 'share' } },
    );

    # And leverages Sub::Exporter to create 2 subs in your package.


Generates the 'dist_file' method.

In development environments, the generated method will return
a path to the development directories 'share' directory. In non-development environments, this simply returns
C<File::ShareDir::dist_file>.

Caveats as a result of package-name as stated in L</build_dist_dir> also apply to this method.

=cut

sub build_dist_file {
  my ( $class, $name, $arg, $col ) = @_;

  my $projectdir = _get_defaults( projectdir => $arg, $col );
  my $pathclass  = _get_defaults( pathclass  => $arg, $col );
  my $pathtiny   = _get_defaults( pathtiny   => $arg, $col );

  my $root = _devel_sharedir( $col->{defaults}->{filename}, $projectdir );

  my $distname = _get_defaults( distname => $arg, $col );

  my $wrap_return_type;

  if ($pathclass) { $wrap_return_type = 'pathclassfile' }
  if ($pathtiny)  { $wrap_return_type = 'pathtiny' }

  if ($root) {
    my $pathclass_method = sub {
      my $file = ( $distname ? $_[0] : $_[1] );

      # if the caller is devel, then we return the project root,
      # regardless of what package you asked for.
      # Might be bad, but we haven't imagined the scenario where yet.
      my $path_o = $root->child($file)->absolute;
      my $path_s = $path_o->stringify;
      ## no critic ( ProhibitExplicitReturnUndef )
      return undef unless -e $path_s;
      if ( not -f $path_s ) {
        return _croak("Found dist_file '$path_s', but not a file");
      }
      if ( not -r $path_s ) {
        return _croak("File '$path_s', no read permissions");
      }
      return $path_o;
    };
    return sub {
      return _wrap_return( $wrap_return_type, $pathclass_method->(@_) );
    };
  }
  if ( not $distname ) {
    my $string_method = \&File::ShareDir::dist_file;
    return sub { return _wrap_return( $wrap_return_type, $string_method->(@_) ) };
  }
  my $string_method = sub($) {
    if ( @_ != 1 or not defined $_[0] ) {
      return _croak('dist_file takes only one argument,a filename, due to distname being specified during import');
    }
    unshift @_, $distname;
    goto &File::ShareDir::dist_file;
  };
  return sub {
    return _wrap_return( $wrap_return_type, $string_method->(@_) );
  };
}

1;
