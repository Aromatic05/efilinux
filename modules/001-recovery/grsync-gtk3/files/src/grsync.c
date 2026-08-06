#include <gtk/gtk.h>
#include <gio/gio.h>
#include <string.h>

typedef struct {
    gboolean archive;
    gboolean contents;
    gboolean compress;
    gboolean delete_files;
    gboolean partial;
    gboolean dry_run;
} SyncOptions;

typedef struct {
    GtkWidget *window;
    GtkWidget *source_entry;
    GtkWidget *destination_entry;
    GtkWidget *archive_check;
    GtkWidget *contents_check;
    GtkWidget *compress_check;
    GtkWidget *delete_check;
    GtkWidget *partial_check;
    GtkWidget *dry_run_check;
    GtkWidget *command_view;
    GtkWidget *output_view;
    GtkWidget *run_button;
    GtkWidget *stop_button;
    GSubprocess *process;
} AppState;

static gboolean is_remote_path(const gchar *path)
{
    const gchar *colon = strchr(path, ':');
    const gchar *slash = strchr(path, '/');
    return colon != NULL && (slash == NULL || colon < slash);
}

static gboolean path_is_within(const gchar *child, const gchar *parent)
{
    gsize parent_length = strlen(parent);
    if (g_strcmp0(parent, G_DIR_SEPARATOR_S) == 0)
        return g_path_is_absolute(child);
    if (!g_str_has_prefix(child, parent))
        return FALSE;
    return child[parent_length] == '\0' || child[parent_length] == G_DIR_SEPARATOR;
}

static void show_error(AppState *state, const gchar *message)
{
    GtkWidget *dialog = gtk_message_dialog_new(
        GTK_WINDOW(state->window),
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        GTK_MESSAGE_ERROR,
        GTK_BUTTONS_CLOSE,
        "%s",
        message);
    gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_destroy(dialog);
}

static gchar **build_sync_argv(const gchar *source_text,
                               const gchar *destination_text,
                               const SyncOptions *options,
                               GError **error)
{
    gchar *source = g_strdup(source_text);
    gchar *destination = g_strdup(destination_text);
    gchar *canonical_source = NULL;
    gchar *canonical_destination = NULL;
    GPtrArray *args;

    g_strstrip(source);
    g_strstrip(destination);

    if (*source == '\0' || *destination == '\0') {
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                            "Source and destination are required.");
        goto fail;
    }

    if (!is_remote_path(source) && !g_file_test(source, G_FILE_TEST_IS_DIR)) {
        g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND,
                    "Source directory does not exist: %s", source);
        goto fail;
    }

    if (!is_remote_path(source) && !is_remote_path(destination)) {
        canonical_source = g_canonicalize_filename(source, NULL);
        canonical_destination = g_canonicalize_filename(destination, NULL);
        if (g_strcmp0(canonical_source, canonical_destination) == 0) {
            g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                                "Source and destination must be different.");
            goto fail;
        }
        if (path_is_within(canonical_destination, canonical_source) ||
            path_is_within(canonical_source, canonical_destination)) {
            g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_ARGUMENT,
                                "Source and destination directories must not contain each other.");
            goto fail;
        }
    }

    if (options->contents && !g_str_has_suffix(source, "/")) {
        gchar *with_slash = g_strconcat(source, "/", NULL);
        g_free(source);
        source = with_slash;
    }

    args = g_ptr_array_new_with_free_func(g_free);
    g_ptr_array_add(args, g_strdup("rsync"));
    g_ptr_array_add(args, g_strdup(options->archive ? "--archive" : "--recursive"));
    g_ptr_array_add(args, g_strdup("--human-readable"));
    g_ptr_array_add(args, g_strdup("--info=progress2"));

    if (options->compress)
        g_ptr_array_add(args, g_strdup("--compress"));
    if (options->delete_files)
        g_ptr_array_add(args, g_strdup("--delete"));
    if (options->partial)
        g_ptr_array_add(args, g_strdup("--partial"));
    if (options->dry_run)
        g_ptr_array_add(args, g_strdup("--dry-run"));

    g_ptr_array_add(args, source);
    source = NULL;
    g_ptr_array_add(args, destination);
    destination = NULL;
    g_ptr_array_add(args, NULL);

    g_free(canonical_source);
    g_free(canonical_destination);
    return (gchar **)g_ptr_array_free(args, FALSE);

fail:
    g_free(source);
    g_free(destination);
    g_free(canonical_source);
    g_free(canonical_destination);
    return NULL;
}

static gchar **build_argv(AppState *state, GError **error)
{
    SyncOptions options = {
        .archive = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(state->archive_check)),
        .contents = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(state->contents_check)),
        .compress = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(state->compress_check)),
        .delete_files = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(state->delete_check)),
        .partial = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(state->partial_check)),
        .dry_run = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(state->dry_run_check)),
    };
    return build_sync_argv(
        gtk_entry_get_text(GTK_ENTRY(state->source_entry)),
        gtk_entry_get_text(GTK_ENTRY(state->destination_entry)),
        &options,
        error);
}

