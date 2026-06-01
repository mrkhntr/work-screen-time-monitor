package com.mrkhntr.workscreentime.enforcement

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

data class BlockUiState(
    val title: String,
    val message: String,
    val requiresPhrase: Boolean,
    val requiresReason: Boolean,
    val confirmationPhrase: String,
)

@Composable
fun BlockScreen(
    state: BlockUiState,
    onSnooze: (String?) -> Unit,
    onDismiss: (String?) -> Unit,
) {
    var reason by remember { mutableStateOf("") }
    var phrase by remember { mutableStateOf("") }

    MaterialTheme {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(Color(0xFF14141C))
                .padding(32.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(state.title, color = Color.White, fontSize = 28.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
            Text(state.message, color = Color.White.copy(alpha = 0.82f), fontSize = 16.sp, textAlign = TextAlign.Center)

            if (state.requiresPhrase) {
                Text("Type: ${state.confirmationPhrase}", color = Color.White.copy(alpha = 0.7f))
                OutlinedTextField(value = phrase, onValueChange = { phrase = it }, singleLine = true, modifier = Modifier.widthIn(max = 360.dp))
            }
            if (state.requiresReason) {
                OutlinedTextField(value = reason, onValueChange = { reason = it }, modifier = Modifier.widthIn(max = 360.dp))
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = { onSnooze(reason.ifBlank { null }) }) { Text("Snooze") }
                Button(onClick = { onDismiss(reason.ifBlank { null }) }) { Text("Dismiss") }
            }
        }
    }
}
