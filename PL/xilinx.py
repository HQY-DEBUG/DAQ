#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
xilinx.py  --  Vivado / Vitis HLS 工程自动化工具
版本    : v1.3
日期    : 2026/05/27

修改记录:
    v1.3  2026/05/27  新增 -clear 命令，删除当前目录下 .str/.log/.jou 文件
    v1.2  2026/05/03  新增 -copy -b 组合命令，从 impl_1 拷贝产物并导出 XSA
    v1.1  2026/04/27  新增 -copy 命令，拷贝工程 IP 目录到 source/ip
    v1.0  —           创建文件，集成 Vivado 启动、TCL 执行、bitstream 生成、IP 导出功能

------------------------------------------------------------------------
使用方法
------------------------------------------------------------------------

【拷贝编译产物（不重新编译）】
    py xilinx.py -copy -b                # 从 impl_1 拷贝 bit/ltx，并导出 XSA 到 bit 目录
    py xilinx.py -copy -b -o ./output    # 指定输出目录
    py xilinx.py -copy -b -p ./proj/x.xpr  # 指定工程文件  

【启动 Vivado GUI】
    py xilinx.py                          # 后台启动 Vivado GUI（默认）
    py xilinx.py -fg                      # 前台启动 Vivado GUI
    py xilinx.py project.xpr             # 后台打开指定工程
    py xilinx.py project.xpr -fg         # 前台打开指定工程

【执行 TCL 脚本】
    py xilinx.py -s script.tcl            # 后台批处理执行 TCL 脚本（默认）
    py xilinx.py -s script.tcl -fg        # 前台 GUI 模式执行 TCL 脚本

【生成 bitstream】
    py xilinx.py -b                       # 生成 bitstream（使用默认配置）
    py xilinx.py -b -o ./output           # 指定 bitstream 输出目录
    py xilinx.py -b -j 32                 # 指定编译 CPU 线程数
    py xilinx.py -b -p ./proj/x.xpr       # 指定工程文件路径
    py xilinx.py -b -o ./bit -j 24 -p ./proj/x.xpr  # 完整参数示例

【组合：先执行脚本再生成 bitstream】
    py xilinx.py -s axidma.tcl -b        # 执行脚本后生成 bitstream
    py xilinx.py -s axidma.tcl -b -o ./bit -j 24

【IP 管理】
    py xilinx.py -ip                      # 扫描 source/ 并导出所有 IP
    py xilinx.py -ip -b                   # 先导出 IP 再生成 bitstream
    py xilinx.py -copy                    # 拷贝 project/.../ip 到 source/ip

【Zynq-7020 程序烧写】
    py xilinx.py -p                       # 烧写 bit/ 文件夹下的 BIN 文件到 QSPI Flash
    py xilinx.py -p -c                    # 根据 bit/ 下的 fsbl、bit、app.elf 创建 BIN 后烧写
    py xilinx.py -p -c -no                # 只创建 BOOT.BIN，不烧写

【清理日志文件】
    py xilinx.py -clear                   # 删除当前目录下所有 .str/.log/.jou 文件

------------------------------------------------------------------------
参数说明
------------------------------------------------------------------------
  （无参数）          后台启动 Vivado GUI
  -fg                前台运行（默认为后台）
  -bg                后台运行（默认，可省略）
  -s  <file.tcl>     执行指定 TCL 脚本
  -b  / -bit         生成 bitstream
  -o  <dir>          bitstream 输出目录（默认: ./bit）
  -p  <file.xpr>     Vivado 工程文件路径（默认: ./project/project.xpr）
  -j  <num>          编译 CPU 线程数（默认: 12）
  -ip                扫描并导出 source/ 下所有 IP
  -copy              将工程 IP（project/.srcs/sources_1/ip）拷贝到 source/ip
  -copy -b           从 project/project.runs/impl_1 拷贝 bit/ltx，并调用 Vivado 导出 XSA
  -p                 烧写 bit/ 下的 BIN 文件；与 -b 连用时仍表示工程文件路径
  -c                 与 -p 连用，先创建 BIN 文件再烧写
  -no                与 -p -c 连用，只创建 BIN 文件，不烧写
    -clear             删除当前目录下所有 .str/.log/.jou 文件

------------------------------------------------------------------------
配置项（脚本顶部常量，按需修改）
------------------------------------------------------------------------
  FPGA_PART           FPGA 芯片型号
  VIVADO_PATH         Vivado bin 目录
  VIVADO_HLS_PATH     Vitis HLS bin 目录
  DEFAULT_PROJECT_PATH  默认工程文件路径
  DEFAULT_CPU_JOBS    默认编译线程数
  DEFAULT_BITSTREAM_PATH  默认 bitstream 输出目录
  ip_export_path      IP 导出目标目录
  PROJECT_IP_SRC      -copy 源 IP 目录
  PROJECT_IP_DST      -copy 目标 IP 目录
