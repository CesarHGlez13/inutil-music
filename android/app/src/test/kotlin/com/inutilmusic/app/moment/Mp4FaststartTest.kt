package com.inutilmusic.app.moment

import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class Mp4FaststartTest {

    @Test
    fun movesMoovBeforeMdatAndPatchesStcoOffsets() {
        val ftyp = buildAtom("ftyp", ByteArray(16) { 1 })
        val mdat = buildAtom("mdat", ByteArray(48) { 2 })
        val originalChunkOffset = ftyp.size + 8 // payload start inside mdat
        val stcoPayload = ByteBuffer.allocate(4 + 4 + 4)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(0) // version + flags
            .putInt(1) // entry count
            .putInt(originalChunkOffset)
            .array()
        val stco = buildAtom("stco", stcoPayload)
        val stbl = buildAtom("stbl", stco)
        val minf = buildAtom("minf", stbl)
        val mdia = buildAtom("mdia", minf)
        val trak = buildAtom("trak", mdia)
        val moov = buildAtom("moov", trak)

        val rawFile = File.createTempFile("faststart_in_", ".mp4")
        val outFile = File.createTempFile("faststart_out_", ".mp4")
        try {
            rawFile.writeBytes(ftyp + mdat + moov)

            val ok = Mp4Faststart.optimize(rawFile, outFile)
            assertTrue(ok)

            val bytes = outFile.readBytes()
            assertEquals(rawFile.length().toInt(), bytes.size)

            // Verify top-level order is now: ftyp -> moov -> mdat.
            val firstType = String(bytes, 4, 4, Charsets.ISO_8859_1)
            val secondOffset = ftyp.size
            val secondType = String(bytes, secondOffset + 4, 4, Charsets.ISO_8859_1)
            val thirdOffset = ftyp.size + moov.size
            val thirdType = String(bytes, thirdOffset + 4, 4, Charsets.ISO_8859_1)

            assertEquals("ftyp", firstType)
            assertEquals("moov", secondType)
            assertEquals("mdat", thirdType)

            // Verify stco chunk offset was shifted by +moov.size.
            val stcoIndex = findAscii(bytes, "stco")
            assertTrue(stcoIndex > 0)
            val patchedOffset = ByteBuffer.wrap(bytes, stcoIndex + 4 + 8, 4)
                .order(ByteOrder.BIG_ENDIAN)
                .int
            assertEquals(originalChunkOffset + moov.size, patchedOffset)
        } finally {
            rawFile.delete()
            outFile.delete()
        }
    }

    private fun buildAtom(type: String, payload: ByteArray): ByteArray {
        val out = ByteArrayOutputStream(8 + payload.size)
        val header = ByteBuffer.allocate(8)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(8 + payload.size)
            .array()
        out.write(header, 0, 4)
        out.write(type.toByteArray(Charsets.ISO_8859_1))
        out.write(payload)
        return out.toByteArray()
    }

    private fun findAscii(haystack: ByteArray, needle: String): Int {
        val target = needle.toByteArray(Charsets.ISO_8859_1)
        outer@ for (i in 0..(haystack.size - target.size)) {
            for (j in target.indices) {
                if (haystack[i + j] != target[j]) continue@outer
            }
            return i
        }
        return -1
    }
}
