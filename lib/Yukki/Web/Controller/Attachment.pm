package Yukki::Web::Controller::Attachment;
use 5.12.1;
use Moose;

extends 'Yukki::Web::Controller';

use JSON;
use Yukki::Error qw( http_throw );

# ABSTRACT: Controller for uploading, downloading, and viewing attachments

=head1 DESCRIPTION

Handles uploading, downloading, and viewing attachments.

=head1 METHODS

=head2 fire

Maps download requests to L</download_file>, upload requests to L</upload_file>, and view requestst to L</view_file>.

=cut

sub fire {
    my ($self, $ctx) = @_;

    given ($ctx->request->path_parameters->{action}) {
        when ('download') { $self->download_file($ctx) }
        when ('upload')   { $self->upload_file($ctx) }
        when ('view')     { $self->view_file($ctx) }
        when ('rename')   { $self->rename_file($ctx) }
        default {
            http_throw('That attachment action does not exist.', {
                status => 'NotFound',
            });
        }
    }
}

=head2 lookup_file

  my $file = $self->lookup_file($repository, $path);

This is a helper for locating and returning a L<Yukki::Model::File> for the
requested repository and path.

=cut

sub lookup_file {
    my ($self, $repo_name, $file) = @_;

    my $repository = $self->model('Repository', { name => $repo_name });

    my $final_part = pop @$file;
    my $filetype;
    if ($final_part =~ s/\.(?<filetype>[a-z0-9]+)$//) {
        $filetype = $+{filetype};
    }

    my $path = join '/', @$file, $final_part;
    return $repository->file({ path => $path, filetype => $filetype });
}

=head2 download_file

Returns the file in the response with a MIME type of "application/octet". This
should force the browser to treat it like a download.

=cut

sub download_file {
    my ($self, $ctx) = @_;

    my $repo_name = $ctx->request->path_parameters->{repository};
    my $path      = $ctx->request->path_parameters->{file};

    my $file      = $self->lookup_file($repo_name, $path);

    $ctx->response->content_type('application/octet');
    $ctx->response->body([ scalar $file->fetch ]);
}

=head2 view_file

Returns the file in the response with a MIME type reported by
L<Yukki::Model::File/media_type>.

=cut

sub view_file {
    my ($self, $ctx) = @_;

    my $repo_name = $ctx->request->path_parameters->{repository};
    my $path      = $ctx->request->path_parameters->{file};

    my $file      = $self->lookup_file($repo_name, $path);

    $ctx->response->content_type($file->media_type);
    $ctx->response->body([ scalar $file->fetch ]);
}

=head2 rename_file

Handles attachment renaming via the page rename controller.

=cut

sub rename_file {
    my ($self, $ctx) = @_;

    my $file = $ctx->request->path_parameters->{file};
    $ctx->request->path_parameters->{page} = $file;

    $self->controller('Page')->fire($ctx);
}

=head2 upload_file

This uploads the file given into the wiki.

=cut

sub upload_file {
    my ($self, $ctx) = @_;

    my $repo_name = $ctx->request->path_parameters->{repository};
    my $path      = $ctx->request->path_parameters->{file};

    my $file      = $self->lookup_file($repo_name, $path);
    
    if (my $user = $ctx->session->{user}) {
        $file->author_name($user->{name});
        $file->author_email($user->{email});
    }

    my $upload = $ctx->request->uploads->{file};
    $file->store({
        filename => $upload->tempname,
        comment  => 'Uploading file ' . $upload->filename,
    });

    $ctx->response->content_type('application/json');
    $ctx->response->body(
        encode_json({
            viewable        => 1,
            repository_path => join('/', $repo_name, $file->full_path),
        })
    );
}

1;
