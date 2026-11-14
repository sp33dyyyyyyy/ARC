package com.viper.mobile.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** Compact port of the desktop VIPER core: rotating rings, segmented arcs, radial audio bars and a luminous centre. */
@Composable
fun VCore(state: String, level: Float, modifier: Modifier = Modifier) {
    val spin = when (state) { "listening" -> 0.35f; "thinking" -> 0.7f; "speaking" -> 0.4f; "warning" -> 0.25f; "offline" -> 0.03f; else -> 0.1f }
    val glow = when (state) { "listening", "speaking" -> 1f; "thinking" -> 0.75f; "offline" -> 0.2f; else -> 0.55f }
    val animGlow by animateFloatAsState(glow, tween(600), label = "glow")
    val animSpin by animateFloatAsState(spin, tween(600), label = "spin")
    val animLevel by animateFloatAsState(level, tween(90), label = "lvl")
    val t = rememberInfiniteTransition(label = "core")
    val time by t.animateFloat(0f, 1000f, infiniteRepeatable(tween(1_000_000, easing = LinearEasing)), label = "t")
    Canvas(modifier) {
        val r = size.minDimension / 2f * 0.92f
        val c = center
        val sec = time
        val white = { a: Float -> Color.White.copy(alpha = a.coerceIn(0f, 1f)) }
        rotate(sec * 6f * animSpin, c) {
            for (i in 0 until 72) {
                val a = i / 72f * 2 * PI.toFloat(); val long = i % 6 == 0
                val r2 = r - (if (long) 10f else 4f)
                drawLine(white(if (long) 0.5f else 0.2f), Offset(c.x + cos(a) * r, c.y + sin(a) * r), Offset(c.x + cos(a) * r2, c.y + sin(a) * r2), strokeWidth = if (long) 2f else 1f)
            }
        }
        rotate(-sec * 15f * animSpin, c) {
            val sr = r * 0.74f
            for (i in 0 until 12) {
                val lit = (sin(sec * 2 + i * 0.9f) * 0.5f + 0.5f) * animGlow
                drawArc(white(0.18f + 0.5f * lit), startAngle = i * 30f + 3f, sweepAngle = 24f * (0.55f + 0.45f * (i % 3) / 2f), useCenter = false,
                    topLeft = Offset(c.x - sr, c.y - sr), size = Size(sr * 2, sr * 2), style = Stroke(width = 4f, pathEffect = if (state == "warning" || state == "offline") PathEffect.dashPathEffect(floatArrayOf(6f, 8f)) else null))
            }
        }
        for (f in listOf(0.86f, 0.62f)) drawCircle(white(0.1f), radius = r * f, center = c, style = Stroke(1f))
        val inner = r * 0.4f; val bars = 64
        for (i in 0 until bars) {
            val a = i / bars.toFloat() * 2 * PI.toFloat() + sec * 0.1f
            val v = animLevel * (0.55f + 0.45f * sin(i * 0.7f + sec * 9)) * (0.6f + 0.4f * sin(i * 1.7f - sec * 5))
            val idle = 0.08f * (0.5f + 0.5f * sin(i * 0.4f + sec * 1.6f))
            val len = (idle + v) * r * 0.22f + 2f
            drawLine(white(0.3f + 0.6f * v), Offset(c.x + cos(a) * inner, c.y + sin(a) * inner), Offset(c.x + cos(a) * (inner + len), c.y + sin(a) * (inner + len)), strokeWidth = 2f, cap = StrokeCap.Round)
        }
        val breathe = 0.5f + 0.5f * sin(sec * 1.4f)
        val coreR = r * (0.22f + 0.02f * breathe + 0.08f * animLevel)
        drawCircle(Brush.radialGradient(listOf(white(0.85f * animGlow + 0.1f), white(0.3f * animGlow), Color.Transparent), center = c, radius = coreR * 1.9f), radius = coreR * 1.9f, center = c)
        drawCircle(white(0.5f + 0.4f * animGlow), radius = coreR, center = c, style = Stroke(2f))
    }
}
