// 文件：tb_daq_ping_pong_buffer.v
// 说明：官方 BMG 双块所有权、同步读与同拍释放写入仿真
// 版本：v1.0
// 日期：2026/09/27
// 修改历史：
// v1.0 2026/09/27 新增：检查完整块、双块占用、IP 端口读写及复位保持
`timescale 1ns/1ps

module tb_daq_ping_pong_buffer;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0, clear_pulse = 0, sample_valid = 0;
    reg [63:0] sample_data = 0;
    reg read_issue = 0, last_accept = 0;
    reg [11:0] read_index = 0;
    wire writable, pending, readable;
    wire [63:0] read_data;
    reg test_pass = 0;
    integer i;
    daq_ping_pong_buffer dut (
        .aclk(clk), .aresetn(rstn), .clear_pulse(clear_pulse),
        .sample_valid(sample_valid), .sample_data(sample_data),
        .selected_writable(writable), .buffer_pending(pending),
        .block_readable(readable), .read_issue(read_issue),
        .read_index(read_index), .read_data(read_data),
        .stream_last_accept(last_accept)
    );
    always @(posedge clk) begin
        if (dut.bank0_ram.ena && dut.bank0_ram.enb)
            $fatal(1, "bank0 simultaneous read/write");
        if (dut.bank1_ram.ena && dut.bank1_ram.enb)
            $fatal(1, "bank1 simultaneous read/write");
        if (!rstn && (dut.bank0_ram.ena || dut.bank1_ram.ena ||
                      dut.bank0_ram.enb || dut.bank1_ram.enb))
            $fatal(1, "IP port enabled during reset");
    end

    task fill_block;
        input [63:0] base;
        begin
            for (i = 0; i < 4096; i = i + 1) begin
                @(negedge clk);
                if (!writable) $fatal(1, "full bank not writable at index %0d", i);
                sample_data = base + i;
                sample_valid = 1;
            end
            @(negedge clk); sample_valid = 0;
        end
    endtask
    task read_word;
        input [11:0] addr;
        input [63:0] expected;
        begin
            @(negedge clk); read_index = addr; read_issue = 1;
            @(negedge clk); read_issue = 0;
            if (read_data !== expected) $fatal(1, "BMG read addr=%0d got=%0h expected=%0h", addr, read_data, expected);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk); rstn = 1;
        fill_block(64'h1000);
        if (!readable || !pending) $fatal(1, "bank0 full");
        fill_block(64'h2000);
        if (writable || !readable) $fatal(1, "two full banks");
        read_word(0, 64'h1000);
        read_word(4095, 64'h1fff);
        @(negedge clk); last_accept = 1; sample_valid = 1;
        sample_data = 64'hfedcba9876543210;
        #1;
        if (!writable) $fatal(1, "same-cycle release/write unavailable");
        @(negedge clk); last_accept = 0; sample_valid = 0;
        if (!pending || !readable) $fatal(1, "bank ownership after release");
        // 复位清所有权但不清官方 BRAM IP 的存储内容。
        rstn = 0;
        repeat (3) @(negedge clk);
        if (pending || readable) $fatal(1, "ownership retained on reset");
        rstn = 1;
        // 定向探测 BMG 端口的已存内容；正常 streamer 仍只读完整块。
        read_word(0, 64'hfedcba9876543210);
        test_pass = 1;
        $display("PASS: daq_ping_pong_buffer BMG read, ownership, release/write, reset");
        $finish;
    end
    initial begin #200000; $fatal(1, "timeout"); end
endmodule
