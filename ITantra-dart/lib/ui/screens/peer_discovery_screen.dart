import 'package:flutter/material.dart';
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
    _customIpController.text = '192.168.43.';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect to IP Address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the Hotspot IP or local network IP of the peer node (Port 8888):',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customIpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'IP Address',
                hintText: '192.168.43.1',
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
                            ? 'Connected successfully to $ip'
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh & Peer Discovery'),
        actions: [
          IconButton(
            tooltip: 'Refresh Local IP',
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
                  icon: Icon(Icons.wifi_tethering_rounded),
                  label: Text('Wi-Fi Hotspot / Mesh'),
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

            // Connection Status Card
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          controller.networkMode == PeerNetworkMode.wifiHotspot
                              ? Icons.wifi_tethering_rounded
                              : Icons.radar_rounded,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          controller.networkMode == PeerNetworkMode.wifiHotspot
                              ? 'Hotspot Mesh Link'
                              : 'Wi-Fi Direct Link',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Status: ${controller.connectionStatus}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (controller.localIp != null) ...[
                      Text(
                        'Device IP: ${controller.localIp} (Port 8888)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer.withAlpha(200),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    Text(
                      'Node ID: ${controller.deviceId}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer.withAlpha(160),
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
        // Quick Action Row
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final ok = await controller.connectToHotspotHost();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Connected to Hotspot Host (Base Station)'
                              : 'Could not connect to Hotspot Host (192.168.43.1)',
                        ),
                        backgroundColor: ok ? Colors.green : Colors.red,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.router_rounded, size: 20),
                label: const Text('CONNECT TO HOST (AP)'),
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
              onPressed: () => _showManualConnectDialog(context, controller),
              icon: const Icon(Icons.edit_road_rounded, size: 18),
              label: const Text('CUSTOM IP'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Hotspot Beacon and Subnet Scan Controls
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => controller.toggleHotspotBeacon(),
                icon: Icon(
                  controller.isHotspotBroadcasting
                      ? Icons.sensors_off_rounded
                      : Icons.sensors_rounded,
                  color: controller.isHotspotBroadcasting ? Colors.green : null,
                ),
                label: Text(
                  controller.isHotspotBroadcasting
                      ? 'BEACON ACTIVE (STOP)'
                      : 'BROADCAST BEACON',
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
              'Hotspot Mesh Nodes (${controller.hotspotPeers.length})',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (controller.hotspotPeers.isNotEmpty)
              Text(
                'Auto-discovered via UDP 8889',
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
                  Icons.wifi_tethering_off_rounded,
                  size: 40,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                ),
                const SizedBox(height: 12),
                Text(
                  'No hotspot peers discovered yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '1. Connect devices to the same Portable Wi-Fi Hotspot.\n'
                  '2. Tap "BROADCAST BEACON" or "CONNECT TO HOST (AP)".\n'
                  '3. Or probe the subnet to discover passive nodes.',
                  textAlign: TextAlign.center,
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
          '${peer.ipAddress}:${peer.port} ${peer.isHost ? "• Base Station (AP)" : ""}',
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
                  content: Text(ok ? 'Connected to ${peer.name}' : 'Connection failed'),
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
                ? 'SCANNING LOCAL MESH...'
                : 'SCAN FOR NEARBY WI-FI DIRECT PEERS',
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'Discovered Wi-Fi Direct Peers (${controller.peers.length})',
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
                'No peers detected in local Wi-Fi Direct mesh.\nTap scan while another iTantra device is active.',
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
                    'MAC: ${peer.deviceAddress} • ${isConnected ? "Connected" : "Available"}',
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
