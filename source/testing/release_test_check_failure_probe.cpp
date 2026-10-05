// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
#include "cgx1_test_check.h"

int main(int argc, char**)
{
    CGX1_TEST_CHECK(argc == 0 && "intentional Release/NDEBUG failure probe");
    return 0;
}