"""

import subprocess
import sys
import os
import argparse
import tempfile
import time
import re
import shutil


def configure_console_encoding():
    """尽量避免 Windows 终端和子进程输出中文时出现乱码。"""
    if os.name == 'nt':
        try:
            os.system('chcp 65001 > nul')
        except Exception:
            pass

    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            try:
                stream.reconfigure(encoding='utf-8')
            except Exception:
                pass


#======================== 配置项 ========================#
# 指定FPGA型号
FPGA_PART = 'xc7z020clg400-2'  # adc_board

# 指定Vivado版本路径（bin目录）
VIVADO_PATH = r"D:\tools\Xilinx\Vivado\2022.1\bin"

# 指定Vitis HLS版本路径（bin目录）
VIVADO_HLS_PATH = r"D:\tools\Xilinx\Vitis_HLS\2022.1\bin"

# 指定Vitis版本路径（安装根目录）
VITIS_PATH = r"D:\tools\Xilinx\Vitis\2022.1"

# 工程文件路径
DEFAULT_PROJECT_PATH = r".\project\project.xpr"

# 设置使用CPU线程数（默认）
DEFAULT_CPU_JOBS = 12

# IP 导出路径
ip_export_path = r".\my_ip"

# bitstream 文件默认路径
DEFAULT_BITSTREAM_PATH = r".\bit"

# Zynq-7020 默认烧录输出文件名
DEFAULT_BOOT_BIN_NAME = "BOOT.BIN"

# Zynq-7020 默认 Flash 类型
DEFAULT_FLASH_TYPE = "qspi_single"
#========================================================#


# v1.1 2026/04/27 新增：工程 IP 拷贝功能
# 工程 IP 源目录（相对于脚本所在目录）
PROJECT_IP_SRC = r".\project\project.srcs\sources_1\ip"

# IP 拷贝目标目录
PROJECT_IP_DST = r".\source\ip"


def copy_ip_from_project():
    """
    将工程 IP 目录拷贝到 source/ip。

    源路径: project\\project.srcs\\sources_1\\ip
    目标路径: source\\ip

    若目标已存在则先删除再拷贝。
    """
    src = os.path.abspath(PROJECT_IP_SRC)
    dst = os.path.abspath(PROJECT_IP_DST)

    if not os.path.exists(src):
        print(f"错误: 源目录不存在: {src}")
        sys.exit(1)

    if os.path.exists(dst):
        print(f"目标目录已存在，删除: {dst}")
        shutil.rmtree(dst)

    shutil.copytree(src, dst)
    print(f"拷贝完成: {src} -> {dst}")


# v1.2 2026/05/03 新增：从 impl_1 拷贝编译产物并导出 XSA
def copy_build_artifacts(output_dir=None, project_path=None):
    """
    @brief  从 impl_1 拷贝已编译的 bit/ltx 文件，并调用 Vivado 导出 XSA，无需重新编译。
    @param  output_dir    输出目录，默认为 DEFAULT_BITSTREAM_PATH
    @param  project_path  Vivado 工程文件路径，默认为 DEFAULT_PROJECT_PATH
    @note   命名规则与 -b 一致：文件名取工程路径上两级目录名（overlay_name）
    """
    if project_path is None:
        project_path = DEFAULT_PROJECT_PATH
    if output_dir is None:
        output_dir = DEFAULT_BITSTREAM_PATH

    project_path = os.path.abspath(project_path)
    output_dir   = os.path.abspath(output_dir)

    if not os.path.exists(project_path):
        print(f"ERROR: project file not found: {project_path}")
        sys.exit(1)

    # 与 -b 相同的命名规则
    overlay_name = os.path.basename(os.path.dirname(os.path.dirname(project_path)))

    # impl_1 目录
    impl1_dir = os.path.join(os.path.dirname(project_path), "project.runs", "impl_1")
    if not os.path.exists(impl1_dir):
        print(f"ERROR: impl_1 directory not found: {impl1_dir}")
        sys.exit(1)

    os.makedirs(output_dir, exist_ok=True)

    # ---- 查找并拷贝 .bit 文件 ----//
    bit_files = [f for f in os.listdir(impl1_dir) if f.endswith('.bit')]
    if not bit_files:
        print(f"ERROR: no .bit file found under impl_1: {impl1_dir}")
        sys.exit(1)

    src_bit = os.path.join(impl1_dir, bit_files[0])
    dst_bit = os.path.join(output_dir, f"{overlay_name}.bit")
    shutil.copy2(src_bit, dst_bit)
    print(f"Copy bit: {src_bit}")
    print(f"      -> {dst_bit}")

    # ---- 查找并拷贝 .ltx 文件（可选，设计无 ILA 时不存在）----//
    ltx_files = [f for f in os.listdir(impl1_dir) if f.endswith('.ltx')]
    if ltx_files:
        src_ltx = os.path.join(impl1_dir, ltx_files[0])
        dst_ltx = os.path.join(output_dir, f"{overlay_name}.ltx")
        shutil.copy2(src_ltx, dst_ltx)
        print(f"Copy ltx: {src_ltx}")
        print(f"      -> {dst_ltx}")
    else:
        print("No .ltx file found; skipped debug probe copy")

    # ---- 调用 Vivado TCL 导出 XSA ----//
    vivado_bat = os.path.join(VIVADO_PATH, 'vivado.bat')
    if not os.path.exists(vivado_bat):
        print(f"ERROR: Vivado path not found: {vivado_bat}")
        sys.exit(1)

    xsa_path     = os.path.join(output_dir, f"{overlay_name}.xsa").replace('\\', '/')
    project_tcl  = project_path.replace('\\', '/')

    tcl_script = f"""
