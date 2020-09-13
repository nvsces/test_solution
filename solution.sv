// You have to write this module to get the message "TEST IS SUCCESSFUL" from the module solution_tb
// You can read about Avalon-ST interface in URL (chapter 5): https://www.intel.com/content/dam/www/programmable/us/en/pdfs/literature/manual/mnl_avalon_spec.pdf
module solution(
	input clk, rst,
	
	// Avalon-ST Interface (ready_latency = 0)
	input snk_sop, snk_eop, snk_valid,
	input[31:0] snk_data,
	output logic snk_ready,
	
	// Avalon-ST Interface (ready_latency = 0)
	input src_ready,
	output logic src_sop, src_eop, src_valid,
	output logic[31:0] src_data
);	

logic reset=1;
logic eop=0;
logic sop=0;
typedef enum logic[1:0] {OPCODE_ADD, OPCODE_XOR, OPCODE_AND, OPCODE_OR} opcode_t;
opcode_t opcode;

	always_ff@(posedge clk) begin
		if (reset) begin
			src_eop <= 0;
			src_sop <= 0;
		end
	end



	always_ff@(posedge clk) begin
		if (snk_sop) begin
			src_sop <= 1;
			if (snk_valid) begin
				src_data <= snk_data;
				opcode <= opcode_t' (snk_data);
			end
			reset <= 0;
		end else begin
			src_sop <= 0;
			if (snk_valid) begin
			case (opcode)
				OPCODE_ADD: src_data <= snk_data[31:16] + snk_data[15:0];
				OPCODE_XOR: src_data <= snk_data[31:16] ^ snk_data[15:0];
				OPCODE_AND: src_data <= snk_data[31:16] & snk_data[15:0];
				OPCODE_OR:  src_data <= snk_data[31:16] | snk_data[15:0];
			endcase
			end
		end
	end

	always_ff@(posedge clk) begin
		if (snk_eop) begin
			src_sop <= 0;
			src_eop <= 1;
			reset <= 0;
		end else src_eop <= 0;	
		src_valid <=snk_valid;
		snk_ready <= src_ready;
	end
endmodule : solution