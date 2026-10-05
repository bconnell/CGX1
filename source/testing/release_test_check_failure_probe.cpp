// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_check.h"

int main()
{
    CGX1_TEST_CHECK(false && "intentional Release/NDEBUG failure probe");
    return 0;
}
