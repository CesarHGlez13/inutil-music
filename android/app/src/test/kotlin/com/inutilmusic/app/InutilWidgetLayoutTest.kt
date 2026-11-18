package com.inutilmusic.app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class InutilWidgetLayoutTest {
    @Test
    fun compactSizesUseTheUpdatedHeightThreshold() {
        for (width in listOf(250, 339, 340, 430)) {
            assertEquals(InutilWidgetLayout.COMPACT_SMALL, InutilWidgetLayout.forSize(width, 56))
            assertEquals(InutilWidgetLayout.COMPACT_SMALL, InutilWidgetLayout.forSize(width, 71))
            assertEquals(InutilWidgetLayout.COMPACT_SMALL, InutilWidgetLayout.forSize(width, 79))
            assertEquals(InutilWidgetLayout.COMPACT, InutilWidgetLayout.forSize(width, 80))
            assertEquals(InutilWidgetLayout.COMPACT, InutilWidgetLayout.forSize(width, 149))
        }
    }

    @Test
    fun tallWidgetsUseSeparateMetadataEvenWhenNarrow() {
        assertEquals(InutilWidgetLayout.LARGE, InutilWidgetLayout.forSize(250, 150))
        assertEquals(InutilWidgetLayout.LARGE, InutilWidgetLayout.forSize(430, 164))
        assertEquals(InutilWidgetLayout.LARGE, InutilWidgetLayout.forSize(339, 165))
        assertEquals(InutilWidgetLayout.LARGE, InutilWidgetLayout.forSize(250, 320))
        assertEquals(InutilWidgetLayout.EXPANDED, InutilWidgetLayout.forSize(340, 165))
        assertEquals(InutilWidgetLayout.EXPANDED, InutilWidgetLayout.forSize(430, 220))
        assertEquals(InutilWidgetLayout.EXPANDED, InutilWidgetLayout.forSize(430, 249))
        assertEquals(InutilWidgetLayout.QUEUE, InutilWidgetLayout.forSize(340, 250))
        assertEquals(InutilWidgetLayout.QUEUE, InutilWidgetLayout.forSize(430, 320))
    }

    @Test
    fun onlyLargeVariantsShowThreeMetadataLines() {
        assertFalse(InutilWidgetLayout.COMPACT_SMALL.hasSeparateMetadata)
        assertFalse(InutilWidgetLayout.COMPACT.hasSeparateMetadata)
        assertTrue(InutilWidgetLayout.LARGE.hasSeparateMetadata)
        assertTrue(InutilWidgetLayout.EXPANDED.hasSeparateMetadata)
        assertTrue(InutilWidgetLayout.QUEUE.hasSeparateMetadata)
    }
}