open_project "{project_tcl}"
puts "Export XSA: {xsa_path}"
write_hw_platform -fixed -include_bit -force -file "{xsa_path}"
close_project
puts "XSA export done"
exit 0
"""

    with tempfile.NamedTemporaryFile(mode='w', suffix='.tcl', delete=False, encoding='utf-8') as f:
        tcl_file = f.name
        f.write(tcl_script)

    try:
        cmd = [vivado_bat, '-mode', 'batch', '-source', tcl_file]
        print("Run Vivado to export XSA...")
        result = subprocess.run(cmd, shell=True)
        if result.returncode != 0:
            print(f"ERROR: XSA export failed, return code: {result.returncode}")
            sys.exit(1)
    except Exception as e:
        print(f"ERROR: XSA export failed: {e}")
        sys.exit(1)
    finally:
        if os.path.exists(tcl_file):
            os.remove(tcl_file)

    # ---- 汇总 ----//
    print()
    print("=" * 60)
    print("Copied Artifact Summary")
    print("=" * 60)
    print(f"Output directory: {output_dir}")
    print()
    for fname, desc in [(f"{overlay_name}.bit", "Bitstream"),
                        (f"{overlay_name}.ltx", "ILA debug probes"),
                        (f"{overlay_name}.xsa", "Hardware platform")]:
        fpath = os.path.join(output_dir, fname)
        if os.path.exists(fpath):
            size_mb = os.path.getsize(fpath) / (1024 * 1024)
            print(f"  [OK]   {fname:30s} ({desc}, {size_mb:.2f} MB)")
        else:
            print(f"  [MISS] {fname:30s} ({desc}) - not generated")
    print()
    print("[OK] Artifact copy completed!")
    print("=" * 60)


# ====================== IP 导出功能 ====================== #

def find_ip_files(source_root):
    """扫描 source 目录，查找包含 creat_project_*.tcl 的 IP 工程"""
    ip_paths = []
    for root, dirs, files in os.walk(source_root, topdown=True):
        has_tcl = (
            'creat_project_h.tcl' in files
            or 'creat_project_x.tcl' in files
        )
        if has_tcl:
            rel_path = os.path.relpath(root, '.')
            ip_paths.append(rel_path.replace('\\', '/'))
            dirs[:] = []
    return sorted(set(ip_paths))


def replace_tcl(source_path, fpga_part):
    """生成运行用 TCL 内容，不修改源 TCL 模板"""
    possible_files = ['creat_project_h.tcl', 'creat_project_x.tcl']
    tcl_file_path = None
    for filename in possible_files:
        candidate_path = os.path.join(source_path, filename)
        if os.path.exists(candidate_path):
            tcl_file_path = candidate_path
            break
    if tcl_file_path is None:
        print(f"Error: Neither 'creat_project_h.tcl' nor 'creat_project_x.tcl' found in {source_path}.")
        return None
    try:
        with open(tcl_file_path, 'r', encoding='utf-8') as tcl_file:
            tcl_content = tcl_file.read()

        original_content = tcl_content

        # 替换芯片型号
        current_chip_type = re.search(r'set\s+chip_type\s+(\S+)', tcl_content)
        if current_chip_type:
            current_chip_type = current_chip_type.group(1)
            if current_chip_type != fpga_part:
                tcl_content = re.sub(r'set\s+chip_type\s+(\S+)', f'set chip_type {fpga_part}', tcl_content)

        # 计算 IP 导出的绝对路径，转换为 TCL 兼容的正斜杠格式
        abs_ip_path = os.path.abspath(ip_export_path).replace('\\', '/')

        # 替换 IP 导出路径为绝对路径，支持 $ip_export_path 变量和硬编码相对路径两种格式
        current_ip_path = re.search(r'set\s+ip_export_path\s+(.+)', tcl_content)
        if current_ip_path:
            current_ip_path_value = current_ip_path.group(1).strip().strip('"')
            if current_ip_path_value != abs_ip_path:
                tcl_content = re.sub(r'(set\s+ip_export_path\s+).+', rf'\1{abs_ip_path}', tcl_content)
        else:
            tcl_content = re.sub(r'(?<!\$)(\.\./)+my_ip', abs_ip_path, tcl_content)

        # 注释掉 TCL 中删除 IP 目录的命令，由 Python 统一删除旧导出目录
        tcl_content = re.sub(
            r'(?<!#\s)file\s+delete\s+-force\s+.+?/\$project_name\b',
            r'# \g<0>  # Managed by Python script',
            tcl_content
        )
        tcl_content = re.sub(r'(#\s*)+#\s*file\s+delete', '# file delete', tcl_content)

        # 替换 file mkdir 为兼容性更好的版本
        tcl_content = re.sub(
            r'(?<!catch \{)file\s+mkdir\s+(-p\s+)?(.+?/\$project_name)',
            r'catch {file mkdir \2}',
            tcl_content
        )
        tcl_content = re.sub(r'catch\s*\{catch\s*\{', 'catch {', tcl_content)

        if tcl_content != original_content:
            print(f"  使用临时 TCL 覆盖配置: {os.path.join(source_path, 'project', os.path.basename(tcl_file_path))}")
        return tcl_content
    except Exception as e:
        print(f"Error processing {tcl_file_path}: {e}")
        return None

def export_ip(source_path):
    """导出IP（直接调用 Vitis HLS / Vivado，无需 start.bat）"""
    try:
        hls_tcl = os.path.join(source_path, 'creat_project_h.tcl')
        rtl_tcl = os.path.join(source_path, 'creat_project_x.tcl')
        is_hls = os.path.exists(hls_tcl)
        is_rtl = os.path.exists(rtl_tcl)
        if is_hls and is_rtl:
            print(f"错误: {source_path} 同时存在 creat_project_h.tcl 和 creat_project_x.tcl")
            return
        if is_hls:
            tcl_filename = 'creat_project_h.tcl'
            tool_path = VIVADO_HLS_PATH
            tool_name = 'vitis_hls'
            tool_args = ['-f', tcl_filename]
        elif is_rtl:
            tcl_filename = 'creat_project_x.tcl'
            tool_path = VIVADO_PATH
            tool_name = 'vivado'
            tool_args = ['-mode', 'batch', '-source', tcl_filename]
        else:
            print(f"错误: {source_path} 未找到 creat_project_h.tcl 或 creat_project_x.tcl")
            return

        # 创建 project 目录并复制 TCL 文件
        project_dir = os.path.join(source_path, 'project')
        os.makedirs(project_dir, exist_ok=True)
        src_tcl = os.path.join(source_path, tcl_filename)
        dst_tcl = os.path.join(project_dir, tcl_filename)
        tcl_content = replace_tcl(source_path, FPGA_PART)
        if tcl_content is None:
            return
        with open(dst_tcl, 'w', encoding='utf-8') as tcl_file:
            tcl_file.write(tcl_content)

        # 构建工具路径
        if os.name == 'nt':
            tool_exe = os.path.join(tool_path, tool_name + '.bat')
        else:
            tool_exe = os.path.join(tool_path, tool_name)
        if not os.path.exists(tool_exe):
            print(f"错误: 工具不存在: {tool_exe}")
            return

        # 启动构建进程
        cmd = [tool_exe] + tool_args
        ip_name = os.path.basename(source_path)
        print(f"导出 IP: {ip_name}")
        print(f"  工具: {tool_name}")
        print(f"  命令: {' '.join(cmd)}")
        print(f"  工作目录: {os.path.abspath(project_dir)}")

        env = os.environ.copy()
        env['PATH'] = tool_path + os.pathsep + env.get('PATH', '')
        subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=project_dir, env=env)

    except Exception as e:
        print(f"导出 IP 失败 ({source_path}): {e}")


def export_done(source_path):
    """等待IP导出完成"""
    ip_name = os.path.basename(source_path)
    component_file_path = os.path.join(ip_export_path, ip_name, 'component.xml')
    while not os.path.exists(component_file_path):
        print(f"Waiting for {ip_name} to export...")
        time.sleep(15)
    print(f"Export completed for {ip_name}")


def get_mod_time(directory):
    """获取文件夹中最新的文件修改时间"""
    try:
        files = []
        for root, dirs, file_names in os.walk(directory):
            for file_name in file_names:
                files.append(os.path.join(root, file_name))
        if not files:
            return 0
        latest_file = max(files, key=os.path.getmtime)
        return os.path.getmtime(latest_file)
    except OSError as e:
        print(f"Error retrieving modification time for directory {directory}: {e}")
        return 0


def ip_update(source_path):
    """检查IP是否需要更新(1代表需要更新,0代表无需更新)"""
    ip_name = os.path.basename(source_path)
    component_file_path = os.path.join(ip_export_path, ip_name, 'component.xml')
    if not os.path.exists(component_file_path):
        return 1
    else:
        source_dir = source_path
        ip_dir = os.path.join(ip_export_path, ip_name)
        source_time = get_mod_time(source_dir)
        ip_time = get_mod_time(ip_dir)
        if source_time > ip_time:
            return 1
        else:
            dependency_file = os.path.join(source_path, 'dependency.txt')
            dependencies = []
            flag = 0
            if os.path.exists(dependency_file):
                with open(dependency_file, 'r') as dep_file:
                    dependencies = [line.strip() for line in dep_file.readlines()]
                for dep in dependencies:
                    dep_path = os.path.join(ip_export_path, dep)
                    dep_time = get_mod_time(dep_path)
                    if dep_time > ip_time:
                        flag = 1
            if flag:
                return 1
            else:
                return 0


def run_ip_export():
    """扫描并导出所有IP"""
    ip_files = find_ip_files('source')
    if not ip_files:
        print("No IP paths found under source. Check for start.bat or creat_project_*.tcl in leaf dirs.")
        return
    print(f"Found IP paths: {ip_files}")
    for source_path in ip_files:
        # 检测是否需要更新
        need_update = ip_update(source_path)
        print(f"{source_path}: need_update={need_update}")
        
        if need_update:
            # 删除旧的IP导出目录
            ip_name = os.path.basename(source_path)
            export_path = os.path.join(ip_export_path, ip_name)
            if os.path.exists(export_path):
                print(f"Removing old IP export: {export_path}")
                shutil.rmtree(export_path)
            
            export_ip(source_path)
            export_done(source_path)
        # else:
        #     print(f"{source_path}: Skipped (up-to-date)")


# ====================== Vivado 工具功能 ====================== #

def _get_vivado_exe():
    """Return vivado.exe path if available, else None."""
    candidates = [
        os.path.join(VIVADO_PATH, 'unwrapped', 'win64.o', 'vivado.exe'),
        os.path.join(VIVADO_PATH, 'vivado.exe')
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return None


def _run_detached(cmd):
    """Run a command detached so the terminal can continue."""
    if os.name == 'nt':
        creationflags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startupinfo.wShowWindow = subprocess.SW_HIDE
        subprocess.Popen(
            cmd,
            shell=False,
            creationflags=creationflags,
            startupinfo=startupinfo,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
    else:
        subprocess.Popen(cmd, shell=False, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _run_hidden_cmd(cmd):
    """Run a hidden cmd.exe process without showing a console window."""
    if os.name != 'nt':
        _run_detached(cmd)
        return
    creationflags = subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP
    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = subprocess.SW_HIDE
    subprocess.Popen(
        cmd,
        shell=False,
        creationflags=creationflags,
        startupinfo=startupinfo,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )


# v1.2 2026/05/03 新增：查找 Vitis 安装目录，用于 bootgen 和 program_flash
def _get_vitis_root():
    """
    @brief  获取 Vitis 安装根目录。
    @return Vitis 安装根目录
    @note   优先使用脚本配置，其次使用 XILINX_VITIS 环境变量。
    """
    if VITIS_PATH and os.path.exists(VITIS_PATH):
        return os.path.abspath(VITIS_PATH)

    xilinx_vitis = os.environ.get("XILINX_VITIS")
    if xilinx_vitis and os.path.exists(xilinx_vitis):
        return os.path.abspath(xilinx_vitis)

    print(f"错误: Vitis 路径不存在: {VITIS_PATH}")
    print("请修改脚本顶部 VITIS_PATH，或先设置 XILINX_VITIS 环境变量")
    sys.exit(1)


# v1.2 2026/05/03 新增：获取 Vitis 环境脚本路径
def _get_vitis_settings_bat():
    """
    @brief  获取 settings64.bat 路径。
    @return settings64.bat 绝对路径
    """
    settings_bat = os.path.join(_get_vitis_root(), "settings64.bat")
    if not os.path.exists(settings_bat):
        print(f"错误: Vitis 环境脚本不存在: {settings_bat}")
        sys.exit(1)

    return settings_bat


# v1.2 2026/05/03 新增：执行 Vitis 命令
def _run_vitis_command(command_args):
    """
    @brief  调用 Vitis 命令行工具。
    @param  command_args  命令参数列表
    @return 命令返回码
    """
    settings_bat = _get_vitis_settings_bat()
    command = ['cmd', '/c', 'call', settings_bat, '&&'] + command_args
    print(f"执行命令: {' '.join(command_args)}")
    result = subprocess.run(command, shell=False)
    return result.returncode


# v1.2 2026/05/03 新增：查找唯一匹配文件
def _find_single_file(search_dir, suffix, keyword=None, exclude_keyword=None):
    """
    @brief  在目录中查找唯一匹配文件。
    @param  search_dir        搜索目录
    @param  suffix            文件后缀
    @param  keyword           文件名必须包含的关键字
    @param  exclude_keyword   文件名不能包含的关键字
    @return 匹配文件绝对路径
    """
    if not os.path.exists(search_dir):
        print(f"错误: 目录不存在: {search_dir}")
        sys.exit(1)

    suffix = suffix.lower()
    matched_files = []
    for file_name in os.listdir(search_dir):
        lower_name = file_name.lower()
        if not lower_name.endswith(suffix):
            continue
        if keyword and keyword.lower() not in lower_name:
            continue
        if exclude_keyword and exclude_keyword.lower() in lower_name:
            continue
        matched_files.append(os.path.join(search_dir, file_name))

    if len(matched_files) == 1:
        return os.path.abspath(matched_files[0])

    if len(matched_files) == 0:
        print(f"错误: {search_dir} 下未找到 {suffix} 文件")
    else:
        print(f"错误: {search_dir} 下找到多个 {suffix} 文件，无法自动选择:")
        for matched_file in matched_files:
            print(f"  {matched_file}")

    sys.exit(1)


# v1.2 2026/05/03 新增：创建 Zynq 启动 BIN 文件
def create_zynq_boot_bin(bit_dir=None):
    """
    @brief  根据 bit 目录下的 fsbl.elf、bitstream 和应用 ELF 创建 BOOT.BIN。
    @param  bit_dir  bit 文件目录，默认为 DEFAULT_BITSTREAM_PATH
    @return BOOT.BIN 绝对路径
    """
    if bit_dir is None:
        bit_dir = DEFAULT_BITSTREAM_PATH

    bit_dir = os.path.abspath(bit_dir)
    fsbl_file = _find_single_file(bit_dir, ".elf", keyword="fsbl")
    bit_file = _find_single_file(bit_dir, ".bit")
    app_file = _find_single_file(bit_dir, ".elf", exclude_keyword="fsbl")
    boot_bin = os.path.join(bit_dir, DEFAULT_BOOT_BIN_NAME)

    bif_content = "\n".join([
        "the_ROM_image:",
        "{",
        f"  [bootloader] {fsbl_file.replace(os.sep, '/')}",
        f"  {bit_file.replace(os.sep, '/')}",
        f"  {app_file.replace(os.sep, '/')}",
        "}",
        ""
    ])

    with tempfile.NamedTemporaryFile(mode='w', suffix='.bif', delete=False, encoding='utf-8') as f:
        bif_file = f.name
        f.write(bif_content)

    try:
        cmd = ['bootgen', '-arch', 'zynq', '-image', bif_file, '-o', boot_bin, '-w']
        print(f"FSBL : {fsbl_file}")
        print(f"BIT  : {bit_file}")
        print(f"APP  : {app_file}")
        print(f"BIN  : {boot_bin}")
        ret = _run_vitis_command(cmd)
        if ret != 0:
            print(f"错误: bootgen 执行失败，返回码: {ret}")
            sys.exit(1)
    finally:
        if os.path.exists(bif_file):
            os.remove(bif_file)

    if not os.path.exists(boot_bin):
        print(f"错误: BOOT.BIN 生成失败: {boot_bin}")
        sys.exit(1)

    print(f"BOOT.BIN 创建完成: {boot_bin}")
    return boot_bin


# v1.2 2026/05/03 新增：烧写 Zynq-7020 QSPI Flash
def program_zynq_flash(create_bin=False, bit_dir=None):
    """
    @brief  烧写 bit 目录下的 BIN 文件到 Zynq-7020 QSPI Flash。
    @param  create_bin  是否先创建 BOOT.BIN
    @param  bit_dir     bit 文件目录，默认为 DEFAULT_BITSTREAM_PATH
    """
    if bit_dir is None:
        bit_dir = DEFAULT_BITSTREAM_PATH

    bit_dir = os.path.abspath(bit_dir)
    if create_bin:
        boot_bin = create_zynq_boot_bin(bit_dir)
    else:
        boot_bin = _find_single_file(bit_dir, ".bin")

    fsbl_file = _find_single_file(bit_dir, ".elf", keyword="fsbl")
    cmd = [
        'program_flash',
        '-f', boot_bin,
        '-fsbl', fsbl_file,
        '-flash_type', DEFAULT_FLASH_TYPE,
        '-offset', '0x0',
        '-blank_check',
        '-verify'
    ]

    print(f"烧写文件   : {boot_bin}")
    print(f"FSBL       : {fsbl_file}")
    print(f"Flash 类型 : {DEFAULT_FLASH_TYPE}")
    ret = _run_vitis_command(cmd)
    if ret != 0:
        print(f"错误: program_flash 执行失败，返回码: {ret}")
        sys.exit(1)

    print("Zynq-7020 QSPI Flash 烧写完成")


# v1.3 2026/05/27 新增：清理当前目录下 Vivado 日志/会话文件
def clear_vivado_temp_files(target_dir='.'):
    """
    删除目标目录下所有 .str/.log/.jou 文件（不递归子目录）。

    Args:
        target_dir: 目标目录，默认为当前目录
    """
    target_dir = os.path.abspath(target_dir)
    if not os.path.exists(target_dir):
        print(f"错误: 目录不存在: {target_dir}")
        sys.exit(1)

    suffixes = ('.str', '.log', '.jou')
    deleted_files = []
    failed_files = []

    for file_name in os.listdir(target_dir):
        file_path = os.path.join(target_dir, file_name)
        if not os.path.isfile(file_path):
            continue
        if not file_name.lower().endswith(suffixes):
            continue
        try:
            os.remove(file_path)
            deleted_files.append(file_path)
        except OSError as exc:
            failed_files.append((file_path, str(exc)))

    print(f"清理目录: {target_dir}")
    print(f"已删除文件数量: {len(deleted_files)}")
    for deleted_file in deleted_files:
        print(f"  删除: {deleted_file}")

    if failed_files:
        print(f"删除失败数量: {len(failed_files)}")
        for failed_file, reason in failed_files:
            print(f"  失败: {failed_file} ({reason})")
        sys.exit(1)

    print("清理完成")


def build_bitstream(output_dir=None, project_path=None, cpu_jobs=None):
    """
    打开 Vivado 工程并生成 bitstream
    
    Args:
        output_dir: bitstream 输出目录，默认为 DEFAULT_BITSTREAM_PATH
        project_path: Vivado 工程文件路径，默认为 DEFAULT_PROJECT_PATH
        cpu_jobs: CPU 线程数，默认为 DEFAULT_CPU_JOBS
    """
    vivado_bat = os.path.join(VIVADO_PATH, 'vivado.bat')
    if not os.path.exists(vivado_bat):
        print(f"错误: Vivado 路径不存在: {vivado_bat}")
        sys.exit(1)
    
    # 设置默认值
    if project_path is None:
        project_path = DEFAULT_PROJECT_PATH
    if cpu_jobs is None:
        cpu_jobs = DEFAULT_CPU_JOBS
    if output_dir is None:
        output_dir = DEFAULT_BITSTREAM_PATH
    
    if not os.path.exists(project_path):
        print(f"错误: 工程文件不存在: {project_path}")
        sys.exit(1)
    
    # 转换为绝对路径
    output_dir = os.path.abspath(output_dir)
    project_path = os.path.abspath(project_path)
    
    # 将 Windows 路径转换为正斜杠格式（TCL 兼容）
    output_dir = output_dir.replace('\\', '/')
    project_path = project_path.replace('\\', '/')
    
    print(f"工程路径: {project_path}")
    print(f"输出目录: {output_dir}")
    print(f"CPU 线程数: {cpu_jobs}")
    print(f"开始生成 bitstream...")
    
    # 创建临时 TCL 脚本
    tcl_script = f"""
