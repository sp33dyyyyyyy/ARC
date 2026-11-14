package com.viper.mobile.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.material3.Typography
import androidx.compose.ui.unit.sp

val Void = Color(0xFF000000)
val Ink = Color(0xFFF4F6F7)
val Ink2 = Color(0xFFC9CED2)
val Mist = Color(0xFF858B91)
val Line = Color(0x21FFFFFF)
val Line2 = Color(0x3DFFFFFF)
val Glass = Color(0x0AFFFFFF)

private val scheme = darkColorScheme(
    primary = Ink, onPrimary = Void, secondary = Ink2, onSecondary = Void, background = Void, onBackground = Ink,
    surface = Void, onSurface = Ink, surfaceVariant = Color(0xFF0B0B0B), onSurfaceVariant = Ink2, outline = Line2, error = Ink, onError = Void,
    surfaceContainer = Color(0xFF080808), surfaceContainerHigh = Color(0xFF101010), surfaceContainerHighest = Color(0xFF151515),
)
private val type = Typography(
    headlineMedium = TextStyle(fontWeight = FontWeight.Light, fontSize = 28.sp, letterSpacing = 0.2.sp),
    titleLarge = TextStyle(fontWeight = FontWeight.Light, fontSize = 21.sp),
    titleMedium = TextStyle(fontWeight = FontWeight.Normal, fontSize = 16.sp),
    bodyLarge = TextStyle(fontSize = 15.sp, lineHeight = 22.sp), bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
    labelSmall = TextStyle(fontSize = 11.5.sp, color = Mist),
)
val Mono = FontFamily.Monospace

@Composable
fun ViperTheme(content: @Composable () -> Unit) = MaterialTheme(colorScheme = scheme, typography = type, content = content)
