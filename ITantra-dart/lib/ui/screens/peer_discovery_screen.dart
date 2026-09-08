import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../controllers/peer_controller.dart';

class PeerDiscoveryScreen extends StatefulWidget {
  const PeerDiscoveryScreen({super.key});

  @override
  State<PeerDiscoveryScreen> createState() => _PeerDiscoveryScreenState();
}

class _PeerDiscoveryScreenState extends State<PeerDiscoveryScreen> {
  final TextEditingController _customIpController = TextEditingController();
  final TextEditingController _customPortController = TextEditingController(text: '8888');
  int _selectedTransportMode = 0; // 0 = Wi-Fi Direct P2P, 1 = Wi-Fi Mesh / Hotspot

  @override
  void dispose() {
    _customIpController.dispose();
    _customPortController.dispose();
    super.dispose();
  }

  void _showManualConnectDialog(BuildContext context, PeerController controller) {
    final localIp = controller.localIp;
    if (localIp != null && localIp.contains('.')) {
      final prefix = localIp.substring(0, localIp.lastIndexOf('.') + 1);
      _customIpController.text = prefix;
    } else {
      _customIpController.text = '192.168.1.';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect to Peer Node'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the IPv4 address of the target iTantra device:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customIpController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'IP Address',
                hintText: '192.168.1.100',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lan_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customPortController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final ip = _customIpController.text.trim();
              final port = int.tryParse(_customPortController.text.trim()) ?? 8888;
              if (ip.isNotEmpty) {
                Navigator.pop(ctx);
                final success = await controller.connectToPeer(ip, port: port);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? 'Linked successfully to $ip:$port'
                            : 'Could not reach $ip on port $port',
                      ),
                      backgroundColor: success ? Colors.green : Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<PeerController>();

    final isConnected = controller.connectedCount > 0 || controller.p2pConnection.groupFormed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peer Discovery & Radio Links'),
        actions: [
          IconButton(
            tooltip: 'Refresh Network Interfaces',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              if (_selectedTransportMode == 0) {
                controller.startP2pDiscovery();
              } else {
                controller.refreshNetwork();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Transport Mode Selector
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.devices_rounded),
                  label: Text('Wi-Fi Direct P2P'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.hub_rounded),
                  label: Text('Wi-Fi Mesh / LAN'),
                ),
              ],
              selected: {_selectedTransportMode},
              onSelectionChanged: (set) => setState(() => _selectedTransportMode = set.first),
            ),
            const SizedBox(height: 16),

            if (_selectedTransportMode == 0) ...[
              // ==========================================
              // WI-FI DIRECT (P2P Native Device-to-Device)
              // ==========================================
              Card(
                color: controller.p2pConnection.groupFormed
                    ? const Color(0xFF1B5E20).withAlpha(35)
                    : theme.colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: controller.p2pConnection.groupFormed
                        ? Colors.green
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                controller.p2pConnection.groupFormed
                                    ? Icons.wifi_protected_setup_rounded
                                    : Icons.perm_scan_wifi_rounded,
                                color: controller.p2pConnection.groupFormed
                                    ? Colors.green
                                    : theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Wi-Fi Direct (P2P Field Radio)',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Chip(
                            label: Text(
                              controller.p2pConnection.groupFormed
                                  ? 'LINK ESTABLISHED'
                                  : (controller.isP2pDiscovering ? 'SCANNING' : 'STANDBY'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: controller.p2pConnection.groupFormed
                                    ? Colors.green
                                    : theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Direct routerless link: Connect two Android devices directly in disaster or offline field zones with zero network infrastructure.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (controller.p2pConnection.groupFormed) ...[
                        const Divider(height: 20),
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                controller.p2pConnection.isGroupOwner
                                    ? 'Group Owner (Host) • Transceiver Server Active on Port 8888'
                                    : 'Client Linked to Host: ${controller.p2pConnection.groupOwnerAddress}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            TextButton(
                              onPressed: () => controller.disconnectP2p(),
                              child: const Text('DISCONNECT', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              ElevatedButton.icon(
                onPressed: () => controller.startP2pDiscovery(),
                icon: const Icon(Icons.radar_rounded),
                label: const Text('SCAN FOR NEARBY P2P DEVICES'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Discovered P2P Devices (${controller.p2pPeers.length})',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              if (controller.p2pPeers.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.wifi_find_rounded, size: 40, color: theme.colorScheme.outline),
                          const SizedBox(height: 8),
                          Text(
                            controller.isP2pDiscovering
                                ? 'Scanning for nearby Wi-Fi Direct radios...'
                                : 'No P2P devices discovered yet.\nTap "Scan For Nearby P2P Devices" above.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: controller.p2pPeers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final peer = controller.p2pPeers[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(Icons.phone_android_rounded, color: theme.colorScheme.primary),
                        ),
                        title: Text(peer.deviceName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${peer.deviceAddress} • ${peer.statusLabel}'),
                        trailing: ElevatedButton(
                          onPressed: () => controller.connectP2p(peer.deviceAddress),
                          child: const Text('Connect'),
                        ),
                      ),
                    );
                  },
                ),
            ] else ...[
              // ==========================================
              // WI-FI MESH / HOTSPOT (LAN Transport)
              // ==========================================
            Card(
              color: isConnected
                  ? const Color(0xFF1B5E20).withAlpha(35)
                  : theme.colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isConnected ? Colors.green : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isConnected
                                  ? Icons.hub_rounded
                                  : Icons.sensors_rounded,
                              color: isConnected ? Colors.green : theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'iTantra Transceiver Mesh',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isConnected ? Colors.green.shade800 : null,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isConnected ? Colors.green : theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isConnected
                                ? '${controller.connectedCount} LINKED'
                                : 'STANDBY',
                            style: TextStyle(
                              color: isConnected ? Colors.white : theme.colorScheme.onPrimaryContainer,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Status: ${controller.connectionStatus}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Active Interfaces List
                    if (controller.interfaces.isNotEmpty) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: controller.interfaces.map((iface) {
                          return Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: Icon(
                              iface.isHotspot
                                  ? Icons.wifi_tethering_rounded
                                  : (iface.isP2P ? Icons.devices_rounded : Icons.wifi_rounded),
                              size: 16,
                            ),
                            label: Text(
                              '${iface.name}: ${iface.ipAddress} (${iface.typeLabel})',
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            ),
                          );
                        }).toList(),
                      ),
                    ] else ...[
                      Text(
                        'Scanning local network interfaces...',
                        style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                      ),
                    ],

                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Node ID: ${controller.deviceId} • Port: 8888 • Beacon: 8889',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (controller.localIp != null)
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            tooltip: 'Copy Primary IP',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: controller.localIp!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Copied ${controller.localIp} to clipboard'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Controls: Auto-Connect Toggle & Beacon Status
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mesh Auto-Connect',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Automatically pair when nodes are detected',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: controller.autoConnect,
                      onChanged: (val) => controller.toggleAutoConnect(val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Action Buttons: Probe Subnet + Connect by IP + Gateway
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: controller.isScanning ? null : () => controller.probeSubnet(),
                    icon: controller.isScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.radar_rounded),
                    label: Text(controller.isScanning ? 'SWEEPING...' : 'SWEEP SUBNET'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _showManualConnectDialog(context, controller),
                  icon: const Icon(Icons.link_rounded, size: 20),
                  label: const Text('CUSTOM IP'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Connect to Wi-Fi Gateway / Host AP (.1)',
                  icon: const Icon(Icons.router_rounded),
                  onPressed: () async {
                    final ok = await controller.connectToGateway();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Connected to Gateway / Base Station'
                                : 'Could not reach Gateway host on port 8888',
                          ),
                          backgroundColor: ok ? Colors.green : Colors.red,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Connected Peers Telemetry Section
            if (controller.connectedCount > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Active Mesh Links (${controller.connectedCount})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                  const Text(
                    'Ready for Push-To-Talk',
                    style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: controller.connectedIps.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final ip = controller.connectedIps[index];
                  final stats = controller.linkStats.where((s) => s.ipAddress == ip).firstOrNull;

                  return Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Colors.green, width: 1.5),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFF1B5E20),
                            child: Icon(Icons.wifi_tethering_rounded, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Linked Peer: $ip',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withAlpha(40),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        stats != null && stats.rttMs > 0
                                            ? '⚡ ${stats.rttMs} ms'
                                            : '⚡ Active',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      stats != null
                                          ? 'Sent: ${stats.packetsSent} • Recv: ${stats.packetsReceived}'
                                          : 'Link active',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => controller.disconnectPeer(ip),
                            child: const Text('Unlink'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],

            // Discovered Nodes Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Discovered Nearby Nodes (${controller.peers.length})',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  controller.isBeaconing ? 'Beaconing (UDP+Multicast)' : 'Beacon Inactive',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: controller.isBeaconing ? Colors.green : theme.colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (controller.peers.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.wifi_find_rounded,
                      size: 48,
                      color: theme.colorScheme.primary.withAlpha(160),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No other iTantra devices detected on this network.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Connect devices to the same Wi-Fi router, Mobile Hotspot, or Wi-Fi Direct group.\n'
                      '• Presence beacons broadcast automatically via UDP and Multicast.\n'
                      '• Tap "SWEEP SUBNET" for an immediate network probe, or connect manually via "CUSTOM IP".',
                      textAlign: TextAlign.start,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: controller.peers.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final peer = controller.peers[index];
                  final isPeerConnected = controller.connectedIps.contains(peer.ipAddress);
                  final secondsAgo = DateTime.now().difference(peer.lastSeen).inSeconds;

                  return Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isPeerConnected ? Colors.green : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isPeerConnected
                            ? Colors.green.withAlpha(40)
                            : theme.colorScheme.primaryContainer,
                        child: Icon(
                          peer.isHost ? Icons.router_rounded : Icons.phone_android_rounded,
                          color: isPeerConnected ? Colors.green : theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        peer.name,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${peer.ipAddress}:${peer.port} • ${peer.networkType} • Seen ${secondsAgo}s ago',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: isPeerConnected
                          ? const Chip(
                              label: Text('LINKED', style: TextStyle(fontSize: 10, color: Colors.green)),
                              visualDensity: VisualDensity.compact,
                              side: BorderSide(color: Colors.green),
                            )
                          : ElevatedButton(
                              onPressed: () async {
                                final ok = await controller.connectToPeer(peer.ipAddress, port: peer.port);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok ? 'Connected to ${peer.name}' : 'Connection failed to ${peer.ipAddress}'),
                                      backgroundColor: ok ? Colors.green : Colors.red,
                                    ),
                                  );
                                }
                              },
                              child: const Text('Connect'),
                            ),
                    ),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    ),
  );
}
}
