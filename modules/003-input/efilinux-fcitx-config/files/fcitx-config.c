#include <gtk/gtk.h>
#include <errno.h>
#include <glib/gstdio.h>
#include <string.h>

enum {
    COLUMN_ENABLED,
    COLUMN_NAME,
    COLUMN_ID,
    COLUMN_COUNT,
};

typedef struct {
    GtkWidget *window;
    GtkListStore *store;
    GtkComboBoxText *default_combo;
} App;

static gboolean string_set_contains(GHashTable *set, const gchar *value) {
    return value != NULL && g_hash_table_contains(set, value);
}

static void load_profile(GHashTable *enabled, gchar **default_id, gboolean *exists) {
    g_autofree gchar *path = g_build_filename(g_get_user_config_dir(), "fcitx5", "profile", NULL);
    g_autoptr(GKeyFile) key_file = g_key_file_new();
    g_autoptr(GError) error = NULL;

    *exists = g_key_file_load_from_file(key_file, path, G_KEY_FILE_NONE, &error);
    if (!*exists) {
        g_clear_error(&error);
        return;
    }

    *default_id = g_key_file_get_string(key_file, "Groups/0", "DefaultIM", NULL);
    g_auto(GStrv) groups = g_key_file_get_groups(key_file, NULL);
    for (gchar **group = groups; group != NULL && *group != NULL; ++group) {
        if (!g_str_has_prefix(*group, "Groups/0/Items/")) {
            continue;
        }
        g_autofree gchar *name = g_key_file_get_string(key_file, *group, "Name", NULL);
        if (name != NULL && *name != '\0') {
            g_hash_table_add(enabled, g_steal_pointer(&name));
        }
    }
}

static gint compare_rows(gconstpointer left, gconstpointer right) {
    gchar *const *a = *(gchar *const *const *)left;
    gchar *const *b = *(gchar *const *const *)right;
    return g_utf8_collate(a[1], b[1]);
}

static GPtrArray *discover_methods(void) {
    GPtrArray *methods = g_ptr_array_new_with_free_func((GDestroyNotify)g_strfreev);
    gchar **keyboard = g_new0(gchar *, 3);
    keyboard[0] = g_strdup("keyboard-us");
    keyboard[1] = g_strdup("English (US)");
    g_ptr_array_add(methods, keyboard);

    const gchar *directory = "/opt/fcitx5/share/fcitx5/inputmethod";
    g_autoptr(GDir) dir = g_dir_open(directory, 0, NULL);
    if (dir == NULL) {
        return methods;
    }

    const gchar *entry;
    while ((entry = g_dir_read_name(dir)) != NULL) {
        if (!g_str_has_suffix(entry, ".conf")) {
            continue;
        }
        g_autofree gchar *path = g_build_filename(directory, entry, NULL);
        g_autoptr(GKeyFile) key_file = g_key_file_new();
        if (!g_key_file_load_from_file(key_file, path, G_KEY_FILE_NONE, NULL)) {
            continue;
        }
        g_autofree gchar *name = g_key_file_get_locale_string(key_file, "InputMethod", "Name", NULL, NULL);
        if (name == NULL || *name == '\0') {
            continue;
        }
        gchar **method = g_new0(gchar *, 3);
        method[0] = g_strndup(entry, strlen(entry) - strlen(".conf"));
        method[1] = g_steal_pointer(&name);
        g_ptr_array_add(methods, method);
    }
    g_ptr_array_sort(methods, compare_rows);
    return methods;
}

static void rebuild_default_combo(App *app, const gchar *preferred) {
    gtk_combo_box_text_remove_all(app->default_combo);
    GtkTreeIter iter;
    gboolean valid = gtk_tree_model_get_iter_first(GTK_TREE_MODEL(app->store), &iter);
    gint preferred_index = -1;
    gint first_index = -1;
    gint index = 0;

    while (valid) {
        gboolean enabled = FALSE;
        gchar *name = NULL;
        gchar *id = NULL;
        gtk_tree_model_get(GTK_TREE_MODEL(app->store), &iter,
                           COLUMN_ENABLED, &enabled,
                           COLUMN_NAME, &name,
                           COLUMN_ID, &id,
                           -1);
        if (enabled) {
            gtk_combo_box_text_append(app->default_combo, id, name);
            if (first_index < 0) {
                first_index = index;
            }
            if (preferred != NULL && g_strcmp0(preferred, id) == 0) {
                preferred_index = index;
            }
            ++index;
        }
        g_free(name);
        g_free(id);
        valid = gtk_tree_model_iter_next(GTK_TREE_MODEL(app->store), &iter);
    }
    gtk_combo_box_set_active(GTK_COMBO_BOX(app->default_combo),
                             preferred_index >= 0 ? preferred_index : first_index);
}

