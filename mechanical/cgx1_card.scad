// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
// CGX 1 low profile dual slot mechanical envelope, millimeters.
$fn = 48;

pcb_l = 167.5;
pcb_h = 68.5;
pcb_t = 1.6;
card_t = 39.5;

fan_d = 50.0;
fan_t = 10;
fin_z = 18.0;
fin_t = 11.0;
fan_z = fin_z + fin_t;

module card() {
    color("green") translate([0,0,8]) cube([pcb_l, pcb_h, pcb_t]);
    color("silver") translate([55,6.75,10]) cube([55,55,8]);
    color("gray",0.65) translate([4,2,fin_z]) cube([159.5,64.5,fin_t]);

    for (x=[38,105]) {
        color("black") translate([x,34.25,fan_z])
            cylinder(h=fan_t,d=fan_d,center=false);
    }

    color("gold") translate([18,-5,7]) cube([90,5,2]);
    color("lightgray") translate([-2,-6,0]) cube([2,80,card_t]);
    color("black") translate([-5,16,20]) rotate([0,90,0]) cylinder(h=8,d=8);
    color("black") translate([-5,31,20]) rotate([0,90,0]) cylinder(h=8,d=8);
}

card();
