#include <stdlib.h>

void* (*zstbiMallocPtr)(size_t size) = NULL;
void* (*zstbiReallocPtr)(void* ptr, size_t size) = NULL;
void (*zstbiFreePtr)(void* ptr) = NULL;

#define STBI_MALLOC(size) zstbiMallocPtr(size)
#define STBI_REALLOC(ptr, size) zstbiReallocPtr(ptr, size)
#define STBI_FREE(ptr) zstbiFreePtr(ptr)

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

void* (*zstbirMallocPtr)(size_t size, void* context) = NULL;
void (*zstbirFreePtr)(void* ptr, void* context) = NULL;

#define STBIR_MALLOC(size, context) zstbirMallocPtr(size, context)
#define STBIR_FREE(ptr, context) zstbirFreePtr(ptr, context)

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize.h"
