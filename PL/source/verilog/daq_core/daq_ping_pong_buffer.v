// 文件：daq_ping_pong_buffer.v
// 说明：两块官方 Block Memory Generator IP 的写入、读取和块所有权
// 版本：v1.0
// 日期：2026/09/27
// 修改历史：
// v1.0 2026/09/27 新增：以双 4096x64 BRAM IP 实例管理 ping-pong 缓冲
`timescale 1ns/1ps

module daq_ping_pong_buffer (
    input wire aclk, aresetn, clear_pulse,
    input wire sample_valid,
    input wire [63:0] sample_data,
    output wire selected_writable,
    output wire buffer_pending,
    output wire block_readable,
    input wire read_issue,
    input wire [11:0] read_index,
    output wire [63:0] read_data,
    input wire stream_last_accept
);
    localparam [1:0] FREE = 2'd0, FILLING = 2'd1,
                     FULL = 2'd2, READING = 2'd3;
    localparam [11:0] LAST_INDEX = 12'd4095;
    reg [1:0] bank0_state, bank1_state;
    reg write_bank, read_bank;
    reg [11:0] write_index;
    wire [63:0] bank0_read_data, bank1_read_data;
    wire bank0_free_now = (bank0_state == FREE) ||
                          (stream_last_accept && read_bank == 1'b0);
    wire bank1_free_now = (bank1_state == FREE) ||
                          (stream_last_accept && read_bank == 1'b1);
    assign selected_writable = write_bank ?
        ((bank1_state == FILLING) || (write_index == 0 && bank1_free_now)) :
        ((bank0_state == FILLING) || (write_index == 0 && bank0_free_now));
    assign buffer_pending = (bank0_state != FREE) || (bank1_state != FREE);
    assign block_readable = read_bank ?
        ((bank1_state == FULL) || (bank1_state == READING)) :
        ((bank0_state == FULL) || (bank0_state == READING));
    assign read_data = read_bank ? bank1_read_data : bank0_read_data;

    // 每个 IP A 口只写、B 口只读；均由 100 MHz aclk 驱动，读口无输出寄存器。
    daq_bram_4096x64 bank0_ram (
        .clka(aclk), .ena(aresetn && sample_valid && !write_bank),
        .wea(1'b1), .addra(write_index), .dina(sample_data),
        .clkb(aclk), .enb(aresetn && read_issue && !read_bank),
        .addrb(read_index), .doutb(bank0_read_data)
    );
    daq_bram_4096x64 bank1_ram (
        .clka(aclk), .ena(aresetn && sample_valid && write_bank),
        .wea(1'b1), .addra(write_index), .dina(sample_data),
        .clkb(aclk), .enb(aresetn && read_issue && read_bank),
        .addrb(read_index), .doutb(bank1_read_data)
    );

    always @(posedge aclk) begin
        if (!aresetn) write_index <= 0;
        else begin
            if (clear_pulse) write_index <= 0;
            if (sample_valid) begin
                if (write_index == LAST_INDEX) write_index <= 0;
                else write_index <= write_index + 1'b1;
            end
        end
    end

    // 仅 TLAST 握手释放读块；允许同拍释放旧块并写入该块的新首样本。
    always @(posedge aclk) begin
        if (!aresetn) begin
            bank0_state <= FREE;
            bank1_state <= FREE;
            write_bank <= 0;
            read_bank <= 0;
        end else begin
            if (clear_pulse) begin
                bank0_state <= FREE;
                bank1_state <= FREE;
                write_bank <= 0;
                read_bank <= 0;
            end
            if (stream_last_accept) begin
                if (read_bank) bank1_state <= FREE;
                else bank0_state <= FREE;
                read_bank <= ~read_bank;
            end
            if (read_issue) begin
                if (read_bank) bank1_state <= READING;
                else bank0_state <= READING;
            end
            if (sample_valid) begin
                if (write_bank)
                    bank1_state <= (write_index == LAST_INDEX) ? FULL : FILLING;
                else
                    bank0_state <= (write_index == LAST_INDEX) ? FULL : FILLING;
                if (write_index == LAST_INDEX) write_bank <= ~write_bank;
            end
        end
    end
endmodule