static void toggle_method(GtkCellRendererToggle *renderer, gchar *path_string, gpointer data) {
    (void)renderer;
    App *app = data;
    GtkTreePath *path = gtk_tree_path_new_from_string(path_string);
    GtkTreeIter iter;
    if (!gtk_tree_model_get_iter(GTK_TREE_MODEL(app->store), &iter, path)) {
        gtk_tree_path_free(path);
        return;
    }

    gboolean enabled = FALSE;
    gchar *id = NULL;
    gtk_tree_model_get(GTK_TREE_MODEL(app->store), &iter,
                       COLUMN_ENABLED, &enabled,
                       COLUMN_ID, &id,
                       -1);
    if (g_strcmp0(id, "keyboard-us") != 0) {
        const gchar *current = gtk_combo_box_get_active_id(GTK_COMBO_BOX(app->default_combo));
        g_autofree gchar *preferred = g_strdup(current);
        gtk_list_store_set(app->store, &iter, COLUMN_ENABLED, !enabled, -1);
        rebuild_default_combo(app, preferred);
    }
    g_free(id);
    gtk_tree_path_free(path);
}

static gboolean write_profile(App *app, GError **error) {
    const gchar *default_id = gtk_combo_box_get_active_id(GTK_COMBO_BOX(app->default_combo));
    if (default_id == NULL) {
        g_set_error_literal(error, G_FILE_ERROR, G_FILE_ERROR_FAILED,
                            "At least one input method must be enabled");
        return FALSE;
    }

    GString *profile = g_string_new(
        "[Groups/0]\n"
        "Name=Default\n"
        "Default Layout=us\n");
    g_string_append_printf(profile, "DefaultIM=%s\n\n", default_id);

    GtkTreeIter iter;
    gboolean valid = gtk_tree_model_get_iter_first(GTK_TREE_MODEL(app->store), &iter);
    guint item = 0;
    while (valid) {
        gboolean enabled = FALSE;
        gchar *id = NULL;
        gtk_tree_model_get(GTK_TREE_MODEL(app->store), &iter,
                           COLUMN_ENABLED, &enabled,
                           COLUMN_ID, &id,
                           -1);
        if (enabled) {
            g_string_append_printf(profile,
                                   "[Groups/0/Items/%u]\nName=%s\nLayout=\n\n",
                                   item++, id);
        }
        g_free(id);
        valid = gtk_tree_model_iter_next(GTK_TREE_MODEL(app->store), &iter);
    }
    g_string_append(profile, "[GroupOrder]\n0=Default\n");

    g_autofree gchar *directory = g_build_filename(g_get_user_config_dir(), "fcitx5", NULL);
    g_autofree gchar *path = g_build_filename(directory, "profile", NULL);
    if (g_mkdir_with_parents(directory, 0700) != 0) {
        g_set_error(error, G_FILE_ERROR, g_file_error_from_errno(errno),
                    "Cannot create %s: %s", directory, g_strerror(errno));
        g_string_free(profile, TRUE);
        return FALSE;
    }
    gboolean result = g_file_set_contents(path, profile->str, profile->len, error);
    g_string_free(profile, TRUE);
    if (!result) {
        return FALSE;
    }

    const gchar *reload_argv[] = { "/usr/bin/fcitx5-remote", "-r", NULL };
    g_spawn_async(NULL, (gchar **)reload_argv, NULL, G_SPAWN_DEFAULT, NULL, NULL, NULL, NULL);
    const gchar *select_argv[] = { "/usr/bin/fcitx5-remote", "-s", default_id, NULL };
    g_spawn_async(NULL, (gchar **)select_argv, NULL, G_SPAWN_DEFAULT, NULL, NULL, NULL, NULL);
    return TRUE;
}

static void save_clicked(GtkButton *button, gpointer data) {
    (void)button;
    App *app = data;
    g_autoptr(GError) error = NULL;
    if (!write_profile(app, &error)) {
        GtkWidget *dialog = gtk_message_dialog_new(GTK_WINDOW(app->window),
            GTK_DIALOG_MODAL, GTK_MESSAGE_ERROR, GTK_BUTTONS_CLOSE,
            "%s", error->message);
        gtk_dialog_run(GTK_DIALOG(dialog));
        gtk_widget_destroy(dialog);
        return;
    }
    gtk_widget_destroy(app->window);
}

