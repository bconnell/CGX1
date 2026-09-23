// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Brandon Connell
module cgx1_vector_int32_alu(
 input logic [3:0] opcode,
 input logic [1023:0] source0_data, source1_data,
 input logic [31:0] lane_mask,
 output logic [1023:0] result_data,
 output logic illegal_opcode
);
 integer lane;
 logic [31:0] a,b,r;
 always_comb begin
   result_data='0; illegal_opcode=(opcode>4'd7);
   for(lane=0;lane<32;lane=lane+1) begin
     a=source0_data[(lane*32)+:32]; b=source1_data[(lane*32)+:32]; r='0;
     case(opcode)
       4'd0:r=a+b; 4'd1:r=a-b; 4'd2:r=a&b; 4'd3:r=a|b; 4'd4:r=a^b;
       4'd5:r=a << b[4:0]; 4'd6:r=a >> b[4:0]; 4'd7:r=$signed(a) >>> b[4:0];
       default:r='0;
     endcase
     if(lane_mask[lane]) result_data[(lane*32)+:32]=r;
   end
 end
endmodule
