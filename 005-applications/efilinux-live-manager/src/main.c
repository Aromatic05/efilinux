#include <gtk/gtk.h>
#include <unistd.h>

typedef struct {
    gchar *path;
    gchar *id;
    gchar *version;
    gchar *description;
    guint64 size;
    gboolean active;
    gboolean autoload;
} Module;

typedef struct {
    gchar *device;
    gchar *mount_path;
    gchar *filesystem;
    gboolean writable;
    gboolean persistence_configured;
    gboolean persistence_exists;
    gboolean persistence_active;
    guint64 persistence_size;
    GPtrArray *modules;
} Medium;

typedef struct {
    GtkWidget *window;
    GtkComboBoxText *media_combo;
    GtkListStore *module_store;
    GtkTreeView *module_view;
    GtkWidget *load_button;
    GtkWidget *unload_button;
    GtkWidget *autoload_button;
    GtkWidget *remove_button;
    GtkWidget *location_label;
    GtkWidget *container_label;
    GtkWidget *boot_label;
    GtkWidget *runtime_label;
    GtkSpinButton *size_spin;
    GtkWidget *create_button;
    GtkWidget *enable_button;
    GtkWidget *disable_button;
    GtkWidget *status_label;
    GPtrArray *media;
} App;

enum {
    COL_NAME,
    COL_VERSION,
    COL_SIZE,
    COL_ACTIVE,
    COL_AUTOLOAD,
    COL_PATH,
    COL_ID,
    COL_COUNT
};

static const gchar *ctl_path(void) {
    const gchar *override = g_getenv("EFILINUX_LIVECTL");
    return override != NULL && *override != '\0' ? override : "/usr/bin/efilinux-livectl";
}

static void module_free(gpointer data) {
    Module *module = data;
    if (module == NULL)
        return;
    g_free(module->path);
    g_free(module->id);
    g_free(module->version);
    g_free(module->description);
    g_free(module);
}

static void medium_free(gpointer data) {
    Medium *medium = data;
    if (medium == NULL)
        return;
    g_free(medium->device);
    g_free(medium->mount_path);
    g_free(medium->filesystem);
    g_ptr_array_free(medium->modules, TRUE);
    g_free(medium);
}

static Medium *find_medium(GPtrArray *media, const gchar *device) {
    guint i;
    for (i = 0; i < media->len; i++) {
        Medium *medium = g_ptr_array_index(media, i);
        if (g_strcmp0(medium->device, device) == 0)
            return medium;
    }
    return NULL;
}

static gboolean field_bool(const gchar *value) {
    return g_strcmp0(value, "1") == 0;
}

static guint64 field_size(const gchar *value) {
    gchar *end = NULL;
    guint64 size = g_ascii_strtoull(value != NULL ? value : "0", &end, 10);
    return end != NULL && *end == '\0' ? size : 0;
}

static GPtrArray *parse_snapshot(const gchar *text, GError **error) {
    GPtrArray *media = g_ptr_array_new_with_free_func(medium_free);
    gchar **lines = g_strsplit(text != NULL ? text : "", "\n", -1);
    guint line_number;

    for (line_number = 0; lines[line_number] != NULL; line_number++) {
        gchar **field;
        guint count;
        Medium *medium;

        if (*lines[line_number] == '\0')
            continue;
        field = g_strsplit(lines[line_number], "\t", -1);
        count = g_strv_length(field);
        if (g_strcmp0(field[0], "MEDIA") == 0 && count == 5) {
            medium = g_new0(Medium, 1);
            medium->device = g_strdup(field[1]);
            medium->mount_path = g_strdup(field[2]);
            medium->filesystem = g_strdup(field[3]);
            medium->writable = field_bool(field[4]);
            medium->modules = g_ptr_array_new_with_free_func(module_free);
            g_ptr_array_add(media, medium);
        } else if (g_strcmp0(field[0], "PERSISTENCE") == 0 && count == 7) {
            medium = find_medium(media, field[1]);
            if (medium == NULL)
                goto malformed;
            medium->persistence_configured = field_bool(field[3]);
            medium->persistence_exists = field_bool(field[4]);
            medium->persistence_active = field_bool(field[5]);
            medium->persistence_size = field_size(field[6]);
        } else if (g_strcmp0(field[0], "MODULE") == 0 && count == 10) {
            Module *module;
            medium = find_medium(media, field[1]);
            if (medium == NULL)
                goto malformed;
            module = g_new0(Module, 1);
            module->path = g_strdup(field[3]);
            module->id = g_strdup(field[4]);
            module->version = g_strdup(field[5]);
            module->description = g_strdup(field[6]);
            module->size = field_size(field[7]);
            module->active = field_bool(field[8]);
            module->autoload = field_bool(field[9]);
            g_ptr_array_add(medium->modules, module);
        } else {
malformed:
            g_set_error(error, G_IO_ERROR, G_IO_ERROR_INVALID_DATA,
                        "Invalid inventory record on line %u", line_number + 1);
            g_strfreev(field);
            g_strfreev(lines);
            g_ptr_array_free(media, TRUE);
            return NULL;
        }
        g_strfreev(field);
    }
    g_strfreev(lines);
    return media;
}

