package com.itantra.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.itantra.ui.screens.*

@Composable
fun ITantraNavGraph(modifier: Modifier = Modifier) {
    val navController = rememberNavController()

    NavHost(
        navController = navController,
        startDestination = "splash",
        modifier = modifier
    ) {
        composable("splash") {
            SplashScreen(
                onSplashComplete = {
                    navController.navigate("home") {
                        popUpTo("splash") { inclusive = true }
                    }
                }
            )
        }
        composable("home") {
            HomeScreen(
                onNavigateToTransceiver = { navController.navigate("transceiver") },
                onNavigateToDiscovery = { navController.navigate("discovery") },
                onNavigateToAlerts = { navController.navigate("alerts") },
                onNavigateToHistory = { navController.navigate("history") },
                onNavigateToSettings = { navController.navigate("settings") }
            )
        }
        composable("transceiver") {
            TransceiverScreen(
                onNavigateBack = { navController.popBackStack() },
                onNavigateToAlerts = { navController.navigate("alerts") },
                onNavigateToDiscovery = { navController.navigate("discovery") }
            )
        }
        composable("alerts") {
            AlertScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }
        composable("discovery") {
            PeerDiscoveryScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }
        composable("history") {
            HistoryScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }
        composable("settings") {
            SettingsScreen(
                onNavigateBack = { navController.popBackStack() }
            )
        }
    }
}
