package Yukki::Web::View::Admin::Repository;

use v5.24;
use utf8;
use Moo;

use Type::Utils qw( class_type );
use Yukki::TemplateUtil qw( field form_error mark_radio_checked );

use namespace::clean;

extends 'Yukki::Web::View';

with 'Yukki::Web::View::Role::Navigation';

# ABSTRACT: display repository admin screens

=head1 DESCRIPTION

Shows repository admin screens.

=cut

has list_template => (
    is          => 'ro',
    isa         => class_type('Template::Pure'),
    lazy        => 1,
    builder     => '_build_list_template',
);

sub _build_list_template {
    shift->prepare_template(
        template   => 'admin/repository/list.html',
        directives => [
            '.repository' => {
                'repo<-repositories' => [
                    '.name' => 'repo.name',
                    '.title' => 'repo.name',
                    '.branch' => 'repo.branch',
                    '.default_page' => 'repo.default_page',
                    '.action' => 'repo.action | encoded_string',
                ],
            },
        ],
    );
}

has edit_template => (
    is          => 'ro',
    isa         => class_type('Template::Pure'),
    lazy        => 1,
    builder     => '_build_edit_template',
);

sub _build_edit_template {
    my @edit_fields = qw(
        name title branch default_page sort
        read_groups write_groups
    );

    shift->prepare_template(
        template   => 'admin/repository/edit.html',
        directives => [
            (map { form_error($_) } (@edit_fields, 'anonymous_access_level')),
            (map { ("#$_\@value" => field(["repository.$_", "form.$_", "default.$_"])) } @edit_fields),
            mark_radio_checked(
                'anonymous_access_level',
                'repository.anonymous_access_level',
                'form.anonymous_access_level',
                'default.anonymous_access_level',
            ),
        ],
    );
}

=head1 METHODS

=head2 standard_menu

Standard navigation menu for repository administration.

=cut

sub standard_menu {
    return map {
        +{
            action => $_,
            href   => "admin/repository/$_",
        },
    } qw( add list );
}

=head2 list

=cut

sub list {
    my ($self, $ctx, $vars) = @_;

    $ctx->response->page_title('List Repositories');
    $self->page_navigation($ctx->response, 'list');

    my @repos = map {
        my $repo = $_;
        my $action = $self->render_links(
            context => $ctx,
            links   => [
                {
                    label => 'View',
                    href  => '/page/view/' . $repo->name,
                },
                ($repo->repository_exists ? () :
                {
                    label => 'Initialize',
                    href  => '/admin/user/initialize/' . $repo->name,
                }),
            ],
        );

        {
            name => $repo->name,
            title => $repo->repository_settings->name,
            branch => $repo->repository_settings->site_branch,
            default_page => $repo->repository_settings->default_page,
            action => $action,
        }
    } sort {
        $a->repository_settings->sort <=> $b->repository_settings->sort
        || $a->repository_settings->name cmp $b->repository_settings->name
    } @{ $vars->{repositories} || [] };


    return $self->render_page(
        template => $self->list_template,
        context  => $ctx,
        vars     => {
            repositories => \@repos
        },
    );
}

=head2 edit

=cut

sub edit {
    my ($self, $ctx, $vars) = @_;

    $ctx->response->page_title('Add Repository');
    $self->page_navigation($ctx->response, 'add');
    $ctx->response->breadcrumb($vars->{breadcrumb});

    return $self->render_page(
        template => $self->edit_template,
        context  => $ctx,
        vars     => {
            form        => $vars->{form},
            form_errors => $vars->{form_errors},
            default     => $vars->{default},
        },
    );
}

=head2 initialize

=cut

sub initialize {
    my ($self, $ctx, $vars) = @_;

    $ctx->response->page_title($vars->{title});
    $ctx->response->breadcrumb($vars->{breadcrumb});

    $self->page_navigation($ctx->response, 'initialize');

    my $repo_name = $vars->{repo}->title;
    return $self->render_confirmation(
        context    => $ctx,
        title      => "Initialize $repo_name?",
        question   => "Are you sure you want to create the git repository for storing the files for $repo_name?",
        yes_label  => 'Initialize Now',
        no_link    => $vars->{return_link},
    );
}

1;