static gboolean run_ctl(const gchar *const *arguments,
                        gboolean privileged,
                        gchar **stdout_text,
                        GError **error) {
    GPtrArray *argv = g_ptr_array_new();
    GSubprocess *process;
    gchar *output = NULL;
    gchar *diagnostic = NULL;
    gboolean ok;
    guint i;

    if (privileged && geteuid() != 0 &&
        g_getenv("EFILINUX_LIVE_MANAGER_NO_PKEXEC") == NULL)
        g_ptr_array_add(argv, (gpointer)"/usr/bin/pkexec");
    g_ptr_array_add(argv, (gpointer)ctl_path());
    for (i = 0; arguments[i] != NULL; i++)
        g_ptr_array_add(argv, (gpointer)arguments[i]);
    g_ptr_array_add(argv, NULL);

    process = g_subprocess_newv((const gchar *const *)argv->pdata,
                                G_SUBPROCESS_FLAGS_STDOUT_PIPE |
                                G_SUBPROCESS_FLAGS_STDERR_PIPE,
                                error);
    g_ptr_array_free(argv, TRUE);
    if (process == NULL)
        return FALSE;

    ok = g_subprocess_communicate_utf8(process, NULL, NULL,
                                       &output, &diagnostic, error);
    if (ok && !g_subprocess_get_successful(process)) {
        const gchar *message = diagnostic != NULL && *diagnostic != '\0'
                                   ? diagnostic
                                   : (output != NULL ? output : "Live operation failed");
        gchar *clean_message = g_strdup(message);
        g_strstrip(clean_message);
        g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED, "%s", clean_message);
        g_free(clean_message);
        ok = FALSE;
    }
    if (ok && stdout_text != NULL) {
        *stdout_text = output;
        output = NULL;
    }
    g_free(output);
    g_free(diagnostic);
    g_object_unref(process);
    return ok;
}

static void set_status(App *app, const gchar *text) {
    gtk_label_set_text(GTK_LABEL(app->status_label), text != NULL ? text : "");
}

static void show_error(App *app, const gchar *title, GError *error) {
    GtkWidget *dialog = gtk_message_dialog_new(GTK_WINDOW(app->window),
                                               GTK_DIALOG_MODAL,
                                               GTK_MESSAGE_ERROR,
                                               GTK_BUTTONS_CLOSE,
                                               "%s", title);
    if (error != NULL)
        gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(dialog), "%s", error->message);
    gtk_dialog_run(GTK_DIALOG(dialog));
    gtk_widget_destroy(dialog);
    g_clear_error(&error);
}

static Medium *selected_medium(App *app) {
    const gchar *device = gtk_combo_box_get_active_id(GTK_COMBO_BOX(app->media_combo));
    return device != NULL ? find_medium(app->media, device) : NULL;
}

static gboolean selected_module(App *app,
                                gchar **path,
                                gchar **id,
                                gboolean *active,
                                gboolean *autoload) {
    GtkTreeSelection *selection = gtk_tree_view_get_selection(app->module_view);
    GtkTreeModel *model;
    GtkTreeIter iter;
    if (!gtk_tree_selection_get_selected(selection, &model, &iter))
        return FALSE;
    gtk_tree_model_get(model, &iter,
                       COL_PATH, path,
                       COL_ID, id,
                       COL_ACTIVE, active,
                       COL_AUTOLOAD, autoload,
                       -1);
    return TRUE;
}