static void close_clicked(GtkButton *button, gpointer data) {
    (void)button;
    gtk_widget_destroy(GTK_WIDGET(data));
}

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);

    App app = {0};
    app.window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(app.window), "Fcitx 5 Input Method Settings");
    gtk_window_set_default_size(GTK_WINDOW(app.window), 520, 420);
    gtk_container_set_border_width(GTK_CONTAINER(app.window), 12);
    g_signal_connect(app.window, "destroy", G_CALLBACK(gtk_main_quit), NULL);

    GtkWidget *layout = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_container_add(GTK_CONTAINER(app.window), layout);
    GtkWidget *description = gtk_label_new(
        "Choose the input methods available in the current group and select the default one.");
    gtk_label_set_xalign(GTK_LABEL(description), 0.0f);
    gtk_label_set_line_wrap(GTK_LABEL(description), TRUE);
    gtk_box_pack_start(GTK_BOX(layout), description, FALSE, FALSE, 0);

    app.store = gtk_list_store_new(COLUMN_COUNT, G_TYPE_BOOLEAN, G_TYPE_STRING, G_TYPE_STRING);
    GtkWidget *tree = gtk_tree_view_new_with_model(GTK_TREE_MODEL(app.store));
    GtkCellRenderer *toggle = gtk_cell_renderer_toggle_new();
    g_signal_connect(toggle, "toggled", G_CALLBACK(toggle_method), &app);
    gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(tree), -1,
        "Enabled", toggle, "active", COLUMN_ENABLED, NULL);
    GtkCellRenderer *text = gtk_cell_renderer_text_new();
    gtk_tree_view_insert_column_with_attributes(GTK_TREE_VIEW(tree), -1,
        "Input Method", text, "text", COLUMN_NAME, NULL);
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),
                                   GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
    gtk_container_add(GTK_CONTAINER(scroll), tree);
    gtk_box_pack_start(GTK_BOX(layout), scroll, TRUE, TRUE, 0);

    GtkWidget *default_row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_box_pack_start(GTK_BOX(default_row), gtk_label_new("Default input method:"), FALSE, FALSE, 0);
    app.default_combo = GTK_COMBO_BOX_TEXT(gtk_combo_box_text_new());
    gtk_box_pack_start(GTK_BOX(default_row), GTK_WIDGET(app.default_combo), TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(layout), default_row, FALSE, FALSE, 0);

    g_autoptr(GHashTable) enabled = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
    g_autofree gchar *default_id = NULL;
    gboolean profile_exists = FALSE;
    load_profile(enabled, &default_id, &profile_exists);
    if (!profile_exists) {
        g_hash_table_add(enabled, g_strdup("keyboard-us"));
        g_hash_table_add(enabled, g_strdup("pinyin"));
        default_id = g_strdup("pinyin");
    }

    g_autoptr(GPtrArray) methods = discover_methods();
    for (guint i = 0; i < methods->len; ++i) {
        gchar **method = g_ptr_array_index(methods, i);
        GtkTreeIter iter;
        gtk_list_store_append(app.store, &iter);
        gtk_list_store_set(app.store, &iter,
                           COLUMN_ENABLED, string_set_contains(enabled, method[0]),
                           COLUMN_NAME, method[1],
                           COLUMN_ID, method[0],
                           -1);
    }
    rebuild_default_combo(&app, default_id);

    GtkWidget *buttons = gtk_button_box_new(GTK_ORIENTATION_HORIZONTAL);
    gtk_button_box_set_layout(GTK_BUTTON_BOX(buttons), GTK_BUTTONBOX_END);
    GtkWidget *cancel = gtk_button_new_with_label("Cancel");
    GtkWidget *save = gtk_button_new_with_label("Apply");
    gtk_container_add(GTK_CONTAINER(buttons), cancel);
    gtk_container_add(GTK_CONTAINER(buttons), save);
    g_signal_connect(cancel, "clicked", G_CALLBACK(close_clicked), app.window);
    g_signal_connect(save, "clicked", G_CALLBACK(save_clicked), &app);
    gtk_box_pack_start(GTK_BOX(layout), buttons, FALSE, FALSE, 0);

    gtk_widget_show_all(app.window);
    gtk_main();
    g_object_unref(app.store);
    return 0;
}
