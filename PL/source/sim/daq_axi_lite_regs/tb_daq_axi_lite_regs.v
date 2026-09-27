// 文件：tb_daq_axi_lite_regs.v
// 说明：AXI-Lite 地址/数据独立到达及控制寄存器边界仿真
// 版本：v1.0
// 日期：2026/09/27
// 修改历史：
// v1.0 2026/09/27 新增：检查 AW/W 顺序、响应保持与错误写入无副作用
`timescale 1ns/1ps

module tb_daq_axi_lite_regs;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0, sampling = 0, pending = 0, overflow = 0;
    reg [63:0] produced_samples = 64'h123456789abcdef0;
    reg [11:0] awaddr = 0, araddr = 0;
    reg awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;
    wire awready, wready, bvalid, arready, rvalid, run_request, clear_pulse;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    reg test_pass = 0;
    integer clear_count = 0;
    daq_axi_lite_regs dut (
        .aclk(clk), .aresetn(rstn), .s_axi_awaddr(awaddr),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
        .s_axi_rready(rready), .sampling(sampling), .pending(pending),
        .overflow(overflow), .produced_samples(produced_samples),
        .run_request(run_request), .clear_pulse(clear_pulse)
    );
    always @(posedge clk) if (rstn && clear_pulse) clear_count = clear_count + 1;

    task write_expect;
        input [11:0] addr;
        input [31:0] data;
        input first_aw;
        input [1:0] expected;
        begin
            @(negedge clk);
            if (first_aw) begin
                awaddr = addr; awvalid = 1;
                @(negedge clk); awvalid = 0;
                repeat (3) @(negedge clk);
                if (bvalid) $fatal(1, "early B response");
                wdata = data; wstrb = 1; wvalid = 1;
                @(negedge clk); wvalid = 0;
            end else begin
                wdata = data; wstrb = 1; wvalid = 1;
                @(negedge clk); wvalid = 0;
                repeat (3) @(negedge clk);
                if (bvalid) $fatal(1, "early B response");
                awaddr = addr; awvalid = 1;
                @(negedge clk); awvalid = 0;
            end
            repeat (2) @(negedge clk);
            if (!bvalid || bresp !== expected) $fatal(1, "write response");
            repeat (2) @(negedge clk);
            if (!bvalid || bresp !== expected) $fatal(1, "B response not held");
            bready = 1;
            @(negedge clk); bready = 0;
        end
    endtask

    task read_expect;
        input [11:0] addr;
        input [31:0] expected_data;
        input [1:0] expected_resp;
        begin
            @(negedge clk); araddr = addr; arvalid = 1;
            @(negedge clk); arvalid = 0;
            if (!rvalid || rresp !== expected_resp || rdata !== expected_data)
                $fatal(1, "read response");
            repeat (2) @(negedge clk);
            if (!rvalid || rdata !== expected_data) $fatal(1, "R response not held");
            rready = 1;
            @(negedge clk); rready = 0;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk); rstn = 1;
        write_expect(12'h000, 1, 0, 0);
        if (!run_request) $fatal(1, "W-first RUN");
        sampling = 1;
        write_expect(12'h000, 2, 1, 2);
        if (!run_request || clear_count != 0) $fatal(1, "rejected CLEAR side effect");
        write_expect(12'h004, 0, 0, 2);
        read_expect(12'h004, 32'h1, 0);
        read_expect(12'h008, 32'h9abcdef0, 0);
        read_expect(12'h00c, 32'h12345678, 0);
        read_expect(12'h003, 0, 2);
        write_expect(12'h000, 0, 1, 0);
        sampling = 0; pending = 1;
        write_expect(12'h000, 1, 0, 2);
        pending = 0;
        write_expect(12'h000, 2, 1, 0);
        if (run_request || clear_count != 1) $fatal(1, "CLEAR pulse");
        test_pass = 1;
        $display("PASS: daq_axi_lite_regs independent AW/W, errors, hold, clear");
        $finish;
    end
    initial begin #100000; $fatal(1, "timeout"); end
endmodule