static void update_module_buttons(App *app) {
    gchar *path = NULL;
    gchar *id = NULL;
    gboolean active = FALSE;
    gboolean autoload = FALSE;
    gboolean selected = selected_module(app, &path, &id, &active, &autoload);
    gboolean valid_id = selected && id != NULL && *id != '\0';
    gtk_widget_set_sensitive(app->load_button, valid_id && !active);
    gtk_widget_set_sensitive(app->unload_button, valid_id && active);
    gtk_widget_set_sensitive(app->autoload_button, selected);
    gtk_widget_set_sensitive(app->remove_button, selected && !active);
    gtk_button_set_label(GTK_BUTTON(app->autoload_button),
                         autoload ? "Disable Autoload" : "Enable Autoload");
    g_free(path);
    g_free(id);
}

static void populate_medium(App *app) {
    Medium *medium = selected_medium(app);
    guint i;
    GtkTreeIter iter;

    gtk_list_store_clear(app->module_store);
    if (medium == NULL) {
        gtk_label_set_text(GTK_LABEL(app->location_label), "No EFI Linux media found");
        gtk_label_set_text(GTK_LABEL(app->container_label), "Unavailable");
        gtk_label_set_text(GTK_LABEL(app->boot_label), "Disabled");
        gtk_label_set_text(GTK_LABEL(app->runtime_label), "Inactive");
        gtk_widget_set_sensitive(app->create_button, FALSE);
        gtk_widget_set_sensitive(app->enable_button, FALSE);
        gtk_widget_set_sensitive(app->disable_button, FALSE);
        update_module_buttons(app);
        return;
    }

    for (i = 0; i < medium->modules->len; i++) {
        Module *module = g_ptr_array_index(medium->modules, i);
        gchar *size = g_format_size_full(module->size, G_FORMAT_SIZE_IEC_UNITS);
        const gchar *name = module->description != NULL && *module->description != '\0'
                                ? module->description
                                : module->path;
        gtk_list_store_append(app->module_store, &iter);
        gtk_list_store_set(app->module_store, &iter,
                           COL_NAME, name,
                           COL_VERSION, module->version,
                           COL_SIZE, size,
                           COL_ACTIVE, module->active,
                           COL_AUTOLOAD, module->autoload,
                           COL_PATH, module->path,
                           COL_ID, module->id,
                           -1);
        g_free(size);
    }

    gchar *location = g_strdup_printf("%s/efilinux", medium->mount_path);
    gtk_label_set_text(GTK_LABEL(app->location_label), location);
    g_free(location);
    if (medium->persistence_exists) {
        gchar *size = g_format_size_full(medium->persistence_size, G_FORMAT_SIZE_IEC_UNITS);
        gchar *container = g_strdup_printf("Present (%s)", size);
        gtk_label_set_text(GTK_LABEL(app->container_label), container);
        g_free(container);
        g_free(size);
    } else {
        gtk_label_set_text(GTK_LABEL(app->container_label), "Not created");
    }
    gtk_label_set_text(GTK_LABEL(app->boot_label),
                       medium->persistence_configured ? "Enabled" : "Disabled");
    gtk_label_set_text(GTK_LABEL(app->runtime_label),
                       medium->persistence_active ? "Active in this session" : "Inactive");
    gtk_widget_set_sensitive(app->create_button,
                             medium->writable && !medium->persistence_exists);
    gtk_widget_set_sensitive(app->enable_button,
                             medium->persistence_exists && !medium->persistence_configured);
    gtk_widget_set_sensitive(app->disable_button, medium->persistence_configured);
    update_module_buttons(app);
}

