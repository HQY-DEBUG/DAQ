// 文件：daq_core.v
// 说明：固定 1 MHz 采样、双块 BRAM 和 AXI-Lite/AXI-Stream 接口
// 版本：v1.5
// 日期：2026/09/26
// 修改历史：
// v1.5 2026/09/26 修改：BRAM 使能相关状态改为同步复位，避免异步控制脚风险
// v1.4 2026/09/26 修改：BRAM 地址计数器改为同步复位，消除复位断言时的异步地址风险
// v1.3 2026/09/26 修改：以无复位同步读口访问两块 RAM，使存储映射到 BRAM
`timescale 1ns/1ps

module daq_core (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK", X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI:M_AXIS, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *)
    input  wire        aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST", X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        aresetn,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR", X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, ADDR_WIDTH 12, DATA_WIDTH 32" *)
    input  wire [11:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire        s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output wire        s_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]  s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire        s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output wire        s_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output reg  [1:0]  s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output reg         s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire        s_axi_bready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [11:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire        s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output wire        s_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output reg  [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output reg  [1:0]  s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output reg         s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire        s_axi_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TDATA", X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS, TDATA_NUM_BYTES 8" *)
    output reg  [63:0] m_axis_tdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *)
    output wire [7:0]  m_axis_tkeep,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TLAST" *)
    output reg         m_axis_tlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TVALID" *)
    output reg         m_axis_tvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS TREADY" *)
    input  wire        m_axis_tready
);

    localparam [1:0] FREE = 2'd0, FILLING = 2'd1,
                     FULL = 2'd2, READING = 2'd3;
    localparam [11:0] LAST_INDEX = 12'd4095;

    // 写入块与输出块独占，只有 TLAST 握手完成才能释放输出块。
    (* ram_style = "block" *) reg [63:0] bank0 [0:4095];
    (* ram_style = "block" *) reg [63:0] bank1 [0:4095];
    reg [1:0] bank0_state, bank1_state;
    reg write_bank, read_bank, axis_bank;
    reg [11:0] write_index, read_index;
    reg [63:0] bank0_read_data, bank1_read_data;
    reg read_pending, read_pending_last;
    wire [63:0] produced_samples;
    wire sampling, overflow;
    wire sample_valid;
    wire [63:0] sample_data;

    // AW、W 可独立到达；响应保持到 BREADY/RREADY。
    reg [11:0] aw_addr_hold;
    reg aw_held;
    reg [31:0] w_data_hold;
    reg [3:0] w_strb_hold;
    reg w_held;
    reg run_request;
    wire aw_accept = s_axi_awvalid && s_axi_awready;
    wire w_accept = s_axi_wvalid && s_axi_wready;
    wire write_commit = aw_held && w_held && !s_axi_bvalid;
    wire stream_accept = m_axis_tvalid && m_axis_tready;
    wire stream_last_accept = stream_accept && m_axis_tlast;
    wire read_issue = !m_axis_tvalid && !read_pending &&
                      (read_bank ? ((bank1_state == FULL) || (bank1_state == READING)) :
                                   ((bank0_state == FULL) || (bank0_state == READING)));
    wire bank0_free_now = (bank0_state == FREE) ||
                          (stream_last_accept && axis_bank == 1'b0);
    wire bank1_free_now = (bank1_state == FREE) ||
                          (stream_last_accept && axis_bank == 1'b1);
    wire selected_writable = write_bank ?
        ((bank1_state == FILLING) || (write_index == 0 && bank1_free_now)) :
        ((bank0_state == FILLING) || (write_index == 0 && bank0_free_now));
    wire pending = (bank0_state != FREE) || (bank1_state != FREE) ||
                   m_axis_tvalid || read_pending;
    wire control_address = aw_addr_hold == 12'h000;
    wire control_byte = w_strb_hold[0];
    wire control_reserved = |w_data_hold[7:2];
    wire control_clear = w_data_hold[1];
    wire control_run = w_data_hold[0];
    wire run_allowed = (sampling && run_request) ||
                       (!sampling && !pending && !overflow);
    wire clear_pulse = write_commit && control_address && control_byte &&
                       !control_reserved && control_clear && !control_run &&
                       !sampling && !pending;
    wire generator_run = run_request && (sampling || !pending);
    daq_data_gen data_gen_0 (
        .clk(aclk), .resetn(aresetn), .run_request(generator_run),
        .clear(clear_pulse), .sink_available(selected_writable),
        .sample_valid(sample_valid), .sample_data(sample_data),
        .sampling(sampling), .overflow(overflow),
        .produced_samples(produced_samples)
    );
    assign m_axis_tkeep = 8'hff;
    assign s_axi_awready = !aw_held && !s_axi_bvalid;
    assign s_axi_wready = !w_held && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;

    // 2026/09/26 修改：两块存储使用无复位同步读写口，状态及 AXIS 输出单独复位。
    always @(posedge aclk) begin
        if (aresetn && sample_valid) begin
            if (write_bank) bank1[write_index] <= sample_data;
            else bank0[write_index] <= sample_data;
        end
        if (aresetn && read_issue) begin
            if (read_bank) bank1_read_data <= bank1[read_index];
            else bank0_read_data <= bank0[read_index];
        end
    end

    // 2026/09/26 修改：地址寄存器在时钟沿复位，复位期间 RAM 端口仍保持禁用。
    always @(posedge aclk) begin
        if (!aresetn) begin
            write_index <= 0;
            read_index <= 0;
        end else begin
            if (clear_pulse) begin
                write_index <= 0;
                read_index <= 0;
            end
            if (stream_last_accept) read_index <= 0;
            else if (read_issue) read_index <= read_index + 1'b1;
            if (sample_valid) begin
                if (write_index == LAST_INDEX) write_index <= 0;
                else write_index <= write_index + 1'b1;
            end
        end
    end

    // 2026/09/26 修改：先判地址和字节使能，再校验控制位与运行状态；错误写入无副作用。
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

    // 2026/09/26 修改：只接受精确对齐的寄存器地址，错误读保持 RDATA=0。
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

    // 2026/09/26 修改：块所有权及 AXIS 有效位同步复位，避免异步变化到达 BRAM 使能脚。
    always @(posedge aclk) begin
        if (!aresetn) begin
            bank0_state <= FREE;
            bank1_state <= FREE;
            write_bank <= 0;
            read_bank <= 0;
            axis_bank <= 0;
            read_pending <= 0;
            read_pending_last <= 0;
            m_axis_tdata <= 0;
            m_axis_tlast <= 0;
            m_axis_tvalid <= 0;
        end else begin
            if (clear_pulse) begin
                bank0_state <= FREE;
                bank1_state <= FREE;
                write_bank <= 0;
                read_bank <= 0;
                read_pending <= 0;
            end

            if (stream_last_accept) begin
                if (axis_bank) bank1_state <= FREE;
                else bank0_state <= FREE;
                read_bank <= ~read_bank;
            end
            if (read_issue) begin
                if (read_bank) bank1_state <= READING;
                else bank0_state <= READING;
                axis_bank <= read_bank;
                read_pending_last <= (read_index == LAST_INDEX);
                read_pending <= 1;
            end else if (read_pending) begin
                m_axis_tdata <= axis_bank ? bank1_read_data : bank0_read_data;
                m_axis_tlast <= read_pending_last;
                m_axis_tvalid <= 1;
                read_pending <= 0;
            end else if (stream_accept) begin
                m_axis_tvalid <= 0;
                m_axis_tlast <= 0;
            end

            if (sample_valid) begin
                if (write_bank) begin
                    bank1_state <= (write_index == LAST_INDEX) ? FULL : FILLING;
                end else begin
                    bank0_state <= (write_index == LAST_INDEX) ? FULL : FILLING;
                end
                if (write_index == LAST_INDEX) begin
                    write_bank <= ~write_bank;
                end
            end
        end
    end
endmodule
