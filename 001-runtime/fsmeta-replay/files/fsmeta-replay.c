#define _GNU_SOURCE

#include <acl/libacl.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/openat2.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/capability.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#define OWNERSHIP_PATH "/etc/filemeta/ownership.tsv"
#define ACL_DIRECTORY "/etc/filemeta/acls"
#define CAP_DIRECTORY "/etc/filemeta/caps"
#define MAX_RECORD_SIZE (1024U * 1024U)

struct ownership_record {
    char *path;
    char *type;
    char *owner;
};

struct ownership_table {
    struct ownership_record *records;
    size_t length;
    size_t capacity;
};

enum metadata_kind {
    METADATA_ACL,
    METADATA_CAPABILITY,
};

static int report_error(const char *format, ...)
{
    va_list arguments;

    fputs("fsmeta-replay: ", stderr);
    va_start(arguments, format);
    vfprintf(stderr, format, arguments);
    va_end(arguments);
    fputc('\n', stderr);
    return -1;
}

static bool valid_package_name(const char *name)
{
    const unsigned char *cursor = (const unsigned char *)name;

    if (*cursor == '\0' ||
        !((*cursor >= 'a' && *cursor <= 'z') ||
          (*cursor >= '0' && *cursor <= '9')))
        return false;
    for (; *cursor != '\0'; ++cursor) {
        if ((*cursor >= 'a' && *cursor <= 'z') ||
            (*cursor >= '0' && *cursor <= '9') ||
            *cursor == '+' || *cursor == '.' || *cursor == '_' ||
            *cursor == '-')
            continue;
        return false;
    }
    return true;
}

static bool valid_target_path(const char *path)
{
    const char *component;
    const char *separator;

    if (path[0] != '/' || path[1] == '\0')
        return false;
    if (strpbrk(path, "\t\r\n") != NULL || strstr(path, "//") != NULL)
        return false;

    component = path + 1;
    while (*component != '\0') {
        separator = strchr(component, '/');
        size_t length = separator == NULL ? strlen(component) :
                                               (size_t)(separator - component);
        if (length == 0 || (length == 1 && component[0] == '.') ||
            (length == 2 && component[0] == '.' && component[1] == '.'))
            return false;
        if (separator == NULL)
            break;
        component = separator + 1;
    }
    return true;
}

static int trim_record(char *line, ssize_t *length)
{
    if (*length < 0 || (size_t)*length > MAX_RECORD_SIZE)
        return report_error("metadata record is too large");
    if (memchr(line, '\0', (size_t)*length) != NULL)
        return report_error("metadata record contains a NUL byte");
    if (*length > 0 && line[*length - 1] == '\n')
        --*length;
    line[*length] = '\0';
    if (strchr(line, '\r') != NULL)
        return report_error("metadata record contains a carriage return");
    return 0;
}

static void free_ownership_table(struct ownership_table *table)
{
    size_t index;

    for (index = 0; index < table->length; ++index) {
        free(table->records[index].path);
        free(table->records[index].type);
        free(table->records[index].owner);
    }
    free(table->records);
    memset(table, 0, sizeof(*table));
}

static int append_ownership_record(struct ownership_table *table,
                                   const char *path,
                                   const char *type,
                                   const char *owner)
{
    struct ownership_record *record;

    if (table->length == table->capacity) {
        size_t next_capacity = table->capacity == 0 ? 256 : table->capacity * 2;
        void *next_records = realloc(table->records,
                                     next_capacity * sizeof(*table->records));
        if (next_records == NULL)
            return report_error("cannot allocate ownership table: %s",
                                strerror(errno));
        table->records = next_records;
        table->capacity = next_capacity;
    }

    record = &table->records[table->length];
    record->path = strdup(path);
    record->type = strdup(type);
    record->owner = strdup(owner);
    if (record->path == NULL || record->type == NULL || record->owner == NULL) {
        free(record->path);
        free(record->type);
        free(record->owner);
        memset(record, 0, sizeof(*record));
        return report_error("cannot allocate ownership record: %s",
                            strerror(errno));
    }
    ++table->length;
    return 0;
}

