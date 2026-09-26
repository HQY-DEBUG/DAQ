/**************************************************************************/
// Function   : 数据生成模块
// Version    : v1.0
// Date       : 2026/2/6
// Description: 通过AXI-Stream接口输出指定数量的连续递增数据
//              1. 接收到start信号后开始输出数据
//              2. 输出MX_DATA_NUM个有效数据后停止
//              3. 使用标准AXI-Stream握手协议
// Modify:
// version       date       modify
// --------    -----------  ------------------------------------------------
//  v1.0        2026/2/6    创建文件
/**************************************************************************/
`timescale 1ns/1ns

module data_gen #(
  parameter MAX_DATA_NUM = 16384, // 输出数据个数
  parameter DATA_WIDTH   = 16,    // 数据位宽
  parameter CNT_WIDTH    = 32     // 计数器位宽
) (
  // Clock and Reset
  input   wire                   clk                             ,
  input   wire                   rstn                            ,

  // Control
  input   wire                   start                           , // 启动信号

  // AXI-Stream Master Interface
  output  reg   [DATA_WIDTH-1:0] m_axis_tdata                    ,
  output  reg                    m_axis_tvalid                   ,
  input   wire                   m_axis_tready                   ,
  output  wire                   m_axis_tlast // 最后一个数据标志
);
// localparam CNT_WIDTH = $clog2(MAX_DATA_NUM)  ; // 计数器位宽，根据MAX_DATA_NUM计算
/********************* 信号定义 ********************/
reg     [CNT_WIDTH-1:0]   data_cnt      ; // 数据计数器
reg     [CNT_WIDTH-1:0]   output_cnt    ; // 输出数据计数器
reg                       gen_active    ; // 生成使能标志
wire                      handshake     ; // 握手成功信号

/********************* 组合逻辑 ********************/
assign handshake   = m_axis_tvalid && m_axis_tready;
assign m_axis_tlast = (output_cnt == MAX_DATA_NUM - 1) && handshake;

/********************* 生成使能控制 ********************/
always @(posedge clk or negedge rstn)
  begin
    if (!rstn)
      gen_active <= 1'b0;
    else if (start && !gen_active)
      gen_active <= 1'b1;
    else if (m_axis_tlast)
      gen_active <= 1'b0;
  end

/********************* 输出数据计数器 ********************/
always @(posedge clk or negedge rstn)
  begin
    if (!rstn)
      output_cnt <= 'd0;
    else if (start && !gen_active)
      output_cnt <= 'd0;
    else if (handshake)
      begin
        if (output_cnt == MAX_DATA_NUM - 1)
          output_cnt <= 'd0;
        else
          output_cnt <= output_cnt + 1'b1;
      end
  end

/********************* 连续递增数据计数器（溢出归零） ********************/
always @(posedge clk or negedge rstn)
  begin
    if (!rstn)
      data_cnt <= 'd0;
    else if (handshake)
      data_cnt <= data_cnt + 1'b1; // 连续递增，溢出自动归零
  end

/********************* AXI-Stream 输出 ********************/
always @(posedge clk or negedge rstn)
  begin
    if (!rstn)
      begin
        m_axis_tvalid <= 1'b0;
        m_axis_tdata  <= 'd0;
      end
    else
      begin
        // tvalid控制：gen_active置高时拉高，握手成功且是最后一个数据时拉低
        if (gen_active && !m_axis_tvalid)
          m_axis_tvalid <= 1'b1;
        else if (handshake && output_cnt == MAX_DATA_NUM - 1)
          m_axis_tvalid <= 1'b0;

        // tdata更新：只在握手成功时更新
        if (handshake)
          m_axis_tdata <= data_cnt + 1'b1; // 输出下一个数据
      end
  end

endmodule
