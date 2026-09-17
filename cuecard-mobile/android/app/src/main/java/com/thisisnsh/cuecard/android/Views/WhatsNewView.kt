package com.thisisnsh.cuecard.android.views

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.R
import com.thisisnsh.cuecard.android.models.AppColors
import com.thisisnsh.cuecard.android.services.WhatsNewService
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * This build's new features, on a card floating over whatever is on screen.
 * Shown once per build on launch, and again from Settings.
 */
@Composable
fun WhatsNewDialog(
    release: WhatsNewService.Release,
    version: String,
    onDismiss: () -> Unit
) {
    val visibility = remember { MutableTransitionState(false).apply { targetState = true } }

    // Let the card leave before the dialog underneath it goes.
    LaunchedEffect(visibility.currentState, visibility.targetState) {
        if (!visibility.targetState && visibility.isIdle) onDismiss()
    }

    Dialog(
        onDismissRequest = { visibility.targetState = false },
        properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnClickOutside = false)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp, vertical = 40.dp),
            contentAlignment = Alignment.Center
        ) {
            AnimatedVisibility(
                visibleState = visibility,
                enter = scaleIn(initialScale = 0.92f) + fadeIn(),
                exit = scaleOut(targetScale = 0.92f) + fadeOut()
            ) {
                WhatsNewCard(
                    release = release,
                    version = version,
                    onClose = { visibility.targetState = false }
                )
            }
        }
    }
}

@Composable
private fun WhatsNewCard(
    release: WhatsNewService.Release,
    version: String,
    onClose: () -> Unit
) {
    val isDark = LocalIsDarkTheme.current
    val primary = AppColors.textPrimary(isDark)
    val secondary = AppColors.textSecondary(isDark)
    val shape = RoundedCornerShape(32.dp)

    Box(
        modifier = Modifier
            .widthIn(max = 380.dp)
            .shadow(30.dp, shape)
            .clip(shape)
            .starfieldGradient(isDark)
            .border(1.dp, primary.copy(alpha = 0.1f), shape)
    ) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(start = 24.dp, end = 24.dp, top = 56.dp, bottom = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            Text(
                text = release.title ?: "What's New",
                fontSize = 30.sp,
                lineHeight = 36.sp,
                fontWeight = FontWeight.Bold,
                color = primary,
                textAlign = TextAlign.Center
            )

            FloatingIcon()

            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = "CueCard",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = primary
                )
                Text(
                    text = "Version $version",
                    fontSize = 15.sp,
                    color = secondary
                )
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(20.dp))
                    .background(primary.copy(alpha = 0.05f))
                    .padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                release.features.forEach { feature ->
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(
                            imageVector = Icons.Filled.AutoAwesome,
                            contentDescription = null,
                            tint = secondary,
                            modifier = Modifier
                                .padding(top = 3.dp)
                                .size(14.dp)
                        )
                        Text(
                            text = feature,
                            fontSize = 15.sp,
                            color = primary
                        )
                    }
                }
            }
        }

        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(14.dp)
                .size(32.dp)
                .clip(CircleShape)
                .background(primary.copy(alpha = 0.08f))
                .clickableWithoutRipple(onClose),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = "Close",
                tint = primary,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

/** The app icon, tilted and bobbing gently. */
@Composable
private fun FloatingIcon() {
    val float by rememberInfiniteTransition(label = "float").animateFloat(
        initialValue = -5f,
        targetValue = 5f,
        animationSpec = infiniteRepeatable(tween(2400), RepeatMode.Reverse),
        label = "offset"
    )
    val shape = RoundedCornerShape(26.dp)

    Image(
        painter = painterResource(id = R.mipmap.ic_launcher),
        contentDescription = null,
        modifier = Modifier
            .graphicsLayer {
                rotationZ = -8f
                translationY = float.dp.toPx()
            }
            .shadow(18.dp, shape)
            .clip(shape)
            .size(112.dp)
    )
}

private data class Star(
    val x: Float,
    val y: Float,
    val radius: Float,
    val speed: Float,
    val phase: Float
)

/** The same sky every time: positions come from a fixed seed. */
private val stars: List<Star> = run {
    val random = kotlin.random.Random(0x2545F491)
    List(48) {
        Star(
            x = random.nextFloat(),
            y = random.nextFloat(),
            radius = 0.6f + random.nextFloat() * 1.4f,
            speed = 0.6f + random.nextFloat() * 1.0f,
            phase = random.nextFloat() * 2f * Math.PI.toFloat()
        )
    }
}

/**
 * The app's background as a slowly turning gradient, with stars twinkling and
 * drifting up through it. Light in light mode, dark in dark mode.
 */
@Composable
private fun Modifier.starfieldGradient(isDark: Boolean): Modifier {
    val background = AppColors.background(isDark)
    val lifted = if (isDark) Color(0xFF24211E) else Color(0xFFE5DDCF)
    // White glints on dark; on the light background white would vanish, so
    // they take the secondary text color, kept faint.
    val starColor = if (isDark) Color.White else AppColors.Light.textSecondary
    val starStrength = if (isDark) 1f else 0.45f
    val glow = Color.White.copy(alpha = if (isDark) 0.08f else 0.7f)

    var time by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(Unit) {
        val start = withFrameNanos { it }
        while (true) {
            withFrameNanos { time = (it - start) / 1_000_000_000f }
        }
    }

    return drawBehind {
        val t = time
        val angle = t / 6f
        val w = size.width
        val h = size.height
        val reach = max(w, h) / 2f
        val dx = cos(angle) * reach
        val dy = sin(angle) * reach

        drawRect(
            Brush.linearGradient(
                colors = listOf(background, lifted, background),
                start = Offset(w / 2f + dx, h / 2f + dy),
                end = Offset(w / 2f - dx, h / 2f - dy)
            )
        )

        // A soft glow behind the icon.
        drawRect(
            Brush.radialGradient(
                colors = listOf(glow, Color.Transparent),
                center = Offset(w / 2f, h * 0.36f),
                radius = 220.dp.toPx()
            )
        )

        val density = this.density
        stars.forEach { star ->
            var y = (star.y - t * 0.006f * star.speed) % 1f
            if (y < 0f) y += 1f
            // Fade out near the edges, so wrapping around never pops.
            val edge = min(min(y * 8f, (1f - y) * 8f), 1f)
            val twinkle = ((sin(t * star.speed * 1.6f + star.phase) + 1f) / 2f).pow(2)
            val alpha = twinkle * edge * starStrength

            val center = Offset(star.x * w, y * h)
            val radius = star.radius * density
            drawCircle(starColor.copy(alpha = alpha * 0.18f), radius = radius * 4f, center = center)
            drawCircle(starColor.copy(alpha = alpha), radius = radius, center = center)
        }
    }
}
