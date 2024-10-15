# NAME

Dist::Zilla::App::Command::CompareMint - Compare files to what a minting profile produces

# SYNOPSIS

```
$ dzil compare-mint [ --provider=<provider> ] [ --profile=<profile> ]
```

# DESCRIPTION

Displays a diff of the current dist with what would be created by minting a
dist with the same name.

Additional files in the current dist, files in the \`t\` or \`lib\` directories,
\`Changes\`, and \`Changelog\` files will be ignored.

While the output is produced using unified diff format, it is only meant to be
interpreted by a human.

# OPTIONS

- --color\[=&lt;when>\]

    Show colored diff. If `<when>` is not specified or is `always`, color
    will be used. If `<when>` is `auto` or when the option is not specified,
    color will be used when the output is a terminal.

- --no-pager

    Avoid using a pager. By default, `$PAGER` or `less` will be used if the
    output is a terminal.

- --provider=&lt;provider>

    The minting provider to compare against. If not specified, it will try to use
    the value configured in the `[%Mint]` section of either the `dist.ini` or
    `~/.dzil/config.ini` file.

- --profile=&lt;profile>

    The minting profile to compare against. If not specified, it will try to use
    the value configured in the `[%Mint]` section of either the `dist.ini` or
    `~/.dzil/config.ini` file.

- --reverse

    Generate the diff in reverse order.

# BUGS

Please report any bugs or feature requests on the bugtracker website
[https://github.com/haarg/Dist-Zilla-App-Command-DiffMint/issues](https://github.com/haarg/Dist-Zilla-App-Command-DiffMint/issues)

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

# AUTHOR

Graham Knop <haarg@haarg.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2024 by Graham Knop.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