# Open project
open_project "{project_path}"

# Get design name
set design_name [get_property TOP [get_filesets sources_1]]
set overlay_name [file tail [file dirname [file dirname "{project_path}"]]]

puts "Design Name: $design_name"
puts "Overlay Name: $overlay_name"

# Set platform properties
set_property platform.default_output_type "sd_card" [current_project]
set_property platform.design_intent.embedded "true" [current_project]
set_property platform.design_intent.server_managed "false" [current_project]
set_property platform.design_intent.external_host "false" [current_project]
set_property platform.design_intent.datacenter "false" [current_project]

# Update and upgrade IP cores
puts "Checking IP cores..."
set ip_locked [get_ips -filter {{IS_LOCKED==true}}]
if {{[llength $ip_locked] > 0}} {{
    puts "Found locked IPs, upgrading..."
    upgrade_ip [get_ips *]
    puts "IP upgrade completed"
}}

# Report IP status
set all_ips [get_ips]
if {{[llength $all_ips] > 0}} {{
    puts "IP Cores in project:"
    foreach ip $all_ips {{
        set ip_status [get_property IS_LOCKED $ip]
        puts "  - $ip: [expr {{$ip_status ? \"LOCKED\" : \"OK\"}}]"
    }}
}}

# Generate all IP output products if needed
puts "Checking IP output products..."
catch {{
    generate_target all [get_ips]
}}

