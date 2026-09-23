// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_vector_int32_alu_tb;
 logic[2:0]opcode;logic[1023:0]source0_data,source1_data,result_data;logic[31:0]lane_mask;logic illegal_opcode;integer lane;
 cgx1_vector_int32_alu dut(.*);
 task automatic fill(input logic[31:0]a,input logic[31:0]b);begin for(lane=0;lane<32;lane=lane+1)begin source0_data[(lane*32)+:32]=a+lane;source1_data[(lane*32)+:32]=b;end end endtask
 initial begin
  lane_mask=32'hffffffff;fill(32'd10,32'd3);opcode=0;#1;if(result_data[31:0]!=13)$fatal(1,"ADD mismatch");opcode=1;#1;if(result_data[31:0]!=7)$fatal(1,"SUB mismatch");opcode=4;#1;if(result_data[31:0]!=(10^3))$fatal(1,"XOR mismatch");source0_data[31:0]=32'h80000000;source1_data[31:0]=1;opcode=7;#1;if(result_data[31:0]!=32'hc0000000)$fatal(1,"ASR mismatch");lane_mask=32'h00000001;opcode=0;#1;for(lane=1;lane<32;lane=lane+1)if(result_data[(lane*32)+:32]!=0)$fatal(1,"inactive lane produced vector result");
  $display("[pass] CGX 1 vector INT32 ALU checks passed.");$finish;
 end
endmodule
