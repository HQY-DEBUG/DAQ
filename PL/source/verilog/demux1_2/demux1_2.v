/**************************************************************************/
// Function   : AXIS接口的1分2数据分配器
// Version    : v1.0
// Date       : 2024/11/19
// Description: 根据sel信号将s输入分配到m0或m1 AXI-Stream通道
//              MODE=0：时序模式，sel在时钟上升沿同步生效
//              MODE=1：异步模式，sel变化后立即切换通道
//
// Modify:
// version       date       modify
// --------    -----------  ------------------------------------------------
//  v1.0        2024/11/19  创建文件
/**************************************************************************/
`timescale 1ns/1ps

module demux1_2 #(
  parameter WIDTH = 256,  // 数据位宽
  parameter MODE  = 0     // 0:时序模式  1:异步模式
)(
  input  wire              clk            ,  // 系统时钟
  input  wire              rst_n          ,  // 低有效异步复位

  input  wire              sel            ,  // 通道选择：0=m0，1=m1

  // s 输入通道
  input  wire [WIDTH-1:0]  s_axis_tdata   ,  // 输入数据
  input  wire              s_axis_tvalid  ,  // 数据有效
  input  wire              s_axis_tlast   ,  // 帧结束标志
  output wire              s_axis_tready  ,  // 接收就绪

  // m0 输出通道
  output wire [WIDTH-1:0]  m0_axis_tdata  ,  // 输出数据
  output wire              m0_axis_tvalid ,  // 输出有效
  output wire              m0_axis_tlast  ,  // 帧结束标志
  input  wire              m0_axis_tready ,  // 下游接收就绪

  // m1 输出通道
  output wire [WIDTH-1:0]  m1_axis_tdata  ,  // 输出数据
  output wire              m1_axis_tvalid ,  // 输出有效
  output wire              m1_axis_tlast  ,  // 帧结束标志
  input  wire              m1_axis_tready    // 下游接收就绪
);

/********************* 数据分配逻辑 ********************/
generate
  if (MODE == 1'b1)  // 异步模式：sel直接驱动组合逻辑
    begin
      assign m0_axis_tdata  = rst_n ? (sel ? {WIDTH{1'b0}} : s_axis_tdata  ) : {WIDTH{1'b0}};
      assign m0_axis_tvalid = rst_n ? (sel ? 1'b0          : s_axis_tvalid ) : 1'b0;
      assign m0_axis_tlast  = rst_n ? (sel ? 1'b0          : s_axis_tlast  ) : 1'b0;
      assign m1_axis_tdata  = rst_n ? (sel ? s_axis_tdata  : {WIDTH{1'b0}} ) : {WIDTH{1'b0}};
      assign m1_axis_tvalid = rst_n ? (sel ? s_axis_tvalid : 1'b0          ) : 1'b0;
      assign m1_axis_tlast  = rst_n ? (sel ? s_axis_tlast  : 1'b0          ) : 1'b0;
      assign s_axis_tready  = rst_n ? (sel ? m1_axis_tready : m0_axis_tready) : 1'b0;
    end
  else  // 时序模式：sel在时钟上升沿同步生效
    begin

      /********************* 信号定义 ********************/
      reg              s_axis_tready_reg  ;  // s 就绪寄存器
      reg [WIDTH-1:0]  m0_axis_tdata_reg  ;  // m0 数据寄存器
      reg              m0_axis_tvalid_reg ;  // m0 有效寄存器
      reg              m0_axis_tlast_reg  ;  // m0 帧结束寄存器
      reg [WIDTH-1:0]  m1_axis_tdata_reg  ;  // m1 数据寄存器
      reg              m1_axis_tvalid_reg ;  // m1 有效寄存器
      reg              m1_axis_tlast_reg  ;  // m1 帧结束寄存器

      /********************* 时序逻辑 ********************/
      always @(posedge clk or negedge rst_n)
        begin
          if (rst_n == 1'b0)
            begin
              s_axis_tready_reg  <= 1'b0;
              m0_axis_tdata_reg  <= {WIDTH{1'b0}};
              m0_axis_tvalid_reg <= 1'b0;
              m0_axis_tlast_reg  <= 1'b0;
              m1_axis_tdata_reg  <= {WIDTH{1'b0}};
              m1_axis_tvalid_reg <= 1'b0;
              m1_axis_tlast_reg  <= 1'b0;
            end
          else
            begin
              if (sel == 1'b1)  // 选择m1通道
                begin
                  s_axis_tready_reg  <= m1_axis_tready;
                  m0_axis_tdata_reg  <= {WIDTH{1'b0}};
                  m0_axis_tvalid_reg <= 1'b0;
                  m0_axis_tlast_reg  <= 1'b0;
                  m1_axis_tdata_reg  <= s_axis_tdata;
                  m1_axis_tvalid_reg <= s_axis_tvalid;
                  m1_axis_tlast_reg  <= s_axis_tlast;
                end
              else  // 选择m0通道
                begin
                  s_axis_tready_reg  <= m0_axis_tready;
                  m0_axis_tdata_reg  <= s_axis_tdata;
                  m0_axis_tvalid_reg <= s_axis_tvalid;
                  m0_axis_tlast_reg  <= s_axis_tlast;
                  m1_axis_tdata_reg  <= {WIDTH{1'b0}};
                  m1_axis_tvalid_reg <= 1'b0;
                  m1_axis_tlast_reg  <= 1'b0;
                end
            end
        end

      assign s_axis_tready  = s_axis_tready_reg;
      assign m0_axis_tdata  = m0_axis_tdata_reg;
      assign m0_axis_tvalid = m0_axis_tvalid_reg;
      assign m0_axis_tlast  = m0_axis_tlast_reg;
      assign m1_axis_tdata  = m1_axis_tdata_reg;
      assign m1_axis_tvalid = m1_axis_tvalid_reg;
      assign m1_axis_tlast  = m1_axis_tlast_reg;

    end
endgenerate

endmodule