package com.memexlab.memex.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

class WidgetLayoutsTest {
    private val zone = ZoneId.of("America/Sao_Paulo")

    @Test
    fun `visibleRowLimit scales cleanly from 0 to 3 rows without half-clipping`() {
        assertEquals(0, WidgetLayouts.visibleRowLimit(120))
        assertEquals(0, WidgetLayouts.visibleRowLimit(249))
        assertEquals(1, WidgetLayouts.visibleRowLimit(250))
        assertEquals(1, WidgetLayouts.visibleRowLimit(339))
        assertEquals(1, WidgetLayouts.visibleRowLimit(387))
        assertEquals(2, WidgetLayouts.visibleRowLimit(388))
        assertEquals(2, WidgetLayouts.visibleRowLimit(435))
        assertEquals(3, WidgetLayouts.visibleRowLimit(436))
        assertEquals(3, WidgetLayouts.visibleRowLimit(480))
    }

    @Test
    fun `usesFullLargeChrome unlocks full reference chrome from 340dp upwards`() {
        assertFalse(WidgetLayouts.usesFullLargeChrome(250))
        assertFalse(WidgetLayouts.usesFullLargeChrome(339))
        assertTrue(WidgetLayouts.usesFullLargeChrome(340))
        assertTrue(WidgetLayouts.usesFullLargeChrome(436))
    }

    @Test
    fun `formatTaskTimeLabel includes dd-MM and optional time for overdue rows`() {
        val datedAndTimed = WidgetRow(
            task = WidgetTask(
                id = "t1",
                title = "Enviar proposta",
                dueDate = LocalDate.of(2026, 11, 14),
                dueTime = LocalTime.of(9, 5),
                zone = zone,
            ),
            overdue = true,
        )
        val datedOnly = WidgetRow(
            task = WidgetTask(
                id = "t2",
                title = "Revisar contrato",
                dueDate = LocalDate.of(2026, 11, 14),
                dueTime = null,
                zone = zone,
            ),
            overdue = true,
        )

        assertEquals("14/11 09:05", WidgetLayouts.formatTaskTimeLabel("Hoje", datedAndTimed))
        assertEquals("14/11", WidgetLayouts.formatTaskTimeLabel("Hoje", datedOnly))
    }

    @Test
    fun `formatTaskTimeLabel shows time when present or todayLabel when untimed`() {
        val timedToday = WidgetRow(
            task = WidgetTask(
                id = "t3",
                title = "Consulta",
                dueDate = LocalDate.of(2026, 11, 15),
                dueTime = LocalTime.of(16, 30),
                zone = zone,
            ),
            overdue = false,
        )
        val untimedToday = WidgetRow(
            task = WidgetTask(
                id = "t4",
                title = "Comprar cafe",
                dueDate = LocalDate.of(2026, 11, 15),
                dueTime = null,
                zone = zone,
            ),
            overdue = false,
        )

        assertEquals("16:30", WidgetLayouts.formatTaskTimeLabel("Hoje", timedToday))
        assertEquals("Hoje", WidgetLayouts.formatTaskTimeLabel("Hoje", untimedToday))
        assertEquals("Today", WidgetLayouts.formatTaskTimeLabel("Today", untimedToday))
    }

    // RemoteViews only inflates whitelisted classes; anything else makes the launcher refuse the widget.
    @Test
    fun `widget layouts use only RemoteViews-allowed tags`() {
        val allowed = setOf(
            "FrameLayout", "LinearLayout", "RelativeLayout", "GridLayout", "TextView", "ImageView",
            "ImageButton", "Button", "ProgressBar", "ListView", "include",
        )
        val layouts = java.io.File("src/main/res/layout").listFiles { f -> f.name.startsWith("widget_") }!!
        assertTrue(layouts.isNotEmpty())
        val tag = Regex("<([A-Za-z.]+)")
        for (file in layouts) {
            for (match in tag.findAll(file.readText())) {
                val name = match.groupValues[1]
                assertTrue("${file.name} uses <$name>", name in allowed)
            }
        }
    }
}
