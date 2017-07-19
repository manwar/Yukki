package Yukki::Settings;

use v5.24;
use utf8;
use Moo;

use Types::Path::Tiny qw( Path );
use Types::Standard qw( Str );
use Yukki::Types qw( RepositoryMap YukkiSettingsAnonymous );

use namespace::clean;

# ABSTRACT: provides structure and validation to settings in yukki.conf

=head1 DESCRIPTION

This class provides structure for the main application configuration in L<Yukki>.

Yukki may fail to start unless your configuration is correct.

=head1 ATTRIBUTES

=head2 root

This is the wiki site directory. This should be the same folder that was given the F<yukki-setup> command. It works best if you make this an absolute path.

=cut

has root => (
    is          => 'ro',
    isa         => Path,
    required    => 1,
    coerce      => 1,
    default     => '.',
);

=head2 repository_path

This is the folder where Yukki will find the git repositories installed under C<root>. The default is F<root/repositories>.

=cut

has repository_path => (
    is          => 'ro',
    isa         => Path,
    required    => 1,
    coerce      => 1,
    default     => 'repositories',
);

=head2 user_path

This is the folder where the list of user files can be found.

=cut

has user_path => (
    is          => 'ro',
    isa         => Path,
    required    => 1,
    coerce      => 1,
    default     => 'var/db/users',
);

=head2 digest

This is the name of the digest algorithm to use to store passwords. See L<Digest> for more information. The default is "SHA-512".

N.B. If you change digest algorithms, old passwords saved with the old digest algorithm will continue to work as long as the old digest algorithm class is still installed.

=cut

has digest => (
    is          => 'ro',
    isa         => Str,
    required    => 1,
    default     => 'SHA-512',
);

=head2 anonymous

This is a section configuring anonymous user information.

=over

=item author_name

This is the name to use when an anonymous user makes a change to a wiki repository.

=item author_email

This is the email address to use when an anonymous user makes a change to a wiki repository.

=back

=cut

has anonymous => (
    is          => 'ro',
    isa         => YukkiSettingsAnonymous,
    required    => 1,
    coerce      => 1,
    default     => sub { Yukki::Settings::Anonymous->new },
);

=head2 repositories

This is a section under which each repository is configured. The keys under here are the name found in the URL. It is also the name to use when running the F<yukki-git-init> and other repository-related commands.

Each repository configuraiton should provide the following configruation keys.

=over

=item repository

This is required. This is the name of the git repository folder found under C<repository_path>.

=item site_branch

This is teh name of the branch that will contain the wiki's files. The default is C<refs/heads/master>. You could actually use the same git repository for multiple Yukki repositories by using different branches. If you want to do it that way for some reason. Unless you know what you're doing, you probably don't want to do that.

=item name

This is a human readable title for the repository.

=item default_page

This is the name of the main repository index.

=item anonymous_access_level

This should be set to one of the following: read, write, or none. This settings decides how much access an anonymous user has when visiting your wiki.

=item read_groups

This may be set to the word "ANY" or the word "NONE" or to an array of group names.

If set to ANY, any logged user may read this repository. If set to NONE, read access is not granted to any logged user (though if C<anonymous_access_level> or C<write_groups> grant a user access, the user will be able to read the repository).

If an array of one or more group names are given, the users with any of those groups will be able to read the repository.

=item write_groups

THe possible values that may be set are identicl to C<read_groups>. This setting determines who has permission to edit pages and upload files to the repository.

=back

=cut

has repositories => (
    is          => 'ro',
    isa         => RepositoryMap,
    required    => 1,
    coerce      => 1,
);

{
    package Yukki::Settings::Anonymous;

    use Moo;
    use Types::Standard qw( Str );
    use Yukki::Types qw( EmailAddress );

    has author_name => (
        is          => 'ro',
        isa         => Str,
        required    => 1,
        default     => 'Anonymous',
    );

    has author_email => (
        is          => 'ro',
        isa         => EmailAddress,
        required    => 1,
        coerce      => 1,
        default     => 'anonymous@localhost',
    );
}

{
    package Yukki::Settings::Repository;

    use Moo;
    use Types::Path::Tiny qw( Path );
    use Types::Standard qw( ArrayRef Int Str );

    has repository => (
        is          => 'ro',
        isa         => Path,
        required    => 1,
        coerce      => 1,
    );

    has site_branch => (
        is          => 'ro',
        isa         => Str,
        required    => 1,
        default     => 'refs/heads/master',
    );

    has name => (
        is          => 'ro',
        isa         => Str,
        required    => 1,
    );

    has default_page => (
        is          => 'ro',
        isa         => Path,
        required    => 1,
        coerce      => 1,
        default     => 'home.yukki',
    );

    has sort => (
        is          => 'ro',
        isa         => Int,
        required    => 1,
        default     => 50,
    );

    has anonymous_access_level => (
        is          => 'ro',
        isa         => Yukki::Types::AccessLevel,
        required    => 1,
        default     => 'none',
    );

    has read_groups => (
        is          => 'ro',
        isa         => Str|ArrayRef[Str],
        required    => 1,
        default     => 'NONE',
    );

    has write_groups => (
        is          => 'ro',
        isa         => Str|ArrayRef[Str],
        required    => 1,
        default     => 'NONE',
    );
}

1;
