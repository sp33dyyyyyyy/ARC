package com.viper.mobile.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun Panel(modifier: Modifier = Modifier, title: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().clip(RoundedCornerShape(3.dp)).background(Glass).border(BorderStroke(1.dp, Line), RoundedCornerShape(3.dp)).padding(14.dp)) {
        if (title != null) { Text(title, style = MaterialTheme.typography.titleMedium); Spacer(Modifier.height(8.dp)) }
        content()
    }
}

@Composable
fun Meter(frac: Float, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(3.dp).background(Color(0x1AFFFFFF))) { Box(Modifier.fillMaxWidth(frac.coerceIn(0f, 1f)).fillMaxHeight().background(Ink)) }
}

@Composable
fun VButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, primary: Boolean = false, enabled: Boolean = true) {
    if (primary) Button(onClick, modifier, enabled = enabled, shape = RoundedCornerShape(3.dp), colors = ButtonDefaults.buttonColors(containerColor = Ink, contentColor = Void)) { Text(text) }
    else OutlinedButton(onClick, modifier, enabled = enabled, shape = RoundedCornerShape(3.dp), border = BorderStroke(1.dp, Line2), colors = ButtonDefaults.outlinedButtonColors(contentColor = Ink)) { Text(text) }
}

private fun inline(s: String): AnnotatedString = buildAnnotatedString {
    var i = 0
    val re = Regex("\\*\\*([^*]+)\\*\\*|`([^`]+)`")
    for (m in re.findAll(s)) {
        append(s.substring(i, m.range.first))
        if (m.groupValues[1].isNotEmpty()) withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(m.groupValues[1]) }
        else withStyle(SpanStyle(fontFamily = Mono, background = Color(0x14FFFFFF))) { append(m.groupValues[2]) }
        i = m.range.last + 1
    }
    append(s.substring(i))
}

/** Minimal, safe Markdown: headings, lists, bold, inline code and fenced code blocks. */
@Composable
fun MarkdownText(md: String, color: Color = Ink) {
    val parts = md.split("```")
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        parts.forEachIndexed { idx, part ->
            if (idx % 2 == 1) {
                val code = part.substringAfter('\n', part)
                Box(Modifier.fillMaxWidth().background(Color(0x0DFFFFFF)).border(1.dp, Line).horizontalScroll(rememberScrollState()).padding(10.dp)) {
                    Text(code.trimEnd(), fontFamily = Mono, fontSize = 12.sp, color = Ink2)
                }
            } else for (line in part.trim('\n').lines()) {
                when {
                    line.isBlank() -> Spacer(Modifier.height(2.dp))
                    line.startsWith("#") -> Text(inline(line.trimStart('#', ' ')), style = MaterialTheme.typography.titleMedium, color = color)
                    Regex("^\\s*([-*]|\\d+\\.)\\s+").containsMatchIn(line) -> Row { Text("•  ", color = Mist); Text(inline(line.replace(Regex("^\\s*([-*]|\\d+\\.)\\s+"), "")), color = color) }
                    else -> Text(inline(line), color = color, style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
    }
}

@Composable
fun Tag(text: String, on: Boolean = false) {
    Box(Modifier.clip(RoundedCornerShape(20.dp)).background(if (on) Ink else Color.Transparent).border(1.dp, if (on) Ink else Line2, RoundedCornerShape(20.dp)).padding(horizontal = 8.dp, vertical = 2.dp)) {
        Text(text, fontSize = 11.5.sp, color = if (on) Void else Ink2)
    }
}

@Composable
fun KV(k: String, v: String) = Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
    Text(k, color = Mist, fontSize = 13.sp, modifier = Modifier.weight(1f)); Text(v, fontSize = 13.sp)
}
