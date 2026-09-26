/**************************************************************************/
// Function   : AXIS接口的2选1数据选择器
// Version    : v1.0
// Date       : 2023/05/05
// Description: 根据sel信号选择s0或s1 AXI-Stream通道数据输出
//              MODE=0：时序模式，sel在时钟上升沿同步生效
//              MODE=1：异步模式，sel变化后立即切换通道
//
// Modify:
// version       date       modify
// --------    -----------  ------------------------------------------------
//  v1.0        2023/05/05  创建文件
/**************************************************************************/
`timescale 1ns/1ps

module mux2_1 #(
  parameter WIDTH = 1280,  // 数据位宽
  parameter MODE  = 0      // 0:时序模式  1:异步模式
)(
  input  wire              clk            ,  // 系统时钟
  input  wire              rst_n          ,  // 低有效异步复位

  input  wire              sel            ,  // 通道选择：0=s0，1=s1

  // s0 输入通道
  input  wire [WIDTH-1:0]  s0_axis_tdata  ,  // 输入数据
  input  wire              s0_axis_tvalid ,  // 数据有效
  input  wire              s0_axis_tlast  ,  // 帧结束标志
  output wire              s0_axis_tready ,  // 接收就绪

  // s1 输入通道
  input  wire [WIDTH-1:0]  s1_axis_tdata  ,  // 输入数据
  input  wire              s1_axis_tvalid ,  // 数据有效
  input  wire              s1_axis_tlast  ,  // 帧结束标志
  output wire              s1_axis_tready ,  // 接收就绪

  // 输出通道
  output wire [WIDTH-1:0]  m_axis_tdata   ,  // 输出数据
  output wire              m_axis_tvalid  ,  // 输出有效
  output wire              m_axis_tlast   ,  // 帧结束标志
  input  wire              m_axis_tready     // 下游接收就绪
);

/********************* 数据选择逻辑 ********************/
generate
  if (MODE == 1'b1)  // 异步模式：sel直接驱动组合逻辑
    begin
      assign s0_axis_tready = rst_n ? (sel ? 1'b0        : m_axis_tready  ) : 1'b0;
      assign s1_axis_tready = rst_n ? (sel ? m_axis_tready : 1'b0         ) : 1'b0;
      assign m_axis_tdata   = rst_n ? (sel ? s1_axis_tdata  : s0_axis_tdata ) : {WIDTH{1'b0}};
      assign m_axis_tvalid  = rst_n ? (sel ? s1_axis_tvalid : s0_axis_tvalid) : 1'b0;
      assign m_axis_tlast   = rst_n ? (sel ? s1_axis_tlast  : s0_axis_tlast ) : 1'b0;
    end
  else  // 时序模式：sel在时钟上升沿同步生效
    begin

      /********************* 信号定义 ********************/
      reg              s0_axis_tready_reg ;  // s0 就绪寄存器
      reg              s1_axis_tready_reg ;  // s1 就绪寄存器
      reg [WIDTH-1:0]  m_axis_tdata_reg   ;  // 输出数据寄存器
      reg              m_axis_tvalid_reg  ;  // 输出有效寄存器
      reg              m_axis_tlast_reg   ;  // 帧结束寄存器

      /********************* 时序逻辑 ********************/
      always @(posedge clk or negedge rst_n)
        begin
          if (rst_n == 1'b0)
            begin
              s0_axis_tready_reg <= 1'b0;
              s1_axis_tready_reg <= 1'b0;
              m_axis_tdata_reg   <= {WIDTH{1'b0}};
              m_axis_tvalid_reg  <= 1'b0;
              m_axis_tlast_reg   <= 1'b0;
            end
          else
            begin
              if (sel == 1'b1)  // 选择s1通道
                begin
                  s0_axis_tready_reg <= 1'b0;
                  s1_axis_tready_reg <= m_axis_tready;
                  m_axis_tdata_reg   <= s1_axis_tdata;
                  m_axis_tvalid_reg  <= s1_axis_tvalid;
                  m_axis_tlast_reg   <= s1_axis_tlast;
                end
              else  // 选择s0通道
                begin
                  s0_axis_tready_reg <= m_axis_tready;
                  s1_axis_tready_reg <= 1'b0;
                  m_axis_tdata_reg   <= s0_axis_tdata;
                  m_axis_tvalid_reg  <= s0_axis_tvalid;
                  m_axis_tlast_reg   <= s0_axis_tlast;
                end
            end
        end

      assign s0_axis_tready = s0_axis_tready_reg;
      assign s1_axis_tready = s1_axis_tready_reg;
      assign m_axis_tdata   = m_axis_tdata_reg;
      assign m_axis_tvalid  = m_axis_tvalid_reg;
      assign m_axis_tlast   = m_axis_tlast_reg;

    end
endgenerate

endmodule