static void refresh(App *app) {
    const gchar *arguments[] = {"snapshot", NULL};
    const gchar *previous = gtk_combo_box_get_active_id(GTK_COMBO_BOX(app->media_combo));
    gchar *previous_copy = g_strdup(previous);
    gchar *output = NULL;
    GError *error = NULL;
    GPtrArray *media;
    gint selected = -1;
    guint i;

    set_status(app, "Scanning EFI Linux media...");
    if (!run_ctl(arguments, TRUE, &output, &error)) {
        show_error(app, "Unable to scan EFI Linux media", error);
        set_status(app, "Scan failed");
        g_free(previous_copy);
        return;
    }
    media = parse_snapshot(output, &error);
    g_free(output);
    if (media == NULL) {
        show_error(app, "Invalid live media inventory", error);
        set_status(app, "Inventory parsing failed");
        g_free(previous_copy);
        return;
    }

    g_ptr_array_free(app->media, TRUE);
    app->media = media;
    gtk_combo_box_text_remove_all(app->media_combo);
    for (i = 0; i < media->len; i++) {
        Medium *medium = g_ptr_array_index(media, i);
        gchar *label = g_strdup_printf("%s — %s — %s",
                                       medium->device, medium->filesystem, medium->mount_path);
        gtk_combo_box_text_append(app->media_combo, medium->device, label);
        if (previous_copy != NULL && g_strcmp0(previous_copy, medium->device) == 0)
            selected = (gint)i;
        g_free(label);
    }
    if (selected < 0 && media->len > 0)
        selected = 0;
    gtk_combo_box_set_active(GTK_COMBO_BOX(app->media_combo), selected);
    g_free(previous_copy);
    populate_medium(app);
    set_status(app, media->len > 0 ? "Media inventory refreshed" : "No EFI Linux media found");
}

static gboolean action(App *app, const gchar *const *arguments, const gchar *success) {
    GError *error = NULL;
    if (!run_ctl(arguments, TRUE, NULL, &error)) {
        show_error(app, "Live operation failed", error);
        return FALSE;
    }
    refresh(app);
    set_status(app, success);
    return TRUE;
}

static gboolean confirm(App *app, const gchar *message) {
    GtkWidget *dialog = gtk_message_dialog_new(GTK_WINDOW(app->window),
                                               GTK_DIALOG_MODAL,
                                               GTK_MESSAGE_WARNING,
                                               GTK_BUTTONS_CANCEL,
                                               "%s", message);
    gtk_dialog_add_button(GTK_DIALOG(dialog), "Continue", GTK_RESPONSE_ACCEPT);
    gboolean accepted = gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT;
    gtk_widget_destroy(dialog);
    return accepted;
}

static void on_media_changed(GtkComboBox *combo, gpointer data) {
    (void)combo;
    populate_medium(data);
}

static void on_selection_changed(GtkTreeSelection *selection, gpointer data) {
    (void)selection;
    update_module_buttons(data);
}

static void on_refresh(GtkButton *button, gpointer data) {
    (void)button;
    refresh(data);
}

static void on_load(GtkButton *button, gpointer data) {
    App *app = data;
    Medium *medium = selected_medium(app);
    gchar *path = NULL, *id = NULL;
    gboolean active, autoload;
    (void)button;
    if (medium != NULL && selected_module(app, &path, &id, &active, &autoload)) {
        const gchar *arguments[] = {"module-load", medium->device, path, NULL};
        action(app, arguments, "Module loaded");
    }
    g_free(path);
    g_free(id);
}

static void on_unload(GtkButton *button, gpointer data) {
    App *app = data;
    gchar *path = NULL, *id = NULL;
    gboolean active, autoload;
    (void)button;
    if (selected_module(app, &path, &id, &active, &autoload)) {
        const gchar *arguments[] = {"module-unload", id, NULL};
        action(app, arguments, "Module unloaded");
    }
    g_free(path);
    g_free(id);
}

static void on_autoload(GtkButton *button, gpointer data) {
    App *app = data;
    Medium *medium = selected_medium(app);
    gchar *path = NULL, *id = NULL;
    gboolean active, autoload;
    (void)button;
    if (medium != NULL && selected_module(app, &path, &id, &active, &autoload)) {
        const gchar *arguments[] = {"module-autoload", medium->device, path,
                                    autoload ? "off" : "on", NULL};
        action(app, arguments, autoload ? "Autoload disabled" : "Autoload enabled");
    }
    g_free(path);
    g_free(id);
}

