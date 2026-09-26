`timescale 1ns / 1ns

/**************************************************************************/
// Function   : 采集控制模块
// Version    : v1.0
// Date       : 2026/04/28
// Description: 检测使能信号 en 的上升沿，触发 start 输出脉冲
//              start 高电平持续 TIME 毫秒后自动拉低
//
// Modify:
// version       date       modify
// --------    -----------  ------------------------------------------------
//  v1.0        2026/04/28  创建文件
/**************************************************************************/
module coll_ctrl #(
  parameter TIME       = 1000 , // 高电平持续时间，单位 ms
  parameter CLK_FREQ   = 100    // 时钟频率，单位 MHz
) (
  input  wire                    clk      ,  // 系统时钟
  input  wire                    rstn     ,  // 低有效复位
  input  wire [31:0]             count_max,  // 计数器最大值，计算方式：TIME * CLK_FREQ * 1000
  input  wire                    en       ,  // 使能信号
  output wire                    start       // 输出信号
);

// ---- 寄存器定义 ---- //
reg  [31:0] count    ;  // 计数器寄存器
reg         start_reg;  // 输出寄存器
reg         en_r     ;  // 使能信号同步寄存器
reg         en_r1    ;  // 使能信号延迟寄存器

// ---- 线网定义 ---- //
wire                   en_pose  ;  // 使能信号上升沿

// ---- 上升沿检测 ---- //
always @(posedge clk or negedge rstn)
  begin
    if (rstn == 1'b0)
      begin
        en_r  <= 1'b0;
        en_r1 <= 1'b0;
      end
    else
      begin
        en_r  <= en;    // 同步使能信号
        en_r1 <= en_r;  // 延迟一个时钟周期
      end
  end

assign en_pose = en_r & (~en_r1);  // 上升沿脉冲

// ---- 计数器逻辑 ---- //
always @(posedge clk or negedge rstn)
  begin
    if (rstn == 1'b0)
      begin
        count <= 32'b0;
      end
    else
      begin
        if (en_pose == 1'b1)  // 检测到上升沿，计数器清零
          begin
            count <= 32'b0;
          end
        else if (start_reg == 1'b1)
          begin
            if (count >= count_max)  // 计数到最大值，保持
              begin
                count <= count;
              end
            else  // 继续计数
              begin
                count <= count + 1'b1;
              end
          end
        else
          begin
            count <= 32'b0;  // 非计数状态，计数器清零
          end
      end
  end

// ---- 输出寄存器逻辑 ---- //
always @(posedge clk or negedge rstn)
  begin
    if (rstn == 1'b0)
      begin
        start_reg <= 1'b0;
      end
    else
      begin
        if (en_pose == 1'b1)  // 检测到上升沿，拉高输出
          begin
            start_reg <= 1'b1;
          end
        else if (start_reg == 1'b1 && count >= count_max)  // 计满拉低
          begin
            start_reg <= 1'b0;
          end
        else
          begin
            start_reg <= start_reg;
          end
      end
  end

assign start = start_reg;

endmodule