static int load_ownership_table(struct ownership_table *table)
{
    int descriptor;
    struct stat status;
    FILE *stream;
    char *line = NULL;
    size_t capacity = 0;
    ssize_t length;
    size_t line_number = 0;
    int result = -1;

    descriptor = open(OWNERSHIP_PATH, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0)
        return report_error("cannot open %s: %s", OWNERSHIP_PATH,
                            strerror(errno));
    if (fstat(descriptor, &status) != 0) {
        close(descriptor);
        return report_error("cannot inspect %s: %s", OWNERSHIP_PATH,
                            strerror(errno));
    }
    if (!S_ISREG(status.st_mode)) {
        close(descriptor);
        return report_error("ownership table is not a regular file: %s",
                            OWNERSHIP_PATH);
    }
    stream = fdopen(descriptor, "r");
    if (stream == NULL) {
        close(descriptor);
        return report_error("cannot read %s: %s", OWNERSHIP_PATH,
                            strerror(errno));
    }

    while ((length = getline(&line, &capacity, stream)) >= 0) {
        char *first_tab;
        char *second_tab;
        char *path;
        char *type;
        char *owner;

        ++line_number;
        if (trim_record(line, &length) != 0)
            goto out;
        if (line_number == 1) {
            if (strcmp(line, "path\ttype\towner") != 0) {
                report_error("invalid ownership header in %s", OWNERSHIP_PATH);
                goto out;
            }
            continue;
        }
        if (line[0] == '\0') {
            report_error("blank ownership record at line %zu", line_number);
            goto out;
        }

        first_tab = strchr(line, '\t');
        second_tab = first_tab == NULL ? NULL : strchr(first_tab + 1, '\t');
        if (first_tab == NULL || second_tab == NULL ||
            strchr(second_tab + 1, '\t') != NULL) {
            report_error("malformed ownership record at line %zu", line_number);
            goto out;
        }
        *first_tab = '\0';
        *second_tab = '\0';
        path = line;
        type = first_tab + 1;
        owner = second_tab + 1;

        if (!valid_target_path(path) || type[0] == '\0' || owner[0] == '\0') {
            report_error("invalid ownership record at line %zu", line_number);
            goto out;
        }
        if (strcmp(owner, "@composer") != 0 && !valid_package_name(owner)) {
            report_error("invalid ownership package at line %zu", line_number);
            goto out;
        }
        if (strcmp(type, "file") != 0 && strcmp(type, "directory") != 0 &&
            strcmp(type, "symlink") != 0 && strcmp(type, "block") != 0 &&
            strcmp(type, "character") != 0 && strcmp(type, "fifo") != 0 &&
            strcmp(type, "socket") != 0) {
            report_error("invalid ownership type at line %zu", line_number);
            goto out;
        }
        if (append_ownership_record(table, path, type, owner) != 0)
            goto out;
    }
    if (ferror(stream)) {
        report_error("cannot read %s: %s", OWNERSHIP_PATH, strerror(errno));
        goto out;
    }
    if (line_number == 0) {
        report_error("ownership table is empty: %s", OWNERSHIP_PATH);
        goto out;
    }
    result = 0;

out:
    free(line);
    fclose(stream);
    return result;
}

static const char *owned_type(const struct ownership_table *table,
                              const char *path,
                              const char *package)
{
    size_t index;

    for (index = 0; index < table->length; ++index) {
        const struct ownership_record *record = &table->records[index];
        if (strcmp(record->path, path) == 0 &&
            strcmp(record->owner, package) == 0)
            return record->type;
    }
    return NULL;
}

static int open_target(int root_fd, const char *path, const char *type)
{
    struct open_how how = {
        .flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW,
        .resolve = RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS |
                   RESOLVE_NO_SYMLINKS,
    };
    struct stat status;
    int descriptor;

    if (strcmp(type, "directory") == 0)
        how.flags |= O_DIRECTORY;
    descriptor = (int)syscall(SYS_openat2, root_fd, path + 1, &how,
                              sizeof(how));
    if (descriptor < 0) {
        report_error("cannot safely open %s: %s", path, strerror(errno));
        return -1;
    }
    if (fstat(descriptor, &status) != 0) {
        report_error("cannot inspect %s: %s", path, strerror(errno));
        close(descriptor);
        return -1;
    }
    if ((strcmp(type, "file") == 0 && !S_ISREG(status.st_mode)) ||
        (strcmp(type, "directory") == 0 && !S_ISDIR(status.st_mode))) {
        report_error("target type changed for %s", path);
        close(descriptor);
        return -1;
    }
    return descriptor;
}