static void on_remove(GtkButton *button, gpointer data) {
    App *app = data;
    Medium *medium = selected_medium(app);
    gchar *path = NULL, *id = NULL;
    gboolean active, autoload;
    (void)button;
    if (medium != NULL && selected_module(app, &path, &id, &active, &autoload) &&
        confirm(app, "Remove the selected module from this medium?")) {
        const gchar *arguments[] = {"module-remove", medium->device, path, NULL};
        action(app, arguments, "Module removed");
    }
    g_free(path);
    g_free(id);
}

static void on_import(GtkButton *button, gpointer data) {
    App *app = data;
    Medium *medium = selected_medium(app);
    GtkWidget *dialog;
    GtkFileFilter *filter;
    (void)button;
    if (medium == NULL)
        return;
    dialog = gtk_file_chooser_dialog_new("Import ZXM Module",
                                         GTK_WINDOW(app->window),
                                         GTK_FILE_CHOOSER_ACTION_OPEN,
                                         "Cancel", GTK_RESPONSE_CANCEL,
                                         "Import", GTK_RESPONSE_ACCEPT,
                                         NULL);
    filter = gtk_file_filter_new();
    gtk_file_filter_set_name(filter, "EFI Linux modules (*.zxm)");
    gtk_file_filter_add_pattern(filter, "*.zxm");
    gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dialog), filter);
    if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
        gchar *filename = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog));
        const gchar *arguments[] = {"module-import", medium->device, filename, NULL};
        action(app, arguments, "Module imported");
        g_free(filename);
    }
    gtk_widget_destroy(dialog);
}

static void on_create(GtkButton *button, gpointer data) {
    App *app = data;
    Medium *medium = selected_medium(app);
    gchar size[32];
    (void)button;
    if (medium == NULL)
        return;
    g_snprintf(size, sizeof(size), "%d", gtk_spin_button_get_value_as_int(app->size_spin));
    const gchar *arguments[] = {"persistence-create", medium->device, size, NULL};
    if (action(app, arguments, "Persistence container created and enabled"))
        set_status(app, "Persistence will become active after reboot");
}

static void on_enable(GtkButton *button, gpointer data) {
    App *app = data;
    Medium *medium = selected_medium(app);
    (void)button;
    if (medium != NULL) {
        const gchar *arguments[] = {"persistence-enable", medium->device, NULL};
        if (action(app, arguments, "Persistence enabled"))
            set_status(app, "Persistence will become active after reboot");
    }
}

static void on_disable(GtkButton *button, gpointer data) {
    App *app = data;
    Medium *medium = selected_medium(app);
    (void)button;
    if (medium != NULL && confirm(app, "Disable persistence for future boots?")) {
        const gchar *arguments[] = {"persistence-disable", medium->device, NULL};
        if (action(app, arguments, "Persistence disabled"))
            set_status(app, "The current session remains unchanged until reboot");
    }
}