static gchar *format_command(gchar **argv)
{
    GString *command = g_string_new(NULL);
    for (gsize i = 0; argv[i] != NULL; ++i) {
        gchar *quoted = g_shell_quote(argv[i]);
        if (i != 0)
            g_string_append_c(command, ' ');
        g_string_append(command, quoted);
        g_free(quoted);
    }
    return g_string_free(command, FALSE);
}

static void update_preview(AppState *state)
{
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(state->command_view));
    GError *error = NULL;
    gchar **argv = build_argv(state, &error);

    if (argv == NULL) {
        gtk_text_buffer_set_text(buffer, error != NULL ? error->message : "", -1);
        g_clear_error(&error);
        return;
    }

    gchar *command = format_command(argv);
    gtk_text_buffer_set_text(buffer, command, -1);
    g_free(command);
    g_strfreev(argv);
}

static void on_option_changed(GtkWidget *widget, gpointer user_data)
{
    (void)widget;
    update_preview((AppState *)user_data);
}

static void on_browse_clicked(GtkButton *button, gpointer user_data)
{
    AppState *state = user_data;
    GtkWidget *entry = g_object_get_data(G_OBJECT(button), "target-entry");
    const gchar *title = g_object_get_data(G_OBJECT(button), "chooser-title");
    GtkWidget *dialog = gtk_file_chooser_dialog_new(
        title,
        GTK_WINDOW(state->window),
        GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER,
        "_Cancel", GTK_RESPONSE_CANCEL,
        "_Select", GTK_RESPONSE_ACCEPT,
        NULL);

    const gchar *current = gtk_entry_get_text(GTK_ENTRY(entry));
    if (*current != '\0' && !is_remote_path(current))
        gtk_file_chooser_set_filename(GTK_FILE_CHOOSER(dialog), current);

    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
        gchar *path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
        gtk_entry_set_text(GTK_ENTRY(entry), path);
        g_free(path);
    }
    gtk_widget_destroy(dialog);
}

static void set_output(AppState *state, const gchar *stdout_text,
                       const gchar *stderr_text, const gchar *status)
{
    GtkTextBuffer *buffer = gtk_text_view_get_buffer(GTK_TEXT_VIEW(state->output_view));
    GString *text = g_string_new(NULL);

    if (status != NULL && *status != '\0')
        g_string_append_printf(text, "%s\n\n", status);
    if (stdout_text != NULL && *stdout_text != '\0')
        g_string_append(text, stdout_text);
    if (stderr_text != NULL && *stderr_text != '\0') {
        if (text->len != 0 && text->str[text->len - 1] != '\n')
            g_string_append_c(text, '\n');
        g_string_append(text, stderr_text);
    }

    gtk_text_buffer_set_text(buffer, text->str, -1);
    g_string_free(text, TRUE);
}

static void on_process_complete(GObject *source_object, GAsyncResult *result,
                                gpointer user_data)
{
    AppState *state = user_data;
    GSubprocess *process = G_SUBPROCESS(source_object);
    GError *error = NULL;
    gchar *stdout_text = NULL;
    gchar *stderr_text = NULL;
    gchar *status;

    if (!g_subprocess_communicate_utf8_finish(process, result, &stdout_text,
                                               &stderr_text, &error)) {
        status = g_strdup_printf("rsync failed: %s", error->message);
        g_clear_error(&error);
    } else if (g_subprocess_get_successful(process)) {
        status = g_strdup("rsync completed successfully.");
    } else if (g_subprocess_get_if_exited(process)) {
        status = g_strdup_printf("rsync exited with status %d.",
                                 g_subprocess_get_exit_status(process));
    } else {
        status = g_strdup("rsync was terminated.");
    }

    if (state->window != NULL) {
        set_output(state, stdout_text, stderr_text, status);
        gtk_widget_set_sensitive(state->run_button, TRUE);
        gtk_widget_set_sensitive(state->stop_button, FALSE);
    }
    g_free(stdout_text);
    g_free(stderr_text);
    g_free(status);
    g_clear_object(&state->process);
}

