package Yukki::Web;

use v5.24;
use Moose;

extends qw( Yukki );

use Class::Load;

use Yukki::Error qw( http_throw http_exception );
use Yukki::Types qw( PluginList YukkiWebSettings );
use Yukki::Web::Context;
use Yukki::Web::Router;
use Yukki::Web::Settings;

use CHI;
use LWP::MediaTypes qw( add_type );
use Plack::Session::Store::Cache;
use Scalar::Util qw( blessed weaken );
use Try::Tiny;

# ABSTRACT: the Yukki web server

=head1 DESCRIPTION

This class handles the work of dispatching incoming requests to the various
controllers.

=head1 ATTRIBUTES

=cut

has '+settings' => ( isa => YukkiWebSettings );

=head2 router

This is the L<Path::Router> that will determine where incoming requests are
sent. It is automatically set to a L<Yukki::Web::Router> instance.

=cut

has router => (
    is          => 'ro',
    isa         => 'Path::Router',
    required    => 1,
    lazy_build  => 1,
);

sub _build_router {
    my $self = shift;
    Yukki::Web::Router->new( app => $self );
}

=head2 plugins

  my @plugins        = $app->all_plugins;
  my @format_helpers = $app->format_helper_plugins;
  my @formatters     = $app->format_plugins;

This attribute stores all the loaded plugins.

=cut

has plugins => (
    is          => 'ro',
    isa         => PluginList,
    required    => 1,
    lazy_build  => 1,
    traits      => [ 'Array' ],
    handles     => {
        all_plugins              => 'elements',
        format_helper_plugins => [ grep => sub {
            $_->does('Yukki::Web::Plugin::Role::FormatHelper')
        } ],
        formatter_plugins => [ grep => sub {
            $_->does('Yukki::Web::Plugin::Role::Formatter')
        } ],
    },
);

sub _build_plugins {
    my $self = shift;

    my @plugins;
    for my $plugin_settings (@{ $self->settings->plugins }) {
        my $module = $plugin_settings->{module};

        my $class  = $module;
           $class  = "Yukki::Web::Plugin::$class" unless $class =~ s/^\+//;

        Class::Load::load_class($class);

        push @plugins, $class->new(%$plugin_settings, app => $self);
    }

    return \@plugins;
}

=head1 METHODS

=cut

sub BUILD {
    my $self = shift;

    my $types = $self->settings->media_types;
    while (my ($mime_type, $ext) = each %$types) {
        my @ext = ref $ext ? @$ext : ($ext);
        add_type($mime_type, @ext);
    }
};

=head2 component

Helper method used by L</controller> and L</view>.

=cut

sub component {
    my ($self, $type, $name) = @_;
    my $class_name = join '::', 'Yukki::Web', $type, $name;
    Class::Load::load_class($class_name);
    return $class_name->new(app => $self);
}

=head2 controller

  my $controller = $app->controller($name);

Returns an instance of the named L<Yukki::Web::Controller>.

=cut

sub controller {
    my ($self, $name) = @_;
    return $self->component(Controller => $name);
}

=head2 view

  my $view = $app->view($name);

Returns an instance of the named L<Yukki::Web::View>.

=cut

sub view {
    my ($self, $name) = @_;
    return $self->component(View => $name);
}

=head2 dispatch

  my $response = $app->dispatch($env);

This is a PSGI application in a method call. Given a L<PSGI> environment, maps
that to the appropriate controller and fires it. Whether successful or failure,
it returns a PSGI response.

=cut

sub dispatch {
    my ($self, $env) = @_;

    my $ctx = Yukki::Web::Context->new(env => $env);

    $env->{'yukki.app'}      = $self;
    $env->{'yukki.settings'} = $self->settings;
    $env->{'yukki.ctx'}      = $ctx;
    weaken $env->{'yukki.ctx'};

    my $response;

    try {
        my $match = $self->router->match($ctx->request->path);

        http_throw('No action found matching that URL.', {
            status => 'NotFound',
        }) unless $match;

        $ctx->request->path_parameters($match->mapping);

        my $access_level_needed = $match->access_level;
        http_throw('You are not authorized to run this action.', {
            status => 'Forbidden',
        }) unless $self->check_access(
                user       => $ctx->session->{user},
                repository => $match->mapping->{repository} // '-',
                needs      => $access_level_needed,
            );

        if ($ctx->session->{user}) {
            $ctx->response->add_navigation_item(user => {
                label => 'Sign out',
                href  => 'logout',
                sort  => 100,
            });
        }

        else {
            $ctx->response->add_navigation_item(user => {
                label => 'Sign in',
                href  => 'login',
                sort  => 100,
            });
        }

        for my $repository (keys %{ $self->settings->repositories }) {
            my $config = $self->settings->repositories->{$repository};

            my $name = $config->name;
            $ctx->response->add_navigation_item(repository => {
                label => $name,
                href  => join('/', 'page/view',  $repository),
                sort  => $config->sort,
            });
        }

        my $controller = $match->target;

        $controller->fire($ctx);
        $response = $ctx->response->finalize;
    }

    catch {

        if (blessed $_ and $_->isa('Yukki::Error')) {

            if ($_->does('HTTP::Throwable::Role::Status::Forbidden')
                    and not $ctx->session->{user}) {

                $response = http_exception('Please login first.', {
                    status   => 'Found',
                    location => ''.$ctx->rebase_url('login'),
                })->as_psgi($env);
            }

            else {
                $response = $_->as_psgi($env);
            }
        }

        else {
            warn "ISE: $_";

            $response = http_exception($_, {
                status           => 'InternalServerError',
                show_stack_trace => 0,
            })->as_psgi($env);
        }
    };

    return $response;
}

=head2 session_middleware

  enable $app->session_middleware;

Returns the setup for the PSGI session middleware.

=cut

sub session_middleware {
    my $self = shift;

    # TODO Make this configurable
    return ('Session',
        store => Plack::Session::Store::Cache->new(
            cache => CHI->new(driver => 'FastMmap'),
        ),
    );
}

=head2 munge_label

  my $link = $app->munch_label("This is a label");

Turns some label into a link slug using the standard means for doing so.

=cut

sub munge_label {
    my ($self, $link) = @_;

    $link =~ m{([^/]+)$};

    $link =~ s{([a-zA-Z])'([a-zA-Z])}{$1$2}g; # foo's -> foos, isn't -> isnt
    $link =~ s{[^a-zA-Z0-9-_./]+}{-}g;
    $link =~ s{-+}{-}g;
    $link =~ s{^-}{};
    $link =~ s{-$}{};

    $link .= '.yukki';

    return $link;
}

=begin Pod::Coverage

  BUILD

=end Pod::Coverage

=cut

__PACKAGE__->meta->make_immutable;
