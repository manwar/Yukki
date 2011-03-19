;(function(){

var periodic_tasks = [];

function add_periodic_task(code) {
    periodic_tasks[periodic_tasks.length] = code;
}

var templates = {};
function fetch_template(name, code) {
    
    // Keep a cache of templates already loaded
    if (templates[name]) {
        code(templates[name]);
    }

    // Load a new template if not already cached
    else {
        $.get('/template/' + name, function(data) {
            templates[name] = data;
            code(data);
        });
    }
}

setInterval(function() {
    for (var i in periodic_tasks) {
        periodic_tasks[i]();
    }
}, 10000);

$(document).ready(function() {
    $(':button').button();

    if ($('#preview-yukkitext').length > 0) {
        add_periodic_task(function() {
            var url = String(window.location).replace(/\/edit\//, '/preview/');
            $.post(url, { 'yukkitext': $('#yukkitext').val() }, 
                function(data) {
                    $('#preview-yukkitext').html(data);
                }
            );
        });
    }

    $('.attachments').each(function() {
        var $this = $(this);

        var $picker    = $this.find('.attachment-picker');
        var $file_list = $this.find('.attachment-list');
        var $drop_zone = $this.find('.attachment-dropzone');
        var $starter   = $this.find('.attachment-start');

        var uploader = new plupload.Uploader({
            'runtimes'            : 'gears,html5,flash,silverlight,html4',
            'browse_button'       : $picker[0].id,
            'container'           : $file_list[0].id,
            'drop_element'        : $drop_zone[0].id,
            'url'                 : String(window.location).replace(/\/edit\//, '/attach/'),
            'flash_swf_url'       : '/script/lib/plupload/plupload.flash.swf',
            'silverlight_xap_url' : '/script/lib/plupload/plupload.silverlight.xap'
        });

        $starter.click(function(e) {
            uploader.start();
            e.preventDefault();
        });

        add_periodic_task(function() { uploader.start(); });

        uploader.init();

        var file_id_memo = {};
        function file_id(file) {
            if (file_id_memo[file.name]) {
                return file_id_memo[file.name];
            }
            else {
                return file_id_memo[file.name] = Sha1.hash(file.name);
            }
        }

        uploader.bind('FilesAdded', function(up, files) {
            fetch_template('page/attachments.html', function(attachments_template) {
                var was_empty = false;
                if ($file_list.is('.empty')) {
                    $file_list.removeClass('empty').empty().append(attachments_template);
                    was_empty = true;
                }

                $.each(files, function(i, file) {
                    var new_row = $file_list.find('.attachment-table #' + file_id(file));
                    var cloned = false;
                    if (!new_row) {
                        new_row = $file_list.find('.attachment-table .file:first').clone();
                        cloned = true;
                    }

                    new_row.attr('id', file_id(file));
                    new_row.find('.filename').text(file.name);
                    new_row.find('.size').text(plupload.formatSize(file.size));
                    new_row.find('.action').html('<div class="progress"></div>');

                    if (cloned) {
                        $file_list.find('tbody').append(new_row);
                    }

                    $file_list.find('#' + file_id(file) + ' .progress').progressbar({ 'value': 0 });
                });

                if (was_empty) {
                    $file_list.find('.attachment-table .file:first').remove();
                }

                up.refresh();
                $starter.show();
            });
        });

        uploader.bind('UploadProgress', function(up, file) {
            $('#' + file_id(file) + ' .progress').progressbar({ 'value': file.percent });
        });

        uploader.bind('FileUploaded', function(up, file, res) {
            var json = eval('('+res.response+')');

            $('#' + file_id(file) + ' .action').empty().append('<ul class="links"></ul>');
            if (json.viewable) {
                $('#' + file_id(file) + ' .links').append(
                    '<li><a href="/attachment/view/' + json.repository_path + '">View</a></li>'
                );
            }

            $('#' + file_id(file) + ' .links').append(
                '<li><a href="/attachment/download/' + json.repository_path + '">Download</a></li>'
            );

            $starter.hide();
        });

        if (uploader.features.dragdrop) {
            $drop_zone.show();
            $picker.hide();
            $starter.hide();
        }
    });
});
})();
