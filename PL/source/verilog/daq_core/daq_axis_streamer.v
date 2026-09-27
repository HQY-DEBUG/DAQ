// 文件：daq_axis_streamer.v
// 说明：完整块同步读请求与 AXI-Stream 握手输出
// 版本：v1.0
// 日期：2026/09/27
// 修改历史：
// v1.0 2026/09/27 新增：拆分同步读流水线、TLAST 与反压控制
`timescale 1ns/1ps

module daq_axis_streamer (
    input wire aclk, aresetn, clear_pulse,
    input wire block_readable,
    input wire [63:0] read_data,
    output wire read_issue,
    output reg [11:0] read_index,
    output wire stream_last_accept,
    output wire stream_pending,
    output reg [63:0] m_axis_tdata,
    output wire [7:0] m_axis_tkeep,
    output reg m_axis_tlast,
    output reg m_axis_tvalid,
    input wire m_axis_tready
);
    localparam [11:0] LAST_INDEX = 12'd4095;
    reg read_pending, read_pending_last;
    wire stream_accept = m_axis_tvalid && m_axis_tready;
    assign stream_last_accept = stream_accept && m_axis_tlast;
    assign stream_pending = m_axis_tvalid || read_pending;
    assign read_issue = !m_axis_tvalid && !read_pending && block_readable;
    assign m_axis_tkeep = 8'hff;

    always @(posedge aclk) begin
        if (!aresetn) begin
            read_index <= 0;
        end else begin
            if (clear_pulse || stream_last_accept) read_index <= 0;
            else if (read_issue) read_index <= read_index + 1'b1;
        end
    end

    // 官方 BRAM IP 的 B 口无附加输出寄存器；请求后一个时钟沿锁存其同步读值。
    always @(posedge aclk) begin
        if (!aresetn) begin
            read_pending <= 0;
            read_pending_last <= 0;
            m_axis_tdata <= 0;
            m_axis_tlast <= 0;
            m_axis_tvalid <= 0;
        end else begin
            if (clear_pulse) read_pending <= 0;
            if (read_issue) begin
                read_pending_last <= (read_index == LAST_INDEX);
                read_pending <= 1;
            end else if (read_pending) begin
                m_axis_tdata <= read_data;
                m_axis_tlast <= read_pending_last;
                m_axis_tvalid <= 1;
                read_pending <= 0;
            end else if (stream_accept) begin
                m_axis_tvalid <= 0;
                m_axis_tlast <= 0;
            end
        end
    end
endmodule
