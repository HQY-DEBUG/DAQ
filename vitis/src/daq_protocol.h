/*
 * 文件：daq_protocol.h
 * 说明：DAQ 小端外框、命令和数据帧的可移植协议接口。
 * 版本：v1.1
 * 日期：2026/09/27
 * 修改历史：
 *   v1.1 2026/09/27 按冻结协议定义致命流错误与逐帧返回接口。
 *   v1.0 2026/09/26 新增协议编解码接口。
 */
#ifndef DAQ_PROTOCOL_H
#define DAQ_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>

#define DAQ_BLOCK_SAMPLES 4096u
#define DAQ_BLOCK_BYTES 32768u
#define DAQ_DATA_SIZE (40u + DAQ_BLOCK_BYTES)
#define DAQ_DATA_FRAME_SIZE (DAQ_DATA_SIZE + 16u)
#define DAQ_MAX_DATA_SIZE 32808u
#define DAQ_MAX_REQUEST_DATA_SIZE 16u
#define DAQ_HEAD 0xA5A5A5A5u
#define DAQ_TAIL 0xB5B5B5B5u

#define DAQ_CMD_RESET 0xC00000FFu
#define DAQ_CMD_START 0xC00100FFu
#define DAQ_CMD_STOP 0xC00200FFu
#define DAQ_CMD_STATUS 0xC00300FFu
#define DAQ_TYPE_DATA 0xF00000FFu
#define DAQ_TYPE_EVENT 0xC00400FFu

enum daq_result {
    DAQ_OK = 0, DAQ_BAD_REQUEST = 1, DAQ_BUSY = 2,
    DAQ_DMA_ERROR = 3, DAQ_PL_OVERFLOW = 4, DAQ_SD_FULL = 5,
    DAQ_SD_IO_ERROR = 6, DAQ_NETWORK_ERROR = 7,
    DAQ_BUFFER_FULL = 8, DAQ_INTERNAL_ERROR = 9
};
enum daq_state { DAQ_IDLE = 0, DAQ_RUNNING = 1, DAQ_DRAINING = 2, DAQ_FAULT = 3 };
enum daq_sd_state { DAQ_SD_DISABLED = 0, DAQ_SD_WRITING = 1,
                    DAQ_SD_FULL_STATE = 2, DAQ_SD_ERROR = 3, DAQ_SD_CLOSED = 4 };

typedef struct {
    uint32_t result, state;
    uint64_t session_id, produced_samples, uploaded_blocks, stored_blocks;
    uint64_t overflow_count;
    uint32_t mode, sd_state, queue_used, queue_capacity;
} daq_status_t;

typedef struct {
    uint32_t type, size;
    uint8_t data[DAQ_MAX_REQUEST_DATA_SIZE];
} daq_command_t;

typedef enum {
    DAQ_PARSE_MORE = 0,
    DAQ_PARSE_FRAME = 1,
    DAQ_PARSE_BAD_HEADER = 2,
    DAQ_PARSE_BAD_LENGTH = 3,
    DAQ_PARSE_BAD_TAIL = 4,
    DAQ_PARSE_FAILED = 5
} daq_parse_result_t;

typedef struct {
    uint8_t head[12];
    uint8_t data[DAQ_MAX_REQUEST_DATA_SIZE];
    uint8_t tail[4];
    uint8_t phase;
    uint8_t used;
    uint32_t type, size;
} daq_parser_t;

uint32_t daq_get_u32(const uint8_t *p);
uint64_t daq_get_u64(const uint8_t *p);
void daq_put_u32(uint8_t *p, uint32_t value);
void daq_put_u64(uint8_t *p, uint64_t value);
void daq_crc_init(void);
uint32_t daq_crc32(const uint8_t *data, size_t bytes);
void daq_encode_status(uint8_t frame[80], uint32_t type, const daq_status_t *status);
void daq_encode_data_prefix(uint8_t prefix[52], uint64_t session,
                            uint64_t sequence, uint64_t first_sample,
                            const uint8_t data[DAQ_BLOCK_BYTES]);
/* 2026/09/27 修改：仅新连接可显式 reset；错误后解析器保持失败态。 */
void daq_parser_reset(daq_parser_t *parser);
/* 2026/09/27 修改：返回一帧即停止并给出 consumed；调用者处理命令或断线后再决定是否继续。
 * MORE 表示字节已消费但帧未完成；BAD_* 是致命错误；FAILED 表示连接已被锁定。
 * 调用者在 daq_parser_has_partial() 为真时使用单调时钟执行 5 秒半帧超时。
 * 受影响调用者：daq_app.c::recv_cb，下一阶段须按返回值循环并在致命错误时关闭连接。 */
daq_parse_result_t daq_parser_feed(daq_parser_t *parser, const uint8_t *bytes,
                                   size_t count, size_t *consumed,
                                   daq_command_t *command);
int daq_parser_has_partial(const daq_parser_t *parser);

#endif