static GtkWidget *modules_page(App *app) {
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    GtkWidget *buttons = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    GtkWidget *import_button = gtk_button_new_with_label("Import Module...");
    GtkTreeSelection *selection;

    app->module_store = gtk_list_store_new(COL_COUNT,
                                            G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING,
                                            G_TYPE_BOOLEAN, G_TYPE_BOOLEAN,
                                            G_TYPE_STRING, G_TYPE_STRING);
    app->module_view = GTK_TREE_VIEW(gtk_tree_view_new_with_model(GTK_TREE_MODEL(app->module_store)));
    gtk_tree_view_append_column(app->module_view,
        gtk_tree_view_column_new_with_attributes("Module", gtk_cell_renderer_text_new(), "text", COL_NAME, NULL));
    gtk_tree_view_append_column(app->module_view,
        gtk_tree_view_column_new_with_attributes("Version", gtk_cell_renderer_text_new(), "text", COL_VERSION, NULL));
    gtk_tree_view_append_column(app->module_view,
        gtk_tree_view_column_new_with_attributes("Size", gtk_cell_renderer_text_new(), "text", COL_SIZE, NULL));
    gtk_tree_view_append_column(app->module_view,
        gtk_tree_view_column_new_with_attributes("Active", gtk_cell_renderer_toggle_new(), "active", COL_ACTIVE, NULL));
    gtk_tree_view_append_column(app->module_view,
        gtk_tree_view_column_new_with_attributes("Autoload", gtk_cell_renderer_toggle_new(), "active", COL_AUTOLOAD, NULL));
    gtk_container_add(GTK_CONTAINER(scroll), GTK_WIDGET(app->module_view));
    gtk_widget_set_vexpand(scroll, TRUE);
    gtk_box_pack_start(GTK_BOX(box), scroll, TRUE, TRUE, 0);

    app->load_button = gtk_button_new_with_label("Load Now");
    app->unload_button = gtk_button_new_with_label("Unload");
    app->autoload_button = gtk_button_new_with_label("Enable Autoload");
    app->remove_button = gtk_button_new_with_label("Remove");
    gtk_box_pack_start(GTK_BOX(buttons), import_button, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(buttons), app->load_button, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(buttons), app->unload_button, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(buttons), app->autoload_button, FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(buttons), app->remove_button, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(box), buttons, FALSE, FALSE, 0);

    selection = gtk_tree_view_get_selection(app->module_view);
    g_signal_connect(selection, "changed", G_CALLBACK(on_selection_changed), app);
    g_signal_connect(import_button, "clicked", G_CALLBACK(on_import), app);
    g_signal_connect(app->load_button, "clicked", G_CALLBACK(on_load), app);
    g_signal_connect(app->unload_button, "clicked", G_CALLBACK(on_unload), app);
    g_signal_connect(app->autoload_button, "clicked", G_CALLBACK(on_autoload), app);
    g_signal_connect(app->remove_button, "clicked", G_CALLBACK(on_remove), app);
    return box;
}

static void add_info_row(GtkGrid *grid, gint row, const gchar *title, GtkWidget **value) {
    GtkWidget *label = gtk_label_new(title);
    *value = gtk_label_new("");
    gtk_widget_set_halign(label, GTK_ALIGN_END);
    gtk_widget_set_halign(*value, GTK_ALIGN_START);
    gtk_label_set_selectable(GTK_LABEL(*value), TRUE);
    gtk_grid_attach(grid, label, 0, row, 1, 1);
    gtk_grid_attach(grid, *value, 1, row, 2, 1);
}

static GtkWidget *persistence_page(App *app) {
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
    GtkWidget *grid = gtk_grid_new();
    GtkWidget *create_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *control_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *size_label = gtk_label_new("Container size (MiB):");
    GtkAdjustment *adjustment = gtk_adjustment_new(1024, 64, 32768, 64, 512, 0);

    gtk_grid_set_row_spacing(GTK_GRID(grid), 8);
    gtk_grid_set_column_spacing(GTK_GRID(grid), 12);
    add_info_row(GTK_GRID(grid), 0, "Location:", &app->location_label);
    add_info_row(GTK_GRID(grid), 1, "Container:", &app->container_label);
    add_info_row(GTK_GRID(grid), 2, "Boot configuration:", &app->boot_label);
    add_info_row(GTK_GRID(grid), 3, "Current session:", &app->runtime_label);
    gtk_box_pack_start(GTK_BOX(box), grid, FALSE, FALSE, 0);

    app->size_spin = GTK_SPIN_BUTTON(gtk_spin_button_new(adjustment, 1, 0));
    app->create_button = gtk_button_new_with_label("Create and Enable");
    gtk_box_pack_start(GTK_BOX(create_row), size_label, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(create_row), GTK_WIDGET(app->size_spin), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(create_row), app->create_button, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(box), create_row, FALSE, FALSE, 0);

    app->enable_button = gtk_button_new_with_label("Enable for Boot");
    app->disable_button = gtk_button_new_with_label("Disable for Boot");
    gtk_box_pack_start(GTK_BOX(control_row), app->enable_button, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(control_row), app->disable_button, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(box), control_row, FALSE, FALSE, 0);

    GtkWidget *notice = gtk_label_new(
        "Persistence changes take effect on the next boot. Disabling it does not delete the container.");
    gtk_label_set_line_wrap(GTK_LABEL(notice), TRUE);
    gtk_widget_set_halign(notice, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(box), notice, FALSE, FALSE, 0);

    g_signal_connect(app->create_button, "clicked", G_CALLBACK(on_create), app);
    g_signal_connect(app->enable_button, "clicked", G_CALLBACK(on_enable), app);
    g_signal_connect(app->disable_button, "clicked", G_CALLBACK(on_disable), app);
    return box;
}

