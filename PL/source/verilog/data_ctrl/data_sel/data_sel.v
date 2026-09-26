/**************************************************************************/
// Function   : Ping-Pong FIFO管理模块
// Version    : v1.1
// Date       : 2026/04/28
// Description: 控制数据在两个FIFO间的写入和读取
//              1. 上电/复位后，先将数据写入ping FIFO
//              2. FIFO读写必须连续，一次性完成
//              3. 当当前选中FIFO写满后，自动切换到另一个FIFO
//              4. 基于当前写入FIFO计数生成AXIS TLAST
//
// Modify:
// version       date       modify
// --------    -----------  ------------------------------------------------
//  v1.1        2026/04/28  修改：脱离状态机，中断由FIFO满边沿直接产生
//  v1.0        2026/02/10  增加intr_num 参数，控制中断保持时长
//  v0.1        2026/02/06  创建文件
/**************************************************************************/
`timescale 1ns/1ns

module data_sel #(
  parameter MAX_DATA_NUM = 16384,
  parameter DATA_WIDTH    = 64,
  parameter COUNT_WIDTH  = 32
)(
  // Clock and Reset
  input  wire                      clk              ,
  input  wire                      rstn             ,

  // Control Inputs
  input  wire                      start            ,  // 采集使能信号

  // FIFO Data Count Inputs
  input  wire [COUNT_WIDTH-1:0]    ping_data_num    ,
  input  wire [COUNT_WIDTH-1:0]    pang_data_num    ,

  // AXI-Stream Handshake Control
  input  wire                      s_axis_tvalid    ,  // 输入数据有效
  input  wire [DATA_WIDTH-1:0]     s_axis_tdata     ,  // 输入数据总线
  output wire                      s_axis_tready    ,  // 上游接收就绪

  output wire                      m_axis_tvalid    ,  // 输出数据有效
  output wire [DATA_WIDTH-1:0]     m_axis_tdata     ,  // 输出数据总线
  input  wire                      m_axis_tready    ,  // 下游接收就绪

  // Control Outputs
  output reg                       data_in_sel      ,  // 0:写入ping, 1:写入pang
  output wire                      data_out_sel     ,  // 0:从ping读, 1:从pang读
  output wire                      m_axis_tlast        // AXIS包尾标志
);

/********************* 信号定义 ********************/
reg                         start_r          ;   // start延迟寄存器
reg                         flush_pending    ;   // 残包flush请求

wire                        axis_handshake   ;   // 上游AXIS握手成功
wire                        flush_handshake  ;   // flush握手成功
wire                        start_negedge    ;   // start下降沿
wire                        cur_fifo_has_data;   // 当前写FIFO存在残包
wire                        ping_last        ;   // ping包尾
wire                        pang_last        ;   // pang包尾
wire                        pkt_last_handshake;  // 满包末拍握手
wire                        partial_handshake;   // 非满包写入握手
wire                        need_flush       ;   // start下降沿需要flush

assign m_axis_tdata = s_axis_tdata;  // 数据通路直接连接，选择由FIFO控制

/********************* AXIS包尾生成 ********************/
assign axis_handshake    = s_axis_tvalid & s_axis_tready;
assign flush_handshake   = flush_pending & m_axis_tready;
assign start_negedge     = (start == 1'b0) & (start_r == 1'b1);
assign cur_fifo_has_data = (data_in_sel == 1'b0) ? (ping_data_num != {COUNT_WIDTH{1'b0}}) : (pang_data_num != {COUNT_WIDTH{1'b0}});
assign ping_last         = (data_in_sel == 1'b0) & (ping_data_num == (MAX_DATA_NUM - 1)) & s_axis_tvalid & (~flush_pending);
assign pang_last         = (data_in_sel == 1'b1) & (pang_data_num == (MAX_DATA_NUM - 1)) & s_axis_tvalid & (~flush_pending);
assign s_axis_tready     = (flush_pending == 1'b1) ? 1'b0 : m_axis_tready;
assign m_axis_tvalid     = s_axis_tvalid | flush_pending;
assign m_axis_tlast      = ping_last | pang_last | flush_pending;
assign pkt_last_handshake = (ping_last | pang_last) & axis_handshake;
assign partial_handshake  = axis_handshake & (~(ping_last | pang_last));
assign need_flush         = start_negedge & ((cur_fifo_has_data & (~pkt_last_handshake)) | partial_handshake);

// v1.1 2026/04/28 新增：检测start下降沿并挂起残包flush请求
always @(posedge clk or negedge rstn)
  begin
    if (rstn == 1'b0)
      begin
        start_r       <= 1'b0;
        flush_pending <= 1'b0;
      end
    else
      begin
        start_r <= start;
        if (flush_handshake == 1'b1)
          begin
            flush_pending <= 1'b0;
          end
        else if (need_flush == 1'b1)
          begin
            flush_pending <= 1'b1;
          end
        else
          begin
            flush_pending <= flush_pending;
          end
      end
  end

/********************* 写入通道选择 ********************/
// v1.1 2026/04/28 修改：仅在AXIS握手形成包尾时切换写FIFOpP
always @(posedge clk or negedge rstn)
  begin
    if (rstn == 1'b0)
      begin
        data_in_sel <= 1'b0;  // 默认写入ping
      end
    else
      begin
        if (flush_handshake == 1'b1)
          begin
            data_in_sel <= ~data_in_sel;
          end
        else if (ping_last == 1'b1 && axis_handshake == 1'b1)
          begin
            data_in_sel <= 1'b1;  // 切到pang
          end
        else if (pang_last == 1'b1 && axis_handshake == 1'b1)
          begin
            data_in_sel <= 1'b0;  // 切回ping
          end
        else
          begin
            data_in_sel <= data_in_sel;
          end
      end
  end

assign data_out_sel = ~data_in_sel;  // 读写相反

endmodule
