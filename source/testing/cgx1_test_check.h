// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#ifndef CGX1_TEST_CHECK_H
#define CGX1_TEST_CHECK_H

#include <stdio.h>
#include <stdlib.h>

static inline void Cgx1TestCheckFailed(
    const char* expression,
    const char* file,
    int line)
{
    (void)fprintf(
        stderr,
        "CGX1_TEST_CHECK failed: %s (%s:%d)\n",
        expression,
        file,
        line);
    (void)fflush(stderr);
    exit(EXIT_FAILURE);
}

#define CGX1_TEST_CHECK(expression) \
    do { \
        if (!(expression)) { \
            Cgx1TestCheckFailed(#expression, __FILE__, __LINE__); \
        } \
    } while (0)

#endif
