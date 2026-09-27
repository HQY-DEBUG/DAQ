/*
 * 文件：test_protocol.c
 * 说明：协议边界、拆粘包、CRC 与 64 bit 字段主机测试。
 * 版本：v1.1
 * 日期：2026/09/27
 * 修改历史：
 *   v1.1 2026/09/27 覆盖冻结协议外框失败锁定、全部分割点和固定向量。
 *   v1.0 2026/09/26 新增主机协议测试。
 */
#include "../src/daq_protocol.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static daq_command_t received[4];
static unsigned received_count;

static size_t make_request(uint8_t *out, uint32_t type, uint32_t size,
                           const uint8_t *data)
{
    daq_put_u32(out, DAQ_HEAD);
    daq_put_u32(out + 4, type);
    daq_put_u32(out + 8, size);
    if (size) memcpy(out + 12, data, size);
    daq_put_u32(out + 12 + size, DAQ_TAIL);
    return (size_t)size + 16u;
}

static void feed_chunk(daq_parser_t *parser, const uint8_t *bytes, size_t count)
{
    size_t offset = 0;
    while (offset < count) {
        size_t consumed;
        daq_command_t command;
        daq_parse_result_t result = daq_parser_feed(parser, bytes + offset,
                                                     count - offset, &consumed,
                                                     &command);
        assert(consumed > 0 && consumed <= count - offset);
        assert(result == DAQ_PARSE_MORE || result == DAQ_PARSE_FRAME);
        offset += consumed;
        if (result == DAQ_PARSE_FRAME) {
            assert(received_count < 4);
            received[received_count++] = command;
        }
    }
}

/* 2026/09/27 修改：每个切分点和逐字节输入都验证同一条有序字节流。 */
static void test_stream(void)
{
    uint8_t stream[48], payload[16];
    daq_parser_t parser;
    size_t split, i;
    daq_put_u32(payload, 3u);
    daq_put_u32(payload + 4, 1000000u);
    daq_put_u32(payload + 8, DAQ_BLOCK_SAMPLES);
    daq_put_u32(payload + 12, 0u);
    assert(make_request(stream, DAQ_CMD_START, 16u, payload) == 32u);
    assert(make_request(stream + 32, DAQ_CMD_STATUS, 0u, NULL) == 16u);

    for (split = 0; split <= sizeof(stream); ++split) {
        received_count = 0;
        daq_parser_reset(&parser);
        feed_chunk(&parser, stream, split);
        if (split != 0u && split != 32u && split != sizeof(stream))
            assert(daq_parser_has_partial(&parser));
        feed_chunk(&parser, stream + split, sizeof(stream) - split);
        assert(received_count == 2u);
        assert(received[0].type == DAQ_CMD_START && received[0].size == 16u);
        assert(daq_get_u32(received[0].data + 4) == 1000000u);
        assert(received[1].type == DAQ_CMD_STATUS && received[1].size == 0u);
        assert(!daq_parser_has_partial(&parser));
    }

    received_count = 0;
    daq_parser_reset(&parser);
    for (i = 0; i < sizeof(stream); ++i)
        feed_chunk(&parser, stream + i, 1u);
    assert(received_count == 2u && !daq_parser_has_partial(&parser));

    received_count = 0;
    daq_parser_reset(&parser);
    assert(make_request(stream, 0xDEADBEEFu, 0u, NULL) == 16u);
    feed_chunk(&parser, stream, 16u);
    assert(received_count == 1u && received[0].type == 0xDEADBEEFu);
    assert(received[0].size == 0u);
}

