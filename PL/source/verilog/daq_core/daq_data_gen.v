// 文件：daq_data_gen.v
// 说明：独立的 100 MHz 到 1 MHz、64 bit 递增测试数据源
// 版本：v1.1
// 日期：2026/09/26
// 修改历史：
// v1.1 2026/09/26 修改：采样有效位改为同步复位，避免异步变化到达 BRAM 写使能
// v1.0 2026/09/26 新增：固定 100 周期采样，不受 DMA 反压改变节拍
`timescale 1ns/1ps

module daq_data_gen (
    input  wire        clk,
    input  wire        resetn,
    input  wire        run_request,
    input  wire        clear,
    input  wire        sink_available,
    output reg         sample_valid,
    output reg  [63:0] sample_data,
    output reg         sampling,
    output reg         overflow,
    output reg  [63:0] produced_samples
);
    reg [6:0] phase;
    reg [11:0] block_index;

    // 2026/09/26 修改：采样输出同步复位；采样节拍与无缓冲溢出行为保持不变。
    always @(posedge clk) begin
        if (!resetn) begin
            phase <= 0;
            block_index <= 0;
            sample_valid <= 0;
            sample_data <= 0;
            sampling <= 0;
            overflow <= 0;
            produced_samples <= 0;
        end else begin
            sample_valid <= 0;
            if (clear && !sampling) begin
                phase <= 0;
                block_index <= 0;
                sample_data <= 0;
                overflow <= 0;
                produced_samples <= 0;
            end else if (!sampling) begin
                phase <= 0;
                if (run_request && !overflow) sampling <= 1;
            end else if (!run_request && block_index == 0) begin
                sampling <= 0;
                phase <= 0;
            end else if (phase == 7'd99) begin
                phase <= 0;
                if (!sink_available) begin
                    overflow <= 1;
                    sampling <= 0;
                end else begin
                    sample_valid <= 1;
                    sample_data <= produced_samples;
                    produced_samples <= produced_samples + 1'b1;
                    block_index <= block_index + 1'b1;
                    if (block_index == 12'd4095 && !run_request)
                        sampling <= 0;
                end
            end else begin
                phase <= phase + 1'b1;
            end
        end
    end
endmodule
