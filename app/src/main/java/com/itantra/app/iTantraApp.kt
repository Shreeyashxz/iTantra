package com.itantra.app

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class iTantraApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Initialization for Sherpa-ONNX or other application-wide setup can be done here.
    }
}
