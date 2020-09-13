`timescale 1ps/1ps
module solution_tb();
	// You can edit these parameters to easy your debug, but they will are enable in the final test
	localparam RANDOM_READY_EN = 0; // 1 - enable, 0 - disable
	localparam RANDOM_VALID_EN = 1; // 1 - enable, 0 - disable
	localparam PACKETS_NUM = 100; // The number must be greater than 0
	localparam MAX_SAMPLES_PER_PACKET = 10; // The number must be greater than 1
	
	typedef enum logic[1:0] {OPCODE_ADD, OPCODE_XOR, OPCODE_AND, OPCODE_OR} opcode_t;
	
	class Data;
		logic sop, eop;
		logic[31:0] data;
		time timestamp;
		string tag;
		
		function new(string _tag, logic _sop, _eop, logic[31:0] _data);
			tag = _tag;
			sop = _sop;
			eop = _eop;
			data = _data;
		endfunction : new
		
		function bit is_equal(Data obj);
			if (
				(sop != obj.sop) || 
				(eop != obj.eop) ||
				(data != obj.data)
			)
				return 0;
			else
				return 1;
		endfunction : is_equal
		
		function void print();
			$display("----%0s----", tag);
			$display("timestamp: %0t", timestamp);
			$display("sop: %0d, eop: %0d", sop, eop);
			$display("data: %0h", data);
		endfunction : print
	endclass : Data
	
	bit RANDOM_READY = 0;
	bit RANDOM_VALID = 0;

	logic clk = '0, rst = '0;
	
	 This this Avalon-ST bus (ready_latency = 0), sop - StartOfPacket, eoo - EndOfPacket
	logic snk_valid = '0, snk_sop = '0, snk_eop = '0, snk_ready;
	logic[31:0] snk_data = '0;
	
	logic src_valid, src_sop, src_eop, src_ready = '1;
	logic[31:0] src_data;
	
	mailbox #(Data) in_mb = new(), out_mb = new();
	
	int req_cnt = 0, in_cnt = 0, out_cnt = 0;
	int pass_cnt = 0, fail_cnt = 0;
	
	always #1 clk <= ~clk;
	
	always_ff @(posedge clk)
		if (RANDOM_READY)
			src_ready <= $urandom();
		else
			src_ready <= '1;
	
	initial begin : main
		fork
		//	monitor_pack(src_sop, src_eop, src_valid, src_ready);
			monitor_in();
			monitor_out();
			compare();
		join_none
	
		reset();
		
		// Generate
		for (int i = 0; i < PACKETS_NUM; ++i) begin
			RANDOM_READY = RANDOM_READY_EN ? $urandom() : '0;
			RANDOM_VALID = RANDOM_VALID_EN ? $urandom() : '0;
			avalon_st_generate(2 + ($urandom() % (MAX_SAMPLES_PER_PACKET-2)));
			repeat ($urandom() % 10) @(posedge clk);
		end
		
		// Result
		#1000 if ((req_cnt == in_cnt) && (in_cnt == out_cnt) && (out_cnt == pass_cnt) && (0 == fail_cnt)) begin
			$display("TEST IS SUCCESSFUL");
		end
		else begin
			$display("TEST IS FAILED");
		end
		
		$display("req_cnt: %0d, in_cnt: %0d, out_cnt: %0d", req_cnt, in_cnt, out_cnt);
		$display("pass_cnt: %0d, fail_cnt: %0d", pass_cnt, fail_cnt);
		
		$stop();
	end : main
	
	task avalon_st_generate(int n);
		logic valid;
		int i;
		logic[31:0] data;
		i = 0;
		valid = '0;
		
		while (i < n) begin
			if (snk_ready) begin
				snk_sop <= '0;
				snk_eop <= '0;
				snk_valid <= '0;
			end
			valid = RANDOM_VALID ? $urandom() : '1;
			
			if (valid) begin
				snk_sop <= (0 == i) ? '1 : '0;
				snk_eop <= ((n-1) == i) ? '1 : '0;
				snk_valid <= '1;
				
				if (0 == i)
					snk_data <= ($urandom() & 2'b11);
				else 
					snk_data <= $urandom() & 32'h7FFF7FFF;
				@(posedge clk);
				while (!snk_ready)
					@(posedge clk);
				++i; ++req_cnt;
			end
			else begin
				snk_sop <= $urandom();
				snk_eop <= $urandom();
				@(posedge clk);
			end
		
		end
		snk_valid <= '0;
	endtask : avalon_st_generate
	
	task automatic monitor_pack(ref logic sop, eop, valid, ready);
		automatic logic pack;
		pack = '0;
		forever @(negedge clk) if (valid && ready) begin
			if (sop & eop) begin
				$error("SOP and EOP can not are being simulatiously");
				$stop();
			end
			else if (sop & !eop) begin
				if (pack) begin
					$error("There are two SOPs one after another");
					$stop();
				end
				else
					pack = '1;
			end
			else if (!sop && eop) begin
				if (pack)
					pack = '0;
				else begin
					$error("There is EOP without SOP ahead");
					$stop();
				end
			end
			else if (!pack) begin
				$error("There is data without SOP and EOP");
				$stop();
			end
		end

	endtask : monitor_pack
	
	task monitor_in();
		Data in;
		logic[31:0] res;
		opcode_t opcode;
		
		forever @(negedge clk) begin
			if (snk_valid && snk_ready) begin
				if (snk_sop) begin
					opcode = opcode_t' (snk_data);
					in = new("INPUT", snk_sop, snk_eop, snk_data);
					in_mb.put(in);
					++in_cnt;
					continue;
				end
				
				case (opcode)
				OPCODE_ADD: res = snk_data[31:16] + snk_data[15:0];
				OPCODE_XOR: res = snk_data[31:16] ^ snk_data[15:0];
				OPCODE_AND: res = snk_data[31:16] & snk_data[15:0];
				OPCODE_OR:  res = snk_data[31:16] | snk_data[15:0];
				endcase
				
				in = new("INPUT", snk_sop, snk_eop, res);
				in_mb.put(in);
				++in_cnt;
			end
		end
	endtask : monitor_in
	
	task monitor_out();
		Data out;
		forever @(negedge clk) begin
			if (src_valid && src_ready) begin
				out = new("OUTPUT", src_sop, src_eop, src_data);
				out_mb.put(out);
				++out_cnt;
			end
		end
	endtask : monitor_out
	
	task compare();
		Data in, out;
		forever @(posedge clk) begin
			if ((in_mb.num() > 0) && (out_mb.num() > 0)) begin
				in_mb.get(in);
				out_mb.get(out);
				
				if (in.is_equal(out))
					++pass_cnt;
				else begin
					++fail_cnt;
					in.print();
					out.print();
				end
			end
		end
	endtask : compare
	
	task reset();
		@(posedge clk);
		rst <= '1;
		@(posedge clk);
		rst <= '0;
		@(posedge clk);
	endtask : reset
	
	solution sol_inst(
		.*
	);
endmodule : solution_tb