/**************************************************************************/
// Function   : 系统控制模块负责与PS进行交互,数据的Debug以及设置
// Version    : v1.0
// Date       : 2026/05/13
// Description: 详细说明
//
// Modify:
// version       date       modify
// --------    -----------  ------------------------------------------------
//  v1.0        2026/05/13  创建文件
/**************************************************************************/
module sys_ctrl #(
  parameter C_S_AXI_DATA_WIDTH = 32, // AXI-Lite 数据位宽
  parameter C_S_AXI_ADDR_WIDTH = 16  // AXI-Lite 地址位宽
) (
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ap_clk CLK" *)
  (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET ap_rstn" *)
  input  wire  ap_clk,

  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ap_rstn RST" *)
  (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
  input   wire                             ap_rstn                       ,
  // ---- AXI-Lite 从机接口 ----//
  // 写地址通道
  input   wire  [C_S_AXI_ADDR_WIDTH-1:0]   s_axi_awaddr                  , // 写地址
  input   wire  [2:0]                      s_axi_awprot                  , // 写地址保护类型
  input   wire                             s_axi_awvalid                 , // 写地址有效
  output  reg                              s_axi_awready                 , // 写地址就绪

  // 写数据通道
  input   wire  [C_S_AXI_DATA_WIDTH-1:0]   s_axi_wdata                   , // 写数据
  input   wire  [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb                   , // 写字节使能
  input   wire                             s_axi_wvalid                  , // 写数据有效
  output  reg                              s_axi_wready                  , // 写数据就绪

  // 写响应通道
  output  wire  [1:0]                      s_axi_bresp                   , // 写响应
  output  reg                              s_axi_bvalid                  , // 写响应有效
  input   wire                             s_axi_bready                  , // 写响应就绪

  // 读地址通道
  input   wire  [C_S_AXI_ADDR_WIDTH-1:0]   s_axi_araddr                  , // 读地址
  input   wire  [2:0]                      s_axi_arprot                  , // 读地址保护类型
  input   wire                             s_axi_arvalid                 , // 读地址有效
  output  reg                              s_axi_arready                 , // 读地址就绪

  // 读数据通道
  output  reg   [C_S_AXI_DATA_WIDTH-1:0]   s_axi_rdata                   , // 读数据
  output  wire  [1:0]                      s_axi_rresp                   , // 读响应
  output  reg                              s_axi_rvalid                  , // 读数据有效
  input   wire                             s_axi_rready                  , // 读数据就绪

  // 输入数据
  input   wire  [31:0]                     data_in_1                     ,
  input   wire  [31:0]                     data_in_2                     ,
  input   wire  [31:0]                     data_in_3                     ,
  input   wire  [31:0]                     data_in_4                     ,
  input   wire  [31:0]                     data_in_5                     ,
  input   wire  [31:0]                     data_in_6                     ,
  input   wire  [31:0]                     data_in_7                     ,
  input   wire  [31:0]                     data_in_8                     ,
  input   wire  [31:0]                     data_in_9                     ,
  input   wire  [31:0]                     data_in_10                    ,
  input   wire  [31:0]                     data_in_11                    ,
  input   wire  [31:0]                     data_in_12                    ,
  input   wire  [31:0]                     data_in_13                    ,
  input   wire  [31:0]                     data_in_14                    ,
  input   wire  [31:0]                     data_in_15                    ,
  input   wire  [31:0]                     data_in_16                    ,

  // 输出数据
  output  reg                              data_gen_start                , // 数据生成启动
  output  reg                              data_sel_start                , // 数据选择启动
  output  reg   [31:0]                     data_out_3                    ,
  output  reg   [31:0]                     data_out_4                    ,
  output  reg   [31:0]                     data_out_5                    ,
  output  reg   [31:0]                     data_out_6                    ,
  output  reg   [31:0]                     data_out_7                    ,
  output  reg   [31:0]                     data_out_8                    ,
  output  reg   [31:0]                     data_out_9                    ,
  output  reg   [31:0]                     data_out_10                   ,
  output  reg   [31:0]                     data_out_11                   ,
  output  reg   [31:0]                     data_out_12                   ,
  output  reg   [31:0]                     data_out_13                   ,
  output  reg   [31:0]                     data_out_14                   ,
  output  reg   [31:0]                     data_out_15                   ,
  output  reg   [31:0]                     data_out_16

);
// ---- 寄存器地址定义 ---- //
localparam  RD_ADDR_DATA_1 = 16'h4000;
localparam  RD_ADDR_DATA_2 = 16'h4004;
localparam  RD_ADDR_DATA_3 = 16'h4008;
localparam  RD_ADDR_DATA_4 = 16'h400C;
localparam  RD_ADDR_DATA_5 = 16'h4010;
localparam  RD_ADDR_DATA_6 = 16'h4014;
localparam  RD_ADDR_DATA_7 = 16'h4018;
localparam  RD_ADDR_DATA_8 = 16'h401C;
localparam  RD_ADDR_DATA_9 = 16'h4020;
localparam  RD_ADDR_DATA_10 = 16'h4024;
localparam  RD_ADDR_DATA_11 = 16'h4028;
localparam  RD_ADDR_DATA_12 = 16'h402C;
localparam  RD_ADDR_DATA_13 = 16'h4030;
localparam  RD_ADDR_DATA_14 = 16'h4034;
localparam  RD_ADDR_DATA_15 = 16'h4038;
localparam  RD_ADDR_DATA_16 = 16'h403C;

localparam  WR_ADDR_DATA_1 = 16'h0000;
localparam  WR_ADDR_DATA_2 = 16'h0004;
localparam  WR_ADDR_DATA_3 = 16'h0008;
localparam  WR_ADDR_DATA_4 = 16'h000C;
localparam  WR_ADDR_DATA_5 = 16'h0010;
localparam  WR_ADDR_DATA_6 = 16'h0014;
localparam  WR_ADDR_DATA_7 = 16'h0018;
localparam  WR_ADDR_DATA_8 = 16'h001C;
localparam  WR_ADDR_DATA_9 = 16'h0020;
localparam  WR_ADDR_DATA_10 = 16'h0024;
localparam  WR_ADDR_DATA_11 = 16'h0028;
localparam  WR_ADDR_DATA_12 = 16'h002C;
localparam  WR_ADDR_DATA_13 = 16'h0030;
localparam  WR_ADDR_DATA_14 = 16'h0034;
localparam  WR_ADDR_DATA_15 = 16'h0038;
localparam  WR_ADDR_DATA_16 = 16'h003C;


// ---- 内部信号定义 ---- //
reg    [C_S_AXI_ADDR_WIDTH-1:0]   awaddr_r        ; // 锁存写地址

reg    [31:0]                     data_in_1_r     ;
reg    [31:0]                     data_in_2_r     ;
reg    [31:0]                     data_in_3_r     ;
reg    [31:0]                     data_in_4_r     ;
reg    [31:0]                     data_in_5_r     ;
reg    [31:0]                     data_in_6_r     ;
reg    [31:0]                     data_in_7_r     ;
reg    [31:0]                     data_in_8_r     ;
reg    [31:0]                     data_in_9_r     ;
reg    [31:0]                     data_in_10_r    ;
reg    [31:0]                     data_in_11_r    ;
reg    [31:0]                     data_in_12_r    ;
reg    [31:0]                     data_in_13_r    ;
reg    [31:0]                     data_in_14_r    ;
reg    [31:0]                     data_in_15_r    ;
reg    [31:0]                     data_in_16_r    ;

// AXI-Lite接口信号处理
assign s_axi_bresp = 2'b00;
assign s_axi_rresp = 2'b00;

// ---- 寄存器写入逻辑 ---- //
always @(posedge ap_clk or negedge ap_rstn)
  begin
    if (ap_rstn == 1'b0)
      begin
        // 复位赋值
        data_in_1_r  <= 32'b0;
        data_in_2_r  <= 32'b0;
        data_in_3_r  <= 32'b0;
        data_in_4_r  <= 32'b0;
        data_in_5_r  <= 32'b0;
        data_in_6_r  <= 32'b0;
        data_in_7_r  <= 32'b0;
        data_in_8_r  <= 32'b0;
        data_in_9_r  <= 32'b0;
        data_in_10_r <= 32'b0;
        data_in_11_r <= 32'b0;
        data_in_12_r <= 32'b0;
        data_in_13_r <= 32'b0;
        data_in_14_r <= 32'b0;
        data_in_15_r <= 32'b0;
        data_in_16_r <= 32'b0;
      end
    else
      begin
        data_in_1_r  <= data_in_1;
        data_in_2_r  <= data_in_2;
        data_in_3_r  <= data_in_3;
        data_in_4_r  <= data_in_4;
        data_in_5_r  <= data_in_5;
        data_in_6_r  <= data_in_6;
        data_in_7_r  <= data_in_7;
        data_in_8_r  <= data_in_8;
        data_in_9_r  <= data_in_9;
        data_in_10_r <= data_in_10;
        data_in_11_r <= data_in_11;
        data_in_12_r <= data_in_12;
        data_in_13_r <= data_in_13;
        data_in_14_r <= data_in_14;
        data_in_15_r <= data_in_15;
        data_in_16_r <= data_in_16;
      end
  end

// ---- AXI 读取寄存器 ---- //
always @(posedge ap_clk or negedge ap_rstn)
  begin
    if (ap_rstn == 1'b0)
      begin
        s_axi_arready <= 1'b0;
        s_axi_rvalid  <= 1'b0;
        s_axi_rdata   <= 32'b0;
      end
    else
      begin
        if (s_axi_arvalid && !s_axi_arready)
          begin
            s_axi_arready <= 1'b1; // 接受读地址
            case (s_axi_araddr)
              RD_ADDR_DATA_1 : s_axi_rdata <= data_in_1_r;
              RD_ADDR_DATA_2 : s_axi_rdata <= data_in_2_r;
              RD_ADDR_DATA_3 : s_axi_rdata <= data_in_3_r;
              RD_ADDR_DATA_4 : s_axi_rdata <= data_in_4_r;
              RD_ADDR_DATA_5 : s_axi_rdata <= data_in_5_r;
              RD_ADDR_DATA_6 : s_axi_rdata <= data_in_6_r;
              RD_ADDR_DATA_7 : s_axi_rdata <= data_in_7_r;
              RD_ADDR_DATA_8 : s_axi_rdata <= data_in_8_r;
              RD_ADDR_DATA_9 : s_axi_rdata <= data_in_9_r;
              RD_ADDR_DATA_10: s_axi_rdata <= data_in_10_r;
              RD_ADDR_DATA_11: s_axi_rdata <= data_in_11_r;
              RD_ADDR_DATA_12: s_axi_rdata <= data_in_12_r;
              RD_ADDR_DATA_13: s_axi_rdata <= data_in_13_r;
              RD_ADDR_DATA_14: s_axi_rdata <= data_in_14_r;
              RD_ADDR_DATA_15: s_axi_rdata <= data_in_15_r;
              RD_ADDR_DATA_16: s_axi_rdata <= data_in_16_r;
              default:         s_axi_rdata <= 32'b0; // 默认返回0
            endcase
            s_axi_rvalid <= 1'b1; // 数据有效
          end
        else if (s_axi_rvalid && s_axi_rready)
          begin
            s_axi_arready <= 1'b0; // 完成一次读操作，等待下一次读地址
            s_axi_rvalid  <= 1'b0; // 数据已被接受，等待下一次读请求
          end
      end
  end

// ---- AXI 写入寄存器 ---- //
always @(posedge ap_clk or negedge ap_rstn)
  begin
    if (ap_rstn == 1'b0)
      begin
        s_axi_awready <= 1'b0;
        s_axi_wready  <= 1'b0;
        s_axi_bvalid  <= 1'b0;
        data_gen_start <= 1'b0;
        data_sel_start <= 1'b0;
        data_out_3    <= 32'b0;
        data_out_4    <= 32'b0;
        data_out_5    <= 32'b0;
        data_out_6    <= 32'b0;
        data_out_7    <= 32'b0;
        data_out_8    <= 32'b0;
        data_out_9    <= 32'b0;
        data_out_10   <= 32'b0;
        data_out_11   <= 32'b0;
        data_out_12   <= 32'b0;
        data_out_13   <= 32'b0;
        data_out_14   <= 32'b0;
        data_out_15   <= 32'b0;
        data_out_16   <= 32'b0;
      end
    else
      begin
        if (s_axi_awvalid && !s_axi_awready)
          begin
            s_axi_awready <= 1'b1;         // 接受写地址
            awaddr_r      <= s_axi_awaddr; // 锁存写地址，防止 wvalid 延迟到达时地址已撤销
          end
        else if (s_axi_awready && s_axi_wvalid && !s_axi_wready)
          begin
            s_axi_awready <= 1'b0; // awready 单拍脉冲，避免 PS 误认为可接受新地址
            s_axi_wready  <= 1'b1; // 接受写数据
            case (awaddr_r)        // 使用锁存的地址
              WR_ADDR_DATA_1 : data_gen_start <= s_axi_wdata[0];
              WR_ADDR_DATA_2 : data_sel_start <= s_axi_wdata[0];
              WR_ADDR_DATA_3 : data_out_3   <= s_axi_wdata;
              WR_ADDR_DATA_4 : data_out_4   <= s_axi_wdata;
              WR_ADDR_DATA_5 : data_out_5   <= s_axi_wdata;
              WR_ADDR_DATA_6 : data_out_6   <= s_axi_wdata;
              WR_ADDR_DATA_7 : data_out_7   <= s_axi_wdata;
              WR_ADDR_DATA_8 : data_out_8   <= s_axi_wdata;
              WR_ADDR_DATA_9 : data_out_9   <= s_axi_wdata;
              WR_ADDR_DATA_10: data_out_10  <= s_axi_wdata;
              WR_ADDR_DATA_11: data_out_11  <= s_axi_wdata;
              WR_ADDR_DATA_12: data_out_12  <= s_axi_wdata;
              WR_ADDR_DATA_13: data_out_13  <= s_axi_wdata;
              WR_ADDR_DATA_14: data_out_14  <= s_axi_wdata;
              WR_ADDR_DATA_15: data_out_15  <= s_axi_wdata;
              WR_ADDR_DATA_16: data_out_16  <= s_axi_wdata;
              default:         ; // 默认不做任何操作
            endcase
            s_axi_bvalid <= 1'b1; // 写响应有效
          end
        else if (s_axi_bvalid && s_axi_bready)
          begin
            s_axi_wready  <= 1'b0; // 完成一次写操作，等待下一次写数据
            s_axi_bvalid  <= 1'b0; // 写响应已被接受，等待下一次写请求
          end
      end
  end

endmodule