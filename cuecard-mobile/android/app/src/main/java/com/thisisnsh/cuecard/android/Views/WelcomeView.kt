package com.thisisnsh.cuecard.android.views

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowOutward
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.thisisnsh.cuecard.android.AnalyticsEvents
import com.thisisnsh.cuecard.android.AppLinks
import com.thisisnsh.cuecard.android.LocalIsDarkTheme
import com.thisisnsh.cuecard.android.R
import com.thisisnsh.cuecard.android.models.AppColors

/**
 * The first thing a new install opens on. Tapping through remembers itself, so
 * this is seen once: only a fresh install brings it back.
 */
@Composable
fun WelcomeView(onGetStarted: () -> Unit) {
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView("welcome")
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.background(isDark))
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.weight(1f))

            // Hero section
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(24.dp)
            ) {
                Image(
                    painter = painterResource(id = R.mipmap.ic_launcher),
                    contentDescription = null,
                    modifier = Modifier
                        .size(80.dp)
                        .clip(RoundedCornerShape(16.dp))
                )

                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = "CueCard",
                        fontSize = 36.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppColors.textPrimary(isDark)
                    )

                    Text(
                        text = "Floating Teleprompter",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Medium,
                        color = AppColors.textSecondary(isDark)
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // Get started section
            Column(
                modifier = Modifier
                    .padding(horizontal = 32.dp)
                    .padding(bottom = 48.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {

                Text(
                    text = "Get Started",
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                    color = if (isDark) Color.Black else Color.White,
                    modifier = Modifier
                        .fillMaxWidth()
                        .shadow(
                            elevation = 4.dp,
                            shape = RoundedCornerShape(12.dp),
                            ambientColor = Color.Black.copy(alpha = 0.1f),
                            spotColor = Color.Black.copy(alpha = 0.1f)
                        )
                        .clip(RoundedCornerShape(12.dp))
                        .background(if (isDark) Color.White else Color.Black)
                        .clickableWithoutRipple {
                            AnalyticsEvents.logButtonClick("get_started", "welcome")
                            onGetStarted()
                        }
                        .padding(vertical = 16.dp)
                )

                // Privacy note
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = "No account needed. Scripts stay on this device.",
                        fontSize = 12.sp,
                        color = AppColors.textSecondary(isDark)
                    )

                    Row(
                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(
                            modifier = Modifier.clickableWithoutRipple {
                                AnalyticsEvents.logButtonClick("privacy_policy", "welcome")
                                openLink(context, AppLinks.PRIVACY_POLICY)
                            },
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(
                                text = "Privacy policy",
                                fontSize = 12.sp,
                                textDecoration = TextDecoration.Underline,
                                color = AppColors.textSecondary(isDark)
                            )
                            Icon(
                                imageVector = Icons.Filled.ArrowOutward,
                                contentDescription = null,
                                tint = AppColors.textSecondary(isDark),
                                modifier = Modifier.size(9.dp)
                            )
                        }

                        Row(
                            modifier = Modifier.clickableWithoutRipple {
                                AnalyticsEvents.logButtonClick("source_code", "welcome")
                                openLink(context, AppLinks.SOURCE_CODE)
                            },
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp)
                        ) {
                            Text(
                                text = "View code",
                                fontSize = 12.sp,
                                textDecoration = TextDecoration.Underline,
                                color = AppColors.textSecondary(isDark)
                            )
                            Icon(
                                imageVector = Icons.Filled.ArrowOutward,
                                contentDescription = null,
                                tint = AppColors.textSecondary(isDark),
                                modifier = Modifier.size(9.dp)
                            )
                        }
                    }
                }
            }
        }
    }
}
