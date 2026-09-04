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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowOutward
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
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
import com.thisisnsh.cuecard.android.services.AuthenticationService
import com.thisisnsh.cuecard.android.services.RemoteConfigService
import kotlinx.coroutines.launch

@Composable
fun LoginView(
    authService: AuthenticationService,
    @Suppress("UNUSED_PARAMETER") remoteConfig: RemoteConfigService
) {
    // A provider can be switched off remotely on iOS, but only while the other one
    // still works. Android has one provider, so honouring `googleSignIn: false`
    // here would lock every user out with no fallback — the flag is read, and the
    // button stays.
    val isLoading by authService.isLoading.collectAsState()
    val error by authService.error.collectAsState()
    val scope = rememberCoroutineScope()
    val isDark = LocalIsDarkTheme.current
    val context = LocalContext.current
    val webClientId = stringResource(id = R.string.default_web_client_id)

    LaunchedEffect(Unit) {
        AnalyticsEvents.logScreenView("login")
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
                    contentDescription = "CueCard Logo",
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

            // Error message
            error?.let { errorMessage ->
                Text(
                    text = errorMessage,
                    fontSize = 12.sp,
                    color = AppColors.red(isDark),
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .padding(horizontal = 16.dp)
                        .padding(bottom = 16.dp)
                )
            }

            // Sign in section
            Column(
                modifier = Modifier
                    .padding(horizontal = 32.dp)
                    .padding(bottom = 48.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .alpha(if (isLoading) 0.6f else 1f)
                        .shadow(
                            elevation = 4.dp,
                            shape = RoundedCornerShape(12.dp),
                            ambientColor = Color.Black.copy(alpha = 0.1f),
                            spotColor = Color.Black.copy(alpha = 0.1f)
                        )
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color.White)
                        .clickableWithoutRipple {
                            if (isLoading) return@clickableWithoutRipple
                            AnalyticsEvents.logButtonClick("sign_in_with_google", "login")
                            scope.launch {
                                authService.signInWithGoogle(webClientId)
                            }
                        }
                        .padding(vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center
                ) {
                    Image(
                        painter = painterResource(id = R.drawable.ic_google),
                        contentDescription = null,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = "Continue with Google",
                        fontWeight = FontWeight.SemiBold,
                        color = Color.Black
                    )
                }

                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = AppColors.green(isDark),
                        strokeWidth = 2.dp
                    )
                }

                // Privacy note
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = "Your notes stay on your device",
                        fontSize = 12.sp,
                        color = AppColors.textSecondary(isDark)
                    )

                    Row(
                        modifier = Modifier.clickableWithoutRipple {
                            AnalyticsEvents.logButtonClick("source_code", "login")
                            openLink(context, AppLinks.SOURCE_CODE)
                        },
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(4.dp)
                    ) {
                        Text(
                            text = "View the code",
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
