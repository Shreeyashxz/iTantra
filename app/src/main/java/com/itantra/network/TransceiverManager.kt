package com.itantra.network

import android.content.Context
import com.itantra.proto.TransceiverPacketProto.TransceiverPacket
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.withContext
import java.io.InputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TransceiverManager @Inject constructor(
    private val context: Context
) {
    private var serverSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    
    private val _incomingPackets = MutableSharedFlow<TransceiverPacket>()
    val incomingPackets: Flow<TransceiverPacket> = _incomingPackets

    private val PORT = 8888

    suspend fun startServer() = withContext(Dispatchers.IO) {
        try {
            serverSocket = ServerSocket(PORT)
            while (true) {
                val socket = serverSocket?.accept() ?: break
                handleIncomingConnection(socket)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    suspend fun connectToPeer(ipAddress: String) = withContext(Dispatchers.IO) {
        try {
            clientSocket = Socket(ipAddress, PORT)
            handleIncomingConnection(clientSocket!!)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private suspend fun handleIncomingConnection(socket: Socket) = withContext(Dispatchers.IO) {
        val inputStream: InputStream = socket.getInputStream()
        try {
            while (true) {
                // parseDelimitedFrom is used for continuous stream of protobufs
                val packet = TransceiverPacket.parseDelimitedFrom(inputStream) ?: break
                _incomingPackets.emit(packet)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    suspend fun sendPacket(packet: TransceiverPacket) = withContext(Dispatchers.IO) {
        try {
            val outputStream: OutputStream? = clientSocket?.getOutputStream()
            outputStream?.let {
                packet.writeDelimitedTo(it)
                it.flush()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun stop() {
        serverSocket?.close()
        clientSocket?.close()
    }
}