# Check and run synthesis
set synth_status [get_property STATUS [get_runs synth_1]]
set synth_progress [get_property PROGRESS [get_runs synth_1]]
puts "Synthesis Status: $synth_status (Progress: $synth_progress)"

if {{![string match "*Complete!*" $synth_status]}} {{
    puts "Starting synthesis run..."
    reset_run synth_1
    launch_runs synth_1 -jobs {cpu_jobs}
    wait_on_run synth_1
    
    set synth_status [get_property STATUS [get_runs synth_1]]
    set synth_progress [get_property PROGRESS [get_runs synth_1]]
    puts "Synthesis completed with status: $synth_status (Progress: $synth_progress)"
    
    if {{![string match "*Complete!*" $synth_status]}} {{
        puts "ERROR: Synthesis failed!"
        puts "  Status: $synth_status"
        puts "  Progress: $synth_progress"
        
        # Try to get error messages
        set msgs [get_msg_config -severity ERROR]
        if {{[llength $msgs] > 0}} {{
            puts "Error messages:"
            foreach msg $msgs {{
                puts "  - $msg"
            }}
        }}
        exit 1
    }}
}} else {{
    puts "Synthesis already completed, skipping synthesis step"
}}

# Launch implementation and generate bitstream
puts "Starting implementation run..."
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs {cpu_jobs}
wait_on_run impl_1