static int apply_acl(int descriptor, const char *path, const char *value)
{
    acl_t acl = acl_from_text(value);
    int result = -1;

    if (acl == NULL) {
        report_error("invalid ACL for %s: %s", path, strerror(errno));
        return -1;
    }
    if (acl_valid(acl) != 0) {
        report_error("invalid ACL entries for %s: %s", path, strerror(errno));
        goto out;
    }
    if (acl_set_fd(descriptor, acl) != 0) {
        report_error("cannot apply ACL to %s: %s", path, strerror(errno));
        goto out;
    }
    result = 0;

out:
    acl_free(acl);
    return result;
}

static int apply_capability(int descriptor,
                            const char *path,
                            const char *value)
{
    cap_t capability = cap_from_text(value);
    int result = -1;

    if (capability == NULL) {
        report_error("invalid capability for %s: %s", path, strerror(errno));
        return -1;
    }
    if (cap_set_fd(descriptor, capability) != 0) {
        report_error("cannot apply capability to %s: %s", path,
                     strerror(errno));
        goto out;
    }
    result = 0;

out:
    cap_free(capability);
    return result;
}

static int compare_names(const void *left, const void *right)
{
    const char *const *left_name = left;
    const char *const *right_name = right;
    return strcmp(*left_name, *right_name);
}

static void free_names(char **names, size_t length)
{
    size_t index;

    for (index = 0; index < length; ++index)
        free(names[index]);
    free(names);
}

static int replay_metadata_file(enum metadata_kind kind,
                                int directory_fd,
                                const char *package,
                                int root_fd,
                                const struct ownership_table *ownership)
{
    const char *expected_header = kind == METADATA_ACL ?
                                      "EFILINUX-ACLS-1" :
                                      "EFILINUX-CAPS-1";
    int metadata_fd;
    struct stat metadata_status;
    FILE *stream;
    char *line = NULL;
    size_t capacity = 0;
    ssize_t length;
    size_t line_number = 0;
    int result = -1;

    metadata_fd = openat(directory_fd, package,
                         O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (metadata_fd < 0)
        return report_error("cannot open metadata file %s: %s", package,
                            strerror(errno));
    if (fstat(metadata_fd, &metadata_status) != 0 ||
        !S_ISREG(metadata_status.st_mode)) {
        close(metadata_fd);
        return report_error("metadata file is not regular: %s", package);
    }
    stream = fdopen(metadata_fd, "r");
    if (stream == NULL) {
        close(metadata_fd);
        return report_error("cannot read metadata file %s: %s", package,
                            strerror(errno));
    }

    while ((length = getline(&line, &capacity, stream)) >= 0) {
        char *separator;
        char *path;
        char *value;
        const char *type;
        int target_fd;

        ++line_number;
        if (trim_record(line, &length) != 0)
            goto out;
        if (line_number == 1) {
            if (strcmp(line, expected_header) != 0) {
                report_error("invalid metadata header in %s", package);
                goto out;
            }
            continue;
        }
        if (line[0] == '\0') {
            report_error("blank metadata record in %s at line %zu", package,
                         line_number);
            goto out;
        }
        separator = strchr(line, '\t');
        if (separator == NULL || strchr(separator + 1, '\t') != NULL) {
            report_error("malformed metadata record in %s at line %zu",
                         package, line_number);
            goto out;
        }
        *separator = '\0';
        path = line;
        value = separator + 1;
        if (!valid_target_path(path) || value[0] == '\0') {
            report_error("invalid metadata record in %s at line %zu", package,
                         line_number);
            goto out;
        }

        type = owned_type(ownership, path, package);
        if (type == NULL) {
            report_error("%s declares metadata for an unowned path: %s",
                         package, path);
            goto out;
        }
        if (kind == METADATA_CAPABILITY && strcmp(type, "file") != 0) {
            report_error("capability target is not a regular file: %s", path);
            goto out;
        }
        if (kind == METADATA_ACL && strcmp(type, "file") != 0 &&
            strcmp(type, "directory") != 0) {
            report_error("ACL target has an unsupported type: %s", path);
            goto out;
        }

        target_fd = open_target(root_fd, path, type);
        if (target_fd < 0)
            goto out;
        if ((kind == METADATA_ACL && apply_acl(target_fd, path, value) != 0) ||
            (kind == METADATA_CAPABILITY &&
             apply_capability(target_fd, path, value) != 0)) {
            close(target_fd);
            goto out;
        }
        close(target_fd);
    }
    if (ferror(stream)) {
        report_error("cannot read metadata file %s: %s", package,
                     strerror(errno));
        goto out;
    }
    if (line_number == 0) {
        report_error("metadata file is empty: %s", package);
        goto out;
    }
    result = 0;

out:
    free(line);
    fclose(stream);
    return result;
}

static int replay_directory(enum metadata_kind kind,
                            const char *path,
                            int root_fd,
                            const struct ownership_table *ownership)
{
    int descriptor;
    DIR *directory;
    struct dirent *entry;
    char **names = NULL;
    size_t length = 0;
    size_t capacity = 0;
    size_t index;
    int result = -1;

    descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) {
        if (errno == ENOENT)
            return 0;
        return report_error("cannot open metadata directory %s: %s", path,
                            strerror(errno));
    }
    directory = fdopendir(descriptor);
    if (directory == NULL) {
        close(descriptor);
        return report_error("cannot read metadata directory %s: %s", path,
                            strerror(errno));
    }

    errno = 0;
    while ((entry = readdir(directory)) != NULL) {
        char *name;

        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;
        if (!valid_package_name(entry->d_name)) {
            report_error("invalid metadata package name in %s: %s", path,
                         entry->d_name);
            goto out;
        }
        if (length == capacity) {
            size_t next_capacity = capacity == 0 ? 16 : capacity * 2;
            void *next_names = realloc(names, next_capacity * sizeof(*names));
            if (next_names == NULL) {
                report_error("cannot allocate metadata file list: %s",
                             strerror(errno));
                goto out;
            }
            names = next_names;
            capacity = next_capacity;
        }
        name = strdup(entry->d_name);
        if (name == NULL) {
            report_error("cannot allocate metadata file name: %s",
                         strerror(errno));
            goto out;
        }
        names[length++] = name;
    }
    if (errno != 0) {
        report_error("cannot enumerate metadata directory %s: %s", path,
                     strerror(errno));
        goto out;
    }

    qsort(names, length, sizeof(*names), compare_names);
    for (index = 0; index < length; ++index) {
        if (replay_metadata_file(kind, dirfd(directory), names[index], root_fd,
                                 ownership) != 0)
            goto out;
    }
    result = 0;

out:
    free_names(names, length);
    closedir(directory);
    return result;
}