/* 2026/09/27 修改：坏外框必须锁定且不可吞入后续合法请求。 */
static void test_fatal_frames(void)
{
    uint8_t stream[48], payload[16] = {0};
    daq_parser_t parser;
    daq_command_t command;
    size_t consumed, good_len, bad_len, header_byte;
    daq_parse_result_t result;

    good_len = make_request(stream + 32, DAQ_CMD_STATUS, 0u, NULL);
    assert(good_len == 16u);

    for (header_byte = 0; header_byte < 4u; ++header_byte) {
        bad_len = make_request(stream, DAQ_CMD_START, 16u, payload);
        stream[header_byte] = 0u;
        daq_parser_reset(&parser);
        result = daq_parser_feed(&parser, stream, bad_len + good_len,
                                 &consumed, &command);
        assert(result == DAQ_PARSE_BAD_HEADER && consumed == header_byte + 1u);
        assert(!daq_parser_has_partial(&parser));
        assert(daq_parser_feed(&parser, stream + bad_len, good_len,
                               &consumed, &command) == DAQ_PARSE_FAILED);
        assert(consumed == 0u);
    }

    make_request(stream, DAQ_CMD_START, 16u, payload);
    stream[31] ^= 1u;
    daq_parser_reset(&parser);
    assert(daq_parser_feed(&parser, stream, bad_len + good_len,
                           &consumed, &command) == DAQ_PARSE_BAD_TAIL);
    assert(consumed == 32u);
    assert(daq_parser_feed(&parser, stream + bad_len, good_len,
                           &consumed, &command) == DAQ_PARSE_FAILED);

    make_request(stream, DAQ_CMD_START, 16u, payload);
    daq_put_u32(stream + 8, 17u);
    daq_parser_reset(&parser);
    assert(daq_parser_feed(&parser, stream, bad_len + good_len,
                           &consumed, &command) == DAQ_PARSE_BAD_LENGTH);
    assert(consumed == 12u);
    assert(daq_parser_feed(&parser, stream + bad_len, good_len,
                           &consumed, &command) == DAQ_PARSE_FAILED);

    daq_put_u32(stream + 8, UINT32_MAX);
    daq_parser_reset(&parser);
    assert(daq_parser_feed(&parser, stream, bad_len + good_len,
                           &consumed, &command) == DAQ_PARSE_BAD_LENGTH);
    assert(consumed == 12u);

    /* 只有新连接显式 reset 才能离开失败态。 */
    daq_parser_reset(&parser);
    received_count = 0;
    feed_chunk(&parser, stream + bad_len, good_len);
    assert(received_count == 1u && received[0].type == DAQ_CMD_STATUS);
}

static void test_encoding(void)
{
    uint8_t status_frame[80], prefix[52], samples[DAQ_BLOCK_BYTES];
    daq_status_t status = {0};
    size_t i;

    daq_crc_init();
    assert(daq_crc32((const uint8_t *)"123456789", 9u) == 0xCBF43926u);
    for (i = 0; i < DAQ_BLOCK_SAMPLES; ++i)
        daq_put_u64(samples + i * 8u, (uint64_t)i);
    for (i = 0; i < DAQ_BLOCK_SAMPLES; ++i)
        assert(daq_get_u64(samples + i * 8u) == (uint64_t)i);
    assert(daq_crc32(samples, sizeof(samples)) == 0x30F674A6u);

    status.result = DAQ_SD_FULL;
    status.state = DAQ_RUNNING;
    status.session_id = 0x123456789ABCDEF0ull;
    status.produced_samples = 259200000000ull;
    status.uploaded_blocks = 0x100000001ull;
    status.stored_blocks = 0x200000003ull;
    status.overflow_count = 1u;
    status.mode = 3u;
    status.sd_state = DAQ_SD_FULL_STATE;
    status.queue_used = 100u;
    status.queue_capacity = 2048u;
    daq_encode_status(status_frame, DAQ_CMD_STATUS, &status);
    assert(daq_get_u32(status_frame) == DAQ_HEAD);
    assert(daq_get_u32(status_frame + 4) == DAQ_CMD_STATUS);
    assert(daq_get_u32(status_frame + 8) == 64u);
    assert(daq_get_u32(status_frame + 12) == DAQ_SD_FULL);
    assert(daq_get_u32(status_frame + 16) == DAQ_RUNNING);
    assert(daq_get_u64(status_frame + 20) == status.session_id);
    assert(daq_get_u64(status_frame + 28) == status.produced_samples);
    assert(daq_get_u64(status_frame + 36) == status.uploaded_blocks);
    assert(daq_get_u64(status_frame + 44) == status.stored_blocks);
    assert(daq_get_u64(status_frame + 52) == status.overflow_count);
    assert(daq_get_u32(status_frame + 60) == status.mode);
    assert(daq_get_u32(status_frame + 64) == status.sd_state);
    assert(daq_get_u32(status_frame + 68) == status.queue_used);
    assert(daq_get_u32(status_frame + 72) == status.queue_capacity);
    assert(daq_get_u32(status_frame + 76) == DAQ_TAIL);

    daq_encode_data_prefix(prefix, status.session_id,
                           0x100000001ull, 0x100000001ull * 4096u, samples);
    assert(daq_get_u32(prefix) == DAQ_HEAD);
    assert(daq_get_u32(prefix + 4) == DAQ_TYPE_DATA);
    assert(daq_get_u32(prefix + 8) == DAQ_DATA_SIZE);
    assert(daq_get_u32(prefix + 12) == 1u);
    assert(daq_get_u32(prefix + 16) == 0u);
    assert(daq_get_u64(prefix + 20) == status.session_id);
    assert(daq_get_u64(prefix + 28) == 0x100000001ull);
    assert(daq_get_u64(prefix + 36) == 0x100000001ull * 4096u);
    assert(daq_get_u32(prefix + 44) == DAQ_BLOCK_SAMPLES);
    assert(daq_get_u32(prefix + 48) == 0x30F674A6u);
}

int main(void)
{
    test_stream();
    test_fatal_frames();
    test_encoding();
    puts("protocol tests passed");
    return 0;
}
