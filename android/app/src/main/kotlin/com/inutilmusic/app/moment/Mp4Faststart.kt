package com.inutilmusic.app.moment

import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Pure-Kotlin MP4 faststart relocator.
 *
 * Android's MediaMuxer writes the `moov` metadata atom at the tail of the file
 * after `mdat`. Moving `moov` right after `ftyp` (and shifting every `stco` /
 * `co64` chunk offset by `+moov.size`) makes WhatsApp, Instagram, TikTok, and
 * web players start decoding immediately without buffering the whole file.
 */
object Mp4Faststart {
    private data class Atom(
        val type: String,
        val offset: Long,
        val size: Long,
    )

    private val CONTAINER_BOXES = setOf(
        "moov", "trak", "mdia", "minf", "stbl", "edts", "dinf", "udta",
    )

    fun optimize(input: File, output: File): Boolean {
        if (!input.exists() || input.length() < 16L) return false
        RandomAccessFile(input, "r").use { raf ->
            val atoms = readTopLevelAtoms(raf)
            val ftyp = atoms.firstOrNull { it.type == "ftyp" } ?: return false
            val moov = atoms.firstOrNull { it.type == "moov" } ?: return false
            val mdat = atoms.firstOrNull { it.type == "mdat" } ?: return false

            // Already faststart: moov precedes mdat.
            if (moov.offset < mdat.offset) {
                if (input.absolutePath != output.absolutePath) {
                    input.copyTo(output, overwrite = true)
                }
                return true
            }

            if (moov.size > 32L * 1024L * 1024L) {
                // Guard against pathological metadata sizes.
                return false
            }

            val moovBytes = ByteArray(moov.size.toInt())
            raf.seek(moov.offset)
            raf.readFully(moovBytes)

            val delta = moov.size
            patchChunkOffsets(moovBytes, 0, moovBytes.size, delta)

            output.parentFile?.mkdirs()
            FileOutputStream(output).use { out ->
                // 1. Write ftyp atom first.
                copyRange(raf, ftyp.offset, ftyp.size, out)
                // 2. Write patched moov atom right after ftyp.
                out.write(moovBytes)
                // 3. Write all remaining top-level atoms (mdat, free, etc.) in order.
                for (atom in atoms) {
                    if (atom === ftyp || atom === moov) continue
                    copyRange(raf, atom.offset, atom.size, out)
                }
            }
            return true
        }
    }

    private fun readTopLevelAtoms(raf: RandomAccessFile): List<Atom> {
        val result = mutableListOf<Atom>()
        val length = raf.length()
        val header = ByteArray(16)
        var pos = 0L
        while (pos + 8L <= length) {
            raf.seek(pos)
            raf.readFully(header, 0, 8)
            val buf = ByteBuffer.wrap(header).order(ByteOrder.BIG_ENDIAN)
            var size = buf.getInt(0).toLong() and 0xFFFFFFFFL
            val type = String(header, 4, 4, Charsets.ISO_8859_1)
            if (size == 1L) {
                if (pos + 16L > length) break
                raf.readFully(header, 8, 8)
                size = ByteBuffer.wrap(header, 8, 8).order(ByteOrder.BIG_ENDIAN).long
            } else if (size == 0L) {
                size = length - pos
            }
            if (size < 8L || pos + size > length) break
            result.add(Atom(type = type, offset = pos, size = size))
            pos += size
        }
        return result
    }

    private fun patchChunkOffsets(bytes: ByteArray, start: Int, end: Int, delta: Long) {
        val buf = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        var pos = start
        while (pos + 8 <= end) {
            var size = (buf.getInt(pos).toLong() and 0xFFFFFFFFL)
            val type = String(bytes, pos + 4, 4, Charsets.ISO_8859_1)
            var headerSize = 8
            if (size == 1L) {
                if (pos + 16 > end) return
                size = buf.getLong(pos + 8)
                headerSize = 16
            } else if (size == 0L) {
                size = (end - pos).toLong()
            }
            if (size < headerSize || pos + size > end) return

            val boxEnd = (pos + size).toInt()
            when {
                type == "stco" -> {
                    val entryCountPos = pos + headerSize + 4
                    if (entryCountPos + 4 <= boxEnd) {
                        val count = buf.getInt(entryCountPos)
                        var entryPos = entryCountPos + 4
                        for (i in 0 until count) {
                            if (entryPos + 4 > boxEnd) break
                            val current = buf.getInt(entryPos).toLong() and 0xFFFFFFFFL
                            buf.putInt(entryPos, (current + delta).toInt())
                            entryPos += 4
                        }
                    }
                }
                type == "co64" -> {
                    val entryCountPos = pos + headerSize + 4
                    if (entryCountPos + 4 <= boxEnd) {
                        val count = buf.getInt(entryCountPos)
                        var entryPos = entryCountPos + 4
                        for (i in 0 until count) {
                            if (entryPos + 8 > boxEnd) break
                            val current = buf.getLong(entryPos)
                            buf.putLong(entryPos, current + delta)
                            entryPos += 8
                        }
                    }
                }
                type in CONTAINER_BOXES -> {
                    patchChunkOffsets(bytes, pos + headerSize, boxEnd, delta)
                }
            }
            pos = boxEnd
        }
    }

    private fun copyRange(
        raf: RandomAccessFile,
        offset: Long,
        size: Long,
        out: FileOutputStream,
    ) {
        raf.seek(offset)
        val buffer = ByteArray(256 * 1024)
        var remaining = size
        while (remaining > 0L) {
            val toRead = minOf(remaining, buffer.size.toLong()).toInt()
            val read = raf.read(buffer, 0, toRead)
            if (read <= 0) break
            out.write(buffer, 0, read)
            remaining -= read
        }
    }
}
