use v5.20; use warnings; use experimental qw(signatures postderef);
package Dist::Zilla::App::Command::DiffMint;

our $VERSION = 'v0.2.1';

use Dist::Zilla::App -command;

use namespace::autoclean;

sub command_names { 'diff-mint' }

sub opt_spec { (
  [ 'profile|p=s',  'name of the profile to use' ],
  [ 'provider|P=s', 'name of the profile provider to use' ],
  [ 'color:s',      'colorize output' ],
  [ 'reverse!',     'reverse diff' ],
  [ 'no-pager',     'avoid pager' ],
) }

sub execute ($self, $opt, $arg) {
  my $provider = $opt->provider;
  my $profile = $opt->profile;
  my $reverse = $opt->reverse;
  my $color
    = (!defined $opt->color || $opt->color eq 'auto') ? -t *STDOUT
    : ($opt->color eq '' || $opt->color eq 'always')  ? 1
    : $opt->color eq 'never'                          ? 0
    : die q[Error: option 'color' expects "always", "auto", or "never", not "] . $opt->color . qq["!\n];

  my $out
    = $opt->no_pager ? \*STDOUT
    : !-t *STDOUT    ? \*STDOUT
    : do {
      local $ENV{LESS} = $ENV{LESS} || 'SRFX';
      my $pager = $ENV{PAGER} || 'less';
      if (open my $fh, '|-', $pager) {
        $fh;
      }
      else {
        \*STDOUT;
      }
    };

  my $minter = $self->_minter($provider, $profile);

  $_->gather_files       for @{ $minter->plugins_with(-FileGatherer) };
  $_->set_file_encodings for @{ $minter->plugins_with(-EncodingProvider) };
  $_->prune_files        for @{ $minter->plugins_with(-FilePruner) };
  $_->munge_files        for @{ $minter->plugins_with(-FileMunger) };

  require Digest::SHA;

  my $root = $self->zilla->root;

  my %files = map +($_->name => $_), $minter->files->@*;
  my @files = map $_->name, $minter->files->@*;
  if (@$arg) {
    my @matched;
    for my $arg (@$arg) {
      my $dir = $arg =~ s{/\z}{};

      if ($files{$arg}) {
        push @matched, $arg;
      }
      elsif (-f $root->child($arg)) {
        push @matched, $arg;
      }
      elsif (my @sub = grep m{\A$dir/}, @files) {
        push @matched, @sub;
      }
      else {
        die "Unknown file or directory $arg!\n";
      }
    }
    @files = @matched;
  }
  else {
      @files = grep !m{^lib/|^t/|^Changes$|^Changelog$}i, @files;
  }

  for my $name (@files) {
    my $file = $files{$name};

    my $mint = $file ? {
      name      => "mint/$name",
      realname  => "mint/$name",
      encoding  => $file->encoding,
      content   => $file->content,
      mode      => sprintf("%06o", $file->mode | 0100644),
      sha       => _sha($file->encoded_content),
    } : _null("mint/$name");

    my $disk = $self->_file_data($root, $name);

    my ($old, $new) = $reverse ? ($mint, $disk) : ($disk, $mint);

    my $diff = _diff($old, $new);

    next
      if !defined $diff;

    if ($color) {
      print { $out } _colorize($diff);
    }
    else {
      print { $out } $diff;
    }
  }
}

sub _null ($name) {
  return {
    name      => $name,
    realname  => '/dev/null',
    content   => '',
    mode      => '',
    sha       => '0' x 40,
    encoding  => 'UTF-8',
  };
}

sub _file_data ($self, $root, $name) {
  my $file = $root->child($name);

  if (open my $fh, '<:raw', $file->stringify) {
    my $mode = (stat($fh))[2] | 0100644;
    my $binary = -B $fh;
    my $content = do { local $/; <$fh> };
    my $sha = _sha($content);
    my $encoding;
    if ($binary) {
      $encoding = 'bytes';
    }
    else {
      require Encode::Guess;
      my $encoder = Encode::Guess::guess_encoding($content, qw(UTF-8 Latin1 ASCII));
      $encoding = $encoder->name;
      $content = $encoder->decode($content);
    }
    close $fh;

    return {
      name      => "dist/$name",
      realname  => "dist/$name",
      content   => $content,
      mode      => sprintf("%06o", $mode),
      sha       => $sha,
      encoding  => $encoding,
    };
  }

  return _null("dist/$name");
}

sub _minter ($self, $opt_provider, $opt_profile) {
  my $zilla = $self->zilla;

  my $global_stash = $self->app->_build_global_stashes; ## no critic (Subroutines::ProtectPrivateSubs)

  my $global_mint_stash = $global_stash->{'%Mint'};
  my $dist_mint_stash = $zilla->stash_named('%Mint');

  my $provider
    = $opt_provider
    // ($dist_mint_stash && $dist_mint_stash->provider)
    // ($global_mint_stash && $global_mint_stash->provider)
    // 'Default';

  my $profile
    = $opt_profile
    // ($dist_mint_stash && $dist_mint_stash->profile)
    // ($global_mint_stash && $global_mint_stash->profile)
    // 'Default';

  my $stashes = $self->_stashes;

  require Dist::Zilla::Dist::Minter;
  return Dist::Zilla::Dist::Minter->_new_from_profile( ## no critic (Subroutines::ProtectPrivateSubs)
    [ $provider, $profile ],
    {
      chrome  => $self->app->chrome,
      name    => $zilla->name,
      _global_stashes => {
        %$global_stash,
        %$stashes,
      },
    },
  );
}

