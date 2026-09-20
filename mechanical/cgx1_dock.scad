// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// CGX 1 external thermal dock packing model, millimeters.
$fn = 48;

dock_l = 310;
dock_w = 210;
dock_h = 75;
wall = 3;

radiator_l = 280;
radiator_w = 120;
radiator_t = 30;
fan_l = 120;
fan_w = 120;
fan_t = 25;

pump_l = 112;
pump_w = 57;
pump_h = 41.95;

module enclosure() {
    difference() {
        color("dimgray",0.25) cube([dock_l,dock_w,dock_h]);
        translate([wall,wall,wall])
            cube([dock_l-2*wall,dock_w-2*wall,dock_h-wall]);
    }
}

module components() {
    color("silver") translate([15,8,8])
        cube([radiator_l,radiator_w,radiator_t]);

    color("black",0.75) translate([22,8,38])
        cube([fan_l,fan_w,fan_t]);
    color("black",0.75) translate([153,8,38])
        cube([fan_l,fan_w,fan_t]);

    color("blue",0.65) translate([15,142,8])
        cube([pump_l,pump_w,pump_h]);

    color("orange",0.45) translate([145,142,8])
        cube([145,50,42]);
}

enclosure();
components();
