import 'dart:async';
import 'dart:io';
import 'package:mdns_dart/mdns_dart.dart';
import '../../models/discovered_server.dart';

class MdnsDiscovery {
  static const String _serviceType = '_cliff._tcp';
  static final MdnsDiscovery _instance = MdnsDiscovery._internal();
  factory MdnsDiscovery() => _instance;
  MdnsDiscovery._internal();

  MDNSServer? _server;
  Timer? _pollTimer;
  StreamSubscription? _subscription;
  final _discovered = <DiscoveredServer>[];
  final _streamCtrl = StreamController<DiscoveredServer>.broadcast();

  Stream<DiscoveredServer> get discoveredStream => _streamCtrl.stream;
  List<DiscoveredServer> get discoveredServers => List.unmodifiable(_discovered);

  Future<void> registerService(String serverId, String name, int port) async {
    await unregisterService();

    final ips = await _getLocalIPs();
    if (ips.isEmpty) return;

    final service = await MDNSService.create(
      instance: name,
      service: _serviceType,
      domain: 'local.',
      port: port,
      ips: ips,
      txt: MDNSService.createTXTRecords({'serverId': serverId}),
    );

    _server = MDNSServer(MDNSServerConfig(
      zone: service,
    ));
    await _server!.start();
  }

  Future<void> unregisterService() async {
    await _server?.stop();
    _server = null;
  }

  Future<void> startListening() async {
    _discovered.clear();
    _pollSubscription();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollSubscription());
  }

  Future<void> _pollSubscription() async {
    await _subscription?.cancel();

    final params = QueryParams(
      service: _serviceType,
      domain: 'local.',
      timeout: const Duration(seconds: 5),
    );

    try {
    final stream = await MDNSClient.query(params);
    _subscription = stream.listen((entry) {
      if (entry.isComplete && entry.port > 0 && entry.primaryAddress != null) {
        final serverId = _extractServerId(entry);
        if (serverId == null) return;

        if (!_discovered.any((s) => s.id == serverId)) {
          final server = DiscoveredServer(
            id: serverId,
            name: '',
            host: entry.primaryAddress!.address,
            port: entry.port,
            discoveredAt: DateTime.now(),
          );
          _discovered.add(server);
          _streamCtrl.add(server);
        }
      }
    });
    } catch (e) {
      // Ignore
    }
  }

  Future<void> stopListening() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _discovered.clear();
  }

  void dispose() {
    stopListening();
    unregisterService();
    _streamCtrl.close();
  }

  Future<List<InternetAddress>> _getLocalIPs() async {
    final interfaces = await NetworkInterface.list(
      includeLinkLocal: false,
      includeLoopback: false,
    );
    final ips = <InternetAddress>[];
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          ips.add(addr);
        }
      }
    }
    return ips;
  }

  String? _extractServerId(ServiceEntry entry) {
    final map = MDNSService.parseTXTRecords(entry.infoFields);
    return map['serverId'];
  }
}