# Check run status
set impl_status [get_property STATUS [get_runs impl_1]]
set impl_progress [get_property PROGRESS [get_runs impl_1]]
puts "Implementation Status: $impl_status (Progress: $impl_progress)"

if {{![string match "*Complete!*" $impl_status]}} {{
    puts "ERROR: Implementation or bitstream generation failed!"
    puts "  Status: $impl_status"
    puts "  Progress: $impl_progress"
    
    # Get timing summary
    catch {{
        open_run impl_1
        set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
        puts "  Worst Negative Slack (WNS): $wns"
    }}
    
    exit 1
}}

# Create output directory
file mkdir "{output_dir}"

# Get bitstream file path
set bit_file [get_property DIRECTORY [get_runs impl_1]]/$design_name.bit
set ltx_file [get_property DIRECTORY [get_runs impl_1]]/$design_name.ltx

# Initialize summary list
set copied_files [list]

if {{[file exists $bit_file]}} {{
    # Copy bitstream file
    file copy -force $bit_file "{output_dir}/$overlay_name.bit"
    puts "Bitstream copied to: {output_dir}/$overlay_name.bit"
    lappend copied_files "  ✓ $overlay_name.bit <- [file tail $bit_file] (from implementation run)"
    
    # Copy ltx file if exists
    if {{[file exists $ltx_file]}} {{
        file copy -force $ltx_file "{output_dir}/$overlay_name.ltx"
        puts "Debug probes file copied to: {output_dir}/$overlay_name.ltx"
        lappend copied_files "  ✓ $overlay_name.ltx <- [file tail $ltx_file] (debug probes file)"
    }} else {{
        puts "No ltx file found, skipping"
    }}
    
    # Generate XSA file
    puts "Generating XSA file..."
    write_hw_platform -fixed -include_bit -force -file "{output_dir}/$overlay_name.xsa"
    puts "XSA file generated: {output_dir}/$overlay_name.xsa"
    lappend copied_files "  ✓ $overlay_name.xsa <- from hardware platform (includes bitstream)"
}} else {{
    puts "ERROR: Bitstream file does not exist: $bit_file"
    exit 1
}}