sub _stashes ($self) {
  my $zilla = $self->zilla;
  my $stashes = {};
  if ($zilla->authors->@*) {
    $stashes->{'%User'} = $self->_authors_stash([ $zilla->authors->@* ]);
  }

  require Dist::Zilla::Stash::Rights;
  my $license = $zilla->license;
  my $license_class = ref $license;
  $license_class =~ s/^(Software::License::)?/$1 ? '' : '='/e;
  $stashes->{'%Rights'} = Dist::Zilla::Stash::Rights->new(
    copyright_holder => $license->holder,
    copyright_year => $license->year,
    license_class => $license_class,
  );

  return $stashes;
}

sub _sha ($content) {
  require Digest::SHA;
  return Digest::SHA::sha1_hex('blob ' . length($content) . "\0" . $content);
}

sub _diff ($old, $new) {
  require Text::Diff;
  my $mode_diff = '';
  if ($new->{mode} ne $old->{mode}) {
    $mode_diff .= "old file mode $old->{mode}\n"
      if $old->{mode};
    $mode_diff .= "new file mode $new->{mode}\n"
      if $new->{mode};
  }

  my $text_diff;
  if ($old->{encoding} eq 'bytes' || $new->{encoding} eq 'bytes') {
    if ($old->{content} ne $new->{content}) {
      $text_diff = "Binary files $old->{realname} and $new->{realname} differ\n";
    }
  }
  else {
    $text_diff = Text::Diff::diff(\$old->{content}, \$new->{content}, {
      STYLE => 'Unified',
      FILENAME_A => $old->{realname},
      FILENAME_B => $new->{realname},
    }) // '';
  }

  return undef
    if !length $mode_diff && !length $text_diff;

  return sprintf(
    "diff --git %s %s\n"
    . '%s'
    . "index %.7s..%.7s\n"
    . '%s', (
      $old->{name},
      $new->{name},
      $mode_diff,
      $old->{sha},
      $new->{sha},
      $text_diff,
    )
  );
}

sub _colorize ($diff) {
  require Term::ANSIColor;
  my $out = '';
  while ($diff =~ /\G([^\n]*)(?:\n|\z)/gc) {
    my $line = $1;
    my $color;
    if ($line =~ /^(?:diff|old mode|new mode|index)/) {
      $color = 'bold bright_white'
    }
    elsif ($line =~ /^(?:---|\+\+\+)/) {
      $color = 'bold bright_white';
    }
    elsif ($line =~ /^@@/) {
      $color = 'cyan';
    }
    elsif ($line =~ /^\+/) {
      $color = 'green';
    }
    elsif ($line =~ /^\-/) {
      $color = 'red';
    }
    elsif ($line =~ /^ /) {
      # nothing
    }
    else {
      # ???
    }

    if ($color) {
      $out .= Term::ANSIColor::colored([$color], $line) . "\n";
    }
    else {
      $out .= $line . "\n";
    }
  }
  return $out;
}

my $authors_meta;
sub _authors_stash ($self, $authors) {
  $authors_meta ||= do {
    require Moose::Meta::Class;
    require Moose::Util;
    my $meta = Moose::Meta::Class->create_anon_class;
    $meta->add_attribute(authors => (
      is => 'ro',
      isa => 'ArrayRef[Str]',
    ));
    Moose::Util::apply_all_roles($meta, qw(
      Dist::Zilla::Role::Stash::Authors
    ));
    $meta->make_immutable;
    $meta;
  };
  $authors_meta->name->new(authors => $authors);
}

1;
__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::App::Command::CompareMint - Compare files to what a minting profile produces

=head1 SYNOPSIS

  $ dzil diff-mint [ --provider=<provider> ] [ --profile=<profile> ] [ <file> ]

=head1 DESCRIPTION

Displays a diff of the current dist with what would be created by minting a
dist with the same name.

Additional files in the current dist, files in the `t` or `lib` directories,
`Changes`, and `Changelog` files will be ignored.

While the output is produced using unified diff format, it is only meant to be
interpreted by a human.

=head1 OPTIONS

=over 4

=item --color[=<when>]

Show colored diff. If C<< <when> >> is not specified or is C<always>, color
will be used. If C<< <when> >> is C<auto> or when the option is not specified,
color will be used when the output is a terminal.

=item --no-pager

Avoid using a pager. By default, C<$PAGER> or C<less> will be used if the
output is a terminal.

=item --provider=<provider>

The minting provider to compare against. If not specified, it will try to use
the value configured in the C<[%Mint]> section of either the F<dist.ini> or
F<~/.dzil/config.ini> file.

=item --profile=<profile>

The minting profile to compare against. If not specified, it will try to use
the value configured in the C<[%Mint]> section of either the F<dist.ini> or
F<~/.dzil/config.ini> file.

=item --reverse

Generate the diff in reverse order.

=back
