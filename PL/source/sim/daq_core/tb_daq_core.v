// 文件：tb_daq_core.v
// 说明：daq_core 固定节拍、双块切换、反压、停机、溢出和 AXI-Lite 仿真
// 版本：v1.3
// 日期：2026/09/26
// 修改历史：
// v1.3 2026/09/26 修改：采样有效脉冲期间断言复位，验证 RAM 写使能被门控
// v1.2 2026/09/26 修改：验证复位不写 RAM 且旧内容不作为新会话数据输出
// v1.1 2026/09/26 修改：补 4 KiB 非法地址、无副作用、随机反压与三类停采边界
`timescale 1ns/1ps

module tb_daq_core;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    reg [11:0] awaddr = 0;
    reg awvalid = 0;
    wire awready;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;
    reg wvalid = 0;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    reg bready = 0;
    reg [11:0] araddr = 0;
    reg arvalid = 0;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    reg rready = 0;
    wire [63:0] tdata;
    wire [7:0] tkeep;
    wire tlast, tvalid;
    reg ready_manual = 0;
    reg random_ready = 0;
    reg [15:0] lfsr = 16'hace1;
    wire tready = random_ready ? (lfsr[1] | lfsr[0]) : ready_manual;
    integer cycles = 0, last_sample_cycle = -1, beats = 0, last_count = 0;
    reg [63:0] previous_count = 0;
    reg hold_valid = 0;
    reg [63:0] held_data;
    reg held_last;

    daq_core dut (
        .aclk(clk), .aresetn(rstn),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .m_axis_tdata(tdata), .m_axis_tkeep(tkeep), .m_axis_tlast(tlast),
        .m_axis_tvalid(tvalid), .m_axis_tready(tready)
    );

    task fail;
        input [255:0] reason;
        begin $display("FAIL cycle=%0d reason=%0s", cycles, reason); $fatal(1); end
    endtask

    always @(posedge clk) begin
        if (rstn) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end

    // 保持检查跨越长反压和随机反压；仅有效握手推进期望样本。
    always @(posedge clk) begin
        if (rstn) begin
            cycles = cycles + 1;
            if (hold_valid && (!tvalid || tdata !== held_data || tlast !== held_last))
                fail("AXIS changed under backpressure");
            hold_valid = tvalid && !tready;
            if (hold_valid) begin held_data = tdata; held_last = tlast; end
            if (tvalid && tready) begin
                if (tdata !== {32'b0, beats[31:0]}) begin
                    $display("data=%0d expected=%0d index=%0d", tdata, beats, dut.read_index);
                    fail("sample order or value");
                end
                if (tkeep !== 8'hff) fail("TKEEP");
                if (tlast !== ((beats % 4096) == 4095)) fail("TLAST");
                beats = beats + 1;
            end
        end
    end

    // 用实际计数增长检查 100 周期采样，避免把反压误当作节拍控制。
    always @(negedge clk) begin
        if (rstn) begin
            if (!dut.sampling && dut.sample_valid && !dut.pending)
                fail("last sample not pending before BRAM write");
            if (dut.produced_samples != previous_count) begin
                if (dut.produced_samples == 0 && !dut.sampling) begin
                    last_sample_cycle = -1;
                end else begin
                    if (dut.produced_samples != previous_count + 1) fail("sample counter jump");
                    if (last_sample_cycle >= 0 && cycles - last_sample_cycle != 100)
                        fail("sample phase changed");
                    last_sample_cycle = cycles;
                    last_count = last_count + 1;
                end
            end
            previous_count = dut.produced_samples;
        end
    end

    // 2026/09/26 修改：参数化地址、数据及字节使能，覆盖 AXI-Lite 全部拒绝路径。
    task write_reg_expect;
        input [11:0] addr;
        input [31:0] value;
        input [3:0] strb;
        input aw_first;
        input [1:0] expected_resp;
        integer n;
        begin
            @(negedge clk);
            if (aw_first) begin
                awaddr = addr; awvalid = 1;
                @(posedge clk); while (!awready) @(posedge clk);
                @(negedge clk); awvalid = 0;
                repeat (3) @(negedge clk);
                wdata = value; wstrb = strb; wvalid = 1;
                @(posedge clk); while (!wready) @(posedge clk);
                @(negedge clk); wvalid = 0;
            end else begin
                wdata = value; wstrb = strb; wvalid = 1;
                @(posedge clk); while (!wready) @(posedge clk);
                @(negedge clk); wvalid = 0;
                repeat (3) @(negedge clk);
                awaddr = addr; awvalid = 1;
                @(posedge clk); while (!awready) @(posedge clk);
                @(negedge clk); awvalid = 0;
            end
            n = 0;
            while (!bvalid && n < 20) begin @(negedge clk); n = n + 1; end
            if (!bvalid || bresp != expected_resp) fail("write response");
            repeat (3) begin @(negedge clk); if (!bvalid) fail("B backpressure"); end
            bready = 1;
            @(posedge clk); @(negedge clk); bready = 0;
        end
    endtask

    task write_control;
        input [31:0] value;
        input aw_first;
        begin write_reg_expect(12'h000, value, 4'h1, aw_first, 2'b00); end
    endtask

    task write_control_expect;
        input [31:0] value;
        input aw_first;
        input [1:0] expected_resp;
        begin write_reg_expect(12'h000, value, 4'h1, aw_first, expected_resp); end
    endtask

    task read_reg_expect;
        input [11:0] addr;
        input [31:0] expected;
        input [1:0] expected_resp;
        integer n;
        begin
            @(negedge clk); araddr = addr; arvalid = 1;
            @(posedge clk); while (!arready) @(posedge clk);
            @(negedge clk); arvalid = 0;
            n = 0;
            while (!rvalid && n < 20) begin @(negedge clk); n = n + 1; end
            if (!rvalid || rresp != expected_resp || rdata !== expected) fail("read response");
            repeat (3) begin
                @(negedge clk);
                if (!rvalid || rresp != expected_resp || rdata !== expected) fail("R backpressure");
            end
            rready = 1;
            @(posedge clk); @(negedge clk); rready = 0;
        end
    endtask

    task read_reg;
        input [11:0] addr;
        input [31:0] expected;
        begin read_reg_expect(addr, expected, 2'b00); end
    endtask

    initial begin
        repeat (5) @(negedge clk); rstn = 1;
        read_reg(7'h10, 32'd4096);
        read_reg(7'h14, 32'd1000000);
        read_reg(7'h18, 32'h00010000);
        read_reg_expect(7'h03, 32'd0, 2'b10);
        read_reg_expect(7'h1c, 32'd0, 2'b10);
        read_reg_expect(7'h7f, 32'd0, 2'b10);
        read_reg_expect(12'h080, 32'd0, 2'b10);
        read_reg_expect(12'h100, 32'd0, 2'b10);
        read_reg_expect(12'hffc, 32'd0, 2'b10);
        write_reg_expect(7'h04, 32'h1, 4'h1, 1, 2'b10);
        write_reg_expect(7'h1c, 32'h1, 4'h1, 0, 2'b10);
        write_reg_expect(7'h01, 32'h1, 4'h0, 1, 2'b10);
        write_reg_expect(12'h080, 32'h1, 4'h1, 1, 2'b10);
        write_reg_expect(12'h100, 32'h2, 4'h1, 0, 2'b10);
        write_reg_expect(12'hffc, 32'h1, 4'h0, 1, 2'b10);
        write_reg_expect(7'h00, 32'h3, 4'h0, 0, 2'b00);
        write_reg_expect(7'h00, 32'hffff0000, 4'hf, 1, 2'b00);
        write_control_expect(32'h4, 0, 2'b10);
        write_control_expect(32'h3, 1, 2'b10);
        read_reg(7'h00, 32'd0);
        read_reg(7'h04, 32'd0);

        // 2026/09/26 修改：首样本前停止不能生成短块或遗留 RUN。
        write_control(32'h1, 0);
        write_control(32'h0, 1);
        wait (!dut.sampling);
        repeat (105) @(negedge clk);
        if (dut.produced_samples != 0 || beats != 0) fail("stop before first sample");
        read_reg(7'h04, 32'd0);
        write_control(32'h2, 1);

        // 块中停止时先保留末块，再拒绝排空期间的非法 RUN。
        write_control(32'h1, 0);
        wait (dut.produced_samples >= 64);
        write_control(32'h1, 1);
        write_control_expect(32'h2, 1, 2'b10);
        read_reg(7'h04, 32'h1 | 32'h2);
        wait (dut.produced_samples >= 4096);
        repeat (600) @(negedge clk);
        if (dut.produced_samples < 4101) fail("backpressure stretched sampling");
        random_ready = 1;
        wait (dut.produced_samples >= 9000);
        random_ready = 0;
        write_control(32'h0, 1);
        if (!dut.sampling) fail("stop accepted too late for mid-block case");
        write_control_expect(32'h1, 0, 2'b10);
        read_reg(7'h00, 32'd0);
        wait (!dut.sampling);
        if (dut.produced_samples != 12288) fail("stop not at block boundary");
        write_control_expect(32'h1, 0, 2'b10);
        read_reg(7'h00, 32'd0);
        write_control_expect(32'h2, 1, 2'b10);
        random_ready = 1;
        wait (beats == 12288);
        random_ready = 0;
        repeat (5) @(negedge clk);
        read_reg(7'h04, 32'h0);
        read_reg(7'h08, 32'd12288);
        write_control(32'h2, 0);
        read_reg(7'h08, 32'd0);
        beats = 0;
        ready_manual = 1;

        // 停止请求恰在完整块边界后，应保持 4096 样本且无短块。
        write_control(32'h1, 1);
        wait (dut.produced_samples == 4096);
        write_control(32'h0, 0);
        wait (!dut.sampling);
        if (dut.produced_samples != 4096) fail("stop at block boundary");
        wait (beats == 4096);
        read_reg(7'h04, 32'd0);
        write_control(32'h2, 1);
        beats = 0;
        ready_manual = 0;

        // 两块缓冲均未释放时，第三块首样本触发一次锁存溢出。
        write_control(32'h1, 1);
        wait (dut.overflow);
        if (dut.produced_samples != 8192 || dut.sampling) fail("overflow behavior");
        read_reg(7'h04, 32'h6);
        write_control_expect(32'h1, 0, 2'b10);
        read_reg(7'h00, 32'd0);
        read_reg(7'h08, 32'd8192);
        write_control_expect(32'h2, 1, 2'b10);
        ready_manual = 1;
        wait (beats == 8192);
        write_control(32'h0, 0);
        write_control(32'h2, 1);
        read_reg(7'h04, 32'h0);
        read_reg(7'h08, 32'd0);

        // 2026/09/26 修改：RAM 内容不随复位清零，但输出所有权必须清除并只读完整的新块。
        dut.bank0[0] = 64'hdeadcafe12345678;
        @(negedge clk); rstn = 0;
        repeat (4) @(negedge clk);
        if (dut.bank0[0] !== 64'hdeadcafe12345678)
            fail("RAM changed during reset");
        if (tvalid || dut.pending || dut.sampling) fail("reset leaked old block");
        rstn = 1;
        beats = 0;
        write_control(32'h2, 0);
        ready_manual = 1;
        write_control(32'h1, 1);
        wait (dut.produced_samples == 4096);
        write_control(32'h0, 0);
        wait (!dut.sampling);
        wait (beats == 4096);
        read_reg(7'h04, 32'd0);

        // 2026/09/26 修改：在采样有效脉冲与 RAM 写入之间复位，写口不得使用旧脉冲。
        write_control(32'h2, 1);
        dut.bank0[0] = 64'h456789abcdef0123;
        ready_manual = 0;
        write_control(32'h1, 0);
        wait (dut.sample_valid);
        rstn = 0;
        repeat (4) @(negedge clk);
        if (dut.bank0[0] !== 64'h456789abcdef0123)
            fail("RAM write enable active during reset");
        if (tvalid || dut.pending || dut.sampling) fail("reset retained active output");
        rstn = 1;
        beats = 0;
        ready_manual = 1;
        write_control(32'h2, 1);
        write_control(32'h1, 0);
        wait (dut.produced_samples == 4096);
        write_control(32'h0, 1);
        wait (!dut.sampling);
        wait (beats == 4096);
        read_reg(7'h04, 32'd0);
        $display("PASS: AXI-Lite errors, fixed rate, BRAM ownership, random stalls, stop boundaries, overflow/clear");
        $finish;
    end

    initial begin
        #40000000;
        fail("timeout");
    end
endmodule