static void activate(GtkApplication *application, gpointer data) {
    App *app = data;
    GtkWidget *root = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    GtkWidget *header = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *refresh_button = gtk_button_new_with_label("Refresh");
    GtkWidget *notebook = gtk_notebook_new();

    app->window = gtk_application_window_new(application);
    gtk_window_set_title(GTK_WINDOW(app->window), "EFI Linux Live Manager");
    gtk_window_set_default_size(GTK_WINDOW(app->window), 860, 560);
    gtk_container_set_border_width(GTK_CONTAINER(app->window), 12);
    app->media_combo = GTK_COMBO_BOX_TEXT(gtk_combo_box_text_new());
    gtk_widget_set_hexpand(GTK_WIDGET(app->media_combo), TRUE);
    gtk_box_pack_start(GTK_BOX(header), gtk_label_new("EFI Linux medium:"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(header), GTK_WIDGET(app->media_combo), TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(header), refresh_button, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(root), header, FALSE, FALSE, 0);

    gtk_notebook_append_page(GTK_NOTEBOOK(notebook), modules_page(app), gtk_label_new("Modules"));
    gtk_notebook_append_page(GTK_NOTEBOOK(notebook), persistence_page(app), gtk_label_new("Persistence"));
    gtk_widget_set_vexpand(notebook, TRUE);
    gtk_box_pack_start(GTK_BOX(root), notebook, TRUE, TRUE, 0);
    app->status_label = gtk_label_new("");
    gtk_widget_set_halign(app->status_label, GTK_ALIGN_START);
    gtk_box_pack_start(GTK_BOX(root), app->status_label, FALSE, FALSE, 0);
    gtk_container_add(GTK_CONTAINER(app->window), root);

    g_signal_connect(app->media_combo, "changed", G_CALLBACK(on_media_changed), app);
    g_signal_connect(refresh_button, "clicked", G_CALLBACK(on_refresh), app);
    gtk_widget_show_all(app->window);
    refresh(app);
}

static int self_test(void) {
    const gchar *sample =
        "MEDIA\t/dev/test\t/run/media/test\text4\t1\n"
        "PERSISTENCE\t/dev/test\t/run/media/test\t1\t1\t0\t67108864\n"
        "MODULE\t/dev/test\t/run/media/test\tmodules/sample.zxm\tsample\t1.0\tSample module\t4096\t0\t1\n";
    GError *error = NULL;
    GPtrArray *media = parse_snapshot(sample, &error);
    if (media == NULL) {
        g_printerr("%s\n", error->message);
        g_clear_error(&error);
        return 1;
    }
    Medium *medium = g_ptr_array_index(media, 0);
    Module *module = g_ptr_array_index(medium->modules, 0);
    gboolean ok = media->len == 1 && medium->modules->len == 1 &&
                  medium->persistence_configured && !medium->persistence_active &&
                  g_strcmp0(module->id, "sample") == 0 && module->autoload;
    g_ptr_array_free(media, TRUE);
    if (!ok)
        return 1;
    g_print("EFILINUX_LIVE_MANAGER_SELF_TEST_OK\n");
    return 0;
}

int main(int argc, char **argv) {
    GtkApplication *application;
    App app = {0};
    int status;

    if (argc == 2 && g_strcmp0(argv[1], "--self-test") == 0)
        return self_test();
    app.media = g_ptr_array_new_with_free_func(medium_free);
    application = gtk_application_new("org.efilinux.LiveManager", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(application, "activate", G_CALLBACK(activate), &app);
    status = g_application_run(G_APPLICATION(application), argc, argv);
    g_object_unref(application);
    g_ptr_array_free(app.media, TRUE);
    return status;
}
