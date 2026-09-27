// 文件：tb_daq_axis_streamer.v
// 说明：同步 BRAM 读延迟、AXIS 反压与末拍释放仿真
// 版本：v1.0
// 日期：2026/09/27
// 修改历史：
// v1.0 2026/09/27 新增：定向检查读请求流水线、稳定输出与 TLAST
`timescale 1ns/1ps

module tb_daq_axis_streamer;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0, readable = 1, ready = 0;
    reg [63:0] read_data = 0;
    wire read_issue, last_accept, pending;
    wire [11:0] read_index;
    wire [63:0] tdata;
    wire [7:0] tkeep;
    wire tlast, tvalid;
    reg test_pass = 0, held = 0, first_valid_seen = 0;
    reg [63:0] held_data;
    reg held_last;
    integer cycles = 0, beats = 0, last_count = 0, first_issue_cycle = -1;
    daq_axis_streamer dut (
        .aclk(clk), .aresetn(rstn), .clear_pulse(1'b0),
        .block_readable(readable), .read_data(read_data),
        .read_issue(read_issue), .read_index(read_index),
        .stream_last_accept(last_accept), .stream_pending(pending),
        .m_axis_tdata(tdata), .m_axis_tkeep(tkeep), .m_axis_tlast(tlast),
        .m_axis_tvalid(tvalid), .m_axis_tready(ready)
    );

    // 仿真源在读请求时钟沿更新，与无附加寄存器的 BMG B 口相同。
    always @(posedge clk) begin
        if (rstn) begin
            cycles = cycles + 1;
            if (read_issue) begin
                read_data <= {52'b0, read_index};
                if (first_issue_cycle < 0) first_issue_cycle = cycles;
            end
            if (held && (!tvalid || tdata !== held_data || tlast !== held_last))
                $fatal(1, "AXIS changed under stall");
            held = tvalid && !ready;
            if (held) begin held_data = tdata; held_last = tlast; end
            if (tvalid && !first_valid_seen) begin
                if (cycles - first_issue_cycle != 2)
                    $fatal(1, "synchronous read latency");
                first_valid_seen = 1;
            end
            if (tvalid && ready) begin
                if (tdata !== {32'b0, beats[31:0]} || tkeep !== 8'hff)
                    $fatal(1, "sample data/order");
                if (tlast !== (beats == 4095) || last_accept !== (beats == 4095))
                    $fatal(1, "TLAST/release");
                if (tlast) last_count = last_count + 1;
                beats = beats + 1;
            end
        end
    end
    initial begin
        repeat (4) @(negedge clk); rstn = 1;
        wait (tvalid);
        repeat (5) @(negedge clk);
        if (!tvalid || tdata !== 0 || !pending) $fatal(1, "first beat stall");
        ready = 1;
        wait (beats == 4096);
        @(negedge clk); readable = 0;
        if (last_count != 1 || read_index != 0) $fatal(1, "block completion");
        test_pass = 1;
        $display("PASS: daq_axis_streamer read latency, 4096 beats, stall, TLAST");
        $finish;
    end
    initial begin #200000; $fatal(1, "timeout"); end
endmodule