static gboolean confirm_delete(AppState *state)
{
    const gchar *destination = gtk_entry_get_text(GTK_ENTRY(state->destination_entry));
    GtkWidget *dialog = gtk_message_dialog_new(
        GTK_WINDOW(state->window),
        GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
        GTK_MESSAGE_WARNING,
        GTK_BUTTONS_NONE,
        "Delete files from the destination that are absent from the source?");
    gtk_message_dialog_format_secondary_text(
        GTK_MESSAGE_DIALOG(dialog),
        "Destination: %s\n\nThis changes existing data. Confirm only after reviewing the dry-run output.",
        destination);
    gtk_dialog_add_buttons(GTK_DIALOG(dialog), "_Cancel", GTK_RESPONSE_CANCEL,
                           "_Delete and synchronize", GTK_RESPONSE_ACCEPT, NULL);
    gint response = gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_destroy(dialog);
    return response == GTK_RESPONSE_ACCEPT;
}

static void on_run_clicked(GtkButton *button, gpointer user_data)
{
    (void)button;
    AppState *state = user_data;
    GError *error = NULL;
    gchar **argv = build_argv(state, &error);

    if (argv == NULL) {
        show_error(state, error != NULL ? error->message : "Invalid synchronization settings.");
        g_clear_error(&error);
        return;
    }

    gboolean deleting = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(state->delete_check));
    gboolean dry_run = gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(state->dry_run_check));
    if (deleting && !dry_run && !confirm_delete(state)) {
        g_strfreev(argv);
        return;
    }

    GSubprocessLauncher *launcher = g_subprocess_launcher_new(
        G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_PIPE);
    g_subprocess_launcher_setenv(launcher, "PATH", "/opt/recovery/bin:/usr/bin:/bin", TRUE);
    state->process = g_subprocess_launcher_spawnv(
        launcher, (const gchar * const *)argv, &error);
    g_object_unref(launcher);
    g_strfreev(argv);

    if (state->process == NULL) {
        show_error(state, error->message);
        g_clear_error(&error);
        return;
    }

    set_output(state, NULL, NULL, dry_run ? "Running dry-run preview..." : "Synchronizing...");
    gtk_widget_set_sensitive(state->run_button, FALSE);
    gtk_widget_set_sensitive(state->stop_button, TRUE);
    g_subprocess_communicate_utf8_async(state->process, NULL, NULL,
                                        on_process_complete, state);
}

static void on_stop_clicked(GtkButton *button, gpointer user_data)
{
    (void)button;
    AppState *state = user_data;
    if (state->process != NULL)
        g_subprocess_force_exit(state->process);
}

static void on_window_destroy(GtkWidget *widget, gpointer user_data)
{
    (void)widget;
    AppState *state = user_data;
    state->window = NULL;
    if (state->process != NULL)
        g_subprocess_force_exit(state->process);
}

static GtkWidget *new_path_row(AppState *state, GtkWidget *grid, gint row,
                               const gchar *label_text, GtkWidget **entry_out,
                               const gchar *chooser_title)
{
    GtkWidget *label = gtk_label_new(label_text);
    GtkWidget *entry = gtk_entry_new();
    GtkWidget *button = gtk_button_new_with_label("Browse...");
    gtk_widget_set_halign(label, GTK_ALIGN_START);
    gtk_widget_set_hexpand(entry, TRUE);
    gtk_grid_attach(GTK_GRID(grid), label, 0, row, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), entry, 1, row, 1, 1);
    gtk_grid_attach(GTK_GRID(grid), button, 2, row, 1, 1);
    g_object_set_data(G_OBJECT(button), "target-entry", entry);
    g_object_set_data_full(G_OBJECT(button), "chooser-title",
                           g_strdup(chooser_title), g_free);
    g_signal_connect(button, "clicked", G_CALLBACK(on_browse_clicked), state);
    g_signal_connect(entry, "changed", G_CALLBACK(on_option_changed), state);
    *entry_out = entry;
    return entry;
}

