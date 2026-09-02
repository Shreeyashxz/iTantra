import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../controllers/peer_controller.dart';
import '../../network/hotspot_network_manager.dart';

class PeerDiscoveryScreen extends StatefulWidget {
  const PeerDiscoveryScreen({super.key});

  @override
  State<PeerDiscoveryScreen> createState() => _PeerDiscoveryScreenState();
}

class _PeerDiscoveryScreenState extends State<PeerDiscoveryScreen> {
  final TextEditingController _customIpController = TextEditingController();

  @override
  void dispose() {
    _customIpController.dispose();
    super.dispose();
  }

  void _showManualConnectDialog(BuildContext context, PeerController controller) {
    final localIp = controller.localIp;
    if (localIp != null && localIp.contains('.')) {
      final prefix = localIp.substring(0, localIp.lastIndexOf('.') + 1);
      _customIpController.text = prefix;
    } else {
      _customIpController.text = '192.168.';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect to IP Address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the Wi-Fi IP of the peer node (Listening on Port 8888):',
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
              if (ip.isNotEmpty) {
                Navigator.pop(ctx);
                final success = await controller.connectToHotspotIp(ip);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? 'Connected successfully to $ip:8888'
                            : 'Failed to reach $ip on port 8888',
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

    final isConnected = controller.connectionStatus.toLowerCase().contains('connect') &&
        !controller.connectionStatus.toLowerCase().contains('failed') &&
        !controller.connectionStatus.toLowerCase().contains('disconnect');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Mesh & Peer Discovery'),
        actions: [
          IconButton(
            tooltip: 'Refresh Local Network IP',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => controller.refreshLocalIp(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Network Mode Segmented Button
            SegmentedButton<PeerNetworkMode>(
              segments: const [
                ButtonSegment(
                  value: PeerNetworkMode.wifiHotspot,
                  icon: Icon(Icons.wifi_rounded),
                  label: Text('Wi-Fi LAN / Hotspot'),
                ),
                ButtonSegment(
                  value: PeerNetworkMode.wifiDirect,
                  icon: Icon(Icons.perm_scan_wifi_rounded),
                  label: Text('Wi-Fi Direct P2P'),
                ),
              ],
              selected: {controller.networkMode},
              onSelectionChanged: (selected) {
                controller.setNetworkMode(selected.first);
              },
            ),
            const SizedBox(height: 16),

            // Connection Status & Device IP Card
            Card(
              color: isConnected
                  ? const Color(0xFF1B5E20).withAlpha(40)
                  : theme.colorScheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: isConnected ? Colors.green : theme.colorScheme.primary.withAlpha(50),
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
                                  ? Icons.check_circle_rounded
                                  : (controller.networkMode == PeerNetworkMode.wifiHotspot
                                      ? Icons.wifi_rounded
                                      : Icons.radar_rounded),
                              color: isConnected
                                  ? Colors.green
                                  : theme.colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              controller.networkMode == PeerNetworkMode.wifiHotspot
                                  ? 'Local Wi-Fi Mesh'
                                  : 'Wi-Fi Direct Link',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: isConnected
                                    ? Colors.green.shade800
                                    : theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isConnected
                                ? Colors.green
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isConnected ? 'ONLINE' : 'STANDBY',
                            style: TextStyle(
                              color: isConnected ? Colors.white : theme.colorScheme.onSurfaceVariant,
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
                    const SizedBox(height: 6),
                    if (controller.localIp != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Device IP: ${controller.localIp} (Port 8888)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            tooltip: 'Copy IP',
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
                    ] else ...[
                      Text(
                        'Device IP: Detecting local network...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    Text(
                      'Node ID: ${controller.deviceId}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Mode-specific controls
            if (controller.networkMode == PeerNetworkMode.wifiHotspot) ...[
              _buildHotspotControls(context, theme, controller),
            ] else ...[
              _buildWifiDirectControls(context, theme, controller),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHotspotControls(
    BuildContext context,
    ThemeData theme,
    PeerController controller,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Quick Action Row: Connect by Custom IP + Gateway Quick Connect
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _showManualConnectDialog(context, controller),
                icon: const Icon(Icons.link_rounded, size: 20),
                label: const Text('CONNECT BY IP'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await controller.connectToHotspotHost();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? 'Connected to Gateway Host'
                            : 'Could not reach Gateway Host on port 8888',
                      ),
                      backgroundColor: ok ? Colors.green : Colors.red,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.router_rounded, size: 18),
              label: const Text('GATEWAY / AP'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Auto-Beacon and Subnet Scan Controls
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => controller.toggleHotspotBeacon(),
                icon: Icon(
                  controller.isHotspotBroadcasting
                      ? Icons.sensors_rounded
                      : Icons.sensors_off_rounded,
                  color: controller.isHotspotBroadcasting ? Colors.green : null,
                ),
                label: Text(
                  controller.isHotspotBroadcasting
                      ? 'BEACON: BROADCASTING'
                      : 'ENABLE BEACON',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: controller.isHotspotScanning
                    ? null
                    : () => controller.scanHotspotSubnet(),
                icon: controller.isHotspotScanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.manage_search_rounded),
                label: Text(
                  controller.isHotspotScanning ? 'PROBING...' : 'PROBE SUBNET',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Section header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Discovered Wi-Fi Nodes (${controller.hotspotPeers.length})',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (controller.hotspotPeers.isNotEmpty)
              Text(
                'Auto-discovered via UDP:8889',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (controller.hotspotPeers.isEmpty) ...[
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
                  size: 44,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                ),
                const SizedBox(height: 12),
                Text(
                  'No other iTantra devices detected on this Wi-Fi.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• Ensure both devices are connected to the same Wi-Fi router or Mobile Hotspot.\n'
                  '• UDP Beacons broadcast automatically in the background.\n'
                  '• If your router restricts broadcasts, tap "PROBE SUBNET" or enter the IP directly with "CONNECT BY IP".',
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
            itemCount: controller.hotspotPeers.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final peer = controller.hotspotPeers[index];
              return _buildHotspotPeerCard(context, theme, controller, peer);
            },
          ),
        ],
      ],
    );
  }

  Widget _buildHotspotPeerCard(
    BuildContext context,
    ThemeData theme,
    PeerController controller,
    HotspotPeer peer,
  ) {
    final secondsAgo = DateTime.now().difference(peer.lastSeen).inSeconds;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: peer.isHost
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.secondaryContainer,
          child: Icon(
            peer.isHost ? Icons.router_rounded : Icons.phone_android_rounded,
            color: peer.isHost
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(
          peer.name,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${peer.ipAddress}:${peer.port} • Seen ${secondsAgo}s ago',
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: ElevatedButton(
          onPressed: () async {
            final ok = await controller.connectToHotspotIp(peer.ipAddress);
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
  }

  Widget _buildWifiDirectControls(
    BuildContext context,
    ThemeData theme,
    PeerController controller,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: controller.isDiscovering ? null : () => controller.startDiscovery(),
          icon: const Icon(Icons.radar_rounded),
          label: Text(
            controller.isDiscovering
                ? 'SCANNING WI-FI DIRECT GROUP...'
                : 'SCAN WI-FI DIRECT P2P SUBNET',
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'Active Wi-Fi Direct Peers (${controller.peers.length})',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        if (controller.peers.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'No active Wi-Fi Direct P2P peers found.\n\nTip: For instant cross-device connectivity across phones and PCs, use the "Wi-Fi LAN / Hotspot" mode.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: controller.peers.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final peer = controller.peers[index];
              final isConnected = peer.status == 0;

              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isConnected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isConnected
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      isConnected ? Icons.wifi_tethering_rounded : Icons.device_hub_rounded,
                      color: isConnected
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  title: Text(
                    peer.deviceName,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'IP: ${peer.deviceAddress} • ${isConnected ? "Connected" : "Available"}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: ElevatedButton(
                    onPressed: isConnected ? null : () => controller.connectToPeer(peer),
                    child: Text(isConnected ? 'Linked' : 'Connect'),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
