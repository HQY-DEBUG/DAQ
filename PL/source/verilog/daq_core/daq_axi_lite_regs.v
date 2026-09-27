// 文件：daq_axi_lite_regs.v
// 说明：DAQ 控制寄存器与独立 AW/W 通道的 AXI-Lite 响应
// 版本：v1.0
// 日期：2026/09/27
// 修改历史：
// v1.0 2026/09/27 新增：拆分控制寄存器与 AXI-Lite 握手
`timescale 1ns/1ps

module daq_axi_lite_regs (
    input wire aclk, aresetn,
    input wire [11:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,
    input wire [11:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready,
    input wire sampling, pending, overflow,
    input wire [63:0] produced_samples,
    output reg run_request,
    output wire clear_pulse
);
    reg [11:0] aw_addr_hold;
    reg aw_held;
    reg [31:0] w_data_hold;
    reg [3:0] w_strb_hold;
    reg w_held;
    wire aw_accept = s_axi_awvalid && s_axi_awready;
    wire w_accept = s_axi_wvalid && s_axi_wready;
    wire write_commit = aw_held && w_held && !s_axi_bvalid;
    wire control_address = aw_addr_hold == 12'h000;
    wire control_byte = w_strb_hold[0];
    wire control_reserved = |w_data_hold[7:2];
    wire control_clear = w_data_hold[1];
    wire control_run = w_data_hold[0];
    wire run_allowed = (sampling && run_request) ||
                       (!sampling && !pending && !overflow);
    assign clear_pulse = write_commit && control_address && control_byte &&
                         !control_reserved && control_clear && !control_run &&
                         !sampling && !pending;
    assign s_axi_awready = !aw_held && !s_axi_bvalid;
    assign s_axi_wready = !w_held && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    // AW 与 W 可按任意顺序到达；一次写响应只对应一组已锁存请求。
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            aw_addr_hold <= 0;
            aw_held <= 0;
            w_data_hold <= 0;
            w_strb_hold <= 0;
            w_held <= 0;
            s_axi_bresp <= 0;
            s_axi_bvalid <= 0;
            run_request <= 0;
        end else begin
            if (aw_accept) begin
                aw_addr_hold <= s_axi_awaddr;
                aw_held <= 1;
            end
            if (w_accept) begin
                w_data_hold <= s_axi_wdata;
                w_strb_hold <= s_axi_wstrb;
                w_held <= 1;
            end
            if (write_commit) begin
                aw_held <= 0;
                w_held <= 0;
                s_axi_bvalid <= 1;
                s_axi_bresp <= 0;
                if (!control_address) begin
                    s_axi_bresp <= 2'b10;
                end else if (control_byte) begin
                    if (control_reserved || (control_clear && control_run)) begin
                        s_axi_bresp <= 2'b10;
                    end else if (control_clear) begin
                        if (!sampling && !pending) run_request <= 0;
                        else s_axi_bresp <= 2'b10;
                    end else if (control_run && !run_allowed) begin
                        s_axi_bresp <= 2'b10;
                    end else begin
                        run_request <= control_run;
                    end
                end
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 0;
            if (overflow) run_request <= 0;
        end
    end

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            s_axi_rdata <= 0;
            s_axi_rresp <= 0;
            s_axi_rvalid <= 0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1;
                s_axi_rresp <= 0;
                case (s_axi_araddr)
                    12'h000: s_axi_rdata <= {30'b0, 1'b0, run_request};
                    12'h004: s_axi_rdata <= {29'b0, overflow, pending, sampling};
                    12'h008: s_axi_rdata <= produced_samples[31:0];
                    12'h00c: s_axi_rdata <= produced_samples[63:32];
                    12'h010: s_axi_rdata <= 32'd4096;
                    12'h014: s_axi_rdata <= 32'd1000000;
                    12'h018: s_axi_rdata <= 32'h00010000;
                    default: begin
                        s_axi_rdata <= 0;
                        s_axi_rresp <= 2'b10;
                    end
                endcase
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 0;
            end
        end
    end
endmodule
