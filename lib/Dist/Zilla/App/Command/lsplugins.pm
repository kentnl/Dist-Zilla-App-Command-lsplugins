use strict;
use warnings;

package Dist::Zilla::App::Command::lsplugins;

# ABSTRACT: Show all dzil plugins on your system, with descriptions

use Moose;
use MooseX::NonMoose;
use Dist::Zilla::App -command;

=head1 SYNOPSIS

    dzil lsplugins # see a list of all plugins on your system
    dzil lsplugins --version # with versions! 
    dzil lsplugins --sort    # sort them!
    dzil lsplugins --abstract # show their ABSTRACTs!
    dzil lsplugins --with=-FilePruner # show only file pruners
    dzil lsplugins --roles=dzil  # show all the dzil related role data!

=cut

has _inc_scanner => ( is => ro =>, lazy_build => 1 );
has _plugin_dirs => ( is => ro =>, lazy_build => 1 );

sub _build__inc_scanner {
  require Path::ScanINC;
  return Path::ScanINC->new();
}

sub _build__plugin_dirs {
  my ($self) = @_;
  return [ $self->_inc_scanner->all_dirs( 'Dist', 'Zilla', 'Plugin' ) ];
}

sub _plugin_dir_iterator {
  my ($self) = @_;
  my @dirs = @{ $self->_plugin_dirs };
  return sub {
    return unless @dirs;
    return shift @dirs;
  };
}

sub _plugin_all_files_iterator {
  my ($self) = @_;
  my $dir_iterator = $self->_plugin_dir_iterator;
  my $dir;
  my $file_iterator;
  my $code;
  $code = sub {
    if ( not defined $dir ) {
      if ( not defined( $dir = $dir_iterator->() ) ) {
        return;
      }
      require Path::Tiny;
      $file_iterator = Path::Tiny->new($dir)->iterator(
        {
          recurse         => 1,
          follow_symlinks => 0,
        }
      );
    }
    my $file = $file_iterator->();
    if ( not defined $file and defined $dir ) {
      $dir = undef;
      goto $code;
    }
    return [ $dir, $file ];
  };
  return $code;
}

sub _plugin_iterator {
  my ($self) = @_;

  my $file_iterator = $self->_plugin_all_files_iterator;

  my $is_plugin = sub {
    my ($file) = @_;
    return unless $file =~ /[.]pm\z/msx;
    return unless -f $file;
    return 1;
  };

  my $code;
  my $end;
  $code = sub {
    return if $end;
    my $file = $file_iterator->();
    if ( not defined $file ) {
      $end = 1;
      return;
    }
    if ( $is_plugin->( $file->[1] ) ) {
      require Dist::Zilla::lsplugins::Module;
      return Dist::Zilla::lsplugins::Module->new(
        file            => $file->[1],
        plugin_root     => $file->[0],
        plugin_basename => 'Dist::Zilla::Plugin',
      );
    }
    goto $code;
  };
  return $code;
}

=method C<opt_spec>

Supported parameters:

=over 4

=item * C<--sort>

Sorting.

=item * C<--no-sort>

No Sorting ( B<Default> )

=item * C<--versions>

Versions

=item * C<--no-versions>

No Versions ( B<Default> )

=item * C<--abstract>

Show abstracts

=item * C<--no-abstract>

Don't show abstracts ( B<Default> )

=item * C<--roles=all>

Show all roles, unabbreviated.

=item * C<--roles=dzil-full>

Show only C<dzil> roles, unabbreviated.

=item * C<--roles=dzil>

Show only <C<dzil> roles, abbreviated.

=item * C<--with=$ROLENAME>

Show only plugins that C<< does($rolename) >>

( A - prefix will be expanded to C<Dist::Zilla::Role::> for convenience )

=back

=cut

sub opt_spec {
  return (
    [ "sort!",     "Sort by module name" ],
    [ "versions!", "Show versions" ],
    [ "abstract!", "Show Abstracts" ],
    [ "roles=s",   "Show applied roles" ],
    [ "with=s",    "Filter plugins to ones that 'do' the specified role" ]
  );
}

sub _process_plugin {
  my ( $self, $plugin, $opt, $args ) = @_;
  if ( defined $opt->with ) {
    return unless $plugin->loaded_module_does( $opt->with );
  }
  printf "%s", $plugin->plugin_name;
  if ( $opt->versions ) {
    printf " (%s)", $plugin->version;
  }
  if ( $opt->abstract ) {
    printf " - %s", $plugin->abstract;
  }
  if ( defined $opt->roles ) {
    if ( $opt->roles eq 'all' ) {
      printf " [%s]", join q[, ], @{ $plugin->roles };
    }
    elsif ( $opt->roles eq 'dzil-full' ) {
      printf " [%s]", join q[, ], grep { $_ =~ /(\A|[|])Dist::Zilla::Role::/msx } @{ $plugin->roles };
    }
    elsif ( $opt->roles eq 'dzil' ) {
      printf " [%s]", join q[, ],
        map { $_ =~ s/(^|[|])Dist::Zilla::Role::/$1-/g; $_ } grep { $_ =~ /(\A|[|])Dist::Zilla::Role::/msx } @{ $plugin->roles };
    }
  }
  print "\n";
}

=begin Pod::Coverage

execute 

=end Pod::Coverage

=cut

sub execute {
  my ( $self, $opt, $args ) = @_;

  if ( !$opt->sort ) {
    my $plugin_iterator = $self->_plugin_iterator;

    while ( my $plugin = $plugin_iterator->() ) {
      $self->_process_plugin( $plugin, $opt, $args );
    }
  }
  else {

    my $plugin_iterator = $self->_plugin_iterator;
    my @plugins;
    while ( my $plugin = $plugin_iterator->() ) {
      push @plugins, $plugin;
    }
    for my $plugin ( sort { $a->plugin_name cmp $b->plugin_name } @plugins ) {
      $self->_process_plugin( $plugin, $opt, $args );
    }
  }

}
__PACKAGE__->meta->make_immutable;
no Moose;

1;