# Close project
close_project

# Print summary
puts ""
puts "========================================"
puts "File Generation Summary"
puts "========================================"
puts "Output directory: {output_dir}"
puts ""
puts "Generated/Copied files:"
foreach file $copied_files {{
    puts $file
}}
puts ""
puts "✓ Bitstream generation completed!"
puts "========================================"

exit 0
"""
    
    # 创建临时文件
    with tempfile.NamedTemporaryFile(mode='w', suffix='.tcl', delete=False, encoding='utf-8') as f:
        tcl_file = f.name
        f.write(tcl_script)
    
    try:
        # 执行 Vivado 批处理模式
        cmd = [vivado_bat, '-mode', 'batch', '-source', tcl_file]
        print(f"执行命令: {' '.join(cmd)}")
        
        result = subprocess.run(cmd, shell=True)
        
        if result.returncode == 0:
            print(f"\n" + "="*60)
            print(f"File Generation Summary (Python)")
            print(f"="*60)
            print(f"Output directory: {output_dir}")
            print(f"\nExpected files:")
            
            # 获取 overlay 名称
            overlay_name = os.path.basename(os.path.dirname(os.path.dirname(project_path)))
            
            # Check and list actually generated files
            expected_files = [
                (f"{overlay_name}.bit", "Bitstream file"),
                (f"{overlay_name}.ltx", "Debug probes file"),
                (f"{overlay_name}.xsa", "Hardware platform export file")
            ]
            
            print(f"\nGenerated files:")
            for filename, description in expected_files:
                filepath = os.path.join(output_dir, filename)
                if os.path.exists(filepath):
                    file_size = os.path.getsize(filepath)
                    size_mb = file_size / (1024 * 1024)
                    print(f"  ✓ {filename:30s} ({description}, {size_mb:.2f} MB)")
                else:
                    print(f"  ✗ {filename:30s} ({description}) - Not found")
            
            print(f"\n✓ Bitstream generation successful!")
            print(f"="*60)
        else:
            print(f"\n✗ Bitstream generation failed, return code: {result.returncode}")
            sys.exit(1)
            
    except Exception as e:
        print(f"Execution failed: {e}")
        sys.exit(1)
    finally:
        # 删除临时文件
        if os.path.exists(tcl_file):
            os.remove(tcl_file)


def run_tcl_script(tcl_file, open_gui=True, background=False):
    """
    执行 TCL 脚本
    
    Args:
        tcl_file: TCL 脚本文件路径
        open_gui: 是否打开 GUI，True 打开图形界面，False 批处理模式
    """
    vivado_bat = os.path.join(VIVADO_PATH, 'vivado.bat')
    if not os.path.exists(vivado_bat):
        print(f"错误: Vivado 路径不存在: {vivado_bat}")
        sys.exit(1)
    
    if not os.path.exists(tcl_file):
        print(f"错误: TCL 脚本不存在: {tcl_file}")
        sys.exit(1)
    
    tcl_file = os.path.abspath(tcl_file)
    
    print(f"执行 TCL 脚本: {tcl_file}")
    
    if open_gui:
        # GUI 模式：打开图形界面
        print(f"运行模式: GUI (图形界面)")
        if background:
            cmd = ['cmd', '/c', 'call', vivado_bat, '-mode', 'gui', '-source', tcl_file]
            _run_hidden_cmd(cmd)
            print("Vivado GUI 已启动")
            return
        else:
            cmd = [vivado_bat, '-source', tcl_file]
        try:
            if background:
                _run_detached(cmd)
            else:
                subprocess.Popen(cmd, shell=False)
            print("Vivado GUI 已启动")
        except Exception as e:
            print(f"启动失败: {e}")
            sys.exit(1)
    else:
        # 批处理模式：后台运行
        print(f"运行模式: Batch (批处理模式)")
        if background:
            cmd = ['cmd', '/c', 'call', vivado_bat, '-mode', 'batch', '-source', tcl_file]
            _run_hidden_cmd(cmd)
            return
        else:
            cmd = [vivado_bat, '-mode', 'batch', '-source', tcl_file]
        try:
            if background:
                _run_detached(cmd)
            else:
                result = subprocess.run(cmd, shell=True)
                if result.returncode != 0:
                    print(f"TCL 脚本执行失败，返回码: {result.returncode}")
                    sys.exit(1)
        except Exception as e:
            print(f"执行失败: {e}")
            sys.exit(1)


def main():
    """主函数"""
    configure_console_encoding()

    parser = argparse.ArgumentParser(
        description='Vivado 工具启动脚本',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
    py xilinx.py                              # 默认后台启动 Vivado GUI
    py xilinx.py -fg                          # 前台启动 Vivado GUI
    py xilinx.py project.xpr                  # 打开指定工程
    py xilinx.py -s script.tcl                # 默认后台执行 TCL 脚本
    py xilinx.py -s script.tcl -fg            # 前台执行 TCL 脚本
    py xilinx.py -b                           # 生成 bitstream（默认配置）
    py xilinx.py -b -o ./output -j 32         # 生成 bitstream 并指定输出目录和线程数
    py xilinx.py -b -p ./custom/project.xpr   # 指定工程文件并生成 bitstream
    py xilinx.py -ip                          # 扫描并导出所有IP
    py xilinx.py -ip -b                       # 先导出IP再生成 bitstream
    py xilinx.py -copy                        # 拷贝工程 IP 目录到 source/ip
    py xilinx.py -copy -b                     # 从 impl_1 拷贝 bit/ltx 并导出 XSA（不重新编译）
    py xilinx.py -copy -b -o ./output         # 同上，指定输出目录
    py xilinx.py -p                           # 烧写 bit/ 下的 BIN 文件
    py xilinx.py -p -c                        # 创建 BOOT.BIN 后烧写
    py xilinx.py -p -c -no                    # 只创建 BOOT.BIN，不烧写
    py xilinx.py -clear                       # 删除当前目录下 .str/.log/.jou 文件
        """
    )
    
    parser.add_argument('-bit', '-b',
                       action='store_true',
                       help='生成 bitstream 文件')
    parser.add_argument('-o',
                       type=str,
                       metavar='DIR',
                       help=f'bitstream 输出目录（默认: {DEFAULT_BITSTREAM_PATH}）')
    # v1.2 2026/05/03 修改：-p 单独使用时表示烧写，与 -b 连用时兼容原工程路径参数
    parser.add_argument('-p',
                       nargs='?',
                       const='__program_flash__',
                       type=str,
                       metavar='FILE',
                       help=f'单独使用时烧写 BIN；与 -b 连用时为 Vivado 工程文件路径（默认: {DEFAULT_PROJECT_PATH}）')
    # v1.2 2026/05/03 新增：-p -c 先创建 BOOT.BIN 再烧写
    parser.add_argument('-c',
                       action='store_true',
                       help='与 -p 连用，根据 bit/ 下的 fsbl、bit、app.elf 创建 BIN 后烧写')
    # v1.2 2026/05/03 新增：-p -c -no 只创建 BOOT.BIN，不执行烧写
    parser.add_argument('-no',
                       action='store_true',
                       dest='no_program',
                       help='与 -p -c 连用，只创建 BOOT.BIN，不烧写')
    parser.add_argument('-j',
                       type=int,
                       metavar='NUM',
                       help=f'CPU 线程数（默认: {DEFAULT_CPU_JOBS}）')
    parser.add_argument('-s',
                       type=str,
                       metavar='FILE',
                       help='执行指定的 TCL 脚本')
    parser.add_argument('-ip',
                       action='store_true',
                       help='扫描并导出所有IP（集成原 top.py 功能）')
    # v1.1 2026/04/27 新增：-copy 参数，拷贝工程 IP 目录到 source/ip
    parser.add_argument('-copy',
                       action='store_true',
                       help='拷贝 project/project.srcs/sources_1/ip 到 source/ip')
    # v1.3 2026/05/27 新增：清理当前目录下 .str/.log/.jou 文件
    parser.add_argument('-clear',
                       action='store_true',
                       help='删除当前目录下所有 .str/.log/.jou 文件')
    parser.add_argument('-bg',
                       action='store_true',
                       help='后台运行 Vivado/脚本（默认）')
    parser.add_argument('-fg',
                       action='store_true',
                       help='前台运行 Vivado/脚本')
    parser.add_argument('vivado_args', 
                       nargs='*',
                       help='传递给 Vivado 的其他参数（当没有指定任何选项时）')
    
    args = parser.parse_args()
    program_flash_mode = args.p == '__program_flash__' and not args.bit

    if args.c and not program_flash_mode:
        print("错误: -c 必须与 -p 烧写模式一起使用")
        sys.exit(1)

    if args.no_program and not (program_flash_mode and args.c):
        print("错误: -no 必须与 -p -c 一起使用")
        sys.exit(1)

    if args.bit and args.p == '__program_flash__':
        print("错误: -b 与 -p 连用时，-p 后必须指定 Vivado 工程文件路径")
        sys.exit(1)

    if args.p and args.p != '__program_flash__' and not args.bit and not args.copy:
        print("错误: -p 指定工程文件路径时必须与 -b 或 -copy -b 连用")
        sys.exit(1)

    # v1.1 2026/04/27 新增：-copy 独立操作，不依赖 Vivado，优先处理后直接返回
    # v1.2 2026/05/03 修改：-copy -b 组合时执行拷贝产物操作，不重新编译
    if args.copy and args.bit:
        copy_build_artifacts(args.o, args.p)
        return

    if args.copy:
        copy_ip_from_project()
        return

    # v1.3 2026/05/27 新增：-clear 独立清理日志文件，不依赖 Vivado
    if args.clear:
        clear_vivado_temp_files('.')
        return

    # v1.2 2026/05/03 新增：Zynq-7020 烧写操作，不依赖 Vivado GUI
    if program_flash_mode:
        if args.no_program:
            create_zynq_boot_bin(args.o)
            return
        program_zynq_flash(create_bin=args.c, bit_dir=args.o)
        return

    bg_mode = True
    if args.fg:
        bg_mode = False
    elif args.bg:
        bg_mode = True
    
    # 检查 Vivado 路径
    vivado_bat = os.path.join(VIVADO_PATH, 'vivado.bat')
    if not os.path.exists(vivado_bat):
        print(f"错误: Vivado 路径不存在: {vivado_bat}")
        sys.exit(1)
    
    # 如果指定了 -ip，直接调用集成的IP导出功能
    if args.ip:
        run_ip_export()

    # 如果指定了 TCL 脚本，先执行
    if args.s:
        # 如果同时指定了 -bit，则以批处理模式运行脚本
        if bg_mode and args.bit:
            print("提示: -bit 需要前台执行，已忽略 -bg")
            run_tcl_script(args.s, open_gui=not args.bit, background=False)
        else:
            run_tcl_script(args.s, open_gui=not args.bit, background=bg_mode)
    
    # 如果指定了生成 bitstream
    if args.bit:
        build_bitstream(args.o, args.p, args.j)
    
    # 如果没有指定任何操作，正常启动 Vivado GUI
    if not args.bit and not args.s and not args.ip and not args.clear:
        # 如果是后台模式，直接调用
        if bg_mode:
            cmd = ['cmd', '/c', 'call', vivado_bat, '-mode', 'gui'] + args.vivado_args
            _run_hidden_cmd(cmd)
            print(f"启动 Vivado: {vivado_bat} -mode gui")
            return
        else:
            cmd = [vivado_bat] + args.vivado_args
        print(f"启动 Vivado: {' '.join(cmd)}")
        
        try:
            if args.bg:
                _run_detached(cmd)
            else:
                subprocess.run(cmd, shell=True)
        except Exception as e:
            print(f"启动失败: {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
