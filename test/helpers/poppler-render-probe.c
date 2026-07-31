#include <cairo.h>
#include <glib.h>
#include <poppler.h>

#include <stdint.h>
#include <stdio.h>

int main(int argc, char **argv) {
    GError *error = NULL;
    PopplerDocument *document;
    PopplerPage *page;
    cairo_surface_t *surface;
    cairo_t *cr;
    char *uri;
    double width;
    double height;
    uint64_t checksum = 0;
    unsigned char *data;
    int stride;
    int image_height;

    if (argc != 2) {
        fprintf(stderr, "usage: %s FILE.pdf\n", argv[0]);
        return 2;
    }

    uri = g_filename_to_uri(argv[1], NULL, &error);
    if (!uri) {
        fprintf(stderr, "failed to create PDF URI: %s\n", error->message);
        g_error_free(error);
        return 1;
    }

    document = poppler_document_new_from_file(uri, NULL, &error);
    g_free(uri);
    if (!document) {
        fprintf(stderr, "failed to open PDF: %s\n", error->message);
        g_error_free(error);
        return 1;
    }
    if (poppler_document_get_n_pages(document) < 1) {
        fprintf(stderr, "PDF contains no pages\n");
        g_object_unref(document);
        return 1;
    }

    page = poppler_document_get_page(document, 0);
    poppler_page_get_size(page, &width, &height);
    if (width < 1.0 || height < 1.0) {
        fprintf(stderr, "PDF page has an invalid size\n");
        g_object_unref(page);
        g_object_unref(document);
        return 1;
    }

    surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, (int)width, (int)height);
    cr = cairo_create(surface);
    cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);
    cairo_paint(cr);
    poppler_page_render(page, cr);
    cairo_destroy(cr);
    cairo_surface_flush(surface);

    if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
        fprintf(stderr, "Poppler render surface failed\n");
        cairo_surface_destroy(surface);
        g_object_unref(page);
        g_object_unref(document);
        return 1;
    }

    data = cairo_image_surface_get_data(surface);
    stride = cairo_image_surface_get_stride(surface);
    image_height = cairo_image_surface_get_height(surface);
    for (int y = 0; y < image_height; ++y) {
        for (int x = 0; x < stride; ++x) {
            checksum = checksum * 131u + data[y * stride + x];
        }
    }

    printf("EFILINUX_POPPLER_PAGES=%d\n", poppler_document_get_n_pages(document));
    printf("EFILINUX_POPPLER_RENDER=%llu\n", (unsigned long long)checksum);

    cairo_surface_destroy(surface);
    g_object_unref(page);
    g_object_unref(document);
    return checksum == 0 ? 1 : 0;
}
