package com.thisisnsh.cuecard.android.ui.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.thisisnsh.cuecard.android.R
import com.thisisnsh.cuecard.android.services.AuthenticationService
import com.thisisnsh.cuecard.android.ui.theme.AppColors
import kotlinx.coroutines.launch

@Composable
fun LoginScreen(
    authService: AuthenticationService
) {
    val isLoading by authService.isLoading.collectAsState()
    val error by authService.error.collectAsState()
    val scope = rememberCoroutineScope()
    val isDark = isSystemInDarkTheme()

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
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Logo - using app icon
                Image(
                    painter = painterResource(id = R.mipmap.ic_launcher),
                    contentDescription = "CueCard Logo",
                    modifier = Modifier
                        .size(80.dp)
                        .clip(RoundedCornerShape(16.dp))
                )

                Spacer(modifier = Modifier.height(24.dp))

                // Title
                Text(
                    text = "CueCard",
                    fontSize = 36.sp,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.textPrimary(isDark)
                )

                Spacer(modifier = Modifier.height(8.dp))

                // Subtitle - matching iOS
                Text(
                    text = "Floating Teleprompter",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Medium,
                    color = AppColors.textSecondary(isDark)
                )
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
                        .padding(horizontal = 32.dp)
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
                // Google Sign-In Button
                Button(
                    onClick = {
                        scope.launch {
                            // Replace with your actual Web Client ID from Firebase Console
                            authService.signInWithGoogle("829544425796-a38eavf0pphc2l2p1rc60dg8d5tpddg3.apps.googleusercontent.com")
                        }
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp)
                        .shadow(
                            elevation = 4.dp,
                            shape = RoundedCornerShape(12.dp),
                            ambientColor = Color.Black.copy(alpha = 0.1f),
                            spotColor = Color.Black.copy(alpha = 0.1f)
                        ),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color.White,
                        contentColor = Color.Black,
                        disabledContainerColor = Color.White.copy(alpha = 0.6f),
                        disabledContentColor = Color.Black.copy(alpha = 0.6f)
                    ),
                    enabled = !isLoading
                ) {
                    Row(
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
                }

                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = AppColors.green(isDark),
                        strokeWidth = 2.dp
                    )
                }

                // Privacy note
                Text(
                    text = "Your data stays on your device",
                    fontSize = 12.sp,
                    color = AppColors.textSecondary(isDark)
                )
            }
        }
    }
}