static void activate(GtkApplication *application, gpointer user_data)
{
    (void)user_data;
    AppState *state = g_new0(AppState, 1);
    GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    GtkWidget *paths = gtk_grid_new();
    GtkWidget *options = gtk_grid_new();
    GtkWidget *command_frame = gtk_frame_new("Command preview");
    GtkWidget *command_scroll = gtk_scrolled_window_new(NULL, NULL);
    GtkWidget *output_frame = gtk_frame_new("Output");
    GtkWidget *output_scroll = gtk_scrolled_window_new(NULL, NULL);
    GtkWidget *buttons = gtk_button_box_new(GTK_ORIENTATION_HORIZONTAL);

    state->window = gtk_application_window_new(application);
    gtk_window_set_title(GTK_WINDOW(state->window), "Grsync");
    gtk_window_set_default_size(GTK_WINDOW(state->window), 760, 600);
    gtk_container_set_border_width(GTK_CONTAINER(outer), 12);
    gtk_container_add(GTK_CONTAINER(state->window), outer);

    gtk_grid_set_row_spacing(GTK_GRID(paths), 8);
    gtk_grid_set_column_spacing(GTK_GRID(paths), 8);
    new_path_row(state, paths, 0, "Source", &state->source_entry,
                 "Select source directory");
    new_path_row(state, paths, 1, "Destination", &state->destination_entry,
                 "Select destination directory");
    gtk_box_pack_start(GTK_BOX(outer), paths, FALSE, FALSE, 0);

    gtk_grid_set_row_spacing(GTK_GRID(options), 6);
    gtk_grid_set_column_spacing(GTK_GRID(options), 18);
    state->archive_check = gtk_check_button_new_with_label("Archive mode");
    state->contents_check = gtk_check_button_new_with_label("Copy source contents");
    state->compress_check = gtk_check_button_new_with_label("Compress transfer");
    state->delete_check = gtk_check_button_new_with_label("Delete destination extras");
    state->partial_check = gtk_check_button_new_with_label("Keep partial files");
    state->dry_run_check = gtk_check_button_new_with_label("Dry run");
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->archive_check), TRUE);
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->contents_check), TRUE);
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->partial_check), TRUE);
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(state->dry_run_check), TRUE);

    GtkWidget *checks[] = {
        state->archive_check, state->contents_check, state->compress_check,
        state->delete_check, state->partial_check, state->dry_run_check
    };
    for (guint i = 0; i < G_N_ELEMENTS(checks); ++i) {
        gtk_grid_attach(GTK_GRID(options), checks[i], i % 2, i / 2, 1, 1);
        g_signal_connect(checks[i], "toggled", G_CALLBACK(on_option_changed), state);
    }
    gtk_box_pack_start(GTK_BOX(outer), options, FALSE, FALSE, 0);

    state->command_view = gtk_text_view_new();
    gtk_text_view_set_editable(GTK_TEXT_VIEW(state->command_view), FALSE);
    gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(state->command_view), FALSE);
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(state->command_view), GTK_WRAP_WORD_CHAR);
    gtk_widget_set_size_request(command_scroll, -1, 72);
    gtk_container_add(GTK_CONTAINER(command_scroll), state->command_view);
    gtk_container_add(GTK_CONTAINER(command_frame), command_scroll);
    gtk_box_pack_start(GTK_BOX(outer), command_frame, FALSE, FALSE, 0);

    state->output_view = gtk_text_view_new();
    gtk_text_view_set_editable(GTK_TEXT_VIEW(state->output_view), FALSE);
    gtk_text_view_set_cursor_visible(GTK_TEXT_VIEW(state->output_view), FALSE);
    gtk_text_view_set_monospace(GTK_TEXT_VIEW(state->output_view), TRUE);
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(state->output_view), GTK_WRAP_NONE);
    gtk_container_add(GTK_CONTAINER(output_scroll), state->output_view);
    gtk_container_add(GTK_CONTAINER(output_frame), output_scroll);
    gtk_box_pack_start(GTK_BOX(outer), output_frame, TRUE, TRUE, 0);

    state->run_button = gtk_button_new_with_label("Run");
    state->stop_button = gtk_button_new_with_label("Stop");
    gtk_widget_set_sensitive(state->stop_button, FALSE);
    gtk_container_add(GTK_CONTAINER(buttons), state->run_button);
    gtk_container_add(GTK_CONTAINER(buttons), state->stop_button);
    gtk_box_pack_start(GTK_BOX(outer), buttons, FALSE, FALSE, 0);
    g_signal_connect(state->run_button, "clicked", G_CALLBACK(on_run_clicked), state);
    g_signal_connect(state->stop_button, "clicked", G_CALLBACK(on_stop_clicked), state);
    g_signal_connect(state->window, "destroy", G_CALLBACK(on_window_destroy), state);

    g_object_set_data(G_OBJECT(state->window), "app-state", state);
    update_preview(state);
    gtk_widget_show_all(state->window);
}

static int print_preview(const gchar *source, const gchar *destination)
{
    const SyncOptions options = {
        .archive = TRUE,
        .contents = TRUE,
        .compress = FALSE,
        .delete_files = FALSE,
        .partial = TRUE,
        .dry_run = TRUE,
    };
    GError *error = NULL;
    gchar **arguments = build_sync_argv(source, destination, &options, &error);
    if (arguments == NULL) {
        g_printerr("grsync: %s\n", error != NULL ? error->message : "invalid arguments");
        g_clear_error(&error);
        return 2;
    }
    gchar *command = format_command(arguments);
    g_print("%s\n", command);
    g_free(command);
    g_strfreev(arguments);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc > 1 && g_strcmp0(argv[1], "--preview") == 0) {
        if (argc != 4) {
            g_printerr("usage: grsync --preview SOURCE DESTINATION\n");
            return 2;
        }
        return print_preview(argv[2], argv[3]);
    }

    GtkApplication *application = gtk_application_new(
        "top.aromatic05.efilinux.grsync", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(application, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(application), argc, argv);
    g_object_unref(application);
    return status;
}
