import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../controllers/peer_controller.dart';
import '../../network/wifi_mesh_manager.dart';

class PeerDiscoveryScreen extends StatefulWidget {
  const PeerDiscoveryScreen({super.key});

  @override
  State<PeerDiscoveryScreen> createState() => _PeerDiscoveryScreenState();
}

class _PeerDiscoveryScreenState extends State<PeerDiscoveryScreen> {
  final TextEditingController _customIpController = TextEditingController();
  final TextEditingController _customPortController = TextEditingController(text: '8888');
  int _selectedTransportMode = 0; // 0 = Wi-Fi Direct P2P, 1 = Wi-Fi Mesh / Hotspot, 2 = BLE Fallback

  @override
  void initState() {
    super.initState();
    // Default to Wi-Fi Mesh / LAN on Windows, Desktop, or non-Android devices
    if (!kIsWeb && !Platform.isAndroid) {
      _selectedTransportMode = 1;
    }
  }

  @override
  void dispose() {
    _customIpController.dispose();
    _customPortController.dispose();
    super.dispose();
  }

  void _showPortTestDialog(BuildContext context, PeerController controller) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Testing Transceiver Radio Port...', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );

    final res = await controller.testRadioPort();

    if (context.mounted) {
      Navigator.pop(context);
      final bool ok = res['success'] as bool? ?? false;
      final int port = res['port'] as int? ?? controller.activePort;
      final int latency = res['latencyMs'] as int? ?? 0;
      final String msg = res['message'] as String? ?? '';

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.error_rounded,
                color: ok ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(ok ? 'Radio Port $port Healthy' : 'Port $port Blocked'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ok
                    ? 'ELI-5: Your local Transceiver Radio is open, listening, and ready! Other devices on your Wi-Fi or Hotspot can connect to port $port to send and receive voice.'
                    : 'ELI-5: Could not connect to port $port. Another program may be using it or a firewall is blocking connections.',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (ok ? Colors.green : Colors.red).withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (ok ? Colors.green : Colors.red).withAlpha(60)),
                ),
                child: Text(
                  ok
                      ? '⚡ Loopback Ping: $latency ms\n📡 Status: Server Active on 0.0.0.0:$port\n📻 Beacon Broadcast: Port ${WifiMeshManager.beaconPort}'
                      : '⚠️ Diagnostics: $msg',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ),
          actions: [
            if (!ok)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showChangePortDialog(context, controller);
                },
                child: const Text('Try Alternative Port'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _showBleLoopbackTestDialog(BuildContext context, PeerController controller) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Testing BLE 180B Chunking Loopback...', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );

    final res = await controller.testBleLoopback();
    if (context.mounted) {
      Navigator.pop(context);
      final ok = res['success'] as bool? ?? false;
      final msg = res['message'] as String? ?? '';
      final chunks = res['chunks'] as int? ?? 0;
      final bytes = res['bytes'] as int? ?? 0;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.error_rounded,
                color: ok ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(ok ? 'BLE Pipeline Verified' : 'BLE Test Failed'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ok
                    ? 'ELI-5: Successfully chunked a payload into $chunks chunks ($bytes bytes with 4-byte sequencing headers), transmitted through the reassembly engine, and verified 100% payload integrity!'
                    : 'Diagnostic failure: $msg',
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (ok ? Colors.green : Colors.red).withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: (ok ? Colors.green : Colors.red).withAlpha(60)),
                ),
                child: Text(
                  '⚡ Chunks: $chunks\n📦 Total Bytes: $bytes\n⏱️ Result: $msg',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _showChangePortDialog(BuildContext context, PeerController controller) {
    final textCtrl = TextEditingController(text: controller.activePort.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Transceiver Port'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ELI-5: If port 8888 is busy on this device, switch to another port. Both devices must use the same port to talk.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: textCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Common Alternative Ports:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [8888, 8887, 8886, 8890].map((p) {
                return ActionChip(
                  label: Text('$p'),
                  onPressed: () => textCtrl.text = p.toString(),
                );
              }).toList(),
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
              final newPort = int.tryParse(textCtrl.text.trim());
              if (newPort != null && newPort > 1024 && newPort < 65535) {
                Navigator.pop(ctx);
                await controller.changePort(newPort);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Transceiver re-bound to Port $newPort'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            child: const Text('Apply Port'),
          ),
        ],
      ),
    );
  }

  void _showManualConnectDialog(BuildContext context, PeerController controller) {
    final localIp = controller.localIp;
    if (localIp != null && localIp.contains('.')) {
      final prefix = localIp.substring(0, localIp.lastIndexOf('.') + 1);
      _customIpController.text = prefix;
    } else {
      _customIpController.text = '192.168.1.';
    }
    _customPortController.text = controller.activePort.toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect to Peer Node'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ELI-5: Type the IP address of the other phone or computer on your Wi-Fi:',
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
            const SizedBox(height: 10),
            const Text('Quick Presets:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                if (controller.hotspotHostIp != null)
                  ActionChip(
                    label: Text('Hotspot Host (${controller.hotspotHostIp})'),
                    onPressed: () => _customIpController.text = controller.hotspotHostIp!,
                  ),
                ActionChip(
                  label: const Text('Local Loopback (127.0.0.1)'),
                  onPressed: () => _customIpController.text = '127.0.0.1',
                ),
              ],
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
              final port = int.tryParse(_customPortController.text.trim()) ?? controller.activePort;
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
              } else if (_selectedTransportMode == 1) {
                controller.refreshNetwork();
              } else {
                controller.startBleScanning();
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
                  label: Text('Wi-Fi Direct'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.hub_rounded),
                  label: Text('Wi-Fi Mesh / LAN'),
                ),
                ButtonSegment(
                  value: 2,
                  icon: Icon(Icons.bluetooth_audio_rounded),
                  label: Text('BLE Fallback'),
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
              if (!controller.isP2pSupported) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade700.withAlpha(120)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.amber.shade800),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ELI-5: Wi-Fi Direct P2P is an Android hardware protocol. On Windows/Desktop, please switch to "Wi-Fi Mesh / LAN" above to connect over Wi-Fi or Mobile Hotspot.',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              ElevatedButton.icon(
                onPressed: controller.isP2pSupported ? () => controller.startP2pDiscovery() : null,
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
            ] else if (_selectedTransportMode == 1) ...[
              // ==========================================
              // WI-FI MESH / HOTSPOT (LAN Transport)
              // ==========================================

              // ELI-5 Transceiver Radio & Port Diagnostics Card
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
                                'Transceiver Radio & Wi-Fi',
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
                                  : 'PORT ${controller.activePort} READY',
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

                      // ELI-5 Status Badges
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Chip(
                            avatar: const Icon(Icons.radio_rounded, size: 16, color: Colors.green),
                            label: Text(
                              'Port: ${controller.activePort} (Open)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          Chip(
                            avatar: Icon(
                              controller.isHotspotHost
                                  ? Icons.wifi_tethering_rounded
                                  : (controller.isHotspotClient ? Icons.phone_android_rounded : Icons.wifi_rounded),
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            label: Text(
                              controller.isHotspotHost
                                  ? 'Mobile Hotspot Host (${controller.localIp ?? "Active"})'
                                  : (controller.isHotspotClient
                                      ? 'Hotspot Client (${controller.localIp ?? "Active"})'
                                      : 'Wi-Fi LAN (${controller.localIp ?? "Searching..."})'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // ELI-5 Explanatory Box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withAlpha(160),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(100)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('💡', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                controller.isHotspotClient
                                    ? 'ELI-5: You are connected to a Phone Hotspot! Tap "Connect to Hotspot Host" below to instantly link radios with the phone broadcasting the hotspot (${controller.hotspotHostIp ?? ".1"}).'
                                    : (controller.isHotspotHost
                                        ? 'ELI-5: You are the Hotspot Host! Other phones should connect to your hotspot Wi-Fi. Their radios will link directly to Port ${controller.activePort}.'
                                        : 'ELI-5: Make sure both devices are on the same Wi-Fi router or one phone hosts a hotspot. Radios talk directly over TCP Port ${controller.activePort}.'),
                                style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Diagnostic Action Buttons
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _showPortTestDialog(context, controller),
                            icon: const Icon(Icons.speed_rounded, size: 16),
                            label: const Text('TEST RADIO PORT'),
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                          if (controller.isHotspotClient && controller.hotspotHostIp != null)
                            FilledButton.icon(
                              onPressed: () async {
                                final ok = await controller.quickConnectHotspotHost();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok
                                            ? 'Linked successfully to Hotspot Host (${controller.hotspotHostIp})!'
                                            : 'Could not reach Hotspot Host on port ${controller.activePort}',
                                      ),
                                      backgroundColor: ok ? Colors.green : Colors.red,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.flash_on_rounded, size: 16),
                              label: const Text('CONNECT TO HOTSPOT HOST'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          TextButton.icon(
                            onPressed: () => _showChangePortDialog(context, controller),
                            icon: const Icon(Icons.tune_rounded, size: 16),
                            label: const Text('CHANGE PORT'),
                            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      Text(
                        'Node ID: ${controller.deviceId} • Radio Port: ${controller.activePort} • Beacon: ${WifiMeshManager.beaconPort}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Controls: Auto-Connect Toggle
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
                            'Automatically pair when nodes are detected on Wi-Fi',
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

              // Action Buttons: Sweep Subnet + Custom IP + Gateway
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
                      label: Text(controller.isScanning ? 'SWEEPING...' : 'SWEEP WI-FI SUBNET'),
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
                    tooltip: 'Connect to Host AP or Gateway (.1)',
                    icon: const Icon(Icons.router_rounded),
                    onPressed: () async {
                      final ok = await controller.connectToGateway();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Connected to Base / Host AP successfully!'
                                  : 'Could not reach Gateway host on port ${controller.activePort}',
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
          ] else ...[
              // ==========================================
              // BLUETOOTH LOW ENERGY (BLE Fallback Radio)
              // ==========================================

              // BLE Radio Diagnostics & Status Card
              Card(
                color: controller.isBleConnected
                    ? const Color(0xFF1B5E20).withAlpha(35)
                    : theme.colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: controller.isBleConnected
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
                                controller.isBleConnected
                                    ? Icons.bluetooth_connected_rounded
                                    : (controller.isBleScanning
                                        ? Icons.bluetooth_searching_rounded
                                        : (controller.isBleAdvertising
                                            ? Icons.bluetooth_audio_rounded
                                            : Icons.bluetooth_rounded)),
                                color: controller.isBleConnected
                                    ? Colors.green
                                    : theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'BLE Fallback Transport',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: controller.isBleConnected ? Colors.green.shade800 : null,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: controller.isBleConnected
                                  ? Colors.green
                                  : (controller.isBleAdvertising || controller.isBleScanning
                                      ? theme.colorScheme.primaryContainer
                                      : theme.colorScheme.surfaceContainerHigh),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              controller.isBleConnected
                                  ? 'LINK ESTABLISHED'
                                  : (controller.isBleAdvertising
                                      ? 'ADVERTISING (GATT)'
                                      : (controller.isBleScanning
                                          ? 'SCANNING'
                                          : 'STANDBY')),
                              style: TextStyle(
                                color: controller.isBleConnected
                                    ? Colors.white
                                    : (controller.isBleAdvertising || controller.isBleScanning
                                        ? theme.colorScheme.onPrimaryContainer
                                        : theme.colorScheme.onSurfaceVariant),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Badges / Metrics
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Chip(
                            avatar: Icon(
                              Icons.cell_tower_rounded,
                              size: 16,
                              color: controller.isBleAdvertising ? Colors.green : Colors.grey,
                            ),
                            label: Text(
                              'GATT Server: ${controller.isBleAdvertising ? "Broadcasting" : "Idle"}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          Chip(
                            avatar: Icon(
                              Icons.radar_rounded,
                              size: 16,
                              color: controller.isBleScanning ? Colors.blue : Colors.grey,
                            ),
                            label: Text(
                              'Scanner: ${controller.isBleScanning ? "Active" : "Idle"}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          Chip(
                            avatar: const Icon(Icons.swap_horiz_rounded, size: 16, color: Colors.teal),
                            label: Text(
                              'Packets: Tx ${controller.blePacketsSent} / Rx ${controller.blePacketsReceived}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          Chip(
                            avatar: const Icon(Icons.grain_rounded, size: 16, color: Colors.indigo),
                            label: Text(
                              '180B Chunks: Tx ${controller.bleChunksSent} / Rx ${controller.bleChunksReceived}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Explanatory Info Box
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withAlpha(160),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: theme.colorScheme.outlineVariant.withAlpha(100)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('💡', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'ELI-5: BLE is your disaster fallback! When Wi-Fi routers and LANs are completely unavailable or down, '
                                'iTantra slices voice and text packets into 180-byte chunks and transmits them directly over native Bluetooth Low Energy radio.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (controller.isBleConnected) ...[
                        const Divider(height: 24),
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Connected to: ${controller.bleConnectedPeerName ?? "Unknown Peer"}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  if (controller.bleConnectedPeerAddress != null)
                                    Text(
                                      'Address: ${controller.bleConnectedPeerAddress}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontFamily: 'monospace',
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => controller.disconnectBle(),
                              icon: const Icon(Icons.link_off_rounded, color: Colors.red, size: 18),
                              label: const Text('DISCONNECT', style: TextStyle(color: Colors.red, fontSize: 12)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (!controller.isBleSupported) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade700.withAlpha(120)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.amber.shade800),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ELI-5: Native Bluetooth GATT Server/Client runs on Android mobile hardware. On Windows/Desktop, you can test the 180-byte chunk fragmentation & reassembly pipeline using "TEST LOOPBACK" or "SIMULATE PEER" below!',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // BLE Action Control Buttons
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      if (controller.isBleAdvertising) {
                        controller.stopBleAdvertising();
                      } else {
                        controller.startBleAdvertising();
                      }
                    },
                    icon: Icon(
                      controller.isBleAdvertising ? Icons.stop_rounded : Icons.cell_tower_rounded,
                      color: controller.isBleAdvertising ? Colors.red : null,
                    ),
                    label: Text(controller.isBleAdvertising ? 'Stop Advertising' : 'Advertise (GATT Server)'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (controller.isBleScanning) {
                        controller.stopBleScanning();
                      } else {
                        controller.startBleScanning();
                      }
                    },
                    icon: Icon(
                      controller.isBleScanning ? Icons.stop_rounded : Icons.search_rounded,
                      color: controller.isBleScanning ? Colors.red : null,
                    ),
                    label: Text(controller.isBleScanning ? 'Stop Scan' : 'Scan for Peers'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showBleLoopbackTestDialog(context, controller),
                    icon: const Icon(Icons.sync_alt_rounded),
                    label: const Text('Test Loopback (180B Chunking)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      controller.simulateBlePeer();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Simulated BLE peer connected and ready for field testing.'),
                          backgroundColor: Colors.teal,
                        ),
                      );
                    },
                    icon: const Icon(Icons.developer_board_rounded),
                    label: const Text('Simulate Peer'),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Discovered Peers Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Discovered BLE Devices (${controller.bleDiscoveredPeers.length})',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    controller.isBleScanning ? 'Scanning...' : (controller.isBleAdvertising ? 'Broadcasting' : 'Idle'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: controller.isBleScanning || controller.isBleAdvertising ? Colors.green : theme.colorScheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (controller.bleDiscoveredPeers.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.bluetooth_searching_rounded,
                        size: 48,
                        color: theme.colorScheme.primary.withAlpha(160),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No BLE iTantra nodes detected nearby.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• To link two phones: Have one phone tap "Advertise (GATT Server)" and the second phone tap "Scan for Peers".\n'
                        '• Devices will negotiate 180-byte MTU chunking and establish a direct low-energy transceiver link.\n'
                        '• You can also tap "Simulate Peer" to test sending and receiving audio over BLE immediately.',
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
                  itemCount: controller.bleDiscoveredPeers.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final peer = controller.bleDiscoveredPeers[index];
                    final isPeerConnected = controller.isBleConnected && controller.bleConnectedPeerAddress == peer.address;

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
                            Icons.bluetooth_audio_rounded,
                            color: isPeerConnected ? Colors.green : theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          peer.name,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${peer.address} • RSSI: ${peer.rssi} dBm (${peer.signalBars}/4 bars)',
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
                                onPressed: () => controller.connectBlePeer(peer.address, peer.name),
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