static int metadata_directory_exists(const char *path)
{
    struct stat status;

    if (lstat(path, &status) != 0) {
        if (errno == ENOENT)
            return 0;
        report_error("cannot inspect metadata directory %s: %s", path,
                     strerror(errno));
        return -1;
    }
    if (!S_ISDIR(status.st_mode)) {
        report_error("metadata path is not a directory: %s", path);
        return -1;
    }
    return 1;
}

int main(void)
{
    struct ownership_table ownership = {0};
    int acl_exists;
    int capability_exists;
    int root_fd = -1;
    int result = EXIT_FAILURE;

    acl_exists = metadata_directory_exists(ACL_DIRECTORY);
    capability_exists = metadata_directory_exists(CAP_DIRECTORY);
    if (acl_exists < 0 || capability_exists < 0)
        goto out;
    if (acl_exists == 0 && capability_exists == 0) {
        result = EXIT_SUCCESS;
        goto out;
    }
    if (load_ownership_table(&ownership) != 0)
        goto out;

    root_fd = open("/", O_PATH | O_DIRECTORY | O_CLOEXEC);
    if (root_fd < 0) {
        report_error("cannot open root directory: %s", strerror(errno));
        goto out;
    }

    if (replay_directory(METADATA_ACL, ACL_DIRECTORY, root_fd, &ownership) != 0)
        goto out;
    if (replay_directory(METADATA_CAPABILITY, CAP_DIRECTORY, root_fd,
                         &ownership) != 0)
        goto out;
    result = EXIT_SUCCESS;

out:
    if (root_fd >= 0)
        close(root_fd);
    free_ownership_table(&ownership);
    return result;
}
