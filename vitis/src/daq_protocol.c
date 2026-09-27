/*
 * 文件：daq_protocol.c
 * 说明：显式小端编解码、流式命令解析与 CRC-32 slicing-by-8。
 * 版本：v1.1
 * 日期：2026/09/27
 * 修改历史：
 *   v1.1 2026/09/27 严格校验外框，坏流锁定并逐帧返回给调用者。
 *   v1.0 2026/09/26 新增协议实现。
 */
#include "daq_protocol.h"
#include <string.h>

static uint32_t crc_table[8][256];

uint32_t daq_get_u32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

uint64_t daq_get_u64(const uint8_t *p)
{
    return (uint64_t)daq_get_u32(p) | ((uint64_t)daq_get_u32(p + 4) << 32);
}

void daq_put_u32(uint8_t *p, uint32_t value)
{
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
    p[2] = (uint8_t)(value >> 16);
    p[3] = (uint8_t)(value >> 24);
}

void daq_put_u64(uint8_t *p, uint64_t value)
{
    daq_put_u32(p, (uint32_t)value);
    daq_put_u32(p + 4, (uint32_t)(value >> 32));
}

void daq_crc_init(void)
{
    unsigned i, j, k;
    for (i = 0; i < 256; ++i) {
        uint32_t crc = i;
        for (j = 0; j < 8; ++j)
            crc = (crc >> 1) ^ ((crc & 1u) ? 0xEDB88320u : 0u);
        crc_table[0][i] = crc;
    }
    for (k = 1; k < 8; ++k)
        for (i = 0; i < 256; ++i)
            crc_table[k][i] = (crc_table[k - 1][i] >> 8) ^
                              crc_table[0][crc_table[k - 1][i] & 0xffu];
}

uint32_t daq_crc32(const uint8_t *data, size_t bytes)
{
    uint32_t crc = 0xffffffffu;
    while (bytes >= 8u) {
        uint32_t one = crc ^ daq_get_u32(data);
        crc = crc_table[7][one & 0xffu] ^
              crc_table[6][(one >> 8) & 0xffu] ^
              crc_table[5][(one >> 16) & 0xffu] ^
              crc_table[4][one >> 24] ^
              crc_table[3][data[4]] ^ crc_table[2][data[5]] ^
              crc_table[1][data[6]] ^ crc_table[0][data[7]];
        data += 8;
        bytes -= 8;
    }
    while (bytes--) crc = (crc >> 8) ^ crc_table[0][(crc ^ *data++) & 0xffu];
    return crc ^ 0xffffffffu;
}

void daq_encode_status(uint8_t frame[80], uint32_t type, const daq_status_t *s)
{
    daq_put_u32(frame, DAQ_HEAD);
    daq_put_u32(frame + 4, type);
    daq_put_u32(frame + 8, 64u);
    daq_put_u32(frame + 12, s->result);
    daq_put_u32(frame + 16, s->state);
    daq_put_u64(frame + 20, s->session_id);
    daq_put_u64(frame + 28, s->produced_samples);
    daq_put_u64(frame + 36, s->uploaded_blocks);
    daq_put_u64(frame + 44, s->stored_blocks);
    daq_put_u64(frame + 52, s->overflow_count);
    daq_put_u32(frame + 60, s->mode);
    daq_put_u32(frame + 64, s->sd_state);
    daq_put_u32(frame + 68, s->queue_used);
    daq_put_u32(frame + 72, s->queue_capacity);
    daq_put_u32(frame + 76, DAQ_TAIL);
}

void daq_encode_data_prefix(uint8_t prefix[52], uint64_t session,
                            uint64_t sequence, uint64_t first_sample,
                            const uint8_t data[DAQ_BLOCK_BYTES])
{
    daq_put_u32(prefix, DAQ_HEAD);
    daq_put_u32(prefix + 4, DAQ_TYPE_DATA);
    daq_put_u32(prefix + 8, DAQ_DATA_SIZE);
    daq_put_u32(prefix + 12, 1u);
    daq_put_u32(prefix + 16, 0u);
    daq_put_u64(prefix + 20, session);
    daq_put_u64(prefix + 28, sequence);
    daq_put_u64(prefix + 36, first_sample);
    daq_put_u32(prefix + 44, DAQ_BLOCK_SAMPLES);
    daq_put_u32(prefix + 48, daq_crc32(data, DAQ_BLOCK_BYTES));
}

/* 2026/09/27 修改：重置只供新连接初始化，致命错误不能在坏流中重同步。 */
void daq_parser_reset(daq_parser_t *p)
{
    memset(p, 0, sizeof(*p));
}

int daq_parser_has_partial(const daq_parser_t *p)
{
    return p->phase != 4u && (p->phase != 0u || p->used != 0u);
}

/* 2026/09/27 修改：一次最多返回一帧；外框错误锁定，调用者在函数返回后处理断线。 */
daq_parse_result_t daq_parser_feed(daq_parser_t *p, const uint8_t *bytes,
                                   size_t count, size_t *consumed,
                                   daq_command_t *command)
{
    size_t i;
    *consumed = 0;
    if (p->phase == 4u) return DAQ_PARSE_FAILED;
    for (i = 0; i < count; ++i) {
        uint8_t byte = bytes[i];
        *consumed = i + 1u;
        if (p->phase == 0) {
            if (byte != 0xa5u) {
                p->phase = 4u;
                return DAQ_PARSE_BAD_HEADER;
            }
            p->head[p->used++] = byte;
            if (p->used == 4u) {
                p->phase = 1;
                p->used = 4u;
            }
        } else if (p->phase == 1) {
            p->head[p->used++] = byte;
            if (p->used == 12u) {
                p->type = daq_get_u32(p->head + 4);
                p->size = daq_get_u32(p->head + 8);
                if (p->size > DAQ_MAX_REQUEST_DATA_SIZE) {
                    p->phase = 4u;
                    return DAQ_PARSE_BAD_LENGTH;
                }
                p->phase = p->size ? 2u : 3u;
                p->used = 0u;
            }
        } else if (p->phase == 2) {
            p->data[p->used++] = byte;
            if (p->used == p->size) {
                p->phase = 3u;
                p->used = 0u;
            }
        } else {
            p->tail[p->used++] = byte;
            if (p->used == 4u) {
                if (daq_get_u32(p->tail) != DAQ_TAIL) {
                    p->phase = 4u;
                    return DAQ_PARSE_BAD_TAIL;
                }
                command->type = p->type;
                command->size = p->size;
                memcpy(command->data, p->data, p->size);
                p->phase = 0u;
                p->used = 0u;
                p->type = 0u;
                p->size = 0u;
                return DAQ_PARSE_FRAME;
            }
        }
    }
    return DAQ_PARSE_MORE;
}
